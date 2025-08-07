# YouTube Watch History HTML Cleaner (R)

This script extracts structured data from the `watch-history.html` file provided by Google Takeout and outputs a clean CSV file. It is the **first stage** in the YouTube Context Project pipeline.

---

## What It Does

- Parses the YouTube watch history HTML file (`watch-history.html`)
- Extracts:
  - Video title
  - Creator/channel name
  - Watch date and time
- Outputs a CSV file with one row per watched video

---

## Input

- `watch-history.html`: Downloaded from your Google Takeout archive.

---

## Output

- `outputs/watch_history_detailed.csv`: A CSV file with columns:
  - `title`
  - `creator`
  - `date`
  - `time`

---

## Dependencies

This script uses the following R packages:

- `rvest`
- `dplyr`
- `stringr`
- `tidyr`
- `readr`

You can install them via:

```r
install.packages(c("rvest", "dplyr", "stringr", "tidyr", "readr"))
