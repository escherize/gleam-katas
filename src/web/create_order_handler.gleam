import customer
import gleam/json
import order
import order_repo.{type OrderRepo}
import wisp.{type Response}

pub fn run(
  repo: OrderRepo,
  raw_order_id: String,
  raw_customer_id: String,
) -> Response {
  case order.new_id(raw_order_id), customer.new_id(raw_customer_id) {
    Error(_), _ -> wisp.bad_request("invalid order_id")
    _, Error(_) -> wisp.bad_request("invalid customer_id")
    Ok(oid), Ok(cid) -> {
      let #(o, _events) = order.new(oid, cid)
      case repo.save(o) {
        Error(_) -> wisp.internal_server_error()
        Ok(Nil) -> {
          let body =
            [#("order_id", json.string(raw_order_id))]
            |> json.object
            |> json.to_string
          wisp.json_response(body, 201)
        }
      }
    }
  }
}
