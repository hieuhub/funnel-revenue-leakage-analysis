/* This file builds a user-level ordered ecommerce funnel from GA4 events.

- One row per user who viewed at least one item.

- Funnel Logic: an user must complete each step after the previous step:
        + view_item -> add_to_cart -> begin_checkout -> purchase
Note:
- Raw event counts are not clean and correct most of the time because users
can trigger the same event multiple times. This model calculates 
ordered user progression through the funnel.
*/

CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.int_user_funnel_steps` AS

WITH funnel_events AS (
  -- Keeping only the events needed for the primary funnel.
  SELECT
    user_pseudo_id,
    event_name,
    event_time
  FROM
    `funnel-analysis-project-499019.funnel_analysis.stg_events`
  WHERE
    event_name IN (
      'view_item',
      'add_to_cart',
      'begin_checkout',
      'purchase'
    )
    AND user_pseudo_id IS NOT NULL
),


first_view AS (
  -- First time each user viewed a product aka entry point into the funnel.
  SELECT
    user_pseudo_id,
    MIN(event_time) AS view_item_time
  FROM
    funnel_events
  WHERE
    event_name = 'view_item'
  GROUP BY
    user_pseudo_id
),


first_cart_after_view AS (
  -- First add_to_cart event after the user's first product view.
  SELECT
    e.user_pseudo_id,
    MIN(e.event_time) AS add_to_cart_time
  FROM
    funnel_events e
  INNER JOIN
    first_view v
      ON e.user_pseudo_id = v.user_pseudo_id
  WHERE
    e.event_name = 'add_to_cart'
    AND e.event_time >= v.view_item_time
  GROUP BY
    e.user_pseudo_id
),


first_checkout_after_cart AS (
  -- First begin_checkout event after the user's first valid cart event.
  SELECT
    e.user_pseudo_id,
    MIN(e.event_time) AS begin_checkout_time
  FROM
    funnel_events e
  INNER JOIN
    first_cart_after_view c
      ON e.user_pseudo_id = c.user_pseudo_id
  WHERE
    e.event_name = 'begin_checkout'
    AND e.event_time >= c.add_to_cart_time
  GROUP BY
    e.user_pseudo_id
),


first_purchase_after_checkout AS (
  -- First purchase event after the user's first valid checkout event.
  SELECT
    e.user_pseudo_id,
    MIN(e.event_time) AS purchase_time
  FROM
    funnel_events e
  INNER JOIN
    first_checkout_after_cart b
      ON e.user_pseudo_id = b.user_pseudo_id
  WHERE
    e.event_name = 'purchase'
    AND e.event_time >= b.begin_checkout_time
  GROUP BY
    e.user_pseudo_id
)


SELECT
  v.user_pseudo_id,

  -- Timestamp of each user's first valid funnel step.
  v.view_item_time,
  c.add_to_cart_time,
  b.begin_checkout_time,
  p.purchase_time,

  -- Binary flags make later aggregation easier.
  1 AS viewed_item,
  CASE WHEN c.add_to_cart_time IS NOT NULL THEN 1 ELSE 0 END AS added_to_cart,
  CASE WHEN b.begin_checkout_time IS NOT NULL THEN 1 ELSE 0 END AS began_checkout,
  CASE WHEN p.purchase_time IS NOT NULL THEN 1 ELSE 0 END AS purchased,

  -- Time from first product view to purchase.
  -- Null if the user did not complete the funnel.
  CASE
    WHEN p.purchase_time IS NOT NULL
      THEN TIMESTAMP_DIFF(p.purchase_time, v.view_item_time, MINUTE)
    ELSE NULL
  END AS minutes_from_view_to_purchase,

  -- User's final reached stage in the ordered funnel.
  CASE
    WHEN p.purchase_time IS NOT NULL THEN 'Purchased'
    WHEN b.begin_checkout_time IS NOT NULL THEN 'Dropped After Checkout'
    WHEN c.add_to_cart_time IS NOT NULL THEN 'Dropped After Cart'
    ELSE 'Dropped After Product View'
  END AS final_funnel_status

FROM
  first_view v

--Left joins so that it includes all users who entered the funnel, including those who dropped off.
LEFT JOIN
  first_cart_after_view c
    ON v.user_pseudo_id = c.user_pseudo_id
LEFT JOIN
  first_checkout_after_cart b
    ON v.user_pseudo_id = b.user_pseudo_id
LEFT JOIN
  first_purchase_after_checkout p
    ON v.user_pseudo_id = p.user_pseudo_id;