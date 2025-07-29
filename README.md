cutcounter
cutcounter is a Python toolkit that estimates the scene change (hard cut) frequency of online or local videos. It combines yt dlp for retrieval, ffmpeg/ffprobe for frame analysis, and a small multiprocessing pipeline to crunch large watch history CSVs quickly.
This package grew out of my interest in finding the the pacing of thousands of YouTube videos from my own watch history. It’s structured to be useable via your own CLI so anyone can use it.
Features
analyze_one() fetches (or opens) a video, counts cuts, and returns cuts/minute in a single call.

process_csv() parallel processes a CSV with a videoId column using a CPU core scaled worker pool.

Random sleeps, rate limits, and cookie support help with staying below YouTube’s radar.

Config dataclass All tunables (threshold, downscale, batch size, etc.) live in Config for simple changes.

Helpers are re exported in cutcounter.__init__ for ease of use.


Installing

# System requirements: Python ≥3.9, ffmpeg ≥4.0, yt-dlp ≥2024.05
git clone https://github.com/jlicit/cutcounter.git
cd cutcounter
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt   # installs Python deps only
Note: You must have ffprobe on your PATH (comes with ffmpeg) and a recent yt dlp binary. The CLI ships a helper to add the official PPA on Debian/Ubuntu if you prefer.

Quick start
Single video example:
CLI Input:
python -m cutcounter.cli "https://youtu.be/TS_59Y7bYoA"

CLI Output:
Cuts        : 42
Duration(s) : 123.0
Cuts / min  : 20.48
CSV batch example:
CLI Input:
python -m cutcounter.cli watch_history.csv --workers 8
Note: watch_history.csv must contain either a videoId header or have the IDs in column B. Videos longer than Config.max_duration (default 1 hour) are skipped.
Results stream into cut_results.csv in 200 row chunks by default.
Command line options
-j / --workers N	Override auto detected process pool size 
--batch-size N		Flush results every N rows
--threshold F		Scene change detection threshold (0.0 1.0)
--downscale W	Downscale width before analysis (set 0 to disable)
--no-throttle	Disable polite sleeps/rate limits (You may trigger YouTube’s bot detection and get shadow banned for a few hours. The faster you process without a throttle, the riskier it gets)
--log-level …		Debugging

Library usage
from cutcounter import analyze_one, Config

cfg = Config(threshold=0.08, downscale=480, polite=False)
cuts, seconds, cpm = analyze_one("my_video.mp4", cfg)
print(f"{cpm:.1f} cuts per minute")

How it works
Download / caching
downloader.local_path_for() copies a local file or fetches a low res MP4 via yt dlp (with cookies + rate limit) and returns a tempory path.
Cut detection
analyzer._count_cuts() runs an ffprobe filter graph that marks frames whose scene score exceeds the configurable threshold.
Duration extraction
A second ffprobe call grabs the exact video duration.
Metrics
Cuts per minute = cuts / (duration/60).

Configuration reference (All live in config.py)
Field			Default		Notes
threshold		0.10		Higher ⇒ fewer detected cuts
downscale		640		Pixel width; None keeps source resolution
batch_size		200		Rows per CSV flush
max_duration		3600		Skip videos longer than n seconds
rate_limit		"2M"		yt dlp bandwidth cap (curl style)
cookies		"cookies.txt"	Pass your browser cookies file to avoid age gates

Some extra Tips
Using your exported YouTube cookies greatly increases hit rate for age restricted or region locked videos.
cutcounter scrapes public endpoints, so it seems to trigger YouTube’s anti botting detection if you try to do too much too fast. I recommend leaving polite mode on for large batches of videos.
Every worker invokes ffprobe, so CPU (not network) is usually the bottleneck. Each worker is assigned to each Core your CPU has available. The more cores your CPU has, the faster it will run.

Contributing
Pull requests are very welcome! Please run ruff and pytest before opening a PR.
pip install -r requirements-dev.txt
ruff check .
pytest

License
This project is licensed under the MIT License. see LICENSE for details.

Acknowledgements
yt dlp the swiss army knife for YouTube.
ffmpeg multimedia workhorse powering frame analysis.
Enjoy measuring video pacing! If you run into issues, open a ticket on GitHub or email the maintainer.
