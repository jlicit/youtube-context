from __future__ import annotations
import csv, logging
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from .analyzer   import analyze_one
from .config     import Config
from .io_utils   import flush_rows

__all__ = ["process_csv"]

def _iter_vids(path: Path):
    with path.open(newline="", encoding="utf-8") as fp:
        reader = csv.reader(fp)
        header = next(reader, None)
        rows   = list(reader)

    vid_idx = header.index("videoId")  if header and "videoId"  in header else 1
    dur_idx = header.index("duration") if header and "duration" in header else 4

    for row in rows:
        vid = row[vid_idx].strip() if len(row) > vid_idx else ""
        if not vid:
            continue
        try:
            dur = int(float(row[dur_idx]))
        except (ValueError, IndexError):
            dur = 0
        yield vid, dur

def _work(pair, cfg):
    url, vid = pair
    try:
        cuts, dur, cpm = analyze_one(url, cfg)
        return vid, str(cuts), f"{dur:.1f}", f"{cpm:.2f}"
    except Exception as e:                                   # noqa: BLE001
        logging.warning("X %s: %s", vid, e)
        return vid, "NA", "NA", "NA"

def process_csv(csv_path: Path, cfg: Config, workers: int | None = None):
    if workers is None:
        workers = (os := __import__('os')).cpu_count() or 4   
    buffer, futures = [], {}

    with ProcessPoolExecutor(max_workers=workers) as pool:
        for vid, dur in _iter_vids(csv_path):
            if dur >= cfg.max_duration:
                buffer.append((vid, "Skipped (duration)", "NA", "NA"))
                continue
            futures[pool.submit(_work, (f"https://youtu.be/{vid}", vid), cfg)] = None

        logging.info("Queued %d videos (%d workers)", len(futures), workers)

        for n, fut in enumerate(as_completed(futures), 1):
            buffer.append(fut.result())
            if len(buffer) >= cfg.batch_size:
                flush_rows(buffer, cfg)
            if n % 50 == 0 or n == len(futures):
                logging.info("  • %d/%d complete", n, len(futures))

    flush_rows(buffer, cfg)
    logging.info("Batch finished → %s", cfg.out_csv)
