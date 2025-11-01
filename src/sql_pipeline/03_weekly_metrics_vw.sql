{{ config(materialized='view') }}

WITH base AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    session_total_time_s,
    session_consumed_runtime_s,
    session_mean_cuts_per_min,
    session_mean_cuts_per_min_content,
    session_avg_playback_speed,
    (binge_time_flag OR binge_count_flag) AS binge_flag,
    (binge_time_flag_content OR binge_count_flag) AS binge_flag_content
  FROM {{ ref('sessions_features_tbl') }}
)
SELECT
  week_start,
  -- Original time
  ROUND(SAFE_DIVIDE(SUM(session_total_time_s), 3600.0), 2) AS hours_watched,
  COUNT(*) AS sessions,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN binge_flag THEN 1 ELSE 0 END), NULLIF(COUNT(*),0)), 3) AS binge_rate,
  ROUND(AVG(session_mean_cuts_per_min), 2) AS mean_cuts_per_min_unweighted,
  ROUND(SAFE_DIVIDE(SUM(session_mean_cuts_per_min * session_total_time_s), NULLIF(SUM(session_total_time_s), 0)), 2)
    AS mean_cuts_per_min_time_weighted,
  ROUND(SAFE_DIVIDE(SUM(session_total_time_s), NULLIF(COUNT(*),0)) / 60.0, 1) AS avg_session_min,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN binge_flag THEN session_total_time_s ELSE 0 END), NULLIF(SUM(session_total_time_s), 0)), 3)
    AS binge_time_share,
  -- Speed aware content time
  ROUND(SAFE_DIVIDE(SUM(session_consumed_runtime_s), 3600.0), 2) AS hours_consumed,
  ROUND(SAFE_DIVIDE(SUM(session_consumed_runtime_s), NULLIF(SUM(session_total_time_s), 0)), 3) AS avg_playback_speed,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN binge_flag_content THEN 1 ELSE 0 END), NULLIF(COUNT(*),0)), 3) AS binge_rate_content,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN binge_flag_content THEN session_consumed_runtime_s ELSE 0 END), NULLIF(SUM(session_consumed_runtime_s), 0)), 3)
    AS binge_time_share_content,
  ROUND(AVG(session_mean_cuts_per_min_content), 2) AS mean_cuts_per_min_unweighted_content,
  ROUND(SAFE_DIVIDE(SUM(session_mean_cuts_per_min_content * session_consumed_runtime_s), NULLIF(SUM(session_consumed_runtime_s), 0)), 2)
    AS mean_cuts_per_min_time_weighted_content
FROM base
GROUP BY week_start
ORDER BY week_start;
