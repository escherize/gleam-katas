import customer
import gleam/http
import money
import order
import order_repo
import web/get_order_handler
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

/// Repo seeded with one draft order (one line) under id ORDER-001.
fn deps_with_seeded_order() {
  let assert Ok(repo) = order_repo.in_memory()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, usd(100))
  let assert Ok(Nil) = repo.save(o2)
  router.Deps(order_repo: repo)
}

fn empty_deps() {
  let assert Ok(repo) = order_repo.in_memory()
  router.Deps(order_repo: repo)
}

// ---- direct handler tests ----

pub fn get_existing_order_returns_200_test() {
  let deps = deps_with_seeded_order()
  let response = get_order_handler.run(deps.order_repo, "ORDER-001")
  assert response.status == 200
}

pub fn get_unknown_order_returns_404_test() {
  let deps = empty_deps()
  let response = get_order_handler.run(deps.order_repo, "UNKNOWN")
  assert response.status == 404
}

pub fn get_with_invalid_id_returns_400_test() {
  let deps = empty_deps()
  let response = get_order_handler.run(deps.order_repo, "")
  assert response.status == 400
}

// ---- via the router ----

pub fn router_dispatches_get_orders_id_test() {
  let deps = deps_with_seeded_order()
  let req = simulate.request(http.Get, "/orders/ORDER-001")
  let response = router.handle(deps, req)
  assert response.status == 200
}
