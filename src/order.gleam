// Kata 4 — Aggregates (Order)
// Read: docs/book/05_kata_order.md
// Tests: test/order_test.gleam
//
// Kata 5 layers on top: Domain Events.
// Spec: docs/raw_kata.md (search for "Kata 5: Domain Events").
//
// Three operations now return both the new state AND the events that
// describe what happened:
//
//   new       -> #(Order, List(OrderEvent))
//   add_line  -> Result(#(Order, List(OrderEvent)), OrderError)
//   place     -> Result(#(Order, List(OrderEvent)), OrderError)
//
// Past tense: OrderCreated, LineAdded, OrderPlaced. Events are facts that
// already happened — failures emit no events.
//
// `OrderPlaced` carries the total, so `place` now has to compute the total
// (which can fail) before it can produce the event. This is where the
// `use <-` and `result.try` chaining starts really paying off.
//
// Reference solution lives on the `solutions` branch (still pre-events at
// time of writing — solutions branch will be updated once you've worked
// through this kata).

import customer.{type CustomerId}
import money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

// Internal — this type does not exist outside this module.
type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}

pub type OrderStatus {
  Draft
  Placed
}

pub opaque type Order {
  Order(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(OrderLine),
    status: OrderStatus,
  )
}

pub type OrderError {
  EmptyOrderId
  EmptySku
  NonPositiveQuantity
  CannotModifyPlacedOrder
  CannotPlaceEmptyOrder
  CurrencyMismatch
  InvalidOrderTotal
}

pub type OrderEvent {
  OrderCreated(order_id: OrderId, customer_id: CustomerId)
  LineAdded(order_id: OrderId, sku: String, quantity: Int, unit_price: Money)
  OrderPlaced(order_id: OrderId, total: Money)
}

pub fn new_id(raw: String) -> Result(OrderId, OrderError) {
  todo
}

pub fn new(
  id: OrderId,
  customer_id: CustomerId,
) -> #(Order, List(OrderEvent)) {
  todo
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(#(Order, List(OrderEvent)), OrderError) {
  todo
}

pub fn place(
  order: Order,
) -> Result(#(Order, List(OrderEvent)), OrderError) {
  todo
}

pub fn total(order: Order) -> Result(Money, OrderError) {
  todo
}
