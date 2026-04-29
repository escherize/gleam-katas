# 07 — Kata 6: Repositories

## Concept

The aggregate has been pure all along. It takes a state and a command,
returns a new state and events. Beautiful — and useless if it doesn't
survive a process restart.

A **repository** is the interface that turns an aggregate type into
something you can load and save. The domain depends on the *interface*
(a port); the *implementation* (an adapter) lives in the infrastructure
layer. Nothing in `order.gleam` learns what storage looks like.

Two consequences:

1. **Use cases become testable without infrastructure.** Place an order, load it
   back, assert on the events — no DB, no fixtures.
2. **Storage strategy is pluggable.** In-memory dict on Tuesday, Postgres on
   Wednesday — same use-case code on top.

The key DDD discipline: **one repository per aggregate**, not per
entity. You save an `Order`, not an `OrderLine`. The aggregate is the
consistency unit; the repo's contract is "give me back a valid one or
fail."

## What you load is what you trust

The repository's other job is to put loaded data back through the smart
constructors. Reading a row gives you raw fields; turning those into a
typed `Order` goes through `email.new`, `customer.new_id`, etc. — the
same validation that keeps HTTP input honest. **A corrupt row is
`Error(CorruptRow(...))`, not a thrown exception.**

This is why the kata 1 ceremony pays off compounded here. Every layer
that reconstructs trusts the type, because every layer that constructs
went through the smart constructor. There is no "but I got it from the
database, so I trust it" backdoor.

## The use case is the orchestrator

A use case is a function that does one thing the application supports:
"place an order." The shape:

```
load via repo → call domain → save via repo → return events
```

Each step can fail, with a *typed* error. The use case wraps repo
errors and domain errors in a `PlaceOrderError` so callers know which
layer broke. This pulls together every chaining pattern from earlier
katas — `result.try` from Kata 3, the wrap-the-cause idea from Kata 5.

The payoff: **the use case is the application boundary.** Above it,
HTTP / CLI / message handlers translate to and from this type. Below
it, the domain. The use case is where you can write a test that says
"given these inputs, this is what happens" without spinning up
infrastructure.

---

## New Gleam fundamentals

### Records of functions

A type whose fields are *functions* is a perfectly normal Gleam type.
Used here as an interface:

```gleam
pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
  )
}
```

A `Customer` and an `OrderRepo` are the same kind of value. The
difference is what's inside the fields. Callers don't care:

```gleam
let order = repo.find(id)
```

That's the entire pattern. No `IFooRepository<Order>`, no DI container,
no annotations. **A type with function fields is the interface.**

### Why we need OTP

Gleam has no globals, no `let mut`, no static fields. State that
survives across function calls has to live somewhere — and the
somewhere is a *process*.

A process is a lightweight Erlang thread with a mailbox. You send it
messages; it processes them one at a time. Its state is a value it
threads through the message loop. From outside, you never see the state
— you only see responses to your messages.

This is the OTP model in one sentence. For a repository, the process
holds a `Dict(OrderId, Order)`; messages ask "find this id" or "save
this order"; the process replies with the answer.

### OTP, just enough

Five vocabulary words is all you need:

- **`Dict(k, v)`** — immutable hash map. `dict.new()`, `dict.get(d, k) -> Result(v, Nil)`, `dict.insert(d, k, v) -> Dict(k, v)`. From `gleam/dict`.
- **`Subject(msg)`** — typed mailbox / address-of-process. You hold a `Subject(Find(...) | Save(...))` to send messages to a particular actor.
- **`actor.new(initial_state) |> actor.on_message(handler) |> actor.start`** — build and start. Returns `Result(Started(Subject(msg)), StartError)`. The `Started.data` field is the subject you use to send messages from outside.
- **The handler signature**: `fn(state, msg) -> actor.Next(state, msg)`. Returns `actor.continue(new_state)` to loop with new state, or `actor.stop()` to terminate.
- **`process.call(subject, timeout, builder)`** — synchronous request/reply. The `builder` is `fn(reply_subject) -> msg`: you embed a reply subject inside the message; the actor sends its response to that subject; `process.call` blocks until it arrives (or times out).

A worked example for intuition (counter actor):

```gleam
type Msg {
  Get(reply: Subject(Int))
  Set(value: Int, reply: Subject(Nil))
}

fn handle(state: Int, msg: Msg) -> actor.Next(Int, Msg) {
  case msg {
    Get(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
    Set(value, reply) -> {
      process.send(reply, Nil)
      actor.continue(value)
    }
  }
}
```

Substitute `Dict(OrderId, Order)` for `Int`, `Find` and `Save` for
`Get` and `Set`, and you have a repository.

### Wrapping the actor in the interface

The actor's `Subject(Msg)` is an implementation detail. The thing the
use case sees is an `OrderRepo`. Bridge with closures:

```gleam
pub fn in_memory() -> Result(OrderRepo, actor.StartError) {
  use started <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_msg)
    |> actor.start,
  )
  let pid = started.data
  Ok(OrderRepo(
    find: fn(id) { process.call(pid, 100, fn(reply) { Find(id, reply) }) },
    save: fn(o)  { process.call(pid, 100, fn(reply) { Save(o, reply) }) },
  ))
}
```

Each function field is a closure over the actor's subject. Callers
never know the actor exists.

### Error wrapping across layers

When two layers can fail, the cleanest pattern is a small sum type that
*names which layer*:

```gleam
pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}
```

The conversion happens via `result.map_error`, but it relies on a
Gleam fact that's easy to miss: **constructors are functions.** When
you write `pub type PlaceOrderError { RepoFailed(RepoError) | ... }`,
`RepoFailed` is two things at once:

- a *pattern* (used in `case` to destructure: `case e { RepoFailed(inner) -> ... }`)
- a *value of type `fn(RepoError) -> PlaceOrderError`* (used anywhere a function is expected)

`result.map_error` has signature `fn(Result(a, e1), fn(e1) -> e2) -> Result(a, e2)` —
it takes a Result and a function from the old error type to the new
error type, applies the function only on the `Error` branch, and
returns a Result whose error type is whatever the function returns.

Pass `RepoFailed` (a function `fn(RepoError) -> PlaceOrderError`) and
the result's error type becomes `PlaceOrderError`:

```gleam
let r1: Result(Order, RepoError)        = repo.find(id)
let r2: Result(Order, PlaceOrderError)  = r1 |> result.map_error(RepoFailed)
//                                    RepoFailed is the function ^
```

The cause is preserved (the original `RepoError` lives inside the
`RepoFailed` wrapper); the layer is named (callers can pattern-match
on `RepoFailed(_)` vs `DomainFailed(_)` to know which side broke).

Why this matters: `result.try` requires the inner Result and the outer
function's return type to share an error type. Without the
`map_error`, you'd get `Result(_, RepoError)` from the repo but the
outer function returns `Result(_, PlaceOrderError)` — type mismatch.
The `map_error(RepoFailed)` is the conversion that lets the chain
type-check.

---

## Task

Add a small accessor to `src/order.gleam` (the repo needs to extract
the ID from an order to use as a dict key):

```gleam
pub fn id(order: Order) -> OrderId {
  order.id
}
```

Create `src/order_repo.gleam` exposing:

```gleam
pub type RepoError {
  NotFound
  // add more if you discover them
}

pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
  )
}

pub fn in_memory() -> Result(OrderRepo, actor.StartError) {
  todo
}
```

Create `src/place_order.gleam` exposing:

```gleam
pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}

pub fn run(
  repo: OrderRepo,
  id: OrderId,
) -> Result(#(Order, List(OrderEvent)), PlaceOrderError) {
  todo
}
```

Wire `in_memory` to an actor that holds a `Dict(OrderId, Order)`. The
actor handles `Find` and `Save` messages. The use case loads, places,
saves.

Tests in `test/order_repo_test.gleam` (round-trip the repo) and
`test/place_order_test.gleam` (run the use case end-to-end against an
in-memory repo).

---

## Hints — what to do

1. **Design the `OrderRepo` type before writing any code.** Two functions is the minimum (`find`, `save`). Do you also want `delete`? `list_for_customer`? Don't over-design — add when a test needs it.
2. **Design `RepoError` next.** `NotFound` is obvious. What else? `StorageError(reason)` for network/disk failures? `CorruptRow(reason)` for "I have a row but cannot reconstruct an Order"? Keep it small and grow as needed.
3. **`handle_msg` is the only real implementation work in `order_repo`.** Pattern-match on `Find(id, reply)` or `Save(o, reply)`, do the right `dict` op, send the result via `process.send(reply, ...)`, return `actor.continue(new_state)`. Five lines per branch.
4. **The actor's state type goes in the type signature.** `fn handle_msg(state: Dict(OrderId, Order), msg: Msg) -> actor.Next(Dict(OrderId, Order), Msg)`. Verbose, but the compiler enforces consistency.
5. **For `place_order.run`**, three steps in a chain:
   - `use order <- result.try(repo.find(id) |> result.map_error(RepoFailed))`
   - `use #(placed, events) <- result.try(order.place(order) |> result.map_error(DomainFailed))`
   - `use _ <- result.try(repo.save(placed) |> result.map_error(RepoFailed))`
   - `Ok(#(placed, events))`
6. **For tests**, build a small helper that creates a repo and seeds it with an order. Most tests are "set up state; call the use case; assert."
7. **`process.call` blocks the calling process** until the actor replies (or times out). For tests, 100ms is plenty.
8. **`result.replace_error(NotFound)`** is the cleanest way to turn a `Result(Order, Nil)` from `dict.get` into a `Result(Order, RepoError)`.

---

