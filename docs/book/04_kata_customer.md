# 04. Kata 3: Entities (`Customer`)

## Concept

A customer named "Alice" who renames to "Alice Smith" tomorrow remains
the same customer, because identity persists while attributes change.

Equality runs on the ID. Gleam's `==` lies about entities; two snapshots
of one customer at different moments compare unequal because their fields
differ, though the person is one. Entities want an explicit ID type and a
`same_X` function that compares by ID, so `==` stays out of entity code.

Value objects start paying rent here. `Customer` *contains* the `Email`
from Kata 1, so the customer layer skips re-validation; the type already
carries the proof.

---

## New Gleam fundamentals

### Importing types from other modules

```gleam
import email.{type Email}
```

This pulls the *type* `Email` into scope by bare name, so the annotation
reads `email: Email` rather than `email: email.Email`. Functions still need
their namespace (`email.new(...)`), since only the type alias travels
unqualified.

### One-arg `use`: `result.try`

`Customer` composes a `CustomerId` and an `Email`, both of which run
through smart constructors, so a boundary function that turns raw strings
into a `Customer` chains three constructions that can each fail:

```gleam
case email.new(raw_email) {
  Error(e) -> Error(InvalidEmail(e))
  Ok(email) -> case new_id(raw_id) {
    Error(e) -> Error(e)
    Ok(id) -> new(id, raw_name, email)
  }
}
```

`use` flattens that pyramid:

```gleam
use email <- result.try(email.new(raw) |> result.map_error(InvalidEmail))
use id <- result.try(new_id(raw_id))
new(id, raw_name, email)
```

`result.try(r, fn(value) { ... })` runs the callback only when `r` is `Ok`;
on `Error` the expression short-circuits to that error, so `use` turns
the call site into a readable sequence of validations. `result.map_error(f)`
rewraps an inner error to fit the outer error type when the two don't line
up.

The minimal Kata 3 won't force you onto this, but you'll reach for it the
moment you start composing types. See `docs/use.md` for the deeper treatment.

---

## Task

Create `src/customer.gleam` exposing:

```gleam
import email.{type Email}

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

- `CustomerId` is its own opaque type; never use raw strings as IDs in domain code.
- Reject empty names and empty ID strings.
- `rename` and `change_email` return a *new* `Customer` with the same ID.
- `same_customer` compares by ID only.

The tests in `test/customer_test.gleam` are the spec. The file ships empty,
so cases land as the implementation lands.

---

## Hints

1. Treat this as Kata 1 applied twice. `CustomerId` is an opaque value object with its own smart constructor, `new_id`, and `Customer` is an opaque entity whose `new` takes value objects that already carry their proofs.
2. `change_email` returns `Customer` rather than `Result` because its one substantive argument, `new_email`, already carries `Email`'s proof, so nothing remains to fail on. The value-object layer pays out.
3. `rename` does return `Result`, because `new_name: String` is raw input that can still be empty. Route it through `new` so the empty-name check lives in one place.
4. For `same_customer`, plain `==` on `CustomerId` is the right tool. `CustomerId` is opaque and only constructable through `new_id`, so every `CustomerId` in your program already cleared the constructor, and opacity buys you trustworthy equality.
5. Skip the extra fields (`created_at`, `version`, address, whatever else is tempting). The kata wants the entity-vs-value distinction; everything else is noise.
6. The strict `new` takes values that already carry their proofs, so don't let raw strings through. Raw input belongs in a separate boundary factory that pipelines the three smart constructors together; see `docs/use.md`. Splitting the two keeps each function honest about what it can fail on.

---

## Walk-through

Funnel `rename` through `new`, same instinct as `Money`. The function
writes no validation of its own and hands off to the smart constructor,
which already checks the name, so the invariant lives in one place.

`Email` arrives carrying its proof, so the entity layer skips the string
check; the type already establishes the invariant. Compounding like
this earns value objects their keystrokes.

`same_customer` carries the other half. After a rename, `alice_v1 == alice_v2`
returns `False` because the structs differ, yet domain-wise they name one
person, and a named function makes the caller commit to identity equality
instead of stumbling into structural equality by reflex. `CustomerId` stays
opaque and only `new_id` builds one, so `a.id == b.id` is safe; both IDs
went through the constructor.

---

## Critique

- `string.length(raw) == 0` works, but `string.is_empty(raw)` is cheaper (no traversal) and reads as the intent. `new_id` above uses `is_empty` while `new` still uses `length`; pick one.
- `new(... name: "   ")` succeeds as written, because whitespace-only names pass the check. Whether that counts as a bug depends on the domain, and every spot a string enters your domain is a place for invariants to leak.
- The strict `new` is good design that grates when you genuinely have raw input from an HTTP handler. Add a separate `from_raw` boundary factory that chains the three smart constructors in a `use`-chain; `docs/use.md` §4 has the worked example.

---

## DDD takeaway

You have a `Customer` whose attributes drift while its identity stays
fixed and trusted. `rename` and `change_email` are state transitions. Each produces a new
immutable value, the next moment in that customer's life.

An event-sourced system would emit a `CustomerRenamed` or `EmailChanged`
event on each transition, and replaying them would reconstruct the
customer's history. Your design already fits that mold without trying; Kata 5
turns the theory into working code.
