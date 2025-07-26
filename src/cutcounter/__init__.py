"""
cutcounter – Python utilities for counting “scene‑change” cuts
in YouTube or local videos.

High‑level helpers re‑exported here so users can do::

    from cutcounter import analyze_one, process_csv

instead of hunting through sub‑modules.
"""
from .config import Config          # noqa: F401
from .analyzer import analyze_one   # noqa: F401
from .batch import process_csv      # noqa: F401
