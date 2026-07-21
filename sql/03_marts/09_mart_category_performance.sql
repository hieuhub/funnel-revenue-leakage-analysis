/*
- This file creates a category performance mart that measures
ordered funnel conversion by cleaned product category.

- One row per cleaned_item_category.

- Note: This model uses a session-category grain internally. A single session
can appear in multiple categories if the user viewed products across
multiple categories.


** The overall funnel shows where users drop off.
This shows which product categories are associated with the
largest conversion gaps and revenue opportunities.

*/


CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.mart_category_performance` AS

WITH category_events AS (
  -- Keepinh only item-level ecommerce events needed for category funnel analysis.
  -- This uses stg_items because product/category fields live at the item level, not the event level.
  SELECT
    session_key,
    user_pseudo_id,
    event_name,
    event_time,
    cleaned_item_category,
    price,
    quantity,
    item_revenue
  FROM
    `funnel-analysis-project-499019.funnel_analysis.stg_items`
  WHERE
    event_name IN (
      'view_item',
      'add_to_cart',
      'begin_checkout',
      'purchase'
    )
    AND session_key IS NOT NULL
    AND cleaned_item_category IS NOT NULL
),


first_category_view AS (
  -- First time each session viewed a product in each category.
  -- This is the entry point for the category-level funnel.
  SELECT
    session_key,
    ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
    cleaned_item_category,
    MIN(event_time) AS view_item_time
  FROM
    category_events
  WHERE
    event_name = 'view_item'
  GROUP BY
    session_key,
    cleaned_item_category
),


first_cart_after_view AS (
  -- First add_to_cart event for the same category after the category view.
  -- Keeping the category funnel ordered and avoids counting cart events that happened before the category was viewed.
  SELECT
    e.session_key,
    e.cleaned_item_category,
    MIN(e.event_time) AS add_to_cart_time
  FROM
    category_events e
  INNER JOIN
    first_category_view v
      ON e.session_key = v.session_key
      AND e.cleaned_item_category = v.cleaned_item_category
  WHERE
    e.event_name = 'add_to_cart'
    AND e.event_time >= v.view_item_time
  GROUP BY
    e.session_key,
    e.cleaned_item_category
),


first_checkout_after_cart AS (
  -- First begin_checkout event for the same category after add_to_cart.
  SELECT
    e.session_key,
    e.cleaned_item_category,
    MIN(e.event_time) AS begin_checkout_time
  FROM
    category_events e
  INNER JOIN
    first_cart_after_view c
      ON e.session_key = c.session_key
      AND e.cleaned_item_category = c.cleaned_item_category
  WHERE
    e.event_name = 'begin_checkout'
    AND e.event_time >= c.add_to_cart_time
  GROUP BY
    e.session_key,
    e.cleaned_item_category
),


first_purchase_after_checkout AS (
  -- First purchase event for the same category after checkout.
  SELECT
    e.session_key,
    e.cleaned_item_category,
    MIN(e.event_time) AS purchase_time
  FROM
    category_events e
  INNER JOIN
    first_checkout_after_cart b
      ON e.session_key = b.session_key
      AND e.cleaned_item_category = b.cleaned_item_category
  WHERE
    e.event_name = 'purchase'
    AND e.event_time >= b.begin_checkout_time
  GROUP BY
    e.session_key,
    e.cleaned_item_category
),


category_session_funnel AS (
  -- Create one row per session-category with binary funnel flags.
  
  SELECT
    v.session_key,
    v.user_pseudo_id,
    v.cleaned_item_category,

    1 AS viewed_item,
    CASE WHEN c.add_to_cart_time IS NOT NULL THEN 1 ELSE 0 END AS added_to_cart,
    CASE WHEN b.begin_checkout_time IS NOT NULL THEN 1 ELSE 0 END AS began_checkout,
    CASE WHEN p.purchase_time IS NOT NULL THEN 1 ELSE 0 END AS purchased

  FROM
    first_category_view v
  LEFT JOIN
    first_cart_after_view c
      ON v.session_key = c.session_key
      AND v.cleaned_item_category = c.cleaned_item_category
  LEFT JOIN
    first_checkout_after_cart b
      ON v.session_key = b.session_key
      AND v.cleaned_item_category = b.cleaned_item_category
  LEFT JOIN
    first_purchase_after_checkout p
      ON v.session_key = p.session_key
      AND v.cleaned_item_category = p.cleaned_item_category
),


category_revenue AS (
  -- Calculate item-level purchase revenue by category.
  SELECT
    cleaned_item_category,
    SUM(COALESCE(item_revenue, price * quantity, 0)) AS total_item_revenue,
    COUNT(*) AS purchased_item_rows
  FROM
    category_events
  WHERE
    event_name = 'purchase'
  GROUP BY
    cleaned_item_category
),


category_summary AS (
  -- Aggregate the ordered session-category funnel to one row per category.
  SELECT
    cleaned_item_category,

    COUNT(DISTINCT session_key) AS category_view_sessions,
    COUNT(DISTINCT user_pseudo_id) AS category_view_users,

    SUM(viewed_item) AS viewed_item_sessions,
    SUM(added_to_cart) AS added_to_cart_sessions,
    SUM(began_checkout) AS began_checkout_sessions,
    SUM(purchased) AS purchased_sessions

  FROM
    category_session_funnel
  GROUP BY
    cleaned_item_category
)


SELECT
  s.cleaned_item_category,

  s.category_view_sessions,
  s.category_view_users,

  s.viewed_item_sessions,
  s.added_to_cart_sessions,
  s.began_checkout_sessions,
  s.purchased_sessions,

  -- Step conversion rates.
  SAFE_DIVIDE(s.added_to_cart_sessions, s.viewed_item_sessions) AS view_to_cart_rate,
  SAFE_DIVIDE(s.began_checkout_sessions, s.added_to_cart_sessions) AS cart_to_checkout_rate,
  SAFE_DIVIDE(s.purchased_sessions, s.began_checkout_sessions) AS checkout_to_purchase_rate,

  -- Overall category conversion rate.
  SAFE_DIVIDE(s.purchased_sessions, s.viewed_item_sessions) AS view_to_purchase_rate,

  -- Drop-off counts.
  s.viewed_item_sessions - s.added_to_cart_sessions AS view_to_cart_dropoff_count,
  s.added_to_cart_sessions - s.began_checkout_sessions AS cart_to_checkout_dropoff_count,
  s.began_checkout_sessions - s.purchased_sessions AS checkout_to_purchase_dropoff_count,

  -- Drop-off rates.
  1 - SAFE_DIVIDE(s.added_to_cart_sessions, s.viewed_item_sessions) AS view_to_cart_dropoff_rate,
  1 - SAFE_DIVIDE(s.began_checkout_sessions, s.added_to_cart_sessions) AS cart_to_checkout_dropoff_rate,
  1 - SAFE_DIVIDE(s.purchased_sessions, s.began_checkout_sessions) AS checkout_to_purchase_dropoff_rate,

  -- Revenue fields for business impact.
  COALESCE(r.total_item_revenue, 0) AS total_item_revenue,
  COALESCE(r.purchased_item_rows, 0) AS purchased_item_rows,
  SAFE_DIVIDE(COALESCE(r.total_item_revenue, 0), s.purchased_sessions) AS revenue_per_purchasing_session,

  -- flags to help with dashboard.
  CASE
    WHEN s.viewed_item_sessions >= 1000 THEN TRUE
    ELSE FALSE
  END AS is_high_volume_category,

  CASE
  WHEN s.cleaned_item_category IN ('Other', 'Unknown', 'Sale') THEN TRUE
  ELSE FALSE
END AS is_low_confidence_category

FROM
  category_summary s
LEFT JOIN
  category_revenue r
    ON s.cleaned_item_category = r.cleaned_item_category;