// Kata 4 — Aggregates (Order)
// Read: docs/book/05_kata_order.md
// Tests: test/order_test.gleam
//
// Implement the function bodies. The recommended path:
// 1. Get a naive `add_line` working with one big nested `case`.
// 2. Carve each invariant into a small helper that takes a callback.
// 3. Apply them in `add_line` via `use <-`. State checks first, arg
//    validation second.
// 4. Reuse the same helpers in `place` where they apply.
// 5. For `total`, reach for `list.try_map` then `list.try_fold`.
//
// Reference solution lives on the `solutions` branch.

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

pub fn new_id(raw: String) -> Result(OrderId, OrderError) {
  todo
}

pub fn new(id: OrderId, customer_id: CustomerId) -> Order {
  todo
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(Order, OrderError) {
  todo
}

pub fn place(order: Order) -> Result(Order, OrderError) {
  todo
}

pub fn total(order: Order) -> Result(Money, OrderError) {
  todo
}
