//// Kata 9 — SQLite-backed OrderRepo
////
//// Read: docs/book/10_kata_sqlite_repo.md
//// Tests: test/order_repo_sqlite_test.gleam
////
//// Same OrderRepo interface as src/order_repo.gleam (in-memory), but
//// persisted to an SQLite database. Single writer actor wraps the
//// connection; same Msg / handle_msg shape as the in-memory adapter,
//// but the body of each arm uses sqlight.query / sqlight.exec instead
//// of dict ops.
////
//// Schema (JSON-blob; one row per order):
////
////   CREATE TABLE IF NOT EXISTS orders (
////     id   TEXT PRIMARY KEY,
////     data TEXT NOT NULL  -- whole OrderSnapshot serialized to JSON
////   );
////
//// Save: order |> order.snapshot |> snapshot_to_json |> json.to_string
////       -> INSERT OR REPLACE INTO orders (id, data) VALUES (?, ?)
////
//// Find: SELECT data FROM orders WHERE id = ?
////       -> json.parse with snapshot_decoder -> order.restore
////
//// List: SELECT data FROM orders
////       -> json.parse each row -> order.restore each -> List(Order)
////
//// You'll need: a JSON encoder for OrderSnapshot, a JSON decoder for
//// it, and the actor scaffolding (Msg, handle_msg, in_memory-shaped
//// closures around process.call). Schema setup runs once on start.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import order.{type Order}
import order_repo.{type RepoError, StorageError}
import sqlight

fn decode_order(data: String) -> Result(Order, RepoError) {
  json.parse(data, order.order_snapshot_decoder())
  |> result.map(order.restore)
  |> result.map_error(fn(e) { StorageError(string.inspect(e)) })
}

pub fn sqlite(
  conn: sqlight.Connection,
) -> Result(order_repo.OrderRepo, sqlight.Error) {
  use _ <- result.try(sqlight.exec(
    "CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
    conn,
  ))

  Ok(
    order_repo.OrderRepo(
      save: fn(o: Order) -> Result(Nil, RepoError) {
        let id = order.order_id_to_string(order.id(o))
        let data =
          o
          |> order.snapshot()
          |> order.order_snapshot_to_json()
          |> json.to_string()

        sqlight.query(
          "INSERT OR REPLACE INTO orders (id, data) VALUES (? , ?)",
          on: conn,
          with: [sqlight.text(id), sqlight.text(data)],
          expecting: decode.success(Nil),
        )
        |> result.replace(Nil)
        |> result.map_error(fn(e) { StorageError(string.inspect(e)) })
      },
      find: fn(id: order.OrderId) -> Result(Order, RepoError) {
        sqlight.query(
          "SELECT data FROM orders WHERE id = ?",
          on: conn,
          with: [sqlight.text(order.order_id_to_string(id))],
          expecting: decode.at([0], decode.string),
        )
        |> result.map_error(fn(e) { StorageError(string.inspect(e)) })
        |> result.try(fn(rows) {
          case rows {
            [] -> Error(order_repo.NotFound)
            [data, ..] -> decode_order(data)
          }
        })
      },
      list_all: fn() -> Result(List(Order), RepoError) {
        sqlight.query(
          "SELECT data from orders",
          on: conn,
          with: [],
          expecting: decode.at([0], decode.string),
        )
        |> result.map_error(fn(e) { order_repo.StorageError(string.inspect(e)) })
        |> result.try(list.try_map(_, decode_order))
      },
    ),
  )
}
