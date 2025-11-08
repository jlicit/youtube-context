CREATE OR REPLACE VIEW `{{project_id}}.{{dataset}}.creator_return_rewatch_weekly_vw` AS

-- 0) Clean, time-contributing events (deduped at (session_id, watch_ts, video_id))
WITH events_base AS (
  SELECT
    e.session_id,
    e.creator,
    e.video_id,
    e.watch_ts
  FROM `{{project_id}}.{{dataset}}.event_features_vw` AS e
  WHERE e.content_elapsed_s > 0
    AND e.watch_ts IS NOT NULL
    AND REGEXP_CONTAINS(e.video_id, r'^[A-Za-z0-9_-]{11}$')
    AND COALESCE(TRIM(e.creator), '') != ''
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY e.session_id, e.watch_ts, e.video_id
    ORDER BY e.video_id
  ) = 1
),

-- 1) Next watch per creator → event-level 7-day return flag
creator_seq AS (
  SELECT
    creator,
    watch_ts,
    LEAD(watch_ts) OVER (
      PARTITION BY creator
      ORDER BY watch_ts, video_id
    ) AS next_watch_ts
  FROM events_base
),
creator_return_events AS (
  SELECT
    creator,
    watch_ts,
    next_watch_ts,
    DATE_DIFF(
      DATE(next_watch_ts, 'America/Los_Angeles'),
      DATE(watch_ts,      'America/Los_Angeles'),
      DAY
    ) AS days_to_return,
    CASE
      WHEN next_watch_ts IS NULL THEN NULL
      WHEN DATE_DIFF(
             DATE(next_watch_ts, 'America/Los_Angeles'),
             DATE(watch_ts,      'America/Los_Angeles'),
             DAY
           ) <= 7
        THEN TRUE
      ELSE FALSE
    END AS return_within_7d_flag
  FROM creator_seq
),

-- 2) Weekly per-creator return rate + used/total denominators
creator_return_weekly AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    creator,
    AVG(
      CASE
        WHEN return_within_7d_flag THEN 1.0
        WHEN return_within_7d_flag IS NULL THEN NULL
        ELSE 0.0
      END
    ) AS return_7d_rate,
    COUNTIF(return_within_7d_flag IS NOT NULL) AS creator_events_used,
    COUNT(*) AS creator_events_total
  FROM creator_return_events
  GROUP BY week_start, creator
),

-- 3) Weekly overall (all creators) return rate + used/total denominators
creator_return_weekly_all AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    AVG(
      CASE
        WHEN return_within_7d_flag THEN 1.0
        WHEN return_within_7d_flag IS NULL THEN NULL
        ELSE 0.0
      END
    ) AS return_7d_rate_all,
    COUNTIF(return_within_7d_flag IS NOT NULL) AS return_events_all_used,
    COUNT(*) AS return_events_all_total
  FROM creator_return_events
  GROUP BY week_start
),

-- 4) Precompute event-weighted average from per-creator parts (sanity check vs overall)
weighted_from_parts AS (
  SELECT
    week_start,
    SAFE_DIVIDE(
      SUM(COALESCE(return_7d_rate, 0) * creator_events_used),
      NULLIF(SUM(creator_events_used), 0)
    ) AS weighted_from_parts,
    SUM(creator_events_used)  AS events_used_from_parts,
    SUM(creator_events_total) AS events_total_from_parts
  FROM creator_return_weekly
  GROUP BY week_start
),

-- 5) Rewatch events and weekly overall rewatch rate (rn>1 => rewatch)
rewatch_seq AS (
  SELECT
    video_id,
    watch_ts,
    ROW_NUMBER() OVER (PARTITION BY video_id ORDER BY watch_ts, video_id) AS rn
  FROM events_base
),
rewatch_weekly AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles') AS week_start,
    AVG(CASE WHEN rn > 1 THEN 1.0 ELSE 0.0 END) AS rewatch_rate,
    COUNT(*) AS rewatch_events
  FROM rewatch_seq
  GROUP BY week_start
),

-- 6) Combine into one unified weekly table
per_creator AS (
  SELECT
    cr.week_start,
    cr.creator,
    'PER_CREATOR' AS creator_scope,
    cr.return_7d_rate,
    cr.creator_events_used,
    cr.creator_events_total,
    rr.rewatch_rate,
    rr.rewatch_events,
    CAST(NULL AS FLOAT64) AS weighted_from_parts,
    CAST(NULL AS INT64)   AS events_used_from_parts,
    CAST(NULL AS INT64)   AS events_total_from_parts,
    CAST(NULL AS FLOAT64) AS return_vs_weighted_abs_diff,
    CAST(NULL AS BOOL)    AS return_vs_weighted_match
  FROM creator_return_weekly AS cr
  LEFT JOIN rewatch_weekly AS rr USING (week_start)
),
overall AS (
  SELECT
    cra.week_start,
    CAST(NULL AS STRING) AS creator,
    'ALL_CREATORS' AS creator_scope,
    cra.return_7d_rate_all AS return_7d_rate,
    -- align names to union with per_creator:
    cra.return_events_all_used  AS creator_events_used,
    cra.return_events_all_total AS creator_events_total,
    rr.rewatch_rate,
    rr.rewatch_events,
    wf.weighted_from_parts,
    wf.events_used_from_parts,
    wf.events_total_from_parts,
    ABS(cra.return_7d_rate_all - wf.weighted_from_parts) AS return_vs_weighted_abs_diff,
    ABS(cra.return_7d_rate_all - wf.weighted_from_parts) <= 1e-9 AS return_vs_weighted_match
  FROM creator_return_weekly_all AS cra
  LEFT JOIN weighted_from_parts AS wf USING (week_start)
  LEFT JOIN rewatch_weekly       AS rr USING (week_start)
)

SELECT * FROM per_creator
UNION ALL
SELECT * FROM overall
ORDER BY week_start, creator_scope, creator;
