-- Monthly creator concentration/diversity metrics (HHI, entropy, top share).
-- Output: capstone-data-pull.YT_Data.monthly_creator_hhi_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.monthly_creator_hhi_vw` AS
WITH events AS (
  SELECT
    TIMESTAMP_TRUNC(watch_ts, MONTH, 'America/Los_Angeles') AS month_start,
    COALESCE(NULLIF(TRIM(creator), ''), '(Unknown)') AS creator,
    CAST(content_elapsed_s AS FLOAT64) AS content_elapsed_s
  FROM `capstone-data-pull.YT_Data.event_features_vw`
  WHERE watch_ts IS NOT NULL
),
per_creator AS (
  SELECT month_start, creator, SUM(content_elapsed_s)/60.0 AS minutes_content
  FROM events
  GROUP BY 1,2
),
shares AS (
  SELECT
    month_start, creator, minutes_content,
    SAFE_DIVIDE(minutes_content, NULLIF(SUM(minutes_content) OVER (PARTITION BY month_start), 0)) AS share
  FROM per_creator
),
agg AS (
  SELECT
    month_start,
    COUNT(*) AS creator_count,
    SUM(share*share) AS hhi_creator,
    -SUM(CASE WHEN share > 0 THEN share*LN(share) ELSE 0 END) AS entropy_nats
  FROM shares
  GROUP BY month_start
),
top AS (
  SELECT month_start, creator AS top_creator, share AS top_share
  FROM (
    SELECT month_start, creator, share,
           ROW_NUMBER() OVER (PARTITION BY month_start ORDER BY share DESC, creator ASC) rn
    FROM shares
  ) WHERE rn = 1
)
SELECT
  a.month_start,
  a.creator_count,
  ROUND(a.hhi_creator, 6) AS hhi_creator,
  ROUND(1.0 / NULLIF(a.hhi_creator,0), 1) AS effective_creators,
  ROUND(a.entropy_nats, 6) AS entropy_nats,
  ROUND(SAFE_DIVIDE(a.entropy_nats, LN(NULLIF(a.creator_count,1))), 6) AS entropy_norm_0_1,
  ROUND(
    SAFE_DIVIDE(
      a.hhi_creator - SAFE_DIVIDE(1.0, NULLIF(a.creator_count,0)),
      1.0 - SAFE_DIVIDE(1.0, NULLIF(a.creator_count,0))
    ),
    6
  ) AS hhi_norm_0_1,
  t.top_creator,
  ROUND(t.top_share, 6) AS top_share
FROM agg a
LEFT JOIN top t USING (month_start)
ORDER BY a.month_start;
