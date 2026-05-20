# 06. Kata 5: Domain Events

## Concept

Until now, every operation on the aggregate returned the new state.
From here on, each one also returns a list of facts about what just
happened. Those facts, domain events, are immutable past-tense
records carrying enough data to describe the transition on their own.

What you get for the extra return value:

- Other parts of the system can react without the aggregate knowing they exist. Send a confirmation email when `OrderPlaced` fires; `Order` doesn't need to know email exists.
- The event stream *is* the audit log, with no separate "what happened to this order" code path.
- Once the aggregate emits a complete event log per state change, you can derive state by replaying events instead of storing it. That's the foundation CQRS and event sourcing build on.

`OrderPlaced` names a fact in the past tense, where `PlaceOrder` would
name a command in the present, a request rather than a record. Mix
the two and you lose the ability to reason about your system. Commands
and events are duals, a point the bonus section returns to.

---

## New Gleam fundamentals

The kata mostly widens the return shape, so the toolkit is what you
already know from earlier chapters.

### Tuples: `#(a, b)`

Gleam's lightweight pair / triple syntax:

```gleam
let pair = #(order, [OrderCreated(id, cid)])
let #(o, events) = pair
```

The pair bundles new state with the events from this transition without
a named record per operation.

Pattern matching on tuples works the same as anywhere else:

```gleam
case order.add_line(o, sku, q, p) {
  Ok(#(new_order, events)) -> todo
  Error(reason)            -> todo
}
```

### `result.try` chaining (earning its keep)

You met `result.try` in Kata 3, and `place` is where it earns its
keep. The `OrderPlaced` event carries the total, computing that total
can fail, and `place` has to thread the preconditions, the total, and
the event into one chain.

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
for. If `total` returns `Error`, the chain stops there; otherwise `t`
binds and execution continues. Without it you'd nest a `case` inside
another `case`.

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

- `new` emits `[OrderCreated(...)]` and is total (no `Result` wrapper).
- `add_line` emits `[LineAdded(...)]` on success.
- `place` emits `[OrderPlaced(...)]` on success, with the total computed at placement time.
- A failed operation isn't a fact, so the `Error(...)` branch returns the error by itself and never builds a partial event list.

`test/order_test.gleam` holds the per-operation spec, and
`test/order_scenarios_test.gleam` exercises the aggregate through
sequences of commands (see "Scenario testing" below).

---

## Hints: what to do

1. Implement in this order: `new_id` → `new` → guard helpers → `add_line` → `total` → `place`. `place` depends on `total`, so `total` comes first.
2. `new` is now the simplest function in the file. Build the order, attach the `OrderCreated` event, and return the tuple; no `Result` wrapper and no precondition guards.
3. Event construction lives on the `Ok` branch only. When a precondition guard returns `Error(...)`, the `use <-` chain short-circuits and you never reach the line that builds the event list.
4. `place` is the interesting one. Sketch:
   - Guard the placed status
   - Check that lines isn't empty (else `CannotPlaceEmptyOrder`)
   - Compute the total via `result.try` (else propagate the underlying error)
   - Construct the placed order plus its `OrderPlaced` event
5. Don't share event-construction code across operations. Each event has a different shape, so build each one inline at the emission site; it's a handful of lines per operation.
6. The kata 4 helpers carry over untouched: `no_modify_placed`, `non_empty_sku`, `positive_qty`, and `currency_matches` keep their signatures and bodies. They short-circuit before you build anything.

---

## Walk-through

`new` is total: a tuple of the new draft order and an event list with
one `OrderCreated`. `add_line` builds its event in the `Ok` branch
only, since the `use <-` guards short-circuit on failure and a failure
isn't a fact.

`place` is the chapter's showpiece (the code block in
"result.try chaining" above): a zero-arg `use <-` for the status guard,
a `case` for the empty-lines guard, and a `use t <- result.try` for
the fallible total. Three failure layers stack independently; the
placed-order record and its event come together only after every layer
passes.

`total` is `pub` because callers want to display a running total before
placing, and the scenario tests assert on expected totals. Exposing it
doesn't break the aggregate boundary, since it's a pure read.

---

## Scenario testing: commands as data

Once the aggregate has multiple operations that chain together,
per-operation tests start looking the same:

> build empty order → add line → add line → place → assert.

That's a lot of ceremony per assertion. The cleaner pattern lifts the
inputs to data, runs them through a tiny engine, and lets the tests
read as declarative scenarios.

The full file lives at `test/order_scenarios_test.gleam`; the core is
about fifteen lines.

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
out as `Error(...)`, while successful runs accumulate events in order.

Tests then read like specifications.

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
    AddLine("GADGET", 1, usd(50)),  // fails because order is placed
  ]
  assert run(empty_draft_order(), cmds)
    == Error(order.CannotModifyPlacedOrder)
}
```

Each scenario is one `let cmds = [...]` followed by one assertion,
where the command sequence carries the meaning and the assertion locks
it in. Fifty of these read in two minutes and you know exactly what the
aggregate does.

The pattern scales because the set of failure scenarios is finite and
easy to enumerate; once they all pass, you trust the aggregate's
behavior rather than just its per-operation correctness.

---

## Takeaway

The aggregate-as-pure-function trajectory reaches its natural
endpoint:

> `aggregate × command → Result(#(new_aggregate, events), error)`

That signature is the central abstraction every CQRS and
event-sourcing framework reaches for, written here without a framework
in about a hundred lines of Gleam, with the type system enforcing
every invariant.

A richer system wouldn't return events to the caller. It would
publish to a bus and let other bounded contexts subscribe, so `Order`
stays unaware that `Shipping` exists yet shipping still happens
because shipping listens for `OrderPlaced`. That decoupling earns
events their place as a first-class concept.

---

## Bonus: commands as a first-class concept

`OrderCommand` lives in test code rather than in the domain. That was
deliberate; this kata is about events. In a fully event-sourced system,
commands graduate to the domain:

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

That function is the aggregate's API; everything else is detail. CQRS
frameworks like Axon, EventFlow, and akka-persistence-typed sit on this
signature.

The kata doesn't need that abstraction yet, but the scenario engine you
just wrote is the test-time twin of the production command handler,
the same pattern wearing a different label.

---

## What's next

Kata 6: **Repositories.** The aggregate has been a pure function so
far; the next chapter introduces persistence. A use case will load an
`Order` from storage, call `place`, save the result, and publish the
events, and the domain code never learns what storage is.

That's where the layering from `00_introduction.md` starts earning its
keep.
