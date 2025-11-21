
## About
`01_watch_events_fe` creates a clean, feature-rich view of YouTube watch events for analysis and dashboards.  
It normalizes timestamps, computes elapsed seconds, sessionizes viewing behavior, derives binge/high-cuts flags, and applies playback speed rules to help interpret “time watched” consistently across periods.

`02_sessions_features_tbl` builds session-level features from YouTube watch events: sessionization (idle gap), wall-time vs content-time consumption (speed-aware), cuts-per-minute, average playback speed, and binge flags (time- or count-based).

`03_weekly_metrics_vw` aggregates session-level YouTube watch behavior into weekly indicators. It reports both wall clock viewing (actual time spent) and speed-aware content time (runtime consumed after accounting for playback speed).

`05_event_features_vw` generates a view of YouTube watch events for analysis and dashboarding. It standardizes time features, computes content-adjusted watch ratios (respecting playback speed and video duration), flags early exits, and bins scene-change rates by category.

`06_session_category_share_long_vw` produces a long-format table of per-session category shares the fraction of each session’s consumed runtime spent in each category. It’s used for downstream content mix visuals and trend analysis.

`07_sessions_enriched_vw` enriches session-level analytics with category concentration, top category share, local-time features (hour, weekend), prior-session gaps, and creator switch rates.

`08_weekly_behavior_vw` is a weekly view used to analyze session and event patterns over time (hours watched, binge rate, cuts per minute, time-of-day mix, etc.).

`09_weekly_category_share_vw` is a weekly category mix view by aggregating content time into Monday-based weeks and returning each category’s minutes and share of total weekly minutes.

`10_top_creators_yearly_vw` computes yearly watch-time leaders by creator, using Pacific Time (PT) year boundaries to better reflect human behavior. Outputs minutes watched, share of year, and multiple tie-aware ranks for flexible charting.

`11_monthly_creator_hhi_vw` monthly rollup of creator concentration and diversity metrics (HHI, effective number of creators, Shannon entropy, normalized indices) from per-event watch time.

`12_event_tags_long_vw` per-event tag lists (from `watch_events_fe.tags_raw`) into a long format—one row per event–tag—after normalizing delimiters, trimming, de-noising characters, lowercasing, and deduplicating.

`13_event_tag_cooccur_vw` computes pairwise tag co-occurrences from event-level tags, with both raw and 30-minute-capped dwell weights so you can rank meaningful tag relationships without long videos dominating.

`14_creator_return_rewatch_weekly_vw` single weekly view that tracks whether viewers return to the same creator within 7 days and how often any video is a rewatch. It exposes both per-creator rows and an overall “ALL_CREATORS” row, plus sanity-check fields (weighted_from_parts) to verify that the overall rate equals a properly weighted mean of per-creator rates.

`15_batch_export_views_to_csv` iterates over a list of view names in a dataset, snapshots each view into a (replaceable) table named `<view>_pub`, exports each table to CSV files in a GCS bucket/prefix and prints a summary of the exported paths.

`16_weekly-validation_checks` BigQuery QC suite validating session-level data and weekly rollups.

## Features
### 01_watch_events_fe
- Typing and parsing for messy `date` and `time` fields (multiple formats, SAFE_* parsing).
- Timezone-aware timestamps (America/Los_Angeles).
- Elapsed seconds parsed from `Elapsed Time` (`hh:mm:ss`, `mm:ss`, or `ss`).
- Playback speed rules (e.g., pre-2024 @ 2×, post-2024 @ 1×) via a simple editable CTE.
- Sessionization using gap thresholds (30 min default) with binge flags (≥45 min or ≥5 videos).
- Category-relative “high-cuts” flag using per-category 75th percentile of cuts/min.
- Use of `SAFE_CAST`, `SAFE_PARSE_*`, and `SAFE_DIVIDE`.
### 02_sessions_features_tbl
- Sessionization with configurable idle gap.
- Wall clock watched seconds with tail capping on the final event.
- Content-time (runtime actually advanced) using playback speed.
- Scaled cuts proportional to content fraction consumed.
- CPM: wall time and content time variants.
- Average playback speed per session.
- Binge flags by time, count, and content-time.
### 03_weekly_metrics_vw
- Weekly rollups with Monday week start and Pacific Time localization.
- Dual time lenses: Wall time (what you actually spent watching). Content time (runtime consumed at your playback speed).
- Binge metrics: rate and time share (both wall time and content-time definitions).
- Cuts/min intensity: unweighted and time-weighted averages (and content-time variants).
- Playback-speed KPI: week-level average playback speed.
- Use of `SAFE_DIVIDE`, `NULLIF`, and rounding for KPI cards.

### 04_data_validation_check (OPTIONAL)
How to read:

**Sessions table health**
- `row_count` should be less than 0
- `negative_time` should be 0
- `zero_time_sessions` should be 0 (a few isn’t bad but you might want to look into it)
- `min_ts/max_ts` should match your overall date range

**Weekly rollup counts match raw sessions**
- `counts_match` should be True for every row. Any False means the bucketing or joins are off

**Weekly hours recompute check**
- `abs_diff` should be 0 (or ≤ 0.01 from rounding). Bigger gaps means aggregation logic is off.

**Weighted vs unweighted cuts**

Some difference is normal. Huge difference (e.g., > 5 CPM) mean a few long sessions dominate; not wrong, just informative.

**Spike finder**

Occasional long sessions (e.g., 6–10h) are possible.

**PT boundary check**

Check that boundary times match up.

### 05_event_features_vw

- `content_elapsed_s` with playback-speed adjustment and duration capping
- `watch_ratio_content` and `watch_ratio_content_quartile` (0–3)
- `early_exit_flag` based on min(60s, 25% of duration)
- `hour_of_day_pt`, `day_of_week_pt`, `is_weekend_pt`, `hour_bin4`
- `cuts_per_min_decile_cat` (0–9) and `cuts_per_min_quintile_cat` (0–4) by category
- `creator_switch_flag` (global previous-event comparison)
- preserves source `gap_from_prev_s_src` plus `recomputed gap_from_prev_s`

### 06_session_category_share_long_vw

- Aggregates event-level content time to session×category.
- Computes per-session shares that sum to ~1.0.
- Null-safe handling of zero-time sessions.

### 08_weekly_behavior_vw
- Stable Monday-based weekly buckets in PT
- Wall-time and time-weighted cuts-per-minute
- Session quality signals (binge, avg session length, playback speed)
- Event quality signals (early exit, creator switches)
- 4-week trailing moving average
- Simple change-point flags for A/B or policy shifts

### 09_weekly_category_share_vw
- `week_start` timestamp; (PT weeks via TIMESTAMP_TRUNC with WEEK(MONDAY))
- `category` string; empty/null categories normalized to (Unknown)
- `minutes_content` float64; category minutes per week, rounded to 2 decimals
- `share_of_week` float64 in [0,1]; category minutes divided by weekly total
- Weeks are bucketed in America/Los_Angeles; the resulting bucket shows as 08:00/07:00 UTC pre/post DST.
- Divisions use SAFE_DIVIDE with a NULLIF guard on totals.
- Minutes are rounded in-view to avoid noisy chart labels

### 10_top_creators_yearly_vw
- PT-aligned year `(EXTRACT(YEAR FROM DATETIME(watch_ts, 'America/Los_Angeles')))`
- Creator cleanup `(TRIM + null/blank to (Unknown))`
- Content minutes rollup + yearly share `(SAFE_DIVIDE)`
- `RANK`, `DENSE_RANK`, and `ROW_NUMBER` for ties

### 11_monthly_creator_hhi_vw
- Month-bucketed (Pacific Time) using TIMESTAMP_TRUNC with timezone
- HHI (unbounded) and normalized HHI (0–1)
- Shannon entropy (nats) and entropy normalized to 0–1
- Top creator + share each month

### 12_event_tags_long_vw
- Normalizes/cleans tags (unifies delimiters, trims, strips brackets/quotes/#, lowercases)
- Explodes to long format (one row per event–tag) and deduplicates per event
- Validates 11-char YouTube video_id and filters blanks to reduce noise
- Preserves engagement fields (watch_ratio_content, early_exit_flag, cuts_per_min) for analysis

### 13_event_tag_cooccur_vw
- Unordered tag pairs per event (no duplicates)
- Tunable stoplist, min tag length, “must contain letters,” min co-occurrence count
- Robust ranking using 30-minute dwell cap

### 14_creator_return_rewatch_weekly_vw
- 7-day creator return rate (per creator and overall)
- Rewatch rate (share of events that are ≥2nd watch of a video)
- Clean event filtering (valid YouTube IDs, positive dwell, non-blank creators)
- Pacific-time weekly bucketing (WEEK(MONDAY), 'America/Los_Angeles')
- Denominators exposed (used vs total) for auditability
- Equality check between the overall rate and weighted per-creator parts

### 16_weekly-validation_checks
Checks:
- Sessions table health: basic sanity flags and time bounds.
- Weekly counts parity: raw sessions vs. weekly_metrics_vw.
- Hours parity: derived hours vs. hours_watched in the view.
- Pace weighting sanity: unweighted vs time-weighted cuts/min (last N weeks).
- Spike finder: outlier sessions (very long or extreme cuts/min).
- PT week bucketing: edge cases around local midnight.

## Installing
### watch_events_fe
This project assumes BigQuery Standard SQL.

1) Clone or copy the folder into your GitHub repo:

2) Edit the dataset references in `watch_events_fe.sql`. Replace:
- `YOUR_PROJECT_ID`
- `YOUR_DATASET`  
…and ensure your source table `cleaned_data` exists (this is your cleaned Takeout+enrichment table).

### sessions_features_tbl
Copy the SQL file into your repo, e.g. `sql/sessions_features.sql`.

Set environment replacements when running (or find/replace in the file):

`${PROJECT}` - your GCP project id

`${DATASET}` - your BigQuery dataset

Ensure the source table exists:

`${PROJECT}.${DATASET}.watch_events_fe` with columns:

`watch_ts` `TIMESTAMP`

`video_id` `STRING`

`duration_meta_s` `FLOAT64` (or `INT64`)

`cuts_total` `FLOAT64` (or `INT64`)

`playback_speed` `FLOAT64`

## How it works
### watch_events_fe
- speed_rules — central place to declare playback speed by date range (editable).
- base — normalize types (watch_date, watch_time, numeric casts with SAFE_CAST).
- typed — build watch_ts in America/Los_Angeles.
- elapsed — parse Elapsed Time into elapsed_s.
- features — row-level metrics: watch ratio, hour/dow, new session flag, playback_speed (from rules).
- sessions — first-pass session IDs using a 30-minute gap.
- sessionized — windowed session totals & binge flags.
- cuts_flags — category-relative 75th percentile to mark high_cuts_flag.
- final SELECT — keep original column names (after safe casting) for compatibility.
### sessions_features_tbl
- params: tune idle_s, tail_cap_s, binge_time_s, binge_count_min.
- watched_s: wall-clock seconds for each event, capped by gap to next event (or tail cap) and by duration_meta_s.
- consumed_runtime_s: speed-aware content time = watched_s * playback_speed, capped by duration_meta_s.
- cuts_watched: scales cuts_total by the content fraction consumed.
- sessionization: cumulative sum of is_new_session to assign session_id.
- aggregates: per session rollups; derived metrics for CPM & flags.
### weekly_metrics_vw
- Truncates each session to a Monday-starting week localized to America/Los_Angeles.
- Brings in session features:

`session_total_time_s` (wall time in seconds)

`session_consumed_runtime_s` (content time in seconds; speed-aware)

`session_mean_cuts_per_min` (+ _content)

`session_avg_playback_speed`

- Binge flags for wall-time and content-time definitions.
- Aggregations (GROUP BY `week_start`)
- Wall-time KPIs: `hours watched`, `count of sessions`, `binge rate`, `time-weighted cuts/min`, `avg session minutes`, `binge time share`.
- Content-time KPIs: `hours consumed`, `avg playback speed`, `binge rate (content)`, `binge time share (content)`, `cuts/min (unweighted & time-weighted using session_consumed_runtime_s)`.

If you watched at ~2× for long periods and later at 1×. Analysts could misread “time watched” without knowing this context. Explicit rules make that assumption visible and auditable.

### event_featurs_vw
- Input table watch_events_fe supplies raw events augmented with playback speed and cuts_per_min.
- Enforce deterministic ordering by (watch_ts, video_id) and keep both the source gap and a recomputed global gap.
- Content time is min(duration_meta_s, elapsed_s × playback_speed).
- Early exits are those with content time ≤ min(60s, 25% of duration).
- Derived local-time features using the provided timezone.
- Rank cuts_per_min within each category to produce deciles and quintiles.
- Create a simple 4-bucket hour_bin4 for easy day-part analysis.

### sessions_enriched_vw
- Adds sessions with local-time features: start hour, day-of-week, weekend flag.
- Category mix metrics: HHI (concentration) and Shannon entropy (diversity).
- Identifies top category and its share per session.
- Adds prior-session gap metrics (raw and 6-hour capped).
- Ranks sessions into deciles (0–9) by cuts/min (wall time and content-time variants).
- Creator-switch rate using a deduped, time-contributing event stream.
- Uses safe numerics (SAFE_DIVIDE) and clear tie-breaks for deterministic results.

### batch_export_views_to_csv
- What it does: Iterates a view list, snapshots to `<view>_pub` tables, exports each to CSV shards in GCS, prints a summary of paths.
- Customize: edit `v_project`, `v_dataset`, `v_gcs_uri`, and the `v_views` array. Optional: set `v_compression` to `'GZIP'`.
- Run it:

  `bq query --use_legacy_sql=false < bq_export_views_to_gcs.sql`

- Typical IAM you’ll need: BigQuery Job User on the project, BigQuery Data Viewer (or above) on the dataset and Storage Object Creator (or above) on the destination bucket.

### weekly-validation_checks
- Open the script in BigQuery.
- Edit variables in the CONFIG block (project, dataset, table/view names, time zone).
- Run all. Each block returns a result set you can export or screenshot for PRs.
  
## Variable Tables
### Variables used as input

| Variable                                   | Type         | How it’s made / parsed                                                                 | What it’s for                               | Example            |
|---                                         |---           |---                                                                                      |---                                           |---                 |
| `date`                                     | DATE/STRING  | Parsed to DATE in `watch_events_fe` via `SAFE_CAST` / `SAFE.PARSE_DATE`                | Calendar day of the watch event              | `4/1/19`           |
| `time`                                     | TIME/STRING  | Parsed to TIME via multiple `SAFE.PARSE_TIME` formats                                   | Clock time of the watch event                | `11:23:06 AM`      |
| `Elapsed Time`                              | STRING       | Later converted to seconds (supports `HH:MM:SS` / `MM:SS` / `SS`)                       | Approx. time spent before next event         | `0:12:34`          |
| `video_id`                                  | STRING       | As-is                                                                                   | Deterministic ordering / tie-breaks          | `eO0nX0eZ0mw`      |
| `duration_meta_s`                           | NUM (sec)    | Cast to `FLOAT64`                                                                       | Video runtime from metadata                  | `600`              |
| `cuts_total`                                | INT          | Cast to `INT64`                                                                         | Total hard cuts per video                    | `180`              |
| `cuts_per_min`                              | NUM          | Cast to `FLOAT64`                                                                       | Cuts per minute from source                  | `18`               |
| `gap_prev_s`                                | INT          | Cast to `INT64`                                                                         | Idle gap since prior event                   | `95`               |
| `category`                                  | STRING       | As-is                                                                                   | For category-relative flags                  | `News & Politics`  |
| `view_count`, `like_count`, `duration_cut_s`| INT/NUM      | Cast to `INT64` / `FLOAT64`                                                             | Optional descriptive stats                   | `250913`, `2444`, `589.1` |

### Variables output as feature engineered watch events 

| Variable                                   | Type     | How it’s made / formula (BigQuery)                                                                                                                                          | What it’s for                                           | Example                           |
|---                                          |---       |---                                                                                                                                                                           |---                                                     |---                                |
| `watch_date`                                | DATE     | From `date` via `SAFE_CAST` / `SAFE.PARSE_DATE`                                                                                                                             | Normalized date                                         | `4/1/19`                          |
| `watch_time`                                | TIME     | From `time` via `SAFE_CAST` / `SAFE.PARSE_TIME`                                                                                                                             | Normalized time                                         | `23:15:42`                        |
| `watch_ts`                                  | TIMESTAMP| `TIMESTAMP(DATETIME(watch_date, IFNULL(watch_time, TIME '00:00:00')), 'America/Los_Angeles')`                                                                               | PT-localized event timestamp                            | `2019-04-01 23:15:42-07:00`       |
| `elapsed_s`                                 | INT      | Length-aware split of `Elapsed Time` → seconds (supports `HH:MM:SS` / `MM:SS` / `SS`)                                                                                       | Approx. seconds actually watched before next event      | `754`                              |
| `raw_watch_ratio`                           | FLOAT    | `elapsed_s / duration_meta_s`                                                                                                                                               | Actual watch ÷ runtime                                  | `1.26`                             |
| `watch_ratio`                               | FLOAT    | `LEAST(1.2, raw_watch_ratio)`                                                                                                                                               | Capped ratio for robustness                             | `1.2`                              |
| `hour_of_day`                               | INT      | `EXTRACT(HOUR FROM watch_ts)`                                                                                                                                                | Diurnal patterns                                        | `23`                               |
| `dow`                                       | INT      | `EXTRACT(DAYOFWEEK FROM watch_ts)` (1=Sun)                                                                                                                                  | Day-of-week patterns                                    | `2`                                |
| `new_session_flag`                          | BOOL     | `gap_prev_s > 1800`                                                                                                                                                         | 30-min session break marker                             | `FALSE`                            |
| `session_id` *(first pass)*                 | INT      | `SUM(CASE WHEN new_session_flag OR gap_prev_s IS NULL THEN 1 ELSE 0 END) OVER (ORDER BY watch_ts, video_id)`                                                               | Coarse session buckets *(not used downstream after v2)* | `1022`                             |
| `session_total_time_s` *(first pass)*       | INT      | Window `SUM(elapsed_s)` over first-pass `session_id`                                                                                                                        | Coarse session duration                                 | `5400`                             |
| `session_video_count` *(first pass)*        | INT      | Window `COUNT(*)` over first-pass `session_id`                                                                                                                              | Coarse session size                                     | `7`                                |
| `session_mean_cuts_per_min` *(first pass)*  | FLOAT    | Window `AVG(cuts_per_min)` over first-pass `session_id`                                                                                                                     | Coarse session CPM                                      | `13.3`                             |
| `binge_time_flag` *(first pass)*            | BOOL     | `SUM(elapsed_s) >= 45*60` over first-pass `session_id`                                                                                                                      | Coarse binge by time                                    | `TRUE`                             |
| `binge_count_flag` *(first pass)*           | BOOL     | `COUNT(*) >= 5` over first-pass `session_id`                                                                                                                                | Coarse binge by count                                   | `TRUE`                             |
| `cuts_q75_cat`                              | FLOAT    | `PERCENTILE_CONT(cuts_per_min, 0.75) OVER (PARTITION BY category)`                                                                                                          | Category baseline (75th pct CPM)                        | `21.5`                             |
| `high_cuts_flag`                            | BOOL     | `cuts_per_min >= cuts_q75_cat`                                                                                                                                              | High-intensity content flag                             | `FALSE`                            |
| *Recast numerics*                           | —        | Internal `_i` / `_f` casts mapped back to original names (e.g., `gap_prev_s_i → gap_prev_s`)                                                                                | Clean numeric schema                                    | `gap_prev_s = 95`                  |
| `playback_speed`                            | FLOAT64  | From speed rules by `watch_date`; defaults to `1.0`. Example rule: everything before `2024-09-01` at `2.0`.                                                             | Playback speed applied to the event                     | `2`                                |

### Variables output as session features 

| Variable                              | Type     | How it’s made / formula (BigQuery)                                                                                             | What it’s for                                                     | Example                          |
|---                                     |---       |---                                                                                                                              |---                                                                |---                               |
| `session_id`                           | INT      | `SUM(CASE WHEN is_new_session THEN 1 ELSE 0 END) OVER (ORDER BY event_idx)`                                                     | Stable session key                                                | `13457`                          |
| `session_start_ts`                     | TIMESTAMP| `MIN(watch_ts) OVER (PARTITION BY session_id)`                                                                                  | Session start (PT/UTC timestamp)                                  | `2019-04-01 20:31:00-07:00`      |
| `events_in_session`                    | INT      | `COUNT(*) OVER (PARTITION BY session_id)`                                                                                       | Number of events in the session                                   | `7`                               |
| `session_total_time_s`                 | INT      | `SUM(watched_s) OVER (PARTITION BY session_id)` where `watched_s = LEAST(gap_to_next_s, duration_meta_s)` (cap tail)            | Actual seconds watched in session                                 | `5400`                           |
| `session_cuts_watched_total`           | FLOAT64  | `SUM(cuts_total * watched_s / duration_meta_s) OVER (PARTITION BY session_id)`                                                  | Cuts scaled by fraction actually watched                          | `1200`                           |
| `session_mean_cuts_per_min`            | FLOAT64  | `SAFE_DIVIDE(session_cuts_watched_total, session_total_time_s/60.0)`                                                            | Session-level CPM (cuts per wall-minute)                          | `13.33`                          |
| `binge_time_flag`                      | BOOL     | `session_total_time_s >= 7200`                                                                                                  | ≥ 2 hours watched                                                 | `FALSE`                          |
| `binge_count_flag`                     | BOOL     | `events_in_session >= 6`                                                                                                        | ≥ 6 events                                                        | `TRUE`                           |
| `session_consumed_runtime_s`           | FLOAT64  | `SUM(consumed_runtime_s) OVER (PARTITION BY session_id)`                                                                        | “Content time” advanced (capped at each video’s runtime)          | `1575` s                         |
| `session_mean_cuts_per_min_content`    | FLOAT64  | `SAFE_DIVIDE(session_cuts_watched_total, session_consumed_runtime_s/60.0)`                                                      | CPM per content minute (creator pacing; speed-invariant)      | `11.14 cuts/min`                 |
| `session_avg_playback_speed`           | FLOAT64  | `SAFE_DIVIDE(session_consumed_runtime_s, session_total_time_s)`                                                                 | Speed-weighted average playback speed for the session             | `1.5`                            |
| `binge_time_flag_content`              | BOOL     | `session_consumed_runtime_s >= 7200`                                                                                            | Content-based binge flag (parallel to wall-time binge)            | `FALSE`                          |
| `consumed_runtime_s` *(per event, temp)* | FLOAT64| `LEAST(duration_meta_s, watched_s * playback_speed)`                                                                            | Temp per-event field used for session aggregates              | `—`                              |
| `cuts_watched` *(per event, temp)*     | FLOAT64  | `SAFE_MULTIPLY(cuts_total, SAFE_DIVIDE(consumed_runtime_s, duration_meta_s))`                                                   | Temp per-event field scaling cuts by content fraction consumed | `—`                              |

                         
### Variables output as weekly metrics

| Variable                                   | Type         | How it’s made / formula (BigQuery)                                                                                                  | What it’s for                                                     | Example |
|---                                         |---           |---                                                                                                                                  |---                                                                 |---|
| `week_start`                               | TIMESTAMP    | `TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles')`                                                            | Week bucket in PT (renders ~08:00/07:00 UTC pre/post DST)         | `2019-04-01 07:00:00 UTC` |
| `hours_watched`                            | FLOAT (h)    | `SUM(session_total_time_s) / 3600`                                                                                                  | Total watch time that week                                        | `10.9` |
| `sessions`                                 | INT          | `COUNT(*)`                                                                                                                          | Number of sessions that week                                      | `30` |
| `binge_rate`                               | FLOAT (0–1)  | `COUNTIF(binge_time_flag OR binge_count_flag) / COUNT(*)`                                                                           | Share of sessions flagged as binge (time or count)                | `0.3` |
| `mean_cuts_per_min_unweighted`             | FLOAT        | `AVG(session_mean_cuts_per_min)`                                                                                                    | Simple average CPM across sessions                                | `26.34` |
| `mean_cuts_per_min_time_weighted`          | FLOAT        | `SUM(session_mean_cuts_per_min * session_total_time_s) / SUM(session_total_time_s)`                                                 | Time-weighted CPM (longer sessions count more)                    | `19.56` |
| `avg_session_min`                          | FLOAT (min)  | `SUM(session_total_time_s) / COUNT(*) / 60`                                                                                         | Average session length                                            | `21.8` |
| `binge_time_share`                         | FLOAT (0–1)  | `SUM(CASE WHEN binge_time_flag OR binge_count_flag THEN session_total_time_s ELSE 0 END) / SUM(session_total_time_s)`               | Share of weekly watch time spent in binge sessions                | `0.42` |
| `hours_consumed`                           | FLOAT64 (h)  | `SUM(session_consumed_runtime_s) / 3600`                                                                                            | Content hours advanced (≥ hours_watched when average speed > 1)   | `20.55` |
| `avg_playback_speed`                       | FLOAT64      | `SUM(session_consumed_runtime_s) / SUM(session_total_time_s)`                                                                       | Sanity check: approximately hours_consumed / hours_watched        | `1.256` |
| `binge_rate_content`                       | FLOAT64      | `COUNTIF(binge_time_flag_content OR binge_count_flag) / COUNT(*)`                                                                   | Share of sessions binge by content time or event count            | `0.271` |
| `binge_time_share_content`                 | FLOAT64      | `SUM(CASE WHEN binge_time_flag_content THEN session_consumed_runtime_s ELSE 0 END) / SUM(session_consumed_runtime_s)`               | Fraction of weekly content time in binge sessions                 | `0.589` |
| `mean_cuts_per_min_unweighted_content`     | FLOAT64      | `AVG(session_mean_cuts_per_min_content)`                                                                                            | Simple average across sessions using content-minute CPM           | `21.74` |
| `mean_cuts_per_min_time_weighted_content`  | FLOAT64      | `SUM(session_mean_cuts_per_min_content * session_consumed_runtime_s) / SUM(session_consumed_runtime_s)`                             | Content-time weighted CPM                                         | `15.2` |


### Variables output as event features

| Variable                     | Type                  | How it’s made / parsed                                                                   | What it’s for                                  | Example                 |
| ---------------------------- | --------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------- | ----------------------- |
| session_id                   | INT64                 | from `watch_events_fe`                                                                   | groups events into sessions                    | 1847362                 |
| watch_ts                     | TIMESTAMP             | carried from source                                                                      | global event ordering; local-time features     | 2021-04-08 11:21:14 UTC |
| prev_watch_ts_global         | TIMESTAMP             | `LAG(watch_ts)` over global kept stream                                                  | audit: prior kept event time (global)          | 2021-04-08 11:19:39 UTC |
| video_id                     | STRING                | `NULLIF(video_id,'#NAME?')`                                                              | deterministic tie-breaks in ordering           | eO0nX0eZ0mw             |
| creator                      | STRING                | as-is                                                                                    | creator-level flags & switch detection         | CNBC                    |
| category                     | STRING                | as-is                                                                                    | category-relative deciles/bins                 | News & Politics         |
| duration_meta_s              | FLOAT64 (sec)         | from metadata                                                                            | caps speed-aware progress; runtime denominator | 600                     |
| elapsed_s                    | FLOAT64 (sec)         | from source (wall-clock)                                                                 | base “time spent” before next event            | 156                     |
| playback_speed               | FLOAT64               | `COALESCE(playback_speed, 1.0)`                                                          | adjusts progress for 1.25×/2×                  | 2                       |
| cuts_per_min                 | FLOAT64               | from source                                                                              | pace/tempo proxy                               | 18                      |
| high_cuts_flag               | BOOL                  | `COALESCE(high_cuts_flag, FALSE)`                                                        | quick filter for high-tempo content            | TRUE                    |
| gap_from_prev_s              | INT64 (sec)           | `TIMESTAMP_DIFF(watch_ts, LAG(watch_ts), SECOND)` on kept stream                         | idle gap since previous kept event (global)    | 95                      |
| gap_from_prev_s_src          | INT64 (sec)           | upstream `gap_prev_s` (pre-filter)                                                       | audit: original gap before filtering           | 87                      |
| rn_in_session                | INT64                 | `ROW_NUMBER()` within `session_id` by time                                               | position of event within session               | 1                       |
| is_new_session               | BOOL                  | `ROW_NUMBER()=1` within session (kept stream)                                            | marks first kept event of a session            | TRUE                    |
| is_new_session_src           | BOOL                  | upstream `new_session_flag`                                                              | audit: original session-start flag             | FALSE                   |
| content_elapsed_s            | FLOAT64 (sec)         | `LEAST(duration_meta_s, elapsed_s * playback_speed)`                                     | speed-aware progress, capped at runtime        | 300                     |
| watch_ratio_content          | FLOAT64 (0–1)         | `content_elapsed_s / NULLIF(duration_meta_s, 0)`                                         | share of the video effectively advanced        | 0.5                     |
| early_exit_flag              | BOOL                  | `content_elapsed_s <= LEAST(60, 0.25*duration_meta_s)`                                   | flags “left early” (≤60s or ≤25%)              | TRUE                    |
| hour_of_day_pt               | INT64 (0–23)          | `EXTRACT(HOUR FROM DATETIME(watch_ts,'America/Los_Angeles'))`                            | local-hour analyses (PT)                       | 23                      |
| day_of_week_pt               | INT64 (1–7)           | `EXTRACT(DAYOFWEEK FROM DATETIME(watch_ts,'America/Los_Angeles'))`                       | day-of-week analyses (PT)                      | 6                       |
| is_weekend_pt                | BOOL                  | `day_of_week_pt IN (1,7)`                                                                | weekend filter (Sun/Sat in PT)                 | TRUE                    |
| cuts_per_min_decile_cat      | INT64 (0–9)           | `NTILE(10)` by `category` on `cuts_per_min` minus 1                                      | category-relative decile (0=low)               | 7                       |
| cuts_per_min_quintile_cat    | INT64 (0–4)           | `NTILE(5)` by `category` on `cuts_per_min` minus 1                                       | category-relative quintile (0–4)               | 3                       |
| hour_bin4                    | INT64 (0–3)           | case on PT hour: 0=0–5, 1=6–11, 2=12–17, 3=18–23                                         | coarser time-of-day grouping                   | 3                       |
| creator_switch_flag          | BOOL                  | `creator != LAG(creator)` over global kept order                                         | marks switches between creators across events  | TRUE                    |
| watch_ratio_content_quartile | INT64 (0–3, nullable) | case on `watch_ratio_content` (<0.25→0, <0.50→1, <0.75→2, else 3); null if ratio is null | coarse completion buckets                      | 1                       |


### Variables output as session category share long view

| Variable   | Type                       | How it’s made / parsed                                                                           | What it’s for                              | Example         |
| ---------- | -------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------ | --------------- |
| session_id | INT64/STRING (your schema) | Inherited from events (or stamped onto event_features_vw in Option A)                            | Join key to session-level tables           | 20200415_0031   |
| category   | STRING                     | From events, grouped per session                                                                 | Category mix within a session              | News & Politics |
| share      | FLOAT64 (0–1)              | SUM(content_elapsed_s) per (session, category) ÷ SUM(content_elapsed_s) per session; SAFE_DIVIDE | Fraction of session spent in that category | 0.37            |

### Variables output as sessions enriched view

| Variable                            | Type                             | How it’s made / parsed                                                                                                                                                               | What it’s for                                                                                                                          | Example                 |
| ----------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| session_start_hour                  | INT64 (0–23)                     | EXTRACT(HOUR FROM DATETIME(session_start_ts, 'America/Los_Angeles'))                                                                                                                 | Local-hour analyses (PT)                                                                                                               | 11                      |
| session_dow                         | INT64 (1–7)                      | EXTRACT(DAYOFWEEK FROM DATETIME(session_start_ts, 'America/Los_Angeles')) (Sun=1, Sat=7)                                                                                             | Day-of-week analyses (PT)                                                                                                              | 5                       |
| session_is_weekend                  | BOOL                             | session_dow IN (1, 7)                                                                                                                                                                | Weekend filter                                                                                                                         | TRUE                    |
| session_category_hhi                | FLOAT64 (0–1)                    | From session_category_share_long_vw: SUM(share*share) per session                                                                                                                    | Concentration (higher = dominated by few categories)                                                                                   | 0.62                    |
| session_category_entropy            | FLOAT64 (≥0)                     | From session_category_share_long_vw: -SUM(IF(share > 0, share*LOG(share), 0))                                                                                                        | Diversity (higher = more mixed; ≤ ln(#cats with share>0))                                                                              | 0.89                    |
| session_news_share*                 | FLOAT64 (0–1)                    | MAX(IF(category = 'News & Politics', share, 0))                                                                                                                                      | Optional named share                                                                                                                   | 0.22                    |
| session_gaming_share*               | FLOAT64 (0–1)                    | MAX(IF(category = 'Gaming', share, 0))                                                                                                                                               | Optional named share                                                                                                                   | 0.10                    |
| session_top_category                | STRING                           | From session_category_share_long_vw; ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY share DESC, category) = 1                                                                   | “What was this session mostly about?” (deterministic ties)                                                                             | Technology              |
| session_top_category_share          | FLOAT64 (0–1)                    | Share corresponding to session_top_category                                                                                                                                          | Strength of top category                                                                                                               | 0.55                    |
| session_cuts_per_min_decile         | INT64 (0–9)                      | NTILE(10) OVER (ORDER BY session_mean_cuts_per_min) - 1                                                                                                                              | Tempo rank bucket (wall-time)                                                                                                          | 7                       |
| session_cuts_per_min_content_decile | INT64 (0–9)                      | NTILE(10) OVER (ORDER BY session_mean_cuts_per_min_content) - 1                                                                                                                      | Tempo rank bucket (content-aware)                                                                                                      | 6                       |
| session_id                          | INT64                            | Unique key per session from sessions_features_tbl                                                                                                                                    | Joins to other session views                                                                                                           | 1847362                 |
| session_start_ts                    | TIMESTAMP                        | First event timestamp in the session (UTC)                                                                                                                                           | Session start time; PT features derive from this                                                                                       | 2025-04-25 23:45:13 UTC |
| events_in_session                   | INT64                            | COUNT(*) of events in the session                                                                                                                                                    | Session length by count                                                                                                                | 9                       |
| session_total_time_s                | FLOAT64 (seconds)                | Sum of per-event dwell time; dwell_s = LEAST(gap_to_next_s, tail_cap_s) (default tail_cap_s = 600)                                                                                   | Total wall-clock time attributed to the session                                                                                        | 4320                    |
| session_consumed_runtime_s          | FLOAT64 (seconds)                | Sum of per-event content-aware time (speed-aware), i.e., content_elapsed_s aggregated to session                                                                                     | Total content-advanced time                                                                                                            | 3890                    |
| session_cuts_watched_total          | FLOAT64                          | Sum over events of estimated cuts seen (e.g., watch_ratio_content * cuts_total)                                                                                                      | Approximate total “cuts” encountered                                                                                                   | 210.4                   |
| session_mean_cuts_per_min           | FLOAT64                          | Time-weighted mean of cuts_per_min using dwell weights                                                                                                                               | Session tempo (wall-time)                                                                                                              | 14.6                    |
| session_mean_cuts_per_min_content   | FLOAT64                          | Time-weighted mean of cuts_per_min using content_elapsed_s weights                                                                                                                   | Session tempo (content-aware)                                                                                                          | 13.9                    |
| session_avg_playback_speed          | FLOAT64                          | Weighted avg of playback_speed (weight = content_elapsed_s)                                                                                                                          | Typical playback speed used in session                                                                                                 | 1.3                     |
| binge_time_flag                     | BOOL                             | session_total_time_s ≥ binge_time_s (default 7200)                                                                                                                                   | Long session by wall-time                                                                                                              | TRUE                    |
| binge_count_flag                    | BOOL                             | events_in_session ≥ binge_count_min (default 6)                                                                                                                                      | Many events in one session                                                                                                             | FALSE                   |
| binge_time_flag_content             | BOOL                             | session_consumed_runtime_s ≥ binge_time_s                                                                                                                                            | Long session by content advanced                                                                                                       | TRUE                    |
| prev_session_ts                     | TIMESTAMP                        | LAG(session_start_ts) OVER (ORDER BY session_start_ts) (UTC)                                                                                                                         | Start time of the previous session; basis for gap calcs                                                                                | 2025-04-25 21:10:00 UTC |
| prior_session_gap_s                 | INT64 (seconds)                  | TIMESTAMP_DIFF(session_start_ts, prev_session_ts, SECOND)                                                                                                                            | True elapsed time between prior session end and this session start                                                                     | 940                     |
| prior_session_gap_capped_s          | INT64 (seconds)                  | LEAST(prior_session_gap_s, 6*3600)                                                                                                                                                   | Robust, winsorized gap (caps extreme gaps at 6h = 21,600s)                                                                             | 21600                   |
| events_in_session_calc_switch       | INT64                            | Count of deduped, time-contributing events from event_features_vw: keep rows with content_elapsed_s > 0; QUALIFY ROW_NUMBER() OVER (PARTITION BY session_id, watch_ts, video_id) = 1 | Aligned event count for creator-switch metrics; denominator for bounded rate; compare to events_in_session to see pipeline differences | 5                       |
| creator_switches                    | INT64                            | On ordered, deduped stream (ORDER BY watch_ts, video_id), count transitions where creator ≠ LAG(creator); NULLs treated as no switch                                                 | Numerator for switch behavior: how often you change creators within a session                                                          | 3                       |
| creator_switch_rate                 | FLOAT64 (0–1; NULL if ≤ 1 event) | SAFE_DIVIDE(creator_switches, events_in_session_calc_switch - 1) on the same deduped stream                                                                                          | Bounded probability of switching creators between consecutive videos in a session (higher = more variety-seeking)                      | 0.75                    |

### Variables output as weekly behavior
| Variable                        | Type                             | How it’s made / parsed                                                                                             | What it’s for                               | Example                 |
| ------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- | ----------------------- |
| week_start                      | TIMESTAMP (PT weeks)             | TIMESTAMP_TRUNC(session_start_ts, WEEK(MONDAY), 'America/Los_Angeles')                                             | Week grain for all weekly charts            | 2019-02-18 08:00:00 UTC |
| hours_watched                   | FLOAT64 (hours)                  | ROUND(SUM(session_total_time_s) / 3600.0, 2)                                                                       | Total real watch time per week              | 12.07                   |
| sessions                        | INT64                            | COUNT(*) over sessions_features_tbl grouped by week                                                                | Weekly session count                        | 39                      |
| binge_rate                      | FLOAT64 (0–1)                    | ROUND(SAFE_DIVIDE(SUM(CASE WHEN binge_time_flag OR binge_count_flag THEN 1 ELSE 0 END), COUNT(*)), 3)              | Share of sessions classified as binge       | 0.24                    |
| mean_cuts_per_min_unweighted    | FLOAT64                          | ROUND(AVG(session_mean_cuts_per_min), 2)                                                                           | Simple average pacing across sessions       | 10.49                   |
| mean_cuts_per_min_time_weighted | FLOAT64                          | ROUND(SAFE_DIVIDE(SUM(session_mean_cuts_per_min * session_total_time_s), NULLIF(SUM(session_total_time_s), 0)), 2) | Time-weighted pacing across sessions        | 9.44                    |
| avg_session_min                 | FLOAT64 (minutes)                | SAFE_DIVIDE(SUM(session_total_time_s), NULLIF(COUNT(*), 0)) / 60.0                                                 | Average session length (real time)          | 17.8                    |
| avg_playback_speed              | FLOAT64                          | SAFE_DIVIDE(SUM(session_consumed_runtime_s), NULLIF(SUM(session_total_time_s), 0))                                 | Average playback speed per week             | 1.18                    |
| early_exit_rate                 | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN early_exit_flag THEN 1 ELSE 0 END), COUNT(*)) on event_features_vw per week              | Share of events that were early exits       | 0.31                    |
| high_cuts_event_rate            | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN high_cuts_flag THEN 1 ELSE 0 END), COUNT(*)) on event_features_vw per week               | Share of events with high pacing            | 0.12                    |
| creator_switch_rate             | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN creator_switch_flag THEN 1 ELSE 0 END), COUNT(*)) on event_features_vw per week          | Share of events that switch creators        | 0.47                    |
| mean_watch_ratio_content        | FLOAT64 (0–1)                    | AVG(watch_ratio_content) across events per week                                                                    | Average share of content consumed per event | 0.42                    |
| share_hour_bin0                 | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 0 THEN 1 ELSE 0 END), COUNT(*))                                              | Share of events 00:00–05:59 PT              | 0.06                    |
| share_hour_bin1                 | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 1 THEN 1 ELSE 0 END), COUNT(*))                                              | Share of events 06:00–11:59 PT              | 0.18                    |
| share_hour_bin2                 | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 2 THEN 1 ELSE 0 END), COUNT(*))                                              | Share of events 12:00–17:59 PT              | 0.34                    |
| share_hour_bin3                 | FLOAT64 (0–1)                    | SAFE_DIVIDE(SUM(CASE WHEN hour_bin4 = 3 THEN 1 ELSE 0 END), COUNT(*))                                              | Share of events 18:00–23:59 PT              | 0.42                    |
| hours_watched_ma4               | FLOAT64 (hours)                  | 4-week moving average of hours_watched using WINDOW ROWS BETWEEN 3 PRECEDING AND CURRENT ROW                       | Smoothing for trend lines                   | 8.28                    |
| post_intervention               | BOOL                             | DATE(week_start) >= DATE '2023-11-01'                                                                              | Segment pre/post change                     | TRUE                    |
| weeks_since_intervention        | INT64 (can be negative pre-date) | DATE_DIFF(DATE(week_start), DATE '2023-11-01', WEEK)                                                               | Relative week index for analysis            | 12                      |

### Variables output as weekly category share

| Variable        | Type                 | How it's made / parsed                                                | What it's for                                               | Example                 |
| --------------- | -------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------- | ----------------------- |
| week_start      | TIMESTAMP (PT weeks) | TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles')        | Week grain for category shares                              | 2019-02-18 08:00:00 UTC |
| category        | STRING               | COALESCE(NULLIF(TRIM(category), ''), '(Unknown)')                     | Category label per YouTube metadata                         | News & Politics         |
| minutes_content | FLOAT64 (minutes)    | SUM(content_elapsed_s)/60 by (week_start, category)                   | Total content minutes watched for that category in the week | 124.33                  |
| share_of_week   | FLOAT64 (0–1)        | minutes_content / SUM(minutes_content) OVER (PARTITION BY week_start) | Fraction of weekly content time by category                 | 0.37                    |

### Variables output as top creators yearly

| Variable           | Type                   | How it's made / parsed                                                           | What it's for                                          | Example         |
| ------------------ | ---------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------- |
| year               | INT64 (PT year)        | EXTRACT(YEAR FROM DATETIME(watch_ts, 'America/Los_Angeles'))                     | Annual aggregation anchor (Pacific Time)               | 2019            |
| creator            | STRING                 | COALESCE(NULLIF(TRIM(creator), ''), '(Unknown)') from event_features_vw          | Grouping dimension for per-creator rollups             | Linus Tech Tips |
| minutes_content    | FLOAT64 (minutes)      | SUM(content_elapsed_s)/60 by (year, creator)                                     | Total content minutes watched for creator in that year | 1462.33         |
| share_of_year      | FLOAT64 (0–1)          | minutes_content ÷ SUM(minutes_content) over the same year (SAFE_DIVIDE)          | Creator’s fraction of annual content minutes           | 0.0731          |
| rank_in_year       | INT64 (1=most minutes) | RANK() OVER (PARTITION BY year ORDER BY minutes_content DESC)                    | Creator rank within year; ties share the same rank     | 2               |
| dense_rank_in_year | INT64                  | DENSE_RANK() OVER (PARTITION BY year ORDER BY minutes_content DESC)              | Like rank, but without gaps between ties               | 2               |
| rownum_tiebreak    | INT64                  | ROW_NUMBER() OVER (PARTITION BY year ORDER BY minutes_content DESC, creator ASC) | Stable ordering to break ties deterministically        | 2               |

### Variables output as monthly creator hhi

| Variable           | Type                  | How it's made / parsed                                           | What it's for                                                                    | Example                 |
| ------------------ | --------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------- |
| month_start        | TIMESTAMP (PT months) | TIMESTAMP_TRUNC(watch_ts, MONTH, 'America/Los_Angeles')          | Monthly grain for creator concentration metrics                                  | 2019-03-01 08:00:00 UTC |
| creator_count      | INT64                 | COUNT(*) creators in the month after computing shares            | Number of distinct creators with >0 minutes in month (K)                         | 278                     |
| hhi_creator        | FLOAT64 (0–1]         | SUM(share * share) over creators in month                        | Herfindahl–Hirschman Index of creator concentration (higher = more concentrated) | 0.016224                |
| effective_creators | FLOAT64 (≥1)          | 1.0 / hhi_creator                                                | “Effective” number of equally sized creators; intuitive diversity proxy          | 61.6                    |
| entropy_nats       | FLOAT64 (≥0)          | −SUM(share * LN(share))                                          | Shannon entropy of the monthly creator distribution (higher = more diverse)      | 4.13                    |
| entropy_norm_0_1   | FLOAT64 [0–1]         | SAFE_DIVIDE(entropy_nats, LN(creator_count))                     | Entropy normalized to [0,1] given K creators (1 = perfectly uniform)             | 0.86                    |
| hhi_norm_0_1       | FLOAT64 [0–1]         | SAFE_DIVIDE(hhi_creator − 1/K, 1 − 1/K), K = creator_count       | HHI normalized to [0,1] given K creators (0 = uniform, 1 = monopoly)             | 0.14                    |
| top_creator        | STRING                | Creator with max share (ROW_NUMBER over share DESC, creator ASC) | Label of most-watched creator that month                                         | Linus Tech Tips         |
| top_share          | FLOAT64 [0–1]         | Max share for month (share of top_creator)                       | Share of total monthly content minutes from top creator                          | 0.07                    |

### Variables output as event tags long

| Variable            | Type               | How it’s made / parsed                                                                                                                                                                                                     | What it’s for                                                         | Example                 |
| ------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ----------------------- |
| watch_ts            | TIMESTAMP (UTC)    | From `event_features_vw` (joined to `watch_events_fe` on `(watch_ts, video_id)`)                                                                                                                                           | Event timestamp to align back to events/sessions                      | 2024-04-16 00:03:13 UTC |
| session_id          | INT64              | From `event_features_vw`                                                                                                                                                                                                   | Join key to session-level tables                                      | 1847362                 |
| video_id            | STRING (11 chars)  | From `event_features_vw`; valid YouTube IDs enforced via `REGEXP_CONTAINS(video_id, r'^[A-Za-z0-9_-]{11}$')`                                                                                                               | Join key to video/event dimensions; prevents bad IDs (e.g., `#NAME?`) | XWzEVrRBrXU             |
| creator             | STRING             | From `event_features_vw`                                                                                                                                                                                                   | Creator/channel analyses by tag                                       | MKBHD                   |
| category            | STRING             | From `event_features_vw`                                                                                                                                                                                                   | Category × tag breakdowns                                             | Science & Technology    |
| tag                 | STRING (lowercase) | From `watch_events_fe.tags_raw`: unify delimiters (pipes/semicolons → commas), normalize comma spacing, split on comma, trim; strip `[]()\"#`; collapse whitespace; lowercase; deduplicate per `(watch_ts, video_id, tag)` | Canonical tag label per event; use for tag-level aggregations         | tech news               |
| content_elapsed_s   | FLOAT64 (seconds)  | From `event_features_vw` (time advancing content); repeated per tag row                                                                                                                                                    | Time-weighted tag analyses (e.g., sum by tag)                         | 212.5                   |
| watch_ratio_content | FLOAT64 (0–1+)     | From `event_features_vw` as `content_elapsed_s / duration_meta_s`; repeated per tag row                                                                                                                                    | Progress/retention proxy at tag level                                 | 0.74                    |
| early_exit_flag     | BOOL               | From `event_features_vw`                                                                                                                                                                                                   | Segment tag mix among early exits                                     | TRUE                    |
| cuts_per_min        | FLOAT64            | From `event_features_vw`                                                                                                                                                                                                   | “Tempo” signal per tag occurrence                                     | 18.4                    |


### Variables output as event tag cooccur

| Variable              | Type        | How it’s made / parsed                                                                                                         | What it’s for                               | Example    |
| --------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- | ---------- |
| tag_a                 | STRING      | Distinct, normalized tags from `event_tags_long_vw`; per event, tags are sorted and paired; keep unordered pairs with `a < b`. | Pair edge: left node.                       | "unboxing" |
| tag_b                 | STRING      | Same as `tag_a`.                                                                                                               | Pair edge: right node.                      | "review"   |
| cooccurs              | INT64       | `COUNT(*)` events where `(tag_a, tag_b)` co-occur; filtered by `min_cooccurs` (default 5).                                     | Unweighted popularity of the pair.          | 607        |
| cooccurs_weight_s     | FLOAT64 (s) | Sum of raw event dwell across all events containing the pair: `SUM(dwell_s)`.                                                  | Time-weighted strength (reference).         | 412,380    |
| cooccurs_weight_30m_s | FLOAT64 (s) | Sum of capped dwell per event: `SUM(LEAST(dwell_s, 1800))` (30-min cap by default).                                            | Robust time-weighted rank (use for charts). | 303,060    |

### Variables output as creator return rewatch weekly

| Variable                    | Type                    | How it’s made / parsed                                                                                                                                                                                                                                                                            | What it’s for                                                              | Example                 |
| --------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------- |
| week_start                  | TIMESTAMP (PT week)     | `TIMESTAMP_TRUNC(watch_ts, WEEK(MONDAY), 'America/Los_Angeles')`. DST-aware (PST weeks show 08:00:00 UTC, PDT weeks 07:00:00 UTC).                                                                                                                                                                | Week bucket for all weekly metrics.                                        | 2025-06-02 07:00:00 UTC |
| creator                     | STRING (nullable)       | For per-creator rows: creator name from `event_features_vw`. For overall rows: NULL.                                                                                                                                                                                                              | Dimension for per-creator metrics.                                         | SirPugger               |
| creator_scope               | STRING                  | Literal: `PER_CREATOR` or `ALL_CREATORS`.                                                                                                                                                                                                                                                         | Distinguishes per-creator rows vs overall rows.                            | PER_CREATOR             |
| return_7d_rate              | FLOAT64 (0–1, nullable) | Event-level 7-day “next time to same creator” flag averaged within week. Per-creator: AVG over that creator’s events; Overall: AVG over all creators’ events. Flags are TRUE if the next view of the same creator is within ≤7 days (PT-date diff), FALSE otherwise, NULL if no next view exists. | Weekly loyalty/return rate.                                                | 0.7945                  |
| creator_events_used         | INT64                   | Count of events with a non-NULL flag (i.e., events that actually contribute to the AVG).                                                                                                                                                                                                          | Denominator used for `return_7d_rate`. Use this for weighting/validations. | 152                     |
| creator_events_total        | INT64                   | All qualifying events before the 7-day flag filter (time-contributing, deduped, valid IDs).                                                                                                                                                                                                       | Volume context; may exceed `*_used` when many events lack a next view yet. | 168                     |
| rewatch_rate                | FLOAT64 (0–1)           | Weekly AVG of `rn > 1` where `rn = ROW_NUMBER() OVER (PARTITION BY video_id ORDER BY watch_ts)`. Overall metric repeated on every row for that week.                                                                                                                                              | Share of events that are re-watches of a video.                            | 0.07237                 |
| rewatch_events              | INT64                   | Weekly count of events used in `rewatch_rate` (all qualifying events).                                                                                                                                                                                                                            | Denominator for `rewatch_rate`.                                            | 152                     |
| weighted_from_parts         | FLOAT64 (0–1, nullable) | Overall rows only. Event-weighted average of per-creator `return_7d_rate`: `SUM(COALESCE(rate,0) * creator_events_used) / NULLIF(SUM(creator_events_used), 0)`.                                                                                                                                   | Cross-check that the overall equals the weighted per-creator pieces.       | 0.86885                 |
| events_used_from_parts      | INT64 (nullable)        | Overall rows only. `SUM(creator_events_used)` across all creators for the week.                                                                                                                                                                                                                   | Denominator used in `weighted_from_parts`.                                 | 152                     |
| events_total_from_parts     | INT64 (nullable)        | Overall rows only. `SUM(creator_events_total)` across all creators for the week.                                                                                                                                                                                                                  | Volume context for pairwise comparison with `return_events_all_total`.     | 168                     |
| return_vs_weighted_abs_diff | FLOAT64 (nullable)      | Overall rows only. `ABS(return_7d_rate - weighted_from_parts)`.                                                                                                                                                                                                                                   | Numerical agreement check between overall and weighted-from-parts.         | 0.000000001             |
| return_vs_weighted_match    | BOOL (nullable)         | Overall rows only. `ABS(diff) ≤ 1e-9`.                                                                                                                                                                                                                                                            | Boolean “green light” for validation.                                      | TRUE                    |

## License
MIT

## Acknowledgments
Thanks to open-source communities behind BigQuery, Tableau Public, and yt-dlp that enable this end-to-end portfolio.

