
## About
`01_watch_events_fe` creates a clean, feature-rich view of YouTube watch events for analysis and dashboards.  
It normalizes timestamps, computes elapsed seconds, sessionizes viewing behavior, derives binge/high-cuts flags, and applies playback speed rules to help interpret “time watched” consistently across periods.

`02_sessions_features_tbl` builds session-level features from YouTube watch events: sessionization (idle gap), wall-time vs content-time consumption (speed-aware), cuts-per-minute (wall & content), average playback speed, and binge flags (time- or count-based).

`03_weekly_metrics_vw` aggregates session-level YouTube watch behavior into weekly KPIs. It reports both wall clock viewing (actual time spent) and speed-aware content time (runtime consumed after accounting for playback speed).

`05_event_features_vw` generates a view of YouTube watch events for analysis and dashboarding. It standardizes time features, computes content-adjusted watch ratios (respecting playback speed and video duration), flags early exits, and bins scene-change rates by category.

`06_session_category_share_long_vw` produces a long-format table of per-session category shares—the fraction of each session’s consumed runtime spent in each category. It’s used for downstream content mix visuals and trend analysis.

`07_sessions_enriched_vw` enriches session-level analytics with category concentration (HHI, entropy), top category share, local-time features (hour, weekend), prior-session gaps, and creator switch rates.

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

                         |
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

## License
MIT

## Acknowledgments
Thanks to open-source communities behind BigQuery, Tableau Public, and yt-dlp that enable this end-to-end portfolio.

