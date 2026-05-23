#!/usr/bin/env bash
# Fire N copies of the full create→lines→place flow in parallel.
# Each invocation uses a unique order_id so the flows don't collide.
#
# Usage:
#   dev/hurl/pool-party.sh                  # 20 flows, 8 in flight, against localhost:9099
#   dev/hurl/pool-party.sh 100              # 100 flows, 8 in flight
#   dev/hurl/pool-party.sh 100 16           # 100 flows, 16 in flight
#   HOST=http://127.0.0.1:8080 ./pool-party.sh 50
#
# Each successful flow proves: create → 2× add line → place → read →
# re-place 409. So success = the actor served six ordered requests
# for that order_id without dropping or interleaving them across IDs.

set -euo pipefail

count=${1:-20}
parallel=${2:-8}
host=${HOST:-http://127.0.0.1:9099}

here=$(cd "$(dirname "$0")" && pwd)

# Sanity-check the server is up before we spawn the pool.
if ! curl -fsS "$host/orders" >/dev/null 2>&1; then
  echo "no server at $host (start one with: gleam run)" >&2
  exit 2
fi

echo "pool party: $count flows, $parallel in flight, against $host"
start=$(date +%s)

# Fire one hurl-test per id, throttled to $parallel in flight via xargs -P.
# Each invocation gets its own ORDER_ID; flow.hurl runs the six-request
# scenario for that id.
seq 1 "$count" | xargs -n1 -P"$parallel" -I{} bash -c '
  id="POOL-$(date +%s)-{}-$RANDOM"
  hurl --test \
       --variable host='"$host"' \
       --variables-file '"$here"'/vars.env \
       --variable order_id="$id" \
       '"$here"'/flow.hurl >/dev/null 2>&1 \
    && echo "ok  $id" \
    || echo "FAIL $id"
'

elapsed=$(( $(date +%s) - start ))
total_orders=$(curl -fsS "$host/orders" | tr ',' '\n' | grep -c '"id"' || true)

echo
echo "elapsed: ${elapsed}s"
echo "orders in repo after run: $total_orders"
