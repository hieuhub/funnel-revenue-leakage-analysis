# Funnel Definition

## Primary Funnel

1. View Item
2. Add to Cart
3. Begin Checkout
4. Purchase

Event mapping:

| Funnel Step | GA4 Event |
|---|---|
| View Item | view_item |
| Add to Cart | add_to_cart |
| Begin Checkout | begin_checkout |
| Purchase | purchase |

## Checkout Friction Funnel

Measuring where users drop off after starting checkout:

1. Begin Checkout
2. Add Shipping Info
3. Add Payment Info
4. Purchase

Event mapping:

| Funnel Step | GA4 Event |
|---|---|
| Begin Checkout | begin_checkout |
| Add Shipping Info | add_shipping_info |
| Add Payment Info | add_payment_info |
| Purchase | purchase |

## Logic

Calculating both: 

- User-level funnel conversion
- Session-level funnel conversion