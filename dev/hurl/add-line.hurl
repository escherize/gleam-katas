# Add a line to a draft order.
#
# POST /orders/:id/lines?sku=...&quantity=...&amount=...&currency=...
# 204 No Content   line accepted
# 400 Bad Request  invalid id / currency / non-int quantity or amount
# 409 / 422        domain rule violation (placed order, currency mismatch, ...)

POST {{host}}/orders/{{order_id}}/lines?sku={{sku}}&quantity={{quantity}}&amount={{amount}}&currency={{currency}}
HTTP 204
