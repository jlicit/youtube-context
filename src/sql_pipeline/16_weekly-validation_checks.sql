-- 1) CONFIG
DECLARE v_project          STRING DEFAULT 'your-project-id';
DECLARE v_dataset          STRING DEFAULT 'your_dataset';
DECLARE v_sessions_tbl     STRING DEFAULT 'sessions_features_tbl';
DECLARE v_weekly_metrics_vw STRING DEFAULT 'weekly_metrics_vw';
DECLARE v_tz               STRING DEFAULT 'America/Los_Angeles';
DECLARE v_recent_weeks     INT64  DEFAULT 12;         -- for check #4
DECLARE v_spike_limit      INT64  DEFAULT 50;         -- for check #5

-- Qualified identifiers
DECLARE v_sessions_qualified STRING DEFAULT FORMAT('`%s.%s.%s`', v_project, v_dataset, v_sessions_tbl);
DECLARE v_weekly_qualified   STRING DEFAULT FORMAT('`%s.%s.%s`', v_project, v_dataset, v_weekly_metrics_vw);


-- 2) SESSIONS TABLE HEALTH
EXECUTE IMMEDIATE FORMAT("""
SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN events_in_session < 1 THEN 1 ELSE 0 END) AS bad_event_counts,
  SUM(CASE WHEN session_total_time_s < 0 THEN 1 ELSE 0 END) AS negative_time,
  SUM(CASE WHEN session_total_time_s = 0 THEN 1 ELSE 0 END) AS zero_time_sessions,
  MIN(session_start_ts) AS min_ts,
  MAX(session_start_ts) AS max_ts
FROM %s
""", v_sessions_qualified);


-- 3) WEEKLY ROLLUP COUNTS PARITY
EXECUTE IMMEDIATE FORMAT("""
WITH w AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), '%s') AS week_start,
    COUNT(*) AS sessions
  FROM %s
  GROUP BY week_start
)
SELECT
  w.week_start,
  w.sessions AS raw_sessions,
  m.sessions AS view_sessions,
  (w.sessions = m.sessions) AS counts_match
FROM w
JOIN %s m USING (week_start)
ORDER BY week_start DESC
""", v_tz, v_sessions_qualified, v_weekly_qualified);


-- 4) HOURS PARITY (DERIVED VS VIEW)
EXECUTE IMMEDIATE FORMAT("""
WITH w AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), '%s') AS week_start,
    SUM(session_total_time_s)/3600.0 AS hours_calc
  FROM %s
  GROUP BY week_start
)
SELECT
  m.week_start,
  m.hours_watched,
  ROUND(w.hours_calc, 2) AS hours_calc,
  ABS(m.hours_watched - ROUND(w.hours_calc, 2)) AS abs_diff
FROM %s m
JOIN w USING (week_start)
ORDER BY week_start DESC
""", v_tz, v_sessions_qualified, v_weekly_qualified);


-- 5) WEIGHTED VS UNWEIGHTED PACE (RECENT N WEEKS)
EXECUTE IMMEDIATE FORMAT("""
SELECT
  week_start,
  mean_cuts_per_min_unweighted,
  mean_cuts_per_min_time_weighted,
  (mean_cuts_per_min_time_weighted - mean_cuts_per_min_unweighted) AS delta
FROM %s
ORDER BY week_start DESC
LIMIT %d
""", v_weekly_qualified, v_recent_weeks);


-- 6) SPIKE FINDER (LONG SESSIONS / EXTREME CUTS)
EXECUTE IMMEDIATE FORMAT("""
SELECT *
FROM %s
WHERE session_total_time_s > 6*3600
   OR session_mean_cuts_per_min > 60
ORDER BY session_total_time_s DESC
LIMIT %d
""", v_sessions_qualified, v_spike_limit);


-- 7) PT WEEK BUCKET CHECK AROUND LOCAL MIDNIGHT
EXECUTE IMMEDIATE FORMAT("""
SELECT
  session_id,
  session_start_ts,
  TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), '%s') AS week_start
FROM %s
WHERE EXTRACT(HOUR FROM DATETIME(session_start_ts, '%s')) IN (0, 23)
ORDER BY session_start_ts DESC
LIMIT 50
""", v_tz, v_sessions_qualified, v_tz);
