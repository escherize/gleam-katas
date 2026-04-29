//// Kata 7 — Cross-context handler
////
//// Read: docs/book/08_kata_bounded_contexts.md
//// Tests: test/shipping/handle_order_placed_test.gleam
////
//// This is the bridge between Ordering and Shipping. It is the *only*
//// place where Shipping mentions Ordering's types. Ordering knows
//// nothing about this file — grep `src/order.gleam` for "shipping" and
//// you'll find zero hits.
////

import gleam/result
import order.{type OrderEvent}
import shipping/shipment.{type ShipmentId}
import shipping/shipment_repo.{type ShipmentRepo}

pub type HandleError {
  RepoFailed(shipment_repo.RepoError)
}

// Behavior:
//   1. Inspect the event. Only act on `OrderPlaced`; ignore other
//      variants and return Ok(Nil).
//   2. Check `repo.find_by_order(order_id)` — if a shipment already
//      exists for this order, return Ok(Nil). (Idempotency: events
//      can be replayed; handlers must not duplicate.)
//   3. Otherwise: construct a new Shipment via `shipment.new`, save
//      it via `repo.save`. Map repo errors into HandleError.
pub fn run(
  repo: ShipmentRepo,
  fresh_id: ShipmentId,
  event: OrderEvent,
) -> Result(Nil, HandleError) {
  case event {
    order.OrderPlaced(order_id:, total:) -> {
      case repo.find_by_order(order_id) {
        Ok(_) -> Ok(Nil)
        Error(_) -> {
          let new_shipment = shipment.new(fresh_id, order_id)
          repo.save(new_shipment) |> result.map_error(RepoFailed)
        }
      }
    }
    _ -> Ok(Nil)
  }
}
