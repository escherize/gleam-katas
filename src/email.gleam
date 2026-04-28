// Kata 1 — Value Objects (Email)
// Read: docs/book/02_kata_email.md
// Tests: test/email_test.gleam (run with `gleam test`)
//
// Implement the bodies of `new` and `to_string`. The error variants below
// are the ones the tests reference — leave them as-is, you'll need them all.
//
// Reference solution lives on the `solutions` branch.

pub opaque type Email {
  Email(value: String)
}

pub type EmailError {
  Empty
  MissingAt
  TooManyAt
  MissingTextBeforeAt
  MissingTextAfterAt
}

pub fn new(raw: String) -> Result(Email, EmailError) {
  todo
}

pub fn to_string(email: Email) -> String {
  todo
}
