import customer
import money
import order
import order_repo
import place_order
import shipping/handle_order_placed
import shipping/shipment
import shipping/shipment_repo

// ---- helpers ----

fn usd(amount: Int) {
  let assert Ok(m) = money.new(amount, money.USD)
  m
}

fn an_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn other_order_id() {
  let assert Ok(id) = order.new_id("ORDER-OTHER")
  id
}

fn a_customer_id() {
  let assert Ok(id) = customer.new_id("CUST-001")
  id
}

fn a_ship_id() {
  let assert Ok(id) = shipment.new_id("SHIP-001")
  id
}

/// Construct an OrderPlaced event directly — no place_order machinery
/// needed for the unit-level handler tests.
fn an_order_placed_event() {
  order.OrderPlaced(an_order_id(), usd(100))
}

// ---- direct handler tests (unit-level) ----

pub fn order_placed_creates_a_shipment_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let assert Ok(Nil) =
    handle_order_placed.run(repo, a_ship_id(), an_order_placed_event())
  let assert Ok(s) = repo.find_by_order(an_order_id())
  assert shipment.order_id(s) == an_order_id()
  assert shipment.status(s) == shipment.Pending
}

pub fn handler_is_idempotent_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  // Dispatch the same event twice with two different fresh IDs.
  let assert Ok(Nil) =
    handle_order_placed.run(repo, a_ship_id(), an_order_placed_event())
  let assert Ok(other_ship_id) = shipment.new_id("SHIP-OTHER")
  let assert Ok(Nil) =
    handle_order_placed.run(repo, other_ship_id, an_order_placed_event())
  // Only one shipment exists for this order — the second call should
  // have been a no-op.
  let assert Ok(s) = repo.find_by_order(an_order_id())
  assert shipment.id(s) == a_ship_id()
}

pub fn non_order_placed_events_are_ignored_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let line_added =
    order.LineAdded(an_order_id(), "WIDGET", 1, usd(50))
  let assert Ok(Nil) =
    handle_order_placed.run(repo, a_ship_id(), line_added)
  // No shipment should have been created.
  assert repo.find_by_order(an_order_id())
    == Error(shipment_repo.NotFound)
}

pub fn order_created_events_are_ignored_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let order_created =
    order.OrderCreated(an_order_id(), a_customer_id())
  let assert Ok(Nil) =
    handle_order_placed.run(repo, a_ship_id(), order_created)
  assert repo.find_by_order(an_order_id())
    == Error(shipment_repo.NotFound)
}

pub fn handler_does_nothing_for_unrelated_order_lookups_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let assert Ok(Nil) =
    handle_order_placed.run(repo, a_ship_id(), an_order_placed_event())
  assert repo.find_by_order(other_order_id())
    == Error(shipment_repo.NotFound)
}

// ---- integration: full vertical slice ----

pub fn place_order_event_flows_to_shipping_test() {
  // Set up Ordering: a placeable order in the order_repo.
  let assert Ok(o_repo) = order_repo.in_memory()
  let assert Ok(s_repo) = shipment_repo.in_memory()
  let #(o, _) = order.new(an_order_id(), a_customer_id())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, usd(100))
  let assert Ok(Nil) = o_repo.save(o2)

  // Place the order via Ordering — get back the events.
  let assert Ok(#(_, events)) = place_order.run(o_repo, an_order_id())
  let assert [order_placed] = events

  // Dispatch to Shipping. (In a real system, an event bus would do this.)
  let assert Ok(Nil) =
    handle_order_placed.run(s_repo, a_ship_id(), order_placed)

  // Shipment was created and is reachable via order_id lookup.
  let assert Ok(s) = s_repo.find_by_order(an_order_id())
  assert shipment.order_id(s) == an_order_id()
}
