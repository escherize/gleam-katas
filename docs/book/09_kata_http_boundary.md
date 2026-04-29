# 09 — Kata 8: Composition Root + HTTP Boundary

## Concept

You've built the *functional core* — pure aggregates, smart constructors,
events as data. You've built the *application layer* — repositories, use
cases that orchestrate. What you haven't built is the **shell**: the part
that receives input from the outside world (HTTP, CLI, message queue),
routes it to a use case, and translates the result back into a response.

This kata wires up:

1. **The composition root** (`src/main.gleam`) — the one place that
   knows how to construct the concrete adapters (in-memory repo, etc.)
   and assemble them into a runnable app.
2. **The HTTP boundary** — a thin handler that converts incoming HTTP
   requests into use-case calls and converts the use case's typed
   results into status codes + JSON bodies.
3. **The dependency-injection pattern in real code** — a `Deps` record
   constructed once at startup, passed to the request handler via
   closure capture so each request has access to the things it needs.

The unifying idea: **the shell does translation, the core does
decisions.** Decisions live in pure functions you've already written
(`order.place`, `place_order.run`). The shell does only:

- Parse strings → typed values (path → `OrderId`)
- Route requests → use-case calls
- Translate typed results → status codes + bodies

If you find yourself writing a business rule in the handler, you've
drifted from the shell back into the core. Push it down.

## Why this is the FCIS payoff chapter

Functional core / imperative shell is a slogan until you see the shell
in code. Look at your `place_order.run`:

```gleam
pub fn run(repo, id) -> Result(#(Order, List(OrderEvent)), PlaceOrderError)
```

That signature is *complete*. There's nothing the handler needs to know
beyond "call this, get back one of these shapes, translate." The
handler reads like:

```
case place_order.run(repo, id) {
  Ok(_)                                          -> 200 OK
  Error(RepoFailed(NotFound))                    -> 404 Not Found
  Error(DomainFailed(CannotPlaceEmptyOrder))     -> 422 Unprocessable
  Error(DomainFailed(CannotModifyPlacedOrder))   -> 409 Conflict
  Error(_)                                       -> 500 Internal Server Error
}
```

Every variant the use case can return becomes one HTTP response. That's
**all** the handler does. The compiler enforces exhaustiveness — if you
add a new error variant to `PlaceOrderError` and forget the HTTP
mapping, the build breaks at the `case` instead of silently returning
500 in production.

This is what types-as-proof gets you at the boundary: the shell *cannot
ignore* a failure mode the core cares about.

---

## New Gleam fundamentals

Two libraries plus one pattern.

### Wisp — the HTTP framework

Wisp is the standard Gleam web framework. Tiny surface area; the parts
you'll touch:

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

That's most of what you need. (For `409 Conflict`, use
`wisp.response(409)` since Wisp doesn't ship a named constructor for
every code.)

### Mist — the underlying HTTP server

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

(Exact function names may drift between Mist versions; check the docs.)

### Wisp/simulate — testing in-process

You don't need a running server to test handlers. `wisp/simulate`
constructs request values and feeds them through your handler
function:

```gleam
import wisp/simulate

let req = simulate.request(http.Post, "/orders/ORDER-001/place")
let response = handle_request(req)
assert response.status == 200
```

This is what makes the shell testable: handlers are pure functions
from request to response (the impurity is hidden inside the Deps
closure, and the in-memory repo provides deterministic state).

### The Deps closure pattern (DI in chill mode)

The handler needs the repository. The repository can't be a global —
each test wants its own clean one. Solution: the handler is *built*
from the deps at composition time:

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

`router` returns a function that closes over `deps`. Mist serves *that*
function. Tests construct different deps and get a different router.
**No DI container, no annotations, no globals.**

---

## Task

Add `wisp` and `mist` as dependencies:

```sh
gleam add wisp mist
```

Create three new source files plus tests.

### 1. `src/main.gleam` — the composition root

```gleam
pub fn main() -> Nil
```

Responsibilities:

- Construct the in-memory `OrderRepo` (and anything else the app needs).
- Bundle into a `Deps` record.
- Build the router from `Deps`.
- Start Mist on a port.

This is the *only* file that knows about concrete adapters. Below it:
the use case takes an interface, never the concrete type.

### 2. `src/web/router.gleam` — request → response dispatcher

```gleam
pub type Deps {
  Deps(order_repo: OrderRepo)
}

pub fn handle(deps: Deps, req: Request) -> Response
```

Pattern-match path segments and method; dispatch to handlers; return
`wisp.not_found()` for unmatched routes.

### 3. `src/web/place_order_handler.gleam` — the one HTTP handler

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

## Hints — what to do

1. **Build the Deps record before anything else.** It's a one-field record now (`order_repo`); growing it later is a no-op for everything that already takes `Deps`. This is the practical "DI bag" pattern from the chill-DI conversation.
2. **The handler is a translation layer.** Anytime you find yourself doing logic in the handler beyond "call use case, map result to HTTP," push that logic down into the use case. The shell decides *response shapes*, never *business outcomes*.
3. **Exhaustive `case` is your friend.** When you `case` on `Result(_, PlaceOrderError)`, the compiler refuses to let you forget a variant. Use that — don't fall back to a wildcard `_` until you've explicitly handled every domain case you care about. The wildcard is the catch-all for *unexpected* errors (500), not for *known* errors you didn't bother to map.
4. **Closure capture for DI.** The router takes `Deps` and returns a `fn(Request) -> Response`. Mist serves that returned function. Each test constructs its own `Deps` and gets its own handler — no shared state, no setup/teardown.
5. **For the JSON body**, use `gleam_json` (`gleam add gleam_json`). Build the response body as `json.object([...])`, encode to a string, pass to `wisp.json_response(body, 200)`.
6. **Tests don't need Mist.** `wisp/simulate.request(method, path)` builds a request value; pass it to your handler function directly; assert on the response. No server, no port, no flaky network.
7. **`main.gleam` ends with `process.sleep_forever()`** — Mist runs in a supervised process; without keeping `main` alive, the OS would exit immediately.

---

## Walk-through

**The composition root in three lines:**

```gleam
let assert Ok(repo) = order_repo.in_memory()
let deps = Deps(order_repo: repo)
let handle = router.handle(deps, _)  // closes over deps
```

The third line uses Gleam's `_` placeholder for the request: `router.handle`
takes `(deps, req)`, but Mist wants `fn(req)`. The `_` builds a closure
that bakes in `deps` and leaves `req` as the open argument. Same pattern
as the `Save(order, _)` capture you wrote in `order_repo`.

**The handler's case-on-result is the table from the kata description**:

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

**Why this works:** every domain-knowable failure is in the type system,
so the boundary can translate each one to a meaningful response. Every
unknown failure (unmodeled exceptions, network hiccups) falls through
to 500. The boundary is *thick at the edges* (translates everything it
can) and *thin in the middle* (does no business logic).

---

## Critique

**No JSON request bodies.** This kata's POST has all its inputs in the
URL path. Real APIs send JSON bodies; parsing them adds another translation
layer (`gleam_json` decoders → `Result(SomeStruct, JsonError)` → either
422 with details or pass to the use case). That's a whole separate skill —
Wisp + `gleam_json` cookbook material — and it's deferred here so the
focus stays on the FCIS shape.

**No auth, no sessions, no CSRF.** Wisp has middleware for all of these
(`wisp.handle_head`, `wisp.csrf_known_header`, etc.). Real apps stack
them; the kata doesn't, because the lesson is the boundary translation,
not the security stack.

**No content negotiation.** We always return JSON. Real APIs check the
`Accept` header and return JSON or HTML or text accordingly. Easy to add
once you have the basics — pattern-match on the header, dispatch to a
different formatter.

**`Deps` is a one-field record.** The "bag of dependencies" only earns
its complexity when you have 3+ deps that travel together. With one,
just passing the repo directly would be fine. We keep it because in a
real app you'll add a `clock`, `event_bus`, `customer_repo`, and so on
quickly — and the bag pattern absorbs those without changing function
signatures everywhere.

**No real persistence.** The composition root constructs an in-memory
repo. Restart the server and every order is gone. A Postgres adapter
(satisfying the same `OrderRepo` interface) would replace
`order_repo.in_memory()` with `order_repo.postgres(pool)` — *and
nothing else changes*. Same use case, same handler, same router. That
substitution is the payoff Kata 6 promised; this kata is where you can
finally feel it.

**No observability.** No request logs, no metrics, no traces. Wisp's
`wisp.handle_head` middleware can log; OpenTelemetry packages exist for
real instrumentation. Skipped here.

---

## DDD takeaway

You now have the full vertical slice running:

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

Each layer is independently testable. Each layer has its own type
vocabulary. The dependency arrows all point inward (boundary → use
case → domain), with the composition root constructing the concrete
adapters and injecting them.

This *is* what hexagonal architecture looks like in working code. Not
six packages and an annotation-driven container — three or four files
and one record of values.

Combined with kata 7 (bounded contexts), kata 6 (repositories), kata 5
(events), and the foundational katas, you can now write a backend
service that:

- Has a typed domain model with enforced invariants
- Persists state through a swappable adapter
- Communicates between contexts via events
- Translates HTTP at the edge with no business logic in the handler
- Is testable end-to-end without spinning up a database or a server

That's a complete architectural toolkit. Everything beyond is
specialization — sagas for multi-context workflows, event sourcing
for audit-heavy domains, CQRS for read/write asymmetry. None of it
changes the shape of what you've already built; each one extends it
in a specific direction.

---

## Where this leaves the book

You've now done the foundation kata progression *and* the integration
capstone:

| Kata | Adds |
|---|---|
| 1–4 | Domain modeling — types as proof |
| 5 | Events as facts |
| 6 | Repositories — domain-storage decoupling |
| 7 | Bounded contexts — model independence |
| 8 | HTTP boundary + composition root — the shell |

Pick a real project, build it with these patterns, ship it. The book
exists to give you the vocabulary and the muscle memory; the muscle
memory only sticks once you do it on something real. Good luck.
