import customer.{type CustomerId}
import gleam/list
import gleam/result
import money.{type Money}

pub opaque type OrderId {
  OrderId(value: String)
}

// Internal — no `pub` on the constructor's fields conceptually,
// and the outside world should not build these directly.
type OrderLine {
  OrderLine(sku: String, quantity: Int, unit_price: Money)
}

pub type OrderStatus {
  Draft
  Placed
}

pub opaque type Order {
  Order(
    id: OrderId,
    customer_id: CustomerId,
    lines: List(OrderLine),
    status: OrderStatus,
  )
}

pub type OrderError {
  EmptyOrderId
  EmptySku
  NonPositiveQuantity
  CannotModifyPlacedOrder
  CannotPlaceEmptyOrder
  CurrencyMismatch
  InvalidOrderTotal
}

pub fn new_id(raw: String) -> Result(OrderId, OrderError) {
  case raw {
    "" -> Error(EmptyOrderId)
    _ -> Ok(OrderId(raw))
  }
}

// Creates a Draft order with no lines.
pub fn new(id: OrderId, customer_id: CustomerId) -> Order {
  Order(id, customer_id, [], Draft)
}

fn no_modify_placed(
  o: Order,
  then: fn() -> Result(t, OrderError),
) -> Result(t, OrderError) {
  case o.status == Placed {
    False -> then()
    True -> Error(CannotModifyPlacedOrder)
  }
}

fn non_empty_sku(
  sku: String,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case sku {
    "" -> Error(EmptySku)
    _ -> then()
  }
}

fn positive_qty(
  q: Int,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case q > 0 {
    True -> then()
    False -> Error(NonPositiveQuantity)
  }
}

fn currency_matches(
  existing: List(OrderLine),
  new_price: Money,
  then: fn() -> Result(a, OrderError),
) -> Result(a, OrderError) {
  case existing {
    // if there is an order, make sure we have homogeneous unit lines
    [ol, ..] -> {
      case money.same_currency(ol.unit_price, new_price) {
        True -> then()
        False -> Error(CurrencyMismatch)
      }
    }
    _ -> then()
  }
}

pub fn add_line(
  order: Order,
  sku: String,
  quantity: Int,
  unit_price: Money,
) -> Result(Order, OrderError) {
  use <- no_modify_placed(order)
  use <- non_empty_sku(sku)
  use <- positive_qty(quantity)
  use <- currency_matches(order.lines, unit_price)
  let new_line = OrderLine(sku, quantity, unit_price)
  Ok(Order(..order, lines: [new_line, ..order.lines]))
}

pub fn place(order: Order) -> Result(Order, OrderError) {
  use <- no_modify_placed(order)
  case order.lines {
    [] -> Error(CannotPlaceEmptyOrder)
    _ -> Ok(Order(..order, status: Placed))
  }
}

// Calculate the total value of all items in an order
pub fn total(order: Order) -> Result(Money, OrderError) {
  case order.lines {
    // If the order has at least one line...
    [ol, ..] -> {
      // Step 1: Calculate the total amount for each line (unit_price * quantity)
      // This uses list.try_map because money.multiply can fail (e.g., overflow)
      // We get a Result(List(Money), money.MoneyError)
      use amounts <- result.try(
        list.try_map(order.lines, fn(ol) {
          // For each order line, multiply unit price by quantity
          money.multiply(ol.unit_price, ol.quantity)
        })
        // Convert any money.MoneyError to our domain error type
        // TODO: Should distinguish between currency vs calculation errors
        |> result.map_error(fn(_) { InvalidOrderTotal }),
      )

      // Step 2: Sum up all the line totals
      // Start with zero in the same currency as the first line
      // Use try_fold because money.add can fail (e.g., currency mismatch, overflow)
      list.try_fold(amounts, money.zero(ol.unit_price), money.add)
      // Convert money.MoneyError to domain error
      // Currency mismatch here would be a programming error since amounts should be homogeneous
      |> result.map_error(fn(_) { InvalidOrderTotal })
    }

    // If the order has no lines, we can't calculate a total
    _ -> Error(InvalidOrderTotal)
  }
}
