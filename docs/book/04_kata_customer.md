# 04 — Kata 3: Entities (`Customer`)

## Concept

The conceptual shift: a customer named "Alice" who renames to "Alice Smith"
tomorrow is *the same customer*. Identity persists; attributes change.

Equality is by **ID**, not by value. Gleam's `==` will give you the wrong
answer if you naively use it on entities — two snapshots of the same
customer at different moments will compare unequal because their fields
differ, but they represent one entity.

The fix is structural: give entities an explicit **ID type**, and don't
compare entities with `==` at all — write a `same_X` function that compares
by ID.

This is the moment value objects start paying off. `Email` from Kata 1 is
a building block here — `Customer` *contains* an `Email`, and there's no
re-validation at the customer layer because the type already carries proof.

---

## New Gleam fundamentals

### Importing types from other modules

```gleam
import email.{type Email}
```

This brings the *type* `Email` into scope by bare name (so you can write
`email: Email` instead of `email: email.Email`). Functions are still
namespaced (`email.new(...)`), only the type alias is unqualified.

### One-arg `use` — `result.try`

Now we have two layers of types: `Customer` is built from `CustomerId` and
`Email`, both smart-constructed. A boundary function that turns raw
strings into a `Customer` has to chain three potentially-failing
constructions:

```gleam
case email.new(raw_email) {
  Error(e) -> Error(InvalidEmail(e))
  Ok(email) -> case new_id(raw_id) {
    Error(e) -> Error(e)
    Ok(id) -> new(id, raw_name, email)
  }
}
```

This is the pyramid `use` was made to flatten:

```gleam
use email <- result.try(email.new(raw) |> result.map_error(InvalidEmail))
use id <- result.try(new_id(raw_id))
new(id, raw_name, email)
```

`result.try(r, fn(value) { ... })` runs the callback only if `r` is `Ok`.
If `r` is `Error`, the whole expression returns that error. With `use`,
the call site reads as a sequence of validations.

`result.map_error(f)` is for when error types don't line up — you wrap the
inner error so it fits the outer type.

You won't strictly need this for the minimal version of Kata 3, but it's
the natural next step once you start composing types. (See `docs/use.md`
for the deeper treatment.)

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

- `CustomerId` is its own opaque type. **Never use raw strings as IDs in domain code.**
- Reject empty names and empty ID strings.
- `rename` and `change_email` return a *new* `Customer` with the same ID.
- `same_customer` compares by ID only.

The tests in `test/customer_test.gleam` are the spec. (Currently empty —
add cases as you implement.)

---

## Hints — what to do

1. **This is mostly Kata 1 applied twice.** `CustomerId` is an opaque value object with its own smart constructor (`new_id`). `Customer` is an opaque entity whose constructor (`new`) takes already-validated value objects. Two layers, same pattern.
2. **`change_email` doesn't return `Result`. Why?** Because its only argument that could be invalid is `new_email`, which is *already* an `Email`, *already* validated. There is nothing to fail. Notice how the value-object layer eliminates checks at the entity layer.
3. **`rename` does return `Result`. Why?** Because `new_name: String` is raw input — it could be empty. Route it through `new` to reuse the empty-name check. Don't write the check twice.
4. **For `same_customer`, plain `==` on `CustomerId` is the right tool.** It works because `CustomerId` is an opaque value object — the only way to construct one is through `new_id`, so any two `CustomerId`s in your program are validated. The opacity gives you trustworthy equality.
5. **Don't add fields you don't need.** No `created_at`, no `version`, no `address`. The kata is about the entity-vs-value distinction; everything else is noise.
6. **The strict `new` takes pre-validated values.** Don't accept raw strings here. There's a separate place (a "boundary factory") for taking raw input and producing a customer; we'll see it in `docs/use.md`. The split keeps each function honest about what it can fail on.

---

## Solution

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
  let raw = string.trim(raw)
  case string.is_empty(raw) {
    True -> Error(EmptyId)
    False -> Ok(CustomerId(raw))
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

---

## Walk-through

**Funneling `rename` through `new`** — same instinct from `Money`. `rename`
doesn't write its own validation; it constructs a new customer through the
smart constructor, which already checks the name. One free invariant
check, one place to maintain it.

**`Email` is now a building block.** No re-validating an email string here
— the type carries proof. This compounding is why value objects pay off;
entities get to assume their parts are well-formed.

**Why `same_customer` and not just `==`.** `alice_v1 == alice_v2` after a
rename returns `False` (the structs differ structurally), but domain-wise
they're the same person. Naming the function forces callers to ask:
structural equality or identity equality? For entities, almost always
identity.

Because `CustomerId` is opaque and constructed only via `new_id`, comparing
`a.id == b.id` is safe — the IDs you're comparing are guaranteed to be
well-formed.

---

## Critique

- `string.length(raw) == 0` is functionally correct but `string.is_empty(raw)` is cheaper (no traversal) and reads more obviously as the intent. The `new_id` solution above uses `is_empty`; `new` still uses `length`. Pick one and be consistent.
- `new(... name: "   ")` succeeds as written — whitespace-only name passes. Whether that's a bug depends on the domain. The deeper point: every place a string enters your domain is a chance for invariants to slip in.
- The strict `new` is good design but inconvenient when you genuinely have raw input from an HTTP boundary. The fix is a separate `from_raw` boundary factory that calls `email.new`, `new_id`, and `new` in a `use`-chain. See `docs/use.md` §4 for the worked example.

---

## DDD takeaway

You have a `Customer` whose attributes can change but whose identity is
permanent and trusted. `rename` and `change_email` are *state transitions*
— each produces a new immutable value representing the next moment in that
customer's life.

In an event-sourced system each transition would emit a `CustomerRenamed`
or `EmailChanged` event, and the customer's full history would be
reconstructible by replaying them. You're already structured for that
without trying. (Kata 5 takes this from theory to working code.)
