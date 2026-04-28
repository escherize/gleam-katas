// Scenario tests — drive the Order aggregate through a sequence of
// commands and assert on the resulting state, the emitted events, or the
// error returned. See docs/book/06_kata_events.md for the design.

import customer
import gleam/list
import gleam/result
import money
import order

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn eur(amount: Int) {
  let assert Ok(m) = money.new(amount, money.EUR)
  m
}

fn test_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn test_customer_id() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

fn empty_draft_order() {
  let #(o, _) = order.new(test_order_id(), test_customer_id())
  o
}

// ---- the scenario engine ----

/// A command is an *intent* to change the order — the input half of the
/// command/event pair. Commands ask for a transition; events record one.
pub type OrderCommand {
  AddLine(sku: String, quantity: Int, unit_price: money.Money)
  Place
}

/// Apply a sequence of commands to an order. Accumulates the events
/// emitted across all commands. Stops at the first failure and returns
/// the Error — partial results are not exposed.
pub fn run(
  initial: order.Order,
  cmds: List(OrderCommand),
) -> Result(#(order.Order, List(order.OrderEvent)), order.OrderError) {
  list.try_fold(cmds, #(initial, []), apply_one)
}

fn apply_one(
  state: #(order.Order, List(order.OrderEvent)),
  cmd: OrderCommand,
) -> Result(#(order.Order, List(order.OrderEvent)), order.OrderError) {
  let #(o, events_so_far) = state
  let step = case cmd {
    AddLine(sku, q, price) -> order.add_line(o, sku, q, price)
    Place -> order.place(o)
  }
  use #(o2, new_events) <- result.try(step)
  Ok(#(o2, list.append(events_so_far, new_events)))
}

// ---- happy-path scenarios ----

pub fn two_lines_then_place_emits_three_events_test() {
  let cmds = [
    AddLine("WIDGET", 2, usd(50)),
    AddLine("GADGET", 1, usd(100)),
    Place,
  ]
  let assert Ok(#(_, events)) = run(empty_draft_order(), cmds)
  assert list.length(events) == 3
}

pub fn two_lines_then_place_emits_correct_events_test() {
  let oid = test_order_id()
  let cmds = [
    AddLine("WIDGET", 2, usd(50)),
    AddLine("GADGET", 1, usd(100)),
    Place,
  ]
  let assert Ok(#(_, events)) = run(empty_draft_order(), cmds)
  assert events
    == [
      order.LineAdded(oid, "WIDGET", 2, usd(50)),
      order.LineAdded(oid, "GADGET", 1, usd(100)),
      order.OrderPlaced(oid, usd(200)),
    ]
}

pub fn single_line_then_place_test() {
  let cmds = [AddLine("WIDGET", 3, usd(50)), Place]
  let assert Ok(#(_, events)) = run(empty_draft_order(), cmds)
  assert events
    == [
      order.LineAdded(test_order_id(), "WIDGET", 3, usd(50)),
      order.OrderPlaced(test_order_id(), usd(150)),
    ]
}

// ---- failure scenarios ----

pub fn place_empty_order_fails_test() {
  assert run(empty_draft_order(), [Place]) == Error(order.CannotPlaceEmptyOrder)
}

pub fn add_line_after_place_fails_test() {
  let cmds = [
    AddLine("WIDGET", 1, usd(50)),
    Place,
    AddLine("GADGET", 1, usd(50)),
  ]
  assert run(empty_draft_order(), cmds) == Error(order.CannotModifyPlacedOrder)
}

pub fn currency_mismatch_fails_at_second_line_test() {
  let cmds = [
    AddLine("WIDGET", 1, usd(50)),
    AddLine("GADGET", 1, eur(50)),
  ]
  assert run(empty_draft_order(), cmds) == Error(order.CurrencyMismatch)
}

pub fn empty_sku_fails_immediately_test() {
  let cmds = [AddLine("", 1, usd(50))]
  assert run(empty_draft_order(), cmds) == Error(order.EmptySku)
}

pub fn negative_quantity_fails_test() {
  let cmds = [AddLine("WIDGET", -1, usd(50))]
  assert run(empty_draft_order(), cmds) == Error(order.NonPositiveQuantity)
}

pub fn place_twice_fails_on_second_test() {
  let cmds = [AddLine("WIDGET", 1, usd(50)), Place, Place]
  assert run(empty_draft_order(), cmds) == Error(order.CannotModifyPlacedOrder)
}

// ---- partial-failure semantics ----

pub fn failed_command_in_middle_returns_error_only_test() {
  // When a sequence fails midway, the result is a flat Error. We don't
  // expose the partially-built order or the events that succeeded before
  // the failure — callers either get the full success or the first error.
  let cmds = [
    AddLine("WIDGET", 1, usd(50)),
    // fine
    AddLine("", 1, usd(50)),
    // fails
    Place,
    // never runs
  ]
  assert run(empty_draft_order(), cmds) == Error(order.EmptySku)
}
