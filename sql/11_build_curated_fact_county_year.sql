-- =============================================================================
-- 11_build_curated_fact_county_year.sql
--
-- BIG PICTURE
--   This is the final table before Tableau. It joins everything together:
--
--     clean.medicare_spending   → Medicare spending, ER visits, PQI rates
--     curated.county_year_panel → pharmacy counts and density
--     clean.rucc_codes          → rural/urban classification (RUCC 1-9)
--
--   Think of this table as the "answer sheet." Every row is one county in
--   one year, with all the numbers Tableau needs to draw the charts:
--     - How rural is this county? (RUCC code)
--     - How many pharmacies does it have per 10k Medicare patients?
--     - How much does Medicare spend there per person?
--     - How often do patients end up in the ER or hospital?
--
-- WHY use clean.medicare_spending as the base table?
--   It contains the full universe of counties CMS tracks (all 3,000+ counties
--   in the US). If we started from county_year_panel instead, we would miss
--   counties that have ZERO pharmacies in our data — and those are the most
--   extreme pharmacy deserts! By starting from Medicare and LEFT JOINing
--   pharmacies, those counties appear with NULL pharmacy metrics, which is
--   the honest representation.
--
-- GRAIN: one row per county per year (same as county_year_panel).
--        Five years: 2019, 2020, 2021, 2022, 2023.
--
-- KEY JOINS
--   Medicare → county_year_panel : LEFT JOIN on county_fips + year_id
--     (counties with no pharmacies get NULL pharmacy metrics)
--   Medicare → rucc_codes        : LEFT JOIN on county_fips
--     (counties not in USDA RUCC — mostly Pacific territories — get NULL RUCC)
--
-- KNOWN LIMITATION (disclose in case study)
--   pharmacy_count_change_2019_2023 is biased toward positive values because
--   permanently closed pharmacies are missing from NPPES single-snapshot data.
--   See CLAUDE.md §7 for the full explanation.
--
-- AUTHOR / DATE
--   Marie Christine Assouad, 2026-06-22
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- STEP 1: Drop and recreate curated.fact_county_year (idempotent)
-- -----------------------------------------------------------------------------
-- curated schema already exists from script 10.
IF OBJECT_ID('curated.fact_county_year', 'U') IS NOT NULL
BEGIN
    DROP TABLE curated.fact_county_year;
    PRINT 'Dropped existing curated.fact_county_year.';
END
GO

CREATE TABLE curated.fact_county_year (

    -- =========================================================================
    -- DIMENSIONS — who and when
    -- =========================================================================
    county_fips                       CHAR(5)        NOT NULL,  -- 5-digit county FIPS code (join key)
    year_id                           INT            NOT NULL,  -- 2019–2023

    -- Geographic labels (from Medicare)
    state_abbrev                      CHAR(2)        NULL,      -- TX, FL, CA ...
    county_desc                       VARCHAR(100)   NULL,      -- Upton, Miami-Dade ...

    -- Rural/urban classification (from USDA RUCC)
    -- rucc_code: 1 = most urban, 9 = most rural
    -- rural_urban_group: simplified to Metro (1-3) or Nonmetro (4-9)
    rucc_code                         TINYINT        NULL,
    rural_urban_group                 VARCHAR(10)    NULL,      -- 'Metro' or 'Nonmetro'
    rucc_description                  VARCHAR(500)   NULL,      -- full USDA label

    -- =========================================================================
    -- PHARMACY METRICS — from curated.county_year_panel
    -- NULL means this county had zero pharmacies in our data that year.
    -- =========================================================================
    active_pharmacies                 INT            NULL,
    openings_in_year                  INT            NULL,
    closures_in_year                  INT            NULL,      -- ~0; NPPES limitation
    pharmacies_per_10k_benes          DECIMAL(10,4)  NULL,      -- PRIMARY ACCESS METRIC
    pharmacy_count_change_2019_2023   INT            NULL,      -- 2023 minus 2019 active count
    pharmacy_density_change_2019_2023 DECIMAL(10,4)  NULL,      -- 2023 minus 2019 density

    -- =========================================================================
    -- MEDICARE BENEFICIARY COUNTS — from clean.medicare_spending
    -- =========================================================================
    benes_ffs_cnt                     BIGINT         NULL,      -- fee-for-service beneficiaries
    benes_total_cnt                   BIGINT         NULL,      -- all Medicare beneficiaries

    -- =========================================================================
    -- MEDICARE SPEND — PRIMARY OUTCOME VARIABLE
    -- tot_mdcr_stdzd_pymt_pc is the headline KPI for the dashboard.
    -- "Standardized" means CMS has removed the effect of local price differences
    -- so counties are comparable apples-to-apples.
    -- =========================================================================
    tot_mdcr_stdzd_pymt_pc            DECIMAL(12,2)  NULL,      -- total spend per beneficiary
    ip_mdcr_stdzd_pymt_pc             DECIMAL(12,2)  NULL,      -- inpatient spend per beneficiary
    op_mdcr_stdzd_pymt_pc             DECIMAL(12,2)  NULL,      -- outpatient spend per beneficiary
    inpatient_spend_share             DECIMAL(8,6)   NULL,      -- IP / TOT (engineered in script 05)
    outpatient_spend_share            DECIMAL(8,6)   NULL,      -- OP / TOT (engineered in script 05)

    -- =========================================================================
    -- UTILIZATION — how often patients use services
    -- =========================================================================
    er_visits_per_1000                DECIMAL(10,2)  NULL,      -- ER visits per 1,000 beneficiaries
    acute_hosp_readmsn_pct            DECIMAL(8,4)   NULL,      -- % readmitted within 30 days

    -- =========================================================================
    -- PQI RATES — Prevention Quality Indicators
    -- These measure hospitalizations that could have been avoided with
    -- good medication access and adherence. The analytical bridge from
    -- "fewer pharmacies" to "higher Medicare spending."
    --
    -- 5 conditions × 3 age bands = 15 columns.
    -- Age bands: lt_65 = under 65, 65_74 = age 65-74, ge_75 = age 75+
    -- Exception: COPD (PQI05) uses age_40_64 instead of lt_65.
    -- Units: admissions per 100,000 beneficiaries in that age group.
    -- =========================================================================

    -- Diabetes (PQI03)
    pqi03_dbts_age_lt_65              DECIMAL(10,4)  NULL,
    pqi03_dbts_age_65_74              DECIMAL(10,4)  NULL,
    pqi03_dbts_age_ge_75              DECIMAL(10,4)  NULL,

    -- COPD / Asthma (PQI05)
    pqi05_copd_asthma_age_40_64       DECIMAL(10,4)  NULL,
    pqi05_copd_asthma_age_65_74       DECIMAL(10,4)  NULL,
    pqi05_copd_asthma_age_ge_75       DECIMAL(10,4)  NULL,

    -- Hypertension / High Blood Pressure (PQI07)
    -- Most pharmacy-adherence-sensitive condition: miss your BP meds → ER visit
    pqi07_hyprtnsn_age_lt_65          DECIMAL(10,4)  NULL,
    pqi07_hyprtnsn_age_65_74          DECIMAL(10,4)  NULL,
    pqi07_hyprtnsn_age_ge_75          DECIMAL(10,4)  NULL,

    -- Congestive Heart Failure (PQI08)
    pqi08_chf_age_lt_65               DECIMAL(10,4)  NULL,
    pqi08_chf_age_65_74               DECIMAL(10,4)  NULL,
    pqi08_chf_age_ge_75               DECIMAL(10,4)  NULL,

    -- Bacterial Pneumonia (PQI11)
    pqi11_bctrl_pna_age_lt_65         DECIMAL(10,4)  NULL,
    pqi11_bctrl_pna_age_65_74         DECIMAL(10,4)  NULL,
    pqi11_bctrl_pna_age_ge_75         DECIMAL(10,4)  NULL,

    -- Clustered PK on the join keys Tableau will use
    CONSTRAINT PK_curated_fact_county_year
        PRIMARY KEY CLUSTERED (county_fips, year_id)
);
GO

PRINT 'Created curated.fact_county_year.';
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Insert — join the three source tables
-- -----------------------------------------------------------------------------
-- WHY LEFT JOIN for both pharmacy panel and RUCC?
--   Medicare is our base — it has the complete county universe.
--   LEFT JOIN means: keep every Medicare county-year even if pharmacy data
--   or RUCC data is missing. Those NULLs are informative, not errors.
--
-- WHY filter year_id IN (2019..2023)?
--   Medicare has 2014-2023 but our pharmacy panel only covers 2019-2023.
--   We align the fact table to the narrower window so the pharmacy metrics
--   are always available for every row in the table.
--
-- WHY bene_age_lvl = 'All'?
--   County-grain Medicare rows only have age_lvl = 'All' (confirmed script 05).

INSERT INTO curated.fact_county_year (
    county_fips, year_id,
    state_abbrev, county_desc,
    rucc_code, rural_urban_group, rucc_description,
    active_pharmacies, openings_in_year, closures_in_year,
    pharmacies_per_10k_benes,
    pharmacy_count_change_2019_2023,
    pharmacy_density_change_2019_2023,
    benes_ffs_cnt, benes_total_cnt,
    tot_mdcr_stdzd_pymt_pc,
    ip_mdcr_stdzd_pymt_pc,
    op_mdcr_stdzd_pymt_pc,
    inpatient_spend_share, outpatient_spend_share,
    er_visits_per_1000, acute_hosp_readmsn_pct,
    pqi03_dbts_age_lt_65, pqi03_dbts_age_65_74, pqi03_dbts_age_ge_75,
    pqi05_copd_asthma_age_40_64, pqi05_copd_asthma_age_65_74, pqi05_copd_asthma_age_ge_75,
    pqi07_hyprtnsn_age_lt_65, pqi07_hyprtnsn_age_65_74, pqi07_hyprtnsn_age_ge_75,
    pqi08_chf_age_lt_65, pqi08_chf_age_65_74, pqi08_chf_age_ge_75,
    pqi11_bctrl_pna_age_lt_65, pqi11_bctrl_pna_age_65_74, pqi11_bctrl_pna_age_ge_75
)
SELECT
    -- Keys
    m.county_fips,
    m.year_id,

    -- Geographic labels
    m.state_abbrev,
    m.county_desc,

    -- RUCC classification
    r.rucc_code,
    r.rural_urban_group,
    r.rucc_description,                    -- "Metro area, pop 250k-1M" etc.

    -- Pharmacy metrics (NULL if county has no pharmacies)
    p.active_pharmacies,
    p.openings_in_year,
    p.closures_in_year,
    p.pharmacies_per_10k_benes,
    p.pharmacy_count_change_2019_2023,
    p.pharmacy_density_change_2019_2023,

    -- Medicare beneficiary counts
    m.benes_ffs_cnt,
    m.benes_total_cnt,

    -- Medicare spend
    m.tot_mdcr_stdzd_pymt_pc,
    m.ip_mdcr_stdzd_pymt_pc,
    m.op_mdcr_stdzd_pymt_pc,
    m.inpatient_spend_share,
    m.outpatient_spend_share,

    -- Utilization
    m.er_visits_per_1000,
    m.acute_hosp_readmsn_pct,

    -- PQI rates
    m.pqi03_dbts_age_lt_65,
    m.pqi03_dbts_age_65_74,
    m.pqi03_dbts_age_ge_75,
    m.pqi05_copd_asthma_age_40_64,
    m.pqi05_copd_asthma_age_65_74,
    m.pqi05_copd_asthma_age_ge_75,
    m.pqi07_hyprtnsn_age_lt_65,
    m.pqi07_hyprtnsn_age_65_74,
    m.pqi07_hyprtnsn_age_ge_75,
    m.pqi08_chf_age_lt_65,
    m.pqi08_chf_age_65_74,
    m.pqi08_chf_age_ge_75,
    m.pqi11_bctrl_pna_age_lt_65,
    m.pqi11_bctrl_pna_age_65_74,
    m.pqi11_bctrl_pna_age_ge_75

FROM clean.medicare_spending AS m

    -- Pharmacy panel: LEFT JOIN so counties with 0 pharmacies still appear
    LEFT JOIN curated.county_year_panel AS p
        ON  m.county_fips = p.county_fips
        AND m.year_id     = p.year_id

    -- RUCC: LEFT JOIN so Pacific territories (no RUCC) still appear
    LEFT JOIN clean.rucc_codes AS r
        ON m.county_fips = r.county_fips

WHERE m.year_id      IN (2019, 2020, 2021, 2022, 2023)
  AND m.bene_age_lvl = 'All';   -- county grain only has 'All' (confirmed script 05)

GO

PRINT 'INSERT into curated.fact_county_year complete.';
GO

-- =============================================================================
-- STEP 3: Validation queries — the most important block in the project.
--         These 7 queries confirm the joins worked AND preview the story
--         the dashboard will tell. Save the output — it goes in the case study.
-- =============================================================================

-- ----- Validation 1: Row count -----
-- Expect: ~15,900 rows (roughly 3,180 Medicare counties × 5 years).
-- Slightly higher than county_year_panel because Medicare includes counties
-- with zero pharmacies in our data.
PRINT '=== Validation 1: Row count (expect ~15,900) ===';
SELECT COUNT(*) AS total_rows FROM curated.fact_county_year;
GO

-- ----- Validation 2: Year distribution -----
-- Expect: same county count in every year.
PRINT '=== Validation 2: Row count by year ===';
SELECT
    year_id,
    COUNT(*) AS county_year_rows
FROM curated.fact_county_year
GROUP BY year_id
ORDER BY year_id;
GO

-- ----- Validation 3: Join coverage -----
-- How many county-years have pharmacy data? How many have RUCC data?
-- Expect: ~98% RUCC coverage (62 counties unmatched, all explainable — see CLAUDE.md §10).
-- Pharmacy coverage will be lower — some counties truly have no pharmacies in our data.
PRINT '=== Validation 3: Join coverage for pharmacy and RUCC data ===';
SELECT
    year_id,
    COUNT(*)                                                        AS total_county_years,
    SUM(CASE WHEN active_pharmacies IS NOT NULL THEN 1 ELSE 0 END) AS has_pharmacy_data,
    SUM(CASE WHEN rucc_code         IS NOT NULL THEN 1 ELSE 0 END) AS has_rucc_data,
    CAST(100.0 * SUM(CASE WHEN active_pharmacies IS NOT NULL THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,1))                               AS pct_with_pharmacy,
    CAST(100.0 * SUM(CASE WHEN rucc_code IS NOT NULL THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,1))                               AS pct_with_rucc
FROM curated.fact_county_year
GROUP BY year_id
ORDER BY year_id;
GO

-- ----- Validation 4: Spot check — TX-Upton 2022 -----
-- Our running reference county. Confirm Medicare spend ties back to script 05
-- (~$25,800) and pharmacy numbers tie back to script 10 (3-4 pharmacies).
PRINT '=== Validation 4: Spot check — TX-Upton 2022 (FIPS 48461) ===';
SELECT
    county_fips, year_id,
    state_abbrev, county_desc,
    rucc_code, rural_urban_group,
    active_pharmacies,
    pharmacies_per_10k_benes,
    benes_ffs_cnt,
    tot_mdcr_stdzd_pymt_pc,
    er_visits_per_1000
FROM curated.fact_county_year
WHERE county_fips = '48461'
  AND year_id     = 2022;
GO

-- ----- Validation 5: THE KEY FINDING — spend by rural/urban group (2023) -----
-- This is the headline result for the dashboard and case study.
-- Hypothesis: Nonmetro counties have HIGHER Medicare spend per person.
-- If the numbers show that, the data supports the pharmacy desert story.
-- If not — we report what we find and discuss why (confounders, age mix, etc.)
PRINT '=== Validation 5: Average Medicare spend by rural/urban group (2023) ===';
SELECT
    rural_urban_group,
    COUNT(*)                                            AS county_count,
    CAST(AVG(tot_mdcr_stdzd_pymt_pc)  AS DECIMAL(10,2)) AS avg_medicare_spend,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,4)) AS avg_pharmacy_density,
    CAST(AVG(er_visits_per_1000)       AS DECIMAL(8,2)) AS avg_er_visits_per_1000
FROM curated.fact_county_year
WHERE year_id              = 2023
  AND rural_urban_group    IS NOT NULL
  AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
GROUP BY rural_urban_group
ORDER BY avg_medicare_spend DESC;
GO

-- ----- Validation 6: Spend by RUCC code (2023) -----
-- Goes one level deeper than Metro/Nonmetro — shows the full 1-9 gradient.
-- Expect: spend should generally rise as RUCC code increases (more rural).
-- Any breaks in that pattern are interesting analytical talking points.
PRINT '=== Validation 6: Average Medicare spend by RUCC code (2023) ===';
SELECT
    rucc_code,
    rural_urban_group,
    COUNT(*)                                            AS county_count,
    CAST(AVG(tot_mdcr_stdzd_pymt_pc)  AS DECIMAL(10,2)) AS avg_medicare_spend,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,4)) AS avg_pharmacy_density
FROM curated.fact_county_year
WHERE year_id              = 2023
  AND rucc_code            IS NOT NULL
  AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
GROUP BY rucc_code, rural_urban_group
ORDER BY rucc_code;
GO

-- ----- Validation 7: Top 10 highest-spend counties 2023 — are they rural? -----
-- Confirms the hypothesis is alive: the counties costing Medicare the most
-- should be rural (high RUCC code) and pharmacy-poor (low density).
-- Screenshot this — it is the visual centerpiece of the case study.
PRINT '=== Validation 7: Top 10 highest Medicare spend counties (2023) ===';
SELECT TOP 10
    county_fips,
    state_abbrev,
    county_desc,
    rucc_code,
    rural_urban_group,
    active_pharmacies,
    pharmacies_per_10k_benes,
    benes_ffs_cnt,
    tot_mdcr_stdzd_pymt_pc
FROM curated.fact_county_year
WHERE year_id = 2023
  AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
ORDER BY tot_mdcr_stdzd_pymt_pc DESC;
GO

PRINT '=== All 7 validations complete. curated.fact_county_year is ready for Tableau. ===';
GO
