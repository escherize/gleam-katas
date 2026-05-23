# Negative paths the boundary translates.
#
# Each request below probes a specific error variant the use case can
# emit, so the HTTP mapping in src/web/place_order_handler.gleam stays
# honest as the domain evolves.

# 404: unknown order id
POST {{host}}/orders/NO-SUCH-ORDER/place
HTTP 404

# 404: unknown order on read
GET {{host}}/orders/NO-SUCH-ORDER
HTTP 404

# 404: route the router doesn't know
PUT {{host}}/orders/anything
HTTP 404

# 422: place an empty order
POST {{host}}/orders?order_id=EMPTY-ORDER&customer_id=CUST-X
HTTP 201
POST {{host}}/orders/EMPTY-ORDER/place
HTTP 422
