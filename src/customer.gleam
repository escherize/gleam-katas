import email.{type Email}
import gleam/dynamic/decode
import gleam/string

pub opaque type CustomerId {
  CustomerId(value: String)
}

pub fn customer_id_decoder() -> decode.Decoder(CustomerId) {
  decode.string |> decode.map(fn(value) { CustomerId(value:) })
}

pub opaque type Customer {
  Customer(id: CustomerId, name: String, email: Email)
}

pub type CustomerError {
  EmptyName
  EmptyId
}

pub fn new_id(raw: String) -> Result(CustomerId, CustomerError) {
  let raw = string.trim(raw)
  case string.is_empty(raw) {
    True -> Error(EmptyId)
    False -> Ok(CustomerId(raw))
  }
}

pub fn new(
  id: CustomerId,
  name: String,
  email: Email,
) -> Result(Customer, CustomerError) {
  case string.length(name) {
    0 -> Error(EmptyName)
    _ -> Ok(Customer(id, name, email))
  }
}

pub fn customer_id(customer_id: CustomerId) -> String {
  customer_id.value
}

pub fn id(customer: Customer) -> CustomerId {
  customer.id
}

pub fn rename(
  customer: Customer,
  new_name: String,
) -> Result(Customer, CustomerError) {
  new(customer.id, new_name, customer.email)
}

pub fn change_email(customer: Customer, new_email: Email) -> Customer {
  Customer(customer.id, customer.name, new_email)
}

pub fn same_customer(a: Customer, b: Customer) -> Bool {
  a.id == b.id
}
