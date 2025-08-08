# About setup_py_env
This script sets up a fresh Debian/Ubuntu-based Google Compute Engine (GCE) instance for running cutcounter.py.

It installs all necessary dependencies, including system libraries, yt-dlp, FFmpeg, and creates a Python virtual environment.

It's designed for long-term first and foremost for cutcounter.py, which may take several weeks to complete; but could also be used for other video analysis script if desired.

# Features
Sets up a GCE instance with the required system dependencies (yt-dlp, FFmpeg, and Python virtual environment).

Installs and configures Python 3 virtual environment to run the cutcounter.py package.

Ensures proper workspace setup for your project to be processed on GCE.

Includes basic logging to track the script's progress during setup.

Provides instructions on how to run the cutcounter.py script in the created environment using screen for long-running processes.

# Prerequisites
Google Cloud account with billing enabled.

A newly created Google Compute Engine (GCE) instance.

Access to a terminal with sudo privileges on the instance.

For this project I used the following specs: n2d-highcpu-8 with 8 vCPUs and 8 GB memory located in the us-west1-c region.

# Installing
**Create a GCE Instance:**

Instance name: cut-counter

Machine type: n2d-highcpu-8 (8 vCPUs, 8 GB Memory)

Location: us-west1-c

**Upload the Setup Script:**

Copy the script below and save it as setup_cut_counter.sh on your local drive.

Upload this file to your GCE instance.

**Run the Setup Script:**

SSH into your GCE instance.

Run the following command to set up the environment:

`bash setup_cut_counter.sh`

# Quick Start
**Upload Files:**

After the environment is set up, upload your cut_counter.py script and CSV file(s) to the workspace directory ($HOME/yt_cut_counter) on the GCE instance.

**Start a Screen Session:**

To run long processes in the background, start a screen session:
`screen -S cuts`

**Activate the Python Environment:**

`source $HOME/yt_cut_counter/venv/bin/activate`

**Run the Cut Counter Script:**

`python cut_counter.py your.csv`

**Detach and Reattach the Screen:**

Detach the screen session: `Ctrl-A` + `D`

Reattach the screen session: `screen -r cuts`

# How It Works
The script installs and configures the following on your GCE instance:

**System Packages:**

Updates APT and installs Python 3 dependencies (python3-venv, python3-pip), ffmpeg (required for video processing), and screen (for running long processes).

**yt-dlp:**

Installs yt-dlp from the official PPA for scraping video metadata.

**Python Virtual Environment:**

Creates a Python 3 virtual environment in the `$HOME/yt_cut_counter/venv` directory.

Installs yt-dlp in the virtual environment, ensuring that Python dependencies are isolated from the system.

**Workspace Setup:**

Creates the `$HOME/yt_cut_counter directory` to store your cut_counter.py script and CSV files.

# Usage Instructions:
After setup, the script provides instructions to start a screen session, activate the Python virtual environment, and run the cutcounter.py script for processing video data.

# Extra Tips
The screen tool allows you to run processes in the background, even after you disconnect from the terminal.

You can always reconnect to your screen session using `screen -r cuts` to check the status or continue the task.

Ensure that your GCE instance has enough disk space to accommodate the video files you're processing, especially if you're working with large datasets.

# License
This project is licensed under the MIT License. see LICENSE for details.

# Acknowledgements
yt-dlp is used for pulling the metdata for videos on YouTube.

ffmpeg multimedia workhorse powering frame analysis.
