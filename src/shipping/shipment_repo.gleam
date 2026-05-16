//// Kata 7 — Shipment repository
////
//// Read: docs/book/08_kata_bounded_contexts.md
//// Tests: test/shipping/shipment_test.gleam (the round-trip cases)
////
//// Same actor-backed shape as `OrderRepo` from kata 6. Three operations
//// instead of two: the handler needs `find_by_order` to check for
//// existing shipments before creating a duplicate.
////
//// Implementation notes:
////   - State is `Dict(ShipmentId, Shipment)` (the storage key is the
////     ShipmentId; `find_by_order` scans the values).
////   - `find_by_order` returns the first match (assumes 1:1 between
////     orders and shipments).

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import order.{type OrderId}
import shipping/shipment.{type Shipment, type ShipmentId}

pub type RepoError {
  NotFound
  StorageError(String)
}

pub type ShipmentRepo {
  ShipmentRepo(
    find: fn(ShipmentId) -> Result(Shipment, RepoError),
    save: fn(Shipment) -> Result(Nil, RepoError),
    find_by_order: fn(OrderId) -> Result(Shipment, RepoError),
  )
}

pub type Msg {
  Find(id: ShipmentId, reply_to: process.Subject(Result(Shipment, RepoError)))
  Save(shipment: Shipment, reply_to: process.Subject(Result(Nil, RepoError)))
  FindByOrder(
    order_id: OrderId,
    reply_to: process.Subject(Result(Shipment, RepoError)),
  )
}

fn handle_msg(
  store: Dict(ShipmentId, Shipment),
  msg: Msg,
) -> actor.Next(Dict(ShipmentId, Shipment), Msg) {
  case msg {
    Find(id:, reply_to:) -> {
      let shipment = store |> dict.get(id) |> result.replace_error(NotFound)
      process.send(reply_to, shipment)
      actor.continue(store)
    }
    Save(shipment:, reply_to:) -> {
      let new_store = store |> dict.insert(shipment.id(shipment), shipment)
      process.send(reply_to, Ok(Nil))
      actor.continue(new_store)
    }
    FindByOrder(order_id:, reply_to:) -> {
      let shipment =
        store
        |> dict.values
        |> list.find(fn(s) { shipment.order_id(s) == order_id })
        |> result.replace_error(NotFound)
      process.send(reply_to, shipment)
      actor.continue(store)
    }
  }
}

pub fn in_memory() -> Result(ShipmentRepo, actor.StartError) {
  use started <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_msg)
    |> actor.start,
  )
  let pid = started.data
  Ok(
    ShipmentRepo(
      find: fn(id) { process.call(pid, 100, fn(subject) { Find(id, subject) }) },
      save: fn(shipment) { process.call(pid, 100, Save(shipment, _)) },
      find_by_order: fn(order_id) {
        process.call(pid, 100, fn(subject) { FindByOrder(order_id, subject) })
      },
    ),
  )
}
