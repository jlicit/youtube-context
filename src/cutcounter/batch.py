from __future__ import annotations

import csv
import logging
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable, Sequence

from .analyzer import analyze_one
from .config import Config
from .io_utils import flush_rows

__all__ = ["process_csv"]

def _iter_vids(csv_path: Path) -> Iterable[tuple[str, int]]:
    with csv_path.open(newline="", encoding="utf-8") as fp:
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

def _worker(url_vid: tuple[str, str], cfg: Config) -> Sequence[str]:
    url, vid = url_vid
    try:
        cuts, dur, cpm = analyze_one(url, cfg)
        return vid, str(cuts), f"{dur:.1f}", f"{cpm:.2f}"
    except Exception as exc:  # noqa: BLE001
        logging.warning("X %s: %s", vid, exc)
        return vid, "NA", "NA", "NA"

def process_csv(csv_path: Path, cfg: Config, workers: int = 4) -> None:
    buffer: list[list[str]] = []
    futures = {}

    with ProcessPoolExecutor(max_workers=workers) as pool:
        for vid, dur in _iter_vids(csv_path):
            if dur >= cfg.max_duration:
                buffer.append((vid, "Skipped (duration)", "NA", "NA"))
                continue
            url = f"https://youtu.be/{vid}"
            futures[pool.submit(_worker, (url, vid), cfg)] = None

        logging.info("Queued %d videos across %d workers", len(futures), workers)

        for idx, fut in enumerate(as_completed(futures), 1):
            buffer.append(fut.result())
            if len(buffer) >= cfg.batch_size:
                flush_rows(buffer, cfg)
            if idx % 50 == 0 or idx == len(futures):
                logging.info("  • %d/%d complete", idx, len(futures))

    flush_rows(buffer, cfg)
    logging.info("Batch finished → %s", cfg.out_csv)
