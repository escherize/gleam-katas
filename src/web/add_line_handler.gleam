//// HTTP handler: POST /orders/:id/lines
////
//// Query params (all required):
////   sku=WIDGET
////   quantity=2
////   amount=100        (in minor units — cents)
////   currency=USD      (USD | EUR | GBP)
////
//// Translation only — parse strings, build typed values, call the use
//// case, map each result variant to an HTTP response.

import add_line
import money
import order
import order_repo.{type OrderRepo}
import wisp.{type Response}

pub fn run(
  repo: OrderRepo,
  raw_id: String,
  sku: String,
  quantity: Int,
  amount: Int,
  raw_currency: String,
) -> Response {
  case order.new_id(raw_id), parse_currency(raw_currency) {
    Error(_), _ -> wisp.bad_request("invalid order id")
    _, Error(_) -> wisp.bad_request("currency must be USD | EUR | GBP")
    Ok(oid), Ok(currency) ->
      case money.new(amount, currency) {
        Error(_) -> wisp.bad_request("amount must be non-negative")
        Ok(unit_price) ->
          case add_line.run(repo, oid, sku, quantity, unit_price) {
            Ok(_) -> wisp.response(204)
            Error(add_line.RepoFailed(order_repo.NotFound)) -> wisp.not_found()
            Error(add_line.DomainFailed(order.CannotModifyPlacedOrder)) ->
              wisp.response(409)
            Error(add_line.DomainFailed(_)) -> wisp.unprocessable_content()
            Error(add_line.RepoFailed(order_repo.StorageError(_))) ->
              wisp.unprocessable_content()
          }
      }
  }
}

fn parse_currency(s: String) -> Result(money.Currency, Nil) {
  case s {
    "USD" -> Ok(money.USD)
    "EUR" -> Ok(money.EUR)
    "GBP" -> Ok(money.GBP)
    _ -> Error(Nil)
  }
}
