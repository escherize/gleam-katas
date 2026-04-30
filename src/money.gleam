import gleam/json

// A sum type: a Currency is exactly one of these. Like an enum.
pub type Currency {
  USD
  EUR
  GBP
}

// `opaque` hides the Money(...) constructor outside this module.
// Callers can't build a Money directly — they must go through `new`,
// so any Money in the wild is guaranteed valid.
pub opaque type Money {
  Money(amount: Int, currency: Currency)
}

// Errors are values, not exceptions. Functions return `Result(Ok, Error)`
// and the type system forces the caller to handle both branches.
pub type MoneyError {
  NegativeAmount
  CurrencyMismatch
}

// Smart constructor. Validates input and returns Ok(Money) or Error(...).
pub fn new(amount: Int, currency: Currency) -> Result(Money, MoneyError) {
  // `case` is Gleam's only conditional — there is no `if`.
  case amount >= 0 {
    True -> Ok(Money(amount, currency))
    False -> Error(NegativeAmount)
  }
}

pub fn same_currency(a: Money, b: Money) {
  a.currency == b.currency
}

// Guard helper. The `then` parameter is a callback — a function value.
// Lowercase `a` in the type is a generic type variable (any type), so this
// works for any caller whose body returns `Result(SOMETHING, MoneyError)`.
fn require_same_currency(
  a: Money,
  b: Money,
  then: fn() -> Result(a, MoneyError),
) -> Result(a, MoneyError) {
  case same_currency(a, b) {
    False -> Error(CurrencyMismatch)
    True -> then()
  }
}

// `use <- f(args)` is sugar for `f(args, fn() { ...rest of block })`.
// this is Gleam's only advanced flow control mechanism. like ? in rust.
// Imagine:
// (defmacro require-same-currency [a b & body]
//  `(if (= (:currency ~a) (:currency ~b))
//     (do ~@body)
//     {:error :currency-mismatch}))
// Reads top-to-bottom as: "require same currency, then compute the sum."
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount + b.amount, a.currency)
}

pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError) {
  use <- require_same_currency(a, b)
  new(a.amount - b.amount, a.currency)
}

// No currency check needed — multiplying by an Int can't change currency.
// Routed through `new` so a negative factor gets rejected the same way
// negative construction does.
pub fn multiply(money: Money, factor: Int) -> Result(Money, MoneyError) {
  new(money.amount * factor, money.currency)
}

pub fn zero(money: Money) -> Money {
  Money(..money, amount: 0)
}

pub fn to_json(money: Money) -> json.Json {
  json.object([
    #("amount", json.int(money.amount)),
    #("currency", currency_to_json(money.currency)),
  ])
}

fn currency_to_json(currency: Currency) -> json.Json {
  case currency {
    USD -> json.string("USD")
    EUR -> json.string("EUR")
    GBP -> json.string("GBP")
  }
}
