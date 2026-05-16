# 12. Putting It Into Practice

The katas teach the patterns. The harder skill is reading a working
codebase and judging which of these tools earns its weight today and
which doesn't, yet or ever. This chapter is opinionated; disagreement
is welcome where context differs.

---

## Don't start with all of it

If you're starting a fresh Gleam project tomorrow, do *not* start with:

- A `domain/`, `application/`, `infrastructure/` folder split
- An `OrderRepo` interface before there's a second implementation
- An event bus before something needs to react to a transition
- A composition root with a `Deps` record before there are multiple deps
- Bounded contexts before there are two distinct sub-models

Start with:

- One module per concept (`order.gleam`, `customer.gleam`)
- Smart constructors that return `Result`
- Functions that take and return values
- A flat `src/` directory until you feel pressure to split

That foundation covers most of what most apps need.

The patterns in this book are answers to specific problems. Apply them
once you've hit the problem. Introducing them preemptively is how DDD
earns its reputation for ceremony.

---

## Minimum viable DDD

For a small project (under ~10k LoC, one team), here's what earns
its weight:

| Pattern | Worth it for...|
|---|---|
| Smart constructors + `Result` errors | every project, day one |
| Opaque types for domain values | every project, day one |
| Aggregate root + state-transition methods | when ≥3 mutations cluster around the same fields |
| Repository as record of functions | when you have ≥2 storage backends OR want to test without one |
| Domain events | when something must react without coupling, or you want an audit log |
| Bounded contexts as folders | when the model honestly has two sub-models, not just two screens |
| Use cases as named functions | when the app has more than ~5 endpoints |
| Composition root with `Deps` bag | when you have ≥3 deps that travel together |
| `result.try` chains in use cases | as soon as use cases call multiple fallible things |
| Idempotent event handlers | as soon as something replays events (which something will) |
| The HTTP boundary as pure translation | every HTTP-served project |

When you're not sure whether a pattern earns its weight, wait. Adding
it later, once the pain is real, costs less than carrying scaffolding
through six months of nobody needing it, and removing an entrenched
abstraction is politically harder than adding the missing one.

---

## Where bounded contexts come from

Contexts emerge from use. They show up when team boundaries harden,
when two parts of the model start disagreeing about what the same
word means, or when a one-line type change drags three people into
the same PR. Whiteboard contexts drawn on day one are guesses; lived
contexts are evidence.

You'll know it's time to split when:

- The `Customer` type has 14 fields and any given function uses 3
- A change to `Customer` blocks a team that doesn't care about the field you're touching
- People start writing `BillingCustomer = Customer with extra fields` workaround types to escape the noise
- A code review for a tiny feature requires sign-off from three teams

That's when you reach for the bounded contexts chapter and split.

The inverse holds, too. Two contexts that always change together
aren't two contexts. If `customer_billing.gleam` and
`customer_marketing.gleam` show up in the same PR every time, merge
them and stop pretending.

### A note on the missing customer endpoints

The kata's HTTP boundary accepts `customer_id` as a string and never
checks whether the customer exists. There are no `POST /customers` or
`GET /customers/:id` endpoints, even though `src/customer.gleam`
defines the type, because we cut them to keep the kata short.

If you want to add them, you have to decide how Ordering should treat
the cross-context reference:

- (a) Pre-validation: call `CustomerRepo.find` before accepting an order; reject unknown ids.
- (b) Async subscription: Customer publishes `CustomerCreated`; Ordering keeps a local index.
- (c) Trust by default: accept any id, reconcile via a periodic job if needed.

Pick one deliberately when it matters. The kata implements (c) by
omission, which is fine for a learning project but worth being honest
about for anything that ships.

---

## Refactor moves as the system grows

These shape-changes show up in roughly this order, each provoked by
its own pain.

### "My CRUD endpoints are getting hard to test"
Pull the business logic into a domain function and test that directly.
The endpoint becomes a 5-line translator, moving from Rails controller
to use case.

### "I keep re-validating the same string in 8 places"
Make it a value object: an opaque type with a smart constructor that
validates once at the boundary. (Kata 1.)

### "I have a 12-field record and I add one more every sprint"
Find the sub-clusters hiding inside. Often there's an aggregate root
pretending to be a record, with two value objects pretending to be
fields. (Katas 1, 2, 4.)

### "Every endpoint takes 9 arguments now"
Bundle them into a `Deps` record and pass it down. (Chill-DI bag.)

### "I want X to happen after Y but X shouldn't know about Y"
Introduce an event that Y emits and X listens for. (Kata 5.)

### "Tests are slow because they hit the database"
Repository as record of functions; pass `in_memory()` in tests. (Kata 6.)

### "Two teams are stepping on each other in the same module"
Bounded contexts. (Kata 7.)

### "Restarting the server loses everything"
SQLite (or Postgres) adapter, same repo interface. (Kata 9.)

Something concrete in the codebase provokes each move: write the
straightforward thing, hit the wall, refactor toward the pattern.
The wall is information unavailable on day one and unrecoverable
from speculation.

---

## Signs you've over-applied DDD

A pattern outlasts its reason and turns into ceremony. The shapes
that line tends to take:

- A Repository interface with one implementation, a wrapper rather than
  a port. If you aren't swapping implementations between tests and prod,
  or between backends, the indirection isn't paying for itself yet.
- Code reviews that argue whether something is an Entity or a Value
  Object. Productive for five minutes, a red flag at thirty.
- An aggregate root with 47 methods, usually two aggregates trying to
  be one, or an aggregate that wants to be a domain service.
- Bug fixes that touch six files because of "the layering." Layers
  are supposed to contain changes; when small changes ripple wide, the
  layering is doing the opposite of its job.
- A Saga or Process Manager added "just in case." These solve specific
  scaling problems, and without the problem they're cosplay.
- A Deps record with one field. Just pass the field; reach for the bag
  once there are three things travelling together.

When you spot one, the fix is usually to delete the abstraction and
inline what it was wrapping. Subtractive refactoring is the most
underrated tool in this toolkit.

---

## Testing in a DDD-shaped pyramid

The pyramid the katas built:

```
              ╱─────────╲       few, slow:
             ╱  end-to- ╲       wisp/simulate -> handler -> use case
            ╱    end     ╲      -> repo -> assert response
           ╱──────────────╲
          ╱  use case      ╲    some, medium:
         ╱  with in-memory  ╲   place_order.run against in_memory()
        ╱     adapters       ╲  repo. No HTTP. No real DB.
       ╱──────────────────────╲
      ╱   pure domain function  ╲  many, fast:
     ╱        unit tests          ╲  order.add_line(...) with various
    ╱──────────────────────────────╲ inputs. No IO. Milliseconds.
```

The pyramid only inverts when there's nothing pure to test. The
non-DDD shape (logic smeared across HTTP handlers, ORM callbacks,
and DB triggers) forces every test to the top, because no clean
domain layer exists to exercise on its own. The testing payoff from
DDD is that the bottom of the pyramid exists at all.

Property-based testing belongs at the bottom. Smart constructors and
state-transition methods are obvious property targets. ("For all
non-empty strings, `email.new` either succeeds or returns a typed
error.")

---

## Composition root in production

The `main.gleam` from kata 8 was the minimum. A production
composition root does more:

```gleam
pub fn main() {
  // 1. Read configuration from env vars, at the top, exactly once
  let config = config.from_env()

  // 2. Open shared resources (DB pool, HTTP clients, secret keys)
  let assert Ok(conn) = sqlight.open(config.database_path)
  let secret = config.session_secret

  // 3. Construct adapters
  let assert Ok(order_repo) = order_repo_sqlite.sqlite(conn)

  // 4. Bundle dependencies
  let deps = Deps(
    order_repo: order_repo,
    clock: time.now,
    // ... more as the app grows
  )

  // 5. Build the request handler from deps
  let handle = web.router(deps)

  // 6. Start the server (supervised when you need crash recovery)
  let assert Ok(_) =
    wisp_mist.handler(handle, secret)
    |> mist.new
    |> mist.port(config.port)
    |> mist.start

  process.sleep_forever()
}
```

Worth internalizing about this shape:

- All configuration enters at the top. `config.from_env()` is the one
  place that reads env vars, and everything else takes typed config
  values. Scattering `env.get("DATABASE_URL")` calls through the
  codebase always rots.
- Resources have known lifetimes. The DB connection lives for the
  process lifetime; tests open their own. A "lazy connection pool
  that auto-initializes on first use" reliably produces the "works
  locally, breaks in production" class of bug.
- Failure to initialize crashes the boot. `let assert Ok(...)` on each
  adapter means that if the DB can't open, the process exits now,
  before the first request, not three minutes later when a user
  notices.
- Supervision, when you need it, wraps everything. For long-running
  apps with multiple actors (event bus, scheduler, background jobs),
  the composition root builds a supervisor and starts it. Plain HTTP
  servers don't need this; Mist supervises itself.
- The composition root is the only file with `let assert Ok(...)` on
  adapter construction. Below it, everything takes already-constructed
  values, and nothing lazily initializes anything.

---

## Talking to non-DDD colleagues

Most engineers haven't read Evans. Saying "the aggregate's invariant
requires that the bounded context emit a domain event so the
anti-corruption layer can translate it" will reliably glaze the room.

Translate down:

| DDD term | Plain version |
|---|---|
| Aggregate | "The cluster of stuff that has to be saved together" |
| Aggregate root | "The thing the rest of the code talks to" |
| Invariant | "A rule we always want to be true" |
| Bounded context | "The slice of the system this team owns" |
| Value object | "A type that's just its data, like a number" |
| Entity | "Something with an ID, same person across renames" |
| Repository | "How we load and save the X" |
| Domain event | "Something that happened, that other parts care about" |
| Use case | "The thing one button does" |
| Smart constructor | "The function that makes a valid one" |
| Anti-corruption layer | "The translator between us and the other team's API" |
| Ports and adapters | "The implementation plugs into an interface" |
| Ubiquitous language | "We use the same words the business uses" |

Reach for jargon when it makes the conversation shorter, plain
language when it makes the conversation clearer. The system is what
matters; the vocabulary is the tool you use to talk about it.

---

## What's beyond the foundation

The katas covered the load-bearing patterns. Beyond them, larger
ideas show up in production systems, roughly in this order:

### 1. Event sourcing
Store the event log and derive current state by replaying it. The log
is the source of truth, and aggregate state is just a projection of
it. You get an audit log for free, and "what was this customer's
state on June 14?" becomes a query instead of a forensic exercise.

When to reach: high audit or compliance demand; complex history the
team has to reason about; "how did we get into this state?" as a
recurring debugging question.

When to skip: most CRUD apps. The complexity overhead lasts forever.

### 2. CQRS: Command/Query Responsibility Segregation
Separate models for writes (commands) and reads (queries). Aggregates
handle the writes while denormalized projections handle the reads.

When to reach: read-heavy apps where the aggregate shape is the wrong
shape to query; cross-aggregate reports; materialized views.

When to skip: writes and reads use roughly the same shape.

### 3. Sagas / Process Managers
Coordinated multi-step workflows that span aggregates or services:
"place order, reserve inventory, charge card, ship, email receipt."
Each step is a use case, and the saga handles sequencing, retry, and
compensation when a step fails.

When to reach: multi-aggregate workflows that cross service
boundaries; explicit compensation logic that the business cares
about.

When to skip: workflows that fit in one transaction.

### 4. Distributed event delivery
Moving from in-process function calls to a message broker (Kafka,
NATS, RabbitMQ) or BEAM distribution. Aggregate code stays identical;
only the wiring at the composition root changes, publishing to the
broker instead of calling handler functions directly.

When to reach: services in different processes or data centers;
at-least-once delivery, retries, dead-letter queues; consumers that
should be independently restartable.

When to skip: monolith, or any case where a synchronous in-process
call is fine.

### 5. Anti-corruption layers in earnest
Adapters between your domain and a system whose model you don't
control. The ACL translates their vocabulary into yours, so the rest
of your code only ever sees your types.

When to reach: integrating with a system you don't own and can't
change; multiple teams whose APIs evolve on their own schedule.

When to skip: small project, one team, all code under your
control.

Each of these is its own book. The kata progression is the foundation
that makes those books readable.

---

## A few patterns the book skipped on purpose

Worth flagging because you'll run into them in other books and wonder
where they went:

- Domain Services: operations that don't naturally belong on any one
  entity. ("Transfer money from A to B", since neither account "owns"
  the transfer.) In Gleam, that's a top-level function that takes both.
  The "Service" object is OO baggage.
- Specifications: composable query objects like "active customers in
  California with last order over $100." Useful in OO languages where
  queries have to be objects. In Gleam, write functions and compose
  them with `|>`.
- Factories as classes. Gleam's smart constructors already are the
  factory, so no additional ceremony earns its keep.
- Layered architecture as packages: `application/`, `domain/`,
  `infrastructure/`. Often right in spirit and often expensive in
  practice. Start flat and let coupling pressure suggest the
  split.

---

## A few things that aren't DDD but pair well with it

- Property-based testing for smart constructors and pure domain
  functions. `gleam_qcheck` or similar.
- Snapshot testing for stable JSON outputs like HTTP responses and
  events. Catches accidental shape changes you'd otherwise notice in
  production.
- Schema migrations as ordered SQL files (`dbmate`, `sqitch`,
  `gorrion`). Plain SQL keeps you honest about what the database
  does.
- OpenTelemetry traces through the use case → handler → adapter call
  graph. The DDD layering makes the trace structure read like the
  code.
- Static dependency-graph linting, so you find out the moment Ordering
  accidentally imports something from Shipping.

---

## A short closing

By this point you have the vocabulary, the patterns in idiomatic
Gleam, and some judgment about when to use them and when to wait.
You've also seen the Gleam-specific moves that keep each pattern
small: records of functions in place of interface hierarchies, smart
constructors in place of Factory classes, closures in place of DI
containers, modules in place of multi-package layouts.

What a book can't give you is the muscle memory. That comes from
doing it on a working project: hitting friction, choosing to introduce
or remove a pattern, watching the result, and updating your mental
model from what happened.

Build something small with these tools and ship it. Most of what the
project needs was already in the first four chapters, and the rest of
the toolkit sits in the back of the mind, available when a problem
justifies pulling it out.
