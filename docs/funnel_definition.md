# Funnel Definition

## Primary Funnel

The primary funnel measures the main e-commerce journey:

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

The checkout friction funnel measures where users drop off after starting checkout:

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

## Planned Measurement Logic

This project will calculate both:

- User-level funnel conversion
- Session-level funnel conversion

Raw event counts will not be used as final conversion metrics because a single user or session can trigger the same event multiple times.