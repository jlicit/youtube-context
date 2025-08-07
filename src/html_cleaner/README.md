# About extract_watch_history

extract_watch_history extracts and cleans data from the `watch-history.html` file downloaded by Google Takeout and outputs a cleaned CSV. It's the first step in the YouTube Context pipeline.


## Features

Parses the YouTube watch history HTML file `watch-history.html`

Extracts: Video title, Creator/channel name, Watch date and time.

Outputs: CSV with one row per watched video.

## Dependencies

This script uses the following R packages:

`rvest`
`dplyr`
`stringr`
`tidyr`
`readr`

# Installing

```r
install.packages(c("rvest", "dplyr", "stringr", "tidyr", "readr"))
