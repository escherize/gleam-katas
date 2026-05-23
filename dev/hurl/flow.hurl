# End-to-end scenario.
#
# Creates an order, adds two lines, places it, reads it back, then
# proves the aggregate's idempotency: re-placing the same order gives
# 409 Conflict.
#
# Re-run with a fresh order_id (or restart the in-memory server)
# before each invocation:
#
#   hurl --variables-file dev/hurl/vars.env \
#        --variable order_id=ORDER-$(date +%s) \
#        --test dev/hurl/flow.hurl

# 1. create
POST {{host}}/orders?order_id={{order_id}}&customer_id={{customer_id}}
HTTP 201
[Asserts]
jsonpath "$.order_id" == "{{order_id}}"

# 2. add two lines
POST {{host}}/orders/{{order_id}}/lines?sku=WIDGET&quantity=2&amount=5000&currency=USD
HTTP 204

POST {{host}}/orders/{{order_id}}/lines?sku=GADGET&quantity=1&amount=10000&currency=USD
HTTP 204

# 3. place
POST {{host}}/orders/{{order_id}}/place
HTTP 200

# 4. read it back
GET {{host}}/orders/{{order_id}}
HTTP 200

# 5. re-placing the same order is a 409
POST {{host}}/orders/{{order_id}}/place
HTTP 409
