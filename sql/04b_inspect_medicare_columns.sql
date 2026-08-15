-- =============================================================================
-- 04b_inspect_medicare_columns.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
--Look inside the raw Medicare table to understand what columns exist and what values they contain before cleaning
--Before writing my clean script, I verify that all expected columns exist and are named exactly as expected.
-- ---------------------------------------------------------------------
-- PURPOSE
--   Pre-flight check before script 05 (clean.medicare_spending build).
--   Confirms the EXACT column names CMS used in our raw load so script 05's
--   column references don't blow up on a 33k-row INSERT.
--
-- WHY THIS EXISTS
--   CMS varies their Geographic Variation column names slightly across
--   publication years (e.g., PQI11_BCTRL_PNEUM vs. PQI11_PNEUM_AGE_GE_65).
--   "Trust the spec doc" is how you waste an afternoon. Confirm against the
--   actual loaded data before writing dependent code.
--
-- AUTHOR / DATE
-- Marie Christine Assouad, 2026-04-29
-- =============================================================================

USE pharmacy_medicare_project;
SET NOCOUNT ON; --Hide “(X rows affected)” messages. Cleaner output.
GO

-- -----------------------------------------------------------------------------
-- 1) PQI columns
--    We need PQI03 diabetes, PQI05 COPD/asthma, PQI08 CHF, PQI11 pneumonia.
--    CMS may split these by age (AGE_LT_65 / AGE_GE_65) — we want to see ALL
--    PQI* columns so we know which split (if any) applies.
-- -----------------------------------------------------------------------------
PRINT '=== Result 1: PQI columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS -- It stores metadata about the tables: column names, data types, table structure)
WHERE TABLE_SCHEMA = 'raw' --Only look inside raw schema.
  AND TABLE_NAME   = 'medicare_spending'
  AND COLUMN_NAME LIKE 'PQI%'
ORDER BY COLUMN_NAME; --Sort alphabetically.

/* Confirms:
            1- which PQI columns exist
            2- how they are named*/

-- -----------------------------------------------------------------------------
-- 2) ER + Readmission columns
--    We expect ER_VISITS_PER_1000_BENES and ACUTE_HOSP_READMSN_PCT.
--    Wider pattern catches naming variants (READMSN, READM, etc.).
-- -----------------------------------------------------------------------------
PRINT '=== Result 2: ER + Readmission columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'medicare_spending'
  AND (COLUMN_NAME LIKE 'ER_%'
       OR COLUMN_NAME LIKE 'ACUTE_%'
       OR COLUMN_NAME LIKE '%READM%') --Because naming might vary: Readmsn, Readm, Readmission. This catches all variations.
ORDER BY COLUMN_NAME;


/*Confirms:
           1- ER visits column exists
           2- readmission column exists*/


-- -----------------------------------------------------------------------------
-- 3) Beneficiary count columns
--    We need BENES_FFS_CNT (denominator for our access rates).
--    BENES_TOTAL_CNT may exist too — we'll keep both if available.
-- -----------------------------------------------------------------------------
PRINT '=== Result 3: Beneficiary count columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS -- Get column names.
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'medicare_spending'
  AND COLUMN_NAME LIKE 'BENES_%' --Find all columns starting with: BENES_
ORDER BY COLUMN_NAME;

/* Confirms:
            1- denominator columns exist
            2- we can compute rates later */

-- -----------------------------------------------------------------------------
-- 4) Standardized payment per-capita columns
--    Confirms our spend-share inputs all exist:
--      TOT_MDCR_STDZD_PYMT_PC, IP_MDCR_STDZD_PYMT_PC,
--      OP_MDCR_STDZD_PYMT_PC, PTD_MDCR_STDZD_PYMT_PC
-- -----------------------------------------------------------------------------
PRINT '=== Result 4: Standardized payment per-capita columns ===';
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'medicare_spending'
  AND COLUMN_NAME LIKE '%STDZD_PYMT_PC' --Find columns that end with:%STDZD_PYMT_PC
ORDER BY COLUMN_NAME;

/* Confirms our main metrics exist: These will be used in Script 5.*/

-- -----------------------------------------------------------------------------
-- 5) BENE_AGE_LVL distinct values + row counts
--    We want to know EXACTLY how the three age buckets are spelled:
--    'All' vs. 'all', '>=65' vs. '65+' vs. 'GE_65', etc.
--    Script 05's filter depends on this.
-- -----------------------------------------------------------------------------
PRINT '=== Result 5: BENE_AGE_LVL distinct values ===';
SELECT BENE_AGE_LVL, COUNT(*) AS row_count -- Select age groups and number of rows
FROM raw.medicare_spending --This time we query actual data, not metadata.
GROUP BY BENE_AGE_LVL --Group by age group.
ORDER BY BENE_AGE_LVL; --This time we query actual data, not metadata.

GO
