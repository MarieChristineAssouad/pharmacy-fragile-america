-- =============================================================================
-- 08b_inspect_pharmacies_columns.sql
--
-- BIG PICTURE
--   Look inside raw.pharmacies BEFORE writing script 09 (clean.pharmacies).
--   Confirm the exact column names so the 200-line transformation script
--   doesn't blow up on a name mismatch (the lesson from script 05's first run).
--
-- PURPOSE
--   Pre-flight check before script 09 (clean.pharmacies build).
--   Five small queries to surface every column we'll reference.
--
-- HOW TO RUN
--   1. Open in SSMS
--   2. F5
--   3. Paste me back all 5 result sets
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-05-06
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1) FULL column list of raw.pharmacies
--    The Python filter exports 17 columns. Let's see exactly what each is named.
-- -----------------------------------------------------------------------------
PRINT '=== Result 1: All columns in raw.pharmacies (full list) ===';
SELECT
    ORDINAL_POSITION,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'pharmacies'
ORDER BY ORDINAL_POSITION;

-- -----------------------------------------------------------------------------
-- 2) Date columns
--    NPPES has three date columns we need: enumeration_date, deactivation_date,
--    reactivation_date. The exact names might use spaces, underscores, or
--    different word ordering depending on how the load script named them.
-- -----------------------------------------------------------------------------
PRINT '=== Result 2: Date-related columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'pharmacies'
  AND (COLUMN_NAME LIKE '%[Dd]ate%'
       OR COLUMN_NAME LIKE '%[Ee]numeration%'
       OR COLUMN_NAME LIKE '%[Dd]eactivat%'
       OR COLUMN_NAME LIKE '%[Rr]eactivat%')
ORDER BY COLUMN_NAME;

-- -----------------------------------------------------------------------------
-- 3) Address-related columns (postal_code, state, city, street)
--    We need postal_code specifically for the ZIP→FIPS join.
-- -----------------------------------------------------------------------------
PRINT '=== Result 3: Address-related columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'pharmacies'
  AND (COLUMN_NAME LIKE '%[Pp]ostal%'
       OR COLUMN_NAME LIKE '%[Zz][Ii][Pp]%'
       OR COLUMN_NAME LIKE '%[Ss]tate%'
       OR COLUMN_NAME LIKE '%[Cc]ity%'
       OR COLUMN_NAME LIKE '%[Aa]ddress%'
       OR COLUMN_NAME LIKE '%[Ss]treet%')
ORDER BY COLUMN_NAME;

-- -----------------------------------------------------------------------------
-- 4) Sample 3 raw rows to see the actual data shapes:
--    - postal_code: 5-digit ZIP or 9-digit ZIP+4?
--    - dates: format like '2005-05-23' or '05/23/2005' or empty?
--    - any leading/trailing whitespace anywhere?
-- -----------------------------------------------------------------------------
PRINT '=== Result 4: Sample 3 raw rows (scroll horizontally to see all 17 cols) ===';
SELECT TOP 3 *
FROM raw.pharmacies;

-- -----------------------------------------------------------------------------
-- 5) Postal code length distribution
--    5 chars = clean ZIP. 9 chars = ZIP+4 (we'll need LEFT(..., 5) in script 09).
--    10 chars = ZIP+4 with hyphen ('12345-6789'). Other lengths = data quality issues.
-- -----------------------------------------------------------------------------
PRINT '=== Result 5: Postal code length distribution ===';
-- Column is named 'postal_code' — confirmed from script 02's CREATE TABLE.
-- NPPES verbose names were shortened to snake_case on load.
SELECT
    LEN(LTRIM(RTRIM(postal_code))) AS postal_length,
    COUNT(*) AS num_rows
FROM raw.pharmacies
GROUP BY LEN(LTRIM(RTRIM(postal_code)))
ORDER BY postal_length;

GO
