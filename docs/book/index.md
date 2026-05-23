# Welcome {.unnumbered}

A 10-kata progression that teaches idiomatic Gleam through the
vocabulary of Domain-Driven Design. Each chapter pairs one DDD
concept with the smallest Gleam toolkit that lets the compiler check
it.

**The chapter labels say DDD; the lessons are idiomatic Gleam.**

## Prerequisites

- A working Gleam toolchain (`gleam` on your `PATH`).
- Comfort with one statically-typed functional or object-oriented language. The book assumes no prior Gleam.

## How to work through it

1. Read the concept and fundamentals sections.
2. Open the source file under `src/` and try the kata before peeking. The tests under `test/` are the spec.
3. Run `gleam test` to confirm.
4. Read the walk-through and critique, then compare to your version.

The reference solutions live in `src/`; the tests in `test/` are
their spec. The companion repository is at
[github.com/escherize/gleam-katas](https://github.com/escherize/gleam-katas).

## A note on style

Each chapter follows roughly this shape:

1. **Concept**: the DDD idea in plain language.
2. **New Gleam fundamentals**: what this kata needs that earlier ones didn't cover. (Omitted when a chapter introduces no new language features.)
3. **The task**: function signatures and rules.
4. **Hints**: enough to unblock without spoiling the design.
5. **Walk-through**: the reference solution, with reasoning.
6. **Critique**: what holds up, what shifts as the system grows.
7. **Takeaway**: the property the code now *guarantees*, and why it matters past the toy example.
