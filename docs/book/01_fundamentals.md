# 01 — Gleam fundamentals for Kata 1

This chapter gives you exactly the Gleam you need to do the first exercise.
Every concept here will be reused in later katas — we add to the toolkit one
chapter at a time.

If you already know Gleam, skim the headers and skip ahead.

---

## Sum types (a.k.a. enums, tagged unions, ADTs)

A custom type is declared as a fixed set of *variants*:

```gleam
pub type Currency {
  USD
  EUR
  GBP
}
```

A value of `Currency` is *exactly one of* `USD`, `EUR`, or `GBP`. There are
no other values. You can't have `null`, you can't have `"USD"` masquerading
as one.

Variants can carry data:

```gleam
pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}
```

`Circle(3.0)` and `Rectangle(2.0, 5.0)` are both valid `Shape` values. Same
type, different shapes — hence "sum type."

---

## Records (variants with named fields)

A type with a single variant whose name matches the type is the Gleam
equivalent of a record/struct:

```gleam
pub type Email {
  Email(value: String)
}
```

Construct with `Email("foo@bar.com")`. Read fields with `email.value`. The
type and the variant share a name; this is idiomatic.

---

## `opaque` — the one-keyword superpower

By default the constructor of a custom type is exported alongside the type
itself. Add `opaque` and the constructor stays private to the module:

```gleam
pub opaque type Email {
  Email(value: String)
}
```

Outside this module:

- The *type* `Email` exists. You can take it as a parameter, return it, store it.
- The *constructor* `Email(...)` does **not** exist. You can't call it.
- Field access `email.value` does **not** work either.

The only way to obtain an `Email` is to call a function that the module
deliberately exports. That function can validate, normalize, do whatever it
wants — and the type system guarantees nothing else gets through.

This is the mechanical foundation for "make illegal states unrepresentable."
**Forgetting `opaque` is the single most common mistake when starting out.**

---

## `Result(a, e)` — failure as a value

Gleam has no exceptions. A function that can fail returns a `Result`:

```gleam
// Built-in. Conceptually:
pub type Result(a, e) {
  Ok(a)
  Error(e)
}
```

Conventional usage: `Result(ValidThing, SomeError)`. `Ok(v)` carries the
success value; `Error(e)` carries why it failed.

Callers must `case` on the result to see either branch — there's no way to
"just get the value" without acknowledging failure. (`let assert Ok(x) =
...` exists for crash-on-error scenarios, mostly tests.)

---

## Smart constructors

A *smart constructor* is the function the outside world calls to make an
opaque value. It runs validation, then either wraps the value in the type
or returns a typed error:

```gleam
pub fn new(raw: String) -> Result(Email, EmailError) {
  // ...validate, then either Ok(Email(...)) or Error(...)
}
```

By convention this function is called `new`. Because the type is `opaque`,
this is the *only door* — there's no shortcut around it.

---

## `case` — Gleam's only conditional

There is no `if`. There is `case`, which pattern-matches on a value:

```gleam
case x {
  0 -> "zero"
  1 -> "one"
  _ -> "other"
}
```

The compiler checks **exhaustiveness**. If you `case` on a sum type and
miss a variant, it's a compile error. This is what makes "named failure
modes" not just a discipline but an enforced one.

`_` matches anything. Use it as the catch-all when the rest are explicit.

---

## Pattern matching on shapes

The killer feature: `case` doesn't just compare values, it matches
*structure*.

```gleam
case string.split(input, "@") {
  [""]        -> Error(Empty)               // single empty element
  [_]         -> Error(MissingAt)           // single non-empty element
  ["", _]     -> Error(MissingLocal)        // empty before @
  [_, ""]     -> Error(MissingDomain)       // empty after @
  [_, _]      -> Ok(...)                    // exactly two non-empty parts
  _           -> Error(TooManyAt)           // three or more
}
```

Each pattern names a *shape* the data could have. There are no chained
`if/else` clauses — the structure of the data *is* the structure of the
validation.

This is the most surprising thing if you come from imperative languages:
pieces of code that you'd write as a sequence of guards (`if (!hasAt) ...
else if (!domain) ...`) collapse into one `case` expression.

**Order of patterns matters when they overlap.** `[""]` must come before
`[_]`, because the empty string matches both — and `case` picks the first.

---

## Modules and imports

One file = one module. The filename is the module name. Public items use
`pub`:

```gleam
import gleam/string  // standard library
import email         // sibling module in the same project

pub fn foo() { string.trim("  hi  ") }
```

Pieces from a module are accessed `module.name`. You can pull specific
names in:

```gleam
import email.{type Email}  // brings the type into scope unqualified

pub fn handle(e: Email) { ... }
```

Functions are still namespaced (`email.new(...)`); only the type alias is
unqualified.

---

## What you have so far

Just enough vocabulary:

- Define a type with one or many variants.
- Mark it `opaque` so only your module can build it.
- Write a smart constructor that returns `Result(YourType, YourError)`.
- Validate by `case`-matching on the structure of the input.
- Return either `Ok(YourType(...))` or `Error(NamedReason)`.

That toolkit is sufficient for Kata 1. **Don't read further until you've
attempted the kata.**
