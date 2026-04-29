//// Kata 6 — Repositories: the use case
////
//// Read: docs/book/07_kata_repositories.md
//// Tests: test/place_order_test.gleam
////
//// Implement `run/2` below. The chain has three potentially-failing steps:
////
////   1. Load the order:        repo.find(id)            -> Result(Order, RepoError)
////   2. Place it:              order.place(order)       -> Result(#(Order, [event]), OrderError)
////   3. Save the placed order: repo.save(placed)        -> Result(Nil, RepoError)
////
//// Each step's error type is different from the function's declared return
//// type (`PlaceOrderError`). Use `result.map_error(RepoFailed)` and
//// `result.map_error(DomainFailed)` to lift them. Chain with `use <- result.try`.

import order.{type Order, type OrderEvent, type OrderError, type OrderId}
import order_repo.{type OrderRepo, type RepoError}

pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}

pub fn run(
  repo: OrderRepo,
  id: OrderId,
) -> Result(#(Order, List(OrderEvent)), PlaceOrderError) {
  todo
}
