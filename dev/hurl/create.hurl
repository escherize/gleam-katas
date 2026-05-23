# Create a fresh draft order.
#
# POST /orders?order_id=...&customer_id=...
# 201 Created  { "order_id": "..." }
# 400 Bad Request  invalid order_id or customer_id

POST {{host}}/orders?order_id={{order_id}}&customer_id={{customer_id}}
HTTP 201
[Asserts]
jsonpath "$.order_id" == "{{order_id}}"
