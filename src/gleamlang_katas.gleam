//// Kata 8 — Composition root
////
//// Read: docs/book/09_kata_http_boundary.md
////
//// The composition root is the *one* file that:
////   - reads configuration / env
////   - constructs the concrete adapters (in_memory repo for now)
////   - bundles them into a `Deps` record
////   - hands `Deps` to the router (closure capture: returns a
////     fn(Request) -> Response)
////   - starts Mist on a port
////
//// Below this file: nothing constructs adapters. Everything takes
//// already-constructed values via Deps.
////
//// To run:
////   gleam run
////   curl -X POST http://localhost:8080/orders/ORDER-001/place
////   (will 404 — no such order until you POST a create endpoint or
////    seed via repo, both of which are outside the kata 8 scope)

import gleam/erlang/process
import mist
import order_repo
import web/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  let assert Ok(repo) = order_repo.in_memory()
  let deps = router.Deps(order_repo: repo)
  let handle = router.handle(deps, _)
  // close over deps
  let secret = wisp.random_string(64)
  let assert Ok(_) =
    wisp_mist.handler(handle, secret)
    |> mist.new
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}
