# 09. Kata 8: Composition Root + HTTP Boundary

## Concept

The functional core is done: pure aggregates, smart constructors,
events as data. The application layer sits on top: repositories and
use cases that orchestrate them. What's left is the shell, which takes
input from outside (HTTP, say) and turns the result back into a
response.

This kata wires up:

1. A composition root (`src/main.gleam`), the one file that knows how
   to construct concrete adapters and assemble them into a running app.
2. An HTTP boundary, a thin handler that turns requests into use-case
   calls, then turns the typed result into a status code and JSON body.
3. The DI pattern in working code, a `Deps` record built once at
   startup and handed to the request handler through closure capture.

The shell translates; the core decides. Decisions live in pure
functions you've already written (`order.place`, `place_order.run`),
and the shell parses strings into typed values (path → `OrderId`),
routes requests to use-case calls, and translates typed results into
status codes and bodies.

A business rule in the handler means you've drifted out of the shell
and back into the core, and the rule belongs further down.

## Why this is the FCIS payoff chapter

Functional core / imperative shell is a slogan until you see the shell
in code. Your `place_order.run` signature looks like this:

```gleam
pub fn run(repo, id) -> Result(#(Order, List(OrderEvent)), PlaceOrderError)
```

That signature is complete. The handler doesn't need to know anything
beyond "call this, get one of these shapes back, translate":

```
case place_order.run(repo, id) {
  Ok(_)                                          -> 200 OK
  Error(RepoFailed(NotFound))                    -> 404 Not Found
  Error(DomainFailed(CannotPlaceEmptyOrder))     -> 422 Unprocessable
  Error(DomainFailed(CannotModifyPlacedOrder))   -> 409 Conflict
  Error(_)                                       -> 500 Internal Server Error
}
```

Every variant the use case can return becomes one HTTP response, and
the handler does nothing else. The compiler enforces exhaustiveness:
add a new variant to `PlaceOrderError`, forget the HTTP mapping, and
the build breaks at the `case` instead of silently returning 500 in
production.

Types-as-proof at the boundary stops the shell from quietly ignoring a
failure mode the core cares about.

---

## New Gleam fundamentals

### Wisp: the HTTP framework

Wisp is the standard Gleam web framework. The surface area you'll touch:

```gleam
import wisp.{type Request, type Response}

// A handler is just a function:
fn handle(req: Request) -> Response { ... }

// Routing: pattern-match on path segments and method
case wisp.path_segments(req), req.method {
  ["orders", id, "place"], http.Post -> ...
  _, _ -> wisp.not_found()
}

// Response constructors:
wisp.ok()                         // 200
wisp.no_content()                 // 204
wisp.bad_request(detail)          // 400
wisp.not_found()                  // 404
wisp.method_not_allowed(allowed)  // 405
wisp.unprocessable_content()      // 422
wisp.internal_server_error()      // 500
wisp.json_response(json, status)  // any status with JSON body
wisp.response(status)             // any status, no body
wisp.string_body(response, str)   // attach a string body
```

For `409 Conflict`, use `wisp.response(409)`, since Wisp doesn't ship a
named constructor for every code.

### Mist: the underlying HTTP server

Wisp doesn't speak HTTP itself; it delegates to Mist. The wiring at the
top of `main`:

```gleam
import mist
import wisp/wisp_mist

pub fn main() {
  let secret = wisp.random_string(64)  // session signing key
  let assert Ok(_) =
    wisp_mist.handler(handle_request, secret)
    |> mist.new
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}
```

Exact function names drift between Mist versions, so the docs are the
source of truth.

### Wisp/simulate: testing in-process

You don't need a running server to test handlers. `wisp/simulate`
builds request values and feeds them through your handler function:

```gleam
import wisp/simulate

let req = simulate.request(http.Post, "/orders/ORDER-001/place")
let response = handle_request(req)
assert response.status == 200
```

The shell is testable because handlers are functions from request to
response, with impurity tucked inside the Deps closure and the
in-memory repo giving you deterministic state.

### The Deps closure pattern (DI in chill mode)

The handler needs the repository, and the repository can't be a global
because each test wants its own clean copy. So composition time
assembles the handler from the deps:

```gleam
pub fn router(deps: Deps) -> fn(Request) -> Response {
  fn(req) {
    case wisp.path_segments(req), req.method {
      ["orders", id, "place"], http.Post ->
        place_order_handler.run(deps, id)
      _, _ -> wisp.not_found()
    }
  }
}
```

`router` returns a function that closes over `deps`, and Mist serves
that function. Each test builds different deps and gets a different
router, with the closure acting as the container.

---

## Task

Add `wisp` and `mist` as dependencies:

```sh
gleam add wisp mist
```

Create the source files and tests below.

### 1. `src/main.gleam`: the composition root

```gleam
pub fn main() -> Nil
```

Responsibilities:

- Construct the in-memory `OrderRepo` (and anything else the app needs).
- Bundle into a `Deps` record.
- Build the router from `Deps`.
- Start Mist on a port.

Only this file knows the concrete adapters. Below it the use case
takes an interface, never the concrete type.

### 2. `src/web/router.gleam`: request to response dispatcher

```gleam
pub type Deps {
  Deps(order_repo: OrderRepo)
}

pub fn handle(deps: Deps, req: Request) -> Response
```

Pattern-match path segments and method; dispatch to handlers; return
`wisp.not_found()` for unmatched routes.

### 3. `src/web/place_order_handler.gleam`: the one HTTP handler

```gleam
pub fn run(deps: Deps, raw_id: String) -> Response
```

Steps inside `run`:

1. Parse `raw_id` → `OrderId` via `order.new_id`. On failure, `wisp.bad_request`.
2. Call `place_order.run(deps.order_repo, order_id)`.
3. Pattern-match the result. Translate every variant to an HTTP response.

### 4. `test/web/place_order_handler_test.gleam`

Use `wisp/simulate` to drive the handler in-process. Test cases:

- 200 on a successful placement (seed a placeable order, hit the endpoint, assert status + body)
- 400 on a malformed `OrderId` (e.g. empty path segment if your routing allows it)
- 404 when the order doesn't exist (`RepoFailed(NotFound)`)
- 422 on `CannotPlaceEmptyOrder`
- 409 on `CannotModifyPlacedOrder`

### Endpoint contract

```
POST /orders/:id/place

200 OK              { "order_id": "...", "total": "...", "events": [...] }
400 Bad Request     bad order id format
404 Not Found       order not in repo
409 Conflict        order already placed
422 Unprocessable   domain rule violation (empty order, etc.)
500 Server Error    unexpected
```

---

## Hints: what to do

1. Build the Deps record first. It's one field now (`order_repo`).
   Growing it later costs nothing for anything that already takes
   `Deps`, the DI-bag pattern from the chill-DI conversation.
2. The handler is a translation layer. Doing logic in there beyond
   "call use case, map result to HTTP" means you should push that
   logic into the use case. The shell decides response shapes, never
   business outcomes.
3. Exhaustive `case` saves you. Match on `Result(_, PlaceOrderError)`
   and the compiler refuses to let you forget a variant. A wildcard
   `_` belongs at the end for unmodeled storage failures (500), not as
   a substitute for handling a known error.
4. Closure capture for DI. The router takes `Deps` and returns
   `fn(Request) -> Response`. Mist serves the returned function. Each
   test builds its own `Deps` and gets its own handler, so there's
   nothing to share or tear down.
5. For the JSON body, use `gleam_json` (`gleam add gleam_json`). Build
   the body as `json.object([...])`, encode to a string, pass to
   `wisp.json_response(body, 200)`.
6. Tests don't need Mist. `wisp/simulate.request(method, path)` builds
   a request value; pass it to your handler directly and assert on the
   response. The handler is a function; call it like one.
7. `main.gleam` ends with `process.sleep_forever()`. Mist runs in a
   supervised process, so without something to keep `main` alive, the OS
   exits immediately.

---

## Walk-through

The composition root:

```gleam
let assert Ok(repo) = order_repo.in_memory()
let deps = Deps(order_repo: repo)
let handle = router.handle(deps, _)  // closes over deps
```

The third line uses Gleam's `_` placeholder for the request.
`router.handle` takes `(deps, req)`; Mist wants `fn(req)`. The `_`
builds a closure that bakes in `deps` and leaves `req` open, the same
capture trick you wrote in `order_repo` with `Save(order, _)`.

The handler's case-on-result is the table from the kata description:

```gleam
case place_order.run(deps.order_repo, oid) {
  Ok(#(_, events))                               -> { /* 200 + JSON */ }
  Error(RepoFailed(NotFound))                    -> wisp.not_found()
  Error(DomainFailed(CannotPlaceEmptyOrder))     -> wisp.unprocessable_content()
  Error(DomainFailed(CannotModifyPlacedOrder))   -> wisp.response(409)
  Error(DomainFailed(_))                         -> wisp.unprocessable_content()
  Error(RepoFailed(_))                           -> wisp.internal_server_error()
}
```

Each domain failure maps to the most informative HTTP code:

| Domain error | HTTP | Why |
|---|---|---|
| `CannotPlaceEmptyOrder` | 422 | The request was syntactically OK, but the resource state forbids the action |
| `CannotModifyPlacedOrder` | 409 | The action conflicts with the resource's current state |
| Other domain errors | 422 | Catch-all for "rules violated" |
| `RepoFailed(NotFound)` | 404 | No such resource |
| Other repo errors | 500 | Storage broke; client did nothing wrong |

Every domain-knowable failure lives in the type system, so the
boundary translates each one into something meaningful, and anything
unknown falls through to 500. The boundary stays thick at the edges
and thin in the middle, translating what it can and deciding nothing.

---

## Critique

This kata's POST has no JSON request body, since it puts all its
inputs in the URL path. Real APIs send JSON bodies, and parsing them
adds another translation layer, since `gleam_json` decoders give you
`Result(SomeStruct, JsonError)`, which becomes either a 422 with
details or a call into the use case. JSON decoding is separate skill
territory, Wisp + `gleam_json` cookbook material, so I deferred it
to keep the focus on the FCIS shape.

Auth is absent. Wisp ships middleware for sessions, CSRF, and the
rest (`wisp.handle_head`, `wisp.csrf_known_header`, and friends), and
real apps stack them. The kata skips them because the lesson is the
boundary translation.

The handler does no content negotiation; it always returns JSON. Real
APIs check the `Accept` header and switch between JSON, HTML, or text.
Adding it on top of the basics costs little: match on the header,
dispatch to a different formatter.

`Deps` holds one field. The dependency-bag pattern earns its
complexity once several deps travel together; with one, passing the
repo directly would be fine. The bag stays because in a real app
you'll soon add a `clock`, an `event_bus`, a `customer_repo`, and the
bag absorbs those without rippling through every signature.

Real persistence is missing. The composition root builds an
in-memory repo, so a server restart drops every order. A Postgres
adapter satisfying the same `OrderRepo` interface would swap
`order_repo.in_memory()` for `order_repo.postgres(pool)` and nothing
above the adapter would change. That substitution is the payoff Kata 6
promised; here is where you feel it.

Observability is absent. Logs, metrics, and traces all go missing.
Wisp's `wisp.handle_head` middleware can log, and OpenTelemetry
packages exist for real instrumentation, but the kata leaves both out.

---

## DDD takeaway

The full vertical slice runs end to end:

```
HTTP Request
    │
    ▼
src/main.gleam              ← composition root: builds deps, starts server
    │
src/web/router.gleam        ← request → handler dispatch
    │
src/web/place_order_handler.gleam  ← parse, call use case, translate result
    │
src/place_order.gleam       ← use case: load → place → save
    │
src/order_repo.gleam        ← in-memory adapter (or Postgres in prod)
    │
src/order.gleam             ← pure aggregate
```

Each layer is independently testable and carries its own type
vocabulary. The dependency arrows all point inward, boundary to use
case to domain, and the composition root builds the concrete adapters
and hands them in.

Hexagonal architecture in working code amounts to a handful of files
and a record of values, in place of six packages and an
annotation-driven container.

Combined with kata 7 (bounded contexts), kata 6 (repositories), kata 5
(events), and the foundational katas, you can write a backend service
that:

- Has a typed domain model with enforced invariants
- Persists state through a swappable adapter
- Communicates between contexts via events
- Translates HTTP at the edge with no business logic in the handler
- Supports end-to-end tests without a running database or server

The architectural toolkit is complete. Everything beyond is
specialization: sagas for multi-context workflows, event sourcing for
audit-heavy domains, CQRS for read/write asymmetry. None of it changes
the shape of what you've already built; each one extends it in a
particular direction.

---

## Where this leaves the book

You've done the foundation kata progression and the integration
capstone:

| Kata | Adds |
|---|---|
| 1–4 | Domain modeling: types as proof |
| 5 | Events as facts |
| 6 | Repositories: domain-storage decoupling |
| 7 | Bounded contexts: model independence |
| 8 | HTTP boundary + composition root: the shell |

The book supplies the vocabulary; muscle memory sticks only once a
real project carries it.
