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

import gleam/result
import order.{type Order, type OrderError, type OrderEvent, type OrderId}
import order_repo.{type OrderRepo, type RepoError}

pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}

/// Run the "place this order" use case.
///
/// Given a repo (where orders live) and the order's id:
///   1. fetch the order from the repo by id
///   2. apply the domain transition `order.place` to it
///        (Draft -> Placed; emits an OrderPlaced event)
///   3. save the placed order back to the repo
///   4. return the placed order + the events emitted in step 2
///
/// On failure, return an error that names which layer broke:
///   - RepoFailed(...)   — fetch or save failed
///        (e.g. NotFound when the id doesn't exist in the repo)
///   - DomainFailed(...) — the domain rejected the transition
///        (e.g. CannotPlaceEmptyOrder, CannotModifyPlacedOrder)
pub fn run(
  repo: OrderRepo,
  id: OrderId,
) -> Result(#(Order, List(OrderEvent)), PlaceOrderError) {
  use order <- result.try(repo.find(id) |> result.map_error(RepoFailed))
  use #(placed, events) <- result.try(
    order.place(order) |> result.map_error(DomainFailed),
  )
  use _ <- result.try(repo.save(placed) |> result.map_error(RepoFailed))
  Ok(#(placed, events))
}
