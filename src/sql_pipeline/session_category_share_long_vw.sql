-- Per-session category share long table.
-- Output: capstone-data-pull.YT_Data.session_category_share_long_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.session_category_share_long_vw` AS
WITH cat AS (
  SELECT session_id, category, SUM(content_elapsed_s) AS content_s
  FROM `capstone-data-pull.YT_Data.event_features_vw`
  GROUP BY session_id, category
)
SELECT
  session_id,
  category,
  SAFE_DIVIDE(content_s, SUM(content_s) OVER (PARTITION BY session_id)) AS share
FROM cat;
