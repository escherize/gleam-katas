import customer
import money
import order
import order_repo
import web/add_line_handler

// ---- helpers ----

fn an_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn a_customer_id() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

fn fresh_repo() {
  let assert Ok(repo) = order_repo.in_memory()
  repo
}

/// Repo seeded with one draft order under id ORDER-001 (no lines yet).
fn repo_with_draft_order() {
  let repo = fresh_repo()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(Nil) = repo.save(o)
  repo
}

/// Repo seeded with one draft order with one USD line.
fn repo_with_one_usd_line() {
  let repo = fresh_repo()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(money_usd) = money.new(50, money.USD)
  let assert Ok(#(o2, _)) = order.add_line(o, "EXISTING", 1, money_usd)
  let assert Ok(Nil) = repo.save(o2)
  repo
}

/// Repo seeded with a placed order (one line, then placed).
fn repo_with_placed_order() {
  let repo = fresh_repo()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(money_usd) = money.new(50, money.USD)
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, money_usd)
  let assert Ok(#(o3, _)) = order.place(o2)
  let assert Ok(Nil) = repo.save(o3)
  repo
}

// run signature reminder:
//   run(repo, raw_id, sku, quantity, amount, raw_currency)

// ---- happy path ----

pub fn add_line_to_draft_returns_204_test() {
  let repo = repo_with_draft_order()
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 2, 100, "USD")
  assert response.status == 204
}

// ---- 400: input parse failures (handler-level) ----

pub fn invalid_order_id_returns_400_test() {
  let repo = fresh_repo()
  let response = add_line_handler.run(repo, "", "WIDGET", 1, 100, "USD")
  assert response.status == 400
}

pub fn invalid_currency_returns_400_test() {
  let repo = repo_with_draft_order()
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 1, 100, "XYZ")
  assert response.status == 400
}

pub fn negative_amount_returns_400_test() {
  let repo = repo_with_draft_order()
  // money.new rejects negatives → handler returns 400.
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 1, -5, "USD")
  assert response.status == 400
}

// ---- 404: order not in repo ----

pub fn add_line_to_unknown_order_returns_404_test() {
  let repo = fresh_repo()
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 1, 100, "USD")
  assert response.status == 404
}

// ---- 422: domain-rule violations ----

pub fn empty_sku_returns_422_test() {
  let repo = repo_with_draft_order()
  let response =
    add_line_handler.run(repo, "ORDER-001", "", 1, 100, "USD")
  assert response.status == 422
}

pub fn zero_quantity_returns_422_test() {
  let repo = repo_with_draft_order()
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 0, 100, "USD")
  assert response.status == 422
}

pub fn currency_mismatch_returns_422_test() {
  let repo = repo_with_one_usd_line()
  // Existing line is USD; adding EUR should be rejected.
  let response =
    add_line_handler.run(repo, "ORDER-001", "WIDGET", 1, 50, "EUR")
  assert response.status == 422
}

// ---- 409: order already placed ----

pub fn add_line_to_placed_order_returns_409_test() {
  let repo = repo_with_placed_order()
  let response =
    add_line_handler.run(repo, "ORDER-001", "GADGET", 1, 25, "USD")
  assert response.status == 409
}
