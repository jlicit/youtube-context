from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .batch import process_csv
from .config import Config
from .analyzer import analyze_one

def _parse_args(cfg: Config) -> tuple[argparse.Namespace, Config]:
    p = argparse.ArgumentParser(description="Count scene‑change cuts in videos.")
    p.add_argument("src",
        help="YouTube URL, local file, or CSV containing videoId column")
    p.add_argument("-j", "--workers", type=int,
        default=min(4, (os := __import__('os')).cpu_count() or 2),
        help="parallel worker processes (default: min(4, CPU cores))")
    p.add_argument("--batch-size", type=int, default=cfg.batch_size, metavar="N",
        help=f"checkpoint every N rows (default: {cfg.batch_size})")
    p.add_argument("--threshold", type=float, default=cfg.threshold,
        help=f"ffmpeg scene‑change threshold (default: {cfg.threshold})")
    p.add_argument("--downscale", type=int, default=cfg.downscale,
        help="downscale width in px (0 = native)")
    p.add_argument("--log-level", default="INFO",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"))
    ns = p.parse_args()

    cfg = cfg.__class__(**vars(cfg) | {
        "batch_size": ns.batch_size,
        "threshold": ns.threshold,
        "downscale": (None if ns.downscale == 0 else ns.downscale),
    })
    return ns, cfg

def main() -> None:
    ns, cfg = _parse_args(Config())
    logging.basicConfig(level=ns.log_level,
                        format="%(asctime)s %(levelname)-8s %(message)s",
                        datefmt="%H:%M:%S")

    try:
        src_path = Path(ns.src)
        if src_path.suffix.lower() == ".csv" and src_path.exists():
            process_csv(src_path, cfg, ns.workers)
        else:
            cuts, dur, cpm = analyze_one(ns.src, cfg)
            print(f"Cuts        : {cuts}")
            print(f"Duration(s) : {dur:.1f}")
            print(f"Cuts / min  : {cpm:.2f}")
    except KeyboardInterrupt:
        logging.error("Interrupted by user")
        sys.exit(130)
    except Exception as exc:  # noqa: BLE001
        logging.exception("Fatal error: %s", exc)
        sys.exit(1)
