# gleamlang_katas

A walk through the building blocks of Domain-Driven Design, in Gleam. Each
kata pairs a DDD concept with the Gleam patterns that make it enforceable.

## Start here

The textbook is in [`docs/book/`](docs/book/README.md). Read the
introduction first, then the fundamentals chapter, then work through one
kata at a time.

```sh
gleam test
```

## How this repo is laid out

**`master`** is where you work — `src/*.gleam` is stubbed with `todo`,
every type and function the tests reference is declared, the bodies are
blank.

**Per-kata reference branches** snapshot the project after each kata is
finished, cumulatively:

| Branch         | What's working                                           | `gleam test`      |
| -------------- | -------------------------------------------------------- | ----------------- |
| `kata-1-done`  | `email`                                                  | 10 pass / 31 fail |
| `kata-2-done`  | + `money`                                                | 25 pass / 16 fail |
| `kata-3-done`  | + `customer`                                             | 25 pass / 16 fail |
| `kata-4-done`  | + `order` (aggregate, pre-events)                        | 41 pass / 0 fail  |

Use them when you're stuck or want to see how a kata's code looks: `git
checkout kata-3-done` and inspect `src/customer.gleam`. Each branch is
the *cumulative* state after that kata, so `kata-4-done` includes
working code for katas 1-4.

`kata-5-done` will be created from your work once you finish kata 5 on
master. (Until then, the chapter at `docs/book/06_kata_events.md` is the
reference — but it shows the full solution, so stop at the "Hints"
section if you want to work it through cold.)

`solutions` is currently a synonym for `kata-4-done`. Treat the
`kata-N-done` branches as authoritative going forward.

The book, the tests, the task specs, and everything in `docs/` are
shared across branches. The only thing that differs is `src/`.

## Roadmap

1. **Value Objects** — `email`, `money`
2. **Entities** — `customer`
3. **Aggregates** — `order` + `order_line`
4. **Domain Events** — facts about what happened (next)
5. **Repositories** — abstraction over persistence (planned)
6. **Bounded Contexts** — same word, different model (planned)

## Workflow

1. Read the relevant chapter in `docs/book/`.
2. Open the corresponding `src/*.gleam` file. Replace each `todo` with a real implementation.
3. Run `gleam test` until the tests for that kata pass.
4. Compare your solution to the matching `kata-N-done` branch (`git diff master kata-3-done -- src/customer.gleam`).
5. Move to the next kata.

The tests are the spec. If your code makes them pass, you've solved the
kata — even if your structure differs from the reference.
