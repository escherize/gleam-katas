# DDD in Gleam: a textbook

One DDD concept per chapter, paired with the Gleam patterns the compiler will enforce.

## Contents

- [00: Introduction](00_introduction.md): what DDD is, what Gleam is, why they fit.
- [01: Gleam fundamentals for Kata 1](01_fundamentals.md): sum types, records, `opaque`, `Result`, `case`, pattern matching. The minimum to start.
- [02: Kata 1: Value Objects (`Email`)](02_kata_email.md): opaque types and smart constructors.
- [03: Kata 2: Value Objects with operations (`Money`)](03_kata_money.md): composition and `use <-` guards funneled through `new`.
- [04: Kata 3: Entities (`Customer`)](04_kata_customer.md): identity versus value. ID types and `result.try`.
- [05: Kata 4: Aggregates (`Order`)](05_kata_order.md): internal types and multi-guard chains, with `list.try_map` and `list.try_fold` doing the heavy lifting.
- [06: Kata 5: Domain Events](06_kata_events.md): tuples, `result.try` earning its keep, and a command engine driving scenario tests.
- [07: Kata 6: Repositories](07_kata_repositories.md): records of functions as interfaces. OTP actors hide the state, so each layer wraps the error from the one below.
- [08: Kata 7: Bounded Contexts](08_kata_bounded_contexts.md): folders as context boundaries, asymmetric dependencies, events as the integration contract. A Shipping context reacts to Ordering.
- [09: Kata 8: Composition Root + HTTP Boundary](09_kata_http_boundary.md): wiring the app with Wisp and Mist through a Deps record, where error translation is the boundary's only job. FCIS in working code.
- [10: Kata 9: SQLite Repository](10_kata_sqlite_repo.md): same `OrderRepo` interface, real persistence via `sqlight`. JSON snapshot/restore back door for opaque aggregates.
- [11: Kata 10: Wiring and Configuration](11_kata_wiring.md): swap the SQLite adapter into the composition root. A `RepoBackend` sum type plus a factory function route env config through a unified error type, so startup fails fast on bad config.
- [12: Putting It Into Practice](12_in_practice.md): the bootstrap path, refactor moves as the system grows, signs of over-application, the testing pyramid, composition root in production, talking to non-DDD colleagues, and what comes after the foundation.

## Prerequisites

- A working Gleam toolchain (`gleam` on your `PATH`).
- Comfort with one statically-typed functional or object-oriented language. The book assumes no prior Gleam.

## How to work through it

1. Read the concept and fundamentals sections.
2. Open the source file under `src/` and try the kata before peeking. The tests under `test/` are the spec.
3. Run `gleam test` to confirm.
4. Read the walk-through and critique, then compare to your version.

The reference solutions live in `src/`; the tests in `test/` are their spec.

## A note on style

Each chapter follows the same shape:

1. **Concept**: the DDD idea in plain language.
2. **New Gleam fundamentals**: what this kata needs that earlier ones didn't cover.
3. **The task**: function signatures and rules.
4. **Hints**: enough to unblock without spoiling the design.
5. **Solution**: the reference, walked through.
6. **Critique**: what holds up, what shifts as the system grows.
7. **DDD takeaway**: the property the code now *guarantees*, and why it matters past the toy example.
