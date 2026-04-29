import customer
import money
import order
import order_repo

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn test_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn other_order_id() {
  let assert Ok(id) = order.new_id("ORDER-OTHER")
  id
}

fn test_customer_id() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

/// A small helper: empty draft order (we drop the OrderCreated event).
fn empty_draft_order() {
  let #(o, _) = order.new(test_order_id(), test_customer_id())
  o
}

/// Order with one line so we can place it.
fn order_with_widget() {
  let assert Ok(#(o, _)) =
    order.add_line(empty_draft_order(), "WIDGET", 1, usd(100))
  o
}

// ---- save then find ----

pub fn save_then_find_returns_the_order_test() {
  let assert Ok(repo) = order_repo.in_memory()
  let o = order_with_widget()
  let assert Ok(Nil) = repo.save(o)
  let assert Ok(loaded) = repo.find(test_order_id())
  assert loaded == o
}

pub fn find_unknown_id_returns_not_found_test() {
  let assert Ok(repo) = order_repo.in_memory()
  let _ = repo.save(order_with_widget())
  // Different ID — should miss.
  assert repo.find(other_order_id()) == Error(order_repo.NotFound)
}

pub fn find_in_empty_repo_returns_not_found_test() {
  let assert Ok(repo) = order_repo.in_memory()
  assert repo.find(test_order_id()) == Error(order_repo.NotFound)
}

// ---- save acts as upsert ----

pub fn second_save_overwrites_test() {
  let assert Ok(repo) = order_repo.in_memory()
  let o1 = order_with_widget()
  // Add another line — different state, same OrderId
  let assert Ok(#(o2, _)) = order.add_line(o1, "GADGET", 2, usd(50))
  let assert Ok(Nil) = repo.save(o1)
  let assert Ok(Nil) = repo.save(o2)
  let assert Ok(loaded) = repo.find(test_order_id())
  assert loaded == o2
}

// ---- isolation between repos ----

pub fn separate_repos_have_separate_state_test() {
  let assert Ok(repo_a) = order_repo.in_memory()
  let assert Ok(repo_b) = order_repo.in_memory()
  let assert Ok(Nil) = repo_a.save(order_with_widget())
  // repo_b never had this order saved.
  assert repo_b.find(test_order_id()) == Error(order_repo.NotFound)
}
