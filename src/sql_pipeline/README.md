# watch_events_fe

## About
`watch_events_fe` creates a clean, feature-rich view of YouTube watch events for analysis and dashboards.  
It normalizes timestamps, computes elapsed seconds, sessionizes viewing behavior, derives binge/high-cuts flags, and applies playback speed rules to help interpret “time watched” consistently across periods.

## Features
- Typing and parsing for messy `date` and `time` fields (multiple formats, SAFE_* parsing).
- Timezone-aware timestamps (America/Los_Angeles).
- Elapsed seconds parsed from `Elapsed Time` (`hh:mm:ss`, `mm:ss`, or `ss`).
- Playback speed rules (e.g., pre-2024 @ 2×, post-2024 @ 1×) via a simple editable CTE.
- Sessionization using gap thresholds (30 min default) with binge flags (≥45 min or ≥5 videos).
- Category-relative “high-cuts” flag using per-category 75th percentile of cuts/min.
- Use of `SAFE_CAST`, `SAFE_PARSE_*`, and `SAFE_DIVIDE`.

## Installing
This project assumes BigQuery Standard SQL.

1) Clone or copy the folder into your GitHub repo:

2) Edit the dataset references in `watch_events_fe.sql`. Replace:
- `YOUR_PROJECT_ID`
- `YOUR_DATASET`  
…and ensure your source table `cleaned_data` exists (this is your cleaned Takeout+enrichment table).

## Quick start
From the BigQuery console (or `bq` CLI), run:

```sql
-- Create or replace the analytics view
CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.YOUR_DATASET.watch_events_fe` AS
-- (paste contents of sql/watch_events_fe.sql below the line that defines the view)
```

## How it works
Pipeline stages (CTEs):
- speed_rules — central place to declare playback speed by date range (editable).
- base — normalize types (watch_date, watch_time, numeric casts with SAFE_CAST).
- typed — build watch_ts in America/Los_Angeles.
- elapsed — parse Elapsed Time into elapsed_s.
- features — row-level metrics: watch ratio, hour/dow, new session flag, playback_speed (from rules).
- sessions — first-pass session IDs using a 30-minute gap.
- sessionized — windowed session totals & binge flags.
- cuts_flags — category-relative 75th percentile to mark high_cuts_flag.
- final SELECT — keep original column names (after safe casting) for compatibility.

If you watched at ~2× for long periods and later at 1×. Analysts could misread “time watched” without knowing this context. Explicit rules make that assumption visible and auditable.

## Variables used as input

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

## Variables output as feature engineered watch events 

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
| `playback_speed`                            | FLOAT64  | From **speed rules** by `watch_date`; defaults to `1.0`. Example rule: everything before `2024-09-01` at `2.0`.                                                             | Playback speed applied to the event                     | `2`                                |


## License
MIT

## Acknowledgments
Thanks to open-source communities behind BigQuery, Tableau Public, and yt-dlp that enable this end-to-end portfolio.

