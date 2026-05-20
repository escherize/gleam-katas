# 10. Kata 9: SQLite Repository

## Concept

`OrderRepo` keeps `find` and `save` as fields on a record so that the
implementation can change without touching the use case. The only
implementation so far is an in-memory actor, so restart the process and
every order vanishes.

Write `pub fn sqlite(connection) -> OrderRepo` against the same
`OrderRepo` interface, backed by a SQLite database. No other file in
the system changes. `place_order.run` keeps calling the same record,
and so do the handler and the existing `in_memory`-based tests.

That swap, with no other code aware of it, is the repository pattern
in concrete form. If you find yourself touching the use case to make
this work, the design drifted somewhere upstream and that's where the
fix belongs.

## Why SQLite for a learning project

SQLite needs no daemon and no port, only a file path or `:memory:`
for tests. You write `CREATE TABLE`, bind parameters, decode rows. The lessons transfer to
Postgres with a different library (`pog` where you'd use `sqlight`)
and the same testing model. Per-test isolation comes from calling
`sqlight.open(":memory:")` in the test itself, which removes the
fixture-and-rollback dance. File-based storage in production means
backups are `cp`, which suffices for an app with one writer.

SQLite handles concurrent writers across processes badly. The kata
sidesteps the issue; production cannot. One process with many
readers and one writer is fine; once you need many writers across
processes, reach for Postgres.

## The interesting design problem

`Order` is opaque. `OrderLine` is private to `order.gleam`, so the type
doesn't exist outside the module. When the SQLite adapter loads a row
from the database, it can't construct an `Order` from raw fields.
There is no public constructor that takes `(id, customer_id, lines,
status)`. The adapter has options.

1. Replay the public API on load, calling `order.new(id, cid)`, then
   `order.add_line(...)` per line, then `order.place(...)` if the
   status was `Placed`. The public API emits events
   (`OrderCreated`, `LineAdded`, `OrderPlaced`), so loading from disk
   emits fake events as if the actions were happening fresh, which
   disqualifies the approach.

2. Punch a rehydrate back door in `order.gleam` that the
   persistence layer uses and application code doesn't. Add
   `pub type OrderSnapshot { ... }` with `pub fn snapshot(o) ->
   OrderSnapshot` and `pub fn restore(s) -> Order`. The snapshot
   exposes internal state in a controlled public shape without
   leaking the private types. The repo serializes the snapshot to
   JSON, stores it, decodes it back, and calls `restore`.

Option 2 is what every production system using opaque aggregates with
state-stored persistence ends up doing. The public API enforces
business invariants on transitions; the snapshot/restore pair handles
persistence. That separation between transition rules and bytes on
disk is the lesson of this kata, with SQL as the vehicle.

---

## New Gleam fundamentals

### `sqlight`: SQLite from Gleam

```gleam
import sqlight

// Open
let assert Ok(conn) = sqlight.open(":memory:")  // or "file:orders.db"

// DDL: no params, no result
let assert Ok(Nil) = sqlight.exec(
  "CREATE TABLE orders (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
  on: conn,
)

// Parameterized query: INSERT/UPDATE/DELETE
let assert Ok(_) = sqlight.query(
  "INSERT INTO orders (id, data) VALUES (?, ?)",
  on: conn,
  with: [sqlight.text("ORDER-001"), sqlight.text(json_blob)],
  expecting: decode.success(Nil),
)

// SELECT with decoder
let assert Ok(rows) = sqlight.query(
  "SELECT data FROM orders WHERE id = ?",
  on: conn,
  with: [sqlight.text(id_string)],
  expecting: decode.field("data", decode.string),
)
```

`sqlight.text/int/float/bool/blob/null/nullable` build parameter
values. `decode.string/int/field/...` from `gleam/dynamic/decode`
builds the row decoder.

Errors come back as `sqlight.SqlightError(code, message, offset)`.
Match on `code` for specific cases like `Constraint` or `Corrupt`.

### `gleam/json`: encoding and decoding JSON

```gleam
import gleam/json

// Encode
let body = json.object([
  #("id", json.string(id_str)),
  #("status", json.string("Placed")),
  #("lines", json.array(of: json.object, items: line_objects)),
])
let blob = json.to_string(body)  // -> String

// Decode
import gleam/dynamic/decode

let order_decoder = {
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", decode.string)
  decode.success(#(id, status))
}
let assert Ok(parsed) = json.parse(blob, order_decoder)
```

The decoder type is `decode.Decoder(t)`, built by chaining
`decode.field` calls inside a `use` block. The hints below walk
through what an `Order`-shaped decoder looks like.

#### The LSP writes the boilerplate

The Gleam language server ships "Generate to-json function" and
"Generate decoder" as code actions. With the cursor on a
`pub type Foo { ... }` line, trigger code actions in your editor
(`⌘.` in VS Code, `<space>a` in Helix, `<leader>ca` in most nvim
setups) and pick the generator. The LSP writes the encoder or decoder
next to the type, populated from the fields it can see, and emits
`todo` placeholders for nested types it hasn't reached yet. Covering
the full Order tree takes several invocations and a styling pass.

#### Visible code is the feature, not the cost

Other ecosystems hide encoders behind derive macros
(`#[derive(Serialize)]`), annotations (`@JsonProperty`), or typeclass
instances, all generated at compile time or via reflection. Gleam asks
you to write the function (or have the LSP write it into your source).
A few keystrokes more, paid back in: encoders you can read, grep, and
step through; field renames that surface as compile errors instead of
silent serialization drift; per-type encoding strategies without
decorator soup; and one mechanism whether the bytes go to JSON,
MessagePack, log lines, or fixtures.

### The snapshot/restore back door pattern

Add these to `src/order.gleam`:

```gleam
/// A serializable view of an Order's internal state. Public so the
/// persistence layer can read/write it; not for application code.
pub type OrderSnapshot {
  OrderSnapshot(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(LineSnapshot),
    status: OrderStatus,
  )
}

pub type LineSnapshot {
  LineSnapshot(sku: String, quantity: Int, unit_price: Money)
}

pub fn snapshot(order: Order) -> OrderSnapshot {
  OrderSnapshot(
    id: order.id,
    customer_id: order.customer_id,
    lines: list.map(order.lines, fn(l) {
      LineSnapshot(sku: l.sku, quantity: l.quantity, unit_price: l.unit_price)
    }),
    status: order.status,
  )
}

pub fn restore(snap: OrderSnapshot) -> Order {
  Order(
    id: snap.id,
    customer_id: snap.customer_id,
    lines: list.map(snap.lines, fn(l) {
      OrderLine(sku: l.sku, quantity: l.quantity, unit_price: l.unit_price)
    }),
    status: snap.status,
  )
}
```

`restore` is total. It assumes the snapshot is valid because the
snapshot came from `snapshot`, which only produces valid snapshots
from valid orders. The persistence layer makes sure the bytes
round-trip. The domain doesn't re-validate.

The snapshot uses `LineSnapshot` instead of the private `OrderLine`.
That keeps `OrderLine` private (no one outside `order.gleam` can
construct one directly) while still giving the persistence layer a
stable public shape to work with.

`Money`, `OrderStatus`, `OrderId`, and `CustomerId` are already
public, and embed in the snapshot as-is.

---

## Task

Add the dependency:

```sh
gleam add sqlight gleam_json
```

Then create one file and edit one:

### 1. Edit `src/order.gleam`: add the snapshot back door

Add `OrderSnapshot`, `LineSnapshot`, `pub fn snapshot`, and `pub fn
restore` as described above. Around 30 new lines. The existing public
API stays unchanged. The snapshot/restore pair is additive.

### 2. Create `src/order_repo_sqlite.gleam`: the SQLite adapter

```gleam
pub fn sqlite(conn: Connection) -> Result(OrderRepo, RepoError)
```

Responsibilities:

1. Run schema setup (`CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, data TEXT NOT NULL)`) on connection.
2. Build closures for `find` and `save`.
   - `find` queries by id. If no row, return `Error(NotFound)`. If a row, decode the `data` JSON into an `OrderSnapshot`, call `order.restore`, return `Ok(order)`.
   - `save` serializes via `order.snapshot` to JSON and runs `INSERT OR REPLACE INTO orders (id, data) VALUES (?, ?)`. On success it returns `Ok(Nil)`. Map sqlight errors to `RepoError`.
3. Return the `OrderRepo` record.

Around 60 to 80 lines, including the JSON encode/decode boilerplate.

### 3. Create `test/order_repo_sqlite_test.gleam`

Same shape as `order_repo_test.gleam` from kata 6. Open `:memory:`
per test, build the repo, exercise the find/save round-trip,
NotFound, and overwrite. The point is that the same assertions run
against a SQLite-backed repo because the interface is the same.

Bonus: a `place_order` integration test using a SQLite repo. It's a
copy of the existing integration test with the constructor swapped.

---

## Hints

1. Build the schema before the queries. Write the `CREATE TABLE` and run it. Add a no-op `find` that always returns `NotFound` and a no-op `save` that always succeeds. The actor-shaped flow has to run end to end with the SQLite layer in place before query logic goes on top of a solid scaffold.

2. JSON encoding is verbose, and the verbosity is the point. `Money` becomes `{"amount": 150, "currency": "USD"}`; `Currency` and `OrderStatus` flatten to strings; `LineSnapshot` becomes an object. The full encoder runs roughly 30 lines of nested `json.object` calls.

3. Decoders mirror encoders. For each `json.object([("foo", ...)])` you wrote, there's a `decode.field("foo", ...)` you write. Build decoders for `Money`, `Currency`, `OrderStatus`, and `LineSnapshot`, then compose them into `OrderSnapshot`.

4. Use `INSERT OR REPLACE` for save. It handles insert-new and update-existing in one statement. The aggregate is the unit of save, so you replace the row.

5. Each `pub fn ..._test` opens its own `:memory:` connection. Sharing one connection means tests share state, and the suite goes flaky.

6. `sqlight.nullable(sqlight.text, optional_string)` is the binding helper for optional fields. Nothing in the current schema is null, but optional fields land in any real-world extension.

7. The hardest debugging path is silent JSON drift. If `snapshot |> encode |> string |> decode |> restore` doesn't round-trip exactly, load-time failures look mysterious. Write a unit test for the round-trip independent of SQLite: encode an order to JSON, decode it back, assert equality. It catches drift before SQL is involved.

8. `pub fn sqlite(conn)` takes an already-open connection rather than opening one itself. That keeps the repo testable (`:memory:` in tests, file connections in main) and lets the composition root own the connection lifecycle.

---

## Walk-through

The schema fits in one table.

```sql
CREATE TABLE IF NOT EXISTS orders (
  id   TEXT PRIMARY KEY,
  data TEXT NOT NULL  -- JSON snapshot of OrderSnapshot
);
```

One row per order holds the serialized snapshot. Saving is
`INSERT OR REPLACE`; finding is `SELECT data WHERE id = ?`. No joins
or transactions yet.

`find` reads the row, decodes the JSON to an `OrderSnapshot`, and
hands it to `order.restore`. `save` runs the inverse: `order.snapshot`,
encode to JSON, `INSERT OR REPLACE`. The id comes from the `pub fn id`
accessor added in kata 6.

If decode fails, the row is corrupt. Add `CorruptRow(reason: String)`
to `RepoError` so callers see something other than a generic decode
error.

The substitution at the composition root is one line:

```gleam
// before
let assert Ok(repo) = order_repo.in_memory()

// after
let assert Ok(conn) = sqlight.open("file:orders.db")
let assert Ok(repo) = order_repo_sqlite.sqlite(conn)
```

`place_order.run`, the HTTP handler, and the use-case tests keep
running unchanged. That swap is the repository pattern's whole point.

---

## Critique

Schema migrations are absent. `CREATE TABLE IF NOT EXISTS` works for
v1. The second version that adds a column needs a migration story:
`ALTER TABLE`, a version table, and so on. Production apps reach for
`dbmate` or `sqitch` for SQL files. In Gleam you can hand-roll a
tracker that records applied migrations in a `_migrations` table.
That work lives outside this kata.

Optimistic concurrency control is absent too. Two concurrent saves can
race, and the second silently overwrites the first. For an actor-writes
setup, which the in-memory actor model gives you by construction, that's
fine. For multi-process writes, add a `version INT` column, check it
on update, and fail with a `Conflict` variant when stale. Postgres
and DynamoDB use the same pattern.

JSON storage is opaque to SQL. You can't write `SELECT * WHERE total
> 100` because `total` lives inside the JSON blob. SQLite's
`json_extract` lets you query into the JSON, but it's slow without
expression indexes. If you need rich querying, denormalize, splitting
into `orders` and `order_lines` tables (the schema design covered in
the chapter on `Shape` versus DB storage). The lesson on the
rehydration back door doesn't change.

Streaming and batch operations stay out of scope. Each extension
(`find_all`, `find_by_customer`, paginated reads) adds a field to
`OrderRepo` and a closure in the constructor.

The connection is a shared resource. SQLite handles one
writer. Multiple opens to the same file work, but write-serialization
happens at the OS level. For production, wrap the `sqlight.Connection`
in an actor that serializes access, or turn on WAL mode with `PRAGMA
journal_mode=WAL`.

`restore` trusts the snapshot. A bad row could produce an `Order`
whose state violates aggregate invariants. The current `restore`
builds the record directly without re-checking. That's defensible
when the snapshot came from a valid order originally, and risky when
a hand-edited row or migration bug slips through. A paranoid
`restore` would re-run invariants, at the cost of going through the
public API (re-emitting events) or duplicating validation logic. The
project picks one tradeoff and records the choice.

---

## Takeaway

Kata 6 made the repository pattern plausible because an in-memory
adapter worked. This kata makes it load-bearing: SQLite slots in
behind the same record of two functions, and the use case, handler,
and scenario tests run against either backend unchanged. The domain
code never learned what storage looks like because the type system
gave it no way to find out, and systems built on that constraint
survive a storage migration five years later.

The snapshot/restore pair is the right Gleam answer to the
serialization boundary. Other languages reach for `@JsonSerializable`
annotations or reflection-based ORMs; Gleam asks you to write the
encoder by hand, so when the schema drifts the function to update is
the one whose field list no longer matches the type.

---

## What's next

The stack is now production-shape: typed domain, events as facts,
repositories as interfaces, bounded contexts, HTTP boundary,
composition root, and disk persistence. Everything beyond is
specialization.

The final chapter steps out of katas and into practice: what
experience teaches that the exercises don't, what to skip, when to
escalate, and how to keep the codebase from drifting back into the
soup the patterns exist to prevent.
