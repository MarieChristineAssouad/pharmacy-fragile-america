-- =============================================================================
-- 06_build_clean_rucc.sql
--------------------------------------------------------------------------------
-- Big Picture
--------------------------------------------------------------------------------
-- This script takes the raw USDA rural/urban county file and turns it into a clean table
-- with correct FIPS codes, correct data types, and a simple Metro/Nonmetro classification.
--------------------------------------------------------------------------------
-- PURPOSE
--   Build clean.rucc_codes from raw.rucc_codes.
--   Second clean-layer table — follows the patterns established in script 05.
--
-- ARCHITECTURE
--   raw      -> source-loyal, all VARCHAR (the source is an Excel-derived CSV)
--   clean    -> typed, validated, business rules applied (this layer)
--   curated  -> star schema for Tableau (later)
--
-- KEY DESIGN DECISIONS
--   1. FIPS normalized to 5-char zero-padded VARCHAR. CRITICAL — the source
--      stores Alabama counties as 4-char integers (e.g., '1081' not '01081')
--      because Excel silently drops leading zeros from numeric-looking values.
--      Without this normalization, every Alabama county would silently fail
--      to join to clean.medicare_spending.
--   2. RUCC code stored as TINYINT (1-9). Codes are categorical integers;
--      the '.0' suffix in the source is just file formatting, not analytical
--      precision. Two-step cast: text -> DECIMAL(3,1) -> TINYINT handles the
--      '1.0' format cleanly.
--   3. Engineered column rural_urban_group. USDA's official split:
--      RUCC 1-3 = 'Metro', RUCC 4-9 = 'Nonmetro'. We keep the raw RUCC code
--      too for sensitivity analysis (the 9-level gradient may matter for
--      some questions; the 2-level split is for the dashboard headline).
--   4. PRIMARY KEY on county_fips. One row per county/territory; no composite
--      key needed (unlike the Medicare table, which is keyed on county+year+age).
--
-- EXPECTED OUTPUT
--   3,235 rows (one per US county or territory)
--   7 columns: county_fips, state_abbrev, county_name, population_2020,
--              rucc_code, rucc_description, rural_urban_group
--
-- VALIDATION TARGETS
--   - Row count = 3,235
--   - Texas county count = 254 (largest state)
--   - RUCC distribution: codes 1-9 across counties + 2 NULLs (matches raw)
--   - All county_fips exactly 5 chars
--   - Upton County TX (FIPS 48461) should be rural (RUCC 6+)
--   - New York County NY (FIPS 36061) should be Metro (RUCC 1)
--   - Join coverage: ~99%+ of clean.medicare_spending counties should have
--     a RUCC match (proves FIPS normalization is aligned across the two tables)
--
-- AUTHOR / DATE
--   Marie Christine Assouad,
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Idempotent setup. Drop existing clean table.
--         (clean schema already exists from script 05.)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('clean.rucc_codes', 'U') IS NOT NULL --Checks if clean.rucc_codes already exists.
BEGIN
    DROP TABLE clean.rucc_codes;
    PRINT 'Dropped existing clean.rucc_codes';
END; --So we can rerun the script safely.
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Create the clean.rucc_codes table with proper types.
--
--   Column types:
--   - CHAR(5)     for county_fips: codes are always exactly 5 chars
--   - CHAR(2)     for state_abbrev: state codes are always 2 chars (AL, VI, PR)
--   - VARCHAR(100) for county_name: variable length, "St. Mary's Parish" etc.
--   - INT         for population_2020: max ~2.1 billion (LA County is ~10M)
--   - TINYINT     for rucc_code: codes are integers 1-9 only
--   - VARCHAR(500) for description: long category text
--   - VARCHAR(10) for rural_urban_group: 'Metro' / 'Nonmetro' / NULL
-- -----------------------------------------------------------------------------
CREATE TABLE clean.rucc_codes (
    county_fips        CHAR(5)        NOT NULL, --County FIPS code, always exactly 5 characters.
    state_abbrev       CHAR(2)        NULL, --State abbreviation
    county_name        VARCHAR(100)   NULL, --County name
    population_2020    INT            NULL, --County population from 2020 Census
    rucc_code          TINYINT        NULL, -- 1-9 (NULL for territories with no RUCC) (1 = very urban,9 = very rural)
    rucc_description   VARCHAR(500)   NULL, -- New column (metro or nonmetro)
    rural_urban_group  VARCHAR(10)    NULL, -- engineered: 'Metro' (1-3) or 'Nonmetro' (4-9)

    CONSTRAINT pk_clean_rucc_codes 
        PRIMARY KEY (county_fips) -- Makes county_fips the unique key.
);
PRINT 'Created clean.rucc_codes';
GO

-- -----------------------------------------------------------------------------
-- STEP 3: INSERT FROM raw.rucc_codes with cleaning.
--
--   Cleaning rules applied:
--     - LTRIM/RTRIM on every text field (defensive against stray whitespace)
--     - NULLIF(col, '') to convert empty strings to NULL
--     - TRY_CAST around every numeric conversion (bad values -> NULL, no crash)
--     - RIGHT('00000' + col, 5) for FIPS zero-padding
--     - Two-step cast for rucc_code: text -> DECIMAL(3,1) -> TINYINT
--       (TRY_CAST('1.0' AS TINYINT) directly fails because of the decimal point;
--        going through DECIMAL handles the '1.0' format, then TINYINT drops it)
-- -----------------------------------------------------------------------------
INSERT INTO clean.rucc_codes (
    county_fips, state_abbrev, county_name, population_2020,
    rucc_code, rucc_description, rural_urban_group
)
SELECT
    -- ---- county_fips: defensive 5-char zero-pad ----
    -- Source stores Alabama counties as 4-char integers (e.g., '1081' for Lee County).
    -- Excel silently dropped the leading zero. RIGHT('00000' + ..., 5) restores it.
    RIGHT('00000' + LTRIM(RTRIM(fips)), 5)                                       AS county_fips, --This fixes FIPS codes.

    -- ---- state_abbrev: trim and enforce 2 chars ----
    LEFT(LTRIM(RTRIM(state)), 2)                                                 AS state_abbrev,--Trim spaces and keep first 2 characters.

    -- ---- county_name: trim, empty -> NULL ----
    NULLIF(LTRIM(RTRIM(county_name)), '')                                        AS county_name, -- Clean county name.

    -- ---- population_2020: text -> INT (forgiving) ----
    TRY_CAST(NULLIF(LTRIM(RTRIM(population_2020)), '') AS INT)                   AS population_2020,-- Convert population from text to number.

    -- ---- rucc_code: text '1.0' to '9.0' -> TINYINT 1 to 9 ----
    -- Two-step cast: handles the decimal-point format in the source.
    TRY_CAST(
        TRY_CAST(NULLIF(LTRIM(RTRIM(rucc_2023)), '') AS DECIMAL(3,1))
        AS TINYINT
    )                                                                            AS rucc_code,

    -- ---- rucc_description: trim, empty -> NULL ----
    NULLIF(LTRIM(RTRIM(description)), '')                                        AS rucc_description,

    -- ---- ENGINEERED: rural_urban_group ----
    -- USDA's official Metro/Nonmetro split. 1-3 = Metro, 4-9 = Nonmetro.
    -- This is the publication standard
    -- The same TRY_CAST pattern is repeated here (rather than referencing rucc_code)
    CASE
        WHEN TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(rucc_2023)), '') AS DECIMAL(3,1)) AS TINYINT) --If RUCC is 1, 2, or 3: Metro
             BETWEEN 1 AND 3
            THEN 'Metro'
        WHEN TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(rucc_2023)), '') AS DECIMAL(3,1)) AS TINYINT)
             BETWEEN 4 AND 9                                                                    -- If RUCC is 4 through 9: Nonmetro
            THEN 'Nonmetro'
        ELSE NULL
    END                                                                          AS rural_urban_group

FROM raw.rucc_codes;

PRINT CONCAT('Inserted ', @@ROWCOUNT, ' rows into clean.rucc_codes'); -- Print how many rows were inserted.
GO


-- =============================================================================
-- STEP 4: VALIDATION BLOCK
--
--   Eight validation queries. The most important is #8 (join coverage) —
--   this is the gate that proves FIPS normalization is aligned across
--   clean.medicare_spending and clean.rucc_codes.
-- =============================================================================

-- Validation 1: Total row count (expect 3,235)
PRINT '=== Validation 1: Total row count (expect 3,235) ===';
SELECT COUNT(*) AS row_count FROM clean.rucc_codes;

-- Validation 2: Top 5 states by county count (Texas should be 254)
PRINT '=== Validation 2: Top 5 states by county count (TX should be 254) ===';
SELECT TOP 5 state_abbrev, COUNT(*) AS num_counties --Shows states with most counties.
FROM clean.rucc_codes
GROUP BY state_abbrev
ORDER BY COUNT(*) DESC;

-- Validation 3: RUCC code distribution (expect codes 1-9 plus ~2 NULLs)
PRINT '=== Validation 3: RUCC code distribution (expect 1-9 + 2 NULLs) ===';
SELECT
    ISNULL(CAST(rucc_code AS VARCHAR(5)), 'NULL') AS rucc_code,  --Counts counties by RUCC code.Confirm codes 1 through 9 exist and check NULLs.
    COUNT(*) AS num_counties
FROM clean.rucc_codes
GROUP BY rucc_code
ORDER BY rucc_code;

-- Validation 4: County FIPS length (all should be exactly 5)
PRINT '=== Validation 4: County FIPS length check (all should be 5 chars) ===';--Checks FIPS length.
SELECT LEN(county_fips) AS fips_length, COUNT(*) AS row_count
FROM clean.rucc_codes
GROUP BY LEN(county_fips);

-- Validation 5: rural_urban_group distribution
-- Metro should have RUCC range 1-3, Nonmetro should have 4-9. Sanity check
-- on the engineered column.
PRINT '=== Validation 5: rural_urban_group distribution (Metro 1-3, Nonmetro 4-9) ===';
SELECT
    ISNULL(rural_urban_group, 'NULL') AS rural_urban_group, --Checks our Metro/Nonmetro logic.
    COUNT(*) AS num_counties,
    MIN(rucc_code) AS min_rucc,
    MAX(rucc_code) AS max_rucc
FROM clean.rucc_codes
GROUP BY rural_urban_group
ORDER BY rural_urban_group;

-- Validation 6: Spot check — Upton County, TX (the rural county that anchored
-- our Medicare validation in scripts 04 and 05). FIPS = 48461. Should be rural.
PRINT '=== Validation 6: Upton County TX (FIPS 48461) — should be rural ===';--Spot-check Upton County, TX.Because Upton was important in our Medicare spending validation.We expect it to be rural/nonmetro.
SELECT *
FROM clean.rucc_codes
WHERE county_fips = '48461';

-- Validation 7: Spot check — New York County, NY (Manhattan). FIPS = 36061.
-- Should be RUCC 1 (most urban metro).
PRINT '=== Validation 7: New York County NY (FIPS 36061) — should be Metro RUCC 1 ===';
SELECT *
FROM clean.rucc_codes
WHERE county_fips = '36061';

-- Validation 8: JOIN COVERAGE — the most important check.
-- How many distinct county_fips in clean.medicare_spending have a matching
-- row in clean.rucc_codes? If FIPS normalization is aligned, this should be
-- close to 100%. If many fail to match, one side has a format issue
-- (likely Alabama or another state where leading-zero normalization broke).
PRINT '=== Validation 8: JOIN COVERAGE — Medicare counties matched to RUCC ===';
SELECT
    COUNT(*)                                                          AS distinct_medicare_counties,-- Counts how many distinct counties are in clean Medicare.
    SUM(CASE WHEN r.county_fips IS NOT NULL THEN 1 ELSE 0 END)        AS matched_to_rucc,-- Counts how many Medicare counties found a match in RUCC.
    SUM(CASE WHEN r.county_fips IS NULL THEN 1 ELSE 0 END)            AS unmatched, --Counts how many Medicare counties did not match RUCC.
    CAST(100.0 * SUM(CASE WHEN r.county_fips IS NOT NULL THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2))                        AS pct_matched -- Calculates match percentage
FROM (SELECT DISTINCT county_fips FROM clean.medicare_spending) m
LEFT JOIN clean.rucc_codes r ON m.county_fips = r.county_fips; --This compares Medicare county FIPS to RUCC county FIPS. It proves our FIPS formatting works across both tables

-- Bonus validation 8b: Show any unmatched county_fips so we can investigate
-- (should be a small number if any — likely territories or very recent
-- county boundary changes that exist in one source but not the other).
PRINT '=== Validation 8b: Sample of any unmatched Medicare counties (should be few) ===';
SELECT TOP 10 --Show unmatched Medicare counties.
    m.county_fips,
    m.state_abbrev,
    m.county_desc
FROM (SELECT DISTINCT county_fips, state_abbrev, county_desc FROM clean.medicare_spending) m --This lists counties that exist in Medicare but not in RUCC.Investigate mismatches instead of ignoring them.
LEFT JOIN clean.rucc_codes r ON m.county_fips = r.county_fips
WHERE r.county_fips IS NULL
ORDER BY m.county_fips;

GO
