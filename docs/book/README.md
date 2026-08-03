# DDD in Gleam: a textbook

Each chapter pairs one Domain-Driven Design concept with the Gleam
patterns that make it enforceable.

## Contents

- [00. Introduction](00_introduction.md): what DDD is, what Gleam is, why they pair.
- [01. Gleam fundamentals for Kata 1](01_fundamentals.md): sum types, records, `opaque`, `Result`, `case`, pattern matching.
- [02. Kata 1: Value Objects (`Email`)](02_kata_email.md): opaque types and smart constructors.
- [03. Kata 2: Value Objects with operations (`Money`)](03_kata_money.md): composition, `use <-` guards, funneling through `new`.
- [04. Kata 3: Entities (`Customer`)](04_kata_customer.md): identity vs value, ID types, `result.try`.
- [05. Kata 4: Aggregates (`Order`)](05_kata_order.md): internal types, multi-guard chains, `list.try_map` / `list.try_fold`.
- [06. Kata 5: Domain Events](06_kata_events.md): tuples, `result.try` earning its keep, scenario tests with a command engine.

## Prerequisites

- A working Gleam toolchain (`gleam` on your `PATH`).
- Comfort with one statically-typed functional or object-oriented language. You don't need to know Gleam already.

## How to work through it

1. Read the concept and fundamentals sections.
2. Open the source file under `src/` and try the kata yourself before peeking. The tests under `test/` are the spec.
3. Run `gleam test` to confirm.
4. Read the walk-through and critique. Compare to your version.
5. Move on.

The reference solutions live in `src/`.

## A note on style

Each chapter follows one shape:

1. **Concept**: the DDD idea in plain language.
2. **New Gleam fundamentals**: only what this kata needs.
3. **The task**: the function signatures and rules.
4. **Hints**: nudges that unblock without spoiling the design.
5. **Solution**: the reference, with a walk-through.
6. **Critique**: what holds, what doesn't, what changes as the system grows.
7. **DDD takeaway**: the property the code now *guarantees*, and why it matters past the toy example.
