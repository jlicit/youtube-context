from __future__ import annotations

import subprocess

from pathlib import Path

from .config import Config
from .downloader import local_path_for

__all__ = ["analyze_one"]

def _esc(s: str) -> str:
    return s.replace("\\", r"\\").replace(":", r"\:").replace("'", r"\'")

def _count_cuts(path: str, cfg: Config) -> int:
    movie = f"movie=filename='{_esc(path)}',"
    if cfg.downscale:
        movie += f"scale={cfg.downscale}:-1,"
    movie += f"select='gt(scene\\,{cfg.threshold})'"

    cmd = (
        "ffprobe -v error -show_frames "
        "-show_entries frame=pkt_pts_time "
        f"-of csv=p=0 -f lavfi \"{movie}\""
    )
    out = subprocess.check_output(cmd, shell=True, text=True)
    return len(out.strip().splitlines())

def _duration(path: str) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path],
        text=True,
    )
    return float(out)

def analyze_one(src: str, cfg: Config = Config()) -> tuple[int, float, float]:
    """
    Analyse *src* (YouTube URL or local file).

    Returns
    -------
    cuts        : int
    duration_s  : float
    cuts_per_m  : float
    """
    local_path, tmp = local_path_for(src, cfg)
    try:
        cuts = _count_cuts(local_path, cfg)
        dur  = _duration(local_path)
    finally:
        if tmp and tmp.exists():
            tmp.unlink()
            tmp.parent.rmdir()

    return cuts, dur, cuts / (dur / 60) if dur else 0.0
