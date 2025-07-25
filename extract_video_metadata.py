#!/usr/bin/env python3
# scripts/extract_video_metadata.py

import argparse, csv, json, subprocess, sys, time
from pathlib import Path

import pandas as pd

def query_yt(query: str, retries: int = 2, delay: float = 0.5):
    cmd = ["yt-dlp", f"ytsearch1:{query}", "--skip-download", "--dump-json"]
    for attempt in range(retries + 1):
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0 and proc.stdout.strip():
            return json.loads(proc.stdout)
        if attempt < retries:
            time.sleep(delay)
    return None

def main(in_csv: Path, out_csv: Path):
    df = pd.read_csv(in_csv)
    rows = []

    for _, row in df.iterrows():
        query = f"{row.Title} {row.Creator}"
        print(f"Searching  {query}")
        data = query_yt(query)

        base = {
            "original_title": row.Title,
            "original_creator": row.Creator,
            "watched_date": row.Date,
            "watched_time": row.Time,
        }

        if data:
            rows.append(
                base
                | {
                    "video_id": data.get("id"),
                    "title": data.get("title"),
                    "uploader": data.get("uploader"),
                    "upload_date": data.get("upload_date"),
                    "duration": data.get("duration"),
                    "view_count": data.get("view_count"),
                    "like_count": data.get("like_count"),
                    "category": (data.get("categories") or [None])[0],
                    "tags": ", ".join(data.get("tags") or []),
                }
            )
        else:
            rows.append(base | {"video_id": None})

        time.sleep(0.1)  # politeness / rate‑limit

    pd.DataFrame(rows).to_csv(out_csv, index=False)
    print(f"Wrote {len(rows)} rows → {out_csv}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Enrich YouTube watch history.")
    parser.add_argument("input", type=Path, help="Path to clean_data.csv")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        default=Path("outputs/enriched_watch_history.csv"),
        help="Where to write the enriched CSV",
    )
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    main(args.input, args.output)
