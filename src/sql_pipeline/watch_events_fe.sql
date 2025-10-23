-- watch_events_fe.sql
-- Build feature-engineered watch events from cleaned input.
-- Input  : `YT_Data.cleaned_data`
-- Output : `YT_Data.watch_events_fe`
-- Notes  : Edit the speed_rules CTE to reflect your actual playback-speed history.

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.watch_events_fe` AS

-- ── Playback speed rules (edit these ranges to match your history) ─────────────
WITH speed_rules AS (
  -- Baseline rule (covers all dates at 1×). Keep this line.
  SELECT DATE '1900-01-01' AS start_date, DATE '2100-01-01' AS end_date, 1.0 AS speed
  UNION ALL
  -- EXAMPLE: everything before 2024‑09‑01 was watched at 2× (adjust/remove)
  SELECT DATE '2000-01-01', DATE '2024-09-01', 2.0
),

-- 1) Normalize types
base AS (
  SELECT
    *,
    COALESCE(SAFE_CAST(`date` AS DATE), SAFE.PARSE_DATE('%Y-%m-%d', CAST(`date` AS STRING))) AS watch_date,
    COALESCE(
      SAFE_CAST(`time` AS TIME),
      SAFE.PARSE_TIME('%I:%M:%S %p', CAST(`time` AS STRING)),
      SAFE.PARSE_TIME('%H:%M:%S',    CAST(`time` AS STRING)),
      SAFE.PARSE_TIME('%I:%M %p',    CAST(`time` AS STRING)),
      SAFE.PARSE_TIME('%H:%M',       CAST(`time` AS STRING))
    ) AS watch_time,
    SAFE_CAST(gap_prev_s       AS INT64)   AS gap_prev_s_i,
    SAFE_CAST(duration_meta_s  AS FLOAT64) AS duration_meta_s_f,
    SAFE_CAST(view_count       AS INT64)   AS view_count_i,
    SAFE_CAST(like_count       AS INT64)   AS like_count_i,
    SAFE_CAST(cuts_total       AS INT64)   AS cuts_total_i,
    SAFE_CAST(duration_cut_s   AS FLOAT64) AS duration_cut_s_f,
    SAFE_CAST(cuts_per_min     AS FLOAT64) AS cuts_per_min_f
  FROM `capstone-data-pull.YT_Data.cleaned_data`
),

-- 2) Localize to PT
typed AS (
  SELECT
    *,
    TIMESTAMP(DATETIME(watch_date, IFNULL(watch_time, TIME '00:00:00')), 'America/Los_Angeles') AS watch_ts
  FROM base
),

-- 3) Parse "Elapsed Time" → seconds
elapsed AS (
  SELECT
    *,
    CASE
      WHEN `Elapsed Time` IS NULL THEN NULL
      ELSE CASE ARRAY_LENGTH(SPLIT(`Elapsed Time`, ':'))
        WHEN 3 THEN 3600 * SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(0)] AS INT64) +
                      60 * SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(1)] AS INT64) +
                           SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(2)] AS INT64)
        WHEN 2 THEN  60 * SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(0)] AS INT64) +
                           SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(1)] AS INT64)
        WHEN 1 THEN SAFE_CAST(SPLIT(`Elapsed Time`, ':')[OFFSET(0)] AS INT64)
        ELSE NULL
      END
    END AS elapsed_s
  FROM typed
),

-- 4) Row-level features (incl. playback_speed from rules)
features AS (
  SELECT
    e.*,
    SAFE_DIVIDE(elapsed_s, duration_meta_s_f)             AS raw_watch_ratio,
    LEAST(1.2, SAFE_DIVIDE(elapsed_s, duration_meta_s_f)) AS watch_ratio,
    EXTRACT(HOUR FROM watch_ts)                           AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM watch_ts)                      AS dow,
    gap_prev_s_i > 1800                                   AS new_session_flag,
    COALESCE(
      (SELECT MAX(speed) FROM speed_rules
       WHERE e.watch_date BETWEEN start_date AND end_date),
      1.0
    ) AS playback_speed
  FROM elapsed e
),

-- 5) First‑pass sessionization (for coarse features)
sessions AS (
  SELECT
    *,
    SUM(CASE WHEN new_session_flag OR gap_prev_s_i IS NULL THEN 1 ELSE 0 END)
      OVER (ORDER BY watch_ts, video_id) AS session_id
  FROM features
),

-- 6) Coarse session aggregates
sessionized AS (
  SELECT
    *,
    SUM(elapsed_s)      OVER (PARTITION BY session_id) AS session_total_time_s,
    COUNT(*)            OVER (PARTITION BY session_id) AS session_video_count,
    AVG(cuts_per_min_f) OVER (PARTITION BY session_id) AS session_mean_cuts_per_min,
    (SUM(elapsed_s) OVER (PARTITION BY session_id) >= 45*60) AS binge_time_flag,
    (COUNT(*)     OVER (PARTITION BY session_id) >= 5)       AS binge_count_flag
  FROM sessions
),

-- 7) Category‑relative “high‑cuts” flag
cuts_flags AS (
  SELECT
    *,
    PERCENTILE_CONT(cuts_per_min_f, 0.75) OVER (PARTITION BY category) AS cuts_q75_cat,
    cuts_per_min_f >= PERCENTILE_CONT(cuts_per_min_f, 0.75)
      OVER (PARTITION BY category) AS high_cuts_flag
  FROM sessionized
)

-- 8) Recast numerics back to original names
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
