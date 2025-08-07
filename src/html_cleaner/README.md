# About extract_watch_history

extract_watch_history extracts and cleans data from the `watch-history.html` file downloaded by Google Takeout and outputs a cleaned CSV. It's the first step in the YouTube Context pipeline.


# Features

Parses the YouTube watch history HTML file `watch-history.html`

Extracts: Video title, Creator/channel name, Watch date and time.

Outputs: CSV with one row per watched video.

# Installing
`System requirements: #version 4.0 or higher recommended`

`install.packages(c("rvest", "dplyr", "stringr", "tidyr", "readr"))`

`git clone https://github.com/jlicit/youtube-context.git`

# How It Works

First it reads the HTML file by using the rvest package, preserving its internal structure for scraping.

Identifies watch activity entries by selecting only `<div>` elements that start with the word “Watched” and have specific class names used by YouTube for video watch records.

Extracts video information:
video title (1st `<a>` tag)
creator or channel name (2nd `<a>` tag)
watch date and time (from a sibling `<div>` element)

Cleans and formats by removing the "Watched" prefix from the title, splits the raw timestamp into two separate columns: date and time.

Outputs the data by saving as a CSV file in outputs/watch_history_detailed.csv. The script will create the outputs/ directory if it doesn’t already exist.

# License
This project is licensed under the MIT License. see LICENSE for details.

# Acknowledgements
`rvest` is used for web scraping and HTML parsing from the HTML.

`dplyr` is used for building and modifying the data frame (tibble) extracted from the HTML.

`stringr` is used to clean up text, like removing the "Watched" prefix from video titles.

`tidyr` is used for separating the date and time from a single string (dt_raw) into two columns: date and time.

`readr` is used to write the cleaned watch history data to a CSV file (write_csv()).
