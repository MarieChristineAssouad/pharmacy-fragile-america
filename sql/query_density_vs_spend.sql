-- =============================================================================
-- query_density_vs_spend.sql
--
-- QUESTION: As pharmacy density goes up, does Medicare spending go down?
--
-- HOW IT WORKS:
--   We take all counties in 2023, sort them by pharmacy density from lowest
--   to highest, and split them into 5 equal groups (called "quintiles").
--   Group 1 = the 20% of counties with the FEWEST pharmacies per patient.
--   Group 5 = the 20% of counties with the MOST pharmacies per patient.
--   Then we look at average Medicare spending in each group.
--
--   If our hypothesis is right: Group 1 should have the HIGHEST spending,
--   and the numbers should drop as we move toward Group 5.
--
-- FILTER: benes_ffs_cnt >= 500
--   We exclude counties with fewer than 500 Medicare patients.
--   Why? Because with tiny populations, even 1 pharmacy makes the density
--   number look enormous (like TX-Upton with 300 patients). That's a math
--   quirk, not a real signal. 500 patients is the minimum for a meaningful ratio.
--
-- NOTE: This is not a numbered script — it's a one-off preview query
--       to see the relationship before building the Tableau chart.
-- =============================================================================

USE pharmacy_medicare_project;

WITH density_buckets AS (
    SELECT
        county_fips,
        state_abbrev,
        county_desc,
        pharmacies_per_10k_benes,
        tot_mdcr_stdzd_pymt_pc,
        benes_ffs_cnt,

        -- NTILE(5) splits all counties into 5 equal groups by density.
        -- Group 1 = lowest density (fewest pharmacies per patient) — pharmacy deserts.
        -- Group 5 = highest density (most pharmacies per patient) — well-served counties.
        NTILE(5) OVER (ORDER BY pharmacies_per_10k_benes ASC) AS density_bucket

    FROM curated.fact_county_year
    WHERE year_id                  = 2023
      AND pharmacies_per_10k_benes IS NOT NULL   -- need a density number
      AND tot_mdcr_stdzd_pymt_pc   IS NOT NULL   -- need a spending number
      AND benes_ffs_cnt            >= 500         -- exclude tiny counties
)

SELECT
    density_bucket,
    COUNT(*)                                              AS county_count,
    CAST(MIN(pharmacies_per_10k_benes) AS DECIMAL(8,2))  AS min_density,
    CAST(MAX(pharmacies_per_10k_benes) AS DECIMAL(8,2))  AS max_density,
    CAST(AVG(pharmacies_per_10k_benes) AS DECIMAL(8,2))  AS avg_density,
    CAST(AVG(tot_mdcr_stdzd_pymt_pc)  AS DECIMAL(10,2))  AS avg_medicare_spend
FROM density_buckets
GROUP BY density_bucket
ORDER BY density_bucket;
