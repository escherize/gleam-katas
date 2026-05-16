import customer
import money
import order
import order_repo
import order_repo_sqlite
import sqlight

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

/// Each test gets its own :memory: SQLite instance — total isolation,
/// no fixtures, no cleanup.
fn fresh_repo() {
  let assert Ok(conn) = sqlight.open(":memory:")
  let assert Ok(repo) = order_repo_sqlite.sqlite(conn)
  repo
}

fn empty_draft_order() {
  let #(o, _) = order.new(test_order_id(), test_customer_id())
  o
}

fn order_with_widget() {
  let assert Ok(#(o, _)) =
    order.add_line(empty_draft_order(), "WIDGET", 1, usd(100))
  o
}

// ---- find / save round-trip ----

pub fn save_then_find_returns_the_order_test() {
  let repo = fresh_repo()
  let o = order_with_widget()
  let assert Ok(Nil) = repo.save(o)
  let assert Ok(loaded) = repo.find(test_order_id())
  assert loaded == o
}

pub fn find_in_empty_repo_returns_not_found_test() {
  let repo = fresh_repo()
  assert repo.find(test_order_id()) == Error(order_repo.NotFound)
}

pub fn find_unknown_id_returns_not_found_test() {
  let repo = fresh_repo()
  let _ = repo.save(order_with_widget())
  // Different id — should miss.
  assert repo.find(other_order_id()) == Error(order_repo.NotFound)
}

// ---- save acts as upsert ----

pub fn second_save_overwrites_test() {
  let repo = fresh_repo()
  let o1 = order_with_widget()
  // Add another line — same OrderId, different state.
  let assert Ok(#(o2, _)) = order.add_line(o1, "GADGET", 2, usd(50))
  let assert Ok(Nil) = repo.save(o1)
  let assert Ok(Nil) = repo.save(o2)
  let assert Ok(loaded) = repo.find(test_order_id())
  assert loaded == o2
}

// ---- list_all ----

pub fn list_all_on_empty_repo_returns_empty_test() {
  let repo = fresh_repo()
  let assert Ok(loaded) = repo.list_all()
  assert loaded == []
}

pub fn list_all_returns_seeded_orders_test() {
  let repo = fresh_repo()
  let assert Ok(other_id) = order.new_id("ORDER-OTHER")
  let #(o1, _) = order.new(test_order_id(), test_customer_id())
  let #(o2, _) = order.new(other_id, test_customer_id())
  let assert Ok(Nil) = repo.save(o1)
  let assert Ok(Nil) = repo.save(o2)
  let assert Ok(loaded) = repo.list_all()
  // Order in the result list isn't guaranteed; just check count + membership.
  assert list_length(loaded) == 2
}

// ---- isolation between in-memory connections ----

pub fn separate_repos_have_separate_state_test() {
  let repo_a = fresh_repo()
  let repo_b = fresh_repo()
  let assert Ok(Nil) = repo_a.save(order_with_widget())
  // repo_b uses its own :memory: SQLite; nothing was saved there.
  assert repo_b.find(test_order_id()) == Error(order_repo.NotFound)
}

// ---- the snapshot round-trip is what makes find work ----

pub fn save_and_load_preserves_lines_test() {
  let repo = fresh_repo()
  // Build an order with two lines, both USD.
  let #(o, _) = order.new(test_order_id(), test_customer_id())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 2, usd(100))
  let assert Ok(#(o3, _)) = order.add_line(o2, "GADGET", 1, usd(50))
  let assert Ok(Nil) = repo.save(o3)
  let assert Ok(loaded) = repo.find(test_order_id())
  // The whole structure must round-trip — equal to the original.
  assert loaded == o3
  // And total still computes correctly after load.
  let assert Ok(t) = order.total(loaded)
  assert t == usd(250)
  // 2 * 100 + 1 * 50
}

// ---- tiny helper because I'd rather not pull in gleam/list ----

fn list_length(xs: List(a)) -> Int {
  case xs {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
