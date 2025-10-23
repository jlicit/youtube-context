-- Weekly KPIs (rounded) + event-level extras and 4-week MA.
-- Output: capstone-data-pull.YT_Data.weekly_behavior_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.weekly_behavior_vw` AS
WITH sess_week AS (
  SELECT
    TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    COUNT(*) AS sessions,
    SUM(session_total_time_s) / 3600.0 AS hours_watched_raw,
    SAFE_DIVIDE(SUM(CASE WHEN binge_time_flag OR binge_count_flag THEN 1 ELSE 0 END), COUNT(*)) AS binge_rate_raw,
    AVG(session_mean_cuts_per_min) AS unwt_raw,
    SAFE_DIVIDE(SUM(session_mean_cuts_per_min * session_total_time_s), NULLIF(SUM(session_total_time_s), 0)) AS twt_raw,
    SAFE_DIVIDE(SUM(session_total_time_s), NULLIF(COUNT(*),0)) / 60.0 AS avg_session_min,
    SAFE_DIVIDE(SUM(session_consumed_runtime_s), NULLIF(SUM(session_total_time_s),0)) AS avg_playback_speed
  FROM `capstone-data-pull.YT_Data.sessions_features_tbl`
  GROUP BY week_start
),
event_week AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    SAFE_DIVIDE(SUM(CASE WHEN early_exit_flag     THEN 1 ELSE 0 END), COUNT(*)) AS early_exit_rate,
    SAFE_DIVIDE(SUM(CASE WHEN high_cuts_flag      THEN 1 ELSE 0 END), COUNT(*)) AS high_cuts_event_rate,
    SAFE_DIVIDE(SUM(CASE WHEN creator_switch_flag THEN 1 ELSE 0 END), COUNT(*)) AS creator_switch_rate,
    AVG(watch_ratio_content) AS mean_watch_ratio_content,
    SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 0 THEN 1 ELSE 0 END), COUNT(*)) AS share_hour_bin0,
    SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 1 THEN 1 ELSE 0 END), COUNT(*)) AS share_hour_bin1,
    SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 2 THEN 1 ELSE 0 END), COUNT(*)) AS share_hour_bin2,
    SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 3 THEN 1 ELSE 0 END), COUNT(*)) AS share_hour_bin3
  FROM `capstone-data-pull.YT_Data.event_features_vw`
  WHERE watch_ts IS NOT NULL
  GROUP BY week_start
)
SELECT
  s.week_start,
  ROUND(s.hours_watched_raw, 2) AS hours_watched,
  s.sessions,
  ROUND(s.binge_rate_raw, 3) AS binge_rate,
  ROUND(s.unwt_raw, 2) AS mean_cuts_per_min_unweighted,
  ROUND(s.twt_raw, 2) AS mean_cuts_per_min_time_weighted,
  s.avg_session_min,
  s.avg_playback_speed,
  e.early_exit_rate,
  e.high_cuts_event_rate,
  e.creator_switch_rate,
  e.mean_watch_ratio_content,
  e.share_hour_bin0, e.share_hour_bin1, e.share_hour_bin2, e.share_hour_bin3,
  AVG(ROUND(s.hours_watched_raw, 2)) OVER (
    ORDER BY s.week_start
    ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
  ) AS hours_watched_ma4,
  CAST(DATE(s.week_start) >= DATE '2023-11-01' AS BOOL) AS post_intervention,
  DATE_DIFF(DATE(s.week_start), DATE '2023-11-01', WEEK) AS weeks_since_intervention
FROM sess_week s
LEFT JOIN event_week e USING (week_start)
ORDER BY week_start;
