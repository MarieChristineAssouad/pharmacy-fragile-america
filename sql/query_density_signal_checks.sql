-- =============================================================================
-- query_density_signal_checks.sql
--
-- Two follow-up queries to find where the pharmacy density signal lives.
--
-- QUERY A: Same density bucket analysis, Nonmetro counties only.
--   Removes urban counties so we compare rural to rural.
--   If the hypothesis is right, spending should DROP as density rises here.
--
-- QUERY B: Density buckets vs ER visits (all counties).
--   ER visits are a more direct measure of "people who couldn't manage
--   their condition at home." If pharmacy deserts drive ER use, the signal
--   should be clearest here — bucket 1 (fewest pharmacies) should have
--   the MOST ER visits per 1,000 patients.
-- =============================================================================

USE pharmacy_medicare_project;

-- =============================================================================
-- QUERY A: Density vs Medicare spend — Nonmetro counties only (2023)
-- =============================================================================
PRINT '=== Query A: Density buckets vs Medicare spend — Nonmetro only ===';

WITH density_buckets_nonmetro AS (
    SELECT
        pharmacies_per_10k_benes,
        tot_mdcr_stdzd_pymt_pc,
        NTILE(5) OVER (ORDER BY pharmacies_per_10k_benes ASC) AS density_bucket
    FROM curated.fact_county_year
    WHERE year_id                  = 2023
      AND pharmacies_per_10k_benes IS NOT NULL
      AND tot_mdcr_stdzd_pymt_pc   IS NOT NULL
      AND benes_ffs_cnt            >= 500
      AND rural_urban_group        = 'Nonmetro'  -- rural counties only
)
SELECT
    density_bucket,
    COUNT(*)                                             AS county_count,
    CAST(MIN(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS min_density,
    CAST(MAX(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS max_density,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS avg_density,
    CAST(AVG(tot_mdcr_stdzd_pymt_pc)  AS DECIMAL(10,2)) AS avg_medicare_spend
FROM density_buckets_nonmetro
GROUP BY density_bucket
ORDER BY density_bucket;

-- =============================================================================
-- QUERY B: Density vs ER visits — all counties (2023)
-- =============================================================================
PRINT '=== Query B: Density buckets vs ER visits per 1,000 — all counties ===';

WITH density_buckets_er AS (
    SELECT
        pharmacies_per_10k_benes,
        er_visits_per_1000,
        NTILE(5) OVER (ORDER BY pharmacies_per_10k_benes ASC) AS density_bucket
    FROM curated.fact_county_year
    WHERE year_id                  = 2023
      AND pharmacies_per_10k_benes IS NOT NULL
      AND er_visits_per_1000       IS NOT NULL
      AND benes_ffs_cnt            >= 500
)
SELECT
    density_bucket,
    COUNT(*)                                             AS county_count,
    CAST(MIN(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS min_density,
    CAST(MAX(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS max_density,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,2)) AS avg_density,
    CAST(AVG(er_visits_per_1000)       AS DECIMAL(10,2)) AS avg_er_visits_per_1000
FROM density_buckets_er
GROUP BY density_bucket
ORDER BY density_bucket;
