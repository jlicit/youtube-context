# About extract_video_metadata
This script is the second step in the pipeline.
It's designed to enrich the YouTube watch history from the HTML created in the first step by scraping video metadata.
It takes the cleaned HTML file (as a CSV) containing YouTube watch history and queries YouTube's API to gather detailed metadata about each video.
The result is a new CSV file with additional information about each video including: view count, upload date, video duration, and tags.

# Features
Queries YouTube via yt-dlp and enriches the CSV file with:

Video ID

Title

Uploader

Upload date

Duration

View count

Like count

Category

Tags

Rate limits and retries to avoid overwhelming YouTube's API.

Outputs the enriched data to a new CSV.

# Installing
`git clone https://github.com/jlicit/youtube-context.git`

Ensure that yt-dlp is installed on your system. If not, install it using:

`sudo apt install yt-dlp`

Make sure to have a clean_data.csv ready, which contains your cleaned YouTube watch history.

# Quick Start
To run the script, use the following command:
python scripts/extract_video_metadata.py path/to/clean_data.csv
This will read the clean_data.csv file, enrich it with metadata, and save the output as outputs/enriched_watch_history.csv.
You can specify a custom output path with the --output flag:

`python scripts/extract_video_metadata.py path/to/clean_data.csv --output path/to/output.csv`

# How It Works
The script reads the clean_data.csv file that contains cleaned YouTube watch history.
This file should have the following columns: Title, Creator, Date, and Time.
For each row, it constructs a query using the video title and creator.
The query is passed to the yt-dlp tool, which fetches metadata for the corresponding video from YouTube.
The script then extracts key pieces of metadata including:
Video ID, Title, Uploader, Upload date, Duration, View count, Like count, Category and Tags

The enriched data is stored in a new CSV file.
The script implements basic rate-limiting and retries to avoid being blocked by YouTube’s API.

# Extra Tips
It uses a small sleep time between each query to avoid YouTube's rate limits.
It retries the query a set number of times (default is 2 retries) if an error occurs. You can adjust this behavior by modifying the retries and delay parameters in the query_yt() function.
You can specify a custom output directory for the enriched CSV file. Ensure that the parent directory of your output file exists before running the script, or the script will create it for you.

# License
This project is licensed under the MIT License. see LICENSE for details.

# Acknowledgements
yt-dlp is used for pulling the metdata for videos on YouTube.
