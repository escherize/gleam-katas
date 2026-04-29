//// Kata 7 — Shipping aggregate
////
//// Read: docs/book/08_kata_bounded_contexts.md
//// Tests: test/shipping/shipment_test.gleam
////
//// Same shape as `Order` from kata 4 but much simpler — no lines, no
//// totals. Just an opaque `ShipmentId`, an `OrderId` foreign-key-ish
//// reference, and a status enum. State transitions check the current
//// status before allowing the move.
////
//// The pattern by now should be familiar: opaque type, smart constructor,
//// state transitions return new immutable values, errors as named typed
//// variants.

import order.{type OrderId}

pub opaque type ShipmentId {
  ShipmentId(value: String)
}

pub type ShipmentStatus {
  Pending
  Shipped
  Delivered
}

pub opaque type Shipment {
  Shipment(id: ShipmentId, order_id: OrderId, status: ShipmentStatus)
}

pub type ShipmentError {
  EmptyShipmentId
  CannotShipNonPending
  CannotDeliverNonShipped
}

pub fn new_id(raw: String) -> Result(ShipmentId, ShipmentError) {
  case raw {
    "" -> Error(EmptyShipmentId)
    _ -> Ok(ShipmentId(raw))
  }
}

/// Construct a new Shipment in the Pending state.
/// Total — never fails.
pub fn new(id: ShipmentId, order_id: OrderId) -> Shipment {
  Shipment(id:, order_id:, status: Pending)
}

pub fn id(s: Shipment) -> ShipmentId {
  s.id
}

pub fn order_id(s: Shipment) -> OrderId {
  s.order_id
}

pub fn status(s: Shipment) -> ShipmentStatus {
  s.status
}

/// Pending -> Shipped. Reject otherwise.
pub fn mark_shipped(s: Shipment) -> Result(Shipment, ShipmentError) {
  case s.status {
    Pending -> Ok(Shipment(id: s.id, order_id: s.order_id, status: Shipped))
    _ -> Error(CannotShipNonPending)
  }
}

/// Shipped -> Delivered. Reject otherwise.
pub fn mark_delivered(s: Shipment) -> Result(Shipment, ShipmentError) {
  case s.status {
    Shipped -> Ok(Shipment(id: s.id, order_id: s.order_id, status: Delivered))
    _ -> Error(CannotDeliverNonShipped)
  }
}
