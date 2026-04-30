import customer
import gleam/http
import money
import order
import order_repo
import web/place_order_handler
import web/router
import wisp/simulate

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn an_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn a_customer_id() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

/// Build deps containing a freshly-seeded repo with one placeable order.
fn deps_with_placeable_order() {
  let assert Ok(repo) = order_repo.in_memory()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, usd(100))
  let assert Ok(Nil) = repo.save(o2)
  router.Deps(order_repo: repo)
}

/// Build deps with an empty repo (find will miss every id).
fn empty_deps() {
  let assert Ok(repo) = order_repo.in_memory()
  router.Deps(order_repo: repo)
}

// ---- happy path ----

pub fn placing_a_draft_order_returns_200_test() {
  let deps = deps_with_placeable_order()
  let response = place_order_handler.run(deps.order_repo, "ORDER-001")
  assert response.status == 200
}

// ---- failure paths ----

pub fn malformed_id_returns_400_test() {
  let deps = empty_deps()
  // empty string is not a valid OrderId (order.new_id rejects it)
  let response = place_order_handler.run(deps.order_repo, "")
  assert response.status == 400
}

pub fn unknown_order_returns_404_test() {
  let deps = empty_deps()
  // Repo is empty — find will miss.
  let response = place_order_handler.run(deps.order_repo, "ORDER-DOES-NOT-EXIST")
  assert response.status == 404
}

pub fn placing_an_empty_order_returns_422_test() {
  let assert Ok(repo) = order_repo.in_memory()
  // Save a draft with NO lines
  let #(empty, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(Nil) = repo.save(empty)
  let deps = router.Deps(order_repo: repo)

  let response = place_order_handler.run(deps.order_repo, "ORDER-001")
  assert response.status == 422
}

pub fn placing_an_already_placed_order_returns_409_test() {
  let deps = deps_with_placeable_order()
  // First call places it successfully.
  let assert 200 = { place_order_handler.run(deps.order_repo, "ORDER-001") }.status
  // Second call should hit CannotModifyPlacedOrder → 409 Conflict.
  let response = place_order_handler.run(deps.order_repo, "ORDER-001")
  assert response.status == 409
}

// ---- routing ----

pub fn router_dispatches_post_orders_id_place_test() {
  let deps = deps_with_placeable_order()
  let req = simulate.request(http.Post, "/orders/ORDER-001/place")
  let response = router.handle(deps, req)
  assert response.status == 200
}

pub fn router_returns_404_for_unknown_route_test() {
  let deps = empty_deps()
  let req = simulate.request(http.Get, "/nothing-here")
  let response = router.handle(deps, req)
  assert response.status == 404
}
