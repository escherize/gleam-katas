# 03. Kata 2: Value Objects with operations (`Money`)

## Concept

Same shape as `Email` (opaque type, smart constructor), under two new pressures.

1. A `Money` has two attributes (amount and currency) that have to stay coherent.
2. `add(usd, eur)` is nonsense the type system should refuse.

The rules of the domain become rules of the type. The type carries
the operations that respect its invariants alongside the data they
operate on.

---

## New Gleam fundamentals

Kata 1 needed an opaque type and a smart constructor. This one adds record update syntax and the `use <-` desugaring.

### Record update syntax

To produce a modified copy of a record without re-listing every field:

```gleam
let updated = Money(..money, amount: 0)
```

`..money` says "take all the fields from this value, then override the
named ones." Without it, aggregate code drowns in field repetition.

### `use <-`: guards as functions

The same precondition shows up at the head of every operation:

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
remainder of the block into a callback and passes it as the helper's last
argument.

A few mechanical facts:

- `use <-` with no binding gives the callback zero arguments, which makes it a guard.
- `use x <- f(...)` gives the callback one argument, for unwrapping (Kata 3).
- The helper decides whether to call the callback. On a currency mismatch it returns its own error and the rest of the block never runs.
- The lowercase `t` in `Result(t, MoneyError)` is a *generic* type variable. The helper works whether the calling body returns `Result(Money, ...)` or `Result(Order, ...)`.

Aggregates built on this pattern read top-to-bottom like a list of
business rules. For a deeper explainer, see [`use.md`](use.md).

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

## Hints: what to do

1. Write the naive version first, with each operation doing its own checks: `subtract` checks currencies and verifies the result isn't negative, `multiply` checks negativity. Get the tests passing before refactoring.
2. Then look for duplication. Operations that touch two `Money`s repeat the same currency check, and operations that produce a new `Money` re-check the negative-amount rule on their own.
3. Route everything through `new` so it becomes the source of truth for the negative-amount invariant. `subtract` loses its own check, and `multiply` inherits the check for free.
4. Lift the currency check into a helper. Write `require_same_currency` with the shape from the fundamentals section, then call it with `use <-`. Every operation now reads as a guard followed by the computation.
5. `zero(money)` returns `Money`, not `Result(Money, _)`. The value `0` always satisfies the invariant, so the function is total. Leave `Result` out of the return type when nothing can go wrong.
6. Trace the test for `multiply(m, -1)`. Why `NegativeAmount`? If `multiply` routes through `new`, the answer falls out, which is the point of funneling.

---

## Walk-through

### Funneling through `new`

Every constructor path re-validates. `subtract` drops its own
`amount >= 0` check because `new` already runs it, and `multiply`
catches negative factors for the same reason. The non-negative invariant
lives in one place, so no caller can construct a `Money` that violates
it.

### `use <- require_same_currency(a, b)`

A naive solution duplicates the currency check across every operation.
Pull the check into a named helper and each operation turns into a flat
list of business rules, where every entry is "require same currency,
then do the work."

The mechanical desugar:

```gleam
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  require_same_currency(a, b, fn() {
    new(a.amount + b.amount, a.currency)
  })
}
```

`use` is sugar for that callback shape, so reading one form teaches the other.

### `zero` is total

The function returns `Money` rather than `Result(Money, _)` because `0`
always satisfies the non-negative rule. Record update
(`Money(..money, amount: 0)`) carries the currency through.

### Amounts as `Int` minor units

Floats and money don't mix, because `0.1 + 0.2 ≠ 0.3` in IEEE-754, which
is why banks store cents instead of dollars. Choosing `Int` here is a
domain modeling decision the type records.

### Why `add` returns `Result`

A primitive `add(usd_5, eur_3)` silently hands back `8` of nothing. The
domain-modeled version returns `CurrencyMismatch`, so the bug now sits
in the type signature where the caller has to deal with it.

---

## Critique

- `same_currency` is `pub` as a forward lean: the next kata (`Order`) wants to compare line currencies without reaching for `==` on the currency field, and a named predicate reads better than `a.currency == b.currency` at the call site. Strictly speaking, keeping it private and inlining one comparison in `Order` would be the smaller diff. Pick whichever rule you prefer ("expose only what's used" vs "expose the named predicate when one exists") and stay consistent. The book picks the latter. The private helper (`require_same_currency`) stays private because it's a `use <-` callback shape, not a predicate.
- The module ignores integer overflow, which is fine for toy domain code. For production money handling, use a bigint type or guard explicitly.

---

## Takeaway

The module has one way to produce a `Money`, and that path passes every
invariant. No caller can lie about currency or smuggle in a negative
amount, so every `Money` in the system is valid by construction.

"Make illegal states unrepresentable" is the slogan, and the type now
embodies it.
