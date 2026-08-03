# 00. Introduction

Gleam makes the core DDD patterns *enforceable* rather than aspirational.
Each chapter pairs one Domain-Driven Design concept with the small set of
Gleam features that make it compile-time true.

This is neither a DDD survey nor a Gleam tutorial. It covers the
intersection, where the language and the methodology compound.

---

## DDD makes business rules the load-bearing structure

Domain-Driven Design makes the **vocabulary**, **boundaries**, and
**invariants** of the business the load-bearing structure of the code.
They are not a layer on top of CRUD models.

The ideas below do most of the work; the familiar patterns (Repositories,
Factories, Anti-Corruption Layers) are consequences of them.

1. **Make illegal states unrepresentable.** If "an order with zero lines cannot be placed" is a rule, the type should *forbid* it; the code shouldn't *check* it everywhere.
2. **Concepts have shapes.** A `CustomerId` is not a `String`, and a `Money` is not a number. Modeling them as their own types makes the rest of the system honest about what it does.
3. **Behavior lives with the data.** "An order is placed" isn't a flag flip in a service; it's an operation on the order itself. It has preconditions and returns either a new state or a typed reason the transition failed.

---

## Gleam's constraints map onto DDD's demands

Gleam is small. The whole language has the feel of a careful editor's pass:
nothing extra, and no escape hatches.

- **[Algebraic data types](https://tour.gleam.run/data-types/custom-types/)** with exhaustive [pattern matching](https://tour.gleam.run/flow-control/case-expressions/). You name every alternative; the compiler refuses to let you forget one.
- **[Opaque types](https://tour.gleam.run/advanced-features/opaque-types/)**: one keyword lets a module hide its constructor. Outside the module the type exists, and the only way to make one is through functions the module exposes.
- **No exceptions, no nulls.** Failure is a value ([`Result(a, e)`](https://tour.gleam.run/data-types/results/), `Option(a)`). Callers can't pretend it didn't happen.
- **No `if`.** Every branch is a [`case`](https://tour.gleam.run/flow-control/case-expressions/), which forces you to consider the alternatives.
- **One control-flow primitive ([`use <-`](https://tour.gleam.run/advanced-features/use/))** that handles guards, chaining, resource handling, and any custom flow you'd write, under one syntactic rule.

Each maps almost suspiciously well onto what DDD wants:

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

## The katas add one concept at a time

1. **Value Objects**: `Email`, `Money`. Build the simplest unit. Practice opaque types, smart constructors, error sums, `use` chaining.
2. **Entities**: `Customer`. Same toolkit, but now identity matters. Practice ID types, equality semantics, state transitions as new immutable values.
3. **Aggregates**: `Order` + `OrderLine`. Multiple internal pieces, invariants spanning them all. Practice hiding internals, designing a single front door.
4. **Domain Events**: `OrderPlaced` and friends. State transitions that *also* report what happened.

Each kata adds **one** new DDD concept, and each chapter introduces **only
the Gleam features that concept needs.** By the end you can read and write
idiomatic domain code in Gleam without learning either subject in the
abstract first.

---

## Each chapter follows one shape

- **Concept.** The DDD idea in plain language.
- **New Gleam fundamentals.** Only what this kata needs.
- **The task.** A function signature and rules. Implement it.
- **Hints.** Nudges that unblock without spoiling the design.
- **Walk-through.** The reference solution, with reasoning.
- **Critique.** What holds, what doesn't, what changes as the system grows.
- **DDD takeaway.** The property the code now *guarantees*, and why it matters past the toy example.

The exercises are real. Type the code. Try to satisfy the tests. Then read
the walk-through.

---

## Keep these tabs open

- **[The Gleam Language Tour](https://tour.gleam.run/)**: interactive, in-browser. The best place to look up any language feature.
- **[Standard library reference](https://hexdocs.pm/gleam_stdlib/)**: `gleam/string`, `gleam/list`, `gleam/result`, etc. You'll reach for these in every kata.
- **[Gleam documentation index](https://gleam.run/documentation/)**: guides, conventions, and cheatsheets, including [Gleam-for-Rust](https://gleam.run/cheatsheets/gleam-for-rust-users/) and [Gleam-for-Elixir](https://gleam.run/cheatsheets/gleam-for-elixir-users/).
- **[Gleam home](https://gleam.run/)**: install instructions if you don't have the `gleam` CLI.
