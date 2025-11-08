-- 1) CONFIG — EDIT THESE VALUES
DECLARE v_project STRING DEFAULT '<YOUR_PROJECT_ID>';            -- e.g. 'my-project'
DECLARE v_dataset STRING DEFAULT '<YOUR_DATASET>';               -- e.g. 'analytics'
DECLARE v_gcs_uri STRING DEFAULT 'gs://<YOUR_BUCKET>/<prefix>';  -- no trailing slash

-- List the views you want to publish/export
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

-- Optional: gzip CSVs. Set to 'GZIP' to enable, or NULL to disable.
DECLARE v_compression STRING DEFAULT NULL;  -- 'GZIP' or NULL

-- 2) LOOP VARS
DECLARE view_name STRING;
DECLARE tbl_pub   STRING;
DECLARE fq_view   STRING;
DECLARE fq_table  STRING;
DECLARE uri       STRING;
DECLARE export_opts STRING;

DECLARE i INT64 DEFAULT 1;
DECLARE n INT64 DEFAULT ARRAY_LENGTH(v_views);

-- 3) LOOP: materialize each view, then export to GCS as CSV
WHILE i <= n DO
  SET view_name = v_views[OFFSET(i-1)];
  SET tbl_pub   = CONCAT(view_name, '_pub');
  SET fq_view   = FORMAT('`%s.%s.%s`', v_project, v_dataset, view_name);
  SET fq_table  = FORMAT('`%s.%s.%s`', v_project, v_dataset, tbl_pub);
  SET uri       = FORMAT('%s/%s-*.csv', v_gcs_uri, tbl_pub);

  -- Build EXPORT options string (conditionally include compression)
  SET export_opts = FORMAT("""
    uri='%s',
    format='CSV',
    header=true,
    overwrite=true,
    field_delimiter=','%s
  """,
  uri,
  IF(v_compression IS NULL, '', FORMAT('\n    ,compression=\'%s\'', v_compression))
  );

  -- a) Snapshot the view to a table
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE %s AS
    SELECT * FROM %s
  """, fq_table, fq_view);

  -- b) Export table to CSV (note: exports are sharded files matching the glob)
  EXECUTE IMMEDIATE FORMAT("""
    EXPORT DATA OPTIONS(
      %s
    ) AS
    SELECT * FROM %s
  """, export_opts, fq_table);

  SET i = i + 1;
END WHILE;

-- 4) Summary of exports
SELECT
  v AS view_name,
  CONCAT(v, '_pub') AS table_name,
  FORMAT('%s/%s-*.csv', v_gcs_uri, CONCAT(v, '_pub')) AS csv_glob
FROM UNNEST(v_views) AS v;
