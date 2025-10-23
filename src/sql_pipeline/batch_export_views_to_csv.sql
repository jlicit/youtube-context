-- Batch snapshot of views to _pub tables + CSV export to GCS.
-- Edit project/dataset/URI or the view list as needed.

DECLARE v_project STRING DEFAULT 'capstone-data-pull';
DECLARE v_dataset STRING DEFAULT 'YT_Data';
DECLARE v_gcs_uri STRING DEFAULT 'gs://youtube_context_data/tableau_pub'; -- no trailing slash

DECLARE v_views ARRAY<STRING> DEFAULT [
  'event_features_vw',
  'session_category_share_long_vw',
  'sessions_enriched_vw',
  'weekly_behavior_vw',
  'weekly_category_share_vw',
  'top_creators_yearly_vw',
  'monthly_creator_hhi_vw',
  'event_tags_long_vw',
  'event_tag_cooccur_vw',
  'creator_return_rewatch_weekly_vw'
];

DECLARE view_name STRING;
DECLARE tbl_pub   STRING;
DECLARE fq_view   STRING;
DECLARE fq_table  STRING;
DECLARE uri       STRING;

DECLARE i INT64 DEFAULT 1;
DECLARE n INT64 DEFAULT ARRAY_LENGTH(v_views);

WHILE i <= n DO
  SET view_name = v_views[OFFSET(i-1)];
  SET tbl_pub   = CONCAT(view_name, '_pub');
  SET fq_view   = FORMAT('`%s.%s.%s`', v_project, v_dataset, view_name);
  SET fq_table  = FORMAT('`%s.%s.%s`', v_project, v_dataset, tbl_pub);
  SET uri       = FORMAT('%s/%s-*.csv', v_gcs_uri, tbl_pub);

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE %s AS
    SELECT * FROM %s
  """, fq_table, fq_view);

  EXECUTE IMMEDIATE FORMAT("""
    EXPORT DATA OPTIONS(
      uri='%s',
      format='CSV',
      header=true,
      overwrite=true,
      field_delimiter=','
    ) AS
    SELECT * FROM %s
  """, uri, fq_table);

  SET i = i + 1;
END WHILE;

SELECT
  v AS view_name,
  CONCAT(v, '_pub') AS table_name,
  FORMAT('%s/%s-*.csv', v_gcs_uri, CONCAT(v, '_pub')) AS csv_glob
FROM UNNEST(v_views) AS v;
