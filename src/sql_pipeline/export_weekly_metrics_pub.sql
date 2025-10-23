-- export_weekly_metrics_pub.sql
-- Materialize the weekly view and export CSV shards to GCS for Tableau/Public.

CREATE OR REPLACE TABLE `capstone-data-pull.YT_Data.weekly_metrics_pub` AS
SELECT * FROM `capstone-data-pull.YT_Data.weekly_metrics_vw`;

EXPORT DATA OPTIONS(
  uri='gs://youtube_context_data/tableau_pub/weekly_metrics_pub-*.csv',
  format='CSV',
  overwrite=true,
  header=true
) AS
SELECT * FROM `capstone-data-pull.YT_Data.weekly_metrics_pub`;
