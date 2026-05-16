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

<!-- this can be a "tip" callout or whatever it's called:  -->
> Remember: 
> Environment variables always arrive as strings

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

Once it's hooked up, test by hand:

```sh
# Start with SQLite, create an order
ORDER_REPO=sqlite gleam run &
curl -X POST "http://localhost:8080/orders?order_id=ORDER-001&customer_id=CUST-1"
curl http://localhost:8080/orders/ORDER-001  # confirm it's there
kill %1

# Restart and check the order survived
ORDER_REPO=sqlite gleam run &
curl http://localhost:8080/orders/ORDER-001  # still there
kill %1
```

If the second `curl` returns the order, the wiring is done. A 404 means
something in the save path isn't writing to disk.

Inspect the SQLite db file directly to confirm:

```sh
sqlite3 orders.db 'SELECT id, length(data) FROM orders;'
```

---

## Hints: what to do

1. Read env vars at the top of `main`, once, not scattered around the
   codebase. `envoy.get` inside a handler or a use case means
   configuration has leaked downward. Pull it back to `load_config`
   and pass typed values through `Deps`.

2. Defaults live in `load_config`, not in `build_repo`. By the time
   `build_repo` runs, the backend choice is decided. If `build_repo`
   had to handle "no backend specified" it would have two jobs
   (parsing plus constructing); separating them keeps each function
   small.

3. Fail loudly on bad config. The kata version matches `"memory"` and
   `"sqlite"`, falling back to `InMemory` for anything else, including
   unset. That works for learning. In a real deployment,
   `ORDER_REPO=sqlight` (typo) launches an in-memory repo and discards
   every request's data after the first restart. The production-grade
   `load_config` distinguishes "unset, default" from "set to garbage,
   crash with a clear message." The critique section returns to this.

4. The factory returns `Result`, not panics. `let assert Ok(...)` is the
   caller's choice. `build_repo` returns a value so tests can exercise it
   without crashing the test runner.

5. Don't make `Config` a global. Pass it in. The function that needs
   the port reads `config.port`; the function that builds the repo
   reads `config.repo`. No top-level mutable state.

6. Connection lifetime is process lifetime. Open the SQLite
   connection once at startup, hand it to the repo, and don't close
   it, since the OS closes it on process exit. (Tests open `:memory:` per
   test, as kata 9 already established.)

7. `ORDER_REPO` lowercase or uppercase? Pick one. Lowercase (`memory`,
   `sqlite`) is friendlier for shell scripts; uppercase (`MEMORY`,
   `SQLITE`) is the older Unix convention. Be consistent, and reject
   unrecognized values rather than guessing.

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

No validation here, and no error path out. The function is total, because any
environment produces a `Config`, which keeps `main` straight-line code.

**`build_repo`** is the function from "New Gleam fundamentals" above. It is
the *one* place that turns a typed `RepoBackend` into a running `OrderRepo`,
with all error paths funneled to `Result(_, String)` for the composition root
to panic on.

**`main` becomes choreography:**

```gleam
let config = load_config()                       // env → typed
let assert Ok(repo) = build_repo(config.repo)    // typed → adapter
let deps = router.Deps(order_repo: repo)         // adapter → bundle
let handle = router.handle(deps, _)              // bundle → handler
// ... start Mist on config.port ...
```

Each line has one job and each function name reads like what it does. The
boundary between "parse the world" and "do work" sits in the first three
lines.

`let assert Ok(repo) = build_repo(config.repo)` is the *only* place this file
panics on adapter construction. Everything below that line, including tests
and alternate entry points, takes the constructed repo as a value. The
fail-on-startup pattern lives in one location.

---

## Critique

Env vars work fine for one-process apps and stop scaling once the deployment
grows. Multi-deployment setups across dev, staging, and prod (with secret
rotation and live reconfiguration) push toward a config file, a config service
like Consul or etcd, or a cloud secrets manager. The shape of `load_config`
doesn't change; the source does. `envoy.get` becomes `config_file.read` or
`secrets_manager.fetch`, and the typed `Config` flows through the rest of the
app unchanged. The typed-config boundary pays back here.

No file-path validation here. `Sqlite("/no/such/dir/orders.db")` won't fail
until `sqlight.open` runs, so the error message arrives at the right moment,
and pre-validation would duplicate the open logic.

The tests don't use the factory. `test/order_repo_sqlite_test.gleam`
constructs the repo directly with `sqlight.open(":memory:")`, which is correct
for unit tests of the adapter. A separate integration test for `load_config`
and `build_repo` together (set env vars, call the functions, assert the right
type came out) would prove the wiring works end-to-end. Worth adding as the
config surface grows.

No migration story yet. The SQLite repo's `CREATE TABLE IF NOT EXISTS` works
for v1, but the day a `version INT` column joins the snapshot shape, a
migration becomes necessary. Out of scope here; the next chapter touches it
under "what's beyond the foundation."

Falling back to `InMemory` on an unrecognized `ORDER_REPO` is a bug magnet. A
typo in the deploy config (`ORDER_REPO=sqlight` instead of `sqlite`) yields a
fresh in-memory repo on every restart. The clean fix logs a warning or errors
out on any non-empty unrecognized value. The kata's `case ... _ -> InMemory`
is the minimum; the production version distinguishes "unset" from "set to
garbage."

SQLite handles concurrent reads but serializes writes through a single
connection. For this app shape, one Mist process with one writer, that works
fine. Real load pushes toward WAL mode (`PRAGMA journal_mode=WAL`) so reads
don't block while a write is in flight, or a connection wrapper that
serializes through an actor. Both are mechanical additions when the need
arrives.

---

## DDD takeaway

Configuration is a boundary like HTTP. Untyped strings arrive at the edge, a
parser turns them into typed values, and everything downstream works with the
typed form. The HTTP handler does this for request bodies; `load_config` does
it for env vars.

Keeping the untyped world at the edges earns its keep over time more than the
domain model itself or the repository pattern. A string or `Dynamic` value
that leaks past `main.gleam` is a future bug; a sum type that meets a
stringly-typed flag downstream is a future refactor. Configuration is one
more input channel that needs the same treatment.

Here the cost of the patterns starts to pay back. The in-memory repo was not
*only* a teaching tool; it serves as a real adapter that runs the test suite
and local development. The SQLite repo slots in behind the same `OrderRepo`
interface, and the use case and handler above it cannot tell the two apart.
The composition root is the one file that knows the difference, so the
architecture earns its keep.

---

## What's next

The next and final chapter, *Putting It Into Practice*, distills the
experience of shipping software with these patterns: what to reach for on
Monday morning, what to skip, when to escalate from one pattern to the next,
and how to discuss any of it with colleagues who haven't read the book. The
katas teach the patterns; the closing chapter covers application.
