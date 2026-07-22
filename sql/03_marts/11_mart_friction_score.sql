/*
- This creates a prioritization mart data for Visualization that ranks funnel
  transitions by business friction.

- One row per funnel type and funnel transition.

- Using file: mart_revenue_leakage

Note:
- This is like a prioritization metric that will help business
  stakeholders identify which funnel problems deserve attention first.
- All the previous files only describe and analysis where users drop off.
- This helps prioritize which issues matter most for business actions.

- Logic:
  friction_score = 65% normalized estimated revenue leakage + 35% drop-off rate
=====================================================================
*/


CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.mart_friction_score` AS

WITH base_leakage AS (
  -- Start from the revenue leakage mart.
  -- This model already contains funnel transition, drop-off, conversion, and estimated revenue opportunity metrics.
  SELECT
    funnel_type,
    unit_type,
    step_order,
    previous_funnel_step,
    current_funnel_step,
    funnel_transition,

    previous_step_count,
    reached_count,
    dropoff_count,
    dropoff_rate,
    step_conversion_rate,
    overall_conversion_rate,

    average_order_value,
    estimated_revenue_leakage,
    leakage_priority
  FROM
    `funnel-analysis-project-499019.funnel_analysis.mart_revenue_leakage`
),


normalized_metrics AS (
  -- Normalize estimated revenue leakage so the largest leakage value becomes 1.
  -- This helps combine revenue impact and drop-off rate into one score.
  SELECT
    *,

    SAFE_DIVIDE(
      estimated_revenue_leakage,
      MAX(estimated_revenue_leakage) OVER ()
    ) AS normalized_revenue_leakage

  FROM
    base_leakage
),


scored_transitions AS (
  -- Create a transparent friction score.
  -- Revenue leakage gets more weight because it captures business impact.
  -- Drop-off rate gets secondary weight because it captures how severe the damage is.
  SELECT
    *,

    ROUND(
      (
        0.65 * normalized_revenue_leakage
        + 0.35 * dropoff_rate
      ) * 100,
      2
    ) AS friction_score

  FROM
    normalized_metrics
)


SELECT
  funnel_type,
  unit_type,
  step_order,
  previous_funnel_step,
  current_funnel_step,
  funnel_transition,

  previous_step_count,
  reached_count,
  dropoff_count,
  dropoff_rate,
  step_conversion_rate,
  overall_conversion_rate,

  average_order_value,
  estimated_revenue_leakage,
  normalized_revenue_leakage,

  friction_score,

  -- Rank transitions by final friction score.
  DENSE_RANK() OVER (
    ORDER BY friction_score DESC
  ) AS overall_friction_rank,

  -- Rank transitions within each funnel type.
  DENSE_RANK() OVER (
    PARTITION BY funnel_type
    ORDER BY friction_score DESC
  ) AS friction_rank_within_funnel,

  -- Priority tier for dashboard filtering.
  CASE
    WHEN friction_score >= 75 THEN 'Critical'
    WHEN friction_score >= 50 THEN 'High'
    WHEN friction_score >= 25 THEN 'Medium'
    ELSE 'Low'
  END AS friction_priority,

  -- Readable interpretation for the dashboard.
  CASE
    WHEN funnel_transition LIKE '%View Item → Add to Cart%'
      THEN 'Product page / merchandising friction'

    WHEN funnel_transition LIKE '%Add to Cart → Begin Checkout%'
      THEN 'Cart-to-checkout friction'

    WHEN funnel_transition LIKE '%Begin Checkout → Add Shipping Info%'
      THEN 'Checkout start / shipping friction'

    WHEN funnel_transition LIKE '%Add Shipping Info → Add Payment Info%'
      THEN 'Shipping-to-payment friction'

    WHEN funnel_transition LIKE '%Add Payment Info → Purchase%'
      THEN 'Payment confirmation friction'

    WHEN funnel_transition LIKE '%Begin Checkout → Purchase%'
      THEN 'Checkout completion friction'

    ELSE 'General funnel friction'
  END AS likely_business_issue,

  -- Recommendations.
  CASE
    WHEN funnel_transition LIKE '%View Item → Add to Cart%'
      THEN 'Review product detail pages, pricing, product relevance, and add-to-cart UX.'

    WHEN funnel_transition LIKE '%Add to Cart → Begin Checkout%'
      THEN 'Review cart page clarity, shipping expectations, discounts, and checkout CTA visibility.'

    WHEN funnel_transition LIKE '%Begin Checkout → Add Shipping Info%'
      THEN 'Review checkout start flow, login requirements, form friction, and shipping cost visibility.'

    WHEN funnel_transition LIKE '%Add Shipping Info → Add Payment Info%'
      THEN 'Review shipping options, delivery costs, and transition from shipping to payment.'

    WHEN funnel_transition LIKE '%Add Payment Info → Purchase%'
      THEN 'Review payment errors, payment method support, trust signals, and final confirmation UX.'

    WHEN funnel_transition LIKE '%Begin Checkout → Purchase%'
      THEN 'Review end-to-end checkout completion barriers.'

    ELSE 'Investigate funnel step behavior and segment-level drivers.'
  END AS recommended_investigation

FROM
  scored_transitions;