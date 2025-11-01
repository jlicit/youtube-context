-- BigQuery Standard SQL
-- Creates a feature view over watch events for analysis

CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.YOUR_DATASET.watch_events_fe` AS

-- 0) Playback speed rules
WITH speed_rules AS (
  -- Baseline rule: all dates default to 1×
  SELECT DATE '1900-01-01' AS start_date, DATE '2100-01-01' AS end_date, 1.0 AS speed
  UNION ALL
  -- EXAMPLE: everything before 2024-09-01 assumed at 2×
  SELECT DATE '2000-01-01', DATE '2024-09-01', 2.0
),

-- 1) Normalize types
base AS (
  SELECT
    cd.*,
    COALESCE(
      SAFE_CAST(cd.`date` AS DATE),
      SAFE.PARSE_DATE('%Y-%m-%d', CAST(cd.`date` AS STRING))
    ) AS watch_date,
    COALESCE(
      SAFE_CAST(cd.`time` AS TIME),
      SAFE.PARSE_TIME('%I:%M:%S %p', CAST(cd.`time` AS STRING)),
      SAFE.PARSE_TIME('%H:%M:%S',    CAST(cd.`time` AS STRING)),
      SAFE.PARSE_TIME('%I:%M %p',    CAST(cd.`time` AS STRING)),
      SAFE.PARSE_TIME('%H:%M',       CAST(cd.`time` AS STRING))
    ) AS watch_time,
    SAFE_CAST(cd.gap_prev_s       AS INT64)   AS gap_prev_s_i,
    SAFE_CAST(cd.duration_meta_s  AS FLOAT64) AS duration_meta_s_f,
    SAFE_CAST(cd.view_count       AS INT64)   AS view_count_i,
    SAFE_CAST(cd.like_count       AS INT64)   AS like_count_i,
    SAFE_CAST(cd.cuts_total       AS INT64)   AS cuts_total_i,
    SAFE_CAST(cd.duration_cut_s   AS FLOAT64) AS duration_cut_s_f,
    SAFE_CAST(cd.cuts_per_min     AS FLOAT64) AS cuts_per_min_f
  FROM `YOUR_PROJECT_ID.YOUR_DATASET.cleaned_data` AS cd
),

-- 2) Local timestamp (America/Los_Angeles)
typed AS (
  SELECT
    b.*,
    TIMESTAMP(DATETIME(watch_date, IFNULL(watch_time, TIME '00:00:00')), 'America/Los_Angeles') AS watch_ts
  FROM base AS b
),

-- 3) Parse "Elapsed Time" -> elapsed_s (supports hh:mm:ss | mm:ss | ss)
elapsed AS (
  SELECT
    t.*,
    CASE
      WHEN t.`Elapsed Time` IS NULL THEN NULL
      ELSE CASE ARRAY_LENGTH(SPLIT(t.`Elapsed Time`, ':'))
        WHEN 3 THEN 3600 * SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(0)] AS INT64) +
                      60 * SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(1)] AS INT64) +
                           SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(2)] AS INT64)
        WHEN 2 THEN  60 * SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(0)] AS INT64) +
                           SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(1)] AS INT64)
        WHEN 1 THEN SAFE_CAST(SPLIT(t.`Elapsed Time`, ':')[OFFSET(0)] AS INT64)
        ELSE NULL
      END
    END AS elapsed_s
  FROM typed AS t
),

-- 4) Row-level features (+ playback_speed from rules)
features AS (
  SELECT
    e.*,
    SAFE_DIVIDE(elapsed_s, duration_meta_s_f)             AS raw_watch_ratio,
    LEAST(1.2, SAFE_DIVIDE(elapsed_s, duration_meta_s_f)) AS watch_ratio, -- cap to reduce outlier impact
    EXTRACT(HOUR FROM watch_ts)                           AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM watch_ts)                      AS dow,
    gap_prev_s_i > 1800                                   AS new_session_flag,
    /* Playback speed: choose the highest matching rule (if overlapping) */
    COALESCE(
      (SELECT MAX(speed)
       FROM speed_rules
       WHERE e.watch_date BETWEEN start_date AND end_date),
      1.0
    ) AS playback_speed
  FROM elapsed AS e
),

-- 5) Sessionization
sessions AS (
  SELECT
    f.*,
    SUM(CASE WHEN new_session_flag OR gap_prev_s_i IS NULL THEN 1 ELSE 0 END)
      OVER (ORDER BY watch_ts, video_id) AS session_id
  FROM features AS f
),

-- 6) Session aggregates & binge flags
sessionized AS (
  SELECT
    s.*,
    SUM(elapsed_s)      OVER (PARTITION BY session_id) AS session_total_time_s,
    COUNT(*)            OVER (PARTITION BY session_id) AS session_video_count,
    AVG(cuts_per_min_f) OVER (PARTITION BY session_id) AS session_mean_cuts_per_min,
    (SUM(elapsed_s) OVER (PARTITION BY session_id) >= 45*60) AS binge_time_flag,
    (COUNT(*)     OVER (PARTITION BY session_id) >= 5)       AS binge_count_flag
  FROM sessions AS s
),

-- 7) Category-relative “high-cuts” flag (75th pct per category)
cuts_flags AS (
  SELECT
    sz.*,
    PERCENTILE_CONT(cuts_per_min_f, 0.75) OVER (PARTITION BY category) AS cuts_q75_cat,
    cuts_per_min_f >= PERCENTILE_CONT(cuts_per_min_f, 0.75)
      OVER (PARTITION BY category) AS high_cuts_flag
  FROM sessionized AS sz
)

-- 8) Final projection (preserve original column names post-cast)
SELECT
  * EXCEPT(gap_prev_s, duration_meta_s, view_count, like_count, cuts_total, duration_cut_s, cuts_per_min),
  gap_prev_s_i      AS gap_prev_s,
  duration_meta_s_f AS duration_meta_s,
  view_count_i      AS view_count,
  like_count_i      AS like_count,
  cuts_total_i      AS cuts_total,
  duration_cut_s_f  AS duration_cut_s,
  cuts_per_min_f    AS cuts_per_min
FROM cuts_flags;
