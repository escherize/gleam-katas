import customer
import money
import order

// Test helpers
fn usd(amount: Int) {
  let assert Ok(money) = money.new(amount, money.USD)
  money
}

fn eur(amount: Int) {
  let assert Ok(money) = money.new(amount, money.EUR)
  money
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
  order.new(test_order_id(), test_customer_id())
}

// ---- add_line invariant tests ----

pub fn add_line_rejects_empty_sku_test() {
  let order = empty_draft_order()
  assert order.add_line(order, "", 1, usd(100)) == Error(order.EmptySku)
}

pub fn add_line_rejects_zero_quantity_test() {
  let order = empty_draft_order()
  assert order.add_line(order, "WIDGET", 0, usd(100))
    == Error(order.NonPositiveQuantity)
}

pub fn add_line_rejects_negative_quantity_test() {
  let order = empty_draft_order()
  assert order.add_line(order, "WIDGET", -1, usd(100))
    == Error(order.NonPositiveQuantity)
}

pub fn add_line_accepts_valid_input_test() {
  let order = empty_draft_order()
  let assert Ok(_) = order.add_line(order, "WIDGET", 2, usd(100))
}

pub fn add_line_fails_on_placed_order_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_line) = order.add_line(order, "WIDGET", 1, usd(100))
  let assert Ok(placed_order) = order.place(order_with_line)

  assert order.add_line(placed_order, "GADGET", 1, usd(50))
    == Error(order.CannotModifyPlacedOrder)
}

pub fn add_line_fails_on_currency_mismatch_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_usd) = order.add_line(order, "WIDGET", 1, usd(100))

  assert order.add_line(order_with_usd, "GADGET", 1, eur(50))
    == Error(order.CurrencyMismatch)
}

pub fn add_line_allows_same_currency_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_usd) = order.add_line(order, "WIDGET", 1, usd(100))
  let assert Ok(_) = order.add_line(order_with_usd, "GADGET", 1, usd(50))
}

// ---- place invariant tests ----

pub fn place_fails_on_empty_order_test() {
  let order = empty_draft_order()
  assert order.place(order) == Error(order.CannotPlaceEmptyOrder)
}

pub fn place_transitions_draft_to_placed_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_line) = order.add_line(order, "WIDGET", 1, usd(100))
  let assert Ok(_) = order.place(order_with_line)
}

pub fn place_fails_on_already_placed_order_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_line) = order.add_line(order, "WIDGET", 1, usd(100))
  let assert Ok(placed_order) = order.place(order_with_line)

  assert order.place(placed_order) == Error(order.CannotModifyPlacedOrder)
}

// ---- total invariant tests ----

pub fn total_fails_on_empty_order_test() {
  let order = empty_draft_order()
  assert order.total(order) == Error(order.InvalidOrderTotal)
}

pub fn total_calculates_single_line_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_line) = order.add_line(order, "WIDGET", 3, usd(50))
  let assert Ok(total) = order.total(order_with_line)

  assert total == usd(150)
  // 3 * 50
}

pub fn total_calculates_multiple_lines_test() {
  let order = empty_draft_order()
  let assert Ok(order_step1) = order.add_line(order, "WIDGET", 2, usd(50))
  let assert Ok(order_step2) =
    order.add_line(order_step1, "GADGET", 1, usd(100))
  let assert Ok(total) = order.total(order_step2)

  assert total == usd(200)
  // (2 * 50) + (1 * 100)
}

pub fn total_works_with_placed_order_test() {
  let order = empty_draft_order()
  let assert Ok(order_with_line) = order.add_line(order, "WIDGET", 2, usd(75))
  let assert Ok(placed_order) = order.place(order_with_line)
  let assert Ok(total) = order.total(placed_order)

  assert total == usd(150)
  // 2 * 75
}

// ---- edge case tests ----

pub fn new_id_rejects_empty_string_test() {
  assert order.new_id("") == Error(order.EmptyOrderId)
}

pub fn new_id_accepts_valid_string_test() {
  let assert Ok(_) = order.new_id("ORDER-001")
}
