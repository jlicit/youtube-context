-- Tag co-occurrence pairs with robust time-weighted ranking (30m cap).
-- Output: capstone-data-pull.YT_Data.event_tag_cooccur_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.event_tag_cooccur_vw` AS
WITH params AS (
  SELECT 5 AS min_cooccurs, 2 AS min_tag_len, TRUE AS require_letters, 1800 AS cap_s
),
stoplist AS (
  SELECT 'youtube' AS tag UNION ALL SELECT 'shorts' UNION ALL SELECT 'viral' UNION ALL SELECT 'new'
),
base AS (
  SELECT
    etl.watch_ts, etl.video_id, TRIM(etl.tag) AS tag, etl.content_elapsed_s
  FROM `capstone-data-pull.YT_Data.event_tags_long_vw` AS etl
  LEFT JOIN stoplist s ON LOWER(etl.tag) = s.tag
  CROSS JOIN params p
  WHERE s.tag IS NULL
    AND etl.tag IS NOT NULL AND TRIM(etl.tag) != ''
    AND LENGTH(TRIM(etl.tag)) >= p.min_tag_len
    AND (NOT p.require_letters OR REGEXP_CONTAINS(etl.tag, r'[A-Za-z]'))
),
per_event AS (
  SELECT
    watch_ts, video_id,
    ANY_VALUE(content_elapsed_s) AS dwell_s,
    ARRAY_AGG(DISTINCT tag ORDER BY tag) AS tags
  FROM base
  GROUP BY watch_ts, video_id
),
pairs AS (
  SELECT
    a AS tag_a, b AS tag_b, dwell_s,
    LEAST(dwell_s, (SELECT cap_s FROM params)) AS dwell_30m_s
  FROM per_event t
  CROSS JOIN UNNEST(t.tags) AS a WITH OFFSET i
  CROSS JOIN UNNEST(t.tags) AS b WITH OFFSET j
  WHERE i < j
)
SELECT
  tag_a, tag_b,
  COUNT(*) AS cooccurs,
  SUM(dwell_s) AS cooccurs_weight_s,
  SUM(dwell_30m_s) AS cooccurs_weight_30m_s
FROM pairs
GROUP BY tag_a, tag_b
HAVING COUNT(*) >= (SELECT min_cooccurs FROM params)
ORDER BY cooccurs_weight_30m_s DESC, cooccurs DESC, tag_a, tag_b;
