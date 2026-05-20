# 08. Kata 7: Bounded Contexts

## Concept

So far you've worked inside one bounded context, **Ordering**,
with `Order` as the aggregate, `place_order` as the use case, and
`OrderRepo` as the repo. Everything in `src/` belongs to that
context.

Real systems grow more. Warehouse ships the placed orders while
Marketing segments customers by lifetime value and Finance
reconciles payments. Each team owns its own data and vocabulary,
and moves at its own pace.

Each becomes its own bounded context with its own model. They share concepts (a customer in Ordering is the same
human as a customer in Marketing), but the *data* each context
holds about that customer diverges. Force them into one type and
the model dies fast:

- A `Customer` type with `name`, `email`, `segment`, `ltv`, `last_campaign`, `default_address`, `loyalty_tier`, `risk_flags`...
- Changes ripple through every team, reads pull fields nobody on this team cares about, and migrations turn into multi-team negotiations.
- The privacy story collapses the moment Marketing's PII fields end up in Ordering's fixtures.

"Customer in Ordering" and "Customer in Marketing" are different
concepts that happen to share an ID. Each gets its own type and
its own storage, and they talk through events.

## The thesis kata 7 demonstrates

> **Ordering doesn't know Shipping exists.**
>
> Shipping reacts to Ordering's events. Ordering just emits them.

Events do the integration work, and neither context shares a type
with the other.

In code, `src/shipping/*` imports `order.OrderEvent` and
`order.OrderId`, while `src/order.gleam` imports nothing from
`shipping/`. Grep proves the asymmetry.

---

## New Gleam fundamentals

Kata 7 is about *organization*, so the new machinery is minimal.

### Folders as namespace boundaries

Gleam's module system is filesystem-driven. `src/shipping/shipment.gleam`
exports a module called `shipping/shipment`. Other code imports it as:

```gleam
import shipping/shipment.{type Shipment}
```

The folder *is* the namespace. Living inside `shipping/` is what
makes a file part of the Shipping bounded context, and no other
ceremony applies.

### Type aliases for function types

To name a function type, say the event handler signature, Gleam
lets you write:

```gleam
pub type OrderEventHandler =
  fn(order.OrderEvent) -> Result(Nil, ShipmentError)
```

Now `handler: OrderEventHandler` stands in for the long signature.
The alias is optional and worth it only when it clarifies the
calling code.

That's the new mechanics. The rest is patterns you already use:
opaque types, smart constructors, records of functions, modules.

---

## Task: one file per step

Create five new files. Each does one job, and reading the kata
top-down matches reading the files in order.

### 1. `src/shipping/shipment.gleam`: the Shipping aggregate

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

The shape mirrors `Order`. This kata skips events because kata 7
focuses on the cross-context flow, and kata 5 already covered how
aggregates emit events.

### 2. `src/shipping/shipment_repo.gleam`: the Shipping repository

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

The shape mirrors `OrderRepo` and adds one new `find_by_order`
query, because the use case asks "did this order already produce a
shipment?", which is a lookup by order_id rather than by
shipment_id. Repos expose what their callers need.

### 3. `src/shipping/handle_order_placed.gleam`: the cross-context handler

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

The handler inspects the event and acts only on `OrderPlaced`. It
asks the repo whether a shipment already exists for this order,
since the bus can replay events and the handler has to stay idempotent.
If none exists, it builds a fresh `Shipment` via `shipment.new` and
saves it through `repo.save`.

This module imports `order` types (`OrderEvent`, `OrderId`) along
with `shipping/shipment` and `shipping/shipment_repo`. It's the one
place where Ordering and Shipping meet.

### 4. `test/shipping/shipment_test.gleam`: Shipping aggregate tests

Standard aggregate tests cover construction, the happy-path
transitions, and the error branches when the status is wrong.

### 5. `test/shipping/handle_order_placed_test.gleam`: the integration spec

One test proves the cross-context flow works:

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

The test runs a full vertical slice of two contexts collaborating,
and no module here imports anything *from* `shipping/` into `order`
or the reverse.

---

## Hints: what to do

1. Build in the order listed: aggregate first (no dependencies), repo next (depends on the aggregate and the actor scaffold), handler last (pulls in the aggregate, the repo, and Ordering's `OrderEvent`).
2. `Shipment` looks like `Order` with the hard parts removed. There are no lines or totals, just an ID, an `OrderId` acting as a foreign key, and a status enum. State transitions check the current status.
3. `shipment_repo.in_memory()` mirrors `order_repo.in_memory()` on the same actor scaffold; the message type grows one variant to support `FindByOrder`.
4. Make the handler idempotent. Pattern-match the event. Anything that isn't `OrderPlaced` returns `Ok(Nil)` and bails. For `OrderPlaced`, call `find_by_order` first, because if a shipment already exists you return `Ok(Nil)` (or `Error(AlreadyShipped)`, your call). Only `save` when nothing's there.
5. Pass the `ShipmentId` in from outside. Generating IDs inside the handler makes it nondeterministic and harder to test, so let the composition root or the test supply a fresh one.
6. Imports tell the story. When you finish, check:
   - `src/shipping/handle_order_placed.gleam` should `import order.{type OrderEvent, OrderPlaced, type OrderId}`
   - `src/order.gleam` should have **zero** imports starting with `shipping/`
   - If you have to import the wrong direction, the design is upside down.
7. For `mark_shipped` / `mark_delivered`: `case s.status { Pending -> Ok(Shipment(..s, status: Shipped)) ; _ -> Error(CannotShipNonPending) }`, which is the same pattern you used in `Order.place`.

---

## Walk-through

The directory structure *is* the bounded context. There's no
`Context` type and no `BoundedContext` annotation declaring
boundaries in a config file. You have `src/shipping/`, and the
folder is the boundary. Grep and dependency-graph tools see the
boundary without further input.

`handle_order_placed` is the only file with both worlds in scope.
Its imports tell the integration story:

```gleam
import order.{type OrderEvent, OrderPlaced}     // ← Ordering's published events
import shipping/shipment.{type ShipmentId}       // ← Shipping's own types
import shipping/shipment_repo.{type ShipmentRepo, NotFound}
```

The module sits *inside* the Shipping context (path: `shipping/`)
but *translates* events from Ordering. This file names the
cross-context relationship in code, in one place. Move it and the
relationship moves with it.

Nothing touches Ordering. `src/order.gleam` gains no new imports
and no new methods or callbacks.
Ordering keeps emitting `OrderPlaced` events; whether anyone's
listening is none of its business. Delete the `shipping/` directory
and `src/order.gleam` still compiles and works.

The test asserts the integration without testing the bus. No event
bus type appears. The test calls `place_order.run`, takes the
events back, and hands them to the Shipping handler. Those two
lines *are* the bus. A fancier one with async delivery, multiple
subscribers, or retry on failure is a separate project, and the
kata works fine without it.

The `find_by_order` check before saving makes the handler safe to
replay. Real event delivery is at-least-once, and handlers that
aren't idempotent end up creating duplicates, so putting the check
in the handler buys idempotency at the application layer for free.

---

## Critique

Where do `money` and `email` live? Both contexts use them, so
there are a couple of honest answers:

- **Shared kernel** (current setup): they sit at the top level (`src/email.gleam`, `src/money.gleam`) and both contexts import them. Good call when the value objects are small, stable, and behave the same wherever they go.
- **Duplicate**: each context defines its own. Good call when contexts evolve at different rates or need different behavior on the same concept (Marketing might tack `tax_jurisdiction` onto its money type for compliance).

A kata sticks with the shared kernel. A real system duplicates as
soon as you feel the pull.

The kata ships without an anti-corruption layer. The handler
imports `order.OrderEvent` directly, so if Ordering's event
vocabulary changes the handler breaks at compile time. That's a
feature when both contexts share a team who can fix both sides in
one PR, and a bug when the teams are independent. In the
independent case, add a tiny adapter:

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

Now `handle_order_placed` deals only in `ShippingTrigger`. Ordering
can rename, add, or remove event variants and only
`order_event_adapter.gleam` updates. That's an Anti-Corruption Layer
in eight lines, and you should add it once you need it, not before.

There's no real event bus. The "bus" is the composition root
iterating events and calling handlers, which suits one process with
synchronous handlers and runs out of room when async delivery,
persistent retry, or dead-letter queues come up. The fix is a real
broker (RabbitMQ, NATS, Kafka, BEAM distribution); application code
doesn't move, only the wiring.

`Shipment` doesn't emit events of its own. Adding `ShipmentShipped`
would feed tracking and Finance reconciliation, but the kata skips it
to keep the focus on cross-context flow instead of redoing kata 5.

Process managers and sagas are also out of scope. Coordinating
`OrderPlaced → CreateShipment → ChargeCard → ConfirmShipment` across
contexts is a saga's job; the pattern here is one idempotent handler
per event, with no orchestration on top.

---

## Takeaway

Two bounded contexts now live in one process, communicating via
events along an asymmetric dependency arrow the file tree makes
visible. One file (the handler) names both contexts and is idempotent;
a test exercises the cross-context flow with no mocks. Adding
Marketing means `src/marketing/`; adding Finance means
`src/finance/`. The shape repeats.

The lessons compound. The boundary lives in the dependency graph
rather than in documentation, since comments and team agreements
drift while imports don't. Events are the integration contract,
named and versioned, and changing one is a public API change while
changing a domain type is a private refactor. "Same word, different
model" is the right answer: contexts share IDs, not data. A Shipping
service in another datacenter is the same code with a different
transport, which is why monoliths and microservices with bounded
contexts swap more easily than the marketing language suggests.
