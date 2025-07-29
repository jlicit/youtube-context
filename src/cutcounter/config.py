from __future__ import annotations
from dataclasses import dataclass

@dataclass()
class Config:
    """Tunables shared across the package."""
    # ffprobe / analysis
    threshold:   float     = 0.10
    downscale:   int | None = 640
    max_duration: int      = 3600

    # CSV + batching
    batch_size:  int       = 200
    out_csv:     str       = "cut_results.csv"

    # Networking / throttling
    cookies:     str       = "cookies.txt"
    rate_limit:  str       = "2M"
    sleep_min:   int       = 1
    sleep_max:   int       = 5
    polite:      bool      = True   # Set False to disable pauses
