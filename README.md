# youtube-context
Compilation of R, Python and SQL code to pull and analyze Youtube watch history data.

**extract_watch_history.R**

Line 1: Shebang tells systems to execute this file on Rscript

Line 3: Libraries
library(rvest) - Package used for web scraping, will be used for importing HTML content
library(dplyr) - Collection of functions for data manipulation
library(stringr) - Deal with NAs and zero length vectors in the same way
library(readr) - Read data diverse set of data in CSV

Libraries wrapped into suppressPackageStartupMessages() to mute messages like “Attaching package…” in the console

Line 7: Captures command-line arguments passed to the script when executed from terminal. For script to recognize the user’s own HTML when they add it in.

Line 8: If the user forgets to supply a path, then it will abort the process with a message. This will prevent it from confusing errors later on, like “file not found” or “object html_file not defined”.

Line 10 and 11: The absolute path that was provided by the user. As well as a fixed output location inside an outputs/ folder

Line 13: Pipe in order by line:
read_html… Reads the HTML into a UTF-8 CSV. Google Takeout are UTF-8 encoded so this helps with preventing scrambling of information.
html_elements… Selects every <div class="content-cell"> In Google Takeout, each watch history entry is in one of these divs.
html_text… Extracts the text content, strips out the html tags and trims out extra white space.
keep… Filters the vector so only lines that begin with “Watched” remain.
str_remove… Deleted the word “Watched” plus any spaces, which leaves behind just the video title and timestamp.
tibble… Wraps the cleaned vector into a one column tibble.

Line 20: Writes the tibble to a CSV file

Line 21: Prints a message to the user that it wrote X amount of rows to a CSV. For example “Wrote 12345 rows to outputs/watch_history.csv”.
