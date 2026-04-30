# Brainstorm: a chapter (or standalone reference doc) on decoders

Status: idea capture, not yet written. Get back to this when there's
appetite. Probably right after kata 9 (SQLite) lands implementation —
that kata uses the same decoders for snapshot/restore and would
benefit from a deeper reference to point at.

---

## Working title options

- "Decoding, decoders, and the Dynamic boundary"
- "Untyped in, typed out: the decoder pattern"
- "Bytes, Dynamic, and you" (less serious, probably better for a blurb than a chapter)

## Where to slot it

Pick one — leaning toward **standalone reference doc** (like `docs/use.md`).

| Option | Pros | Cons |
|---|---|---|
| New chapter 12 — "Decoding" | Has space to breathe; pairs cleanly with kata 9 (SQLite) chapter that uses the same decoders | One more chapter to maintain |
| Sidebar in chapter 09 (HTTP) | Lands when readers first need it (request body parsing) | Bloats an already-long chapter |
| Sidebar in chapter 10 (SQLite) | SQLite uses decoders too | Same bloat problem |
| **Standalone reference doc** (`docs/decoders.md`, paired with `use.md`) | Doesn't disrupt kata flow; deep-dive material; cross-referenced from katas 8 and 9 | Easier to ignore than an in-line chapter |

## Sections — checklist

### Core (the tight ~150-line "blurb" version, if we cut everything else)

- [ ] **The two-step model.** Bytes → Dynamic → T. Diagram. Why Gleam splits this when other languages fuse it.
- [ ] **`gleam/dynamic/decode` is source-agnostic.** Same decoder works for JSON, Erlang terms, SQLite rows, FFI returns. Show the same `user_decoder()` consumed by `json.parse` and by `decode.run` on a non-JSON Dynamic.
- [ ] **Anatomy of a decoder.** `decode.string`, `decode.int`, `decode.field`, `decode.success` — the four pieces 90% of real decoders use. The `use <-` chain shape.
- [ ] **Errors and the path.** What `decode.DecodeError` looks like — path tells you which field broke, expected/found tells you why. Better than a generic JSON-library stack trace.

### Composition (pushes to ~250 lines, full-chapter shape)

- [ ] **Composing decoders for nested types.** `Money` decoder lives in `money.gleam`. `OrderLine` decoder in `order.gleam` reusing `money.decoder()`. Same compositional shape as the encoders from chapter 9 (SQLite).
- [ ] **Decoders as the inverse of encoders.** Pair them — `to_json` and `decoder` are siblings, defined together, kept in sync by hand. The "no derive" tax with the explicitness payoff.
- [ ] **Sum type decoding.** Pattern: read a discriminator field, switch to the right sub-decoder. Worked example: `OrderEvent` (multiple variants with shared id field) and `OrderStatus` (string-tagged).

### Cookbook / patterns (sidebar material — could defer to v2)

- [ ] **Optional fields & defaulting.** `decode.optional_field` vs `decode.field` with a default in the success step. When to use each.
- [ ] **Custom validation.** `decode.then` for post-validation ("decode an int, then enforce 1..100"). Where to put domain validation: in the decoder, in the smart constructor, or both?
- [ ] **Where Dynamic actually comes from in real code.** JSON / SQLite / Erlang terms / FFI / HTTP form bodies. Brief note on what each looks like.

### Anti-patterns (~30 lines)

- [ ] Decoders that re-validate domain invariants (smart constructor's job — single source of truth)
- [ ] Decoders that don't compose (each one assumes a custom format, can't be reused)
- [ ] Using `dynamic.from` everywhere instead of staying typed
- [ ] Hand-rolling JSON-string parsers instead of going via the Dynamic boundary

### Practical wrap (the why-this-matters payoff)

- [ ] **Same decoder, every stack layer.** The decoder you write for HTTP body parsing is the same decoder you use for the SQLite snapshot/restore. Same encoder + decoder pair powers config loading, event-bus deserialization, test fixtures. Write once, use everywhere there's untrusted bytes.

---

## Decisions to make before writing

- **Length target?** ~150 (blurb) or ~250 (chapter). Pick before drafting.
- **Standalone or in-chapter?** See table above. Standalone is the leaning recommendation.
- **`gleam_json` API version assumption?** Latest unified API (decoders from `gleam/dynamic/decode`, parser from `gleam/json`). Older `json.decode_field` API briefly mentioned as historical / what to migrate from.
- **Do we cover form bodies and query strings?** Yes briefly — they're "flat" formats that don't go through Dynamic decoders, useful contrast.
- **Worked-example domain?** Use the kata's existing types (`User`, `Order`, `Money`) so cross-references work. Avoid inventing a separate toy domain.

## Cross-references when written

- Link from chapter 09 (HTTP) where `wisp.require_json` first appears
- Link from chapter 10 (SQLite) where snapshot decoders are introduced
- Link from `docs/use.md` (since `use <-` is the shape decoders use)
- Add to `docs/book/README.md` TOC if it ends up as a numbered chapter

---

## Open questions

- Does Gleam's `decode.then` handle accumulating errors across fields or short-circuit at the first? (Worth verifying before writing — affects how we describe error reporting.)
- Are there sum-type-decoding helpers in current `gleam/dynamic/decode` (e.g., `decode.one_of`)? Or do we hand-roll the discriminator-then-dispatch pattern?
- What's the idiomatic name for the decoder-of-X function? `decoder()`, `from_dynamic()`, `to_decoder()`, just plain `decode()`? Pick one and use consistently.
