# dev/hurl

Hurl scripts for exercising the running server over HTTP.

## One-time install

```sh
brew install hurl       # macOS
# or: cargo install hurl
```

Verify with `hurl --version`. Anything 4.x or newer fits.

## Start the server

```sh
gleam run                            # in-memory repo on :8080
ORDER_REPO=sqlite gleam run          # SQLite-backed
PORT=9001 gleam run                  # custom port
```

## Kick the tires

The five single-endpoint files (`create.hurl`, `get.hurl`,
`add-line.hurl`, `place.hurl`, `list.hurl`) each fire one request and
assert the success path:

```sh
hurl --variables-file dev/hurl/vars.env dev/hurl/create.hurl
hurl --variables-file dev/hurl/vars.env dev/hurl/get.hurl
```

Add `--include` to print full request/response headers and body,
useful for the first run:

```sh
hurl --include --variables-file dev/hurl/vars.env dev/hurl/get.hurl
```

Override a variable from the shell:

```sh
hurl --variables-file dev/hurl/vars.env \
     --variable order_id=ORDER-42 \
     dev/hurl/get.hurl
```

## Run the full scenario

`flow.hurl` chains create → add lines → place → read → re-place
(expected 409). Re-runs need a fresh `order_id` or a freshly-started
server:

```sh
hurl --test \
     --variables-file dev/hurl/vars.env \
     --variable order_id=ORDER-$(date +%s) \
     dev/hurl/flow.hurl
```

`--test` mode suppresses request/response output and reports
pass/fail per file, the shape you want in CI.

## Probe the error paths

```sh
hurl --test --variables-file dev/hurl/vars.env dev/hurl/errors.hurl
```

`errors.hurl` walks the 400/404/422 branches the HTTP boundary
translates. If one starts failing, either a use-case error variant
moved or the handler's `case` arm drifted out of sync.

## Run everything

```sh
hurl --test \
     --variables-file dev/hurl/vars.env \
     --variable order_id=ORDER-$(date +%s) \
     dev/hurl/*.hurl
```

Hurl runs each file in order, reports a pass/fail summary, and exits
non-zero on the first failure. That's the contract a CI step wants.

## The full workout

`workout.hurl` walks the aggregate's state machine across four
customers: happy path, currency mismatch, empty-place rejection, and
modify-after-place. It asserts on the JSON body of `GET /orders/:id`
(status, line count, SKU membership) and finishes by asserting that
the repo holds exactly four orders.

```sh
PORT=9099 gleam run &                                  # fresh in-memory
hurl --test --variable host=http://127.0.0.1:9099 \
     --variables-file dev/hurl/vars.env \
     dev/hurl/workout.hurl
```

Twenty requests, rich asserts, end-to-end domain coverage. Start
from a fresh server (or unique SQLite path) so the final population
check doesn't fight pre-existing rows.

## Pool party

`pool-party.sh` fires N copies of `flow.hurl` in parallel via `xargs -P`,
each with a unique `order_id`. It's the cheapest way to confirm the
OTP actor serializes correctly under concurrent load: every flow
runs six sequential requests, and if the actor ever interleaves them
across order_ids the 409-on-re-place assertion at the end of
`flow.hurl` blows up.

```sh
PORT=9099 gleam run &
HOST=http://127.0.0.1:9099 dev/hurl/pool-party.sh 200 32
```

Args: `dev/hurl/pool-party.sh [count=20] [parallel=8]`.

On a laptop, 200 flows / 32 in flight clears in about a second
(~1200 req/s sustained, ~200 orders in the repo at the end).

