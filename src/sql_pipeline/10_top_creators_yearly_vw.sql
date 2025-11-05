CREATE OR REPLACE VIEW `{{ project }}.{{ dataset }}.top_creators_yearly_vw` AS
-- 1) Normalize events
WITH events AS (
  SELECT
    EXTRACT(YEAR FROM DATETIME(watch_ts, 'America/Los_Angeles')) AS year_pt,
    COALESCE(NULLIF(TRIM(creator), ''), '(Unknown)')             AS creator,
    CAST(content_elapsed_s AS FLOAT64)                           AS content_elapsed_s
  FROM `{{ project }}.{{ dataset }}.event_features_vw`
  WHERE watch_ts IS NOT NULL
),

-- 2) Aggregate minutes per (year, creator)
per_creator AS (
  SELECT
    year_pt AS year,
    creator,
    SUM(content_elapsed_s) / 60.0 AS minutes_content
  FROM events
  GROUP BY year_pt, creator
),

-- 3) Yearly totals for shares
tot AS (
  SELECT year, SUM(minutes_content) AS minutes_total
  FROM per_creator
  GROUP BY year
)

-- 4) Final output
SELECT
  p.year,
  p.creator,
  ROUND(p.minutes_content, 2)                                                   AS minutes_content,  -- tidy for charts
  SAFE_DIVIDE(p.minutes_content, NULLIF(t.minutes_total, 0))                    AS share_of_year,    -- 0–1
  RANK()       OVER (PARTITION BY p.year ORDER BY p.minutes_content DESC)       AS rank_in_year,
  DENSE_RANK() OVER (PARTITION BY p.year ORDER BY p.minutes_content DESC)       AS dense_rank_in_year,
  ROW_NUMBER() OVER (PARTITION BY p.year ORDER BY p.minutes_content DESC, p.creator ASC)
    AS rownum_tiebreak
FROM per_creator p
JOIN tot t USING (year)
ORDER BY p.year, rank_in_year, p.creator;
