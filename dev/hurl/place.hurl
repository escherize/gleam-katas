# Finalize a draft order.
#
# POST /orders/:id/place
# 200 OK            { "order_id": "..." }
# 404 Not Found     no such order
# 409 Conflict      already placed
# 422 Unprocessable empty order, etc.
# 500               unexpected repo failure

POST {{host}}/orders/{{order_id}}/place
HTTP 200
[Asserts]
jsonpath "$.order_id" == "{{order_id}}"
