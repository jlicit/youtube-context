#!/usr/bin/env bash

set -euo pipefail

# Constants
readonly WORKDIR="$HOME/yt_cut_counter"
readonly VENV_DIR="$WORKDIR/venv"
readonly PYTHON_BIN="$(command -v python3)"

# Helper functions
log() { printf "\n\e[1;34m➤ %s\e[0m\n" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command '$1' not found. Aborting." >&2
    exit 1
  }
}

# Checks
log "Checking prerequisites…"
need_cmd sudo
need_cmd curl

# System packages
log "Updating APT and installing base packages…"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3-venv python3-pip ffmpeg screen

# yt‑dlp
log "Installing yt‑dlp (PPA)…"
if ! command -v yt-dlp >/dev/null 2>&1; then
  sudo add-apt-repository -y ppa:tomtomtom/yt-dlp
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y yt-dlp
fi

# Workspace
log "Creating project workspace at $WORKDIR…"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Python environment
log "Creating Python virtual environment…"
"$PYTHON_BIN" -m venv "$VENV_DIR"
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

log "Upgrading pip and installing Python dependencies…"
pip install --upgrade pip
pip install yt-dlp

# Finish
log "Cut counter environment is ready"
cat <<EOF

Next steps:

1. Upload your cut_counter.py and CSV file(s) to $WORKDIR
2. Start a screen session:
       screen -S cuts
3. Inside screen, activate the environment:
       source $VENV_DIR/bin/activate
4. Run:
       python cut_counter.py your.csv
5. Detach with  Ctrl‑A D  and reattach with  screen -r cuts
