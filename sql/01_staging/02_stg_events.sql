/*
- This query creates a clean event-level staging view from the raw GA4 dataset.

- The raw dataset contains nested fields, null, missing values,... so this staging view extracts
the core fields needed for funnel analysis so later SQL models are easier to write.
*/


CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.stg_events` AS

SELECT
  -- Convert GA4 string date into a real DATE field.
  PARSE_DATE('%Y%m%d', event_date) AS event_date,

  -- Convert GA4 microsecond timestamp into a readable timestamp.
  TIMESTAMP_MICROS(event_timestamp) AS event_time,

  -- Keep original timestamp for event ordering.
  event_timestamp,

  -- Main user action, like view_item, add_to_cart, purchase,...
  event_name,

  -- Anonymous GA4 user id.
  user_pseudo_id,

  -- Extract session ID from GA4 event parameters.
  -- GA4 stores session ID inside the nested event_params array.
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
    LIMIT 1
  ) AS ga_session_id,

  -- Create a unique session key.
  -- ga_session_id alone is not enough because different users can have the same session number.
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

  -- Page URL where the event happened.
  -- For maybe product page analysis later.
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_location'
    LIMIT 1
  ) AS page_location,


  -- Device and platform fields.
  platform,
  LOWER(device.category) AS device_category,

  -- Traffic fields for channel/source performance analysis.
  LOWER(traffic_source.source) AS traffic_source,
  LOWER(traffic_source.medium) AS traffic_medium,
  LOWER(traffic_source.name) AS traffic_campaign,

  -- Traffic channel grouping for dashboard use.
  CASE
    WHEN LOWER(traffic_source.source) = 'google'
         AND LOWER(traffic_source.medium) = 'organic'
      THEN 'Google Organic'

    WHEN LOWER(traffic_source.source) = 'google'
         AND LOWER(traffic_source.medium) = 'cpc'
      THEN 'Google CPC'

    WHEN LOWER(traffic_source.source) = '(direct)'
         AND LOWER(traffic_source.medium) = '(none)'
      THEN 'Direct'

    WHEN LOWER(traffic_source.medium) = 'referral'
      THEN 'Referral'

    WHEN LOWER(traffic_source.source) = '(data deleted)'
         OR LOWER(traffic_source.medium) = '(data deleted)'
      THEN 'Data Deleted / Unknown'

    ELSE 'Other'
  END AS traffic_channel,

  -- Purchase fields, populated on purchase events.
  ecommerce.transaction_id,
  ecommerce.purchase_revenue

FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

-- Restrict to the dataset window.
WHERE
  _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';