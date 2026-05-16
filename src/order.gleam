//// Kata 4 — Aggregates (Order)
//// Read: docs/book/05_kata_order.md
//// Tests: test/order_test.gleam
////
//// Kata 5 layers on top: Domain Events.
//// Spec: docs/raw_kata.md (search for "Kata 5: Domain Events").
////
//// Three operations now return both the new state AND the events that
//// describe what happened:
////
////   new       -> #(Order, List(OrderEvent))
////   add_line  -> Result(#(Order, List(OrderEvent)), OrderError)
////   place     -> Result(#(Order, List(OrderEvent)), OrderError)
////
//// Past tense: OrderCreated, LineAdded, OrderPlaced. Events are facts that
//// already happened — failures emit no events.
////
//// `OrderPlaced` carries the total, so `place` now has to compute the total
//// (which can fail) before it can produce the event. This is where the
//// `use <-` and `result.try` chaining starts really paying off.
////
//// Reference solution lives on the `solutions` branch.

import customer.{type CustomerId}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import money.{type Money}

/// The ID for an order
pub opaque type OrderId {
  OrderId(value: String)
}

fn order_id_decoder() -> decode.Decoder(OrderId) {
  decode.string |> decode.map(fn(value) { OrderId(value:) })
}

pub fn order_id_to_string(order_id: OrderId) -> String {
  order_id.value
}

// Internal — this type does not exist outside this module.
type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}

fn order_line_to_json(order_line: OrderLine) -> json.Json {
  let OrderLine(sku:, quantity:, unit_price:) = order_line
  json.object([
    #("sku", json.string(sku)),
    #("quantity", json.int(quantity)),
    #("unit_price", money.to_json(unit_price)),
  ])
}

pub type OrderStatus {
  Draft
  Placed
}

fn order_status_decoder() -> decode.Decoder(OrderStatus) {
  use variant <- decode.then(decode.string)
  case variant {
    "draft" -> decode.success(Draft)
    "placed" -> decode.success(Placed)
    _ -> decode.failure(Draft, "OrderStatus")
  }
}

fn order_status_to_json(order_status: OrderStatus) -> json.Json {
  case order_status {
    Draft -> json.string("draft")
    Placed -> json.string("placed")
  }
}

pub opaque type Order {
  Order(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(OrderLine),
    status: OrderStatus,
  )
}

pub fn order_to_json(order: Order) -> json.Json {
  let Order(id:, customer_id:, lines:, status:) = order
  json.object([
    #("id", json.string(id.value)),
    #("customer_id", json.string(customer.customer_id(customer_id))),
    #("lines", json.array(lines, order_line_to_json)),
    #("status", order_status_to_json(status)),
  ])
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
  case raw {
    "" -> Error(EmptyOrderId)
    _ -> Ok(OrderId(raw))
  }
}

/// Public accessor — needed by the repository layer (kata 6) so it can
/// extract the ID from an order to use as the storage key.
pub fn id(order: Order) -> OrderId {
  order.id
}

pub fn new(id: OrderId, customer_id: CustomerId) -> #(Order, List(OrderEvent)) {
  let order = Order(id, customer_id, [], Draft)
  let event = OrderCreated(id, customer_id)
  #(order, [event])
}

fn cannot_modify_placed_order(
  order: Order,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case order.status {
    Placed -> Error(CannotModifyPlacedOrder)
    _ -> then()
  }
}

fn require_non_empty_sku(
  sku: String,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case sku {
    "" -> Error(EmptySku)
    _ -> then()
  }
}

fn require_positive_quantity(
  q: Int,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case q > 0 {
    True -> then()
    False -> Error(NonPositiveQuantity)
  }
}

fn order_line_currency_matches(
  order: Order,
  unit_price: Money,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case order.lines {
    [] -> then()
    [ol, ..] ->
      case money.same_currency(ol.unit_price, unit_price) {
        True -> then()
        False -> Error(CurrencyMismatch)
      }
  }
}

fn require_non_empty_lines(
  order: Order,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case order.lines {
    [] -> Error(CannotPlaceEmptyOrder)
    _ -> then()
  }
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(#(Order, List(OrderEvent)), OrderError) {
  use <- cannot_modify_placed_order(order)
  use <- require_non_empty_sku(sku)
  use <- require_positive_quantity(quantity)
  use <- order_line_currency_matches(order, unit_price)
  let new_order_line = OrderLine(sku, quantity, unit_price)
  let new_order_lines = [new_order_line, ..order.lines]
  let order = Order(..order, lines: new_order_lines)
  Ok(#(order, [LineAdded(order_id: order.id, sku:, quantity:, unit_price:)]))
}

pub fn place(order: Order) -> Result(#(Order, List(OrderEvent)), OrderError) {
  use <- cannot_modify_placed_order(order)
  use <- require_non_empty_lines(order)
  use total <- result.try(total(order))
  let order = Order(..order, status: Placed)
  Ok(#(order, [OrderPlaced(order.id, total)]))
}

pub fn total(order: Order) -> Result(Money, OrderError) {
  case order.lines {
    [] -> Error(InvalidOrderTotal)
    [ol, ..] ->
      order.lines
      |> list.try_fold(money.zero(ol.unit_price), fn(acc, line) {
        use subtotal <- result.try(money.multiply(
          line.unit_price,
          line.quantity,
        ))
        money.add(acc, subtotal)
      })
      |> result.replace_error(InvalidOrderTotal)
  }
}

// snapshots

pub type LineSnapshot {
  LineSnapshot(sku: String, quantity: Int, unit_price: Money)
}

fn line_snapshot_decoder() -> decode.Decoder(LineSnapshot) {
  use sku <- decode.field("sku", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use unit_price <- decode.field("unit_price", money.money_decoder())
  decode.success(LineSnapshot(sku:, quantity:, unit_price:))
}

fn line_snapshot_to_json(line_snapshot: LineSnapshot) -> json.Json {
  let LineSnapshot(sku:, quantity:, unit_price:) = line_snapshot
  json.object([
    #("sku", json.string(sku)),
    #("quantity", json.int(quantity)),
    #("unit_price", money.to_json(unit_price)),
  ])
}

/// A serializable view of an Order's internal state. Public so the
/// persistence layer can read/write it; not for application code.
pub type OrderSnapshot {
  OrderSnapshot(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(LineSnapshot),
    status: OrderStatus,
  )
}

pub fn order_snapshot_decoder() -> decode.Decoder(OrderSnapshot) {
  use id <- decode.field("id", order_id_decoder())
  use customer_id <- decode.field("customer_id", customer.customer_id_decoder())
  use lines <- decode.field("lines", decode.list(line_snapshot_decoder()))
  use status <- decode.field("status", order_status_decoder())
  decode.success(OrderSnapshot(id:, customer_id:, lines:, status:))
}

pub fn order_snapshot_to_json(order_snapshot: OrderSnapshot) -> json.Json {
  let OrderSnapshot(id:, customer_id:, lines:, status:) = order_snapshot
  json.object([
    #("id", order_id_to_string(id) |> json.string),
    #("customer_id", customer.customer_id(customer_id) |> json.string),
    #("lines", json.array(lines, line_snapshot_to_json)),
    #("status", order_status_to_json(status)),
  ])
}

pub fn snapshot(order: Order) -> OrderSnapshot {
  OrderSnapshot(
    id: order.id,
    customer_id: order.customer_id,
    lines: order.lines
      |> list.map(fn(ol) {
        let OrderLine(sku:, quantity:, unit_price:) = ol
        LineSnapshot(sku, quantity, unit_price)
      }),
    status: order.status,
  )
}

pub fn restore(snap: OrderSnapshot) -> Order {
  let OrderSnapshot(id:, customer_id:, lines:, status:) = snap
  let order_lines =
    lines
    |> list.map(fn(line) {
      let LineSnapshot(sku:, quantity:, unit_price:) = line
      OrderLine(sku, quantity, unit_price)
    })
  Order(id, customer_id, order_lines, status)
}
