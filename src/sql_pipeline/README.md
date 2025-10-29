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

## License
MIT

## Acknowledgments
Thanks to open-source communities behind BigQuery, Tableau Public, and yt-dlp that enable this end-to-end portfolio.

