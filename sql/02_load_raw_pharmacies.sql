-- =====================================================================
-- 02_load_raw_pharmacies.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
-- Load pharmacy data into SQL exactly as it is
-- ---------------------------------------------------------------------
-- Project: Quantifying the Impact of Rural Pharmacy Closures on
--          Medicare Spending: A County-Level Analysis (2019-2024)
-- Step:    Load filtered NPPES pharmacy data into raw.pharmacies
-- Author:  Marie Christine Assouad
-- =====================================================================
-- WHY BULK INSERT INSTEAD OF THE IMPORT WIZARD?
--   1. Scriptable & idempotent: re-run this script and you get the
--      same result every time. The wizard's GUI clicks aren't.
--   2. Faster: BULK INSERT bypasses the SSIS pipeline overhead and
--      can load 100k+ rows in seconds.
--   3. Clearer errors: failures point to specific row/column with
--      a real error message, unlike the wizard's silent "Stopped".
--   4. Portfolio-grade: written T-SQL is what recruiters look for.
--
-- DESIGN CHOICES:
--   - All columns are VARCHAR. The `raw` schema is loyal to the
--     source file -- no parsing of dates or numbers here. Type
--     casting and validation happen in the `clean` schema, where
--     business logic belongs.
--   - Column names are renamed to snake_case for consistency and
--     to drop the verbose "Provider Business Practice Location
--     Address ..." prefixes that NPPES uses.
-- =====================================================================

USE pharmacy_medicare_project;
GO

-- ---------------------------------------------------------------------
-- STEP 1: Drop the table if it exists (idempotency)
-- ---------------------------------------------------------------------
IF OBJECT_ID('raw.pharmacies', 'U') IS NOT NULL--Check if the table already exists.
BEGIN
    DROP TABLE raw.pharmacies;
    PRINT 'Dropped existing raw.pharmacies table.';
END--makes your script re-runnable (idempotent).
GO

-- ---------------------------------------------------------------------
-- STEP 2: Create the table
-- ---------------------------------------------------------------------
-- Column widths follow the official NPPES File Layout specification
-- (see: https://download.cms.gov/nppes/NPI_Files.html), with generous
-- safety padding. Notable: NPPES allows up to 40 chars for state names
-- (not just 2!) to accommodate foreign addresses, military APO/FPO,
-- and US territories.
CREATE TABLE raw.pharmacies (
    npi                          VARCHAR(20)  NULL,  -- spec: 10 digits-Unique ID for each pharmacy.
    entity_type_code             VARCHAR(5)   NULL,  -- spec: 1 char ("1"=person, "2"=org).Type of provider.
    org_name                     VARCHAR(500) NULL,  -- spec: 70, padded heavily-Pharmacy name
    address_line_1               VARCHAR(500) NULL,  -- spec: 55, padded heavily
    city                         VARCHAR(100) NULL,  -- spec: 40
    state                        VARCHAR(50)  NULL,  -- spec: 40 (foreign addresses!).Not just “FL” or “TX” — can include long values (Puerto Rico, military addresses)
    postal_code                  VARCHAR(30)  NULL,  -- spec: 20 (ZIP+4 or foreign)
    enumeration_date             VARCHAR(30)  NULL,  -- spec: 10 (MM/DD/YYYY)-When the pharmacy was registered
    last_update_date             VARCHAR(30)  NULL,  -- Last time the record changed
    deactivation_reason_code     VARCHAR(20)  NULL,  -- spec: 2-Why the pharmacy was deactivated
    deactivation_date            VARCHAR(30)  NULL,  -- When the pharmacy closed (if it did)
    reactivation_date            VARCHAR(30)  NULL,  -- If it reopened later
    taxonomy_code_1              VARCHAR(20)  NULL,  -- spec: 10-Type of pharmacy (retail, mail-order, etc.)
    taxonomy_code_2              VARCHAR(20)  NULL,
    taxonomy_code_3              VARCHAR(20)  NULL,
    pharmacy_taxonomy_code       VARCHAR(20)  NULL,  -- v2 derived
    pharmacy_taxonomy_position   VARCHAR(10)  NULL   -- v2 derived; 1-15 + trailing \r safety-Which slot (1–15) the pharmacy code came from
);
GO

PRINT 'Created table raw.pharmacies.';
GO

-- ---------------------------------------------------------------------
-- STEP 3: BULK INSERT from the CSV
-- ---------------------------------------------------------------------
-- File: pharmacies_filtered.csv (~50MB, 112,744 data rows)
-- Format: comma-delimited, double-quote text qualifier, UTF-8, CRLF
--
-- IMPORTANT: FORMAT = 'CSV' is REQUIRED for SQL Server to actually
-- honor the FIELDQUOTE setting. Without it, the parser ignores quotes
-- and treats embedded commas (e.g. inside "BIOSCRIP PHARMACY, INC.")
-- as field separators, breaking the column alignment.
-- FORMAT = 'CSV' requires SQL Server 2017+.
-- ---------------------------------------------------------------------
BULK INSERT raw.pharmacies --Load data from CSV into this table.
FROM 'C:\Users\carln\Desktop\Project Data Analyst 1\data_raw\pharmacies_filtered.csv' --Path to the CSV file
WITH (                             -- Start configuration for how to read the file
    FORMAT = 'CSV',                -- enable RFC-4180 CSV parser (honors quoted fields)-This is a proper CSV file
    FIRSTROW = 2,                  -- skip the header row
    FIELDTERMINATOR = ',',         -- commas separate fields
    ROWTERMINATOR = '0x0a',        -- LF (CSV-mode parser handles trailing \r cleanly)--Each row ends with a line break (\n)
    FIELDQUOTE = '"',              -- double-quote text qualifier (handles embedded commas)-Text inside quotes should be treated as one field
    CODEPAGE = '65001',            -- UTF-8
    TABLOCK,                       -- Lock the table during load → improves performanced
    MAXERRORS = 0                  -- fail fast on any bad row so we see the problem
);
GO

PRINT 'BULK INSERT completed.';
GO

-- ---------------------------------------------------------------------
-- STEP 4: Strip trailing carriage return from the last column
-- ---------------------------------------------------------------------
-- Why: CSV files written on Windows use CRLF (\r\n) line endings, but
-- BULK INSERT only consumes \n as the row terminator. The leftover \r
-- gets appended to the value in the last column. So 'pharmacy_taxonomy_position'
-- might contain "2\r" instead of "2". This statement cleans that up.
-- ---------------------------------------------------------------------
UPDATE raw.pharmacies --Modify data after loading
SET pharmacy_taxonomy_position = REPLACE(pharmacy_taxonomy_position, CHAR(13), '')--Remove hidden carriage return characters (\r)
WHERE pharmacy_taxonomy_position LIKE '%' + CHAR(13);--Only fix rows that actually contain this hidden character
GO

PRINT 'Cleaned trailing carriage returns from last column.';
GO

-- ---------------------------------------------------------------------
-- STEP 5: Verify the load
-- ---------------------------------------------------------------------
DECLARE @loaded_rows INT; --Create a temporary box called @loaded_rows where we can store the number of rows loaded.
SELECT @loaded_rows = COUNT(*) FROM raw.pharmacies;--Count how many pharmacy rows were loaded and store that count in @loaded_rows.

PRINT '------------------------------------------------------------';
PRINT 'LOAD COMPLETE';
PRINT '------------------------------------------------------------';
PRINT 'Rows loaded into raw.pharmacies: ' + CAST(@loaded_rows AS VARCHAR(20));
PRINT 'Expected:                         112,744';
PRINT '------------------------------------------------------------';
GO

-- Quick QA: peek at the data
SELECT TOP 10 *
FROM raw.pharmacies;
GO

-- Distribution of pharmacy taxonomy positions.This proves the Python filtering worked correctly.
SELECT
    pharmacy_taxonomy_position,
    COUNT(*) AS num_pharmacies
FROM raw.pharmacies
GROUP BY pharmacy_taxonomy_position
ORDER BY pharmacy_taxonomy_position;
GO

-- Distribution by US state (sanity check geography).See which states have most pharmacies
SELECT TOP 15
    state,
    COUNT(*) AS num_pharmacies
FROM raw.pharmacies
GROUP BY state
ORDER BY COUNT(*) DESC;
GO
