# 01. Gleam fundamentals for Kata 1

Just enough Gleam to do Kata 1; each chapter adds to the toolkit. Readers
fluent in Gleam can skim the headers.

---

## Sum types (a.k.a. tagged unions)

Declare a custom type as a fixed set of *variants*:

```gleam
pub type Currency {
  USD
  EUR
  GBP
}
```

A `Currency` value is exactly one of `USD`, `EUR`, or `GBP`. There's no
`null` and no string `"USD"` impersonating the variant; the type has three
values and that's the set.

Variants can carry data:

```gleam
pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}
```

`Circle(3.0)` and `Rectangle(2.0, 5.0)` are both `Shape` values, the same type
holding differently shaped data, hence "sum type."

---

## Records (variants with named fields)

A type with a single variant of the same name is Gleam's record/struct:

```gleam
pub type Email {
  Email(value: String)
}
```

Construction is `Email("foo@bar.com")` and field access is `email.value`. The
type and the variant sharing a name is idiomatic Gleam.

---

## `opaque`: one keyword, one consequence

A custom type's constructor is public by default and travels with the
type; `opaque` keeps the constructor private to its module:

```gleam
pub opaque type Email {
  Email(value: String)
}
```

Outside this module the *type* `Email` still exists and behaves like any
other value, but the constructor `Email(...)` is gone and field access
`email.value` no longer compiles. The only way to get an `Email` is to call
a function the module exports, which validates whatever it wants before
wrapping the value, so the type system guarantees nothing else gets through.

That mechanism is the foundation for "make illegal states unrepresentable,"
and forgetting `opaque` is the most common mistake when starting out.

---

## `Result(a, e)`: failure as a value

Gleam has no exceptions, so a function that can fail returns a `Result`:

```gleam
// Built-in. Conceptually:
pub type Result(a, e) {
  Ok(a)
  Error(e)
}
```

A typical signature is `Result(ValidThing, SomeError)`, where `Ok(v)` holds
the success value and `Error(e)` holds why it failed.

Callers `case` on the result to reach either branch, and there's no way to
grab the value without acknowledging failure. (`let assert Ok(x) = ...`
exists for crash-on-error scenarios, mostly tests.)

---

## Smart constructors

A *smart constructor* is the function outside callers use to build an
opaque value. It validates and either wraps the value in the type or
returns a typed error:

```gleam
pub fn new(raw: String) -> Result(Email, EmailError) {
  // ...validate, then either Ok(Email(...)) or Error(...)
}
```

Convention names it `new`; combined with `opaque`, it becomes the only
door into the type.

---

## `case`: Gleam's only conditional

Gleam has no `if`, only `case`, which pattern-matches on a value:

```gleam
case x {
  0 -> "zero"
  1 -> "one"
  _ -> "other"
}
```

The compiler checks *exhaustiveness*: a missed variant in a match on a
sum type breaks the build. "Named failure modes" stop being a discipline
and become a compiler-enforced property.

`_` matches anything and serves as the catch-all once the rest are explicit.

---

## Pattern matching on shapes

`case` can destructure as it matches, so patterns end up describing shapes:

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

Each branch names a shape the input could take, so the structure of the
data does the work that chained guards do elsewhere. The surprise coming
from imperative languages is that a sequence of guards like
`if (!hasAt) ... else if (!domain) ...` collapses into one `case`.

Order of patterns matters when they overlap: `[""]` must come before `[_]`
because the empty string matches both, and `case` picks the first.

---

## Modules and imports

One file is one module, named after the file, and public items use `pub`:

```gleam
import gleam/string  // standard library
import email         // sibling module in the same project

pub fn foo() { string.trim("  hi  ") }
```

A module's contents are reachable as `module.name`, or specific names can come into scope:

```gleam
import email.{type Email}  // brings the type into scope unqualified

pub fn handle(e: Email) { ... }
```

Functions stay namespaced as `email.new(...)`; only the type alias is
unqualified.

---

## The toolkit so far

- A type defined with one or many variants.
- `opaque` to restrict construction to the defining module.
- A smart constructor returning `Result(YourType, YourError)`.
- Validation via `case` on the structure of the input.
- Either `Ok(YourType(...))` or `Error(NamedReason)` as the return.

The rest of the book waits on an attempt at the kata.
