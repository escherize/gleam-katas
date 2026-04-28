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

Two branches, one purpose each:

- **`master`** — *start learning here.* `src/*.gleam` is stubbed with `todo`. Every type and function the tests reference is declared, but the bodies are blank. Your job is to fill them in.
- **`solutions`** — the worked-out reference implementation for every kata. Switch to it (`git checkout solutions`) when you want to compare your version against the canonical one.

The book, the tests, the task specs, and everything in `docs/` are
identical on both branches. The only thing that differs is `src/`.

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
4. Compare your solution to the one on the `solutions` branch.
5. Move to the next kata.

The tests are the spec. If your code makes them pass, you've solved the
kata — even if your structure differs from the reference.
