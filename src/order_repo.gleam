//// Kata 6 — Repositories
////
//// Read: docs/book/07_kata_repositories.md
//// Tests: test/order_repo_test.gleam
////
//// Build an in-memory `OrderRepo` backed by a Gleam OTP actor that holds
//// a `Dict(OrderId, Order)`. The interface (`OrderRepo`) is given —
//// callers see a record of two functions and never know an actor exists.
////
//// Three things to figure out:
////
//// 1. The `Msg` type — what messages does the actor need to handle?
////    Each one needs to embed a reply Subject so callers can wait for
////    the answer.
////
//// 2. `handle_msg` — pattern-match on the message; do the right `dict`
////    op; send the reply via `process.send(reply, result)`; return
////    `actor.continue(state)` (or `actor.continue(new_state)` after a
////    save).
////
//// 3. `in_memory()` — wire the actor and bridge to OrderRepo:
////      - actor.new(dict.new()) |> actor.on_message(handle_msg) |> actor.start
////      - The actor's Subject lives at `started.data`
////      - Build `OrderRepo(find: ..., save: ...)` with closures that
////        call `process.call(subject, timeout, fn(reply) { Find/Save(..., reply) })`
////
//// The chapter walks through every step. Keep the Hints section open.
////
//// Don't forget to `gleam add gleam_otp` (already done in this repo) so
//// you can import gleam/otp/actor and gleam/erlang/process.

import order.{type Order, type OrderId}

pub type RepoError {
  NotFound
  // add more variants if you need them (StorageError, CorruptRow, ...)
}

pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
  )
}

// Once you wire the actor, change this return type to
// `Result(OrderRepo, actor.StartError)` so startup failures bubble up.
pub fn in_memory() -> Result(OrderRepo, Nil) {
  todo
}
