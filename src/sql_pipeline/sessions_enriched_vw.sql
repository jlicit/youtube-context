-- Enrich sessions_features_tbl with PT features, diversity metrics, top category,
-- creator-switch rate, and prior-session gap.
-- Output: capstone-data-pull.YT_Data.sessions_enriched_vw

CREATE OR REPLACE VIEW `capstone-data-pull.YT_Data.sessions_enriched_vw` AS
WITH s AS (
  SELECT
    sf.*,
    EXTRACT(HOUR      FROM DATETIME(sf.session_start_ts, 'America/Los_Angeles')) AS session_start_hour,
    EXTRACT(DAYOFWEEK FROM DATETIME(sf.session_start_ts, 'America/Los_Angeles')) AS session_dow,
    EXTRACT(DAYOFWEEK FROM DATETIME(sf.session_start_ts, 'America/Los_Angeles')) IN (1, 7) AS session_is_weekend
  FROM `capstone-data-pull.YT_Data.sessions_features_tbl` AS sf
),
cat_share AS (
  SELECT
    session_id,
    SUM(share * share)                         AS session_category_hhi,
    -SUM(IF(share > 0, share * LOG(share), 0)) AS session_category_entropy,
    MAX(IF(category = 'News & Politics', share, 0)) AS session_news_share,
    MAX(IF(category = 'Gaming',          share, 0)) AS session_gaming_share
  FROM `capstone-data-pull.YT_Data.session_category_share_long_vw`
  GROUP BY session_id
),
top_cat AS (
  SELECT
    session_id,
    category AS session_top_category,
    share    AS session_top_category_share
  FROM `capstone-data-pull.YT_Data.session_category_share_long_vw`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY share DESC, category) = 1
),
with_deciles AS (
  SELECT
    s.*,
    NTILE(10) OVER (ORDER BY s.session_mean_cuts_per_min)         - 1 AS session_cuts_per_min_decile,
    NTILE(10) OVER (ORDER BY s.session_mean_cuts_per_min_content) - 1 AS session_cuts_per_min_content_decile
  FROM s
),
prior_tmp AS (
  SELECT
    session_id,
    session_start_ts,
    LAG(session_start_ts) OVER (ORDER BY session_start_ts) AS prev_session_ts
  FROM s
),
prior_gaps AS (
  SELECT
    session_id,
    prev_session_ts,
    TIMESTAMP_DIFF(session_start_ts, prev_session_ts, SECOND) AS prior_session_gap_s,
    LEAST(TIMESTAMP_DIFF(session_start_ts, prev_session_ts, SECOND), 6*3600) AS prior_session_gap_capped_s
  FROM prior_tmp
),
events_base AS (
  SELECT
    session_id, watch_ts, video_id, creator
  FROM `capstone-data-pull.YT_Data.event_features_vw`
  WHERE session_id IS NOT NULL AND content_elapsed_s > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id, watch_ts, video_id ORDER BY video_id) = 1
),
events_ordered AS (
  SELECT
    eb.*,
    LAG(creator) OVER (PARTITION BY session_id ORDER BY watch_ts, video_id) AS prev_creator
  FROM events_base eb
),
switch_agg AS (
  SELECT
    session_id,
    COUNT(*) AS evts_distinct,
    SUM(CASE WHEN prev_creator IS NOT NULL AND creator IS NOT NULL AND creator != prev_creator THEN 1 ELSE 0 END) AS creator_switches
  FROM events_ordered
  GROUP BY session_id
),
switch_final AS (
  SELECT
    sf.session_id,
    COALESCE(sa.evts_distinct, 0)    AS events_in_session_calc_switch,
    COALESCE(sa.creator_switches, 0) AS creator_switches,
    CASE WHEN COALESCE(sa.evts_distinct, 0) <= 1 THEN NULL
         ELSE SAFE_DIVIDE(COALESCE(sa.creator_switches, 0), sa.evts_distinct - 1)
    END AS creator_switch_rate
  FROM `capstone-data-pull.YT_Data.sessions_features_tbl` sf
  LEFT JOIN switch_agg sa USING (session_id)
)
SELECT
  d.*,
  tc.session_top_category,
  tc.session_top_category_share,
  cs.session_category_hhi,
  cs.session_category_entropy,
  cs.session_news_share,
  cs.session_gaming_share,
  pg.prev_session_ts,
  pg.prior_session_gap_s,
  pg.prior_session_gap_capped_s,
  ss.creator_switches,
  ss.events_in_session_calc_switch,
  ss.creator_switch_rate
FROM with_deciles AS d
LEFT JOIN top_cat      AS tc USING (session_id)
LEFT JOIN cat_share    AS cs USING (session_id)
LEFT JOIN prior_gaps   AS pg USING (session_id)
LEFT JOIN switch_final AS ss USING (session_id);
