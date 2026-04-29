import customer
import money
import order
import order_repo
import place_order

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn test_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn unknown_order_id() {
  let assert Ok(id) = order.new_id("ORDER-DOES-NOT-EXIST")
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

/// Build a repo seeded with a draft order that has at least one line —
/// ready to be placed.
fn repo_with_placeable_order() {
  let assert Ok(repo) = order_repo.in_memory()
  let assert Ok(#(o, _)) =
    order.add_line(empty_draft_order(), "WIDGET", 2, usd(50))
  let assert Ok(Nil) = repo.save(o)
  repo
}

// ---- happy path ----

pub fn placing_a_draft_order_returns_placed_state_and_event_test() {
  let repo = repo_with_placeable_order()
  let assert Ok(#(_placed, events)) = place_order.run(repo, test_order_id())
  assert events == [order.OrderPlaced(test_order_id(), usd(100))]
}

pub fn placing_a_draft_order_persists_the_placed_state_test() {
  let repo = repo_with_placeable_order()
  let assert Ok(#(placed, _)) = place_order.run(repo, test_order_id())
  let assert Ok(reloaded) = repo.find(test_order_id())
  assert reloaded == placed
}

// ---- failure paths ----

pub fn placing_unknown_order_returns_repo_failure_test() {
  let assert Ok(repo) = order_repo.in_memory()
  // Repo is empty — find will miss.
  assert place_order.run(repo, unknown_order_id())
    == Error(place_order.RepoFailed(order_repo.NotFound))
}

pub fn placing_empty_order_returns_domain_failure_test() {
  let assert Ok(repo) = order_repo.in_memory()
  // Save a draft with NO lines.
  let assert Ok(Nil) = repo.save(empty_draft_order())
  assert place_order.run(repo, test_order_id())
    == Error(place_order.DomainFailed(order.CannotPlaceEmptyOrder))
}

pub fn placing_already_placed_order_returns_domain_failure_test() {
  let repo = repo_with_placeable_order()
  // First call places it successfully.
  let assert Ok(_) = place_order.run(repo, test_order_id())
  // Second call should hit `CannotModifyPlacedOrder` from the domain.
  assert place_order.run(repo, test_order_id())
    == Error(place_order.DomainFailed(order.CannotModifyPlacedOrder))
}
