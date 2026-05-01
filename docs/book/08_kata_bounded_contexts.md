# 08 — Kata 7: Bounded Contexts

## Concept

You've built one bounded context — call it **Ordering**. Customers,
orders, prices. The aggregate is `Order`; the use case is
`place_order`; the repo is `OrderRepo`. Everything in `src/` so far
belongs to that one context.

Real systems have more than one. The warehouse team needs to ship
placed orders. Marketing wants to segment customers by lifetime value.
Finance wants to reconcile payments against orders. Each has its own
team, its own data, its own vocabulary, its own rate of change.

The DDD answer: **each is a separate bounded context, with its own
model.** They share concepts (a customer in Ordering and a customer in
Marketing are the same human), but the *data* each context holds about
that customer is wildly different. Forcing them into one type is the
single fastest way to wreck a domain model:

- A `Customer` type with `name`, `email`, `segment`, `ltv`, `last_campaign`, `default_address`, `loyalty_tier`, `risk_flags`...
- Every change ripples through every team.
- Every read pulls fields nobody on this team cares about.
- Migrations are nightmares. Privacy boundaries collapse. Test fixtures balloon.

The fix isn't "stop adding fields." The fix is to recognize that
"Customer in Ordering" and "Customer in Marketing" are *different
concepts that share an ID*, not the same concept. Different types.
Different storage. Communicate via events.

## The thesis kata 7 demonstrates

> **Ordering doesn't know Shipping exists.**
>
> Shipping reacts to Ordering's events. Ordering just emits them.

That's the whole lesson. Asymmetric dependency. Events as the integration contract. Two contexts collaborating without sharing types.

In code: `src/shipping/*` imports `order.OrderEvent` and
`order.OrderId`. `src/order.gleam` imports nothing from `shipping/`.
Grep proves it.

---

## New Gleam fundamentals

Almost nothing new — kata 7 is mostly about *organization*, not new machinery.

### Folders as namespace boundaries

Gleam's module system is filesystem-driven. `src/shipping/shipment.gleam`
exports a module called `shipping/shipment`. Other code imports it as:

```gleam
import shipping/shipment.{type Shipment}
```

The folder *is* the namespace. The fact that this file lives in a
`shipping/` directory **is** what makes it part of the Shipping
bounded context. There's no other ceremony.

### Type aliases for function types (mildly useful)

If you want to give a function-type a name (e.g., for the event
handler signature), Gleam lets you:

```gleam
pub type OrderEventHandler =
  fn(order.OrderEvent) -> Result(Nil, ShipmentError)
```

Now you can write `handler: OrderEventHandler` instead of repeating
the long signature. Optional — sometimes clarity, sometimes overkill.

That's it for new mechanics. Everything else is patterns you already
know: opaque types, smart constructors, records of functions, modules.

---

## Task — one file per step

Create five new files. Each does one job; reading the kata top-down is
the same as reading the files in this order.

### 1. `src/shipping/shipment.gleam` — the Shipping aggregate

```gleam
pub opaque type ShipmentId {
  ShipmentId(value: String)
}

pub type ShipmentStatus {
  Pending
  Shipped
  Delivered
}

pub opaque type Shipment {
  Shipment(
    id: ShipmentId,
    order_id: order.OrderId,
    status: ShipmentStatus,
  )
}

pub type ShipmentError {
  EmptyShipmentId
  CannotShipNonPending
  CannotDeliverNonShipped
}

pub fn new_id(raw: String) -> Result(ShipmentId, ShipmentError)
pub fn new(id: ShipmentId, order_id: order.OrderId) -> Shipment
pub fn id(s: Shipment) -> ShipmentId
pub fn order_id(s: Shipment) -> order.OrderId
pub fn mark_shipped(s: Shipment) -> Result(Shipment, ShipmentError)
pub fn mark_delivered(s: Shipment) -> Result(Shipment, ShipmentError)
```

Same patterns as `Order`. No events for now (could add them; kata 7
focuses on the cross-context flow, not re-doing kata 5).

### 2. `src/shipping/shipment_repo.gleam` — the Shipping repository

```gleam
pub type RepoError {
  NotFound
}

pub type ShipmentRepo {
  ShipmentRepo(
    find: fn(ShipmentId) -> Result(Shipment, RepoError),
    save: fn(Shipment) -> Result(Nil, RepoError),
    find_by_order: fn(order.OrderId) -> Result(Shipment, RepoError),
  )
}

pub fn in_memory() -> Result(ShipmentRepo, actor.StartError)
```

Same record-of-functions shape as `OrderRepo`. Note the extra
`find_by_order` — the use case ("did this order already produce a
shipment?") needs lookup by order_id, not just shipment_id. Repos
expose what their callers need.

### 3. `src/shipping/handle_order_placed.gleam` — the cross-context handler

```gleam
pub type HandleError {
  RepoFailed(shipment_repo.RepoError)
  ShipmentFailed(shipment.ShipmentError)
  AlreadyShipped
}

pub fn run(
  repo: ShipmentRepo,
  fresh_id: ShipmentId,
  event: order.OrderEvent,
) -> Result(Nil, HandleError)
```

The handler:

1. Inspects the event. Only acts on `OrderPlaced`; ignores other variants.
2. Checks: does a shipment already exist for this order? (Idempotency — events can be replayed.)
3. If not, constructs a new `Shipment` via `shipment.new`, saves via `repo.save`.

This module **imports `order` types** (for `OrderEvent`, `OrderId`)
and `shipping/shipment` and `shipping/shipment_repo`. It is the
*only* place where Ordering and Shipping touch.

### 4. `test/shipping/shipment_test.gleam` — Shipping aggregate tests

Standard aggregate tests: construct, transition, error cases.

### 5. `test/shipping/handle_order_placed_test.gleam` — the integration spec

The test that proves the cross-context flow works:

```gleam
pub fn order_placed_creates_shipment_test() {
  let assert Ok(order_repo) = order_repo.in_memory()
  let assert Ok(ship_repo) = shipment_repo.in_memory()

  // Place an order via Ordering
  let oid = test_order_id()
  let #(o, _) = order.new(oid, test_customer_id())
  let assert Ok(#(o2, _)) = order.add_line(o, "WIDGET", 1, usd(100))
  let assert Ok(_) = order_repo.save(o2)
  let assert Ok(#(_, events)) = place_order.run(order_repo, oid)

  // Dispatch the events to Shipping
  let assert [order_placed] = events
  let assert Ok(sid) = shipment.new_id("SHIP-001")
  let assert Ok(Nil) = handle_order_placed.run(ship_repo, sid, order_placed)

  // Shipment exists
  let assert Ok(s) = ship_repo.find_by_order(oid)
  assert shipment.order_id(s) == oid
}
```

That's the full vertical slice of two contexts collaborating — and
notice that no module here imports anything *from* `shipping/` into
`order` or vice versa.

---

## Hints — what to do

1. **Build it in the order listed.** Aggregate first (no dependencies on the rest). Repo next (depends on aggregate + actor). Handler last (depends on aggregate, repo, and Ordering's `OrderEvent`).
2. **`Shipment` is structurally similar to `Order` but simpler.** No lines, no totals — just an ID, a foreign-key-ish `OrderId`, a status enum. State transitions check the current status.
3. **`shipment_repo.in_memory()` is almost a copy of `order_repo.in_memory()`** — same actor scaffold, just with three message variants instead of two (`Find`, `Save`, `FindByOrder`).
4. **The handler must be idempotent.** Pattern-match on the event; if it's not `OrderPlaced`, return `Ok(Nil)` (silently ignore). If it is, check `find_by_order` first — if a shipment already exists, return `Ok(Nil)` or `Error(AlreadyShipped)` depending on your taste. Only `save` if nothing's there.
5. **The handler takes the `ShipmentId` from the outside.** Don't generate IDs inside the handler — that makes it deterministic and testable. Composition root or test passes a fresh ID in.
6. **Imports tell the story.** When you've finished, check:
   - `src/shipping/handle_order_placed.gleam` should `import order.{type OrderEvent, OrderPlaced, type OrderId}`
   - `src/order.gleam` should have **zero** imports starting with `shipping/`
   - If you have to import the wrong direction, the design is upside down.
7. **For `mark_shipped` / `mark_delivered`**: `case s.status { Pending -> Ok(Shipment(..s, status: Shipped)) ; _ -> Error(CannotShipNonPending) }`. Same pattern you used in `Order.place`.

---

## Walk-through

**The directory structure *is* the bounded context.** You don't need a
`Context` type or a `BoundedContext` annotation or a config file
declaring boundaries. You have `src/shipping/`. The folder *is* the
boundary. Tools (search, grep, dependency graphs) understand it for
free.

**`handle_order_placed` is the only file with both worlds in scope.**
Its imports are the entire integration story:

```gleam
import order.{type OrderEvent, OrderPlaced}     // ← Ordering's published events
import shipping/shipment.{type ShipmentId}       // ← Shipping's own types
import shipping/shipment_repo.{type ShipmentRepo, NotFound}
```

This module sits *in* the Shipping context (path: `shipping/`) but
*translates* events from Ordering. It's where the cross-context
relationship is named, in code, in one place. Move this file and the
relationship moves with it.

**Ordering doesn't get touched.** No new imports in `src/order.gleam`,
no new methods, no callbacks. Ordering keeps emitting `OrderPlaced`
events; whether anyone's listening is none of its business. You could
delete the entire `shipping/` directory and `src/order.gleam` would
still compile and work.

**The test asserts the integration without testing the bus.** No event
bus type appears. The test calls `place_order.run` to get events,
iterates them, calls the Shipping handler. That *is* the bus, in two
lines. If you want a fancier bus (async, multiple subscribers per
event, retry on failure), you can write one — but the kata works
without it.

**Idempotency matters.** The `find_by_order` check before saving makes
the handler safe to replay. Real event delivery is at-least-once;
handlers that aren't idempotent eventually create duplicates. This is
free at the application layer when the check is in the handler.

---

## Critique

**Where do `money` and `email` live?** Both contexts use them. Two
honest answers:

- **Shared kernel** (current setup) — they're at the top level (`src/email.gleam`, `src/money.gleam`), both contexts import them. Right call when the value objects are stable, small, and behaviorally identical across contexts.
- **Duplicate** — each context defines its own. Right call when contexts evolve at different rates or want different behavior on the same concept (e.g., Marketing might add `+ tax_jurisdiction` to its money type for compliance reasons).

For a kata: shared kernel. For a real system: duplicate as soon as you feel the pull.

**No anti-corruption layer.** The handler imports `order.OrderEvent`
directly. If Ordering's event vocabulary changes, the handler breaks
at compile time. That's a feature *if* the two contexts are
maintained by collaborating teams; a bug *if* they're independent.
Then you'd add a tiny adapter:

```gleam
// src/shipping/order_event_adapter.gleam
pub type ShippingTrigger {
  TriggerForOrder(OrderId)  // shipping's own vocabulary
}

pub fn from_order_event(e: order.OrderEvent) -> Option(ShippingTrigger) {
  case e {
    OrderPlaced(id, _) -> Some(TriggerForOrder(id))
    _ -> None
  }
}
```

Now `handle_order_placed` deals only in `ShippingTrigger`. Ordering can rename, add, or remove event variants and only `order_event_adapter.gleam` needs to update. That's an Anti-Corruption Layer in 8 lines. **Add it when you actually need it, not preemptively.**

**No real event bus.** The "bus" is the composition root iterating
events and calling handlers. That's fine for a single process with
synchronous handlers. Becomes inadequate when you want async delivery
across services, persistent retry, dead-letter queues, etc. — at which
point you reach for a real broker (RabbitMQ, NATS, Kafka, BEAM
distribution + persistent_term). The application code stays the same;
the wiring changes.

**`Shipment` doesn't emit events.** Maybe it should — `ShipmentShipped`
would be useful for `tracking@shipping.example.com` notifications
and Finance reconciliation. Skipped here to keep the kata focused on
the cross-context flow rather than re-doing kata 5.

**No process manager / saga.** A full "ship and bill" flow might be:
`OrderPlaced → CreateShipment → ChargeCard → ConfirmShipment`.
Coordinating that across contexts is a saga's job. Out of scope; the
pattern is "one handler per event, idempotent, no orchestration."

---

## DDD takeaway

What you've built:

- Two bounded contexts in one process, communicating via events
- An asymmetric dependency arrow that the file tree visibly enforces
- A small, idempotent integration handler that's the *only* place either context names the other
- A test that exercises the full cross-context flow without mocking
- A pattern that scales: add Marketing? `src/marketing/`. Add Finance? `src/finance/`. Each follows the same shape.

What it teaches:

- **The boundary is in the dependency graph, not the documentation.** Comments and team agreements drift; imports don't.
- **Events are the integration contract.** They're versioned, named, immutable. Changing an event signature is a public API change. Changing a domain type is a private refactor.
- **"Same word, different model" is OK.** It's better than OK — it's *correct*. The shared concept is the ID; the data each context cares about is local.
- **Distributed systems use the same model**, just with a network in between. A Shipping *service* in another process or another datacenter would have the same code shape — different transport, same domain logic. That's why "monolith with bounded contexts" and "microservices with bounded contexts" are easier to switch between than the rhetoric implies.

---

## Where this leaves the book

You now have, in roughly this order of value:

1. Types as the load-bearing structure of the domain (katas 1–4)
2. Events as facts that escape the aggregate (kata 5)
3. Repositories that hide storage from the domain (kata 6)
4. Bounded contexts as the unit of model independence (kata 7)

That's the core of DDD — the strategic patterns (contexts, ubiquitous
language, events) and the tactical ones (entities, value objects,
aggregates, repositories), all in idiomatic Gleam, none of the
ceremony.

What's beyond the book:

- **Sagas / process managers** — orchestrating multi-aggregate, multi-context workflows
- **Distributed event delivery** — moving from "in-process function calls" to message brokers or BEAM distribution
- **Read models / CQRS** — denormalized projections optimized for queries, fed by the event stream
- **Event sourcing** — making the event log the source of truth, deriving state by replay
- **Anti-corruption layers in earnest** — when one context has to integrate with a foreign system whose model you can't change

Each of those is its own book. The kata progression you've finished is
the foundation that makes them readable.
