-- =============================================================================
-- 05_build_clean_medicare.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
--Turn messy Medicare data into analysis-ready data
-- ---------------------------------------------------------------------
-- PURPOSE
--   Build clean.medicare_spending from raw.medicare_spending.
--   This is the FIRST clean-layer table in the project — sets the pattern
--   for scripts 06 (clean.rucc_codes) and 07 (clean.pharmacies).
--
-- ARCHITECTURE
--   raw      -> source-loyal, all VARCHAR, preserves CMS column naming
--   clean    -> typed, validated, business rules applied (this layer)
--   curated  -> star schema for Tableau (later)
--
-- KEY DESIGN DECISIONS (defensible in interviews)
--   1. Filter to BENE_GEO_LVL = 'County' only. Single grain. Mixed-grain
--      tables invite silent fan-out bugs in joins.
--   2. Keep bene_age_lvl as a constant column ('All' for all county rows)
--      for documentation/audit trail. CMS suppresses age splits at county
--      grain to protect small-cell privacy, so this is a constant — but
--      naming the dim explicitly is good hygiene.
--   3. TRY_CAST everywhere (not CAST). Bad values become NULL, not errors.
--   4. NULLIF(col, '*') BEFORE the cast. CMS uses '*' as the suppression
--      marker; explicit handling documents intent.
--   5. FIPS defensively zero-padded to 5 chars even though source is already
--      5 chars — protects against future loads from a different file format.
--   6. Engineered columns: inpatient_spend_share, outpatient_spend_share.
--      Dropped part_d_spend_share — CMS publishes Part D in a separate
--      Geographic Variation file (this one is Parts A/B only).
--   7. PRIMARY KEY on (county_fips, year_id, bene_age_lvl) — gives us a
--      clustered index for the join keys we'll use most.
--
-- EXPECTED OUTPUT
--   ~31,959 rows (all county-grain, all bene_age_lvl='All', years 2014-2023)
--   30 columns (state_desc dropped: CMS doesn't publish it; Tableau resolves
--               state_abbrev to state name automatically for the dashboard)
--
-- VALIDATION TARGETS
--   - Row count ~31,959
--   - Years span 2014-2023 inclusive
--   - Upton County TX 2022 tot_mdcr_stdzd_pymt_pc ~ $25,800
--     (must match script 04's validation result)
--   - All county_fips values exactly 5 chars
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-04-29
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Idempotent setup. Drop existing clean table; create clean schema
--         if it doesn't exist yet (first time we write to clean.).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('clean.medicare_spending', 'U') IS NOT NULL
BEGIN
    DROP TABLE clean.medicare_spending;
    PRINT 'Dropped existing clean.medicare_spending';
END;
GO

IF SCHEMA_ID('clean') IS NULL
BEGIN
    EXEC('CREATE SCHEMA clean');
    PRINT 'Created clean schema';
END;
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Create the clean.medicare_spending table with proper types.
--
--   Types chosen for storage efficiency + Tableau compatibility:
--   - DECIMAL(12,2) for money per-capita (max ~$10M per capita, 2 decimals)
--   - DECIMAL(10,2) for ER_VISITS_PER_1000 (rates up to ~99,999.99)
--   - DECIMAL(8,4)  for percentages (0.0000 to 9999.9999)
--   - DECIMAL(10,4) for PQI rates (admits per 100k, decimal precision)
--   - DECIMAL(8,6)  for spend shares (0.000000 to 99.999999)
--   - BIGINT for counts (FFS beneficiaries can hit millions in big counties)
-- -----------------------------------------------------------------------------
CREATE TABLE clean.medicare_spending (
    -- Geographic + time + age dimensions
    -- Note: state_desc dropped — CMS publishes only state ABBREV embedded in
    -- BENE_GEO_DESC ('DE-Kent'). Tableau resolves abbrev to full state name
    -- automatically, so a parallel state_desc column adds no value here.
    geo_lvl                          VARCHAR(20)    NOT NULL,--County
    state_abbrev                     CHAR(2)        NULL,--TX, FL, CA, NY,..
    county_desc                      VARCHAR(100)   NULL,--Upton, Miami-Dade, Palm Beach,...
    county_fips                      CHAR(5)        NOT NULL,-- 12011 = Broward County, FL
    year_id                          INT            NOT NULL,
    bene_age_lvl                     VARCHAR(10)    NOT NULL,--All

    -- Beneficiary counts (denominators for any rate not pre-standardized)
    benes_ffs_cnt                    BIGINT         NULL,--Medicare beneficiary Counts, BIGINT is used because large counties can have many beneficiaries
    benes_total_cnt                  BIGINT         NULL,

    -- Headline spend + ER + readmission metrics
    tot_mdcr_stdzd_pymt_pc           DECIMAL(12,2)  NULL,--Total standardized Medicare payment per capita. How much Medicare spends per beneficiary in that county-year?
    ip_mdcr_stdzd_pymt_pc            DECIMAL(12,2)  NULL,--Inpatient spending per person. Inpatient = hospital admissions.
    op_mdcr_stdzd_pymt_pc            DECIMAL(12,2)  NULL,--Outpatient spending per person. Outpatient = care without hospital admission.
    er_visits_per_1000               DECIMAL(10,2)  NULL,--Emergency room visits per 1,000 Medicare beneficiaries.
    acute_hosp_readmsn_pct           DECIMAL(8,4)   NULL,--Hospital readmission percentage. This measures people coming back to the hospital after being discharged.

    -- PQI (Prevention Quality Indicator.):Hospitalizations that might have been prevented with good outpatient care and medication adherence.
    -- PQI rates: 5 conditions x 3 age bands = 15 columns
    -- These are the medication-adherence-sensitive admission rates that
    -- form the analytical bridge from "fewer pharmacies" to "higher Medicare spend."
    pqi03_dbts_age_lt_65             DECIMAL(10,4)  NULL,--This stores preventable diabetes admissions for people under 65.
    pqi03_dbts_age_65_74             DECIMAL(10,4)  NULL,
    pqi03_dbts_age_ge_75             DECIMAL(10,4)  NULL,

    pqi05_copd_asthma_age_40_64      DECIMAL(10,4)  NULL,--This stores preventable COPD/asthma admissions for people under 65.
    pqi05_copd_asthma_age_65_74      DECIMAL(10,4)  NULL,
    pqi05_copd_asthma_age_ge_75      DECIMAL(10,4)  NULL,

    pqi07_hyprtnsn_age_lt_65         DECIMAL(10,4)  NULL,--This stores preventable Hypertension admissions for people under 65.
    pqi07_hyprtnsn_age_65_74         DECIMAL(10,4)  NULL,
    pqi07_hyprtnsn_age_ge_75         DECIMAL(10,4)  NULL,

    pqi08_chf_age_lt_65              DECIMAL(10,4)  NULL,--This stores preventable Heart failure admissions for people under 65.
    pqi08_chf_age_65_74              DECIMAL(10,4)  NULL,
    pqi08_chf_age_ge_75              DECIMAL(10,4)  NULL,

    pqi11_bctrl_pna_age_lt_65        DECIMAL(10,4)  NULL,--This stores preventable Bacterial pneumonia admissions for people under 65.
    pqi11_bctrl_pna_age_65_74        DECIMAL(10,4)  NULL,
    pqi11_bctrl_pna_age_ge_75        DECIMAL(10,4)  NULL,

    -- Engineered columns
    inpatient_spend_share            DECIMAL(8,6)   NULL,--inpatient spending / total spending
    outpatient_spend_share           DECIMAL(8,6)   NULL,--outpatient spending / total spending

    CONSTRAINT pk_clean_medicare_spending
        PRIMARY KEY (county_fips, year_id, bene_age_lvl) --Each county-year-age combination must be unique. This prevents duplicates.
);
PRINT 'Created clean.medicare_spending';
GO

-- -----------------------------------------------------------------------------
-- STEP 3: INSERT FROM raw.medicare_spending with cleaning.
--
--   Cleaning rules applied to every column:
--     a) NULLIF(col, '*')   -- explicit handling of CMS suppression marker
--     b) NULLIF(NULLIF(col, '*'), '')  -- empty strings -> NULL too
--     c) TRY_CAST(... AS <type>)  -- any other unparseable value -> NULL
--
--   Why NULLIF before TRY_CAST and not just rely on TRY_CAST to fail?
--   TRY_CAST('*' AS DECIMAL) does return NULL — but the explicit NULLIF
--   documents that we KNOW about CMS suppression, which is what an
--   interviewer wants to hear. "Defensive AND legible."
--
--   Filter: BENE_GEO_LVL = 'County' only.
--   This drops:
--     - 30 National rows (not at our analytical grain)
--     - 1,650 State rows (not at our analytical grain)
--   And keeps:
--     - 31,959 County rows
-- -----------------------------------------------------------------------------
INSERT INTO clean.medicare_spending (
    geo_lvl, state_abbrev, county_desc, county_fips,
    year_id, bene_age_lvl,
    benes_ffs_cnt, benes_total_cnt,
    tot_mdcr_stdzd_pymt_pc, ip_mdcr_stdzd_pymt_pc, op_mdcr_stdzd_pymt_pc,
    er_visits_per_1000, acute_hosp_readmsn_pct,
    pqi03_dbts_age_lt_65, pqi03_dbts_age_65_74, pqi03_dbts_age_ge_75,
    pqi05_copd_asthma_age_40_64, pqi05_copd_asthma_age_65_74, pqi05_copd_asthma_age_ge_75,
    pqi07_hyprtnsn_age_lt_65, pqi07_hyprtnsn_age_65_74, pqi07_hyprtnsn_age_ge_75,
    pqi08_chf_age_lt_65, pqi08_chf_age_65_74, pqi08_chf_age_ge_75,
    pqi11_bctrl_pna_age_lt_65, pqi11_bctrl_pna_age_65_74, pqi11_bctrl_pna_age_ge_75,
    inpatient_spend_share, outpatient_spend_share
)
SELECT
    -- ---- Dimensions ----
    BENE_GEO_LVL                                                                 AS geo_lvl,--Takes the raw column BENE_GEO_LVL and renames it to geo_lvl.
    -- BENE_GEO_DESC at county grain looks like 'DE-Kent', 'TX-Upton', 'FL-Miami-Dade'.
    -- We split on the FIRST hyphen via CHARINDEX. CHARINDEX returns the position
    -- of the FIRST occurrence, so counties with hyphens in their names (Miami-Dade)
    -- parse correctly: state_abbrev = 'FL', county_desc = 'Miami-Dade'.
    LEFT(BENE_GEO_DESC, CHARINDEX('-', BENE_GEO_DESC) - 1)                       AS state_abbrev,--extracts the state abbreviation from a value, ex:TX-Upton → TX
    LTRIM(RTRIM(SUBSTRING(BENE_GEO_DESC, CHARINDEX('-', BENE_GEO_DESC) + 1, LEN(BENE_GEO_DESC)))) AS county_desc,--extracts the county name after the first hyphen,ex:TX-Upton → Upton
    -- Defensive 5-char zero-pad. Source is already 5-char, but this protects
    -- against any future re-load where FIPS arrives without padding (e.g., Excel
    -- silently dropping the leading zero on Alabama's 4-digit FIPS values).
    RIGHT('00000' + LTRIM(RTRIM(BENE_GEO_CD)), 5)                                AS county_fips,--forces FIPS to always be 5 digits,ex:1001 → 01001. Zero-padded FIPS to protect joins, because leading zeros are meaningful
    TRY_CAST(NULLIF([YEAR], '*') AS INT)                                         AS year_id,--converts year from text to integer.
    BENE_AGE_LVL                                                                 AS bene_age_lvl,--Copies age level into the clean table.

    -- ---- Beneficiary counts ----
    TRY_CAST(NULLIF(NULLIF(BENES_FFS_CNT,   '*'), '') AS BIGINT)                 AS benes_ffs_cnt,--Takes a messy text column and safely convert it into a number, while handling bad values like * and empty strings
    TRY_CAST(NULLIF(NULLIF(BENES_TOTAL_CNT, '*'), '') AS BIGINT)                 AS benes_total_cnt,

    -- ---- Headline spend + ER + readmission ----
    TRY_CAST(NULLIF(NULLIF(TOT_MDCR_STDZD_PYMT_PC, '*'), '') AS DECIMAL(12,2))   AS tot_mdcr_stdzd_pymt_pc,--Clean the total Medicare spending per capita column and convert it to a money-like number.
    TRY_CAST(NULLIF(NULLIF(IP_MDCR_STDZD_PYMT_PC,  '*'), '') AS DECIMAL(12,2))   AS ip_mdcr_stdzd_pymt_pc,
    TRY_CAST(NULLIF(NULLIF(OP_MDCR_STDZD_PYMT_PC,  '*'), '') AS DECIMAL(12,2))   AS op_mdcr_stdzd_pymt_pc,
    TRY_CAST(NULLIF(NULLIF(ER_VISITS_PER_1000_BENES, '*'), '') AS DECIMAL(10,2)) AS er_visits_per_1000,
    TRY_CAST(NULLIF(NULLIF(ACUTE_HOSP_READMSN_PCT, '*'), '') AS DECIMAL(8,4))    AS acute_hosp_readmsn_pct,

    -- ---- PQI03 Diabetes ----
    TRY_CAST(NULLIF(NULLIF(PQI03_DBTS_AGE_LT_65,  '*'), '') AS DECIMAL(10,4))    AS pqi03_dbts_age_lt_65,--If CMS suppressed or left the value blank, store NULL. Otherwise, store it as a decimal number.
    TRY_CAST(NULLIF(NULLIF(PQI03_DBTS_AGE_65_74,  '*'), '') AS DECIMAL(10,4))    AS pqi03_dbts_age_65_74,
    TRY_CAST(NULLIF(NULLIF(PQI03_DBTS_AGE_GE_75,  '*'), '') AS DECIMAL(10,4))    AS pqi03_dbts_age_ge_75,

    -- ---- PQI05 COPD/Asthma ----
    TRY_CAST(NULLIF(NULLIF(PQI05_COPD_ASTHMA_AGE_40_64, '*'), '') AS DECIMAL(10,4)) AS pqi05_copd_asthma_age_40_64,
    TRY_CAST(NULLIF(NULLIF(PQI05_COPD_ASTHMA_AGE_65_74, '*'), '') AS DECIMAL(10,4)) AS pqi05_copd_asthma_age_65_74,
    TRY_CAST(NULLIF(NULLIF(PQI05_COPD_ASTHMA_AGE_GE_75, '*'), '') AS DECIMAL(10,4)) AS pqi05_copd_asthma_age_ge_75,

    -- ---- PQI07 Hypertension ----
    TRY_CAST(NULLIF(NULLIF(PQI07_HYPRTNSN_AGE_LT_65, '*'), '') AS DECIMAL(10,4)) AS pqi07_hyprtnsn_age_lt_65,
    TRY_CAST(NULLIF(NULLIF(PQI07_HYPRTNSN_AGE_65_74, '*'), '') AS DECIMAL(10,4)) AS pqi07_hyprtnsn_age_65_74,
    TRY_CAST(NULLIF(NULLIF(PQI07_HYPRTNSN_AGE_GE_75, '*'), '') AS DECIMAL(10,4)) AS pqi07_hyprtnsn_age_ge_75,

    -- ---- PQI08 CHF ----
    TRY_CAST(NULLIF(NULLIF(PQI08_CHF_AGE_LT_65, '*'), '') AS DECIMAL(10,4))      AS pqi08_chf_age_lt_65,
    TRY_CAST(NULLIF(NULLIF(PQI08_CHF_AGE_65_74, '*'), '') AS DECIMAL(10,4))      AS pqi08_chf_age_65_74,
    TRY_CAST(NULLIF(NULLIF(PQI08_CHF_AGE_GE_75, '*'), '') AS DECIMAL(10,4))      AS pqi08_chf_age_ge_75,

    -- ---- PQI11 Bacterial Pneumonia ----
    TRY_CAST(NULLIF(NULLIF(PQI11_BCTRL_PNA_AGE_LT_65, '*'), '') AS DECIMAL(10,4)) AS pqi11_bctrl_pna_age_lt_65,
    TRY_CAST(NULLIF(NULLIF(PQI11_BCTRL_PNA_AGE_65_74, '*'), '') AS DECIMAL(10,4)) AS pqi11_bctrl_pna_age_65_74,
    TRY_CAST(NULLIF(NULLIF(PQI11_BCTRL_PNA_AGE_GE_75, '*'), '') AS DECIMAL(10,4)) AS pqi11_bctrl_pna_age_ge_75,

    -- ---- Engineered: spend shares ----
    -- inpatient_spend_share = IP per-capita / TOT per-capita
    -- NULLIF on the denominator avoids divide-by-zero exception (returns NULL)
    -- These will only be non-NULL where both IP and TOT are non-NULL and TOT > 0.
    CASE
        WHEN TRY_CAST(NULLIF(NULLIF(TOT_MDCR_STDZD_PYMT_PC, '*'), '') AS DECIMAL(12,2)) > 0--Calculate (inpatient spending / total spending) only when total spending is greater than 0
        THEN TRY_CAST(NULLIF(NULLIF(IP_MDCR_STDZD_PYMT_PC,  '*'), '') AS DECIMAL(12,2))
             / TRY_CAST(NULLIF(NULLIF(TOT_MDCR_STDZD_PYMT_PC, '*'), '') AS DECIMAL(12,2))
        ELSE NULL
    END                                                                          AS inpatient_spend_share,

    CASE
        WHEN TRY_CAST(NULLIF(NULLIF(TOT_MDCR_STDZD_PYMT_PC, '*'), '') AS DECIMAL(12,2)) > 0--Calculate (outpatient spending / total spending) only when total spending is greater than 0
        THEN TRY_CAST(NULLIF(NULLIF(OP_MDCR_STDZD_PYMT_PC,  '*'), '') AS DECIMAL(12,2))
             / TRY_CAST(NULLIF(NULLIF(TOT_MDCR_STDZD_PYMT_PC, '*'), '') AS DECIMAL(12,2))
        ELSE NULL
    END                                                                          AS outpatient_spend_share

FROM raw.medicare_spending
WHERE BENE_GEO_LVL = 'County';

PRINT CONCAT('Inserted ', @@ROWCOUNT, ' rows into clean.medicare_spending');--prints how many rows were inserted.
GO


-- =============================================================================
-- STEP 4: VALIDATION BLOCK
--
--   Six validation queries. Each checks one specific assumption.
--   If any fails its expected value, stop and investigate before moving on.
-- =============================================================================

-- Validation 1: Total row count (expect 31,959)
PRINT '=== Validation 1: Total row count (expect 31,959) ===';
SELECT COUNT(*) AS row_count FROM clean.medicare_spending;--Checks total row count.

-- Validation 2: Year distribution (expect 2014-2023, 10 years)
PRINT '=== Validation 2: Year distribution (expect 2014-2023, ~3,196 rows/year) ===';--Checks how many rows exist per year.
SELECT year_id, COUNT(*) AS row_count
FROM clean.medicare_spending
GROUP BY year_id
ORDER BY year_id;

-- Validation 3: bene_age_lvl distribution (expect 'All' only, since CMS suppresses
-- age splits at county grain).
PRINT '=== Validation 3: bene_age_lvl distribution (expect All only) ===';--Checks age group.
SELECT bene_age_lvl, COUNT(*) AS row_count
FROM clean.medicare_spending
GROUP BY bene_age_lvl;

-- Validation 4: County FIPS format check (all should be exactly 5 chars)
PRINT '=== Validation 4: County FIPS length check (all should be 5 chars) ===';--Checks FIPS length.
SELECT LEN(county_fips) AS fips_length, COUNT(*) AS row_count
FROM clean.medicare_spending
GROUP BY LEN(county_fips);

-- Validation 5: Spot-check Upton County, TX 2022 — must match script 04 (~$25.8k per capita)
-- This is the load-tying-back check. If this number is off, something in the cast went wrong.
PRINT '=== Validation 5: Upton County TX 2022 spot check (expect ~$25,800 per capita) ===';
SELECT
    state_abbrev,
    county_desc,
    year_id,
    benes_ffs_cnt,
    tot_mdcr_stdzd_pymt_pc,
    ip_mdcr_stdzd_pymt_pc,
    op_mdcr_stdzd_pymt_pc,
    er_visits_per_1000,
    inpatient_spend_share,
    outpatient_spend_share
FROM clean.medicare_spending
WHERE state_abbrev = 'TX'
  AND county_desc LIKE 'Upton%'
  AND year_id = 2022;

-- Validation 6: Suppression and missingness rates on the headline KPI.
-- We expect SOME suppression/missing data — CMS suppresses small-cell counties.
-- Knowing the rate is essential for the case study's data-quality section.
PRINT '=== Validation 6: Headline KPI completeness (expect some NULLs from CMS suppression) ===';
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN tot_mdcr_stdzd_pymt_pc IS NULL THEN 1 ELSE 0 END) AS null_rows,--Counts how many rows have missing total Medicare spending.
    CAST(100.0 * SUM(CASE WHEN tot_mdcr_stdzd_pymt_pc IS NULL THEN 1 ELSE 0 END)--calculates the percent missing.
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) AS pct_null
FROM clean.medicare_spending;

-- Validation 7: Spend share sanity — IP + OP shares should be in [0, 1]
-- (with the residual going to non-decomposed categories like SNF, hospice, etc.)
PRINT '=== Validation 7: Spend share range check (top 5 IP-share counties, 2022) ===';
SELECT TOP 5
    state_abbrev,
    county_desc,
    year_id,
    inpatient_spend_share,
    outpatient_spend_share,
    inpatient_spend_share + outpatient_spend_share AS ip_op_combined_share--Checks whether inpatient share + outpatient share looks reasonable (it should not necessarily equal 1)
FROM clean.medicare_spending
WHERE year_id = 2022
  AND inpatient_spend_share IS NOT NULL
  AND outpatient_spend_share IS NOT NULL
ORDER BY inpatient_spend_share DESC;

GO
