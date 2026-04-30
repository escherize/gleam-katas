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

pub fn main() -> Nil {
  todo
  //  1. let assert Ok(repo) = order_repo.in_memory()
  //  2. let deps = router.Deps(order_repo: repo)
  //  3. let handle = router.handle(deps, _)   // close over deps
  //  4. let secret = wisp.random_string(64)
  //  5. let assert Ok(_) =
  //       wisp_mist.handler(handle, secret)
  //       |> mist.new
  //       |> mist.port(8080)
  //       |> mist.start
  //  6. process.sleep_forever()
}
