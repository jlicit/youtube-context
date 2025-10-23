-- validation_checks.sql
-- Lightweight sanity checks for sessions and weekly rollups.

-- 1) Sessions table health
SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN events_in_session < 1 THEN 1 ELSE 0 END) AS bad_event_counts,
  SUM(CASE WHEN session_total_time_s < 0 THEN 1 ELSE 0 END) AS negative_time,
  SUM(CASE WHEN session_total_time_s = 0 THEN 1 ELSE 0 END) AS zero_time_sessions,
  MIN(session_start_ts) AS min_ts,
  MAX(session_start_ts) AS max_ts
FROM `capstone-data-pull.YT_Data.sessions_features_tbl`;

-- 2) Weekly rollup counts match raw sessions?
WITH w AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    COUNT(*) AS sessions
  FROM `capstone-data-pull.YT_Data.sessions_features_tbl`
  GROUP BY week_start
)
SELECT
  w.week_start,
  w.sessions AS raw_sessions,
  m.sessions AS view_sessions,
  (w.sessions = m.sessions) AS counts_match
FROM w
JOIN `capstone-data-pull.YT_Data.weekly_metrics_vw` m USING (week_start)
ORDER BY week_start DESC;

-- 3) Does hours_watched equal summed session_total_time_s/3600 per week?
WITH w AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    SUM(session_total_time_s)/3600.0 AS hours_calc
  FROM `capstone-data-pull.YT_Data.sessions_features_tbl`
  GROUP BY week_start
)
SELECT
  m.week_start,
  m.hours_watched,
  ROUND(w.hours_calc, 2) AS hours_calc,
  ABS(m.hours_watched - ROUND(w.hours_calc, 2)) AS abs_diff
FROM `capstone-data-pull.YT_Data.weekly_metrics_vw` m
JOIN w USING (week_start)
ORDER BY week_start DESC;

-- 4) Weighted vs. unweighted sanity (recent 12 weeks)
SELECT
  week_start,
  mean_cuts_per_min_unweighted,
  mean_cuts_per_min_time_weighted,
  (mean_cuts_per_min_time_weighted - mean_cuts_per_min_unweighted) AS delta
FROM `capstone-data-pull.YT_Data.weekly_metrics_vw`
ORDER BY week_start DESC
LIMIT 12;

-- 5) Spike finder: unusually long sessions or extreme cuts
SELECT *
FROM `capstone-data-pull.YT_Data.sessions_features_tbl`
WHERE session_total_time_s > 6*3600
   OR session_mean_cuts_per_min > 60
ORDER BY session_total_time_s DESC
LIMIT 50;

-- 6) PT week bucket check (boundary weeks around local midnight)
SELECT
  session_id,
  session_start_ts,
  TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start
FROM `capstone-data-pull.YT_Data.sessions_features_tbl`
WHERE EXTRACT(HOUR FROM DATETIME(session_start_ts, 'America/Los_Angeles')) IN (0, 23)
ORDER BY session_start_ts DESC
LIMIT 50;
