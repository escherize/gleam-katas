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

1. **Use cases become testable without infrastructure.** Place an order, load it back, assert on the events — no DB, no fixtures.
2. **Storage strategy is pluggable.** In-memory dict on Tuesday, Postgres on Wednesday — same use-case code on top.

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

`result.map_error(RepoFailed)` lifts a `Result(_, RepoError)` to a
`Result(_, PlaceOrderError)`. Same for domain errors. The cause is
preserved; the layer is named. Callers can match on either level.

Note the trick: `RepoFailed` is a one-argument constructor, which means
it *is* a function `fn(RepoError) -> PlaceOrderError`. You pass it
directly to `result.map_error` — no `fn(e) { RepoFailed(e) }` wrapper
needed.

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

pub fn in_memory() -> Result(OrderRepo, actor.StartError)
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
) -> Result(#(Order, List(OrderEvent)), PlaceOrderError)
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

## Solution

```gleam
// src/order_repo.gleam
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import order.{type Order, type OrderId}

pub type RepoError {
  NotFound
  CorruptRow(reason: String)
  StorageError(reason: String)
}

pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
  )
}

// Internal — outside this module nobody ever holds a Subject(Msg).
type Msg {
  Find(id: OrderId, reply: Subject(Result(Order, RepoError)))
  Save(order: Order, reply: Subject(Result(Nil, RepoError)))
}

fn handle_msg(
  state: Dict(OrderId, Order),
  msg: Msg,
) -> actor.Next(Dict(OrderId, Order), Msg) {
  case msg {
    Find(id, reply) -> {
      let result = dict.get(state, id) |> result.replace_error(NotFound)
      process.send(reply, result)
      actor.continue(state)
    }
    Save(o, reply) -> {
      let new_state = dict.insert(state, order.id(o), o)
      process.send(reply, Ok(Nil))
      actor.continue(new_state)
    }
  }
}

pub fn in_memory() -> Result(OrderRepo, actor.StartError) {
  use started <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_msg)
    |> actor.start,
  )
  let pid = started.data
  Ok(OrderRepo(
    find: fn(id) { process.call(pid, 100, fn(reply) { Find(id, reply) }) },
    save: fn(o) { process.call(pid, 100, fn(reply) { Save(o, reply) }) },
  ))
}
```

```gleam
// src/place_order.gleam
import gleam/result
import order.{type Order, type OrderEvent, type OrderError, type OrderId}
import order_repo.{type OrderRepo, type RepoError}

pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}

pub fn run(
  repo: OrderRepo,
  id: OrderId,
) -> Result(#(Order, List(OrderEvent)), PlaceOrderError) {
  use order <- result.try(repo.find(id) |> result.map_error(RepoFailed))
  use #(placed, events) <- result.try(
    order.place(order) |> result.map_error(DomainFailed),
  )
  use _ <- result.try(repo.save(placed) |> result.map_error(RepoFailed))
  Ok(#(placed, events))
}
```

---

## Walk-through

**`OrderRepo` is the contract, not the implementation.** The use case
takes one. The test passes one. Production `main` passes a different
one. Same use-case code runs against any value of type `OrderRepo`.
This is *parametric polymorphism without ceremony* — no interface
declarations, no virtual dispatch tables, just a record whose fields
are functions.

**The actor is a closure of state.** From outside, the actor's
existence is invisible — callers see two functions. The `Dict` is the
actor's state; messages mutate it; replies flow back through reply
subjects. This is the "state machine with a mailbox" model that Erlang
has had for thirty years, exposed in Gleam through `actor.start` +
`Subject`.

**`process.call` is synchronous request/reply built on async
primitives.** Internally it creates a fresh `Subject(Result)`, embeds
it in the message, sends, and waits on that subject's mailbox. The
actor sends the reply to that subject. From the caller's view it's a
function call. From the actor's view it's a message-and-reply pattern.
Same primitives, different shapes.

**`place_order.run` reads top-to-bottom as the use case spec.** Three
fallible steps, one `Ok` at the end. No try/catch, no defensive null
checks, no "did this succeed?" booleans. The type signature *is* the
contract; the body is the implementation of that contract.

**The error vocabulary names layers.** `RepoFailed(NotFound)` is
unambiguously different from `DomainFailed(CannotPlaceEmptyOrder)`. An
HTTP boundary that consumes this can return 404 vs 422 trivially:

```gleam
case place_order.run(repo, id) {
  Ok(_) -> http.ok(...)
  Error(RepoFailed(NotFound)) -> http.not_found()
  Error(DomainFailed(CannotPlaceEmptyOrder)) -> http.unprocessable("empty order")
  Error(_) -> http.internal_error()
}
```

---

## Critique

**The repo's API is two functions.** Real apps need more — `delete`,
`list_by_customer`, paginated queries, batch operations. Adding them is
mechanical (one new message variant, one new branch in `handle_msg`,
one new field in `OrderRepo`). The pattern scales but the boilerplate
grows linearly. Once you have ~6 fields, look hard at whether some of
them are different aggregates wearing one repo's clothes.

**`save` always returns `Ok(Nil)`** in the in-memory implementation —
there's no failure path because `dict.insert` can't fail. A real
implementation (Postgres) would have storage errors. The
`Result(Nil, RepoError)` return type already accommodates that; the
in-memory version just never exercises it.

**No concurrency story.** A single actor processes messages
sequentially. That's correct (no race conditions) but it's a bottleneck
if you need to handle a thousand concurrent saves. Real implementations
partition state across multiple actors or delegate to a backing store
that handles its own concurrency.

**The actor's failure modes are unhandled.** If `handle_msg` panics,
the actor dies and every subsequent `process.call` times out.
Production OTP code uses *supervisors* to restart dying actors —
out of scope for this kata.

**The 100ms timeout is arbitrary.** Production code should plumb
timeouts from configuration, not hard-code them.

**Postgres is sketched, not built.** A `pub fn postgres(pool: Pool) ->
OrderRepo` would have the same shape — closures over a connection
pool, queries that map rows back to `Order` *through smart
constructors*, errors mapped to `RepoError`. The interface stays the
same; only the body of `find` / `save` changes. **That's the whole
point of the pattern.**

---

## DDD takeaway

You now have the full vertical slice for one use case:

```
HTTP / CLI / message bus
            │
            ▼
      place_order.run
            │
   ┌────────┼────────┐
   ▼        ▼        ▼
OrderRepo  Order  OrderEvent
   │
(in-memory or Postgres adapter)
```

Each layer has its own type vocabulary. Each can be tested in
isolation. Each can be replaced without touching the others. The
aggregate stays pure; the use case orchestrates; the repo abstracts
storage; the boundary translates.

This is what people mean by **hexagonal architecture** or **ports and
adapters**. The kata progression has been *building toward this* the
whole time:

| Kata | What it added |
|---|---|
| 1 | Types as proof |
| 2 | Types that carry operations |
| 3 | Identity vs value |
| 4 | Aggregates as consistency boundaries |
| 5 | Events as facts about transitions |
| 6 | Repositories as the door between domain and infrastructure |

Bounded contexts (Kata 7) take this slice and copy it. *Ordering* has
its own `Order`, repo, and use cases. *Shipping* has its own
`Shipment`, repo, and use cases. They communicate via events, never by
sharing types.

That's the architecture. The rest is implementation detail.

---

## What's next

Kata 7 — **Bounded Contexts.** Same word, different model. The
*Ordering* context's `Customer` (id + name + email) is not the
*Marketing* context's `Customer` (id + segment + LTV + last campaign).
They're related concepts, not the same type. Letting them share a type
is the single fastest way to wreck a domain model.

The kata: split the existing code into two contexts, define the events
each emits, and wire them together via an event bus that lets them
collaborate without sharing types.
