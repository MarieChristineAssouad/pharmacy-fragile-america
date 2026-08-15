-- =============================================================================
-- 10_build_curated_county_year_panel.sql
--
-- BIG PICTURE
--   Build curated.county_year_panel — the main analytical table at
--   (county_fips, year_id) grain, years 2019–2023.
--
--   This is the table Tableau reads for the pharmacy density dashboard.
--   It answers: for each county, each year:
--     - How many pharmacies were open?
--     - How many opened that year?
--     - How many closed that year? (will be ~0 — see NPPES limitation)
--     - What is the pharmacy density per 10k Medicare beneficiaries?
--     - How has density changed from 2019 to 2023?
--
-- DESIGN DECISIONS
--   1. Years 2019–2023 only. Medicare data runs 2014–2023, but the
--      dashboard story is 2019 → 2023 (pre-COVID through recovery).
--      Five years is sufficient for trend analysis.
--
--   2. Active pharmacy count uses single-snapshot closure detection
--      (CLAUDE.md §7). We cross-join clean.pharmacies × years and apply
--      the lifecycle logic per row. See pharmacy_year CTE below.
--
--   3. closures_in_year is built but will be ~0.
--      NPPES permanently removes closed pharmacy records from the main
--      dissemination file (confirmed 6/22/26 — see CLAUDE.md §7).
--      We build the column honestly and disclose the limitation in the
--      case study. openings_in_year (from enumeration_date) IS reliable.
--
--   4. Density denominator = BENES_FFS_CNT (Medicare fee-for-service
--      beneficiaries), matching the spend denominator. Joined from
--      clean.medicare_spending at county + year + bene_age_lvl = 'All'.
--
--   5. pharmacy_count_change_2019_2023 and pharmacy_density_change_2019_2023
--      are window-function deltas: 2023 value minus 2019 value, repeated
--      in every year row for that county. This lets Tableau filter to any
--      single year while still displaying the full-period trend.
--      Known bias: missing permanent closures undercount 2019 pharmacy
--      totals, making change appear more positive than it truly is.
--      Disclosed in case study.
--
--   6. Counties with zero pharmacies do NOT appear in this panel.
--      They are excluded naturally because the CROSS JOIN starts from
--      clean.pharmacies rows. script 11 (curated.fact_county_year) will
--      bring in the full county universe via a join to clean.rucc_codes.
--
-- NPPES LIMITATION DISCLOSURE (required in case study)
--   Permanently deactivated pharmacies are absent from our data.
--   active_pharmacies counts are LOWER BOUNDS for pre-2026 years.
--   pharmacy_count_change_2019_2023 is biased toward positive values.
--   Future improvement: longitudinal NPPES snapshots (Approach B).
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-06-22
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 0: Create curated schema if it does not exist
-- -----------------------------------------------------------------------------
-- WHY this pattern instead of CREATE SCHEMA IF NOT EXISTS?
--   T-SQL does not support IF NOT EXISTS on CREATE SCHEMA.
--   The sys.schemas lookup is the standard workaround.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'curated')
    EXEC('CREATE SCHEMA curated');
GO

PRINT 'curated schema ready.';
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Drop and recreate curated.county_year_panel (idempotent)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('curated.county_year_panel', 'U') IS NOT NULL
BEGIN
    DROP TABLE curated.county_year_panel;
    PRINT 'Dropped existing curated.county_year_panel.';
END
GO

CREATE TABLE curated.county_year_panel (
    -- === Keys ===
    county_fips                       CHAR(5)        NOT NULL,
    year_id                           SMALLINT       NOT NULL,

    -- === Pharmacy stock and flow ===
    active_pharmacies                 INT            NULL,   -- count active during this year
    openings_in_year                  INT            NULL,   -- NPIs enumerated this year (reliable)
    closures_in_year                  INT            NULL,   -- closed this year (~0; see header)

    -- === Beneficiary count from Medicare ===
    benes_ffs_cnt                     INT            NULL,   -- FFS Medicare beneficiaries

    -- === Density ===
    pharmacies_per_10k_benes          DECIMAL(10,4)  NULL,   -- primary access metric
    closures_per_10k_benes            DECIMAL(10,4)  NULL,   -- will be ~0

    -- === Change over full period ===
    -- Same value repeated for all 5 year rows of a county (2023 minus 2019).
    -- Bias note: biased toward positive — see header.
    pharmacy_count_change_2019_2023   INT            NULL,
    pharmacy_density_change_2019_2023 DECIMAL(10,4)  NULL,

    -- Clustered PK on the join keys Tableau will use most
    CONSTRAINT PK_curated_county_year_panel
        PRIMARY KEY CLUSTERED (county_fips, year_id)
);
GO

PRINT 'Created curated.county_year_panel.';
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Insert — build the panel using CTEs
-- -----------------------------------------------------------------------------
-- WHY CTEs instead of nested subqueries?
--   Each CTE is a named, discrete transformation. Easier to read, easier to
--   debug by running one CTE at a time in a SELECT statement.

WITH

-- --- CTE 1: Reference years ---
-- Simple inline table. Add years here if the panel scope changes.
years AS (
    SELECT year_id
    FROM (VALUES (2019),(2020),(2021),(2022),(2023)) AS y(year_id)
),

-- --- CTE 2: Year boundary dates ---
-- Precompute start and end dates once rather than repeating DATEFROMPARTS
-- in every CASE expression below.
year_dates AS (
    SELECT
        year_id,
        DATEFROMPARTS(year_id,  1,  1) AS year_start,
        DATEFROMPARTS(year_id, 12, 31) AS year_end
    FROM years
),

-- --- CTE 3: Cross-join pharmacies × years, compute per-row lifecycle flags ---
-- For each (NPI, year) pair we compute three binary flags:
--
--   is_active  — was this pharmacy open at any point during this calendar year?
--   is_opening — did this pharmacy receive its NPI during this year?
--   is_closing — did this pharmacy close during this year with no reversal?
--
-- WHY CROSS JOIN?
--   clean.pharmacies has one row per NPI. To ask "was it open in 2019?"
--   AND "was it open in 2020?" we need one row per NPI per year.
--   CROSS JOIN creates all 112,744 × 5 = 563,720 combinations.
--   The CASE logic then flags each pair. Aggregation in CTE 4 collapses
--   back to (county_fips, year_id).
--
-- Active logic (three sub-cases):
--   (a) Never deactivated              → always active once enumerated
--   (b) Deactivated AFTER year-end     → still open during this year
--   (c) Deactivated AND later reactivated before year-end → active again
--
-- WHY filter enumeration_date IS NOT NULL?
--   A pharmacy with no enumeration date cannot be placed in time. Rare but
--   possible if the NPPES record was malformed. Excluding prevents wrong counts.
pharmacy_year AS (
    SELECT
        p.county_fips,
        d.year_id,

        -- is_active flag
        CASE
            WHEN p.enumeration_date > d.year_end
                THEN 0   -- not yet open by year-end
            WHEN p.deactivation_date IS NULL
                THEN 1   -- (a) never deactivated
            WHEN p.deactivation_date > d.year_end
                THEN 1   -- (b) deactivation is in the future relative to this year
            WHEN p.reactivation_date IS NOT NULL
                 AND p.reactivation_date > p.deactivation_date
                 AND p.reactivation_date <= d.year_end
                THEN 1   -- (c) reactivated before year-end
            ELSE 0       -- deactivated within or before this year, not reversed
        END                              AS is_active,

        -- is_opening flag: NPI first issued within this calendar year
        CASE
            WHEN p.enumeration_date >= d.year_start
             AND p.enumeration_date <= d.year_end
                THEN 1
            ELSE 0
        END                              AS is_opening,

        -- is_closing flag: deactivated within this year, no subsequent reversal
        -- Will be ~0 due to NPPES permanently removing closed pharmacy records.
        CASE
            WHEN p.deactivation_date >= d.year_start
             AND p.deactivation_date <= d.year_end
             AND (p.reactivation_date IS NULL
                  OR p.reactivation_date <= p.deactivation_date)
                THEN 1
            ELSE 0
        END                              AS is_closing

    FROM clean.pharmacies AS p
    CROSS JOIN year_dates AS d
    WHERE p.county_fips      IS NOT NULL   -- need a county to aggregate to
      AND p.enumeration_date IS NOT NULL   -- need a date to place in time
),

-- --- CTE 4: Aggregate flags to (county_fips, year_id) ---
county_year_counts AS (
    SELECT
        county_fips,
        year_id,
        SUM(is_active)   AS active_pharmacies,
        SUM(is_opening)  AS openings_in_year,
        SUM(is_closing)  AS closures_in_year
    FROM pharmacy_year
    GROUP BY county_fips, year_id
),

-- --- CTE 5: Join to Medicare for beneficiary count and compute density ---
-- WHY LEFT JOIN?
--   Keep all county-years with pharmacy data even if CMS suppressed the
--   Medicare row (suppressed = not in clean.medicare_spending for that county-year).
--   benes_ffs_cnt and density will be NULL for suppressed rows — honest.
--
-- WHY bene_age_lvl = 'All'?
--   Confirmed in script 05: county-grain Medicare rows only have age_lvl = 'All'.
--   CMS suppresses county-level age splits to protect small-cell privacy.
with_density AS (
    SELECT
        c.county_fips,
        c.year_id,
        c.active_pharmacies,
        c.openings_in_year,
        c.closures_in_year,
        m.benes_ffs_cnt,

        -- Pharmacies per 10,000 Medicare FFS beneficiaries
        -- CASE guard prevents divide-by-zero for suppressed or zero counts
        CASE
            WHEN m.benes_ffs_cnt > 0
                THEN CAST(c.active_pharmacies * 10000.0
                          / m.benes_ffs_cnt AS DECIMAL(10,4))
            ELSE NULL
        END                              AS pharmacies_per_10k_benes,

        CASE
            WHEN m.benes_ffs_cnt > 0
                THEN CAST(c.closures_in_year * 10000.0
                          / m.benes_ffs_cnt AS DECIMAL(10,4))
            ELSE NULL
        END                              AS closures_per_10k_benes

    FROM county_year_counts AS c
    LEFT JOIN clean.medicare_spending AS m
        ON  c.county_fips  = m.county_fips
        AND c.year_id      = m.year_id
        AND m.bene_age_lvl = 'All'
)

-- --- Final SELECT: add change metrics via window functions ---
-- pharmacy_count_change_2019_2023 = 2023 active minus 2019 active.
-- We compute this for every row in the partition (all 5 year-rows of
-- a county) so Tableau can access the period change regardless of year filter.
--
-- WHY ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING on LAST_VALUE?
--   Without this frame clause, LAST_VALUE returns the CURRENT row's value,
--   not the last row in the partition. T-SQL's default window for ORDER BY
--   is RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW — which means
--   LAST_VALUE is useless without the explicit frame. Always specify the frame
--   when using LAST_VALUE. This is a classic T-SQL gotcha.
INSERT INTO curated.county_year_panel (
    county_fips, year_id,
    active_pharmacies, openings_in_year, closures_in_year,
    benes_ffs_cnt,
    pharmacies_per_10k_benes, closures_per_10k_benes,
    pharmacy_count_change_2019_2023,
    pharmacy_density_change_2019_2023
)
SELECT
    county_fips,
    year_id,
    active_pharmacies,
    openings_in_year,
    closures_in_year,
    benes_ffs_cnt,
    pharmacies_per_10k_benes,
    closures_per_10k_benes,

    -- 2023 active minus 2019 active (same value in all 5 rows for this county)
    LAST_VALUE(active_pharmacies) OVER (
        PARTITION BY county_fips ORDER BY year_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )
    - FIRST_VALUE(active_pharmacies) OVER (
        PARTITION BY county_fips ORDER BY year_id
    )                                    AS pharmacy_count_change_2019_2023,

    -- 2023 density minus 2019 density
    LAST_VALUE(pharmacies_per_10k_benes) OVER (
        PARTITION BY county_fips ORDER BY year_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )
    - FIRST_VALUE(pharmacies_per_10k_benes) OVER (
        PARTITION BY county_fips ORDER BY year_id
    )                                    AS pharmacy_density_change_2019_2023

FROM with_density;

GO

PRINT 'INSERT into curated.county_year_panel complete.';
GO

-- =============================================================================
-- STEP 3: Validation queries — run all 7, review before moving to script 11
-- =============================================================================

-- ----- Validation 1: Row count -----
-- Expect: ~10,000–15,000 rows (counties with at least 1 pharmacy × 5 years).
-- Lower if many counties have no pharmacies in our data.
PRINT '=== Validation 1: Row count (expect ~10,000–15,000) ===';
SELECT COUNT(*) AS total_rows FROM curated.county_year_panel;
GO

-- ----- Validation 2: Year distribution -----
-- Expect: same county count every year (each county present in all 5 years).
-- Also: total active pharmacies should GROW from 2019 to 2023 (known positive bias
-- from missing closures — confirms the limitation is real and documentable).
PRINT '=== Validation 2: Row count and totals by year ===';
SELECT
    year_id,
    COUNT(*)                              AS county_count,
    SUM(active_pharmacies)                AS total_active,
    SUM(openings_in_year)                 AS total_openings,
    SUM(closures_in_year)                 AS total_closures,
    CAST(AVG(CAST(active_pharmacies AS FLOAT)) AS DECIMAL(6,1))
                                          AS avg_per_county
FROM curated.county_year_panel
GROUP BY year_id
ORDER BY year_id;
GO

-- ----- Validation 3: Density range (2023) -----
-- Expect: pharmacies_per_10k_benes roughly 0 to ~50.
-- Very high values in small rural counties are real (1 pharmacy / 200 beneficiaries = 50).
-- NULL density = counties where CMS suppressed Medicare data.
PRINT '=== Validation 3: Density range for 2023 ===';
SELECT
    MIN(pharmacies_per_10k_benes)         AS min_density,
    MAX(pharmacies_per_10k_benes)         AS max_density,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,4))
                                          AS avg_density,
    SUM(CASE WHEN pharmacies_per_10k_benes IS NULL THEN 1 ELSE 0 END)
                                          AS null_density_count
FROM curated.county_year_panel
WHERE year_id = 2023;
GO

-- ----- Validation 4: Closures vs openings (NPPES limitation check) -----
-- Expect: closures_in_year is ~0 every year.
-- Any non-zero value = one of the 139 temp-deactivated-then-reactivated pharmacies.
-- Openings should grow as more pharmacies enter the dataset over time.
-- THIS IS THE DOCUMENTED LIMITATION — capture this output for the case study.
PRINT '=== Validation 4: Closures vs openings by year (expect closures ~0) ===';
SELECT
    year_id,
    SUM(closures_in_year)                 AS total_closures,
    SUM(openings_in_year)                 AS total_openings
FROM curated.county_year_panel
GROUP BY year_id
ORDER BY year_id;
GO

-- ----- Validation 5: Spot check — TX-Upton county (FIPS 48461) -----
-- Our running reference: highest Medicare spend per capita in 2022.
-- Expect: very few pharmacies (tiny, remote West Texas county).
-- If active_pharmacies = 0 or NULL, it means no NPPES pharmacy has that ZIP.
PRINT '=== Validation 5: Spot check — TX-Upton (FIPS 48461) ===';
SELECT
    county_fips,
    year_id,
    active_pharmacies,
    openings_in_year,
    benes_ffs_cnt,
    pharmacies_per_10k_benes,
    pharmacy_count_change_2019_2023,
    pharmacy_density_change_2019_2023
FROM curated.county_year_panel
WHERE county_fips = '48461'
ORDER BY year_id;
GO

-- ----- Validation 6: Top 10 pharmacy deserts in 2023 -----
-- Counties with the LOWEST pharmacy density among those with at least 1 pharmacy.
-- These are the analytical stars of the dashboard.
-- Cross-check: do they also have HIGH Medicare spend per capita?
-- If yes — hypothesis supported. If not — still interesting, needs context.
PRINT '=== Validation 6: Top 10 lowest-density counties (pharmacy deserts, 2023) ===';
SELECT TOP 10
    p.county_fips,
    p.active_pharmacies,
    p.benes_ffs_cnt,
    p.pharmacies_per_10k_benes,
    m.tot_mdcr_stdzd_pymt_pc         AS medicare_spend_per_capita
FROM curated.county_year_panel AS p
LEFT JOIN clean.medicare_spending AS m
    ON  p.county_fips  = m.county_fips
    AND m.year_id      = 2023
    AND m.bene_age_lvl = 'All'
WHERE p.year_id = 2023
  AND p.pharmacies_per_10k_benes IS NOT NULL
  AND p.active_pharmacies > 0        -- exclude possible data gaps with 0 pharmacies
ORDER BY p.pharmacies_per_10k_benes ASC;
GO

-- ----- Validation 7: 2019 vs 2023 national summary -----
-- Compare total and average pharmacy presence across the two anchor years.
-- Expect: total active pharmacies higher in 2023 (positive bias from missing closures).
-- The avg density trend tells the story for the case study narrative.
PRINT '=== Validation 7: 2019 vs 2023 national summary ===';
SELECT
    year_id,
    COUNT(*)                              AS counties_with_pharmacies,
    SUM(active_pharmacies)                AS national_active_pharmacies,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,4))
                                          AS avg_national_density
FROM curated.county_year_panel
WHERE year_id IN (2019, 2023)
GROUP BY year_id
ORDER BY year_id;
GO

PRINT '=== All 7 validations complete. Review results before running script 11. ===';
GO
