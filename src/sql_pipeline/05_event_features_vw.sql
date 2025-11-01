CREATE OR REPLACE VIEW `{{PROJECT_ID}}.{{DATASET}}.watch_events_features_vw` AS
WITH base AS (
  SELECT
    we.session_id,                                   -- session id from upstream sessionization (if present)
    we.watch_ts,                                     -- event timestamp (TIMESTAMP, UTC)
    NULLIF(we.video_id, '#NAME?') AS video_id,       -- guard against corrupted id
    we.creator,
    we.category,
    we.duration_meta_s,                              -- video duration from metadata (seconds)
    SAFE_CAST(we.elapsed_s AS FLOAT64) AS elapsed_s, -- wall-time elapsed for this event (seconds)
    COALESCE(we.playback_speed, 1.0) AS playback_speed,
    we.cuts_per_min,                                 -- scene-change rate (cuts per minute)
    COALESCE(we.high_cuts_flag, FALSE) AS high_cuts_flag,
    we.gap_prev_s AS gap_from_prev_s_src,            -- gap from previous event (as provided by source feed)
    COALESCE(we.new_session_flag, FALSE) AS is_new_session_src
  FROM `{{PROJECT_ID}}.{{DATASET}}.watch_events_fe` AS we
  WHERE NULLIF(we.video_id, '#NAME?') IS NOT NULL
),
ordered AS (
  -- Ensure deterministic ordering across ties by (watch_ts, video_id)
  SELECT
    b.*,
    LAG(b.watch_ts) OVER (ORDER BY b.watch_ts, b.video_id) AS prev_watch_ts_global,
    TIMESTAMP_DIFF(
      b.watch_ts,
      LAG(b.watch_ts) OVER (ORDER BY b.watch_ts, b.video_id),
      SECOND
    ) AS gap_from_prev_s,
    ROW_NUMBER() OVER (PARTITION BY b.session_id ORDER BY b.watch_ts, b.video_id) AS rn_in_session,
    (ROW_NUMBER() OVER (PARTITION BY b.session_id ORDER BY b.watch_ts, b.video_id) = 1) AS is_new_session
  FROM base b
),
feat AS (
  SELECT
    o.*,

    -- Content-adjusted elapsed time: cap by metadata duration and adjust by playback speed
    LEAST(o.duration_meta_s, o.elapsed_s * o.playback_speed) AS content_elapsed_s,

    -- Proportion of the video actually consumed (content-adjusted)
    SAFE_DIVIDE(
      LEAST(o.duration_meta_s, o.elapsed_s * o.playback_speed),
      NULLIF(o.duration_meta_s, 0)
    ) AS watch_ratio_content,

    -- Early exit if consumed <= min(60s, 25% of duration)
    (LEAST(o.duration_meta_s, o.elapsed_s * o.playback_speed)
       <= LEAST(60.0, 0.25 * o.duration_meta_s)) AS early_exit_flag,

    -- Local time features (defaults to America/Los_Angeles; override by templating {{TIMEZONE}})
    EXTRACT(HOUR      FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}'))          AS hour_of_day_pt,
    EXTRACT(DAYOFWEEK FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}'))          AS day_of_week_pt, -- 1=Sunday
    EXTRACT(DAYOFWEEK FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}')) IN (1,7) AS is_weekend_pt,

    -- Category-relative rank bins of cuts_per_min (0-indexed)
    NTILE(10) OVER (PARTITION BY o.category ORDER BY o.cuts_per_min) - 1 AS cuts_per_min_decile_cat,
    NTILE(5)  OVER (PARTITION BY o.category ORDER BY o.cuts_per_min) - 1 AS cuts_per_min_quintile_cat,

    -- Four coarse hour bins (0=overnight, 1=morning, 2=afternoon, 3=evening)
    CASE
      WHEN EXTRACT(HOUR FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}')) BETWEEN 0  AND 5  THEN 0
      WHEN EXTRACT(HOUR FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}')) BETWEEN 6  AND 11 THEN 1
      WHEN EXTRACT(HOUR FROM DATETIME(o.watch_ts, '{{TIMEZONE|America/Los_Angeles}}')) BETWEEN 12 AND 17 THEN 2
      ELSE 3
    END AS hour_bin4,

    -- Creator change relative to immediately preceding global event (note: global, not per session)
    (o.creator != LAG(o.creator) OVER (ORDER BY o.watch_ts, o.video_id)) AS creator_switch_flag
  FROM ordered o
)
SELECT
  f.*,

  -- Quartiles of content watch ratio (0..3), null-safe
  CASE
    WHEN f.watch_ratio_content IS NULL THEN NULL
    WHEN f.watch_ratio_content < 0.25 THEN 0
    WHEN f.watch_ratio_content < 0.50 THEN 1
    WHEN f.watch_ratio_content < 0.75 THEN 2
    ELSE 3
  END AS watch_ratio_content_quartile
FROM feat f;
