# Full state-machine workout. Four customers, four trajectories
# through the aggregate's state space, plus a final population check.
#
# Run against a fresh in-memory server (or with a unique ORDER_DB
# under SQLite) so the population assertion at the end isn't fighting
# pre-existing rows:
#
#   PORT=9099 gleam run &
#   hurl --test --variable host=http://127.0.0.1:9099 \
#        --variables-file dev/hurl/vars.env dev/hurl/workout.hurl

# ---------------------------------------------------------------- #
# Customer A — happy path                                          #
# ---------------------------------------------------------------- #

POST {{host}}/orders?order_id=ORD-A&customer_id=CUST-A
HTTP 201

POST {{host}}/orders/ORD-A/lines?sku=WIDGET&quantity=3&amount=2500&currency=USD
HTTP 204

POST {{host}}/orders/ORD-A/lines?sku=GADGET&quantity=2&amount=4000&currency=USD
HTTP 204

GET {{host}}/orders/ORD-A
HTTP 200
[Asserts]
jsonpath "$.id" == "ORD-A"
jsonpath "$.customer_id" == "CUST-A"
jsonpath "$.status" == "draft"
jsonpath "$.lines" count == 2
# add_line prepends, so insertion order isn't response order — assert
# membership rather than indexed positions.
jsonpath "$.lines[*].sku" contains "WIDGET"
jsonpath "$.lines[*].sku" contains "GADGET"

POST {{host}}/orders/ORD-A/place
HTTP 200

GET {{host}}/orders/ORD-A
HTTP 200
[Asserts]
jsonpath "$.status" == "placed"
jsonpath "$.lines" count == 2

# Re-placing the placed order = 409 (CannotModifyPlacedOrder)
POST {{host}}/orders/ORD-A/place
HTTP 409

# ---------------------------------------------------------------- #
# Customer B — currency mismatch on second line                    #
# ---------------------------------------------------------------- #

POST {{host}}/orders?order_id=ORD-B&customer_id=CUST-B
HTTP 201

POST {{host}}/orders/ORD-B/lines?sku=USD-THING&quantity=1&amount=1000&currency=USD
HTTP 204

# Second line is EUR, but the order already has USD lines.
# Domain emits CurrencyMismatch, boundary translates to 422.
POST {{host}}/orders/ORD-B/lines?sku=EUR-THING&quantity=1&amount=1000&currency=EUR
HTTP 422

# The order is still in a coherent draft state with one line.
GET {{host}}/orders/ORD-B
HTTP 200
[Asserts]
jsonpath "$.status" == "draft"
jsonpath "$.lines" count == 1
jsonpath "$.lines[0].sku" == "USD-THING"

# ---------------------------------------------------------------- #
# Customer C — empty place                                         #
# ---------------------------------------------------------------- #

POST {{host}}/orders?order_id=ORD-C&customer_id=CUST-C
HTTP 201

# CannotPlaceEmptyOrder → 422
POST {{host}}/orders/ORD-C/place
HTTP 422

GET {{host}}/orders/ORD-C
HTTP 200
[Asserts]
jsonpath "$.status" == "draft"
jsonpath "$.lines" count == 0

# ---------------------------------------------------------------- #
# Customer D — modify after place                                  #
# ---------------------------------------------------------------- #

POST {{host}}/orders?order_id=ORD-D&customer_id=CUST-D
HTTP 201

POST {{host}}/orders/ORD-D/lines?sku=ITEM&quantity=1&amount=500&currency=USD
HTTP 204

POST {{host}}/orders/ORD-D/place
HTTP 200

# CannotModifyPlacedOrder on add_line → 409
POST {{host}}/orders/ORD-D/lines?sku=LATE-COMER&quantity=1&amount=100&currency=USD
HTTP 409

GET {{host}}/orders/ORD-D
HTTP 200
[Asserts]
jsonpath "$.status" == "placed"
jsonpath "$.lines" count == 1
jsonpath "$.lines[0].sku" == "ITEM"

# ---------------------------------------------------------------- #
# Final population check — exactly four orders                     #
# ---------------------------------------------------------------- #

GET {{host}}/orders
HTTP 200
[Asserts]
jsonpath "$" count == 4
