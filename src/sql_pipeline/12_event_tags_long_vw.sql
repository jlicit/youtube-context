CREATE OR REPLACE VIEW `PROJECT.DATASET.event_tags_long_vw` AS
WITH base AS (
  SELECT
    e.watch_ts,
    e.session_id,
    e.video_id,
    e.creator,
    e.category,
    e.content_elapsed_s,
    e.watch_ratio_content,
    e.early_exit_flag,
    e.cuts_per_min,
    w.tags_raw
  FROM `PROJECT.DATASET.event_features_vw` AS e
  LEFT JOIN `PROJECT.DATASET.watch_events_fe` AS w
    ON e.watch_ts = w.watch_ts
   AND e.video_id = w.video_id
  -- Guardrail: keep only valid 11-char YouTube IDs
  WHERE REGEXP_CONTAINS(e.video_id, r'^[A-Za-z0-9_-]{11}$')
),
norm AS (
  SELECT
    *,
    -- Unify delimiters: convert pipes/semicolons to commas, then normalize comma spacing
    REGEXP_REPLACE(
      REGEXP_REPLACE(COALESCE(tags_raw, ''), r'\s*\|\s*|;', ','),
      r'\s*,\s*', ','
    ) AS tags_norm
  FROM base
),
split AS (
  SELECT
    watch_ts, session_id, video_id, creator, category,
    content_elapsed_s, watch_ratio_content, early_exit_flag, cuts_per_min,
    TRIM(tag_piece) AS raw_tag
  FROM norm, UNNEST(SPLIT(tags_norm, ',')) AS tag_piece
),
clean AS (
  SELECT
    watch_ts, session_id, video_id, creator, category,
    content_elapsed_s, watch_ratio_content, early_exit_flag, cuts_per_min,
    -- remove brackets/quotes/hashtags, collapse whitespace, lowercase
    LOWER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(raw_tag, r'[\[\]\(\)"#]+', ''),
        r'\s+', ' '
      )
    ) AS tag
  FROM split
  WHERE raw_tag IS NOT NULL AND TRIM(raw_tag) != ''
),
dedup AS (
  SELECT
    watch_ts, session_id, video_id, creator, category,
    content_elapsed_s, watch_ratio_content, early_exit_flag, cuts_per_min,
    tag
  FROM clean
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY watch_ts, video_id, tag
    ORDER BY tag
  ) = 1
)
SELECT *
FROM dedup
WHERE tag != '';
