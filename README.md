# youtube-context
Compilation of R, Python and SQL code to pull and analyze Youtube watch history data.

**extract_watch_history.R**

Line 1: Shebang tells systems to execute this file on Rscript

Line 3: Libraries
library(rvest) - Package used for web scraping, will be used for importing HTML content
library(dplyr) - Collection of functions for data manipulation
library(stringr) - Deal with NAs and zero length vectors in the same way
library(tidyr) - Package helps with adding each variable to a column
library(readr) - Read data diverse set of data in CSV

Libraries wrapped into suppressPackageStartupMessages() to mute messages like “Attaching package…” in the console

Line 7: Captures command-line arguments passed to the script when executed from terminal for script to recognize the user’s own HTML when they add it in.

Line 8: If the user forgets to supply a path, then it will abort the process with a message. This will prevent it from confusing errors later on, like “file not found” or “object html_file not defined”.

Line 10 and 11: The absolute path that was provided by the user in the command line interface. As well as a fixed output location inside an outputs/ folder

Line 14: read_html… Reads the HTML into a UTF-8 CSV. Google Takeout are UTF-8 encoded so this helps with preventing scrambling of information.

Line 21: Pipe in order by line:
watch_nodes is the vector of divs.

title:
html_elements… Selects the first item in each division and assigns it to either the title, creator 
html_text… Extracts the text content, strips out the html tags and trims out extra white space and replaces any missing data with “NA”
str_remove… Deleted the word “Watched” plus any spaces, which leaves behind just the video title and timestamp.

creator:
html_elements… Selects the first item in each division and assigns it to either the title, creator 
html_text… Extracts the text content, strips out the html tags and trims out extra white space and replaces any missing data with “NA”

dt_raw (Date and Time raw data): 
following-sibling::div.. from each watch node, it moves to the divs that come afterwards
[contains(@class,"content-cell") and contains(@class,"mdl-cell--2-col”)]… Keeps only the sibling divs, these hold the date and time text. Result looks like "Jun 10, 2025, 21:33:11 UTC"

separate(dt_raw, into = c("date", "time"), sep = ",\\s+", extra = "merge”)… splits this into a date column, and a time column

Line 33: Writes to a CSV file

Line 34: Prints a message to the user that it wrote X amount of rows to a CSV. For example “Wrote 12345 rows to outputs/watch_history.csv”.
