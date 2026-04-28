// Kata 2 — Value Objects with operations (Money)
// Read: docs/book/03_kata_money.md
// Tests: test/money_test.gleam
//
// Implement the function bodies. Try the naive version first — every
// operation does its own checks. Then refactor: route everything through
// `new` and lift the currency check into a `use <-` helper.
//
// Reference solution lives on the `solutions` branch.

pub type Currency {
  USD
  EUR
  GBP
}

pub opaque type Money {
  Money(amount: Int, currency: Currency)
}

pub type MoneyError {
  NegativeAmount
  CurrencyMismatch
}

// Amount is in minor units (cents/pence). $1.50 -> new(150, USD).
pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError) {
  todo
}

pub fn same_currency(a: Money, b: Money) -> Bool {
  todo
}

pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  todo
}

pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError) {
  todo
}

pub fn multiply(money: Money, factor: Int) -> Result(Money, MoneyError) {
  todo
}

pub fn zero(money: Money) -> Money {
  todo
}
