CREATE OR REPLACE VIEW `{{project}}.{{dataset}}.event_tag_cooccur_vw` AS

-- 1) Tunables
WITH params AS (
  SELECT
    5    AS min_cooccurs,     -- keep pairs seen in ≥ this many events
    2    AS min_tag_len,      -- drop tags shorter than this
    TRUE AS require_letters,  -- drop tags with no [A-Za-z]
    1800 AS cap_s             -- 30 minutes per event cap (seconds)
),

-- 2) Tiny lowercase stoplist (customize freely)
stoplist AS (
  SELECT 'youtube' AS tag UNION ALL
  SELECT 'shorts'           UNION ALL
  SELECT 'viral'            UNION ALL
  SELECT 'new'
),

-- 3) Normalize + filter tags
base AS (
  SELECT
    etl.watch_ts,
    etl.video_id,
    TRIM(etl.tag) AS tag,
    etl.content_elapsed_s
  FROM `{{project}}.{{dataset}}.event_tags_long_vw` AS etl
  LEFT JOIN stoplist s
    ON LOWER(etl.tag) = s.tag
  CROSS JOIN params p
  WHERE s.tag IS NULL
    AND etl.tag IS NOT NULL
    AND TRIM(etl.tag) != ''
    AND LENGTH(TRIM(etl.tag)) >= p.min_tag_len
    AND (NOT p.require_letters OR REGEXP_CONTAINS(etl.tag, r'[A-Za-z]'))
),

-- 4) One dwell value + distinct tags per (watch_ts, video_id)
per_event AS (
  SELECT
    watch_ts,
    video_id,
    ANY_VALUE(content_elapsed_s) AS dwell_s,                       -- raw dwell for the event
    ARRAY_AGG(DISTINCT tag ORDER BY tag) AS tags                   -- distinct, sorted
  FROM base
  GROUP BY watch_ts, video_id
),

-- 5) Build unordered tag pairs; attach raw + capped dwell
pairs AS (
  SELECT
    a AS tag_a,
    b AS tag_b,
    dwell_s,
    LEAST(dwell_s, (SELECT cap_s FROM params)) AS dwell_30m_s
  FROM per_event t
  CROSS JOIN UNNEST(t.tags) AS a WITH OFFSET i
  CROSS JOIN UNNEST(t.tags) AS b WITH OFFSET j
  WHERE i < j
)

-- 6) Final rollup: counts + raw and 30m-capped weights
SELECT
  tag_a,
  tag_b,
  COUNT(*)         AS cooccurs,              -- events count
  SUM(dwell_s)     AS cooccurs_weight_s,     -- raw total dwell (reference)
  SUM(dwell_30m_s) AS cooccurs_weight_30m_s  -- recommended for ranking
FROM pairs
GROUP BY tag_a, tag_b
HAVING COUNT(*) >= (SELECT min_cooccurs FROM params)
ORDER BY cooccurs_weight_30m_s DESC, cooccurs DESC, tag_a, tag_b;
