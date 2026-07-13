/*
This file creates a clean item-level staging view from the raw dataset

One row per item within a GA4 event.

Note:
- GA4 stores product data inside the nested/repeated items array.
- This view flattens item records so we can analyze funnel behavior by product category, item name, item price, quantity, and item revenue.
*/

CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.stg_items` AS

SELECT
  -- Event date and timestamp for time-based analysis.
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  TIMESTAMP_MICROS(event_timestamp) AS event_time,
  event_timestamp,

  -- Core event and user/session fields.
  event_name,
  user_pseudo_id,

  -- Extract session ID from nested event parameters.
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
    LIMIT 1
  ) AS ga_session_id,

  -- Create a unique session key using user + session ID.
  CONCAT(
    user_pseudo_id,
    '-',
    CAST((
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
      LIMIT 1
    ) AS STRING)
  ) AS session_key,

  -- Product fields from the unnested items array.
  item.item_id,
  item.item_name,
  item.item_brand,
  item.item_category AS raw_item_category,
  item.price,
  item.quantity,
  item.item_revenue,

  -- Clean category grouping for dashboard analysis from raw sets.
  CASE
    WHEN LOWER(item.item_category) LIKE '%apparel%'
      OR LOWER(item.item_category) LIKE "%men%"
      OR LOWER(item.item_category) LIKE "%women%"
      THEN 'Apparel'

    WHEN LOWER(item.item_category) LIKE '%drinkware%'
      THEN 'Drinkware'

    WHEN LOWER(item.item_category) LIKE '%bags%'
      THEN 'Bags'

    WHEN LOWER(item.item_category) LIKE '%stationery%'
      THEN 'Stationery'

    WHEN LOWER(item.item_category) LIKE '%sale%'
      THEN 'Sale'

    WHEN item.item_category IS NULL
      OR TRIM(item.item_category) = ''
      THEN 'Unknown'

    ELSE 'Other'
  END AS cleaned_item_category

FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item

-- Keep the same analysis window as stg_events.
WHERE
  _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';









