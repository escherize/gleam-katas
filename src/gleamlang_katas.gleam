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

import envoy
import gleam/erlang/process
import gleam/int
import gleam/result
import gleam/string
import mist
import order_repo
import order_repo_sqlite
import sqlight
import web/router
import wisp
import wisp/wisp_mist

pub type RepoBackend {
  InMemory
  Sqlite(path: String)
}

pub type Config {
  Config(repo: RepoBackend, port: Int)
}

fn parse_env_var(name: String, with parse, default default: a) -> a {
  envoy.get(name) |> result.try(parse) |> result.unwrap(default)
}

fn env_vars_to_config() -> Config {
  let port: Int = parse_env_var("PORT", with: int.parse, default: 8080)
  let order_repo = envoy.get("ORDER_REPO") |> result.unwrap("memory")
  let repo_backend = case order_repo {
    "memory" -> InMemory
    path -> Sqlite(path)
  }
  Config(repo: repo_backend, port: port)
}

fn build_order_repo(config: Config) -> Result(order_repo.OrderRepo, String) {
  case config.repo {
    InMemory -> order_repo.in_memory() |> result.map_error(string.inspect)
    Sqlite(path) -> {
      use conn <- result.try(
        sqlight.open(path) |> result.map_error(string.inspect),
      )
      order_repo_sqlite.sqlite(conn) |> result.map_error(string.inspect)
    }
  }
}

pub fn main() -> Nil {
  let config = env_vars_to_config()
  let assert Ok(repo) = build_order_repo(config)

  let deps = router.Deps(order_repo: repo)
  let handle = router.handle(deps, _)
  // close over deps
  let secret = wisp.random_string(64)
  let assert Ok(_) =
    wisp_mist.handler(handle, secret)
    |> mist.new
    |> mist.port(config.port)
    |> mist.start
  process.sleep_forever()
}
