# 10 — Kata 9: SQLite Repository

## Concept

Your `OrderRepo` interface has been waiting for this moment. You designed
it generically — `find` and `save` as fields on a record — *precisely so*
the implementation could change without touching the use case. Until
now the only implementation has been an in-memory actor; restart the
process and every order vanishes. Time to make it real.

The kata: write `pub fn sqlite(connection) -> OrderRepo` that satisfies
the same `OrderRepo` interface, backed by a SQLite database. **No other
file in the system changes.** Same `place_order.run`, same handler, same
tests using `in_memory` — none of them know the difference.

That sentence is the promise of the repository pattern, in concrete
form. If you find yourself touching the use case to make this work,
the design has drifted somewhere upstream and you should fix that
first.

## Why SQLite is the right choice for a learning project

- **Zero infrastructure.** No daemon, no `docker compose`, no port to manage. Just a file path (or `:memory:` for tests).
- **Real SQL.** You'll write `CREATE TABLE`, deal with parameter binding, decode rows. The lessons transfer to Postgres directly — same library shape (`pog` instead of `sqlight`), same testing model, same patterns.
- **Per-test isolation is trivial.** `sqlight.open(":memory:")` per test gives you a fresh DB; no fixtures, no rollback ceremony.
- **Single-file storage** for production. Backups are `cp`. Suitable for a real app with one writer.

The thing SQLite is *bad* at — concurrent writers across processes — isn't a kata concern, but it's worth knowing for real apps. (One process, many readers + one writer, is fine. Many writers across processes is where you reach for Postgres.)

## The interesting design problem

`Order` is opaque. `OrderLine` is *fully* private to `order.gleam` —
the type doesn't even exist outside the module. So when the SQLite
adapter loads a row from the database, it can't just construct an
`Order` from raw fields. There is no public constructor that takes
`(id, customer_id, lines, status)`.

You have two ways out:

1. **Replay the public API on load** — call `order.new(id, cid)`, then
   `order.add_line(...)` per line, then `order.place(...)` if the
   status was `Placed`. This works *but* the public API emits events
   (`OrderCreated`, `LineAdded`, `OrderPlaced`). Loading from disk
   shouldn't emit fake events as if the actions are happening fresh.
   Bad.

2. **Punch a small "rehydrate" back door** in `order.gleam` that the
   persistence layer uses but normal application code doesn't. Add
   `pub type OrderSnapshot { ... }` and `pub fn snapshot(o) ->
   OrderSnapshot` / `pub fn restore(s) -> Order`. The snapshot
   exposes the internal state in a controlled, public shape (without
   leaking the actual private types). The repo serializes the
   snapshot to JSON, stores it, decodes it back, calls `restore`.

Option 2 is what every production system that uses opaque aggregates +
state-stored persistence does, eventually. It's a real DDD design
moment: **the public API enforces business invariants on transitions;
the snapshot/restore pair handles persistence**. They're different
concerns; they get different functions.

That's the core lesson of this kata. The SQL is just the vehicle.

---

## New Gleam fundamentals

Three pieces.

### `sqlight` — SQLite from Gleam

```gleam
import sqlight

// Open
let assert Ok(conn) = sqlight.open(":memory:")  // or "file:orders.db"

// DDL — no params, no result
let assert Ok(Nil) = sqlight.exec(
  "CREATE TABLE orders (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
  on: conn,
)

// Parameterized query — INSERT/UPDATE/DELETE
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

`sqlight.text/int/float/bool/blob/null/nullable` build the parameter
values. `decode.string/int/field/...` from `gleam/dynamic/decode` build
the row decoder.

Errors are `sqlight.SqlightError(code, message, offset)` — match on
`code` for specific cases (`Constraint`, `Corrupt`, etc.).

### `gleam/json` — encoding and decoding JSON

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
`decode.field` calls inside a `use` block. The chapter's hints walk
through what an `Order`-shaped decoder looks like.

#### Tip: the LSP can write the boilerplate for you

Recent versions of the Gleam language server expose **"Generate
to-json function"** and **"Generate decoder"** as code actions. Put
your cursor on a type definition (the `pub type Foo { ... }` line),
trigger code actions in your editor (`⌘.` / `Ctrl+.` in VS Code,
`<space>a` in Helix, `<leader>ca` in most nvim setups), and pick the
generator. The LSP writes a `pub fn foo_to_json` and / or
`pub fn foo_decoder` next to the type, populated from the field
names and types it can see.

Caveats:

- Only works on the type *definition*, in the file that owns it.
  Outside that module, types are opaque and the LSP can't reach the
  fields.
- Generates encoders/decoders for the immediate type only. Nested
  types referenced in the definition (e.g., `Money`, `Currency`,
  `OrderLine`) need their own generated functions — the generator
  emits `todo` placeholders for types whose encoder/decoder doesn't
  yet exist. You'll be running the action ~5 times to cover the full
  Order tree.
- Generated code is starting-point quality. Read it, rename / restyle
  to match your conventions before committing.

#### And: "no magic" is the feature, not the cost

Other ecosystems do this with derive macros (`#[derive(Serialize)]`),
annotations (`@JsonProperty`), or typeclass instances (`instance
ToJSON`). All of these *hide* the encoder — it's generated at compile
time or via reflection, and you can't see it without expanding macros
or stepping through reflection metadata.

Gleam's choice — write the function, or have the LSP generate it
into your source — costs you a one-time scroll past ~10 lines per
type. In return:

- The encoder is **visible code** you can read, grep, and step
  through. When `to_json` produces wrong output, the bug is in plain
  text in your file, not buried in macro expansion.
- Field renames / additions surface as **compile errors** in your
  encoder, not as silent serialization drift.
- Different types can have different encoding strategies (snake_case
  vs camelCase, omit-empty vs always-include) without invoking
  decorator soup — they're just different functions.
- The encoder works the same whether the bytes go to JSON, MessagePack,
  log lines, or test fixtures. **No format-specific magic to learn.**

The tax is real (more typing) and the benefit is real (no surprises).
Most Gleam programmers come to like it. Worth knowing the LSP exists
to take the keystroke pain out of the boilerplate.

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

Two key design notes:

- **`restore` is total.** It assumes the snapshot is valid (because it came from `snapshot`, which only produces valid snapshots from valid orders). The persistence layer's job is to ensure the bytes round-trip correctly; the domain doesn't re-validate.
- **The snapshot uses `LineSnapshot`, a different public type, not the private `OrderLine`.** That keeps `OrderLine` private (no one outside `order.gleam` can construct one directly), while still giving the persistence layer a stable public shape to work with.

`Money` and `OrderStatus` and `OrderId` and `CustomerId` are already
public types; they're fine to embed directly in the snapshot.

---

## Task

Add the dependency:

```sh
gleam add sqlight gleam_json
```

Then create one file and edit one:

### 1. Edit `src/order.gleam` — add the snapshot back door

Add `OrderSnapshot`, `LineSnapshot`, `pub fn snapshot`, `pub fn restore`
as described above. Around 30 new lines. The existing public API stays
unchanged; the snapshot/restore pair is purely additive.

### 2. Create `src/order_repo_sqlite.gleam` — the SQLite adapter

```gleam
pub fn sqlite(conn: Connection) -> Result(OrderRepo, RepoError)
```

Responsibilities:

1. Run schema setup (`CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, data TEXT NOT NULL)`) on connection.
2. Build closures for `find` and `save` that:
   - **find**: query by id; if no row, `Error(NotFound)`; if a row, decode the `data` JSON into an `OrderSnapshot`, call `order.restore`, return `Ok(order)`.
   - **save**: serialize via `order.snapshot` → JSON → `INSERT OR REPLACE INTO orders (id, data) VALUES (?, ?)`. Always returns `Ok(Nil)` on success; map sqlight errors to `RepoError`.
3. Return the `OrderRepo` record.

About 60–80 lines including the JSON encode/decode boilerplate.

### 3. Create `test/order_repo_sqlite_test.gleam`

Same shape as `order_repo_test.gleam` (kata 6). Open `:memory:` per test, build the repo, exercise find/save round-trip, NotFound, overwrite. The whole point: the **same assertions** can run against a SQLite-backed repo because the interface is the same.

Bonus: a `place_order` integration test using a SQLite repo. Should be a copy-paste of the existing integration test with one line changed (the constructor).

---

## Hints — what to do

1. **Schema first, test the schema.** Write the `CREATE TABLE` and run it. Then write a no-op `find` (always returns `NotFound`) and `save` (always succeeds). Make sure the actor-shaped flow runs end to end with the SQLite layer in place. Add real query logic after that scaffold is solid.

2. **JSON encoding is verbose; embrace it.** A `Money` becomes `{"amount": 150, "currency": "USD"}`. A `Currency` becomes a string. An `OrderStatus` becomes a string. A `LineSnapshot` becomes an object. The full encoder is maybe 30 lines and entirely straightforward — just nested `json.object` calls.

3. **Decoders mirror encoders.** For each `json.object([("foo", ...)])` you wrote, there's a `decode.field("foo", ...)` you write. Build small decoders for `Money`, `Currency`, `OrderStatus`, `LineSnapshot`, then compose them into `OrderSnapshot`.

4. **Use `INSERT OR REPLACE` for save.** It handles both insert-new and update-existing in one statement. The aggregate is the unit of save; you always replace the whole row.

5. **`:memory:` per test, not shared.** Each `pub fn ..._test` should open its own connection. Otherwise tests share state and you get flakes.

6. **Watch for `nullable` carefully.** In our schema nothing is null, but if you add optional fields later, `sqlight.nullable(sqlight.text, optional_string)` is the binding helper.

7. **The hardest debugging path is silent JSON drift.** If `snapshot |> encode |> string |> decode |> restore` doesn't round-trip exactly, things fail mysteriously at load time. Write a unit test for the round-trip independently of SQLite — encode an order to JSON, decode it back, assert equality. Catches drift before SQL is even involved.

8. **You'll want to expose the connection.** `pub fn sqlite(conn)` takes an already-open connection rather than opening one itself. That keeps the repo testable (`:memory:` connections in tests, file connections in main) and lets the composition root manage the connection lifecycle.

---

## Walk-through

**The schema is one table:**

```sql
CREATE TABLE IF NOT EXISTS orders (
  id   TEXT PRIMARY KEY,
  data TEXT NOT NULL  -- JSON snapshot of OrderSnapshot
);
```

That's the entire database. One row per order; the row holds the
serialized snapshot. Saving is `INSERT OR REPLACE`; finding is
`SELECT data WHERE id = ?`. No joins, no transactions for the basic
case.

**The find path:**

```
SQL row (data: "{...}")
  → JSON string
  → decode to OrderSnapshot via gleam/json + decode.Decoder
  → order.restore(snapshot) → Order
  → wrap in Ok(...)
```

If `decode` fails, you have a corrupt row. The right answer is
`Error(CorruptRow(reason))` — a specific variant of `RepoError`,
because "the database has bytes I cannot decode into my domain type"
is a real failure mode worth naming. Add `CorruptRow(reason: String)`
to `RepoError` if it's not already there.

**The save path:**

```
Order
  → order.snapshot(o) → OrderSnapshot
  → encode to JSON object
  → json.to_string → "{...}"
  → INSERT OR REPLACE INTO orders (id, data) VALUES (?, ?)
  → Ok(Nil)
```

The id is extracted from the order via the `pub fn id(order)` accessor
you added in kata 6.

**The substitution at the composition root** is one line:

```gleam
// before
let assert Ok(repo) = order_repo.in_memory()

// after
let assert Ok(conn) = sqlight.open("file:orders.db")
let assert Ok(repo) = order_repo_sqlite.sqlite(conn)
```

`place_order.run`, the HTTP handler, the use-case tests — none of them
change. *That* is the design payoff of the repository pattern. Until
you actually do this swap you can't fully feel it; afterwards you can.

---

## Critique

**No schema migrations.** The `CREATE TABLE IF NOT EXISTS` works for the first version of the app. The second version that adds a column needs a migration story (`ALTER TABLE`, version table, etc.). Real apps use a migration tool — `dbmate` or `sqitch` for SQL files; or in Gleam, hand-roll something tiny that tracks applied migrations in a `_migrations` table. Out of scope here.

**No optimistic concurrency control.** Two concurrent saves can race; the second silently overwrites the first. For a single-actor-writes setup (which the in-memory actor model already gives you implicitly) this is fine. For multi-process writes, you'd add a `version INT` column, check it on update, and fail with a `Conflict` variant when stale. Same pattern Postgres / Mongo / DynamoDB use.

**JSON storage is opaque to SQL.** You can't `SELECT * WHERE total > 100` because `total` lives inside the JSON blob. SQLite's `json_extract` function lets you query into the JSON, but it's slow without expression indexes. If you need rich querying, denormalize: split into `orders` + `order_lines` tables (the schema design discussed in the chapter on `Shape`-vs-DB-storage). The lesson on the rehydration back door doesn't change.

**No streaming, no batch operations.** `find_all`, `find_by_customer`, paginated reads — all out of scope but trivial extensions. Each one adds a new field to `OrderRepo` and a new closure in the constructor.

**The connection is a single shared resource.** SQLite handles one writer; multiple opens to the same file work but write-serialization happens at the OS level. For real apps, wrap the `sqlight.Connection` in an actor that serializes access, or use `sqlite3`'s WAL mode (the connection setting `PRAGMA journal_mode=WAL`).

**`restore` trusts the snapshot.** A bad row could produce an `Order` whose state violates aggregate invariants. The current `restore` doesn't re-check; it builds the record directly. Defensible because the snapshot came from a valid order originally; risky because a hand-edited row or migration bug could slip through. A paranoid `restore` would re-run invariants — but the cost is it would have to use the public API (re-emitting events) or duplicate validation logic. Pick one tradeoff and document it.

---

## DDD takeaway

You've now experienced what the repository pattern was actually for.

When you wrote `OrderRepo` as a record of two functions in kata 6, the
in-memory implementation made the architecture *plausible*. Switching
to SQLite without touching the use case makes it *real*. Same
`place_order.run`, same HTTP handler, same scenario tests — none of
them noticed.

The deeper point: **your domain code never learned what storage looks
like.** Not because of discipline; because the type system literally
gave it no way to find out. That's how you build systems that survive
the inevitable storage migration five years from now.

The other thing this kata teaches that no in-memory adapter can: the
*serialization boundary* is its own design problem. The
snapshot/restore pair is the right Gleam pattern for it. Other
languages reach for `@JsonSerializable` annotations or reflection-based
ORMs; Gleam asks you to write the encoder by hand and benefits from
the explicitness — when the schema drifts, you see exactly which
function to update.

---

## What's next

You now have:

- A typed domain (kata 1–4)
- Events as facts (kata 5)
- Repositories as interfaces (kata 6)
- Bounded contexts (kata 7)
- HTTP boundary + composition root (kata 8)
- Real persistence (this kata)

That's a complete production-shape backend stack, in idiomatic Gleam,
with the type system enforcing the architecture. Everything beyond is
specialization.

The next chapter (the last in this book) is **practical advice for
shipping with these patterns** — what experience teaches that the
katas don't, what to skip, when to escalate from one pattern to the
next, and how to keep the codebase from drifting back into the soup
the patterns exist to prevent.
