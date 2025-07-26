from __future__ import annotations

from dataclasses import dataclass

@dataclass(slots=True)
class Config:
    """All adjustable variables in one dataclass so callers can override anything."""
    threshold: float = 0.10          # ffmpeg scene‑change threshold
    downscale: int | None = 640      # width for analysis; None ⇒ native
    max_duration: int = 3_600        # skip videos ≥ this many seconds
    batch_size: int = 200            # checkpoint every N rows
    out_csv: str = "cut_results.csv"
    cookies: str = "cookies.txt"     # YouTube cookie jar
    rate_limit: str = "2M"           # yt‑dlp download throttling
    sleep_min: int = 1               # polite random delay lower bound
    sleep_max: int = 5               # … upper bound
