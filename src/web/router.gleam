//// Kata 8 — HTTP boundary: the router
////
//// Read: docs/book/09_kata_http_boundary.md
//// Tests: test/web/place_order_handler_test.gleam (covers the only
////        route this router knows about)
////
//// The router does *one* thing: pattern-match path segments + method,
//// dispatch to the right handler with the deps closure, and return
//// `wisp.not_found()` for anything else. No business logic. No
//// validation. Just dispatch.
////
//// Use cases / handlers do the actual work. The router is the
//// switchboard.

import gleam/http
import gleam/json
import order
import order_repo.{type OrderRepo}
import web/place_order_handler
import wisp.{type Request, type Response}

/// The application's dependencies, constructed once in main.gleam and
/// passed through the router into each handler.
///
/// Add fields here as the app grows (event_bus, customer_repo, clock,
/// secret keys for tokens, etc.). The router takes the whole bag and
/// hands relevant pieces to the handler that needs them.
pub type Deps {
  Deps(order_repo: OrderRepo)
}

/// Pattern-match path + method, dispatch to a handler.
///
/// Hint: `wisp.path_segments(req)` returns `List(String)`; pattern-
/// match against literals like `["orders", id, "place"]`. For the
/// method, `req.method` is `http.Method` from `gleam_http` —
/// match `http.Post`, `http.Get`, etc.
///
/// One route to support for kata 8:
///   POST /orders/:id/place
/// Anything else → wisp.not_found()
pub fn handle(deps: Deps, req: Request) -> Response {
  case req.method, wisp.path_segments(req) {
    http.Post, ["orders", order_id, "place"] ->
      place_order_handler.run(deps.order_repo, order_id)
    // http.Post, ["orders"] -> { todo }
    // create make an order?
    http.Get, ["orders", id] -> {
      case order.new_id(id) {
        Error(_) -> wisp.bad_request("Invalid order ID")
        Ok(order_id) -> {
          case deps.order_repo.find(order_id) {
            Ok(order) ->
              order
              |> order.order_to_json
              |> json.to_string
              |> wisp.json_response(200)
            Error(_) -> wisp.not_found()
          }
        }
      }
    }
    _, _ -> wisp.not_found()
  }
}
