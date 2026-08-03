# 05. Kata 4: Aggregates (`Order`)

## Concept

An **aggregate** is a cluster of related objects treated as a unit. One
object, the **aggregate root**, is the only entry point; everything
outside the aggregate goes through it. The root's job is to enforce
**invariants that span multiple internal pieces.**

Concrete example: an `Order` has `OrderLine`s. Some rules span multiple
lines:

- *"an order must have at least one line to be placed"*
- *"every line in an order must be in the same currency"*

No single line can enforce them; they're properties of the whole. So
`OrderLine` stays internal, and `Order` is the only thing the outside
world touches.

This is the moment Gleam's module system starts pulling its weight. A
module is the natural unit for an aggregate: what's `pub` is the
aggregate's API; what isn't is sealed inside.

---

## New Gleam fundamentals

### Internal types: no `pub`, no name outside

A type without `pub` is private to its module:

```gleam
type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}
```

Outside the module, `OrderLine` doesn't exist as a name. The aggregate
root `Order` exposes operations that *manipulate* lines internally, but no
one outside can construct or hold one directly. This is the hard,
type-system-enforced version of "don't reach into the aggregate."

### Guards stack

Kata 2 used one `use <-` guard. Aggregate invariants need several:

```gleam
pub fn add_line(order, sku, quantity, unit_price) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)
  // ... do the work
}
```

Each line is one named precondition; the function reads top-to-bottom like
a spec.

### `list.try_map` and `list.try_fold`: fallible iteration

Aggregating over a list where each step can fail:

- `list.try_map(list, f)`: runs `f` on each element; short-circuits with the first `Error`. Returns `Result(List(b), e)`.
- `list.try_fold(list, init, f)`: folds the list with a fallible combining function. Short-circuits.

`order.total` uses both: multiply each line's price by its quantity (each
can fail), then sum the results (each addition can fail).

---

## Task

Create `src/order.gleam` exposing:

```gleam
import customer.{type CustomerId}
import money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

// Internal — outside this module, this type does not exist.
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

pub fn new_id(raw: String) -> Result(OrderId, OrderError)
pub fn new(id: OrderId, customer_id: CustomerId) -> Order
pub fn add_line(order: Order, sku: String, quantity: Int, unit_price: Money) -> Result(Order, OrderError)
pub fn place(order: Order) -> Result(Order, OrderError)
pub fn total(order: Order) -> Result(Money, OrderError)
```

Aggregate invariants, the reason this type exists:

1. `add_line` rejects empty SKUs and non-positive quantities.
2. `add_line` fails with `CannotModifyPlacedOrder` if status is `Placed`.
3. `add_line` fails with `CurrencyMismatch` if the new line's currency differs from existing lines.
4. `place` fails with `CannotPlaceEmptyOrder` if there are no lines.
5. `place` transitions `Draft -> Placed`.
6. `place` fails with `CannotModifyPlacedOrder` on an already-placed order.
7. `total` sums all line totals; fails on empty order or any underlying money error.

The tests in `test/order_test.gleam` are the spec.

---

## Hints

1. **Implement straight first, then refactor.** The naive `add_line` is one big nested `case`. Get it green, then carve out the helpers. You'll *feel* the duplication; that's the signal to refactor.
2. **Each invariant becomes a guard helper.** One per rule: `no_modify_placed`, `non_empty_sku`, `positive_qty`, `currency_matches`. Each takes a callback (`then: fn() -> Result(...)`). Each returns `Error(SpecificReason)` if the rule is violated, else delegates to the callback.
3. **Apply them via `use <-`.** Stack the `use <-` lines in `add_line`. The body becomes "run the rules, then do the one record update."
4. **State checks before arg validation.** The sequence of guards determines which error the caller sees. If a caller tries `("", -3, ...)` against a *placed* order, the most informative error is `CannotModifyPlacedOrder`, not `EmptySku`.
5. **Reuse `no_modify_placed` in `place`.** "You can't re-place a placed order" is the *same* invariant as "you can't modify a placed order." This is the cleanest demonstration that the helpers aren't code dedup; they're named domain rules applied wherever relevant.
6. **`Order(..order, lines: [new_line, ..order.lines])`.** Record update + list cons. Without record update you'd be re-typing every field of `Order` to change one. With it, the change is what's interesting.
7. **For `total`, think in two stages.**
   - Stage 1: line-by-line, multiply `unit_price * quantity`. Each multiply can fail. Use `list.try_map`.
   - Stage 2: sum the per-line totals. Each `money.add` can fail. Use `list.try_fold`, starting from `money.zero(first.unit_price)`.
   - Both stages return `Result(_, money.MoneyError)`. Translate to `OrderError` with `result.map_error`.
8. **`new` doesn't return `Result`.** A brand-new draft order with an empty line list is always valid. That you can't `place` it yet is enforced *by `place`*, not by `new`. Keep the constructors honest about what they validate.

If you find yourself writing more than ~10 lines inside `add_line` after
the refactor, you've gone wrong somewhere.

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

pub fn new_id(raw: String) -> Result(OrderId, OrderError) {
  case raw {
    "" -> Error(EmptyOrderId)
    _ -> Ok(OrderId(raw))
  }
}

pub fn new(id: OrderId, customer_id: CustomerId) -> Order {
  Order(id, customer_id, [], Draft)
}

fn no_modify_placed(
  o: Order,
  then: fn() -> Result(t, OrderError),
) -> Result(t, OrderError) {
  case o.status == Placed {
    False -> then()
    True -> Error(CannotModifyPlacedOrder)
  }
}

fn non_empty_sku(
  sku: String,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case sku {
    "" -> Error(EmptySku)
    _ -> then()
  }
}

fn positive_qty(
  q: Int,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case q > 0 {
    True -> then()
    False -> Error(NonPositiveQuantity)
  }
}

fn currency_matches(
  existing: List(OrderLine),
  new_price: Money,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
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
) -> Result(Order, OrderError) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)
  let new_line = OrderLine(sku, quantity, unit_price)
  Ok(Order(..order, lines: [new_line, ..order.lines]))
}

pub fn place(order: Order) -> Result(Order, OrderError) {
  use <- no_modify_placed(order)
  case order.lines {
    [] -> Error(CannotPlaceEmptyOrder)
    _ -> Ok(Order(..order, status: Placed))
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

**Five lines of preconditions, one line of work.** That's `add_line`. Each
`use <-` line is a named domain rule. The actual mutation is a single
record-update at the bottom. This is what aggregate code should feel like:
a flat list of invariants followed by the transition.

**Guard sequence matters.** State checks (`no_modify_placed`) come before
argument validation (`non_empty_sku`, `positive_qty`). A placed order is
locked; `CannotModifyPlacedOrder` is the informative error, and the
argument problems are moot.

**Reusing `no_modify_placed` in `place`.** "You can't re-place a placed
order" is the *same invariant* as "you can't modify a placed order." The
helper isn't a code-dedup trick; it's a *named domain rule* applied
wherever it's relevant.

**`Order(..order, lines: [new_line, ..order.lines])`.** Record update plus
list cons. Without record update the body would re-list every field of
`Order` just to change one. With it, the change is what's interesting.

**`total` uses `try_map` then `try_fold`.** Map each line to its
line-total (each `money.multiply` can fail); fold those with `money.add`
(each addition can fail). Both stages short-circuit on the first failure.

**The `case order.lines` wrapper in `total`.**

- An empty order has no first line to seed `money.zero`. The `[first, ..]` pattern gets us a valid currency to start from.
- An empty order has no meaningful total to compute. `Error(InvalidOrderTotal)` is the honest answer.

---

## Critique

**Collapsing `money.MoneyError` to `InvalidOrderTotal`.** As written, an
underlying overflow and a currency mismatch from the money layer are
indistinguishable to the caller. Two options:

- (a) Define richer `OrderError` variants (`OrderCurrencyMismatch`, `OrderOverflow`) and translate explicitly.
- (b) Wrap the underlying error: `TotalCalculationFailed(money.MoneyError)`.

Option (b) is what most projects settle on; it preserves the cause without
exploding the error vocabulary.

**`OrderLine` is fully internal (no `pub`, no `opaque`).** The original
spec said `pub opaque type OrderLine`. Both work for opacity, but
private-only is cleaner: it signals that nobody outside should even *name*
this type, much less manipulate one. The decision is whether external code
ever needs to *talk about* an `OrderLine` (e.g., as a return type); in
this aggregate, no.

**`new_id` doesn't trim.** `new_id("   ")` succeeds with a whitespace ID.
That is probably a bug; the fix is the same trim as `customer.new_id`.

---

## DDD takeaway

The `Order` module is now a *boundary*. Outside it:

- `OrderLine` doesn't exist as a constructible thing.
- You can't put an order into an inconsistent state.
- "Currency homogeneity across lines" isn't even a concept you have to remember; the only door in enforces it.

When DDD people say *"the aggregate is a consistency boundary,"* this
module is exactly what they mean. Every aggregate operation either
succeeds with a fully-valid new state, or fails with a typed error
explaining why. There is no third outcome.

---

## What's next

Kata 5: **Domain Events.** State transitions that *also* report what
happened. `add_line` and `place` will return not just the new `Order` but
also a list of facts (`LineAdded`, `OrderPlaced`). Other parts of the
system can react to those facts without the aggregate knowing about them.

The toolkit you now have (opacity, smart constructors, `use <-` chains,
record update) carries straight through. Events are an *additive* change
to the aggregate's return type, not a redesign.
