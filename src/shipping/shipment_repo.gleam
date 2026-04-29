//// Kata 7 — Shipment repository
////
//// Read: docs/book/08_kata_bounded_contexts.md
//// Tests: test/shipping/shipment_test.gleam (the round-trip cases)
////
//// Same actor-backed shape as `OrderRepo` from kata 6. Three operations
//// instead of two: the handler needs `find_by_order` to check for
//// existing shipments before creating a duplicate.
////
//// Implementation notes:
////   - State is `Dict(ShipmentId, Shipment)` (the storage key is the
////     ShipmentId; `find_by_order` scans the values).
////   - `find_by_order` returns the first match (assumes 1:1 between
////     orders and shipments).

import order.{type OrderId}
import shipping/shipment.{type Shipment, type ShipmentId}

pub type RepoError {
  NotFound
}

pub type ShipmentRepo {
  ShipmentRepo(
    find: fn(ShipmentId) -> Result(Shipment, RepoError),
    save: fn(Shipment) -> Result(Nil, RepoError),
    find_by_order: fn(OrderId) -> Result(Shipment, RepoError),
  )
}

// Once you wire the actor, change this return type to
// Result(ShipmentRepo, actor.StartError) so startup failures bubble up.
pub fn in_memory() -> Result(ShipmentRepo, Nil) {
  todo
}
