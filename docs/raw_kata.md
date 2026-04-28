# Domain-Driven Design Katas in Gleam

A progression of small focused katas, one DDD concept each, building from value objects up through aggregates and domain events.

---

## Progression

1. **Value Objects** — immutable, defined by attributes (Email, Money)
2. **Entities** — things with identity that persists (Customer)
3. **Aggregates** — clusters with a root that enforces invariants (Order + lines)
4. **Domain Events** — facts about what happened (OrderPlaced)
5. **Repositories** — abstraction over persistence
6. **Bounded Contexts** — same word, different model

---

## Kata 1: Value Objects — `Email`

A **value object** is defined entirely by its attributes, not identity. Two `Email`s with the same string are interchangeable. The key move: you can't construct an invalid one — validation happens at the boundary, then the rest of your code trusts it.

In Gleam, the idiom is the **opaque type**: hide the constructor, expose a smart constructor returning `Result`.

### Task

```gleam
pub opaque type Email {
  Email(value: String)
}

pub type EmailError {
  Empty
  MissingAt
  // add more as you see fit
}

pub fn new(raw: String) -> Result(Email, EmailError) {
  // your code
}

pub fn to_string(email: Email) -> String {
  // your code
}
```

Rules:
- Trim whitespace
- Reject empty
- Exactly one `@`
- Both sides of `@` non-empty

### Solution

```gleam
import gleam/string

pub opaque type Email {
  Email(value: String)
}

pub type EmailError {
  Empty
  MissingAt
  TooManyAt
  MissingTextBeforeAt
  MissingTextAfterAt
}

pub fn new(raw: String) -> Result(Email, EmailError) {
  let trimmed = string.trim(raw)
  case string.split(trimmed, "@") {
    [""] -> Error(Empty)
    [_] -> Error(MissingAt)
    ["", _] -> Error(MissingTextBeforeAt)
    [_, ""] -> Error(MissingTextAfterAt)
    [local, domain] -> Ok(Email(local <> "@" <> domain))
    _ -> Error(TooManyAt)
  }
}

pub fn to_string(email: Email) -> String {
  email.value
}
```

### Notes

**What's solid:**
- `opaque` correctly hides the constructor — outside this module, nobody can build an `Email` without going through `new`. That's the whole game with value objects.
- Pattern order matters: `[""]` is checked before `[_]`, so the empty case is caught before the generic single-element case.
- Returning `Result(Email, EmailError)` instead of throwing or returning a bool makes callers handle failure explicitly.

**Small things:**
- `Ok(Email(local <> "@" <> domain))` rebuilds the same string you already have. Just `Ok(Email(trimmed))` works — the split was for validation, not transformation.

### DDD takeaway

Anywhere in your codebase that has a parameter `email: Email`, you have a *compile-time guarantee* it's been validated. No defensive checks, no "did someone forget to validate this?" anxiety. Validation happens once, at the boundary where strings come in, and the type system carries the proof everywhere else. That's the payoff for the upfront ceremony.

---

## Kata 2: Value Objects — `Money`

Same shape (opaque type, smart constructor) but now with **composition** and **operations that can fail at the domain level**. Money has two attributes — amount and currency — and adding USD to EUR is nonsense, so `add` has to express that.

### Task

```gleam
pub type Currency {
  USD
  EUR
  GBP
}

pub opaque type Money {
  Money(amount: Int, currency: Currency)
}

pub type MoneyError {
  NegativeAmount
  CurrencyMismatch
}

// Amount is in minor units (cents/pence). $1.50 -> new(150, USD).
pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError)
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError)
pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError)
pub fn multiply(money: Money, factor: Int) -> Money
```

Rules:
- Reject negative amounts in `new`
- `add` and `subtract` fail with `CurrencyMismatch` if currencies differ
- `subtract` shouldn't produce negative money (return `NegativeAmount`)

### Solution v1 — straightforward

```gleam
pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError) {
  case amount >= 0 {
    True -> Ok(Money(amount, currency))
    False -> Error(NegativeAmount)
  }
}

pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  case a.currency == b.currency {
    False -> Error(CurrencyMismatch)
    True -> Ok(Money(a.amount + b.amount, a.currency))
  }
}

pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError) {
  case a.currency == b.currency {
    False -> Error(CurrencyMismatch)
    True -> {
      let amt = a.amount - b.amount
      case amt >= 0 {
        True -> Ok(Money(amt, a.currency))
        False -> Error(NegativeAmount)
      }
    }
  }
}

pub fn multiply(money: Money, factor: Int) -> Money {
  Money(money.amount * factor, money.currency)
}
```

### Solution v2 — funnel through `new`, extract precondition helper

```gleam
pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError) {
  case amount >= 0 {
    True -> Ok(Money(amount, currency))
    False -> Error(NegativeAmount)
  }
}

fn require_same_currency(
  a: Money,
  b: Money,
  then: fn() -> Result(Money, MoneyError),
) -> Result(Money, MoneyError) {
  case a.currency == b.currency {
    False -> Error(CurrencyMismatch)
    True -> then()
  }
}

pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount + b.amount, a.currency)
}

pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount - b.amount, a.currency)
}

pub fn multiply(money: Money, factor: Int) -> Result(Money, MoneyError) {
  new(money.amount * factor, money.currency)
}
```

### Notes

**Funneling through `new`.** Every constructor path re-validates. `subtract` no longer needs its own `amt >= 0` check — `new` handles it. `multiply` now correctly catches negative factors for free. The invariant is enforced in exactly one place, and you literally cannot construct a `Money` that violates it.

**`use <- require_same_currency(a, b)`.** Spotted that `case a.currency == b.currency` was duplicated, abstracted it into a continuation-passing helper, and used Gleam's `use` sugar to keep the call sites linear. The helper takes the precondition; the body assumes it holds. Reads top-to-bottom like a list of business rules: *require same currency, then compute.*

This is the same pattern as `use customer <- result.try(find_customer(id))` — how Gleam programmers chain things that can fail without nesting `case` ten levels deep.

**Storing amounts as `Int` minor units.** Floats and money don't mix — `0.1 + 0.2 ≠ 0.3`. Real systems store cents. This is a domain modeling decision encoded in the type.

**Why `add` returns `Result`.** In a primitive world `add(usd_5, eur_3)` silently gives you `8` of nothing. In a domain-modeled world, it's a `CurrencyMismatch` error you must handle. The bug becomes impossible to ignore.

### DDD takeaway

You have a module where the *only* way to produce a `Money` value is one that passes every invariant. Callers cannot lie about currency. Callers cannot smuggle in negative amounts. Every `Money` in your system is, by construction, valid. This is what people mean by "make illegal states unrepresentable" — it's not a slogan, it's the literal property your type now has.

---

## Kata 3: Entities — `Customer`

The conceptual shift: a customer named "Alice" who becomes "Alice Smith" tomorrow is *the same customer*. Identity persists, attributes change. Equality is by **ID**, not by value — Gleam's `==` will give you the wrong answer if you use it on entities.

### Task

```gleam
import your_app/email.{type Email}

pub opaque type CustomerId {
  CustomerId(value: String)
}

pub opaque type Customer {
  Customer(id: CustomerId, name: String, email: Email)
}

pub type CustomerError {
  EmptyName
  EmptyId
}

pub fn new_id(raw: String) -> Result(CustomerId, CustomerError)
pub fn new(id: CustomerId, name: String, email: Email) -> Result(Customer, CustomerError)
pub fn id(customer: Customer) -> CustomerId
pub fn rename(customer: Customer, new_name: String) -> Result(Customer, CustomerError)
pub fn change_email(customer: Customer, new_email: Email) -> Customer
pub fn same_customer(a: Customer, b: Customer) -> Bool
```

Rules:
- `CustomerId` is its own opaque type — never use raw strings as IDs in domain code
- Reject empty names and empty ID strings
- `rename` and `change_email` return a *new* `Customer` with the same ID
- `same_customer` compares by ID only

### Solution

```gleam
import email.{type Email}
import gleam/string

pub opaque type CustomerId {
  CustomerId(value: String)
}

pub opaque type Customer {
  Customer(id: CustomerId, name: String, email: Email)
}

pub type CustomerError {
  EmptyName
  EmptyId
}

pub fn new_id(raw: String) -> Result(CustomerId, CustomerError) {
  case string.length(raw) {
    0 -> Error(EmptyId)
    _ -> Ok(CustomerId(raw))
  }
}

pub fn new(
  id: CustomerId,
  name: String,
  email: Email,
) -> Result(Customer, CustomerError) {
  case string.length(name) {
    0 -> Error(EmptyName)
    _ -> Ok(Customer(id, name, email))
  }
}

pub fn id(customer: Customer) -> CustomerId {
  customer.id
}

pub fn rename(
  customer: Customer,
  new_name: String,
) -> Result(Customer, CustomerError) {
  new(customer.id, new_name, customer.email)
}

pub fn change_email(customer: Customer, new_email: Email) -> Customer {
  Customer(customer.id, customer.name, new_email)
}

pub fn same_customer(a: Customer, b: Customer) -> Bool {
  a.id == b.id
}
```

### Notes

**Funneling `rename` through `new`** — same instinct from Money v2 applied here. One free invariant check, one place to maintain it.

**On `string.length(raw) == 0`** — functionally correct, but `raw == ""` is cheaper (no traversal) and more obviously a "is it empty" check. Even better: `string.is_empty(raw)`.

**On trimming** — `new_id("   ")` and `new(... name: "   ")` both succeed as written. Whether that's a bug depends on the domain. The deeper point: every place a string enters your domain is a chance for invariants to slip in.

**On `same_customer`** — because `CustomerId` is opaque and constructed only via `new_id`, `a.id == b.id` is safe. The opacity does double duty: it enforces validity and gives trustworthy equality.

**The `Email` type is now a building block.** No re-validating an email string here — the type carries proof. This compounding is why value objects pay off; entities get to assume their parts are well-formed.

**Why `same_customer` and not just `==`.** `alice_v1 == alice_v2` after a rename returns `False` (structs differ), but domain-wise they're the same person. Naming the function forces callers to ask: structural equality or identity equality? For entities, almost always identity.

### DDD takeaway

You have a `Customer` whose attributes can change but whose identity is permanent and trusted. `rename` and `change_email` are *state transitions* — each produces a new immutable value representing the next moment in that customer's life. In an event-sourced system, each would emit a `CustomerRenamed` or `EmailChanged` event and the customer's full history would be reconstructible by replaying them. Already structured for that without trying.

---

## Kata 4: Aggregates — `Order`

An **aggregate** is a cluster of related objects treated as a unit. One object — the **aggregate root** — is the only entry point; everything outside the aggregate goes through it. The root's job is to enforce **invariants that span multiple internal pieces**.

Concrete example: an `Order` has `OrderLine`s. Rules like "an order must have at least one line to be placed" or "you can't add lines to a placed order" are invariants no single line can enforce alone — they're properties of the whole. So the line type stays internal, and `Order` is the only thing the outside world touches.

### Task

```gleam
import your_app/customer.{type CustomerId}
import your_app/money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

pub opaque type OrderLine {
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
}

pub fn new_id(raw: String) -> Result(OrderId, OrderError)
pub fn new(id: OrderId, customer_id: CustomerId) -> Order
pub fn add_line(order: Order, sku: String, quantity: Int, unit_price: Money) -> Result(Order, OrderError)
pub fn place(order: Order) -> Result(Order, OrderError)
pub fn total(order: Order) -> Result(Money, OrderError)
```

Rules — these are the *aggregate invariants*, the whole reason this type exists:

1. `add_line` rejects empty SKUs and non-positive quantities
2. `add_line` fails with `CannotModifyPlacedOrder` if status is `Placed`
3. `add_line` fails with `CurrencyMismatch` if the new line's currency differs from existing lines
4. `place` fails with `CannotPlaceEmptyOrder` if there are no lines
5. `place` transitions Draft → Placed
6. `total` sums all line totals; fails on empty order or currency mismatch

### Solution

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

fn non_empty_sku(sku: String, then: fn() -> Result(a, OrderError)) {
  case sku {
    "" -> Error(EmptySku)
    _ -> then()
  }
}

fn positive_qty(q: Int, then: fn() -> Result(a, OrderError)) {
  case q > 0 {
    True -> then()
    False -> Error(NonPositiveQuantity)
  }
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(Order, OrderError) {
  use <- positive_qty(quantity)
  use <- non_empty_sku(sku)
  use <- no_modify_placed(order)
  let new_line = OrderLine(sku, quantity, unit_price)
  case order.lines {
    [ol, ..] -> {
      case money.same_currency(ol.unit_price, unit_price) {
        True ->
          Ok(Order(
            order.id,
            order.customer_id,
            [new_line, ..order.lines],
            order.status,
          ))
        False -> Error(CurrencyMismatch)
      }
    }
    _ ->
      Ok(Order(
        order.id,
        order.customer_id,
        [new_line, ..order.lines],
        order.status,
      ))
  }
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
    [ol, ..] -> {
      use amounts <- result.try(
        list.try_map(order.lines, fn(ol) {
          money.multiply(ol.unit_price, ol.quantity)
        })
        |> result.map_error(fn(_) { InvalidOrderTotal }),
      )

      list.try_fold(amounts, money.zero(ol.unit_price), money.add)
      |> result.map_error(fn(_) { InvalidOrderTotal })
    }
    _ -> Error(InvalidOrderTotal)
  }
}
```

### Notes

**Reusing `no_modify_placed` in `place`.** The same precondition guards both `add_line` AND `place`, because "you can't re-place a placed order" is the same invariant as "you can't modify a placed order." The helper isn't a code-dedup trick — it's a *named domain rule* applied wherever it's relevant.

**`list.try_map` + `list.try_fold`.** Right shape for `total`. Map each line to its line-total (each multiply can fail), then fold them with `money.add` (each addition can fail). Both stages short-circuit on the first failure.

### Critiques

**Order of preconditions in `add_line`.** Currently `positive_qty` → `non_empty_sku` → `no_modify_placed`. If a caller tries to add `("", -3, ...)` to a placed order, they'll see `NonPositiveQuantity` — but the more important fact is that the order is locked. State checks should generally come first; arg validation second.

**Duplication in `add_line`'s Ok branches.** Both branches construct an identical `Order(...)`. Lift the construction out and make currency just another precondition:

```gleam
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
```

Then `add_line` collapses to:

```gleam
pub fn add_line(order, sku, quantity, unit_price) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)
  let new_line = OrderLine(sku, quantity, unit_price)
  Ok(Order(..order, lines: [new_line, ..order.lines]))
}
```

Five lines of preconditions, one line of work. Reads top-to-bottom like a spec. Note `Order(..order, lines: ...)` — Gleam's record update syntax saves you from re-listing every field.

**Collapsing `money.MoneyError` to `InvalidOrderTotal`.** As written, an overflow and a currency mismatch are indistinguishable to the caller. Two options: (a) define `OrderError` variants like `OrderCurrencyMismatch` and `OrderOverflow` and translate explicitly, or (b) wrap the underlying error: `TotalCalculationFailed(money.MoneyError)`. (b) is what people usually settle on — it preserves the cause without flattening the error vocabulary.

### DDD takeaway

The `Order` module is now a *boundary*. Outside it, `OrderLine` doesn't exist as a constructible thing. Outside it, you can't put an order into an inconsistent state. Outside it, "currency homogeneity" isn't even a concept you have to remember — it's enforced by the only door in. When DDD people say "the aggregate is a consistency boundary," this module is exactly what they mean. Every aggregate operation either succeeds with a fully-valid new state, or fails with a typed error explaining why. There is no third outcome.

---

## Kata 5: Domain Events

The shift: instead of operations returning just *the new state*, they return *the new state plus a list of facts about what changed*. Those facts — domain events — are immutable, named in past tense, and carry enough data to describe what happened.

Why bother? Three reasons that compound:
- Other parts of the system can react to events without the aggregate knowing about them (send a confirmation email when `OrderPlaced` fires — the order doesn't need to know email exists)
- Audit log for free
- Seed of event sourcing, where state is *derived* from the event log rather than stored directly

### Task

```gleam
pub type OrderEvent {
  OrderCreated(order_id: OrderId, customer_id: CustomerId)
  LineAdded(order_id: OrderId, sku: String, quantity: Int, unit_price: Money)
  OrderPlaced(order_id: OrderId, total: Money)
}
```

Past tense: `OrderPlaced`, not `PlaceOrder`. Events are *facts that already happened*, not *commands to do something*. This naming is doctrine — once you start mixing them you lose the ability to reason about your system.

Modify `new`, `add_line`, and `place` to return both the updated aggregate AND the events emitted.

```gleam
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
- `new` emits `[OrderCreated(...)]`
- `add_line` emits `[LineAdded(...)]` on success
- `place` emits `[OrderPlaced(...)]` on success, with the total computed at placement time
- Failures emit no events — events represent things that *actually happened*, and a failed operation didn't happen

### Things to chew on

**Why a list?** Most operations emit one event, but some emit several (e.g., a future `cancel_and_refund` might emit `[OrderCancelled, RefundIssued]`). Returning `List(OrderEvent)` keeps the shape uniform.

**Why include data in the event, not just the type?** `OrderPlaced` could just be a marker, but then a downstream "email the customer their total" handler would have to look the order up again. Events should carry enough context to be processed standalone. They're messages, not pointers.

**Hidden challenge:** `OrderPlaced` carries the total, which means `place` now has to compute the total — which can fail. So `place` now has to chain: validate preconditions → compute total → produce event. This is where `use <-` and `result.try` start really earning their keep.

### DDD takeaway

In a richer system, you wouldn't return events to the caller — you'd publish them to an event bus and forget about them. Other bounded contexts subscribe and react. Your `Order` aggregate would be entirely unaware that a `Shipping` context exists, yet shipping would still happen, because shipping listens for `OrderPlaced`. This decoupling is the whole reason events exist as a first-class concept.

---

## Still to come

- **Kata 6: Repositories** — abstraction over persistence
- **Kata 7: Bounded Contexts** — same word, different model