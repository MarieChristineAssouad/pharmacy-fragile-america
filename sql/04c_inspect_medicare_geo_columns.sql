-- =============================================================================
-- 04c_inspect_medicare_geo_columns.sql
--------------------------------------------------------------------------------
-- BIG PICTURE
--------------------------------------------------------------------------------
-- This script inspects geographic column names in raw.medicare_spending
-- so downstream clean-layer scripts reference the correct CMS columns.
--------------------------------------------------------------------------------
-- PURPOSE
--   This script dumps EVERY column whose name suggests it's a geographic
--   identifier so we can read the actual names off and patch script 05.
--
-- LESSON LEARNED
--   04b was incomplete. It inspected the "tricky" columns (PQI, BENES, PYMT)
--   but assumed the geo-key columns were stable across CMS publications.
--   Lesson for the project: when inspecting column names before a transform,
--   inspect EVERY column the transform references, not just the ones that
--   feel risky.
--
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-04-29
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1) Every BENE_* column (excludes BENES_* which we already inspected)
--    This catches the geo + age dim columns: BENE_GEO_LVL, BENE_AGE_LVL,
--    plus whatever the actual state/county/FIPS columns are called.
-- -----------------------------------------------------------------------------
PRINT '=== Result 1: BENE_* columns (excluding BENES_*) ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS --Look at the structure of the table, not the data inside the table.
WHERE TABLE_SCHEMA = 'raw' --Only inspect tables in the raw schema.
  AND TABLE_NAME   = 'medicare_spending' -- Only inspect the raw.medicare_spending table.
  AND COLUMN_NAME LIKE 'BENE[_]%' -- Find column names starting with: BENE_
  AND COLUMN_NAME NOT LIKE 'BENES[_]%' -- Because BENES_ columns are beneficiary count columns, not geography dimension columns (BENES_TOTAL_CNT, BENES_FFS_CNT)
ORDER BY COLUMN_NAME;

-- -----------------------------------------------------------------------------
-- 2) Anything with STATE / COUNTY / FIPS / GEO in the name
--    Wider net to catch geo columns that don't follow the BENE_ prefix.
-- -----------------------------------------------------------------------------
PRINT '=== Result 2: Any column with STATE / COUNTY / FIPS / GEO ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'medicare_spending' --Only inspect raw.medicare_spending.
  AND (COLUMN_NAME LIKE '%STATE%'
       OR COLUMN_NAME LIKE '%COUNTY%'
       OR COLUMN_NAME LIKE '%FIPS%'
       OR COLUMN_NAME LIKE '%GEO%') --why? Because maybe the geography columns do not start with BENE_.
ORDER BY COLUMN_NAME;

-- -----------------------------------------------------------------------------
-- 3) Sample of 3 raw rows to see what the geo columns actually contain
--    Limit to County level so we see real FIPS values, not state/national.
-- -----------------------------------------------------------------------------
PRINT '=== Result 3: 3 sample county rows (geo columns only — TOP 3 rows) ===';
SELECT TOP 3 *
FROM raw.medicare_spending
WHERE BENE_GEO_LVL = 'County';--Because we want to see real county geography values, not national or state rows.
-- Note: this shows ALL 247 columns. We only need to look at the leftmost
-- 5-10 columns. Just scroll left in the result grid.

GO
