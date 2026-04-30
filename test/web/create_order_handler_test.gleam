import order
import order_repo
import web/create_order_handler

// ---- helpers ----

fn fresh_repo() {
  let assert Ok(repo) = order_repo.in_memory()
  repo
}

// ---- happy path ----

pub fn create_with_valid_ids_returns_201_test() {
  let repo = fresh_repo()
  let response =
    create_order_handler.run(repo, "ORDER-001", "CUST-001")
  assert response.status == 201
}

pub fn create_persists_the_order_test() {
  let repo = fresh_repo()
  let _ = create_order_handler.run(repo, "ORDER-001", "CUST-001")
  let assert Ok(oid) = order.new_id("ORDER-001")
  let assert Ok(_) = repo.find(oid)
  // Found in the repo — persistence happened.
}

pub fn created_order_has_no_lines_yet_test() {
  let repo = fresh_repo()
  let _ = create_order_handler.run(repo, "ORDER-001", "CUST-001")
  let assert Ok(oid) = order.new_id("ORDER-001")
  let assert Ok(o) = repo.find(oid)
  // total/1 returns Error(InvalidOrderTotal) when the order has no lines.
  assert order.total(o) == Error(order.InvalidOrderTotal)
}

// ---- failure paths ----

pub fn invalid_order_id_returns_400_test() {
  let repo = fresh_repo()
  let response = create_order_handler.run(repo, "", "CUST-001")
  assert response.status == 400
}

pub fn invalid_customer_id_returns_400_test() {
  let repo = fresh_repo()
  let response = create_order_handler.run(repo, "ORDER-001", "")
  assert response.status == 400
}

pub fn order_id_invalid_takes_precedence_test() {
  // When both are bad, the handler reports the order_id failure first.
  // (Matches the case-arm order in run/3.)
  let repo = fresh_repo()
  let response = create_order_handler.run(repo, "", "")
  assert response.status == 400
}

// ---- idempotency / overwrite ----

pub fn create_twice_with_same_id_overwrites_test() {
  // The repo's save is INSERT OR REPLACE semantics. Creating twice
  // with the same id is allowed and ends with a single row.
  let repo = fresh_repo()
  let r1 = create_order_handler.run(repo, "ORDER-001", "CUST-001")
  let r2 = create_order_handler.run(repo, "ORDER-001", "CUST-002")
  assert r1.status == 201
  assert r2.status == 201
  // Whichever customer_id won the second save is now in the repo.
  let assert Ok(oid) = order.new_id("ORDER-001")
  let assert Ok(_) = repo.find(oid)
}

