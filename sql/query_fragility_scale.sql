/* =====================================================================
   query_fragility_scale.sql
   Purpose: Put real numbers on the reframed story —
   "pharmacy-fragile rural America" as a retail + payer opportunity.

   Two questions:
     Q1. How big is the fragile segment? (counties + senior population per tier)
     Q2. Does the fragile segment cost MORE per senior than comparable
         rural counties that HAVE pharmacies? If so, scale it to dollars.

   Honest framing note (read before quoting any number):
     - "rural" = RUCC 4-9 (Nonmetro).
     - We weight $/senior by FFS beneficiary count (benes_ffs_cnt), NOT a
       plain AVG of the per-capita column. Reason: a plain AVG treats a
       150-senior county the same as a 60,000-senior county. To talk about
       TOTAL DOLLARS, you must population-weight. (Strong interview point.)
     - active_pharmacies IS NULL is treated as UNKNOWN and excluded from the
       0/1 tiers (this is the Glasscock TX issue — missing, not confirmed 0).
     - Any "excess" here is DESCRIPTIVE (money concentrated in fragile
       counties), NOT causal. Density is confounded by urbanization. Say
       "concentrated in," never "caused by."
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Q1: The fragility landscape — how many rural counties, how many seniors,
--     and what they cost, by pharmacy tier.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN active_pharmacies = 0              THEN '0 - desert (acute)'
        WHEN active_pharmacies = 1              THEN '1 - fragile (1 closure from desert)'
        WHEN active_pharmacies BETWEEN 2 AND 5  THEN '2-5 pharmacies'
        WHEN active_pharmacies >= 6             THEN '6+ pharmacies'
        ELSE 'NULL / unknown'                   -- surfaced, not hidden
    END                                                         AS pharmacy_tier,
    COUNT(*)                                                    AS county_count,
    SUM(benes_ffs_cnt)                                          AS total_ffs_seniors,
    -- unweighted county average (what an AVG() in Tableau gives you):
    AVG(CAST(tot_mdcr_stdzd_pymt_pc AS float))                 AS avg_total_pc_unweighted,
    -- population-weighted $/senior (the honest one for dollar talk):
    SUM(CAST(tot_mdcr_stdzd_pymt_pc AS float) * benes_ffs_cnt)
        / NULLIF(SUM(benes_ffs_cnt), 0)                         AS avg_total_pc_weighted,
    AVG(CAST(ip_mdcr_stdzd_pymt_pc AS float))                  AS avg_inpatient_pc_unweighted
FROM curated.fact_county_year
WHERE year_id = 2023
  AND rucc_code BETWEEN 4 AND 9          -- rural only
  AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
GROUP BY
    CASE
        WHEN active_pharmacies = 0              THEN '0 - desert (acute)'
        WHEN active_pharmacies = 1              THEN '1 - fragile (1 closure from desert)'
        WHEN active_pharmacies BETWEEN 2 AND 5  THEN '2-5 pharmacies'
        WHEN active_pharmacies >= 6             THEN '6+ pharmacies'
        ELSE 'NULL / unknown'
    END
ORDER BY pharmacy_tier;


-- ---------------------------------------------------------------------
-- Q2: The honest scaled-dollar headline.
--     Fragile (0 or 1 pharmacy, rural) vs the benchmark of comparable
--     rural counties that HAVE pharmacies (2+). Population-weighted.
--     The final column is the number that either makes the story or breaks it.
-- ---------------------------------------------------------------------
WITH rural AS (
    SELECT *
    FROM curated.fact_county_year
    WHERE year_id = 2023
      AND rucc_code BETWEEN 4 AND 9
      AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
      AND benes_ffs_cnt IS NOT NULL
),
benchmark AS (                              -- rural counties WITH pharmacies
    SELECT SUM(CAST(tot_mdcr_stdzd_pymt_pc AS float) * benes_ffs_cnt)
           / NULLIF(SUM(benes_ffs_cnt), 0)  AS bench_spend_pc
    FROM rural
    WHERE active_pharmacies >= 2
),
fragile AS (                                -- rural counties with 0 or 1 pharmacy
    SELECT SUM(benes_ffs_cnt)               AS fragile_seniors,
           COUNT(*)                         AS fragile_counties,
           SUM(CAST(tot_mdcr_stdzd_pymt_pc AS float) * benes_ffs_cnt)
           / NULLIF(SUM(benes_ffs_cnt), 0)  AS fragile_spend_pc
    FROM rural
    WHERE active_pharmacies IN (0, 1)       -- excludes NULL/unknown automatically
)
SELECT
    f.fragile_counties,
    f.fragile_seniors,
    CAST(f.fragile_spend_pc AS decimal(10,2))                       AS fragile_spend_per_senior,
    CAST(b.bench_spend_pc   AS decimal(10,2))                       AS rural_with_pharmacy_per_senior,
    CAST(f.fragile_spend_pc - b.bench_spend_pc AS decimal(10,2))    AS gap_per_senior,
    -- THE HEADLINE: total annual Medicare $ concentrated in fragile rural
    -- counties above the comparable-rural benchmark. Could be +/-; report either.
    CAST((f.fragile_spend_pc - b.bench_spend_pc) * f.fragile_seniors AS decimal(18,0))
                                                                    AS annual_excess_dollars
FROM fragile f
CROSS JOIN benchmark b;
