#!/usr/bin/env Rscript
# scripts/extract_watch_history_detailed.R
suppressPackageStartupMessages({
  library(rvest); library(dplyr); library(stringr); library(tidyr); library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1)
  stop("Usage: Rscript extract_watch_history_detailed.R <watch-history.html>")

html_file <- args[1]
out_csv   <- "outputs/watch_history_detailed.csv"

watch_nodes <- read_html(html_file, encoding = "UTF-8") |>
  html_elements(xpath = "
    //div[contains(@class,'content-cell')
         and contains(@class,'mdl-cell--6-col')
         and starts-with(normalize-space(.),'Watched')]
  ")

watch_data <- tibble(
  title   = watch_nodes |> html_element("a:nth-of-type(1)") |> html_text2() |> 
              str_remove("^Watched\\s+"),
  creator = watch_nodes |> html_element("a:nth-of-type(2)") |> html_text2(),
  dt_raw  = watch_nodes |> html_element(xpath = '
              following-sibling::div
                [contains(@class,"content-cell") and contains(@class,"mdl-cell--2-col")][2]
            ') |> html_text2()
) |>
  separate(dt_raw, into = c("date", "time"), sep = ",\\s+", extra = "merge")

dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
write_csv(watch_data, out_csv)
message("Wrote ", nrow(watch_data), " rows to ", out_csv)
