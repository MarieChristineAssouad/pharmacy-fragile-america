-- =============================================================================
-- 08_build_clean_zip_to_fips.sql
--------------------------------------------------------------------------------
-- BIG PICTURE
--------------------------------------------------------------------------------
-- It ranks all county options for each ZIP using business ratio, keeps the best county only, 
-- then validates that the final ZIP-to-FIPS table is clean, unique, and joinable to RUCC.
-- Cleans ZIP and FIPS codes
-- Converts ratios to numbers
-- Uses ROW_NUMBER() to rank counties by bus_ratio
-- Keeps only the dominant county per ZIP
--------------------------------------------------------------------------------
-- PURPOSE
--   Build clean.zip_to_fips from raw.zip_to_fips.
--   Third clean-layer table — collapses HUD's 54,571 ZIP-County pairs to
--   ~39,494 unique ZIPs, picking the county with the highest business-address
--   share for each ZIP (since pharmacies are commercial addresses).
--
-- ARCHITECTURE
--   raw      -> source-loyal, all VARCHAR (54,571 rows, multi-county ZIPs duplicated)
--   clean    -> typed, single-grain (this layer): one row per unique ZIP
--   curated  -> star schema for Tableau (later)
--
-- KEY DESIGN DECISIONS 
--   1. Disambiguation by highest BUS_RATIO.
--      Pharmacies are commercial addresses, so we assign each ZIP to the
--      county containing the largest share of business addresses. Ties are
--      broken by TOT_RATIO. The alternative — ratio-weighted assignment,
--      where one pharmacy contributes fractionally to multiple counties —
--      would make closure-detection logic incoherent (a pharmacy is either
--      open or closed, not 0.7 open in one county).
--
--   2. Window function pattern: ROW_NUMBER() OVER (PARTITION BY zip ORDER BY ...).
--      For each ZIP group, rank rows by bus_ratio descending, keep rank 1.
--      Standard SQL pattern for "deduplicate while keeping the best row."
--
--   3. FLOAT for ratios (not DECIMAL).
--      Ratios are between 0 and 1 and are used for sorting + documentation,
--      not exact arithmetic. FLOAT handles scientific notation cleanly
--      (some values come in as "7.5642e-05"). Money columns elsewhere in
--      the project use DECIMAL because money requires exact arithmetic;
--      ratios don't.
--
--   4. Engineered column: num_counties_in_zip.
--      How many counties did this ZIP originally span? Stored as a data-quality
--      indicator. Pharmacies in single-county ZIPs (~72% of cases) have
--      unambiguous county assignments. Pharmacies in 7-county ZIPs (rare but
--      they exist) are the riskiest assignments — useful to surface that on
--      the dashboard later.
--
--   5. PRIMARY KEY on zip. One row per unique ZIP.
--
-- EXPECTED OUTPUT
--   ~39,494 rows (one per unique ZIP)
--   9 columns: zip, county_fips, state_abbrev, city_name,
--              bus_ratio, res_ratio, oth_ratio, tot_ratio, num_counties_in_zip
--
-- VALIDATION TARGETS
--   - Row count = 39,494 (matches the distinct-ZIP count from script 07)
--   - All zip values exactly 5 chars
--   - All county_fips values exactly 5 chars
--   - num_counties_in_zip distribution: most are 1, max around 7
--   - Spot check ZIP 40361: should appear ONCE in clean (was 7 rows in raw),
--     with the highest-bus_ratio county selected
--   - Join coverage: nearly all chosen county_fips should exist in clean.rucc_codes
--     (proves the disambiguation didn't pick any phantom counties)
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-04-30
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Idempotent setup. Drop existing clean table.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('clean.zip_to_fips', 'U') IS NOT NULL -- the script can be rerun safely
BEGIN
    DROP TABLE clean.zip_to_fips;
    PRINT 'Dropped existing clean.zip_to_fips';
END;
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Create the clean.zip_to_fips table with proper types.
--
--   Column types:
--   - CHAR(5)     for zip and county_fips: always exactly 5 chars
--   - CHAR(2)     for state_abbrev: 2-char abbrev (or territory)
--   - VARCHAR(100) for city_name: variable length
--   - FLOAT       for ratios: handles scientific notation, plenty of precision
--   - TINYINT     for num_counties_in_zip: max value is ~7-10, fits in 1 byte
-- -----------------------------------------------------------------------------
CREATE TABLE clean.zip_to_fips (
    zip                  CHAR(5)        NOT NULL,
    county_fips          CHAR(5)        NOT NULL,
    state_abbrev         CHAR(2)        NULL,
    city_name            VARCHAR(100)   NULL,    -- Preferred USPS city
    bus_ratio            FLOAT          NULL,    -- the chosen row's business address share (most important ratio)
    res_ratio            FLOAT          NULL,    -- Residential ratio converted into numeric form. Residential share (kept for transparency)
    oth_ratio            FLOAT          NULL,    -- other share (kept for transparency)
    tot_ratio            FLOAT          NULL,    -- total share (kept for transparency)
    num_counties_in_zip  TINYINT        NULL,    -- engineered: data-quality indicator

    CONSTRAINT pk_clean_zip_to_fips              -- Makes ZIP the unique key (One row per ZIP)
        PRIMARY KEY (zip)
);
PRINT 'Created clean.zip_to_fips';
GO

-- -----------------------------------------------------------------------------
-- STEP 3: INSERT FROM raw.zip_to_fips, deduplicating by highest BUS_RATIO.
--
--   This uses two window functions in one CTE pass:
--     - ROW_NUMBER() OVER (PARTITION BY zip ORDER BY bus_ratio DESC, tot_ratio DESC)
--       Ranks each row within its ZIP group. Highest bus_ratio gets rank 1.
--       Tie-breaker is tot_ratio.
--     - COUNT(*) OVER (PARTITION BY zip)
--       Counts how many counties each ZIP spans (the data-quality column).
--
--   The CTE is filtered to rn = 1 in the outer query, so we keep exactly
--   one row per ZIP — the one with the highest business-address share.
--
--   Cleaning rules: same canonical idiom as scripts 05 and 06:
--     TRY_CAST(NULLIF(LTRIM(RTRIM(col)), '') AS <type>)
-- -----------------------------------------------------------------------------
WITH ranked AS (                                                                              --Create a temporary result set
    SELECT
        -- Identity columns — defensive 5-char zero-pad
        RIGHT('00000' + LTRIM(RTRIM(zip)), 5)                                AS zip,          -- Fix ZIP codes. (601 → 00601). Because leading zeros matter
        RIGHT('00000' + LTRIM(RTRIM(county_fips)), 5)                        AS county_fips,  -- Fix county FIPS. (1001 → 01001)

        -- Geographic dimension fields
        LEFT(LTRIM(RTRIM(usps_zip_pref_state)), 2)                           AS state_abbrev,  -- Trim spaces and keep first 2 characters
        NULLIF(LTRIM(RTRIM(usps_zip_pref_city)), '')                         AS city_name,     -- Trim spaces

        -- Ratio columns — FLOAT handles "0.058..." and "7.5e-05" formats
        TRY_CAST(NULLIF(LTRIM(RTRIM(bus_ratio)), '') AS FLOAT)               AS bus_ratio,     -- Convert business ratio to numeric.Very important because ranking depends on it
        TRY_CAST(NULLIF(LTRIM(RTRIM(res_ratio)), '') AS FLOAT)               AS res_ratio,     -- Convert residential ratio from text → decimal.If blank → NULL.If invalid → NULL instead of crash.
        TRY_CAST(NULLIF(LTRIM(RTRIM(oth_ratio)), '') AS FLOAT)               AS oth_ratio,
        TRY_CAST(NULLIF(LTRIM(RTRIM(tot_ratio)), '') AS FLOAT)               AS tot_ratio,

        -- Window function 1: how many counties does this ZIP span?
        -- COUNT(*) OVER (PARTITION BY zip) computes the size of each ZIP's group.
        -- Same value on every row of that ZIP, so we'll just keep the rn=1 row's value.
        CAST(COUNT(*) OVER (PARTITION BY zip) AS TINYINT)                    AS num_counties_in_zip,

        -- Window function 2: rank rows within each ZIP group.
        -- Rank by bus_ratio descending, then tot_ratio descending as tie-breaker.
        -- The row with rn=1 is the "winner" — the county with the highest business
        -- address share, which is the right disambiguation for commercial pharmacies.
        ROW_NUMBER() OVER (
            PARTITION BY zip
            ORDER BY
                TRY_CAST(NULLIF(LTRIM(RTRIM(bus_ratio)), '') AS FLOAT) DESC,       --This ranks rows by business ratio, highest first.For each ZIP, put the county with the highest business-address share at the top.
                TRY_CAST(NULLIF(LTRIM(RTRIM(tot_ratio)), '') AS FLOAT) DESC        -- If two rows have the same business ratio, use total ratio as the tie-breaker.
        )                                                                    AS rn -- Stores the ranking number in a temporary column called rn
    FROM raw.zip_to_fips
)
INSERT INTO clean.zip_to_fips (                                                    -- Insert cleaned rows into clean.zip_to_fips
    zip, county_fips, state_abbrev, city_name,
    bus_ratio, res_ratio, oth_ratio, tot_ratio,
    num_counties_in_zip
)
SELECT
    zip, county_fips, state_abbrev, city_name,
    bus_ratio, res_ratio, oth_ratio, tot_ratio,
    num_counties_in_zip
FROM ranked
WHERE rn = 1; --It keeps only the top-ranked county per ZIP. For every ZIP code, keep only the county with the highest business ratio.

PRINT CONCAT('Inserted ', @@ROWCOUNT, ' rows into clean.zip_to_fips'); --Number of rows affected by the previous insert.
GO


-- =============================================================================
-- STEP 4: VALIDATION BLOCK
-- =============================================================================

-- Validation 1: Total row count (expect 39,494 — matches distinct ZIP count from raw)
PRINT '=== Validation 1: Total row count (expect 39,494) ===';
SELECT COUNT(*) AS row_count FROM clean.zip_to_fips;  --Checks how many rows are in the clean table.Expected: 39,494 (That should match the number of distinct ZIPs.)

-- Validation 2: ZIP length check (all should be 5)
PRINT '=== Validation 2: ZIP length check (all should be 5 chars) ==='; --This protects leading zeros like 00601.
SELECT LEN(zip) AS zip_length, COUNT(*) AS row_count
FROM clean.zip_to_fips
GROUP BY LEN(zip);

-- Validation 3: County FIPS length check (all should be 5)  --This protects leading zeros like 01001.
PRINT '=== Validation 3: County FIPS length check (all should be 5 chars) ===';
SELECT LEN(county_fips) AS fips_length, COUNT(*) AS row_count
FROM clean.zip_to_fips
GROUP BY LEN(county_fips);

-- Validation 4: num_counties_in_zip distribution.
-- Most ZIPs should be in 1 county; multi-county ZIPs taper off.
-- Expect: ~70%+ in num=1, smaller counts at 2, 3, 4, 5, 6, 7+.
PRINT '=== Validation 4: num_counties_in_zip distribution (mostly 1, max ~7) ===';
SELECT  --This shows how many ZIPs span 1 county, 2 counties, 3 counties, etc.
    num_counties_in_zip,
    COUNT(*) AS num_zips,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_total
FROM clean.zip_to_fips
GROUP BY num_counties_in_zip
ORDER BY num_counties_in_zip;

-- Validation 5: Spot check ZIP 40361 — was 7 rows in raw, should be 1 row in clean.
-- Verify the chosen county is the one with the highest bus_ratio.
PRINT '=== Validation 5: Spot check ZIP 40361 (was 7 counties in raw, should be 1 here) ===';
SELECT zip, county_fips, state_abbrev, city_name, bus_ratio, tot_ratio, num_counties_in_zip --Confirm the script selected one winning county
FROM clean.zip_to_fips
WHERE zip = '40361';

-- Validation 5b: Show what the raw rows for ZIP 40361 looked like, sorted by bus_ratio.
-- The clean row should match the topmost (highest bus_ratio) row here.
PRINT '=== Validation 5b: Raw rows for ZIP 40361 sorted by bus_ratio (clean = topmost) ===';
SELECT   -- Purpose: The top row here should match the clean row from Validation 5. This proves rn = 1 chose the correct county.
    zip, county_fips, usps_zip_pref_city, usps_zip_pref_state, -- Purpose: Confirm a normal single-county ZIP behaves correctly.
    bus_ratio, tot_ratio
FROM raw.zip_to_fips
WHERE zip = '40361'
ORDER BY TRY_CAST(NULLIF(LTRIM(RTRIM(bus_ratio)), '') AS FLOAT) DESC;

-- Validation 6: Spot check single-county ZIP. Pick a Manhattan ZIP (10001 = Chelsea NY).
-- Should show one row, num_counties_in_zip = 1 (or close to it), bus_ratio close to 1.
PRINT '=== Validation 6: Spot check ZIP 10001 (Manhattan — should be single-county) ===';
SELECT zip, county_fips, state_abbrev, city_name, bus_ratio, num_counties_in_zip
FROM clean.zip_to_fips
WHERE zip = '10001';

-- Validation 7: Join coverage to clean.rucc_codes.
-- For every ZIP in clean.zip_to_fips, does the chosen county_fips exist in
-- clean.rucc_codes? If yes, our disambiguation produced valid county codes.
-- If many fail to match, we may have selected a non-existent or territory FIPS.
PRINT '=== Validation 7: JOIN COVERAGE — chosen counties matched to clean.rucc_codes ==='; -- After assigning each ZIP to a county, can those counties connect to the RUCC rural/urban table?
SELECT
    COUNT(*)                                                          AS total_zips,
    SUM(CASE WHEN r.county_fips IS NOT NULL THEN 1 ELSE 0 END)        AS counties_in_rucc,
    SUM(CASE WHEN r.county_fips IS NULL THEN 1 ELSE 0 END)            AS counties_not_in_rucc,
    CAST(100.0 * SUM(CASE WHEN r.county_fips IS NOT NULL THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2))                       AS pct_matched
FROM clean.zip_to_fips z
LEFT JOIN clean.rucc_codes r ON z.county_fips = r.county_fips;

-- Validation 7b: Sample of any unmatched counties (likely PR/territories/etc.)
PRINT '=== Validation 7b: Sample unmatched counties (likely territories) ==='; -- Shows examples of ZIPs whose county FIPS did not match RUCC. Purpose: After assigning each ZIP to a county, can those counties connect to the RUCC rural/urban table?
SELECT TOP 10
    z.zip,
    z.county_fips,
    z.state_abbrev,
    z.city_name
FROM clean.zip_to_fips z
LEFT JOIN clean.rucc_codes r ON z.county_fips = r.county_fips
WHERE r.county_fips IS NULL
ORDER BY z.county_fips;

GO
