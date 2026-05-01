//// Query-parameter helpers for handlers.
////
//// `wisp.get_query(req)` returns `List(#(String, String))` — duplicates
//// preserved. These helpers turn "I need exactly one" into a single
//// `use <-` line at the call site, with sensible 400 responses for
//// missing or duplicated keys.

import gleam/int
import gleam/list
import wisp.{type Response}

/// Require exactly one value for `key`. On success, calls `then(value)`.
/// On missing or duplicate, returns a 400 directly — the callback never runs.
///
/// Use it like `use <-` from kata 2:
///   use cid <- qp.require_one(wisp.get_query(req), "customer_id")
///   ... continue with cid in scope ...
pub fn require_one(
  qp: List(#(String, String)),
  key: String,
  then: fn(String) -> Response,
) -> Response {
  case list.key_filter(qp, key) {
    [value] -> then(value)
    [] -> wisp.bad_request("missing query parameter: " <> key)
    _ -> wisp.bad_request("duplicate query parameter: " <> key)
  }
}

/// Optional version: passes `Ok(value)` for exactly one, `Error(Nil)` for
/// missing. Multiple values still 400 (ambiguous).
pub fn optional_one(
  qp: List(#(String, String)),
  key: String,
  then: fn(Result(String, Nil)) -> Response,
) -> Response {
  case list.key_filter(qp, key) {
    [] -> then(Error(Nil))
    [value] -> then(Ok(value))
    _ -> wisp.bad_request("duplicate query parameter: " <> key)
  }
}

/// All values for `key` (zero or more). Use for filters / tags / anything
/// where repetition is meaningful.
///
///   use tags <- qp.all(wisp.get_query(req), "tag")
pub fn all(
  qp: List(#(String, String)),
  key: String,
  then: fn(List(String)) -> Response,
) -> Response {
  then(list.key_filter(qp, key))
}

/// Require exactly one Int-parseable value for `key`. 400 on missing,
/// duplicated, or unparseable. Same `use <-` shape as `require_one`.
pub fn require_int(
  qp: List(#(String, String)),
  key: String,
  then: fn(Int) -> Response,
) -> Response {
  use raw <- require_one(qp, key)
  case int.parse(raw) {
    Ok(n) -> then(n)
    Error(_) -> wisp.bad_request("query parameter " <> key <> " must be an integer")
  }
}
