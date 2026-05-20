# 02. Kata 1: Value Objects (`Email`)

## Concept

A **value object** has no identity beyond its attributes. Two `Email`s
with the same string are the same email, the way `5` and `5` are the
same `5`. Nothing distinguishes one from another beyond the string itself.

The exercise enforces one rule: you cannot construct an invalid `Email`.
Validate once at the boundary where the string arrives, and from then on
any function taking an `Email` parameter can trust it without defensive
checks.

In Gleam that means an opaque type with a smart constructor returning
`Result`.

---

## Task

Create `src/email.gleam` exposing:

```gleam
pub opaque type Email {
  Email(value: String)
}

pub type EmailError {
  Empty
  MissingAt
  // add more as you see fit
}

pub fn new(raw: String) -> Result(Email, EmailError) {
  // your code
}

pub fn to_string(email: Email) -> String {
  // your code
}
```

Rules:

- Trim leading/trailing whitespace.
- Reject empty (after trimming).
- Exactly one `@`.
- Both sides of `@` non-empty.

The tests in `test/email_test.gleam` are the spec. Run with `gleam test`.

---

## Hints

1. Trim first. `gleam/string` has `string.trim/1`, and trimming before any structural check folds a class of edge cases into the empty case.
2. Skip boolean guards. Don't write `if has_at && local_is_non_empty && domain_is_non_empty`. Gleam has no `if`, so a cleaner shape opens up.
3. Inspect what `string.split(trimmed, "@")` returns. It's a `List(String)`, and the shape of that list (its length, which elements are empty) *is* the validation. Sketch every meaningful shape on paper before writing code.
4. Pattern order matters. When two patterns can match the same input (e.g. `[""]` and `[_]`), put the more specific one first. The empty string matches both, but the right name for it is `Empty`, not `MissingAt`.
5. Add error variants as you discover them. The starter has `Empty` and `MissingAt`. At least two more meaningful failure modes are waiting. Name each one, because that's the point of a sum-type error.
6. For `to_string`, reach into the inner field directly. Inside the module that works because the constructor is in scope; outside, it wouldn't.

If 15 or 20 minutes pass without traction, scroll down. Brute-forcing it
defeats the point; the goal is to internalize the pattern.

---

## Walk-through

`opaque` does the work, since nothing outside this module can build an `Email`
without calling `new`. Value objects need exactly that guarantee.

Check `[""]` before `[_]`: an empty string after trimming splits into
`[""]` (a one-element list holding the empty string), which also matches
`[_]`. When patterns overlap, the more specific one goes first.

A typed error beats a `Bool` because the variant names which failure
happened, and the compiler forces every caller to handle both branches.
That information survives all the way out to wherever the error surfaces,
whether that's an HTTP response or a log line.

Use `Ok(Email(trimmed))` rather than `Ok(Email(local <> "@" <> domain))`.
Some solutions rebuild the email from the split parts, but the split
already did its job as validation and `trimmed` is the string you want.

---

## Critique

- After splitting on `@`, `[_]` matches a non-empty token, so the input had no `@`. `MissingAt` reads correctly here.
- `[""]` only happens when `trimmed` is `""`. Trimming first folds whitespace-only inputs into the `Empty` case for free.
- A name like `MissingTextBeforeAt` reads better than `EmptyLocalPart` for the audience that sees these errors. Domain language is part of the design.

### Out of scope on purpose

This validator is a teaching exercise, not a production email parser.
What it doesn't do, and what you'd add if it had to ship:

- **RFC 5322 corner cases.** Quoted local parts, comments, escaped `@` characters, IP-literal domains, all rejected here and all legal in the RFC.
- **Internationalized email (RFC 6531).** `user@bücher.de` and `测试@example.com` both fail the "ASCII-friendly" assumptions baked into the split. A real validator either pre-encodes to IDNA/punycode or accepts Unicode locals.
- **Whitespace inside the address.** Trimming the outside isn't the same as rejecting `" @example.com"`, which currently passes both halves of the `[_, _]` check with a leading space.
- **Deliverability.** Even a syntactically perfect address may not exist. That's an MX-lookup / send-and-confirm problem, not a parser problem.

The point of the kata is that *whatever* rules you settle on, the
opaque-type-plus-smart-constructor shape makes them enforceable in one
place. Swap in a stricter parser tomorrow and the rest of the codebase
doesn't move.

---

## Takeaway

Anywhere in your codebase with a parameter `email: Email`, the compiler
guarantees `new` already validated it. You validate once at the
boundary and the type carries the proof everywhere else, so downstream
code never has to recheck.

That's the upfront ceremony the design pays for. Every later layer of the
system assumes the email is well-formed, because the type system permits
nothing else.
