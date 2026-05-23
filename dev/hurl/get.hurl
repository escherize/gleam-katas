# Fetch one order by id.
#
# GET /orders/:id
# 200 OK  { ... full order shape ... }
# 400 Bad Request  invalid id
# 404 Not Found    no such order

GET {{host}}/orders/{{order_id}}
HTTP 200
[Asserts]
jsonpath "$.id" exists
