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

import web/router.{type Deps}
import wisp.{type Response}

pub fn run(deps: Deps, raw_id: String) -> Response {
  todo
}
