# 05. Kata 4: Aggregates (`Order`)

## Concept

An aggregate clusters related objects into a unit. The aggregate root
is the only entry point; everything outside goes through it. The root
enforces invariants that span multiple internal pieces.

An `Order` has `OrderLine`s. Rules like "an order must have at least one
line to be placed" or "every line must share a currency" are properties
of the aggregate, which no individual line can enforce on its own, so
`OrderLine` stays internal, and `Order` is the only thing the outside
world touches.

Gleam's module system starts pulling its weight here. A module is the
natural unit for an aggregate, and the module seals anything not marked
`pub`.

---

## New Gleam fundamentals

### Internal types (no `pub`)

A type without `pub` is private to its module:

```gleam
type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}
```

Outside the module, `OrderLine` does not exist as a name. `Order` exposes
operations that manipulate lines internally, and nothing outside can
construct or hold one. The type system enforces the rule against reaching
into the aggregate.

### Multiple guards in sequence

`use <-` carried one guard in Kata 2. Aggregate invariants stack several:

```gleam
pub fn add_line(order, sku, quantity, unit_price) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)
  // ... do the work
}
```

Each line names one precondition, and the body reads top-to-bottom like a spec.

### `list.try_map` and `list.try_fold`

For aggregating over a list when each step can fail:

- `list.try_map(list, f)` runs `f` on each element and short-circuits on the first `Error`. Returns `Result(List(b), e)`.
- `list.try_fold(list, init, f)` folds with a fallible combining function and short-circuits the same way.

`order.total` uses both: multiply each line's price by its quantity, then
sum the results. Either stage can fail.

---

## Task

Create `src/order.gleam` exposing:

```gleam
import customer.{type CustomerId}
import money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

// Internal. Outside this module, this type does not exist.
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

Aggregate invariants, the reason the type exists:

1. `add_line` rejects empty SKUs and non-positive quantities.
2. `add_line` fails with `CannotModifyPlacedOrder` if status is `Placed`.
3. `add_line` fails with `CurrencyMismatch` when the new line's currency differs from existing lines.
4. `place` fails with `CannotPlaceEmptyOrder` if there are no lines.
5. `place` transitions `Draft → Placed`.
6. `place` fails with `CannotModifyPlacedOrder` on an already-placed order.
7. `total` sums all line totals, and fails on an empty order or any underlying money error.

The tests in `test/order_test.gleam` are the spec.

---

## Hints: what to do

1. Start with the naive version. `add_line` is one big nested `case`. Get it green, then carve out the helpers. The duplication is the signal.
2. Each invariant becomes a guard helper: `no_modify_placed`, `non_empty_sku`, `positive_qty`, `currency_matches`. Each takes a callback (`then: fn() -> Result(...)`) and returns `Error(SpecificReason)` when the rule is violated, otherwise delegating to the callback.
3. Apply them via `use <-`, stacked in `add_line`, so the body becomes "run the rules, then do the one record update."
4. State checks come before arg validation. A caller passing `("", -3, ...)` against a placed order sees `CannotModifyPlacedOrder` first, since `Placed` already locks the order out of further modification.
5. Reuse `no_modify_placed` in `place`. "Re-place a placed order" and "modify a placed order" violate the same invariant, so the helper names a domain rule that applies wherever it fits.
6. `Order(..order, lines: [new_line, ..order.lines])` is record update plus list cons. Without record update, changing one field forces retyping every field of `Order`; with it, only the change shows.
7. `total` works in two stages:
   - line-by-line, multiply `unit_price * quantity` with `list.try_map` (each multiply can fail);
   - sum the per-line totals with `list.try_fold`, starting from `money.zero(first.unit_price)` (each `money.add` can fail).
   Both stages return `Result(_, money.MoneyError)`; translation to `OrderError` uses `result.map_error`.
8. `new` does not return `Result`. A brand-new draft order with no lines is always valid, so `place` enforces "an empty order cannot be placed." Constructors stay honest about what they validate.

If `add_line` runs longer than ~10 lines after the refactor, something
has gone wrong.

---

## Walk-through

`add_line` resolves into a short stack of preconditions with one line of
real work underneath. Each `use <-` names a domain rule, and the mutation
is a record update at the bottom. Aggregate code reads like a flat list
of invariants followed by the transition.

Order of preconditions matters. State checks (`no_modify_placed`) come
before arg validation (`non_empty_sku`, `positive_qty`), so a caller
passing `("", -3, ...)` against a placed order deserves
`CannotModifyPlacedOrder` ahead of `EmptySku`. `Placed` locks out further
modification, and the rest is moot.

`place` reuses `no_modify_placed` because "re-place a placed order" and
"modify a placed order" violate the same invariant. The helper names a
domain rule that applies wherever it fits.

`Order(..order, lines: [new_line, ..order.lines])` is record update plus
list cons. Without record update, changing one field forces relisting
every field of `Order`; with it, only the change shows.

`total` uses `try_map` then `try_fold`: map each line to its line total
with `money.multiply`, then fold those with `money.add`. Both stages
short-circuit on the first failure.

The `case order.lines` wrapper around `total` covers two cases:

- A non-empty order matches `[first, ..]`, which supplies a valid currency to seed `money.zero`.
- An empty order has no meaningful total, so `Error(InvalidOrderTotal)` is the honest answer.

---

## Critique

Collapsing `money.MoneyError` to `InvalidOrderTotal` flattens the
diagnostic, so an underlying overflow and a currency mismatch from the
money layer look identical to the caller. Two options:

- (a) define richer `OrderError` variants (`OrderCurrencyMismatch`, `OrderOverflow`) and translate explicitly;
- (b) wrap the underlying error as `TotalCalculationFailed(money.MoneyError)`.

**The book recommends (b).** It preserves the cause without exploding
the error vocabulary, and it keeps the layering honest: `OrderError`
doesn't have to know what failure modes `Money` will grow next month.
Option (a) is the right choice only when the outer layer needs to
*react* differently per cause (different HTTP status codes, different
retry policies); when callers just want to log the cause, wrapping is
cheaper and ages better.

`OrderLine` is fully internal, with no `pub` and no `opaque`. The original spec
said `pub opaque type OrderLine`, which also provides opacity. Private-only
is cleaner because it signals that nothing outside should even name the
type. Whether external code ever needs to talk about an `OrderLine` (say,
as a return type) decides between the two; in this aggregate, it does not.

`new_id` does not trim, so `new_id("   ")` succeeds with a whitespace ID.
That is a bug; the fix mirrors `customer.new_id`.

---

## Takeaway

The `Order` module is now a boundary. Outside it, `OrderLine` is not
constructible, and no caller can put an order into an inconsistent state.
"Currency homogeneity across lines" stops being a concept anyone has to
remember, because the only door in enforces it.

When DDD writers say "the aggregate is a consistency boundary," they
mean the module. Every operation either succeeds with a fully-valid new
state or fails with a typed error explaining why.

---

## What's next

Kata 5 takes on domain events: state transitions that also report what
happened. `add_line` and `place` will return the new `Order` along with a
list of facts (`LineAdded`, `OrderPlaced`) that other parts of the system
can react to without the aggregate knowing about them.

The existing toolkit carries straight through: opacity, smart
constructors, `use <-` chains, record update. Events add to the
aggregate's return type; nothing needs redesigning.
