/*
- This file estimates potential revenue leakage by funnel transition using
drop-off counts and average order value.


- One row per funnel type and funnel transition.

- Using files:
  - mart_funnel_summary
  - stg_events

- Note:
  Revenue leakage here is an estimated number, not guaranteed
  lost revenue. It still helps to prioritize where funnel drop-offs may have
  the largest business impact.

- Formula I use: estimated_revenue_leakage = dropoff_count * average_order_value

*/


CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.mart_revenue_leakage` AS

WITH transaction_revenue AS (
  -- Creating one row per transaction to avoid overcounting revenue.
  -- The raw GA4 data can contain multiple purchase events for the same transaction_id, so we aggregate at the transaction level first.
  SELECT
    transaction_id,
    MAX(purchase_revenue) AS transaction_revenue
  FROM
    `funnel-analysis-project-499019.funnel_analysis.stg_events`
  WHERE
    event_name = 'purchase'
    AND transaction_id IS NOT NULL
    AND purchase_revenue IS NOT NULL
  GROUP BY
    transaction_id
),


revenue_baseline AS (
  -- Calculating average order value from deduplicated transactions.
  -- This is the baseline for estimated leakage calculations.
  SELECT
    COUNT(*) AS unique_transactions,
    SUM(transaction_revenue) AS total_purchase_revenue,
    AVG(transaction_revenue) AS average_order_value
  FROM
    transaction_revenue
),


funnel_transitions AS (
  -- Pull funnel transition metrics from the funnel summary mart.
  SELECT
    funnel_type,
    unit_type,
    step_order,

    LAG(funnel_step) OVER (
      PARTITION BY funnel_type
      ORDER BY step_order
    ) AS previous_funnel_step,

    funnel_step AS current_funnel_step,
    reached_count,
    previous_step_count,
    dropoff_count,
    dropoff_rate,
    step_conversion_rate,
    overall_conversion_rate
  FROM
    `funnel-analysis-project-499019.funnel_analysis.mart_funnel_summary`
),


leakage_estimates AS (
  -- Estimate potential revenue leakage for each funnel transition.
  -- Joining to revenue_baseline adds one global average order value to every funnel transition.
  SELECT
    t.funnel_type,
    t.unit_type,
    t.step_order,
    t.previous_funnel_step,
    t.current_funnel_step,
    CONCAT(t.previous_funnel_step, ' → ', t.current_funnel_step) AS funnel_transition,
    
    t.previous_step_count,
    t.reached_count,
    t.dropoff_count,
    t.dropoff_rate,
    t.step_conversion_rate,
    t.overall_conversion_rate,

    r.unique_transactions,
    r.total_purchase_revenue,
    r.average_order_value,

    -- Estimated opportunity from users/sessions lost at this step.
    t.dropoff_count * r.average_order_value AS estimated_revenue_leakage

  FROM
    funnel_transitions t
  JOIN
    revenue_baseline r
      ON TRUE
  WHERE
    t.step_order > 1
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

  unique_transactions,
  total_purchase_revenue,
  average_order_value,

  estimated_revenue_leakage,

  -- Rank the largest leakage opportunities within each funnel.
  DENSE_RANK() OVER (
    PARTITION BY funnel_type
    ORDER BY estimated_revenue_leakage DESC
  ) AS leakage_rank_within_funnel,

  -- Rank the largest leakage opportunities across all funnels.
  DENSE_RANK() OVER (
    ORDER BY estimated_revenue_leakage DESC
  ) AS overall_leakage_rank,

  -- priority label for dashboard filtering.
  CASE
    WHEN estimated_revenue_leakage >= 1000000 THEN 'Very High'
    WHEN estimated_revenue_leakage >= 500000 THEN 'High'
    WHEN estimated_revenue_leakage >= 100000 THEN 'Medium'
    ELSE 'Low'
  END AS leakage_priority

FROM
  leakage_estimates;

  