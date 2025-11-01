CREATE OR REPLACE VIEW `{{PROJECT_ID}}.{{DATASET}}.session_category_share_long_vw` AS
WITH cat AS (
  SELECT
    session_id,
    category,
    SUM(content_elapsed_s) AS content_s
  FROM `{{PROJECT_ID}}.{{DATASET}}.{{EVENT_FEATURES_VW}}`
  WHERE category IS NOT NULL
  GROUP BY session_id, category
)
SELECT
  session_id,
  category,
  SAFE_DIVIDE(content_s, SUM(content_s) OVER (PARTITION BY session_id)) AS share
FROM cat;
