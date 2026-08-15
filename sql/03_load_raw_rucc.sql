-- =====================================================================
-- 03_load_raw_rucc.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
--Load rural vs urban classification
-- ---------------------------------------------------------------------
-- Project: Quantifying the Impact of Rural Pharmacy Closures on
--          Medicare Spending: A County-Level Analysis (2019-2024)
-- Step:    5b - Load USDA Rural-Urban Continuum Codes 2023 into
--          raw.rucc_codes
-- Author: Marie Christine Assouad
-- =====================================================================
-- WHY THIS DATASET MATTERS
--   The USDA RUCC code is HOW we operationalize the word "rural" in
--   this project. Counties get a 1-9 score (1 = most urban metro,
--   9 = completely rural). Without this, "rural pharmacy desert"
--   is a vibe; with this, it's a measurable category.
--
-- SOURCE
--   Ruralurbancontinuumcodes2023.xlsx (3,235 rows, 6 columns).
--   Pre-converted to CSV by scripts/convert_rucc_to_csv.py because
--   BULK INSERT can't read .xlsx natively.
--
-- DESIGN CHOICES
--   - All columns VARCHAR. The `raw` schema is loyal to the source
--     -- no parsing, no padding, no NULL coercion. Type casting and
--     business rules belong in the `clean` schema.(Don’t clean data in raw. Just load it.)
--   - FIPS comes in as a 4 or 5 digit integer (e.g. Alabama is 1001,
--     not 01001) because the source xlsx stores it as a number. The
--     leading-zero normalization required for the join to medicare /
--     pharmacies happens in the clean layer, NOT here.
-- =====================================================================

USE pharmacy_medicare_project;
GO

-- ---------------------------------------------------------------------
-- STEP 1: Drop the table if it exists (idempotency)
-- ---------------------------------------------------------------------
IF OBJECT_ID('raw.rucc_codes', 'U') IS NOT NULL--Checks whether the table already exists.('U' means user table.)
BEGIN
    DROP TABLE raw.rucc_codes;--Deletes the old table.
    PRINT 'Dropped existing raw.rucc_codes table.';
END --This makes the script idempotent - safe to rerun.
GO

-- ---------------------------------------------------------------------
-- STEP 2: Create the table
-- ---------------------------------------------------------------------
-- Widths are generously padded. The source is small (3k rows) so the
-- storage cost of being defensive is zero.
CREATE TABLE raw.rucc_codes (
    fips             VARCHAR(10)  NULL,  -- 4 or 5 digit county FIPS (no leading zero in source)-County FIPS code from the source.(It may be 1001 instead of 01001, so we keep it as text for now.)
    state            VARCHAR(10)  NULL,  -- 2-char state/territory code (AL, VI, PR, ...)
    county_name      VARCHAR(100) NULL,  -- e.g. "Broward County"
    population_2020  VARCHAR(20)  NULL,  -- integer-as-text in raw layer
    rucc_2023        VARCHAR(10)  NULL,  -- "1.0" .. "9.0", or empty for the 2 known nulls: The rural-urban code.
    description      VARCHAR(500) NULL   -- long category text containing commas- e.g. Metro - Counties in metro areas of 1 million population or more
);
GO

PRINT 'Created table raw.rucc_codes.';
GO

-- ---------------------------------------------------------------------
-- STEP 3: BULK INSERT from the CSV
-- ---------------------------------------------------------------------
-- File: Ruralurbancontinuumcodes2023.csv (UTF-8, CRLF, ~3,235 data rows)
--
-- IMPORTANT #1: FORMAT='CSV' is REQUIRED so the parser actually honors
-- FIELDQUOTE. The Description column contains literal commas inside
-- quoted text (e.g. "Metro - Counties in metro areas of 250,000 to ..."),
-- and without FORMAT='CSV' those commas shred column alignment.
--
-- IMPORTANT #2: ROWTERMINATOR='0x0d0a' (CRLF), NOT '0x0a' (LF).
--   When FORMAT='CSV' is on AND the source file uses CRLF AND the last
--   column is a quoted string, the LF-only row terminator '0x0a'
--   reproducibly fails with: "invalid column value ... in row N, column 6".
--   The fix is to match the file's actual line ending exactly.
--   Script 02 got away with '0x0a' because the Python filter script
--   wrote pharmacies_filtered.csv with LF-only line endings. The pandas
--   to_csv used here writes CRLF on Windows, so we must match that.
--   With CRLF row terminator, no separate trailing-CR cleanup is needed
--   (the CR is consumed as part of the terminator).
-- ---------------------------------------------------------------------
BULK INSERT raw.rucc_codes--Load data into this table.
FROM 'C:\Users\carln\Desktop\Project Data Analyst 1\data_raw\Ruralurbancontinuumcodes2023.csv'
WITH (
    FORMAT = 'CSV',                -- enable RFC-4180 CSV parser - Very important because the description column contains commas inside quoted text.
    FIRSTROW = 2,                  -- Row 1 contains column headers, not data.
    FIELDTERMINATOR = ',',         -- Columns are separated by commas.
    ROWTERMINATOR = '0x0d0a',      -- CRLF; matches what pandas writes on Windows
    FIELDQUOTE = '"',              -- needed for the Description column
    CODEPAGE = '65001',            -- Read the file as UTF-8 - This helps avoid encoding problems.
    TABLOCK,                       -- table-level lock = faster bulk load
    MAXERRORS = 0                  -- fail fast on any bad row
);
GO

PRINT 'BULK INSERT completed.';
GO

-- ---------------------------------------------------------------------
-- STEP 4: Verify the load
-- ---------------------------------------------------------------------
DECLARE @loaded_rows INT; -- Creates a variable
SELECT @loaded_rows = COUNT(*) FROM raw.rucc_codes; -- Counts all rows in raw.rucc_codes and stores the count inside @loaded_rows.

PRINT '------------------------------------------------------------';
PRINT 'LOAD COMPLETE';
PRINT '------------------------------------------------------------';
PRINT 'Rows loaded into raw.rucc_codes: ' + CAST(@loaded_rows AS VARCHAR(20)); --Prints the actual number of loaded rows.
PRINT 'Expected:                         3,235';
PRINT '------------------------------------------------------------';
GO

-- Quick QA: peek at the data
SELECT TOP 10 * --Quick visual check that the data loaded correctly.
FROM raw.rucc_codes
ORDER BY fips;
GO

-- Distribution of RUCC codes -- this is the headline distribution that
-- drives the project's "rural" definition. RUCC 1-3 = metro, 4-9 = nonmetro.
SELECT
    rucc_2023,
    COUNT(*) AS num_counties
FROM raw.rucc_codes
GROUP BY rucc_2023
ORDER BY rucc_2023;
GO -- This counts how many counties fall into each RUCC category.

-- Sanity: top states by county count (Texas should dominate at 254)
SELECT TOP 10
    state,
    COUNT(*) AS num_counties
FROM raw.rucc_codes
GROUP BY state
ORDER BY COUNT(*) DESC;
GO -- This counts counties per state and shows the top 10.
