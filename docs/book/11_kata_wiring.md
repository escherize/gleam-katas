# 11. Kata 10: Wiring and Configuration

Kata 9 built and tested the SQLite adapter in isolation. Time to hook it up.

`gleamlang_katas.gleam` still says:

```gleam
let assert Ok(repo) = order_repo.in_memory()
```

Two `OrderRepo`s exist now, one in an actor and one over sqlite, so the
implementation swaps without touching anything downstream.

To test the SQLite wiring, save an order, restart the server, and `GET` the
order back. The `OrderRepo` choice also becomes configurable from the command
line.

Either via:

```
ORDER_REPO=in_memory
```
or
```
ORDER_REPO=sqlite
ORDER_DB=my_orders.db
```

## New Tricks

### `envoy` handles env var access

```gleam
import envoy

envoy.get("MY_ENV_VAR")  // -> Result(String, Nil)
```

`envoy.get` returns `Ok(String)` when the env var has a value, and `Error(Nil)` when it doesn't.

> Environment variables always arrive as strings.

Result-handling composes with it the usual way:

```gleam
envoy.get("PORT")
|> result.try(int.parse) // it should become an int
|> result.unwrap(8080) // default value
```

### Organizing the Config

The wrong shape:

```gleam
pub type Bad_Config {
  Bad_Config(repo_kind: String, db_path: String)
  //     ^^^^^^^^ stringly typed; needs validation everywhere it's used
}
```

The right shape:

```gleam
pub type RepoBackend {
  InMemory
  Sqlite(path: String)
}

pub type Config {
  Config(repo: RepoBackend, port: Int)
}
```

`Bad_Config` is harder to use, since the type system cannot help you set it up
correctly. You'd have to scan the code for valid values of `repo_kind`.

Reading the `Config` definition explains what it can be, and hints at how
callers will use it. The `db_path` only exists when the variant is `Sqlite`,
so you can't accidentally read it when the backend is `InMemory`.

This is the cleanest example of "make illegal states unrepresentable" in
the whole book. `Bad_Config` lets `("in_memory", "/some/path.db")` exist as
a value even though the path is meaningless without `sqlite`; the typed
`RepoBackend` makes that pairing un-constructable. The slogan from Kata 1
applied to configuration.

The shape mirrors HTTP input parsing. Untyped strings arrive, a parser turns
them into typed values, and the typed values flow through the system.

> Note:
> Extending this to connect to postgres adds the connection uri, or the
> host_name and db name, as fields of a Postgres variant of RepoBackend.
> Something like:

```gleam
pub type ExtendedRepoBackend {
  InMemory
  Sqlite(path: String)
  PostgresURI(uri: String)
  PostgresParts(host_name: String, db_name: String, ...)
}
```

### Config -> Repo

A config value passes into a function that produces a running adapter.

```gleam
fn build_repo(backend: RepoBackend) -> Result(OrderRepo, String) {
  case backend {
    InMemory ->
      order_repo.in_memory()
      |> result.map_error(string.inspect)

    Sqlite(path) -> {
      // opening a connection can fail:
      use conn <- result.try(
        sqlight.open(path) |> result.map_error(string.inspect)
      )
      order_repo_sqlite.sqlite(conn) |> result.map_error(string.inspect)
    }
  }
}
```

`Error` types collapse to `String` here. `actor.StartError` and `sqlight.Error`
don't share an ancestor, so the composition root flattens them. `string.inspect`
works at this layer, since the only consumer of the error is a human (or agent)
reading the panic message.

---

## Task

### 1. Add the dependency

```sh
gleam add envoy
```

### 2. Add `RepoBackend` and `Config` types

In `gleamlang_katas.gleam` read the config, and turn it into an `OrderRepo`.

### 3. Implement `load_config`

#### Env vars

Read `ORDER_REPO` and `ORDER_DB`, and `PORT` into typed values.

##### Order Repo

Default to `InMemory` when `ORDER_REPO` is unset. Crash if the value is set
and invalid.

`ORDER_DB` defaults to `"orders.db"`.

##### Port

Default Port: `8080`. An unparsable value should crash.

### 4. Implement `build_repo`

The factory given above, but try doing it without looking.

Its signature is `fn(RepoBackend) -> Result(OrderRepo, String)`

### 5. Update `main`

```gleam
pub fn main() -> Nil {
  let config = load_config()
  let assert Ok(repo) = build_repo(config.repo)
  let deps = router.Deps(order_repo: repo)
  let handle = router.handle(deps, _)
  let secret = wisp.random_string(64)
  let assert Ok(_) =
    wisp_mist.handler(handle, secret)
    |> mist.new
    |> mist.port(config.port)
    |> mist.start
  process.sleep_forever()
}
```

### 6. Update `.gitignore`

```
orders.db
orders.db*
```

Don't commit the database. The glob also covers SQLite's sidecar files.

### 7. Verify persistence

The Hurl scripts from chapter 09 (`dev/hurl/`) do the round-trip
without any per-step `kill`/`restart` choreography:

```sh
# 1. start with SQLite, create + read one order
ORDER_REPO=sqlite gleam run &
hurl --test --variables-file dev/hurl/vars.env dev/hurl/create.hurl
hurl --test --variables-file dev/hurl/vars.env dev/hurl/get.hurl
kill %1

# 2. restart, prove the order survived
ORDER_REPO=sqlite gleam run &
hurl --test --variables-file dev/hurl/vars.env dev/hurl/get.hurl
kill %1
```

If the second `get.hurl` passes, the wiring is done. A 404 means
something in the save path isn't writing to disk.

Without Hurl, the same shape with curl:

```sh
ORDER_REPO=sqlite gleam run &
curl -X POST "http://localhost:8080/orders?order_id=ORDER-001&customer_id=CUST-1"
curl http://localhost:8080/orders/ORDER-001
kill %1
```

Inspect the SQLite file directly to confirm bytes landed:

```sh
sqlite3 orders.db 'SELECT id, length(data) FROM orders;'
```

---

## Hints: what to do

1. Read env vars at the top of `main`, once. `envoy.get` inside a handler or use case means configuration has leaked downward; pull it back to `load_config` and pass typed values through `Deps`.

2. Defaults live in `load_config`, not in `build_repo`. By the time `build_repo` runs, the backend choice is decided. Splitting parsing from construction keeps each function small.

3. The factory returns `Result`, not panics. `let assert Ok(...)` is the caller's choice. `build_repo` returns a value so tests can exercise it without crashing the test runner.

4. Open the SQLite connection once at startup, hand it to the repo, and don't close it. The OS closes it on process exit. (Tests open `:memory:` per test, as kata 9 established.)

5. Pick a case convention for `ORDER_REPO` values (lowercase reads as more shell-friendly) and reject unrecognized values rather than guessing. The Critique section returns to this.

---

## Walk-through

**`load_config`:**

```gleam
import envoy
import gleam/int
import gleam/result

fn load_config() -> Config {
  let repo = case envoy.get("ORDER_REPO") {
    Ok("sqlite") -> {
      let path = envoy.get("ORDER_DB") |> result.unwrap("orders.db")
      Sqlite(path)
    }
    Ok("memory") -> InMemory
    Error(Nil) -> InMemory       // unset: default
    Ok(_) -> InMemory            // unrecognized: see critique
  }

  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(8080)

  Config(repo: repo, port: port)
}
```

The function is total, since any environment produces a `Config`,
which keeps `main` straight-line.

**`build_repo`** is the factory from "New Gleam fundamentals." It's
the one place that turns a typed `RepoBackend` into a running
`OrderRepo`, with all error paths funneled to `Result(_, String)`.

**`main` becomes choreography:**

```gleam
let config = load_config()                       // env → typed
let assert Ok(repo) = build_repo(config.repo)    // typed → adapter
let deps = router.Deps(order_repo: repo)         // adapter → bundle
let handle = router.handle(deps, _)              // bundle → handler
// ... start Mist on config.port ...
```

The boundary between "parse the world" and "do work" sits in the
first three lines, and the `let assert Ok` on line 2 is the only
place this file panics on adapter construction.

---

## Critique

Env vars suit one-process apps and stop scaling past dev/staging/prod
with secret rotation. The source then becomes a config file or
secrets manager, but the shape of `load_config` doesn't change:
`envoy.get` becomes `secrets_manager.fetch`, and the typed `Config`
flows through unchanged. The typed-config boundary pays back here.

File paths aren't validated up front. `Sqlite("/no/such/dir/orders.db")`
doesn't fail until `sqlight.open` runs, which is the right moment for
the error to arrive; pre-validation would duplicate the open logic.

Falling back to `InMemory` on an unrecognized `ORDER_REPO` is the
worst bug in the kata. A typo (`ORDER_REPO=sqlight`) yields a fresh
in-memory repo on every restart, silently. Production code should log
a warning or refuse to start on any non-empty unrecognized value, so
that "unset" and "set to garbage" land on different code paths.

Migrations and concurrency are out of scope. `CREATE TABLE IF NOT EXISTS`
works for v1; the day a `version INT` column joins, a migration tool
becomes necessary. SQLite serializes writes through one connection,
which suits one Mist process; heavier load wants WAL mode or an actor
that serializes connection access. Both are mechanical additions when
they matter.

The tests don't exercise the factory end to end. `order_repo_sqlite_test`
constructs the repo directly, which is right for unit tests; an
integration test that sets env vars and asserts the right `Config` and
`OrderRepo` come out would prove the wiring as the config surface
grows.

---

## Takeaway

Configuration is a boundary like HTTP. Untyped strings arrive at the
edge, a parser turns them into typed values, and everything downstream
works with the typed form. The HTTP handler does this for request
bodies; `load_config` does it for env vars.

Keeping the untyped world at the edges earns its keep over time more
than the domain model itself or the repository pattern. A `Dynamic`
that leaks past `main.gleam` is a future bug; a sum type meeting a
stringly-typed flag downstream is a future refactor. The in-memory
repo from kata 6 was never only a teaching tool, since it runs the
test suite and local development. The SQLite repo slots in behind the
same interface, and the layers above can't tell which is which. The
composition root is the one file that knows.

---

## What's next

The next and final chapter, *Putting It Into Practice*, distills the
experience of shipping software with these patterns: what to reach for on
Monday morning, what to skip, when to escalate from one pattern to the next,
and how to discuss any of it with colleagues who haven't read the book. The
katas teach the patterns; the closing chapter covers application.
