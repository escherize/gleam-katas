# gleamlang_katas

A walk through the building blocks of Domain-Driven Design, in Gleam. Each kata
pairs a DDD concept with the Gleam patterns that make it enforceable.

```sh
gleam test
```

## Roadmap

1. **Value Objects** — `email`, `money` ✅
2. **Entities** — things with identity that persists
3. **Aggregates** — clusters with a root that enforces invariants
4. **Domain Events** — facts about what happened
5. **Repositories** — abstraction over persistence
6. **Bounded Contexts** — same word, different model

---

## Kata 1 — `email` (value objects)

**DDD idea:** A value object is defined entirely by its attributes. Two `Email`s
with the same string are interchangeable. The crucial move is that you can't
construct an invalid one — validation lives at the boundary, then the rest of
the code trusts the type.

**Gleam patterns it teaches:**

- `pub opaque type` — hides the constructor so callers can't bypass validation.
- Smart constructor returning `Result(T, E)` — failure is a value you must handle, not an exception.
- Sum-type errors (`Empty | MissingAt | TooManyAt | ...`) — each failure mode is a named, exhaustive case.
- `case` is the only conditional — there is no `if`.
- Pattern-matching on the _shape of data_ (e.g. `string.split` returning a list whose length and contents _are_ the validation rules) beats chained guards.

## Kata 2 — `money` (value objects with arithmetic + invariants)

**DDD idea:** Same value-object foundation, but now the type carries operations
(add, subtract, multiply) that must preserve invariants — you cannot add USD to
EUR, you cannot end up with a negative amount. Currency-safety is enforced by
the type, not by callers remembering to check.

**Gleam patterns it teaches:**

- All of Kata 1, plus:
- Routing every mutating operation through the smart constructor so invariants hold uniformly.
- `use <- helper(args)` — sugar for callback-passing, used here to factor out a shared guard (`require_same_currency`) without nesting.
- Generic type variables (the lowercase `a` in `Result(a, MoneyError)`) — let one helper serve callers that return different inner types.
