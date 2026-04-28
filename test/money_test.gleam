import money

// ---- new ----

pub fn new_positive_amount_is_ok_test() {
  let assert Ok(_) = money.new(150, money.USD)
}

pub fn new_zero_is_ok_test() {
  let assert Ok(_) = money.new(0, money.USD)
}

pub fn new_negative_is_rejected_test() {
  assert money.new(-1, money.USD) == Error(money.NegativeAmount)
}

// ---- add ----

pub fn add_same_currency_sums_amounts_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(b) = money.new(50, money.USD)
  let assert Ok(expected) = money.new(200, money.USD)
  assert money.add(a, b) == Ok(expected)
}

pub fn add_is_commutative_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(b) = money.new(50, money.USD)
  assert money.add(a, b) == money.add(b, a)
}

pub fn add_different_currencies_is_rejected_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(b) = money.new(50, money.EUR)
  assert money.add(a, b) == Error(money.CurrencyMismatch)
}

// ---- subtract ----

pub fn subtract_same_currency_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(b) = money.new(50, money.USD)
  let assert Ok(expected) = money.new(100, money.USD)
  assert money.subtract(a, b) == Ok(expected)
}

pub fn subtract_to_zero_is_ok_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(expected) = money.new(0, money.USD)
  assert money.subtract(a, a) == Ok(expected)
}

pub fn subtract_going_negative_is_rejected_test() {
  let assert Ok(small) = money.new(50, money.USD)
  let assert Ok(big) = money.new(150, money.USD)
  assert money.subtract(small, big) == Error(money.NegativeAmount)
}

pub fn subtract_different_currencies_is_rejected_test() {
  let assert Ok(a) = money.new(150, money.USD)
  let assert Ok(b) = money.new(50, money.EUR)
  assert money.subtract(a, b) == Error(money.CurrencyMismatch)
}

// ---- multiply ----

pub fn multiply_by_positive_factor_test() {
  let assert Ok(m) = money.new(150, money.USD)
  let assert Ok(expected) = money.new(300, money.USD)
  assert money.multiply(m, 2) == Ok(expected)
}

pub fn multiply_by_one_is_identity_test() {
  let assert Ok(m) = money.new(150, money.USD)
  assert money.multiply(m, 1) == Ok(m)
}

pub fn multiply_by_zero_yields_zero_money_test() {
  let assert Ok(m) = money.new(150, money.USD)
  let assert Ok(expected) = money.new(0, money.USD)
  assert money.multiply(m, 0) == Ok(expected)
}

pub fn multiply_preserves_currency_test() {
  let assert Ok(eur) = money.new(100, money.EUR)
  let assert Ok(expected) = money.new(300, money.EUR)
  assert money.multiply(eur, 3) == Ok(expected)
}

pub fn multiply_by_negative_factor_is_rejected_test() {
  let assert Ok(m) = money.new(150, money.USD)
  assert money.multiply(m, -1) == Error(money.NegativeAmount)
}
