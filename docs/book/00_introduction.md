# 00 — Introduction

A hands-on walkthrough of Domain-Driven Design fundamentals, using Gleam to
make the patterns *enforceable* rather than aspirational. Each chapter pairs
one DDD concept with the small set of Gleam features that make it
compile-time true.

It's not a survey of DDD, and it's not a Gleam tutorial. It's the
intersection — the place where the language and the methodology compound on
each other.

---

## What DDD actually is

Domain-Driven Design is a way of organizing software so that the
**vocabulary**, **boundaries**, and **invariants** of the business are the
load-bearing structure of the code, not an afterthought layered on top of
CRUD models.

Three ideas do most of the work:

1. **Make illegal states unrepresentable.** If "an order with zero lines cannot be placed" is a rule, the code shouldn't *check* it everywhere — the type should *forbid* it.
2. **Concepts have shapes.** A `CustomerId` is not a `String`. A `Money` is not a number. Modeling them as their own types makes the rest of the system more honest about what it does.
3. **Behavior lives with the data.** "An order is placed" isn't a flag flip in a service somewhere — it's a method on the order itself, with its own preconditions, returning either a new state or a typed reason it can't transition.

Most introductions to DDD bury these ideas in patterns (Repositories,
Factories, Anti-Corruption Layers). The patterns are real, but they're
*consequences*. The cause is those three ideas above.

---

## Why Gleam

Gleam is small. The whole language has the feel of a careful editor's pass:
nothing extra, nothing fancy, no escape hatches.

- **[Algebraic data types](https://tour.gleam.run/data-types/custom-types/)** with exhaustive [pattern matching](https://tour.gleam.run/flow-control/case-expressions/). Every alternative gets named; the compiler refuses to let you forget one.
- **[Opaque types](https://tour.gleam.run/advanced-features/opaque-types/)** — a one-keyword feature that lets a module hide its constructor. Outside the module, the type exists; the only way to make one is through functions you expose.
- **No exceptions, no nulls.** Failure is a value ([`Result(a, e)`](https://tour.gleam.run/data-types/results/), `Option(a)`). Callers can't pretend it didn't happen.
- **No `if`.** Every branch is a [`case`](https://tour.gleam.run/flow-control/case-expressions/), which forces you to consider the alternatives.
- **One control-flow primitive ([`use <-`](https://tour.gleam.run/advanced-features/use/))** that handles guards, chaining, resource handling, and any custom flow you'd write — with a single syntactic rule.

Each of these maps almost suspiciously onto what DDD wants:

| DDD wants...                             | Gleam gives you...                            |
| ---------------------------------------- | --------------------------------------------- |
| Illegal states unrepresentable           | Opaque types + smart constructors             |
| Validate at the boundary, trust within   | `Result` + types as proof                     |
| Named, exhaustive failure modes          | Sum-type errors + `case`                      |
| Aggregates as consistency boundaries     | Modules + opacity + record update syntax      |
| Linear top-to-bottom domain rules        | `use <-` for guard chains                     |

You can do DDD in any language. You can also drive a nail with a wrench.
Gleam happens to be the right shape for the job.

---

## Why this kata progression

The progression goes:

1. **Value Objects** — `Email`, `Money`. Build the simplest unit. Practice opaque types, smart constructors, error sums, `use` chaining.
2. **Entities** — `Customer`. Same toolkit, but now identity matters. Practice ID types, equality semantics, state transitions as new immutable values.
3. **Aggregates** — `Order` + `OrderLine`. Multiple internal pieces, invariants spanning them all. Practice hiding internals, designing a single front door.
4. **Domain Events** — `OrderPlaced`, etc. State transitions that *also* report what happened. (Coming in a later chapter.)

Each kata adds **one** new DDD concept. Each chapter introduces **only the
Gleam features needed for that concept.** By the end you can read or write
idiomatic domain code in Gleam without having to learn either subject in the
abstract first.

---

## How to read this

Each chapter follows the same shape:

- **Concept.** The DDD idea in plain language.
- **Gleam fundamentals you need.** Just enough — no full language tour.
- **The task.** A function signature and rules. Implement it.
- **Hints / what to do.** Nudges to unblock without spoiling the design.
- **A walk-through.** The reference solution, with reasoning.
- **Critique.** What's solid, what could be tightened, what changes when the system grows.
- **DDD takeaway.** What the code now *guarantees*, and why that matters past the toy example.

The exercises are real. Type the code. Try to satisfy the tests. Then read
the walk-through.

---

## Gleam resources

Useful tabs to keep open while you work through the book:

- **[The Gleam Language Tour](https://tour.gleam.run/)** — interactive, in-browser. The single best place to look up any language feature.
- **[Standard library reference](https://hexdocs.pm/gleam_stdlib/)** — `gleam/string`, `gleam/list`, `gleam/result`, etc. You'll reach for these in every kata.
- **[Gleam documentation index](https://gleam.run/documentation/)** — guides, cheatsheets (including a [Gleam-for-Rust](https://gleam.run/cheatsheets/gleam-for-rust-users/) and [Gleam-for-Elixir](https://gleam.run/cheatsheets/gleam-for-elixir-users/) one), conventions.
- **[Gleam home](https://gleam.run/)** — install instructions if you don't already have the `gleam` CLI.
