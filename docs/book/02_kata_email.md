# 02 — Kata 1: Value Objects (`Email`)

## Concept

A **value object** is defined entirely by its attributes. Two `Email`s with
the same string are the same email. There's no identity — there's nothing
to identify. They're like numbers: `5` and `5` are the same `5`.

The crucial move is that **you cannot construct an invalid one.** Validation
happens at the boundary where strings come in. After that, the rest of your
code can take an `Email` parameter and *trust it*. No defensive checks. No
"did someone forget to validate this?" anxiety.

In Gleam the move is: **opaque type, smart constructor returning `Result`.**

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

## Hints — what to do

1. **Start by trimming.** `gleam/string` has `string.trim/1`. Get that out of the way before you do any structural checks; it removes a whole class of edge cases.
2. **Don't reach for boolean guards.** Don't write `if has_at && local_is_non_empty && domain_is_non_empty`. There's no `if` in Gleam, but more importantly, there's a much cleaner shape available.
3. **Think about what `string.split(trimmed, "@")` returns.** It's a `List(String)`. The *shape* of that list — its length, which elements are empty — is the validation. Sketch out every possible meaningful shape on paper before writing code.
4. **Pattern order matters.** When two patterns can match the same input (e.g., `[""]` and `[_]`), put the more specific one first. The empty string matches both, but you want to call it `Empty`, not `MissingAt`.
5. **Add error variants as you discover them.** The starter has `Empty` and `MissingAt`. You'll find at least two more meaningful failure modes. Name each one explicitly — that's the whole point of a sum-type error.
6. **For `to_string`,** you need to read the inner field. That works *inside* the module (where the constructor is in scope). Outside this module it would not.

If you get stuck after 15–20 minutes, scroll down. The point is not to
brute-force it — it's to internalize the pattern.

---

## Walk-through

**`opaque` is doing all the work.** Nothing outside this module can build
an `Email` without calling `new`. That's the whole game with value objects.

**Pattern order matters.** `[""]` is checked before `[_]`, because an empty
string after trimming would split into `[""]` (a list containing one empty
string), which would also match `[_]`. When patterns overlap, the more
specific one goes first.

**Returning `Result(Email, EmailError)` instead of `Bool`.** A bool tells
you yes/no. A typed error tells you *why* — and the compiler forces every
caller to handle both branches. The information is preserved all the way
to wherever the error is finally surfaced (an HTTP response, a CLI message,
a log line).

**Why `Ok(Email(trimmed))` and not `Ok(Email(local <> "@" <> domain))`.**
Some solutions reconstruct the email from the split parts. Skip the rebuild
— the split was for validation, not transformation. `trimmed` is already
the right string.

---

## Critique

- The check `[_]` matches a single non-empty token (after splitting on `@`), which means there was no `@` in the input. The variant name `MissingAt` reads correctly here.
- `[""]` only happens when `trimmed` is `""`. Trimming first is what folds whitespace-only inputs into the `Empty` case for free.
- Naming variants like `MissingTextBeforeAt` reads better than `EmptyLocalPart` for the audience that actually sees these errors. (Domain language is part of the design.)

---

## DDD takeaway

Anywhere in your codebase that has a parameter `email: Email`, you have a
*compile-time guarantee* it's been validated. No defensive checks. No
"did someone forget to validate this?" Validation happens once, at the
boundary where strings come in, and the type system carries the proof
everywhere else.

That's the upfront ceremony you pay for. In return: every later layer of
the system gets to assume the email is well-formed, because the type system
won't let it be otherwise.
