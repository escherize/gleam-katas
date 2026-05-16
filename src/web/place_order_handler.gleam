//// Kata 8 — HTTP boundary: the place-order handler
////
//// Read: docs/book/09_kata_http_boundary.md
//// Tests: test/web/place_order_handler_test.gleam
////
//// The handler is a translation layer:
////   1. Parse the URL's :id segment into an `OrderId`. On failure
////      (empty / invalid), return `wisp.bad_request("...")`.
////   2. Call `place_order.run(deps.order_repo, order_id)`.
////   3. Pattern-match the result. Translate every variant to an HTTP
////      response.
////
//// The compiler enforces exhaustiveness on the `case` — if you add a
//// PlaceOrderError variant later and forget the HTTP mapping, the
//// build breaks here, not in production.
////
//// Endpoint contract:
////   200 OK              { "order_id": "..." } (or richer; pick a JSON shape)
////   400 Bad Request     malformed order id
////   404 Not Found       order not in repo (RepoFailed(NotFound))
////   409 Conflict        already placed (DomainFailed(CannotModifyPlacedOrder))
////   422 Unprocessable   any other domain rule violation
////   500 Server Error    any other repo failure

import gleam/json
import order
import order_repo.{type OrderRepo}
import place_order
import wisp.{type Response}

pub fn run(repo: OrderRepo, raw_id: String) -> Response {
  case order.new_id(raw_id) {
    Error(_) -> wisp.bad_request("Invalid order ID")
    Ok(order_id) ->
      case place_order.run(repo, order_id) {
        Ok(_) -> {
          let body =
            [#("order_id", json.string(raw_id))]
            |> json.object
            |> json.to_string
          wisp.json_response(body, 200)
        }
        Error(place_order.RepoFailed(order_repo.NotFound)) -> wisp.not_found()
        Error(place_order.DomainFailed(order.CannotModifyPlacedOrder)) ->
          wisp.response(409)
        Error(place_order.DomainFailed(_)) -> wisp.unprocessable_content()
        Error(place_order.RepoFailed(order_repo.StorageError(_))) ->
          wisp.unprocessable_content()
      }
  }
}
