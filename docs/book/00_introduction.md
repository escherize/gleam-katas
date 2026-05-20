# 00: Introduction

A hands-on walkthrough of Domain-Driven Design fundamentals, using Gleam to
make the patterns *enforceable* rather than aspirational. Each chapter pairs
one DDD concept with the Gleam features that make it compile-time true.

The book lives where the two subjects meet, and neither one receives a
full survey of its own.

---

## What DDD is

Domain-Driven Design organizes software so the business vocabulary and its
invariants become the load-bearing structure of the code, not an
afterthought layered on top of CRUD models.

A few ideas do most of the work. Illegal states should be unrepresentable;
if "an order with zero lines cannot be placed" is a rule, the type should
*forbid* it rather than every call site *checking* for it. Concepts have
shapes, so a `CustomerId` deserves its own type, and so does `Money`,
which makes the rest of the system more honest about what it handles.
Behavior lives with the data, so "an order is placed" is a method on the
order itself, with its own preconditions, returning either a new state or
a typed reason it can't transition. No service elsewhere flips a flag on
its behalf.

Most introductions to DDD bury these ideas under pattern catalogs:
Repositories, Factories, Anti-Corruption Layers. Those patterns are real,
but they sit downstream of the ideas above.

---

## Why Gleam

Gleam is a compact language with the feel of a careful editor's pass. It
ships with very few escape hatches. `let assert`, `panic`, and FFI exist,
but each one is a deliberate keystroke rather than an idiomatic shortcut.

- [Algebraic data types](https://tour.gleam.run/data-types/custom-types/) with exhaustive [pattern matching](https://tour.gleam.run/flow-control/case-expressions/). You name every alternative, and the compiler refuses to let you forget one.
- [Opaque types](https://tour.gleam.run/advanced-features/opaque-types/), a one-keyword feature that lets a module hide its constructor. Outside the module, the type exists, but the only way to build one is through functions you expose.
- Failure is a value rather than an exception or a `null` ([`Result(a, e)`](https://tour.gleam.run/data-types/results/), `Option(a)`). Callers can't pretend it didn't happen.
- Every branch is a [`case`](https://tour.gleam.run/flow-control/case-expressions/) rather than an `if`, so you must consider the alternatives by name.
- One control-flow primitive ([`use <-`](https://tour.gleam.run/advanced-features/use/)) covers guards, chaining, resource handling, and whatever custom flow you'd otherwise invent.

These features map onto what DDD wants:

| DDD wants...                             | Gleam gives you...                            |
| ---------------------------------------- | --------------------------------------------- |
| Illegal states unrepresentable           | Opaque types + smart constructors             |
| Validate at the boundary, trust within   | `Result` + types as proof                     |
| Named, exhaustive failure modes          | Sum-type errors + `case`                      |
| Aggregates as consistency boundaries     | Modules + opacity + record update syntax      |
| Linear top-to-bottom domain rules        | `use <-` for guard chains                     |

You can do DDD in any language. Gleam fits it well enough that the patterns
stop being conventions and start being what the compiler checks.

---

## Why this kata progression

The book climbs from one-file types up to a wired backend, each kata
adding one DDD concept and only the Gleam features that concept needs.

1. *Value Objects* (`Email`, `Money`, katas 1–2). Opaque types, smart constructors, error sums, and `use` chaining.
2. *Entities* (`Customer`, kata 3). The same toolkit, but identity matters; ID types, equality semantics, and state transitions modeled as new immutable values.
3. *Aggregates* (`Order`, kata 4). Several internal pieces with invariants spanning them, so the work shifts to hiding internals behind one front door.
4. *Domain Events* (`OrderPlaced` and friends, kata 5). State transitions that *also* report what happened.
5. *Repositories* (kata 6). Records of functions as interfaces; OTP actors hidden behind them.
6. *Bounded Contexts* (kata 7). Folders as boundaries; events as the integration contract.
7. *Composition Root + HTTP Boundary* (kata 8). Wisp/Mist with a `Deps` record. The shell translates; the core decides.
8. *SQLite Repository* (kata 9). Same interface, real persistence, snapshot/restore for opaque aggregates.
9. *Wiring and Configuration* (kata 10). Env vars become typed config; a factory routes config to adapters.

By the end you can read or write idiomatic Gleam domain code without
having taken either subject as a course first.

---

## How to read this

Each chapter follows the same shape:

- *Concept*: the DDD idea in plain language.
- *Gleam fundamentals you need*: enough to do the kata, not a full language tour.
- *The task*: a function signature and the rules it must satisfy.
- *Hints / what to do*: nudges to unblock without spoiling the design.
- *A walk-through*: the reference solution, with reasoning.
- *Critique*: where the solution holds up, where it could be tightened, and how it strains as the system grows around it.
- *Takeaway*: what the code now *guarantees*, and why that matters past the toy example.

Type the code and satisfy the tests before you read the walk-through,
because the exercises won't do their work otherwise.

---

## Gleam resources

Useful tabs to keep open while you work through the book:

- [The Gleam Language Tour](https://tour.gleam.run/), interactive and in-browser, and the best place to look up any language feature.
- [Standard library reference](https://hexdocs.pm/gleam_stdlib/): `gleam/string`, `gleam/list`, `gleam/result`, and the rest. You'll reach for these in every kata.
- [Gleam documentation index](https://gleam.run/documentation/), with guides and cheatsheets, including a [Gleam-for-Rust](https://gleam.run/cheatsheets/gleam-for-rust-users/) and [Gleam-for-Elixir](https://gleam.run/cheatsheets/gleam-for-elixir-users/) one.
- [Gleam home](https://gleam.run/) for install instructions if you don't already have the `gleam` CLI.
