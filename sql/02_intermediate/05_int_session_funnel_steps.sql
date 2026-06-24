/*
- This file builds a session-lvl ordered funnel from GA4 events.

- One row per session that views at least 1 item 

Logic: A session must complete each step after the previous one: 
view_item -> add_to_cart -> begin_checkout -> purchase

- The user-funnel file allows action from across the full dataset. 
- This session-lvl funnel only counts actions that happen in the same session. 

Note: With this file we can see if the users complete the whole 
purchase journey in one visit. 

*/

CREATE OR REPLACE VIEW `funnel-analysis-project-499019.funnel_analysis.int_session_funnel_steps` AS

WITH 
funnel_events AS (

    -- Keeping only the events needed for the main funnel.
    -- Each row is one funnel event inside a session. 
    SELECT
        session_key,
        user_pseudo_id,
        event_name,
        event_time
    FROM 'funnel-analysis-project-499019.funnel_analysis.stg_events'
    WHERE 
        event_name IN (
            'view_item',
            'add_to_cart',
            'begin_checkout',
            'purchase'
        )
        AND session_key IS NOT NULL 
),

first_view AS (
    SELECT 
        session_key,
        ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
        MIN (event_time) AS view_item_time
    FROM 
        funnel_events
    WHERE 
        event_name = 'view_item'
    GROUP BY 
        session_key
),