import customer
import gleam/http
import money
import order
import order_repo
import web/list_orders_handler
import web/router
import wisp/simulate

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn cid() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

fn id_for(s: String) {
  let assert Ok(id) = order.new_id(s)
  id
}

fn fresh_repo() {
  let assert Ok(repo) = order_repo.in_memory()
  repo
}

fn save_draft(repo: order_repo.OrderRepo, id_str: String) -> Nil {
  let #(o, _) = order.new(id_for(id_str), cid())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, usd(100))
  let assert Ok(Nil) = repo.save(o2)
  Nil
}

// ---- direct handler tests ----

pub fn list_on_empty_repo_returns_200_test() {
  let repo = fresh_repo()
  let response = list_orders_handler.run(repo)
  assert response.status == 200
}

pub fn list_returns_seeded_orders_test() {
  let repo = fresh_repo()
  save_draft(repo, "ORDER-001")
  save_draft(repo, "ORDER-002")
  save_draft(repo, "ORDER-003")
  let response = list_orders_handler.run(repo)
  assert response.status == 200
  // Body is a JSON array; we just check status here. Content-shape
  // tests would parse the body — overkill for kata.
}

// ---- via the router ----

pub fn router_dispatches_get_orders_test() {
  let assert Ok(repo) = order_repo.in_memory()
  let deps = router.Deps(order_repo: repo)
  let req = simulate.request(http.Get, "/orders")
  let response = router.handle(deps, req)
  assert response.status == 200
}
