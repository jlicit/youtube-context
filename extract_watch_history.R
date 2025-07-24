#!/usr/bin/env Rscript
# scripts/extract_watch_history.R
suppressPackageStartupMessages({
  library(rvest); library(dplyr); library(stringr); library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript extract_watch_history.R <watch-history.html>")

html_file <- args[1]
out_csv   <- "outputs/watch_history.csv"

watch_data <- read_html(html_file, encoding = "UTF-8") |>
  html_elements("div.content-cell") |>
  html_text(trim = TRUE) |>
  keep(~ str_starts(.x, "Watched")) |>
  str_remove("^Watched\\s+") |>
  tibble(title = _)

write_csv(watch_data, out_csv)
message("Wrote ", nrow(watch_data), " rows to ", out_csv)
