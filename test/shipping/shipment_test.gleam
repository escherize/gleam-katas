import order
import shipping/shipment
import shipping/shipment_repo

// ---- helpers ----

fn an_order_id() {
  let assert Ok(id) = order.new_id("ORDER-001")
  id
}

fn other_order_id() {
  let assert Ok(id) = order.new_id("ORDER-OTHER")
  id
}

fn a_ship_id() {
  let assert Ok(id) = shipment.new_id("SHIP-001")
  id
}

fn pending_shipment() {
  shipment.new(a_ship_id(), an_order_id())
}

// ---- new_id ----

pub fn new_id_rejects_empty_string_test() {
  assert shipment.new_id("") == Error(shipment.EmptyShipmentId)
}

pub fn new_id_accepts_non_empty_test() {
  let assert Ok(_) = shipment.new_id("SHIP-001")
}

// ---- new ----

pub fn new_shipment_starts_pending_test() {
  let s = pending_shipment()
  assert shipment.status(s) == shipment.Pending
}

pub fn new_shipment_records_order_id_test() {
  let s = pending_shipment()
  assert shipment.order_id(s) == an_order_id()
}

pub fn new_shipment_records_id_test() {
  let s = pending_shipment()
  assert shipment.id(s) == a_ship_id()
}

// ---- mark_shipped ----

pub fn mark_shipped_from_pending_succeeds_test() {
  let s = pending_shipment()
  let assert Ok(s2) = shipment.mark_shipped(s)
  assert shipment.status(s2) == shipment.Shipped
}

pub fn mark_shipped_from_shipped_fails_test() {
  let s = pending_shipment()
  let assert Ok(shipped) = shipment.mark_shipped(s)
  assert shipment.mark_shipped(shipped)
    == Error(shipment.CannotShipNonPending)
}

pub fn mark_shipped_from_delivered_fails_test() {
  let s = pending_shipment()
  let assert Ok(shipped) = shipment.mark_shipped(s)
  let assert Ok(delivered) = shipment.mark_delivered(shipped)
  assert shipment.mark_shipped(delivered)
    == Error(shipment.CannotShipNonPending)
}

// ---- mark_delivered ----

pub fn mark_delivered_from_shipped_succeeds_test() {
  let s = pending_shipment()
  let assert Ok(shipped) = shipment.mark_shipped(s)
  let assert Ok(delivered) = shipment.mark_delivered(shipped)
  assert shipment.status(delivered) == shipment.Delivered
}

pub fn mark_delivered_from_pending_fails_test() {
  let s = pending_shipment()
  assert shipment.mark_delivered(s)
    == Error(shipment.CannotDeliverNonShipped)
}

pub fn mark_delivered_from_delivered_fails_test() {
  let s = pending_shipment()
  let assert Ok(shipped) = shipment.mark_shipped(s)
  let assert Ok(delivered) = shipment.mark_delivered(shipped)
  assert shipment.mark_delivered(delivered)
    == Error(shipment.CannotDeliverNonShipped)
}

// ---- shipment_repo round-trip ----

pub fn save_then_find_returns_the_shipment_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let s = pending_shipment()
  let assert Ok(Nil) = repo.save(s)
  let assert Ok(loaded) = repo.find(a_ship_id())
  assert loaded == s
}

pub fn find_unknown_id_returns_not_found_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let assert Ok(other) = shipment.new_id("SHIP-OTHER")
  assert repo.find(other) == Error(shipment_repo.NotFound)
}

pub fn find_by_order_returns_matching_shipment_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let s = pending_shipment()
  let assert Ok(Nil) = repo.save(s)
  let assert Ok(loaded) = repo.find_by_order(an_order_id())
  assert loaded == s
}

pub fn find_by_order_returns_not_found_when_no_match_test() {
  let assert Ok(repo) = shipment_repo.in_memory()
  let assert Ok(Nil) = repo.save(pending_shipment())
  assert repo.find_by_order(other_order_id())
    == Error(shipment_repo.NotFound)
}
