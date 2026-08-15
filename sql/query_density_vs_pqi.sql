-- =============================================================================
-- query_density_vs_pqi.sql
--
-- Testing the pharmacy access → preventable hospitalization relationship.
--
-- PQI = Prevention Quality Indicator. These measure hospital admissions for
-- conditions that should have been managed at home with medication.
-- If a patient can't get their medication because there's no nearby pharmacy,
-- they end up in the hospital instead. That shows up in PQI rates.
--
-- We focus on two conditions most directly tied to medication access:
--   PQI07 — Hypertension (high blood pressure). Miss your BP pills → ER visit.
--   PQI03 — Diabetes. Miss your insulin or metformin → hospitalization.
--
-- Age band: 65-74 (the core Medicare population — old enough to be on Medicare,
-- young enough that the rates aren't dominated by end-of-life complexity).
--
-- QUERY A: Density buckets vs PQI rates — all counties (2023)
--   If the hypothesis holds: bucket 1 (fewest pharmacies) should have the
--   HIGHEST preventable hospitalization rates. Numbers should DROP going
--   from bucket 1 to bucket 5.
--
-- QUERY B: The extreme cases — counties with 0 or 1 pharmacy (2023)
--   These are the true pharmacy deserts. Show their PQI rates directly
--   alongside Medicare spend. These rows go straight into the case study.
-- =============================================================================

USE pharmacy_medicare_project;

-- =============================================================================
-- QUERY A: Density buckets vs PQI rates (2023, benes >= 500)
-- =============================================================================
PRINT '=== Query A: Density buckets vs preventable hospitalization rates ===';

WITH density_buckets AS (
    SELECT
        pharmacies_per_10k_benes,
        pqi07_hyprtnsn_age_65_74,   -- hypertension admissions, age 65-74
        pqi03_dbts_age_65_74,       -- diabetes admissions, age 65-74
        tot_mdcr_stdzd_pymt_pc,
        NTILE(5) OVER (ORDER BY pharmacies_per_10k_benes ASC) AS density_bucket
    FROM curated.fact_county_year
    WHERE year_id                  = 2023
      AND pharmacies_per_10k_benes IS NOT NULL
      AND benes_ffs_cnt            >= 500
)
SELECT
    density_bucket,
    COUNT(*)                                                    AS county_count,
    CAST(AVG(pharmacies_per_10k_benes)  AS DECIMAL(8,2))       AS avg_density,
    CAST(AVG(pqi07_hyprtnsn_age_65_74)  AS DECIMAL(10,2))      AS avg_hypertension_admissions,
    CAST(AVG(pqi03_dbts_age_65_74)      AS DECIMAL(10,2))      AS avg_diabetes_admissions,
    CAST(AVG(tot_mdcr_stdzd_pymt_pc)    AS DECIMAL(10,2))      AS avg_medicare_spend
FROM density_buckets
GROUP BY density_bucket
ORDER BY density_bucket;

-- =============================================================================
-- QUERY B: True pharmacy deserts — counties with 0 or 1 pharmacy (2023)
-- =============================================================================
-- These are the most extreme cases. No pharmacy = patients drive hours
-- or simply go without medication. Show their PQI rates and Medicare spend.
-- Filter benes >= 200 (lower threshold because these counties are tiny by nature).
PRINT '=== Query B: True pharmacy deserts (0 or 1 pharmacy) — 2023 ===';

SELECT
    county_fips,
    state_abbrev,
    county_desc,
    rucc_code,
    rural_urban_group,
    active_pharmacies,
    benes_ffs_cnt,
    pharmacies_per_10k_benes,
    tot_mdcr_stdzd_pymt_pc,
    pqi07_hyprtnsn_age_65_74    AS hypertension_admissions_65_74,
    pqi03_dbts_age_65_74        AS diabetes_admissions_65_74,
    er_visits_per_1000
FROM curated.fact_county_year
WHERE year_id          = 2023
  AND active_pharmacies <= 1       -- zero or one pharmacy
  AND benes_ffs_cnt    >= 200      -- enough patients for rates to be meaningful
  AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
ORDER BY tot_mdcr_stdzd_pymt_pc DESC;
