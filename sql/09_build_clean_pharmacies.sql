-- =============================================================================
-- 09_build_clean_pharmacies.sql
--
-- BIG PICTURE
--   Transform raw.pharmacies (112,744 rows, all VARCHAR) into
--   clean.pharmacies: typed columns, normalized ZIP, derived county_fips,
--   and a most_recent_status flag (Active / Closed).
--
--   This is the last clean-layer table. After this, the next step is
--   curated.county_year_panel (script 10), which builds the
--   (county, year) panel using the closure-detection logic to count
--   active pharmacies, openings, and closures per county per year.
--
-- DESIGN DECISIONS
--   1. ZIP → FIPS via clean.zip_to_fips
--      raw.pharmacies has no county FIPS — only a postal code.
--      We join to clean.zip_to_fips (HUD Q4 2025 crosswalk, already built
--      in script 08) on the first 5 chars of postal_code.
--      ~88% of rows are 9-char ZIP+4 (no hyphen), e.g. "285572918".
--      LEFT(..., 5) strips the +4 and gives us the 5-digit ZIP we need.
--
--   2. most_recent_status reflects the April 2026 NPPES snapshot.
--      It answers: is this pharmacy open RIGHT NOW?
--      The year-by-year active/closed panel (for the 2019–2023 trend)
--      is computed in script 10, not here.
--      Logic (from project closure-detection design, §7 of CLAUDE.md):
--        Active  = deactivation_date IS NULL
--                  OR (reactivation_date IS NOT NULL
--                      AND reactivation_date > deactivation_date)
--        Closed  = deactivation_date IS NOT NULL
--                  AND (reactivation_date IS NULL
--                       OR reactivation_date <= deactivation_date)
--
--   3. Dates use TRY_CONVERT with style 101 (MM/DD/YYYY).
--      Confirmed from sample rows: "03/19/2007" format.
--      TRY_CONVERT returns NULL for any unparseable value — never errors.
--
--   4. Columns dropped from raw (not needed for analysis):
--      address_line_1  — city/state/ZIP is sufficient for geographic join
--      taxonomy_code_1/2/3 — redundant; pharmacy_taxonomy_code is the
--                             relevant one (the matching 3336* code)
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-06-17
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Drop and recreate clean.pharmacies (idempotent)
-- -----------------------------------------------------------------------------
-- WHY DROP and recreate instead of just inserting? So the script is safe
-- to re-run from scratch — same result every time, no duplicate rows.
IF OBJECT_ID('clean.pharmacies', 'U') IS NOT NULL
BEGIN
    DROP TABLE clean.pharmacies;
    PRINT 'Dropped existing clean.pharmacies.';
END
GO

CREATE TABLE clean.pharmacies (
    -- === Identity ===
    npi                       CHAR(10)      NOT NULL,  -- 10-digit NPI; always exactly 10 chars
    entity_type_code          TINYINT       NULL,      -- 1 = individual, 2 = organization

    -- === Name ===
    org_name                  VARCHAR(500)  NULL,      -- pharmacy name (trimmed)

    -- === Location ===
    city                      VARCHAR(100)  NULL,
    state                     VARCHAR(50)   NULL,      -- NPPES allows up to 40 chars (territories, foreign addresses)
    zip5                      CHAR(5)       NULL,      -- normalized 5-digit ZIP (LEFT of postal_code)
    county_fips               CHAR(5)       NULL,      -- derived via ZIP→FIPS join; NULL for foreign ZIPs

    -- === NPI Lifecycle Dates (typed from MM/DD/YYYY source) ===
    enumeration_date          DATE          NULL,      -- when NPI was first registered
    last_update_date          DATE          NULL,      -- most recent record update
    deactivation_date         DATE          NULL,      -- when NPI was deactivated (NULL = still active)
    reactivation_date         DATE          NULL,      -- when NPI was reactivated after deactivation

    -- === Deactivation ===
    deactivation_reason_code  VARCHAR(10)   NULL,      -- DQ = deceased, DP = duplicate, etc.

    -- === Engineered Status Flag ===
    most_recent_status        VARCHAR(10)   NULL,      -- 'Active' or 'Closed' as of April 2026 snapshot

    -- === Taxonomy ===
    pharmacy_taxonomy_code    VARCHAR(20)   NULL,      -- the matching 3336* NUCC code
    pharmacy_taxonomy_pos     TINYINT       NULL,      -- which slot (1–15) the match was found in

    -- Clustered PK on NPI — every downstream join to clean.pharmacies uses NPI
    CONSTRAINT PK_clean_pharmacies PRIMARY KEY CLUSTERED (npi)
);
GO

PRINT 'Created clean.pharmacies.';
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Insert — transform and load
-- -----------------------------------------------------------------------------
-- WHY LEFT JOIN to clean.zip_to_fips?
--   We want to keep ALL 112,744 pharmacies in the clean layer, even if we
--   can't assign them a county (e.g. foreign addresses, territories with no
--   RUCC code). county_fips will be NULL for those, and they'll be
--   filtered out naturally when the curated layer does an INNER JOIN to RUCC.
--   Dropping them here would make it harder to audit coverage later.

INSERT INTO clean.pharmacies (
    npi, entity_type_code, org_name,
    city, state, zip5, county_fips,
    enumeration_date, last_update_date,
    deactivation_date, reactivation_date,
    deactivation_reason_code,
    most_recent_status,
    pharmacy_taxonomy_code, pharmacy_taxonomy_pos
)
SELECT
    -- === Identity ===
    -- NPI is always 10 digits in NPPES; LTRIM/RTRIM defensively removes whitespace
    LTRIM(RTRIM(p.npi))                                          AS npi,

    -- entity_type_code: '1' or '2' in the source — cast to TINYINT
    TRY_CAST(NULLIF(LTRIM(RTRIM(p.entity_type_code)), '') AS TINYINT)
                                                                 AS entity_type_code,

    -- === Name ===
    LTRIM(RTRIM(p.org_name))                                     AS org_name,

    -- === Location ===
    LTRIM(RTRIM(p.city))                                         AS city,
    LTRIM(RTRIM(p.state))                                        AS state,

    -- zip5: take first 5 chars of postal_code.
    --   9-char ZIP+4 (e.g. "285572918") → "28557"
    --   5-char ZIP (e.g. "28557")       → "28557"
    --   4-char (1 row, likely leading 0 stripped) → zero-pad then take 5
    RIGHT('00000' + LEFT(LTRIM(RTRIM(p.postal_code)), 5), 5)    AS zip5,

    -- county_fips: from the ZIP→FIPS crosswalk (already disambiguated by
    -- business address ratio in script 08). NULL if ZIP has no US county match.
    z.county_fips                                                AS county_fips,

    -- === Dates: TRY_CONVERT with style 101 = MM/DD/YYYY ===
    -- NULLIF strips empty strings before conversion so we get NULL, not an error.
    TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(p.enumeration_date)),  ''), 101)
                                                                 AS enumeration_date,
    TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(p.last_update_date)),  ''), 101)
                                                                 AS last_update_date,
    TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(p.deactivation_date)), ''), 101)
                                                                 AS deactivation_date,
    TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(p.reactivation_date)), ''), 101)
                                                                 AS reactivation_date,

    -- === Deactivation reason ===
    NULLIF(LTRIM(RTRIM(p.deactivation_reason_code)), '')         AS deactivation_reason_code,

    -- === most_recent_status: snapshot status as of April 2026 ===
    -- Active:  never deactivated, OR was reactivated after the last deactivation
    -- Closed:  deactivated and no later reactivation reverses it
    -- NULL:    enumeration_date is missing — can't trust the record
    CASE
        WHEN NULLIF(LTRIM(RTRIM(p.enumeration_date)), '') IS NULL
            THEN NULL   -- no enumeration date = unreliable record; exclude from counts
        WHEN NULLIF(LTRIM(RTRIM(p.deactivation_date)), '') IS NULL
            THEN 'Active'   -- never deactivated
        WHEN NULLIF(LTRIM(RTRIM(p.reactivation_date)), '') IS NOT NULL
             AND TRY_CONVERT(DATE, LTRIM(RTRIM(p.reactivation_date)), 101)
               > TRY_CONVERT(DATE, LTRIM(RTRIM(p.deactivation_date)), 101)
            THEN 'Active'   -- reactivated after most recent deactivation
        ELSE 'Closed'
    END                                                          AS most_recent_status,

    -- === Taxonomy ===
    NULLIF(LTRIM(RTRIM(p.pharmacy_taxonomy_code)), '')           AS pharmacy_taxonomy_code,
    TRY_CAST(NULLIF(LTRIM(RTRIM(p.pharmacy_taxonomy_position)), '') AS TINYINT)
                                                                 AS pharmacy_taxonomy_pos

FROM raw.pharmacies AS p

    -- LEFT JOIN: keep all pharmacies; county_fips = NULL for unmatched ZIPs
    LEFT JOIN clean.zip_to_fips AS z
        ON RIGHT('00000' + LEFT(LTRIM(RTRIM(p.postal_code)), 5), 5) = z.zip;

GO

PRINT 'INSERT into clean.pharmacies complete.';
GO

-- =============================================================================
-- STEP 3: Validation queries
-- =============================================================================
-- Run all 7. All should pass before moving to script 10.

-- ----- Validation 1: Row count -----
-- Expect: 112,744 (matches raw.pharmacies load)
PRINT '=== Validation 1: Row count (expect 112,744) ===';
SELECT COUNT(*) AS total_rows FROM clean.pharmacies;
GO

-- ----- Validation 2: most_recent_status distribution -----
-- Expect: 'Active' is the large majority (most NPIs are still live).
-- 'Closed' = pharmacies with a deactivation not reversed by reactivation.
-- NULL = records with no enumeration_date (should be very small or zero).
PRINT '=== Validation 2: most_recent_status distribution ===';
SELECT
    most_recent_status,
    COUNT(*)                                    AS num_pharmacies,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                       AS pct
FROM clean.pharmacies
GROUP BY most_recent_status
ORDER BY num_pharmacies DESC;
GO

-- ----- Validation 3: county_fips match rate -----
-- Expect: ~99%+ matched (from script 08 we know 99.98% of ZIPs map to a county).
-- NULLs = foreign addresses, military APO/FPO, Pacific territory ZIPs.
PRINT '=== Validation 3: county_fips match rate ===';
SELECT
    CASE WHEN county_fips IS NULL THEN 'No county (foreign/territory)'
         ELSE 'Matched to US county' END        AS fips_match,
    COUNT(*)                                    AS num_pharmacies,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                       AS pct
FROM clean.pharmacies
GROUP BY CASE WHEN county_fips IS NULL THEN 'No county (foreign/territory)'
              ELSE 'Matched to US county' END;
GO

-- ----- Validation 4: zip5 length check -----
-- Expect: all rows = length 5 after normalization.
-- Any other length = a bug in the zip5 derivation logic.
PRINT '=== Validation 4: zip5 length distribution (all should be 5) ===';
SELECT
    LEN(zip5)   AS zip5_length,
    COUNT(*)    AS num_rows
FROM clean.pharmacies
GROUP BY LEN(zip5)
ORDER BY zip5_length;
GO

-- ----- Validation 5: Date parse sanity -----
-- Expect: enumeration_date range is roughly 2004–2026 (NPPES launched May 2004).
-- Any NULL enumeration_dates flag records we can't use for temporal analysis.
PRINT '=== Validation 5: enumeration_date range and NULL count ===';
SELECT
    MIN(enumeration_date)   AS earliest_npi,
    MAX(enumeration_date)   AS latest_npi,
    SUM(CASE WHEN enumeration_date IS NULL THEN 1 ELSE 0 END)
                            AS null_enum_dates
FROM clean.pharmacies;
GO

-- ----- Validation 6: Spot check — Stilwell Drug Company -----
-- Row 3 from the inspection (NPI 1306768067, OK, ZIP 74960-3806).
-- If this row loaded correctly, dates/ZIP/status should all look clean.
PRINT '=== Validation 6: Spot check — Stilwell Drug Company (NPI 1306768067) ===';
SELECT
    npi, org_name, city, state,
    zip5, county_fips,
    enumeration_date, deactivation_date, reactivation_date,
    most_recent_status,
    pharmacy_taxonomy_code
FROM clean.pharmacies
WHERE npi = '1306768067';
GO

-- ----- Validation 7: Top 10 states by pharmacy count -----
-- Sanity check: CA, TX, FL, NY should dominate (most populous states).
-- Large deviations from expected rank order would signal a load problem.
PRINT '=== Validation 7: Top 10 states by pharmacy count ===';
SELECT TOP 10
    state,
    COUNT(*)                                    AS num_pharmacies,
    SUM(CASE WHEN most_recent_status = 'Active' THEN 1 ELSE 0 END)
                                                AS active,
    SUM(CASE WHEN most_recent_status = 'Closed' THEN 1 ELSE 0 END)
                                                AS closed
FROM clean.pharmacies
GROUP BY state
ORDER BY num_pharmacies DESC;
GO

PRINT '=== All validations complete. Review results before running script 10. ===';
GO
