# 03 — Kata 2: Value Objects with operations (`Money`)

## Concept

Same shape as `Email` (opaque type, smart constructor) but now with two new
pressures:

1. **Composition.** A `Money` has *two* attributes — amount and currency — and they have to stay coherent.
2. **Operations that can fail at the domain level.** Adding USD to EUR is nonsense; the type system should stop it.

This is where DDD starts to feel less like "wrap your strings" and more like
*encoding the rules of the domain into the types*. The type doesn't just
store data — it carries the operations that respect its invariants.

---

## New Gleam fundamentals

You'll need two more concepts on top of what Kata 1 used.

### Record update syntax

To produce a "modified" copy of a record without re-listing every field:

```gleam
let updated = Money(..money, amount: 0)
```

`..money` says "take all the fields from this value, then override the
named ones." Critical for keeping aggregate code from drowning in field
repetition.

### `use <-` — guards as functions

Some logic appears as a precondition again and again:

```gleam
case a.currency == b.currency {
  False -> Error(CurrencyMismatch)
  True -> {
    // do the work
  }
}
```

Pull the precondition into a helper that takes a *callback*:

```gleam
fn require_same_currency(
  a: Money,
  b: Money,
  then: fn() -> Result(t, MoneyError),
) -> Result(t, MoneyError) {
  case a.currency == b.currency {
    False -> Error(CurrencyMismatch)
    True -> then()
  }
}
```

Then call it with `use`:

```gleam
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount + b.amount, a.currency)
}
```

`use <- f(...)` is sugar for `f(..., fn() { rest_of_block })`. It lifts the
rest of your block into a callback and passes it as the helper's last
argument.

A few mechanical facts:

- `use <-` (no binding) means the callback takes zero arguments — it's a guard.
- `use x <- f(...)` (one binding) means the callback takes one argument — used for unwrapping (we'll see this in Kata 3).
- The helper decides whether to call the callback. If it doesn't (e.g., currency mismatch), it returns its own error directly.
- The lowercase `t` in `Result(t, MoneyError)` is a *generic type variable*. It lets the helper work for callers whose body returns `Result(Money, ...)`, `Result(Order, ...)`, anything.

This is the pattern that will let aggregates read top-to-bottom like a list
of business rules. (For a deeper explainer, see [`docs/use.md`](../use.md).)

---

## Task

Create `src/money.gleam` exposing:

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
pub fn multiply(money: Money, factor: Int) -> Result(Money, MoneyError)
pub fn same_currency(a: Money, b: Money) -> Bool
pub fn zero(money: Money) -> Money
```

Rules:

- Reject negative amounts in `new`.
- `add` and `subtract` fail with `CurrencyMismatch` if currencies differ.
- `subtract` shouldn't produce negative money (returns `NegativeAmount`).
- `multiply` with a negative factor should also be rejected.
- `zero(money)` returns a money of the same currency with amount `0`.

The tests in `test/money_test.gleam` are the spec.

---

## Hints — what to do

1. **Write the naive version first.** Each operation does its own checks: `subtract` checks currencies *and* checks the result isn't negative. `multiply` checks negativity. It will work and the tests will pass. Get there first.
2. **Then look for duplication.** Once it works, you'll see two patterns repeating across the file:
   - Every operation that touches two `Money`s repeats the same currency check.
   - Every operation that produces a new `Money` independently re-checks the negative-amount rule.
3. **Refactor: route everything through `new`.** If `new` is the single source of truth for the negative-amount invariant, then `subtract` doesn't need its own check, and `multiply` gets the check for free.
4. **Refactor: lift the currency check into a helper.** Write `require_same_currency` with the shape from the fundamentals section. Use it via `use <-`. Suddenly every operation reads as `require same currency, then compute`.
5. **`zero(money)` doesn't return `Result`.** Why? Because `0` is always valid — it can never violate the invariant. Lean on the types: when an operation is total, say so by leaving `Result` out of the return type.
6. **Why does the test for `multiply(m, -1)` expect `NegativeAmount`?** Trace it through your implementation. If `multiply` routes through `new`, this falls out automatically — that's the point of funneling.

---

## Solution

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

pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError) {
  case amount >= 0 {
    True -> Ok(Money(amount, currency))
    False -> Error(NegativeAmount)
  }
}

pub fn same_currency(a: Money, b: Money) -> Bool {
  a.currency == b.currency
}

fn require_same_currency(
  a: Money,
  b: Money,
  then: fn() -> Result(t, MoneyError),
) -> Result(t, MoneyError) {
  case same_currency(a, b) {
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

pub fn zero(money: Money) -> Money {
  Money(..money, amount: 0)
}
```

---

## Walk-through

**Funneling through `new`.** Every constructor path re-validates. `subtract`
no longer needs its own `amount >= 0` check — `new` does it. `multiply`
catches negative factors automatically — also `new`. The non-negative
invariant exists in exactly *one place*, and you literally cannot construct
a `Money` that violates it.

**`use <- require_same_currency(a, b)`.** The duplicate currency check from
a naive solution gets pulled into a named helper. Each operation now reads
as a flat list of business rules:

> require same currency, then sum.
> require same currency, then subtract.

The mechanical desugar:

```gleam
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  require_same_currency(a, b, fn() {
    new(a.amount + b.amount, a.currency)
  })
}
```

`use` is *just sugar* for that callback shape. Once you can read one form,
you can read the other.

**`zero` is total.** No `Result`. The function can't fail — `0` always
satisfies the non-negative rule. Use record update (`Money(..money, amount:
0)`) so the currency comes along for free.

**Storing amounts as `Int` minor units.** Floats and money don't mix —
`0.1 + 0.2 ≠ 0.3` in IEEE-754. Real systems store cents. This is a domain
modeling decision encoded in the type.

**Why `add` returns `Result`.** In a primitive world `add(usd_5, eur_3)`
silently gives you `8` of nothing. In a domain-modeled world, it's a
`CurrencyMismatch` you must handle. The bug becomes impossible to ignore.

---

## Critique

- `same_currency` is `pub` because the next kata (`Order`) needs to compare currencies between lines. Helpers that the wider domain reaches for should be exposed; helpers that are private to the module's internal flow (`require_same_currency`) shouldn't be.
- This implementation doesn't handle integer overflow. For toy domain code that's fine; for production money handling you'd want to either use a bigint type or guard against it explicitly.

---

## DDD takeaway

You have a module where the *only* way to produce a `Money` is one that
passes every invariant. Callers cannot lie about currency. Callers cannot
smuggle in negative amounts. Every `Money` in your system is, by
construction, valid.

This is what people mean by "make illegal states unrepresentable" — it's
not a slogan, it's the literal property your type now has.
