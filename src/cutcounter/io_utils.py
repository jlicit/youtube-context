from __future__ import annotations

import csv
from pathlib import Path
from typing import Sequence

from .config import Config

__all__ = ["flush_rows"]

def flush_rows(buffer: list[Sequence[str]], cfg: Config) -> None:
    """Append *buffer* to cfg.out_csv; create header if file is new."""
    if not buffer:
        return
    out = Path(cfg.out_csv)
    mode = "a" if out.exists() else "w"
    with out.open(mode, newline="", encoding="utf-8") as fp:
        w = csv.writer(fp)
        if mode == "w":
            w.writerow(("videoId", "Cuts", "Duration(s)", "Cuts/min"))
        w.writerows(buffer)
    buffer.clear()
  
