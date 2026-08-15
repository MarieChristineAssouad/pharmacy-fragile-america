-- =====================================================================
-- 07_load_raw_zip_to_fips.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
-- This script loads the HUD ZIP-to-County crosswalk into SQL.
-- pharmacy ZIP → county FIPS
-- ---------------------------------------------------------------------
-- Author: Marie Christine Assouad
-- =====================================================================
-- WHY THIS DATASET MATTERS
--   Our pharmacy data (raw.pharmacies, from NPPES) has ZIP codes but
--   no county FIPS. Medicare and RUCC use county FIPS as their join
--   key. So we need a ZIP-to-FIPS crosswalk to translate pharmacy
--   ZIPs into county FIPS before we can join the three datasets.
--
--   The Department of Housing and Urban Development publishes the
--   federal-standard quarterly crosswalk. Each row is one ZIP-County
--   pairing. ZIPs spanning multiple counties have multiple rows with
--   ratio columns showing the share of addresses in each county.
--
-- SOURCE
--   ZIP_COUNTY_122025.xlsx  (Q4 2025, ~54,572 rows, 8 columns).
--   Pre-converted to CSV by scripts/convert_zip_county_to_csv.py
--   because BULK INSERT can't read .xlsx natively.
--
-- DESIGN CHOICES
--   - All columns VARCHAR. The `raw` schema is loyal to the source —
--     no parsing, no padding, no type casting. Type casting and
--     business rules (collapsing multi-county ZIPs to one row per ZIP
--     by highest BUS_RATIO) belong in the `clean` schema.
--   - ZIP and COUNTY were forced to text in the Python converter
--     (dtype=str) so leading zeros survive. The CSV here should
--     already have 5-char zero-padded values. We still apply
--     defensive padding in the clean layer.
-- =====================================================================

USE pharmacy_medicare_project;
GO

-- ---------------------------------------------------------------------
-- STEP 1: Drop the table if it exists (idempotency)
-- ---------------------------------------------------------------------
IF OBJECT_ID('raw.zip_to_fips', 'U') IS NOT NULL -- Checks if the table already exists.
BEGIN
    DROP TABLE raw.zip_to_fips;
    PRINT 'Dropped existing raw.zip_to_fips table.';
END
GO  -- So we can rerun the script safely.

-- ---------------------------------------------------------------------
-- STEP 2: Create the table
-- ---------------------------------------------------------------------
-- Widths are generously padded. The source is medium-small (~55k rows)
-- so the storage cost of being defensive is negligible.
CREATE TABLE raw.zip_to_fips (
    zip                   VARCHAR(10)  NULL,  -- USPS ZIP, expected 5 chars zero-padded
    county_fips           VARCHAR(10)  NULL,  -- County FIPS, expected 5 chars zero-padded
    usps_zip_pref_city    VARCHAR(100) NULL,  -- preferred USPS city name for this ZIP
    usps_zip_pref_state   VARCHAR(10)  NULL,  -- 2-char state abbrev (or territory)
    -- Ratio columns: pandas writes floats with full repr() precision (~17-20+ chars),
    -- e.g., "0.05882352941176471". VARCHAR(50) gives generous headroom — raw layer
    -- should be permissive on width; precision normalization happens in clean.
    res_ratio             VARCHAR(50)  NULL,  -- residential address share (decimal as text)
    bus_ratio             VARCHAR(50)  NULL,  -- business address share (decimal as text)
    oth_ratio             VARCHAR(50)  NULL,  -- other address share (decimal as text)
    tot_ratio             VARCHAR(50)  NULL   -- total address share (decimal as text)
);
GO

PRINT 'Created table raw.zip_to_fips.';
GO

-- ---------------------------------------------------------------------
-- STEP 3: BULK INSERT from the CSV
-- ---------------------------------------------------------------------
-- File: ZIP_COUNTY_122025.csv (UTF-8, CRLF, ~54,572 data rows)
--
-- Same load pattern as scripts 03 and 04:
--   - FORMAT='CSV'         : honors FIELDQUOTE for any quoted text
--   - ROWTERMINATOR='0x0d0a' : CRLF (matches what pandas writes on Windows)
--   - FIELDQUOTE='"'       : protects against commas in city names like
--                            "Fort Lauderdale, FL" (rare but possible)
--   - CODEPAGE='65001'     : UTF-8
--   - MAXERRORS=0          : fail fast on any bad row
--   - TABLOCK              : table-level lock = faster bulk load
-- ---------------------------------------------------------------------
BULK INSERT raw.zip_to_fips
FROM 'C:\Users\carln\Desktop\Project Data Analyst 1\data_raw\ZIP_COUNTY_122025.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,                  -- skip the header row. Row 1 contains column names, not data.
    FIELDTERMINATOR = ',',         -- Columns are separated by commas.
    ROWTERMINATOR = '0x0d0a',      -- CRLF
    FIELDQUOTE = '"',              -- This prevents commas inside text from breaking the import.
    CODEPAGE = '65001',            -- UTF-8
    TABLOCK,                       -- Makes the bulk load faster.
    MAXERRORS = 0                  -- Prevents silent data loss.
);
GO

PRINT 'BULK INSERT completed.';
GO

-- ---------------------------------------------------------------------
-- STEP 4: Verify the load
-- ---------------------------------------------------------------------
DECLARE @loaded_rows INT;
SELECT @loaded_rows = COUNT(*) FROM raw.zip_to_fips;

PRINT '------------------------------------------------------------';
PRINT 'LOAD COMPLETE';
PRINT '------------------------------------------------------------';
PRINT 'Rows loaded into raw.zip_to_fips: ' + CAST(@loaded_rows AS VARCHAR(20));
PRINT 'Expected:                          54,572';
PRINT '------------------------------------------------------------';
GO

-- Quick QA: peek at the first 10 rows. Verify ZIP and county_fips are
-- 5-char zero-padded text, ratios look like decimals (e.g., '0.95'),
-- and city/state values are reasonable.
SELECT TOP 10 *  -- Quick visual check that ZIPs, FIPS, city, state, and ratios look right.
FROM raw.zip_to_fips
ORDER BY zip;
GO

-- ZIP length distribution. Should be 5 for everything. If we see 4-char
-- ZIPs, the Python converter's defensive zfill didn't fire and we have
-- New England ZIPs (00xxx-09xxx) with stripped leading zeros.
SELECT LEN(zip) AS zip_length, COUNT(*) AS row_count -- ZIPs like 01234 must not become 1234.
FROM raw.zip_to_fips
GROUP BY LEN(zip)
ORDER BY zip_length;
GO

-- County FIPS length distribution. Same check on the other join key.
SELECT LEN(county_fips) AS fips_length, COUNT(*) AS row_count --FIPS like 01001 must not become 1001.
FROM raw.zip_to_fips
GROUP BY LEN(county_fips)
ORDER BY fips_length;
GO

-- How many distinct ZIPs do we have? Should be ~41,000-43,000 (well
-- below total row count since multi-county ZIPs have multiple rows).
SELECT
    COUNT(DISTINCT zip)         AS distinct_zips, -- How many unique ZIP codes exist.
    COUNT(*)                    AS total_rows, -- How many ZIP-county rows exist.
    COUNT(*) - COUNT(DISTINCT zip) AS extra_rows_from_multi_county_zips --How many extra rows exist because some ZIPs touch multiple counties.
FROM raw.zip_to_fips;
GO

-- Sanity: pick a ZIP we know spans multiple counties and confirm we see
-- multiple rows for it. ZIP 79734 (Pecos County TX area) is a classic
-- multi-county ZIP. Pick any well-known multi-county example or just
-- look at the highest-row-count ZIP.
SELECT TOP 5 -- This finds ZIPs that touch the most counties.
    zip,
    COUNT(*) AS counties_per_zip
FROM raw.zip_to_fips
GROUP BY zip
ORDER BY COUNT(*) DESC;
GO

-- Top states by ZIP-County row count. Texas, California, New York
-- should dominate (they have the most ZIPs).
SELECT TOP 10  -- This counts ZIP-county rows by state
    usps_zip_pref_state,
    COUNT(*) AS num_zip_county_rows
FROM raw.zip_to_fips
GROUP BY usps_zip_pref_state
ORDER BY COUNT(*) DESC;
GO
