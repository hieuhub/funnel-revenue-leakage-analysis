/*
Purpose:Create a summary table from the intermediate user-level, session-level, and checkout funnel models.

One row per funnel type and funnel step.
Note: For reporting. 

- Output Example:
User-Level Main Funnel | View Item | 61,252 users | 100%
User-Level Main Funnel | Add to Cart | 12,538 users | 20.5%
*/

CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.mart_funnel_summary` AS

WITH funnel_counts AS (

  -- User-level main funnel.
  -- Measures whether users eventually moved through the ordered funnel.
  SELECT
    'User-Level Main Funnel' AS funnel_type,
    'Users' AS unit_type,
    1 AS step_order,
    'View Item' AS funnel_step,
    SUM(viewed_item) AS reached_count
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_user_funnel_steps`

  UNION ALL

  SELECT
    'User-Level Main Funnel',
    'Users',
    2,
    'Add to Cart',
    SUM(added_to_cart)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_user_funnel_steps`

  UNION ALL

  SELECT
    'User-Level Main Funnel',
    'Users',
    3,
    'Begin Checkout',
    SUM(began_checkout)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_user_funnel_steps`

  UNION ALL

  SELECT
    'User-Level Main Funnel',
    'Users',
    4,
    'Purchase',
    SUM(purchased)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_user_funnel_steps`


  UNION ALL


  -- Session-level main funnel.
  -- Measures whether sessions completed the ordered funnel in one visit.
  SELECT
    'Session-Level Main Funnel' AS funnel_type,
    'Sessions' AS unit_type,
    1 AS step_order,
    'View Item' AS funnel_step,
    SUM(viewed_item) AS reached_count
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_session_funnel_steps`

  UNION ALL

  SELECT
    'Session-Level Main Funnel',
    'Sessions',
    2,
    'Add to Cart',
    SUM(added_to_cart)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_session_funnel_steps`

  UNION ALL

  SELECT
    'Session-Level Main Funnel',
    'Sessions',
    3,
    'Begin Checkout',
    SUM(began_checkout)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_session_funnel_steps`

  UNION ALL

  SELECT
    'Session-Level Main Funnel',
    'Sessions',
    4,
    'Purchase',
    SUM(purchased)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_session_funnel_steps`


  UNION ALL


  -- Checkout friction funnel.
  -- Measures where sessions drop off after checkout starts.
  SELECT
    'Checkout Friction Funnel' AS funnel_type,
    'Sessions' AS unit_type,
    1 AS step_order,
    'Begin Checkout' AS funnel_step,
    SUM(began_checkout) AS reached_count
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_checkout_funnel_steps`

  UNION ALL

  SELECT
    'Checkout Friction Funnel',
    'Sessions',
    2,
    'Add Shipping Info',
    SUM(added_shipping_info)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_checkout_funnel_steps`

  UNION ALL

  SELECT
    'Checkout Friction Funnel',
    'Sessions',
    3,
    'Add Payment Info',
    SUM(added_payment_info)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_checkout_funnel_steps`

  UNION ALL

  SELECT
    'Checkout Friction Funnel',
    'Sessions',
    4,
    'Purchase',
    SUM(purchased)
  FROM
    `funnel-analysis-project-499019.funnel_analysis.int_checkout_funnel_steps`
),


with_previous_steps AS (
  -- Add previous-step and first-step counts.
  -- These are needed to calculate step conversion, drop-off, and overall conversion.
  SELECT
    funnel_type,
    unit_type,
    step_order,
    funnel_step,
    reached_count,

    LAG(reached_count) OVER (
      PARTITION BY funnel_type
      ORDER BY step_order
    ) AS previous_step_count,

    FIRST_VALUE(reached_count) OVER (
      PARTITION BY funnel_type
      ORDER BY step_order
    ) AS first_step_count

  FROM
    funnel_counts
)


SELECT
  funnel_type,
  unit_type,
  step_order,
  funnel_step,
  reached_count,
  previous_step_count,

  -- Step conversion compares each step to the step before it.
  -- Example: Add to Cart / View Item.
  CASE
    WHEN step_order = 1 THEN 1.0
    ELSE SAFE_DIVIDE(reached_count, previous_step_count)
  END AS step_conversion_rate,

  -- Overall conversion compares each step to the first funnel step.
  -- Example: Purchase / View Item.
  SAFE_DIVIDE(reached_count, first_step_count) AS overall_conversion_rate,

  -- Drop-off count shows how many users/sessions were lost from the prior step.
  CASE
    WHEN step_order = 1 THEN 0
    ELSE previous_step_count - reached_count
  END AS dropoff_count,

  -- Drop-off rate shows the percentage lost from the prior step.
  CASE
    WHEN step_order = 1 THEN 0.0
    ELSE 1 - SAFE_DIVIDE(reached_count, previous_step_count)
  END AS dropoff_rate

FROM
  with_previous_steps
ORDER BY
  funnel_type,
  step_order;