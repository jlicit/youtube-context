from __future__ import annotations
import random, subprocess, tempfile, time
from pathlib import Path
from .config import Config

__all__ = ["local_path_for"]

def _download(url: str, cfg: Config) -> Path:
    """Download a low‑res MP4 to a temp dir and return its path."""
    if cfg.polite:                                           
        time.sleep(random.uniform(cfg.sleep_min, cfg.sleep_max))

    tmpdir  = Path(tempfile.mkdtemp())
    target  = tmpdir / "video.%(ext)s"

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

def local_path_for(src: str, cfg: Config):
    """Return (local_path, temp_file_to_delete_or_None)."""
    p = Path(src)
    if p.exists():
        return p.as_posix(), None
    tmp = _download(src, cfg)
    return tmp.as_posix(), tmp
