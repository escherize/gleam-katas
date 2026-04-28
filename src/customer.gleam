// Kata 3 — Entities (Customer)
// Read: docs/book/04_kata_customer.md
// Tests: test/customer_test.gleam (currently empty — write your own as you go)
//
// Implement the function bodies. Notice which functions return `Result`
// and which don't — the value-object inputs (`Email`, `CustomerId`) are
// already validated, so functions that only take those don't need to fail.
//
// Reference solution lives on the `solutions` branch.

import email.{type Email}

pub opaque type CustomerId {
  CustomerId(value: String)
}

pub opaque type Customer {
  Customer(id: CustomerId, name: String, email: Email)
}

pub type CustomerError {
  EmptyName
  EmptyId
}

pub fn new_id(raw: String) -> Result(CustomerId, CustomerError) {
  todo
}

pub fn new(
  id: CustomerId,
  name: String,
  email: Email,
) -> Result(Customer, CustomerError) {
  todo
}

pub fn id(customer: Customer) -> CustomerId {
  todo
}

pub fn rename(
  customer: Customer,
  new_name: String,
) -> Result(Customer, CustomerError) {
  todo
}

pub fn change_email(customer: Customer, new_email: Email) -> Customer {
  todo
}

pub fn same_customer(a: Customer, b: Customer) -> Bool {
  todo
}
