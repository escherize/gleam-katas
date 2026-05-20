# 07. Kata 6: Repositories

## Concept

The aggregate has stayed pure. State and a command go in, a new state
and events come out. That work is worth nothing once the process
restarts.

A repository turns an aggregate type into something you can load and
save. The domain depends on the interface and the implementation lives
in the infrastructure layer, so `order.gleam` stays ignorant of
storage.

Use cases then test without infrastructure. A test places an order
through the repo, loads it back, and checks the events. Storage stays
pluggable on the other side, so you swap an in-memory dict today for
Postgres next week, and the use-case code on top doesn't notice.

A repository belongs to an aggregate, not an entity. You save an
`Order` and an `OrderLine` rides along inside it. The aggregate is the
consistency unit, and the repo's contract is "give me back a valid one
or fail."

## What you load is what you trust

The repository's other job is to feed loaded data back through the
smart constructors. A database row is raw fields, and turning those
into a typed `Order` goes through `email.new`, `customer.new_id`, and
friends, the same validation that keeps HTTP input honest. A corrupt
row becomes `Error(CorruptRow(...))` rather than a thrown exception.

The Kata 1 ceremony compounds here. Every reconstruction trusts the
type because every construction went through the smart constructor.
No "but I got it from the database, so I trust it" backdoor exists.

## The use case is the orchestrator

A use case is a function that does one thing the application
supports, like "place an order." The shape is:

```
load via repo → call domain → save via repo → return events
```

Every step has a typed error. The use case wraps repo errors and
domain errors in a `PlaceOrderError` so callers know which layer broke,
which is where the chaining patterns from earlier katas come together:
`result.try` from Kata 3 and the wrap-the-cause idea from Kata 5.

The use case is the application boundary that HTTP, CLI, and message
handlers translate into and out of. The domain sits beneath it. A test
of a use case says "given these inputs, this is what happens" without
spinning up any infrastructure.

---

## New Gleam fundamentals

### Records of functions

A Gleam record whose fields happen to be functions is still an
ordinary record, and that record serves as an interface:

```gleam
pub type OrderRepo {
  OrderRepo(
    find: fn(OrderId) -> Result(Order, RepoError),
    save: fn(Order) -> Result(Nil, RepoError),
  )
}
```

A `Customer` and an `OrderRepo` are the same kind of value. The
fields differ and callers don't care:

```gleam
let order = repo.find(id)
```

A type with function fields is the interface, without an
`IFooRepository<Order>` or a DI container in sight.

### Why we need OTP

Gleam has no globals or mutable fields. State that needs to survive
across function calls has to live somewhere, and that somewhere is a
process.

A process is a lightweight Erlang thread with a mailbox. You send
messages and it handles them one at a time. The state is a value the
process threads through its message loop, and outside the process you
see replies rather than the state itself.

For a repository, the process holds a `Dict(OrderId, Order)` and the
messages ask "find this id" or "save this order."

### OTP, just enough

The vocabulary stays compact.

- `Dict(k, v)` from `gleam/dict`, an immutable hash map. `dict.new()`, `dict.get(d, k) -> Result(v, Nil)`, `dict.insert(d, k, v) -> Dict(k, v)`.
- `Subject(msg)`, a typed mailbox, the address of a process. Hold a `Subject(Find(...) | Save(...))` to send messages to a particular actor.
- `actor.new(initial_state) |> actor.on_message(handler) |> actor.start` builds and starts the actor. Returns `Result(Started(Subject(msg)), StartError)`. The `Started.data` field is the subject outside callers use.
- The handler signature is `fn(state, msg) -> actor.Next(state, msg)`. Return `actor.continue(new_state)` to loop, or `actor.stop()` to terminate.
- `process.call(subject, timeout, builder)` does synchronous request/reply. The `builder` has type `fn(reply_subject) -> msg`. You embed a reply subject in the outgoing message, the actor sends its response there, and `process.call` blocks until that response arrives or the timeout expires.

A counter actor builds the same shape:

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

Swap `Dict(OrderId, Order)` for `Int` and swap `Find`/`Save` for
`Get`/`Set`, and you have a repository.

### Wrapping the actor in the interface

The actor's `Subject(Msg)` is an implementation detail. The use case
sees an `OrderRepo`. Closures bridge the two:

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

Each function field closes over the actor's subject. Callers never
know the actor exists.

### Error wrapping across layers

When two layers can fail, the error type names the layer:

```gleam
pub type PlaceOrderError {
  RepoFailed(RepoError)
  DomainFailed(OrderError)
}
```

The conversion happens via `result.map_error`, which relies on a
Gleam fact that's easy to miss: constructors are functions. When you
write `pub type PlaceOrderError { RepoFailed(RepoError) | ... }`,
`RepoFailed` does double duty. It works as a pattern in a `case`
expression to destructure (`case e { RepoFailed(inner) -> ... }`), and
it also works as a value of type `fn(RepoError) -> PlaceOrderError`
that fits anywhere a function does.

`result.map_error` has signature
`fn(Result(a, e1), fn(e1) -> e2) -> Result(a, e2)`. Given a Result
and a function from the old error type to the new one, it applies
that function on the `Error` branch and returns a Result whose error
type is whatever the function returned.

Pass `RepoFailed` (a function `fn(RepoError) -> PlaceOrderError`) and
the result's error type becomes `PlaceOrderError`:

```gleam
let r1: Result(Order, RepoError)        = repo.find(id)
let r2: Result(Order, PlaceOrderError)  = r1 |> result.map_error(RepoFailed)
//                                    RepoFailed is the function ^
```

The original `RepoError` survives inside the `RepoFailed` wrapper, so
the cause is intact, and callers pattern-match on `RepoFailed(_)`
versus `DomainFailed(_)` to see which side broke.

`result.try` only chains when the inner Result and the outer
function's return type share an error type. Drop the `map_error` and
the repo gives you `Result(_, RepoError)` while the outer function
returns `Result(_, PlaceOrderError)`, so the types refuse to line up.
`map_error(RepoFailed)` makes the chain type-check.

---

## Task

Add an accessor to `src/order.gleam` so the repo can extract the ID
from an order to use as a dict key:

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
actor handles `Find` and `Save` messages, and the use case loads,
places, and saves.

Tests go in `test/order_repo_test.gleam` (round-trip the repo) and
`test/place_order_test.gleam` (run the use case end-to-end against an
in-memory repo).

---

## Hints: what to do

1. Design the `OrderRepo` type before you write any code. `find` and `save` are the minimum; add `delete` or `list_for_customer` when a test asks for them and skip them until then.
2. `RepoError` is the next type to pin down. `NotFound` is obvious. Beyond that, `StorageError(reason)` covers network or disk failures and `CorruptRow(reason)` covers "I have a row but cannot reconstruct an Order." Keep the type compact and grow it as you go.
3. `handle_msg` is the only real implementation work in `order_repo`. Match on `Find(id, reply)` or `Save(o, reply)`, run the matching `dict` op, send the answer with `process.send(reply, ...)`, then return `actor.continue(new_state)`. Each branch runs about five lines.
4. Put the actor's state type in the handler signature: `fn handle_msg(state: Dict(OrderId, Order), msg: Msg) -> actor.Next(Dict(OrderId, Order), Msg)`. The signature is verbose, and the compiler keeps you honest.
5. `place_order.run` chains these steps:
   - `use order <- result.try(repo.find(id) |> result.map_error(RepoFailed))`
   - `use #(placed, events) <- result.try(order.place(order) |> result.map_error(DomainFailed))`
   - `use _ <- result.try(repo.save(placed) |> result.map_error(RepoFailed))`
   - `Ok(#(placed, events))`
6. For tests, write a helper that creates a repo and seeds it with an order. Most tests then set up state, call the use case, and assert against the events.
7. `process.call` blocks the calling process until the actor replies or times out. 100ms is plenty for tests.
8. `result.replace_error(NotFound)` is the cleanest way to turn the `Result(Order, Nil)` from `dict.get` into a `Result(Order, RepoError)`.

---

## Walk-through

The actor's message type does the design work. Each request becomes a
variant, and each variant carries a typed reply `Subject` so the actor
knows where to send the answer:

```gleam
pub type Msg {
  Find(id: OrderId, reply_to: Subject(Result(Order, RepoError)))
  Save(order: Order, reply_to: Subject(Result(Nil, RepoError)))
}
```

The reply types differ by message. The compiler refuses to let `Find`
ever reply with `Nil` or `Save` with an `Order`, so the wiring stays
honest without runtime checks.

`handle_msg` is then small:

```gleam
fn handle_msg(store, msg) {
  case msg {
    Find(id:, reply_to:) -> {
      let r = store |> dict.get(id) |> result.replace_error(NotFound)
      process.send(reply_to, r)
      actor.continue(store)
    }
    Save(order:, reply_to:) -> {
      let new_state = dict.insert(store, order.id(order), order)
      process.send(reply_to, Ok(Nil))
      actor.continue(new_state)
    }
  }
}
```

`result.replace_error(NotFound)` swaps the `Nil` from `dict.get` for
the repo's vocabulary in one call, since the missing-key case carries
no detail worth preserving.

`in_memory` starts the actor and bridges its subject into the
`OrderRepo` record, so callers see two function fields and never learn
an actor exists:

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

The `fn(reply) { Find(id, reply) }` shape is `process.call`'s contract:
it hands you a fresh reply subject, you embed it in the outgoing
message, and `process.call` blocks until the actor sends a response
there or 100ms passes.

`place_order.run` is the payoff:

```gleam
pub fn run(repo, id) {
  use order <- result.try(repo.find(id) |> result.map_error(RepoFailed))
  use #(placed, events) <- result.try(
    order.place(order) |> result.map_error(DomainFailed),
  )
  use _ <- result.try(repo.save(placed) |> result.map_error(RepoFailed))
  Ok(#(placed, events))
}
```

Three `result.try` lines, each wrapping the layer-specific error in a
`PlaceOrderError` variant. The function reads top-to-bottom like a
checklist: load, transition, save, return. Nothing here knows the repo
is an actor or that the actor holds a `Dict`, so swapping in a SQLite
repo (kata 9) doesn't move a line.

The `map_error(RepoFailed)` calls do the type-juggling the
"constructors as functions" detour set up. Without them the inner
`Result(_, RepoError)` wouldn't fit a chain expecting
`Result(_, PlaceOrderError)`.

---

## Critique

The 100ms timeout fits an in-memory dict and nothing else. A real I/O
repo would take the timeout as config, since "long enough for the slow
case, short enough that hung backends don't pile up callers" is a
deployment decision rather than a code one.

The actor itself is a teaching scaffold. It serializes every request
through one mailbox, which a `Dict` needs and a SQL connection pool
already provides. A SQLite or Postgres repo drops the actor entirely;
the in-memory dict has nowhere else to live, so it borrows one.

`StorageError(String)` is a placeholder. A real repo distinguishes
"connection lost," "constraint violated," and "decode failed" because
callers want to react differently. Grow the variant set as the
production adapter forces the cases.

`list_all` is `pub` only because integration tests want to read
everything back. Production repos almost never expose it directly,
since returning the whole table is an outage waiting to happen.
Filtered or paginated queries earn the field; an unbounded list
doesn't.

`order.id(order)` is the one accessor that crosses the aggregate's
opaque-type wall for the repo's benefit, and it's the right size: the
repo needs a key to store under, and an explicit accessor is cheaper
than exposing the record. Kata 9 extends the same idea
(`snapshot`/`restore`) when the repo needs the full state.

---

## Takeaway

The aggregate stayed pure. `order.place` still takes an `Order` and
returns `Result(#(Order, List(OrderEvent)), OrderError)`, the same
signature it had after kata 5. Nothing in `order.gleam` learned that
storage exists.

What the repository bought, in one chapter: a use case that takes an
interface and swaps adapters in kata 9 without moving, tests that
build a fresh in-memory backend per case without mocks, and layer
errors that stay distinct all the way to the HTTP boundary where
`RepoFailed(NotFound)` becomes a 404 and `DomainFailed(CannotPlaceEmptyOrder)`
becomes a 422.

The use case is the application layer the rest of the book builds on.
HTTP handlers (kata 8) translate requests into use-case calls;
bounded contexts (kata 7) react to the events use cases return. Its
signature reads like a sentence about what the application does.

---

## What's next

Kata 7 introduces a second bounded context, Shipping, that reacts to
Ordering's events without either side importing the other's
internals. The repository pattern from this chapter carries straight
through: `ShipmentRepo` is the same record-of-functions on the same
actor scaffold, with the message type adapted to shipping's queries.

