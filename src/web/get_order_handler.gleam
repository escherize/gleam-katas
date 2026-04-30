//// Kata 8 — HTTP boundary: GET /orders/:id
////
//// Returns the full order as JSON, or 400/404 on parse / lookup errors.
//// Same translation-only shape as place_order_handler — no business
//// logic in here.

import gleam/json
import order
import order_repo.{type OrderRepo}
import wisp.{type Response}

pub fn run(repo: OrderRepo, raw_id: String) -> Response {
  case order.new_id(raw_id) {
    Error(_) -> wisp.bad_request("Invalid order ID")
    Ok(order_id) ->
      case repo.find(order_id) {
        Error(order_repo.NotFound) -> wisp.not_found()
        Ok(o) ->
          o
          |> order.order_to_json
          |> json.to_string
          |> wisp.json_response(200)
      }
  }
}
