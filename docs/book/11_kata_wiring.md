# 11 — Kata 10: Wiring and Configuration

## Concept

You built the SQLite adapter in kata 9 and tested it in isolation. It
works. It's also sitting on a shelf. The composition root in
`gleamlang_katas.gleam` still says:

```gleam
let assert Ok(repo) = order_repo.in_memory()
```

That single line is the part of the architecture you haven't actually
exercised. The whole point of the repository pattern was *swap the
implementation without touching anything downstream* — and you've never
actually performed the swap.

This kata does it. Twice:

1. **Wire the SQLite adapter in.** Replace one constructor call with
   another. Verify orders persist across `gleam run` restarts. *That* is
   when the architecture becomes real to you — until you've watched data
   survive a process exit, the in-memory and SQLite implementations are
   indistinguishable in practice.

2. **Make the choice runtime configurable.** A single deployable that
   reads `ORDER_REPO=memory|sqlite` from the environment and constructs
   the right adapter. This is what "configuration as a typed value"
   looks like in working code — and it forces three small design
   decisions: sum type vs string flag, factory function vs inline
   construction, and where to fail fast.

## Why this is more than a one-line change

The diff is small. The design content isn't.

Kata 9 taught you to *build* an adapter. This kata teaches you to
*choose between adapters at runtime* — a different skill. The factory
pattern, the `Config` value object, env-driven backend selection,
error-type unification at the composition root — these are the things
every production Gleam app needs and that the book hasn't covered yet.

There's also a payoff moment worth slowing down for: the first time
you watch data survive `kill %1; gleam run`. The architecture diagram
you've been drawing in your head for nine katas finally has a running
counterexample to "in-memory state is fine, what could go wrong?"

---

## New Gleam fundamentals

Three small additions.

### `envoy` — env var access

```gleam
import envoy

envoy.get("ORDER_REPO")  // -> Result(String, Nil)
```

That's the entire API surface that matters. `Result(_, Nil)` because
"env var not set" is the only failure mode, and it has no detail
beyond *not set*. The standard idiom for "default if missing":

```gleam
envoy.get("PORT")
|> result.try(int.parse)
|> result.unwrap(8080)
```

Read → parse → fall back. Each step is one line.

### Sum types as configuration

The wrong shape:

```gleam
pub type Config {
  Config(repo_kind: String, db_path: String)
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

After `load_config` returns, no other code has to ask "is the string
`repo_kind` actually one of the known values?" That question was
answered once, at the parse boundary, and the type system carries the
answer the rest of the way. The `db_path` only exists when the variant
is `Sqlite` — meaning you can't accidentally read it when the backend
is `InMemory`.

**This is the same shape as parsing HTTP input.** Untyped strings come
in at the edge. A parser turns them into typed values. Typed values
flow through the system. The HTTP boundary does it for request bodies;
the config boundary does it for env vars. Same idea, different input
source.

### The factory function pattern

One function that takes the typed backend choice and produces a
running adapter:

```gleam
fn build_repo(backend: RepoBackend) -> Result(OrderRepo, String) {
  case backend {
    InMemory ->
      order_repo.in_memory()
      |> result.map_error(string.inspect)

    Sqlite(path) -> {
      use conn <- result.try(
        sqlight.open(path) |> result.map_error(string.inspect)
      )
      order_repo_sqlite.sqlite(conn) |> result.map_error(string.inspect)
    }
  }
}
```

Three things to internalize:

1. **One function, one decision.** `build_repo` is the *only* place in
   the codebase that knows how to construct any backend. Add a Postgres
   adapter later, you change one function. Nothing else.
2. **Error types are unified to `String` here.** `actor.StartError`
   and `sqlight.Error` don't share an ancestor; the composition root is
   the natural place to flatten them. `string.inspect` is pragmatic at
   this layer — the only thing that consumes the error is the human
   reading the panic message.
3. **`use ... <- result.try` chains adapter construction.** Opening the
   connection can fail. Building the repo from the connection can fail.
   Both errors flow out the same channel.

---

## Task

### 1. Add the dependency

```sh
gleam add envoy
```

### 2. Add `RepoBackend` and `Config` types

In `gleamlang_katas.gleam` (the composition root). Sum type for the
backend choice, record for the bundled config.

### 3. Implement `load_config`

Read `ORDER_REPO` and `ORDER_DB` (and `PORT` while you're there). Map
to typed values. Defaults: `InMemory` if `ORDER_REPO` is unset or
unrecognized, `"orders.db"` if `ORDER_DB` is unset, `8080` if `PORT`
is unset or unparseable.

### 4. Implement `build_repo`

The factory above. Takes a `RepoBackend`, returns
`Result(OrderRepo, String)`.

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
orders.db-journal
orders.db-wal
orders.db-shm
```

Don't commit the database. SQLite produces sidecar files (WAL, shared
memory) in some modes; ignore them all.

### 7. Verify persistence

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

If the second `curl` returns the order, the kata is done. If it
returns 404, something in your save path isn't actually writing to
disk. Sanity-check by inspecting the SQLite file directly:

```sh
sqlite3 orders.db 'SELECT id, length(data) FROM orders;'
```

---

## Hints — what to do

1. **Read env vars at the top of `main`, once.** Not scattered around
   the codebase. The pattern `envoy.get` inside a handler or a use case
   means configuration has leaked downward. Pull it back to
   `load_config` and pass typed values through `Deps`.

2. **Defaults live in `load_config`, not in `build_repo`.** By the time
   `build_repo` runs, the backend choice is already decided. If
   `build_repo` had to handle "no backend specified" it would have two
   jobs (parsing + constructing); separating them keeps each function
   small.

3. **Fail loudly on bad config — eventually.** The kata version
   matches `"memory"`, `"sqlite"`, and falls back to `InMemory` for
   anything else (including unset). That's fine for learning. But in a
   real deployment, `ORDER_REPO=sqlight` (typo) silently launches an
   in-memory repo and quietly throws every request's data on the floor
   after the first restart. The production-grade version of
   `load_config` distinguishes "unset → default" from "set to garbage
   → crash with a clear message." The critique section returns to
   this.

4. **The factory returns `Result`, not panics.** `let assert Ok(...)`
   is a *caller* choice. `build_repo` returns a value so tests can
   exercise it without crashing the test runner.

5. **Don't make `Config` a global.** Pass it in. The function that
   needs the port reads `config.port`; the function that builds the
   repo reads `config.repo`. No top-level mutable state.

6. **Connection lifetime is process lifetime.** Open the SQLite
   connection once at startup, hand it to the repo, never close it
   explicitly. The OS closes it on process exit. (Tests open
   `:memory:` per test, as kata 9 already established.)

7. **`ORDER_REPO` lowercase or uppercase?** Pick one. Lowercase
   (`memory`, `sqlite`) is friendlier for shell scripts; uppercase
   (`MEMORY`, `SQLITE`) is the older Unix convention. Be consistent.
   Reject unrecognized values rather than guessing.

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

Notice what's *not* here: validation, logging, error returns. This
function is total — given any environment, it produces a `Config`.
That keeps `main` straight-line code.

**`build_repo`** is the function from "New Gleam fundamentals" above.
Read it again now that you have the context: it's the *one* place that
turns a typed `RepoBackend` into a running `OrderRepo`, with all error
paths funneled to `Result(_, String)` for the composition root to
panic on.

**`main` becomes choreography:**

```gleam
let config = load_config()                       // env → typed
let assert Ok(repo) = build_repo(config.repo)    // typed → adapter
let deps = router.Deps(order_repo: repo)         // adapter → bundle
let handle = router.handle(deps, _)              // bundle → handler
// ... start Mist on config.port ...
```

Each line has one job. Each function name reads like what it does. The
boundary between "parse the world" and "do work" is the first three
lines.

**One detail to look at on a second read:** `let assert Ok(repo) =
build_repo(config.repo)` is the *only* place this whole file panics on
adapter construction. Tests, alternate entry points, anything below
this line — they all take the *constructed* repo as a value. The fail-
on-startup pattern lives in exactly one location.

---

## Critique

**Env vars are a fine config source for one-process apps; they don't
scale.** Multi-deployment setups (dev/staging/prod), secret rotation,
runtime reconfiguration — all push you toward a config file, a config
service (Consul, etcd), or a cloud secrets manager. The *shape* of
`load_config` doesn't change; the source does. `envoy.get` becomes
`config_file.read` or `secrets_manager.fetch`, and the typed `Config`
flows through the rest of the app unchanged. That's the payoff of the
typed-config boundary.

**No file-path validation.** `Sqlite("/no/such/dir/orders.db")` doesn't
fail until `sqlight.open` runs. That's actually fine — fail-on-open is
the simplest pattern and gives you a clear error message at the right
moment. Pre-validation would duplicate the open logic. Skip it.

**Tests don't use the factory.** `test/order_repo_sqlite_test.gleam`
constructs the repo directly with `sqlight.open(":memory:")`. That's
correct for *those* tests — they're unit tests of the adapter. A
separate integration test for `load_config` and `build_repo` together
(set env vars, call the functions, assert the right type came out)
would prove the wiring works end-to-end. Worth adding as you grow the
config surface.

**No migrations.** The SQLite repo's `CREATE TABLE IF NOT EXISTS` is
fine for v1. The day you add a `version INT` column to the snapshot
shape, you need a migration story. Out of scope here; covered in the
next chapter under "what's beyond the foundation."

**Falling back silently to `InMemory` on unrecognized `ORDER_REPO` is
a bug magnet.** A typo in the deploy config (`ORDER_REPO=sqlight`
instead of `sqlite`) gets you a fresh in-memory repo on every restart.
The clean fix: log a warning, or error out, on any non-empty
unrecognized value. The kata's `case ... _ -> InMemory` is the
minimum; the production version distinguishes "unset" from "set to
garbage."

**One process, one connection.** SQLite handles concurrent reads but
serializes writes through a single connection. For this app shape
(one Mist process serving requests, single writer) that's fine. Real
load would push you toward WAL mode (`PRAGMA journal_mode=WAL`) so
reads don't block while a write is in flight, or a connection wrapper
that serializes through an actor. Both are mechanical additions when
the need is real.

---

## DDD takeaway

Configuration is a boundary, exactly like HTTP. Untyped strings come
in at the edge. A parser turns them into typed values. Typed values
flow through the rest of the system. The HTTP handler does this for
request bodies; `load_config` does it for env vars. Same pattern,
different source.

The architectural shape that earns its keep over time isn't the
domain model or even the repository pattern — it's **the discipline of
keeping the untyped world at the edges.** Every place where a string
or a `Dynamic` value leaks past `main.gleam` is a future bug. Every
place where a sum type meets a stringly-typed flag is a future
refactor. Configuration is just another input channel that needs the
same treatment.

This is also where the cost of the patterns starts to pay back. The
in-memory repo wasn't *only* a teaching tool — it's a real adapter
that runs in tests, in development, and in CI. The SQLite repo is the
production adapter. Same interface, same use case, same handler. The
only file that knows the difference is the composition root. **That's
the architecture working.**

---

## What's next

The final chapter — *Putting It Into Practice* — distills the
experience of shipping software with these patterns: what to do on
Monday morning, what to skip, when to escalate from one pattern to
the next, how to talk about all of this with colleagues who haven't
read the book. The katas teach the patterns. The last chapter teaches
the judgment.
