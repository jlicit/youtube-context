-- Weekly category minutes + share of week.
-- Output: capstone-data-pull.YT_Data.weekly_category_share_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.weekly_category_share_vw` AS
WITH events AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    COALESCE(NULLIF(TRIM(category), ''), '(Unknown)') AS category,
    CAST(content_elapsed_s AS FLOAT64) AS content_elapsed_s
  FROM `capstone-data-pull.YT_Data.event_features_vw`
  WHERE watch_ts IS NOT NULL
),
per_cat AS (
  SELECT
    week_start, category,
    SUM(content_elapsed_s) / 60.0 AS minutes_content
  FROM events
  GROUP BY week_start, category
),
tot AS (
  SELECT week_start, SUM(minutes_content) AS minutes_total
  FROM per_cat
  GROUP BY week_start
)
SELECT
  p.week_start,
  p.category,
  ROUND(p.minutes_content, 2) AS minutes_content,
  SAFE_DIVIDE(p.minutes_content, NULLIF(t.minutes_total, 0)) AS share_of_week
FROM per_cat p
JOIN tot t USING (week_start)
ORDER BY p.week_start, p.category;
