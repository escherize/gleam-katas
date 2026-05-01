//// Use case: add a line to a draft order.
////
//// Same shape as place_order.run: load → mutate via domain → save.
//// Wraps repo and domain errors into AddLineError so the boundary
//// (HTTP handler) can map each variant to a status code.

import gleam/result
import money.{type Money}
import order.{type Order, type OrderEvent, type OrderError, type OrderId}
import order_repo.{type OrderRepo, type RepoError}

pub type AddLineError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}

pub fn run(
  repo: OrderRepo,
  id: OrderId,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(#(Order, List(OrderEvent)), AddLineError) {
  use loaded <- result.try(repo.find(id) |> result.map_error(RepoFailed))
  use #(updated, events) <- result.try(
    order.add_line(loaded, sku, quantity, unit_price)
    |> result.map_error(DomainFailed),
  )
  use _ <- result.try(repo.save(updated) |> result.map_error(RepoFailed))
  Ok(#(updated, events))
}
