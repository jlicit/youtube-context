from __future__ import annotations
import argparse, logging, sys
from pathlib import Path
from .config   import Config
from .batch    import process_csv
from .analyzer import analyze_one

def _parse(cfg: Config):
    p = argparse.ArgumentParser(description="Count scene‑change cuts in videos.")
    p.add_argument("src", help="YouTube URL, local file, or CSV with videoId column")
    p.add_argument("-j", "--workers", type=int,
                   help="override worker processes (default = CPU cores)")
    p.add_argument("--batch-size", type=int, default=cfg.batch_size)
    p.add_argument("--threshold",  type=float, default=cfg.threshold)
    p.add_argument("--downscale",  type=int,   default=cfg.downscale)
    p.add_argument("--no-throttle", action="store_false", dest="polite",
                   help="Disable polite pauses (may trigger rate‑limits)")
    p.add_argument("--log-level", default="INFO",
                   choices=("DEBUG", "INFO", "WARNING", "ERROR"))
    ns = p.parse_args()

    cfg = cfg.__class__(**vars(cfg) | {
        "batch_size": ns.batch_size,
        "threshold":  ns.threshold,
        "downscale":  None if ns.downscale == 0 else ns.downscale,
        "polite":     ns.polite,
    })
    return ns, cfg

def main() -> None:
    ns, cfg = _parse(Config())
    logging.basicConfig(level=ns.log_level,
                        format="%(asctime)s %(levelname)-8s %(message)s",
                        datefmt="%H:%M:%S")
    try:
        p = Path(ns.src)
        if p.suffix.lower() == ".csv" and p.exists():
            process_csv(p, cfg, ns.workers)
        else:
            cuts, dur, cpm = analyze_one(ns.src, cfg)
            print(f"Cuts        : {cuts}")
            print(f"Duration(s) : {dur:.1f}")
            print(f"Cuts / min  : {cpm:.2f}")
    except KeyboardInterrupt:
        logging.error("Interrupted")
        sys.exit(130)
    except Exception as exc:                                     # noqa: BLE001
        logging.exception("Fatal: %s", exc)
        sys.exit(1)

if __name__ == "__main__":
    main()
