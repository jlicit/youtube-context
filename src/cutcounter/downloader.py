from __future__ import annotations

import random
import subprocess
import tempfile
import time
from pathlib import Path

from .config import Config

__all__ = ["local_path_for"]

def _download_to_temp(url: str, cfg: Config) -> Path:
    """Download a small MP4 and return its path."""
    time.sleep(random.uniform(cfg.sleep_min, cfg.sleep_max))           # polite pause
    tmpdir = Path(tempfile.mkdtemp())
    target = tmpdir / "video.%(ext)s"

    base_cmd = [
        "yt-dlp",
        "--cookies", cfg.cookies,
        "--sleep-interval", "1",
        "--max-sleep-interval", "5",
        "--rate-limit", cfg.rate_limit,
        "-o", str(target),
        "--quiet",
        url,
    ]
    for fmt in ("best[ext=mp4][height<=480]/best[ext=mp4]", "best"):
        try:
            subprocess.check_call(base_cmd + ["-f", fmt])
            break
        except subprocess.CalledProcessError:
            continue
    else:
        raise RuntimeError(f"yt-dlp could not download {url}")

    return next(tmpdir.glob("video.*"))

def local_path_for(src: str, cfg: Config) -> tuple[str, Path | None]:
    """
    Ensure *src* is a local file.

    Returns
    -------
    local_path : str            – absolute path usable by ffmpeg
    temp_file  : Path | None    – delete this when finished
    """
    p = Path(src)
    if p.exists():
        return p.as_posix(), None
    tmp_file = _download_to_temp(src, cfg)
    return tmp_file.as_posix(), tmp_file
