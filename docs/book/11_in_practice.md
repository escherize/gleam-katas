# 11 — Putting It Into Practice

The katas teach the patterns. Knowing patterns isn't the same as knowing
when to apply them, when to skip them, and how to talk about them with
the people who haven't read this book. This chapter is the distilled
experience version — what to actually do on Monday morning.

It's deliberately opinionated. Disagree where your context differs.

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

That's the foundation. It's also already 90% of what most apps need.

**The patterns are answers to specific problems.** Apply them when you
hit the problem. Introducing them preemptively is how DDD earns its
reputation for ceremony.

---

## Minimum viable DDD

For a small project (under ~10k LoC, single team), what genuinely earns
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
| Idempotent event handlers | as soon as events get replayed (which they will) |
| The HTTP boundary as pure translation | every HTTP-served project |

If you're not sure whether a pattern earns its weight: **wait**. The
cost of adding a pattern later (when you feel the pain) is much lower
than the cost of carrying its scaffolding through six months of
not-needing-it. *Subtractive refactors are harder politically than
additive ones.*

---

## Where bounded contexts actually come from

You don't sit down on day one and design contexts. You don't draw
boxes on a whiteboard before writing code.

**Contexts emerge from team boundaries, organizational pressure, and
the noticeable moment when two parts of the model start disagreeing
about what the same word means.**

Concretely, you'll know it's time to split when:

- The `Customer` type has 14 fields and any given function uses 3
- A change to `Customer` blocks a team that doesn't care about the field you're touching
- People start writing `BillingCustomer = Customer with extra fields` workaround types to escape the noise
- A code review for a tiny feature requires sign-off from three teams

When that happens — *that's* when you reach for the bounded contexts
chapter and split. Not before.

The opposite signal is just as important: **two contexts that always
change together aren't really separate.** If `customer_billing.gleam`
and `customer_marketing.gleam` always get touched in the same PR,
merge them.

---

## Refactor moves as the system grows

Concrete shape-changes you'll do, roughly in the order they tend to
appear. Each is a response to a specific pain.

### "My CRUD endpoints are getting hard to test"
→ Pull the business logic into a domain function. Test that. The
endpoint becomes a 5-line translator. *Move from "Rails controller"
to "use case."*

### "I keep re-validating the same string in 8 places"
→ Make it a value object. Opaque type, smart constructor, validate
once at the boundary. *Kata 1.*

### "I have a 12-field record and I add one more every sprint"
→ Find the sub-clusters hiding inside. Often there's an aggregate
root pretending to be a record, with two value objects pretending
to be fields. *Katas 1, 2, 4.*

### "Every endpoint takes 9 arguments now"
→ Introduce a `Deps` record. Pass it down. *Chill-DI bag.*

### "I want X to happen after Y but X shouldn't know about Y"
→ Introduce an event. Y emits, X listens. *Kata 5.*

### "Tests are slow because they hit the database"
→ Repository as record of functions; pass `in_memory()` in tests.
*Kata 6.*

### "Two teams are stepping on each other in the same module"
→ Bounded contexts. *Kata 7.*

### "Restarting the server loses everything"
→ SQLite (or Postgres) adapter, same repo interface. *Kata 9.*

Each move is provoked, not predicted. **You write the simple thing,
hit the wall, refactor toward the pattern.** The wall is the
information you didn't have on day one.

---

## Signs you've over-applied DDD

Patterns become ceremony when they outlast their reason. Warning
signs:

- **A Repository interface with one implementation.** That's not a
  port; it's a wrapper. If you're not actually swapping
  implementations (between tests and prod, or between backends),
  you don't need the indirection yet.
- **Code reviews that argue whether something is an Entity or a Value
  Object.** Productive question for 5 minutes; red flag for 30.
- **An aggregate root with 47 methods.** It's two aggregates trying
  to be one, or it's an aggregate that should be a domain service.
- **Bug fixes requiring touches in 6 files because of "the
  layering."** Layers exist to *contain* changes, not propagate
  them. If small changes ripple wide, the layering is wrong.
- **A Saga or Process Manager added "just in case."** These solve
  specific scaling problems. Without the problem, they're cosplay.
- **A Deps record with one field.** Pass the field directly. Add the
  bag when there are 3+ things to pass.

When you spot one: the fix is usually to **delete the abstraction and
inline what it was wrapping**. Subtractive refactors are the most
underrated tool in DDD.

---

## Testing in a DDD-shaped pyramid

The pyramid the katas implicitly built:

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

**The pyramid only inverts when there's nothing pure to test.** The
non-DDD shape (logic spread across HTTP handlers, ORM callbacks, DB
triggers) forces all tests to the top because there's no clean
domain layer to test independently. DDD's testing payoff is that
the bottom of the pyramid actually exists.

Property-based testing belongs at the bottom: smart constructors and
state-transition methods are perfect property targets. ("For all
non-empty strings, `email.new` either succeeds or returns a typed
error.")

---

## Composition root in production

The `main.gleam` from kata 8 was the minimum. A real production
composition root does more:

```gleam
pub fn main() {
  // 1. Read configuration from env vars — at the top, exactly once
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

A few things to internalize:

- **All configuration enters at the top.** `config.from_env()` is the
  *one* place env vars are read. Everything else takes typed config
  values. No `env.get("DATABASE_URL")` scattered around — that
  pattern always rots.
- **Resources have known lifetimes.** The DB connection lives for the
  process lifetime; tests open their own. There's no "lazy
  connection pool that auto-initializes on first use" — that
  pattern reliably produces "works locally, breaks in production"
  bugs.
- **Failure to initialize crashes the boot.** `let assert Ok(...)`
  for each adapter. If the DB can't open, the process exits *now*,
  not three minutes from now when the first request fails.
- **Supervision (when you need it) wraps the whole thing.** For
  long-running apps with multiple actors (event bus, scheduler,
  background jobs), the composition root constructs a supervisor
  and starts it. For simple HTTP servers, Mist supervises itself
  and you don't need to.
- **The composition root is the only file with `let assert Ok(...)`
  on adapter construction.** Below it, everything takes already-
  constructed values. No layer of indirection exists to "lazily
  initialize" anything.

---

## Talking to non-DDD colleagues

Most engineers haven't read Evans. You'll be tempted to say "the
aggregate's invariant requires that the bounded context emit a
domain event so the anti-corruption layer can translate it" and
watch their eyes glaze.

Translate down:

| DDD term | Plain version |
|---|---|
| Aggregate | "The cluster of stuff that has to be saved together" |
| Aggregate root | "The thing the rest of the code talks to" |
| Invariant | "A rule we always want to be true" |
| Bounded context | "The slice of the system this team owns" |
| Value object | "A type that's just its data, like a number" |
| Entity | "Something with an ID — same person across renames" |
| Repository | "How we load and save the X" |
| Domain event | "Something that happened, that other parts care about" |
| Use case | "The thing one button does" |
| Smart constructor | "The function that makes a valid one" |
| Anti-corruption layer | "The translator between us and the other team's API" |
| Ports and adapters | "The implementation is plugged into an interface" |
| Ubiquitous language | "We use the same words the business uses" |

Use the jargon when it makes the conversation *shorter*. Use the plain
version when it makes the conversation *clearer*. They are different
tools for different audiences. **The point is the system, not the
vocabulary**.

---

## What's beyond the foundation

The katas covered the load-bearing patterns. Five more areas worth
knowing about, roughly in the order they show up in real systems:

### 1. Event sourcing
Storing the event log and *deriving* current state by replaying it.
The log becomes the source of truth; aggregate state is a
projection. Free audit log; "what was this customer's state on June
14?" becomes a query.

When to reach: high audit/compliance demand, complex history the
team needs to reason about, "how did we get into this state?" as a
recurring debugging question.

When to skip: most CRUD apps. The complexity overhead is real and
permanent.

### 2. CQRS — Command/Query Responsibility Segregation
Separate models for writes (commands) and reads (queries). Aggregates
handle commands; denormalized projections handle reads.

When to reach: read-heavy apps where the aggregate shape isn't the
right query shape; cross-aggregate reports; materialized views.

When to skip: writes and reads use roughly the same shape.

### 3. Sagas / Process Managers
Coordinated multi-step workflows that span aggregates or services.
"Place order → reserve inventory → charge card → ship → email
receipt." Each step is a use case; the saga handles ordering,
retry, and compensation when a step fails.

When to reach: real multi-aggregate workflows, especially across
service boundaries; need for explicit compensation logic.

When to skip: workflows that fit in a single transaction.

### 4. Distributed event delivery
Moving from in-process function calls to a message broker (Kafka,
NATS, RabbitMQ) or BEAM distribution. **Aggregate code stays
identical**; only the wiring at the composition root changes —
publish to broker instead of calling handler functions directly.

When to reach: services in different processes/data centers; need
for at-least-once delivery, retries, dead-letter queues; consumers
that should be independently restartable.

When to skip: monolith, or any case where a synchronous in-process
function call is fine.

### 5. Anti-corruption layers in earnest
Real adapters between your domain and a system whose model you don't
control. The ACL translates *their* vocabulary into *yours*, so the
rest of your code only ever sees your types.

When to reach: integrating with a system you don't own and can't
change; multiple teams whose APIs evolve independently of you.

When to skip: small project, single team, all code under your
control.

Each of these is its own book. The kata progression is the foundation
that makes them readable.

---

## A few patterns that the book skipped on purpose

Worth flagging because you'll see them and wonder:

- **Domain Services** — operations that don't naturally belong on any
  one entity. ("Transfer money from account A to account B" — neither
  account "owns" the transfer.) Idiomatic Gleam: just a top-level
  function that takes both. The "Service" object pattern is OO baggage.
- **Specifications** — composable query objects ("active
  customers in California with last order > $100"). Useful in OO
  languages where queries are objects; in Gleam, just write functions
  that compose with `|>`.
- **Factories as classes** — Gleam's smart constructors are factories.
  No additional ceremony needed.
- **Layered architecture as packages** — `application/`, `domain/`,
  `infrastructure/`. Often correct in spirit, often expensive in
  practice. Start flat; let real coupling pressure suggest the split.

---

## A few things that aren't DDD but pair well with it

- **Property-based testing** for smart constructors and pure domain
  functions. `gleam_qcheck` or similar.
- **Snapshot testing** for stable JSON outputs (HTTP responses,
  events). Catches accidental shape changes.
- **Schema migrations** as ordered SQL files (`dbmate`, `sqitch`,
  `gorrion`). Plain SQL keeps you honest.
- **OpenTelemetry traces** through the use case → handler → adapter
  call graph. The DDD layering makes the trace structure honest.
- **Static dependency-graph linting** to catch the moment when
  Ordering accidentally imports something from Shipping.

---

## A short closing

You now have:

- The vocabulary
- The patterns, in idiomatic Gleam
- The judgment about when to use them and when to wait
- The Gleam-specific tricks that keep each pattern small (records of
  functions over interface hierarchies, smart constructors over
  Factory classes, closures over DI containers, modules over
  multi-package layouts)

The thing this book can't give you is the muscle memory. That comes
from doing it on a real project, hitting the friction, deciding to
introduce or remove a pattern, watching the result, and updating
your mental model.

Pick something small. Build it with these tools. You'll discover that
80% of what you needed was already in the first four chapters, and
the rest of the toolkit sits in the back of your mind, waiting for
the specific problem that justifies it.

That's the whole game.

Go ship something.
