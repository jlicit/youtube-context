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


**extract_video_metadata.py**

Line 1: Shebang to run Python

Line 4: Import libraries
argparse - For converting command lines into parts
json - For decoding JSON text returned from yt-dlp
subprocess - For launching yt-dlp as an external process
time - For sleeping between requests 
pathlib - For convenience of handling system paths

Line 7: Import pandas
For reading CSV and build an output table

Lines 9-17:

def query_yt(query: str, retries: int = 2, delay: float = 0.5):
takes a search string, a retry count, and a delay (seconds) between retries

cmd = ["yt-dlp", f"ytsearch1:{query}", "--skip-download", "--dump-json"]
Builds the yt-dlp command… 
ytsearch1
Tells yt-dlp to fetch only the first hit
—skip download
avoids downloading the video
—dump-json
prints metadata to stdout

for attempt in range(retries + 1):
loop through the initial try and any retries

proc = subprocess.run(cmd, capture_output=True, text=True)
launch yt-dlp and capture its stdout/stderr as text

if proc.returncode == 0 and proc.stdout.strip():
return json.loads(proc.stdout)
If yt-dlp succeeds and produces and output, parse the JSON and return it

if attempt < retries:
time.sleep(delay)
If it fails and there are retries, pause it briefly before retrying again

return None
After all attempts fail, return None

Lines 19 - 21:
def main(in_csv: Path, out_csv: Path):
df = pd.read_csv(in_csv)
rows = []
load the user’s cleaned watch history file and accumulate dictionaries for the output CSV

Lines 23 - 26:
for _, row in df.iterrows():
query = f"{row.Title} {row.Creator}"
print(f"Searching  {query}")
data = query_yt(query)
Construct a search query and call a helper

Lines 28 - 33:
base = {
"original_title": row.Title,
"original_creator": row.Creator,
"watched_date": row.Date,
"watched_time": row.Time,
}
Builds a base record with original watch information 

Lines 35 - 49:
        if data:
            rows.append(
                base
                | {                        
                    "video_id": data.get("id"),
                    "title": data.get("title"),
                    "uploader": data.get("uploader"),
                    "upload_date": data.get("upload_date"),
                    "duration": data.get("duration"),
                    "view_count": data.get("view_count"),
                    "like_count": data.get("like_count"),
                    "category": (data.get("categories") or [None])[0],
                    "tags": ", ".join(data.get("tags") or []),
                }
            )
If yt-dlp returns data, merge it in
data.get()… returns None if a field is missing
Categories is a list, so it will grab the first element or None
Tags are joined into a single comma-separated string

Lines 50 - 53:
        else:
            rows.append(base | {"video_id": None})
If not data comes back, it still records the basics
        time.sleep(0.1)  # politeness / rate‑limit
Time delate so Youtube’s search endpoint isn’t triggered

Lines 55 - 56:
    pd.DataFrame(rows).to_csv(out_csv, index=False)
    print(f"Wrote {len(rows)} rows → {out_csv}")
Write results and output message to user

Lines 58 - 71:
Command Line Interface
if __name__ == "__main__":
Only runs when the script is executed
    parser = argparse.ArgumentParser(description="Enrich YouTube watch history.")
Creates the CLI parser and arguments
    parser.add_argument("input", type=Path, help="Path to clean_data.csv")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        default=Path("outputs/enriched_watch_history.csv"),
        help="Where to write the enriched CSV",
    )
    args = parser.parse_args()
Input is required, but output is optional, defaults to the given path

    args.output.parent.mkdir(parents=True, exist_ok=True)
Ensures the output directory exists, and creates output/ if necessary 

    main(args.input, args.output)
Pass the parsed paths into main() to start processing



