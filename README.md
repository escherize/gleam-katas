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

Two branches:

- **`master`** — where you work. `src/*.gleam` is stubbed with `todo`; every type and function the tests reference is declared, the bodies are blank. Drive failing tests to green.
- **`solutions`** — the worked-out reference implementation for every kata. Switch to it (`git checkout solutions`) to see how a kata's code can look. The book and tests are the same on both branches; only `src/` differs.

The book and all task specs are shared across branches. The only thing
that differs is `src/`.

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
4. Compare your solution to the reference on the `solutions` branch (`git diff master solutions -- src/customer.gleam`).
5. Move to the next kata.

The tests are the spec. If your code makes them pass, you've solved the
kata — even if your structure differs from the reference.
