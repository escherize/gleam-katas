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

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import order.{type Order, type OrderId}

pub type RepoError {
  NotFound
}

pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
    list_all: fn() -> Result(List(Order), RepoError),
  )
}

pub type Msg {
  Find(id: OrderId, reply_to: Subject(Result(Order, RepoError)))
  Save(order: Order, reply_to: Subject(Result(Nil, RepoError)))
  ListAll(reply_to: Subject(Result(List(Order), RepoError)))
}

fn handle_msg(
  store: Dict(OrderId, Order),
  msg: Msg,
) -> actor.Next(Dict(OrderId, Order), Msg) {
  case msg {
    Find(id:, reply_to:) -> {
      let order = store |> dict.get(id) |> result.replace_error(NotFound)
      process.send(reply_to, order)
      actor.continue(store)
    }
    Save(order:, reply_to:) -> {
      let new_state = dict.insert(store, order.id(order), order)
      process.send(reply_to, Ok(Nil))
      actor.continue(new_state)
    }
    ListAll(reply_to:) -> {
      process.send(reply_to, Ok(dict.values(store)))
      actor.continue(store)
    }
  }
}

pub fn in_memory() -> Result(OrderRepo, actor.StartError) {
  use started <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_msg)
    |> actor.start,
  )
  let pid = started.data
  Ok(
    OrderRepo(
      find: fn(id) { process.call(pid, 100, fn(subject) { Find(id, subject) }) },
      save: fn(order) { process.call(pid, 100, Save(order, _)) },
      list_all: fn() { process.call(pid, 100, ListAll) },
    ),
  )
}
