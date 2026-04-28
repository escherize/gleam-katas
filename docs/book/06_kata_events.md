# 06 — Kata 5: Domain Events

## Concept

Up to now, every operation on the aggregate returned just *the new state*.
Now they return the new state **plus a list of facts about what happened.**

Those facts — domain events — are immutable, named in **past tense**, and
carry enough data to describe the transition standalone.

Why bother? Three reasons that compound:

- **Decoupling.** Other parts of the system can react to events without the aggregate knowing about them. Send a confirmation email when `OrderPlaced` fires — `Order` doesn't need to know email exists.
- **Audit log for free.** The event stream *is* the history. No separate "what happened to this order" code path.
- **Seed of event sourcing.** Once the aggregate emits a complete event log per state change, you can derive state by replaying events instead of storing it. That's the foundation of CQRS / event sourcing systems.

The naming matters: `OrderPlaced`, not `PlaceOrder`. Events are *things
that already happened*, not *commands to do something*. (Commands and
events are duals — see the bonus section at the end.) Mix them and you
lose the ability to reason about your system.

---

## New Gleam fundamentals

You don't actually need much new. The kata is mostly an *additive change*
to the API — same toolkit, new return shape.

### Tuples — `#(a, b)`

Gleam's lightweight pair / triple syntax:

```gleam
let pair = #(order, [OrderCreated(id, cid)])
let #(o, events) = pair
```

No type definition needed — just a structural pair. Used here to bundle
"the new state" and "the events emitted by this transition" into one
return value without inventing a record per operation.

Pattern matching on tuples works the same as anywhere else:

```gleam
case order.add_line(o, sku, q, p) {
  Ok(#(new_order, events)) -> ...
  Error(reason)            -> ...
}
```

### `result.try` chaining (earning its keep)

You met `result.try` in Kata 3, but `place` is where it earns its keep.
`OrderPlaced` carries the total; computing the total can fail. So
`place` has to chain: validate preconditions → compute total →
construct event:

```gleam
pub fn place(order: Order) -> Result(#(Order, List(OrderEvent)), OrderError) {
  use <- no_modify_placed(order)
  case order.lines {
    [] -> Error(CannotPlaceEmptyOrder)
    _  -> {
      use t <- result.try(total(order))
      let placed = Order(..order, status: Placed)
      Ok(#(placed, [OrderPlaced(order.id, t)]))
    }
  }
}
```

That `use t <- result.try(total(order))` line is what `use` was designed
for — it short-circuits the rest of the body if `total` returns `Error`,
otherwise it binds `t` and continues. Without it the construction would
nest a `case` inside another `case`.

---

## Task

Modify `src/order.gleam` so `new`, `add_line`, and `place` return both
the updated aggregate **and** the events emitted:

```gleam
pub type OrderEvent {
  OrderCreated(order_id: OrderId, customer_id: CustomerId)
  LineAdded(order_id: OrderId, sku: String, quantity: Int, unit_price: Money)
  OrderPlaced(order_id: OrderId, total: Money)
}

pub fn new(id: OrderId, customer_id: CustomerId) -> #(Order, List(OrderEvent))

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(#(Order, List(OrderEvent)), OrderError)

pub fn place(order: Order) -> Result(#(Order, List(OrderEvent)), OrderError)
```

Rules:

- `new` emits `[OrderCreated(...)]`. It's total — no `Result` wrapper.
- `add_line` emits `[LineAdded(...)]` on success.
- `place` emits `[OrderPlaced(...)]` on success, with the total computed at placement time.
- **Failures emit no events.** Events represent things that *actually happened*, and a failed operation didn't happen. The `Error(...)` branch returns *only* the error — no partial event list.

The tests in `test/order_test.gleam` are the per-operation spec. The
tests in `test/order_scenarios_test.gleam` exercise the aggregate
through *sequences* of commands (see the "Scenario testing" section
below).

---

## Hints — what to do

1. **Implement in this order:** `new_id` → `new` → guard helpers → `add_line` → `total` → `place`. `place` depends on `total`, so do `total` first.
2. **`new` is the simplest function in the file now.** It's total. Construct the order, construct the event, return the tuple. No `Result`, no `case`, no preconditions.
3. **Failures emit no events.** When a precondition guard returns `Error(...)`, the event list never gets built. The `Ok` branch is the *only* place where you construct events. This falls out naturally from the `use <-` chain — you never reach the event construction if a guard short-circuits.
4. **`place` is the interesting one.** Sketch:
   - Guard: order not already placed
   - Check: lines isn't empty (else `CannotPlaceEmptyOrder`)
   - Compute total via `result.try` (else propagate the underlying error)
   - Construct placed order + `OrderPlaced` event
5. **Don't try to share event-construction code.** Each operation's event has a different shape. Just construct each event inline at its emission site — it's three lines per operation.
6. **The kata 4 helpers are unchanged.** `no_modify_placed`, `non_empty_sku`, `positive_qty`, `currency_matches` — same signatures, same bodies. They short-circuit before you build anything.

---

## Solution

```gleam
import customer.{type CustomerId}
import gleam/list
import gleam/result
import money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}

pub type OrderStatus {
  Draft
  Placed
}

pub opaque type Order {
  Order(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(OrderLine),
    status: OrderStatus,
  )
}

pub type OrderError {
  EmptyOrderId
  EmptySku
  NonPositiveQuantity
  CannotModifyPlacedOrder
  CannotPlaceEmptyOrder
  CurrencyMismatch
  InvalidOrderTotal
}

pub type OrderEvent {
  OrderCreated(order_id: OrderId, customer_id: CustomerId)
  LineAdded(order_id: OrderId, sku: String, quantity: Int, unit_price: Money)
  OrderPlaced(order_id: OrderId, total: Money)
}

pub fn new_id(raw: String) -> Result(OrderId, OrderError) {
  case raw {
    "" -> Error(EmptyOrderId)
    _ -> Ok(OrderId(raw))
  }
}

pub fn new(
  id: OrderId,
  customer_id: CustomerId,
) -> #(Order, List(OrderEvent)) {
  let order = Order(id, customer_id, [], Draft)
  #(order, [OrderCreated(id, customer_id)])
}

fn no_modify_placed(o: Order, then) {
  case o.status {
    Placed -> Error(CannotModifyPlacedOrder)
    Draft -> then()
  }
}

fn non_empty_sku(sku: String, then) {
  case sku {
    "" -> Error(EmptySku)
    _ -> then()
  }
}

fn positive_qty(q: Int, then) {
  case q > 0 {
    True -> then()
    False -> Error(NonPositiveQuantity)
  }
}

fn currency_matches(existing, new_price, then) {
  case existing {
    [] -> then()
    [first, ..] ->
      case money.same_currency(first.unit_price, new_price) {
        True -> then()
        False -> Error(CurrencyMismatch)
      }
  }
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(#(Order, List(OrderEvent)), OrderError) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)

  let new_line = OrderLine(sku, quantity, unit_price)
  let new_order = Order(..order, lines: [new_line, ..order.lines])
  let event = LineAdded(order.id, sku, quantity, unit_price)
  Ok(#(new_order, [event]))
}

pub fn place(order: Order) -> Result(#(Order, List(OrderEvent)), OrderError) {
  use <- no_modify_placed(order)
  case order.lines {
    [] -> Error(CannotPlaceEmptyOrder)
    _ -> {
      use t <- result.try(total(order))
      let placed = Order(..order, status: Placed)
      Ok(#(placed, [OrderPlaced(order.id, t)]))
    }
  }
}

pub fn total(order: Order) -> Result(Money, OrderError) {
  case order.lines {
    [first, ..] -> {
      use amounts <- result.try(
        list.try_map(order.lines, fn(ol) {
          money.multiply(ol.unit_price, ol.quantity)
        })
        |> result.map_error(fn(_) { InvalidOrderTotal }),
      )
      list.try_fold(amounts, money.zero(first.unit_price), money.add)
      |> result.map_error(fn(_) { InvalidOrderTotal })
    }
    _ -> Error(InvalidOrderTotal)
  }
}
```

---

## Walk-through

**`new` is total.** No `Result`. Always succeeds. Returns a tuple of the
new draft order and a single-element event list. The simplest function
in the file now.

**`add_line` builds the event in the Ok branch only.** The four `use <-`
guards short-circuit on failure. If we get past them, we construct the
new line, the new order, and the event — all in three lines. Failures
return `Error(...)` directly, which means **no event list ever gets
built on the failure path**. That's the rule: failures aren't facts.

**`place` is the interesting one.**

```gleam
use <- no_modify_placed(order)        // guard 1
case order.lines {
  [] -> Error(CannotPlaceEmptyOrder)  // guard 2 (with specific error)
  _ -> {
    use t <- result.try(total(order)) // chain — total can fail
    let placed = Order(..order, status: Placed)
    Ok(#(placed, [OrderPlaced(order.id, t)]))
  }
}
```

Three layers of "can fail":

1. The status check (zero-arg `use <-`).
2. The empty-lines check (a `case` returning `Error` directly).
3. The total computation (one-arg `use <-` with `result.try`).

Each short-circuits independently. The body — *constructing the placed
order and its event* — only runs when all three have passed. This is
exactly what the chained-failure machinery from earlier chapters was
built for.

**Why `total` is `pub`.** Two reasons. (a) Callers might want to display
a running total before placing. (b) The scenario tests want to assert on
expected totals. Exposing `total` doesn't violate the aggregate boundary
because it's a pure read — it can't put the order into a bad state.

---

## Scenario testing — commands as data

Once the aggregate has multiple operations that chain together,
per-operation tests start looking the same:

> build empty order → add line → add line → place → assert.

That's a lot of ceremony per assertion. The cleaner pattern: make the
inputs *data*, build a tiny engine to run them, write tests as
declarative scenarios.

The full file lives at `test/order_scenarios_test.gleam`. The core is
~15 lines:

```gleam
pub type OrderCommand {
  AddLine(sku: String, quantity: Int, unit_price: money.Money)
  Place
}

pub fn run(
  initial: order.Order,
  cmds: List(OrderCommand),
) -> Result(#(order.Order, List(order.OrderEvent)), order.OrderError) {
  list.try_fold(cmds, #(initial, []), apply_one)
}

fn apply_one(state, cmd) {
  let #(o, events_so_far) = state
  let step = case cmd {
    AddLine(sku, q, price) -> order.add_line(o, sku, q, price)
    Place -> order.place(o)
  }
  use #(o2, new_events) <- result.try(step)
  Ok(#(o2, list.append(events_so_far, new_events)))
}
```

`list.try_fold` walks the command list, threading `(order, events)`
through each step. The first failure short-circuits the fold and bubbles
out as `Error(...)`. Successful runs accumulate events in order.

Then tests read like specifications:

```gleam
pub fn two_lines_then_place_emits_correct_events_test() {
  let oid = test_order_id()
  let cmds = [
    AddLine("WIDGET", 2, usd(50)),
    AddLine("GADGET", 1, usd(100)),
    Place,
  ]
  let assert Ok(#(_, events)) = run(empty_draft_order(), cmds)
  assert events == [
    order.LineAdded(oid, "WIDGET", 2, usd(50)),
    order.LineAdded(oid, "GADGET", 1, usd(100)),
    order.OrderPlaced(oid, usd(200)),
  ]
}

pub fn add_line_after_place_fails_test() {
  let cmds = [
    AddLine("WIDGET", 1, usd(50)),
    Place,
    AddLine("GADGET", 1, usd(50)),  // fails — order is placed
  ]
  assert run(empty_draft_order(), cmds)
    == Error(order.CannotModifyPlacedOrder)
}
```

Each scenario is one `let cmds = [...]` followed by one assertion. The
*sequence* is the data; the *assertion* is the spec. You can read fifty
of these in two minutes and know exactly what the aggregate does.

This pattern scales. The set of failure scenarios is finite and easy to
enumerate — once they all pass, you have *high confidence* in the
aggregate's behavior, not just per-operation correctness.

---

## DDD takeaway

You've reached the natural endpoint of the aggregate-as-pure-function
trajectory:

> `aggregate × command → Result(#(new_aggregate, events), error)`

That signature is exactly what every CQRS / event-sourcing framework
treats as the central abstraction. You wrote it without a framework, in
about 100 lines of Gleam, with the type system enforcing every
invariant.

In a richer system you wouldn't return events to the caller — you'd
publish them to an event bus and forget about them. Other bounded
contexts subscribe and react. Your `Order` aggregate would be entirely
unaware that a `Shipping` context exists, yet shipping would still
happen, because shipping listens for `OrderPlaced`. **This decoupling
is the whole reason events exist as a first-class concept.**

---

## Bonus — commands as a first-class concept

Notice we kept `OrderCommand` in *test code*, not in the domain. That
was a deliberate choice — the kata is about events, not commands. But
in a fully event-sourced system, commands graduate to the domain:

```gleam
// commands flow in from the boundary (HTTP, message queue, etc.)
// events flow out to the bus
pub fn handle(
  state: Order,
  cmd: OrderCommand,
) -> Result(#(Order, List(OrderEvent)), OrderError) {
  case cmd {
    AddLine(...) -> add_line(state, ...)
    Place -> place(state)
  }
}
```

That single function is the aggregate's entire API. Everything else is
detail. CQRS frameworks (Axon, EventFlow, akka-persistence-typed) are
built around exactly this signature.

For the kata, we don't need that abstraction yet — but recognize that
the scenario engine you just wrote is a *test-time* version of the
production-time command handler. The pattern is real.

---

## What's next

Kata 6 — **Repositories.** The aggregate has been a pure function so
far. The next chapter introduces persistence: how the use case loads an
`Order` from storage, calls `place`, saves the result, and publishes
events — all without the domain code knowing what storage is.

That's where the layering from `00_introduction.md` earns its keep.
