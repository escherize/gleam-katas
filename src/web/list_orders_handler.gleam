//// HTTP handler: GET /orders
////
//// Returns all orders in the repo as a JSON array.
//// 200 always (an empty repo returns []).
//// 500 if the repo errors (rare for in-memory; possible for SQLite).

import gleam/json
import order
import order_repo.{type OrderRepo}
import wisp.{type Response}

pub fn run(repo: OrderRepo) -> Response {
  case repo.list_all() {
    Error(_) -> wisp.internal_server_error()
    Ok(orders) ->
      orders
      |> json.array(order.order_to_json)
      |> json.to_string
      |> wisp.json_response(200)
  }
}
