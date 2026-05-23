# `use` in Gleam — an in-depth explainer

Gleam's `use` is one keyword with one mechanical rule, but it shows up in
several different shapes. Once you internalize the rule, every shape is just an application of it. This doc walks through the rule, then the patterns you'll hit most often.

---

## 1. The mechanical rule

```gleam
use <bindings> <- f(arg1, arg2, ..., argN)
<rest of block>
```

desugars to exactly:

```gleam
f(arg1, arg2, ..., argN, fn(<bindings>) { <rest of block> })
```

That's the whole feature. `use` takes the rest of the block, wraps it in an
anonymous function, and passes that function as the **last argument** to `f`.

A few consequences fall out of that one rule:

- The helper `f` is just a normal function that happens to take a callback as its last parameter. Nothing magical about it.
- Whatever the callback returns is what `f` returns (in the success branch). So your block's last expression is the function's value.
- `use` must be followed by something — there has to be a "rest of the block" to lift into the callback. A `use` line on its own is an error.

### Why Gleam has this

Gleam is **expression-based and has no early `return`**. Without `use`, every "check then continue" pattern becomes a nested `case`, and chains of fallible operations become a pyramid.

Concretely: `Customer.new` in this repo is strict — it takes `(id: CustomerId, name: String, email: Email)`, all pre-validated. But somewhere at the boundary (HTTP handler, CLI, DB row) you have raw strings that need to be turned into those value objects first. That "raw → validated" factory is where the chain lives. Without `use` it looks like this:

```gleam
case email.new(raw_email) {
  Error(e) -> Error(InvalidEmail(e))
  Ok(email) -> case customer.new_id(raw_id) {
    Error(e) -> Error(e)
    Ok(id) -> customer.new(id, raw_name, email)
  }
}
```

With `use` and `result.try`, that pyramid flattens into a sequence:

```gleam
import gleam/result

use email <- result.try(email.new(raw_email) |> result.map_error(InvalidEmail))
use id <- result.try(customer.new_id(raw_id))
customer.new(id, raw_name, email)
```

Each line is one validation step. There is no nesting, no manually
re-propagating errors, no `Ok(...) -> case ...` ladder. If any step returns
`Error`, the whole block short-circuits with that error; if all succeed, the
final expression is the function's return value.

(Adding this boundary factory would require adding `InvalidEmail(EmailError)` to `CustomerError` so the email error has a place to live — see section 4.)

`use` is Gleam's answer to Rust's `?`, Haskell's `do` notation, and Clojure's
macros — but with one syntactic rule covering all the cases instead of a
separate construct per case.

---

## 2. The shape of the helper

Any function with this general signature is a candidate for `use`:

```gleam
fn helper(arg1, arg2, ..., callback: fn(...) -> R) -> R
```

The helper decides three things:

1. **What arguments the callback receives** (zero or more, of any types).
2. **When the callback runs** (always? only on success? only on failure?).
3. **What to return when the callback doesn't run** (the short-circuit value).

That's the design space. Every pattern below is a different choice across
those three knobs.

---

## 3. Pattern — guard / short-circuit (zero-arg callback)

The helper takes a precondition. If it passes, it runs the callback (the rest
of your block). If it fails, it returns an error directly.

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

pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount + b.amount, a.currency)
}
```

Key signals it's a guard:

- The callback's parameter list is empty (`fn() -> ...`).
- At the call site you write `use <- f(...)` with no binding.
- The check is the entire contract of the helper.

Other guard examples worth writing:

```gleam
fn require_authenticated(session, then: fn() -> Result(a, e)) -> Result(a, e)
fn require_role(session, role, then: fn() -> Result(a, e)) -> Result(a, e)
fn require_non_empty(s: String, then: fn() -> Result(a, FieldError)) -> Result(a, FieldError)
```

You're effectively building little control-flow combinators for your domain.

---

## 4. Pattern — `Result` chaining (one-arg callback)

The helper _unwraps_ a `Result`, passes the inner value to the callback, and
short-circuits on error. This is `result.try`:

```gleam
// from gleam/result
pub fn try(
  result: Result(a, e),
  apply: fn(a) -> Result(b, e),
) -> Result(b, e)
```

Used with `use`. The natural home for this in our codebase is a `from_raw` boundary factory that pairs with the strict inner `Customer.new`:

```gleam
// Strict inner constructor (already in customer.gleam) — no `use` needed,
// because every argument is already a validated value object.
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

// Boundary factory — turns raw strings into a Customer, composing errors.
// This is where the `use` chain belongs. Requires CustomerError to gain
// an `InvalidEmail(EmailError)` variant.
pub fn from_raw(
  raw_id: String,
  raw_name: String,
  raw_email: String,
) -> Result(Customer, CustomerError) {
  use email <- result.try(email.new(raw_email) |> result.map_error(InvalidEmail))
  use id <- result.try(new_id(raw_id))
  new(id, raw_name, email)
}
```

Two layers, two responsibilities:

- `new` enforces _Customer-level_ invariants and trusts its value-object inputs. No `use` because there's nothing to short-circuit on.
- `from_raw` is the boundary — turns untrusted strings into trusted values, composes the errors, then delegates to `new`.

This is the moral equivalent of:

- Rust: `let email = email::new(raw_email).map_err(InvalidEmail)?;`
- Haskell: `email <- liftError InvalidEmail (Email.new raw_email)`
- F#: `let! email = ...`

**Key gotcha — error types must match.** `result.try` requires the input's
error type to match the function's return error type. When they differ, lift
the inner error with `result.map_error(WrappingConstructor)` — exactly what
the email line above does. This is why composing modules pushes you toward
each module owning its own error type and _wrapping_ others rather than
sharing one giant error enum.

---

## 5. Pattern — `Option` chaining

Same shape as Result chaining, with `option.then`:

```gleam
import gleam/option.{type Option, Some, None}

pub fn shipping_eta(customer: Customer) -> Option(Date) {
  use address <- option.then(customer.address)
  use zone <- option.then(zone_for(address))
  Some(eta_for_zone(zone))
}
```

Returns `None` if any link in the chain is `None`, otherwise `Some(...)`.

---

## 6. Pattern — resource acquisition (with-style)

A helper that **always** runs the callback but wraps it in setup/teardown.
Same idea as `with-open` in Clojure or `with` in Python.

```gleam
fn with_db_connection(
  config: Config,
  body: fn(Connection) -> a,
) -> a {
  let conn = connect(config)
  let result = body(conn)
  close(conn)
  result
}

pub fn fetch_user(config: Config, id: Int) -> Result(User, DbError) {
  use conn <- with_db_connection(config)
  query(conn, "select ...", [id])
}
```

The connection always closes, even if `body` returned an error, because
`close(conn)` runs after `body(conn)` returns. (For real cleanup you need to
handle exceptions; Gleam has libraries for this — the pattern is what matters
here.)

---

## 7. Pattern — list iteration (less common)

You can use `use` with `list.try_each` and friends to iterate fallibly while
keeping the body flat:

```gleam
use _ <- list.try_each(orders)  // returns Error on first failure
process_order(_)
```

Honestly, for most list work, `list.map` and `list.try_map` in pipelines read
better than `use`. Reach for `use` when the body is multi-line or has its own
internal `use` chain.

---

## 8. Pattern — custom DSLs

Once you see `use` as "callback with this last-arg shape," you can build your
own combinators:

```gleam
fn assert_field(name: String, value: String, then: fn(String) -> Result(a, FieldError))
  -> Result(a, FieldError) {
  case string.trim(value) {
    "" -> Error(FieldError(name, "must not be empty"))
    trimmed -> then(trimmed)
  }
}

pub fn parse_form(raw: Form) -> Result(ValidForm, FieldError) {
  use name <- assert_field("name", raw.name)
  use email <- assert_field("email", raw.email)
  use age_str <- assert_field("age", raw.age)
  use age <- result.try(parse_int(age_str))
  Ok(ValidForm(name, email, age))
}
```

Each `use` line is a single concern; the body is a flat list of validations.
Without `use` this would nest five levels deep.

---

## 9. Syntactic variants

```gleam
use <- f(args)            // zero-arg callback   (guards)
use x <- f(args)          // one-arg callback    (try, then)
use x, y <- f(args)       // multi-arg callback  (rare; e.g. fold-style helpers)
use _ <- f(args)          // discard the binding (run for side effect)
```

The number of bindings on the left of `<-` must match the callback's parameter
count exactly. Compiler enforces this.

---

## 10. Type constraints (the part that bites)

The callback's return type has to line up with what the helper expects. The
two most common mismatches:

**Mismatched error types in `result.try`:**

```gleam
// won't compile — EmailError ≠ CustomerError
use email <- result.try(email.new(raw))

// fixed — lift the inner error
use email <- result.try(email.new(raw) |> result.map_error(InvalidEmail))
```

**Wrong return type from the body:**

The body of a `use` block must return what the helper's callback declared.
For `result.try`, that's `Result(_, e)`. So the last line of a `use`-chained
function is almost always `Ok(something)` or `Error(something)`, not a bare
value:

```gleam
use email <- result.try(...)
Ok(Customer(email))   // ✓
Customer(email)       // ✗ — type error, expected Result, got Customer
```

---

## 11. When NOT to reach for `use`

- **One-shot pattern matching** with no chain: `let assert Ok(x) = ...` is
  fine (when crashing on Error is acceptable) and reads more directly than
  `use x <- result.try(...)` followed by a single line.
- **The body has only one statement.** Nesting one level isn't a sin. `use`
  pays off when there are two or more steps to flatten.
- **The helper isn't really doing control flow.** If you find yourself writing
  a "helper" that just calls the callback unconditionally, the `use` is just
  obfuscation — drop it.

---

## 12. Mental model summary

Forget the syntax for a second. The shape `use ... <- f(...)` says:

> "I'm about to do the rest of this function as a callback. `f`, you decide
> what to do with it: run it, skip it, run it conditionally, run it with cleanup,
> run it with these arguments. Whatever you return is what I return."

That's it. Every pattern in this doc is a different choice the helper makes
about how to use that callback. Once helpers exist for guards (your domain),
`Result` (`result.try`), `Option` (`option.then`), and resources, most Gleam
business logic flattens into a sequence of `use` lines reading top-to-bottom
like a recipe.

Compared to other languages:

| Need                 | Gleam                | Rust                 | Clojure            | Haskell     |
| -------------------- | -------------------- | -------------------- | ------------------ | ----------- |
| Result short-circuit | `use x <- try(...)`  | `?`                  | `some->` / `mlet`  | `do` + `<-` |
| Guard / early return | `use <- guard(...)`  | `if cond { return }` | macro / `when-let` | `when`      |
| Resource handling    | `use r <- with(...)` | `Drop` trait         | `with-open`        | `bracket`   |
| New control flow     | helper + `use`       | macro / fn           | macro              | monad / fn  |

Gleam is unusual in answering all four with the same one-syntax-rule
mechanism. That uniformity is the whole point.
