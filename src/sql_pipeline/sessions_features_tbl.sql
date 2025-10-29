CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.sessions_features_tbl`
PARTITION BY DATE(session_start_ts)
CLUSTER BY session_id AS
WITH
  -- Tunable parameters (edit safely)
  params AS (
    SELECT
      1800 AS idle_s,          -- new session if idle > 30 min
      600  AS tail_cap_s,      -- cap last event’s tail at 10 min (wall time)
      7200 AS binge_time_s,    -- binge if ≥ 2 hours
      6    AS binge_count_min  -- OR binge if ≥ 6 events
  ),

  -- Source events (ensure schema matches)
  src AS (
    SELECT
      watch_ts,
      video_id,
      duration_meta_s,
      cuts_total,
      playback_speed                 -- from watch_events_fe
    FROM `${PROJECT}.${DATASET}.watch_events_fe`
    WHERE watch_ts IS NOT NULL
  ),

  -- Stable event ordering
  ordered_base AS (
    SELECT
      s.*,
      ROW_NUMBER() OVER (ORDER BY watch_ts, video_id) AS event_idx
    FROM src s
  ),

  -- Peeking neighbors to compute gaps
  ordered AS (
    SELECT
      ob.*,
      LEAD(ob.watch_ts) OVER (ORDER BY ob.event_idx) AS next_ts,
      TIMESTAMP_DIFF(LEAD(ob.watch_ts) OVER (ORDER BY ob.event_idx), ob.watch_ts, SECOND) AS gap_to_next_s,
      LAG(ob.watch_ts)  OVER (ORDER BY ob.event_idx) AS prev_ts,
      TIMESTAMP_DIFF(ob.watch_ts, LAG(ob.watch_ts) OVER (ORDER BY ob.event_idx), SECOND) AS gap_from_prev_s
    FROM ordered_base ob
  ),

  -- 1) Wall clock seconds watched and session breaks
  watched_base AS (
    SELECT
      *,
      CASE
        WHEN next_ts IS NOT NULL
          THEN GREATEST(0.0, LEAST(CAST(gap_to_next_s AS FLOAT64), COALESCE(duration_meta_s, 0.0)))
        ELSE
          -- tail cap on last event
          GREATEST(
            0.0,
            LEAST(CAST((SELECT tail_cap_s FROM params) AS FLOAT64), COALESCE(duration_meta_s, 0.0))
          )
      END AS watched_s,  -- wall clock seconds
      CASE
        WHEN gap_from_prev_s IS NULL OR gap_from_prev_s > (SELECT idle_s FROM params) THEN 1 ELSE 0
      END AS is_new_session
    FROM ordered
  ),

  -- 2) Speed-aware content consumption and scaled cuts
  watched AS (
    SELECT
      *,
      -- content seconds advanced (capped by runtime)
      LEAST(
        COALESCE(duration_meta_s, 0.0),
        CAST(watched_s AS FLOAT64) * COALESCE(NULLIF(playback_speed, 0.0), 1.0)
      ) AS consumed_runtime_s,

      -- scale cuts by content fraction (not wall time)
      COALESCE(
        SAFE_MULTIPLY(
          CAST(cuts_total AS FLOAT64),
          SAFE_DIVIDE(
            LEAST(
              COALESCE(duration_meta_s, 0.0),
              CAST(watched_s AS FLOAT64) * COALESCE(NULLIF(playback_speed, 0.0), 1.0)
            ),
            NULLIF(duration_meta_s, 0.0)
          )
        ),
        0.0
      ) AS cuts_watched
    FROM watched_base
  ),

  -- 3) Sessionize
  sessionized AS (
    SELECT
      *,
      SUM(is_new_session) OVER (ORDER BY event_idx) AS session_id
    FROM watched
  ),

  -- 4) Session aggregates
  sessions AS (
    SELECT
      session_id,
      MIN(watch_ts)                   AS session_start_ts,
      COUNT(*)                        AS events_in_session,
      SUM(watched_s)                  AS session_total_time_s,         -- wall time
      SUM(consumed_runtime_s)         AS session_consumed_runtime_s,   -- content time
      SUM(cuts_watched)               AS session_cuts_watched_total
    FROM sessionized
    GROUP BY session_id
  )

-- 5) Feature derivations
SELECT
  s.*,

  -- wall-time CPM (existing behavior)
  SAFE_DIVIDE(s.session_cuts_watched_total, s.session_total_time_s / 60.0)
    AS session_mean_cuts_per_min,

  -- content-time CPM
  SAFE_DIVIDE(s.session_cuts_watched_total, NULLIF(s.session_consumed_runtime_s / 60.0, 0.0))
    AS session_mean_cuts_per_min_content,

  -- average playback speed across the session
  SAFE_DIVIDE(s.session_consumed_runtime_s, NULLIF(s.session_total_time_s, 0.0))
    AS session_avg_playback_speed,

  -- binge flags: wall-time, count, content-time
  (s.session_total_time_s       >= (SELECT binge_time_s     FROM params)) AS binge_time_flag,
  (s.events_in_session          >= (SELECT binge_count_min  FROM params)) AS binge_count_flag,
  (s.session_consumed_runtime_s >= (SELECT binge_time_s     FROM params)) AS binge_time_flag_content
FROM sessions s
;
