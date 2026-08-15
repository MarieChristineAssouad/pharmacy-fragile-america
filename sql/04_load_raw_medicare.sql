-- =====================================================================
-- 04_load_raw_medicare.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
-- Load Medicare spending data
-- ---------------------------------------------------------------------
-- Project: Quantifying the Impact of Rural Pharmacy Closures on
--          Medicare Spending: A County-Level Analysis (2019-2024)
-- Step:    5c - Load CMS Medicare Geographic Variation Public Use File
--          into raw.medicare_spending
-- Author:  Christine Assouad
-- =====================================================================
-- WHY THIS DATASET MATTERS
--   This is the dependent variable of the entire project: county-level
--   Medicare spending. The headline KPI is TOT_MDCR_STDZD_PYMT_PC
--   (total standardized Medicare payment per capita). The PQI columns
--   (Prevention Quality Indicators) are the medication-adherence-
--   sensitive condition rates -- diabetes, COPD, heart failure --
--   that pharmacy access is HYPOTHESIZED to influence.
--
-- SOURCE
--   Medicare_GV_by_National_State_County.csv (33,639 rows, 247 columns).
--   YEAR range: 2014-2023 (CMS published 2023 data; CLAUDE.md was
--   one cycle behind).
--   BENE_GEO_LVL hierarchy: National (30) | State (1,650) | County (31,959).
--   BENE_AGE_LVL: All / >=65 / <65.
--
-- DESIGN CHOICES
--   - All 247 columns load as VARCHAR. raw schema is source-loyal.
--     Type casting and the County-level + age='All' filter happen
--     in the clean schema.
--   - Column names preserved verbatim from CMS (UPPERCASE_SNAKE).
--     Diff-friendly against the source spec; clean schema can rename.
--   - VARCHAR(20) is the default width: max observed numeric width is
--     12 chars across all 240+ numeric columns. Three text columns
--     (BENE_GEO_DESC, BENE_GEO_LVL, BENE_AGE_LVL) get explicit larger
--     widths.
--   - DDL was machine-generated from the CSV header to eliminate the
--     247-column transcription error class. The generated block is
--     pasted inline below so a recruiter reads real SQL, not a Python
--     codegen pipeline.
-- =====================================================================

USE pharmacy_medicare_project;
GO

-- ---------------------------------------------------------------------
-- STEP 1: Drop the table if it exists (idempotency)
-- ---------------------------------------------------------------------
IF OBJECT_ID('raw.medicare_spending', 'U') IS NOT NULL
BEGIN
    DROP TABLE raw.medicare_spending;
    PRINT 'Dropped existing raw.medicare_spending table.';
END
GO

-- ---------------------------------------------------------------------
-- STEP 2: Create the table (247 columns)
-- ---------------------------------------------------------------------
CREATE TABLE raw.medicare_spending (
    YEAR                            VARCHAR(20),
    BENE_GEO_LVL                    VARCHAR(20),
    BENE_GEO_DESC                   VARCHAR(100),
    BENE_GEO_CD                     VARCHAR(20),
    BENE_AGE_LVL                    VARCHAR(10),
    BENES_TOTAL_CNT                 VARCHAR(20),
    BENES_WTH_PTAPTB_CNT            VARCHAR(20),
    BENES_FFS_CNT                   VARCHAR(20),
    BENES_MA_CNT                    VARCHAR(20),
    MA_PRTCPTN_RATE                 VARCHAR(20),
    BENE_AVG_AGE                    VARCHAR(20),
    BENE_FEML_PCT                   VARCHAR(20),
    BENE_MALE_PCT                   VARCHAR(20),
    BENE_RACE_WHT_PCT               VARCHAR(20),
    BENE_RACE_BLACK_PCT             VARCHAR(20),
    BENE_RACE_HSPNC_PCT             VARCHAR(20),
    BENE_RACE_OTHR_PCT              VARCHAR(20),
    BENE_DUAL_PCT                   VARCHAR(20),
    BENE_AVG_RISK_SCRE              VARCHAR(20),
    TOT_MDCR_PYMT_AMT               VARCHAR(20),
    TOT_MDCR_STDZD_PYMT_AMT         VARCHAR(20),
    TOT_MDCR_PYMT_PC                VARCHAR(20),
    TOT_MDCR_STDZD_PYMT_PC          VARCHAR(20),
    IP_MDCR_PYMT_AMT                VARCHAR(20),
    IP_MDCR_PYMT_PCT                VARCHAR(20),
    IP_MDCR_PYMT_PC                 VARCHAR(20),
    IP_MDCR_PYMT_PER_USER           VARCHAR(20),
    IP_MDCR_STDZD_PYMT_AMT          VARCHAR(20),
    IP_MDCR_STDZD_PYMT_PCT          VARCHAR(20),
    IP_MDCR_STDZD_PYMT_PC           VARCHAR(20),
    IP_MDCR_STDZD_PYMT_PER_USER     VARCHAR(20),
    BENES_IP_CVRD_STAY_CNT          VARCHAR(20),
    BENES_IP_PCT                    VARCHAR(20),
    IP_CVRD_STAYS_PER_1000_BENES    VARCHAR(20),
    IP_CVRD_DAYS_PER_1000_BENES     VARCHAR(20),
    ACUTE_HOSP_READMSN_CNT          VARCHAR(20),
    ACUTE_HOSP_READMSN_PCT          VARCHAR(20),
    BENES_ER_VISITS_CNT             VARCHAR(20),
    ER_VISITS_PER_1000_BENES        VARCHAR(20),
    BENES_ER_VISITS_PCT             VARCHAR(20),
    OP_MDCR_PYMT_AMT                VARCHAR(20),
    OP_MDCR_PYMT_PCT                VARCHAR(20),
    OP_MDCR_PYMT_PC                 VARCHAR(20),
    OP_MDCR_PYMT_PER_USER           VARCHAR(20),
    OP_MDCR_STDZD_PYMT_AMT          VARCHAR(20),
    OP_MDCR_STDZD_PYMT_PCT          VARCHAR(20),
    OP_MDCR_STDZD_PYMT_PC           VARCHAR(20),
    OP_MDCR_STDZD_PYMT_PER_USER     VARCHAR(20),
    BENES_OP_CNT                    VARCHAR(20),
    BENES_OP_PCT                    VARCHAR(20),
    OP_VISITS_PER_1000_BENES        VARCHAR(20),
    ASC_MDCR_PYMT_AMT               VARCHAR(20),
    ASC_MDCR_PYMT_PCT               VARCHAR(20),
    ASC_MDCR_PYMT_PC                VARCHAR(20),
    ASC_MDCR_PYMT_PER_USER          VARCHAR(20),
    ASC_MDCR_STDZD_PYMT_AMT         VARCHAR(20),
    ASC_MDCR_STDZD_PYMT_PCT         VARCHAR(20),
    ASC_MDCR_STDZD_PYMT_PC          VARCHAR(20),
    ASC_MDCR_STDZD_PYMT_PER_USER    VARCHAR(20),
    BENES_ASC_CNT                   VARCHAR(20),
    BENES_ASC_PCT                   VARCHAR(20),
    ASC_EVNTS_PER_1000_BENES        VARCHAR(20),
    SNF_MDCR_PYMT_AMT               VARCHAR(20),
    SNF_MDCR_PYMT_PCT               VARCHAR(20),
    SNF_MDCR_PYMT_PC                VARCHAR(20),
    SNF_MDCR_PYMT_PER_USER          VARCHAR(20),
    SNF_MDCR_STDZD_PYMT_AMT         VARCHAR(20),
    SNF_MDCR_STDZD_PYMT_PCT         VARCHAR(20),
    SNF_MDCR_STDZD_PYMT_PC          VARCHAR(20),
    SNF_MDCR_STDZD_PYMT_PER_USER    VARCHAR(20),
    BENES_SNF_CNT                   VARCHAR(20),
    BENES_SNF_PCT                   VARCHAR(20),
    SNF_CVRD_STAYS_PER_1000_BENES   VARCHAR(20),
    SNF_CVRD_DAYS_PER_1000_BENES    VARCHAR(20),
    IRF_MDCR_PYMT_AMT               VARCHAR(20),
    IRF_MDCR_PYMT_PCT               VARCHAR(20),
    IRF_MDCR_PYMT_PC                VARCHAR(20),
    IRF_MDCR_PYMT_PER_USER          VARCHAR(20),
    IRF_MDCR_STDZD_PYMT_AMT         VARCHAR(20),
    IRF_MDCR_STDZD_PYMT_PCT         VARCHAR(20),
    IRF_MDCR_STDZD_PYMT_PC          VARCHAR(20),
    IRF_MDCR_STDZD_PYMT_PER_USER    VARCHAR(20),
    BENES_IRF_CNT                   VARCHAR(20),
    BENES_IRF_PCT                   VARCHAR(20),
    IRF_CVRD_STAYS_PER_1000_BENES   VARCHAR(20),
    IRF_CVRD_DAYS_PER_1000_BENES    VARCHAR(20),
    LTCH_MDCR_PYMT_AMT              VARCHAR(20),
    LTCH_MDCR_PYMT_PCT              VARCHAR(20),
    LTCH_MDCR_PYMT_PC               VARCHAR(20),
    LTCH_MDCR_PYMT_PER_USER         VARCHAR(20),
    LTCH_MDCR_STDZD_PYMT_AMT        VARCHAR(20),
    LTCH_MDCR_STDZD_PYMT_PCT        VARCHAR(20),
    LTCH_MDCR_STDZD_PYMT_PC         VARCHAR(20),
    LTCH_MDCR_STDZD_PYMT_PER_USER   VARCHAR(20),
    BENES_LTCH_CNT                  VARCHAR(20),
    BENES_LTCH_PCT                  VARCHAR(20),
    LTCH_CVRD_STAYS_PER_1000_BENES  VARCHAR(20),
    LTCH_CVRD_DAYS_PER_1000_BENES   VARCHAR(20),
    HH_MDCR_PYMT_AMT                VARCHAR(20),
    HH_MDCR_PYMT_PCT                VARCHAR(20),
    HH_MDCR_PYMT_PC                 VARCHAR(20),
    HH_MDCR_PYMT_PER_USER           VARCHAR(20),
    HH_MDCR_STDZD_PYMT_AMT          VARCHAR(20),
    HH_MDCR_STDZD_PYMT_PCT          VARCHAR(20),
    HH_MDCR_STDZD_PYMT_PC           VARCHAR(20),
    HH_MDCR_STDZD_PYMT_PER_USER     VARCHAR(20),
    BENES_HH_CNT                    VARCHAR(20),
    BENES_HH_PCT                    VARCHAR(20),
    HH_EPISODES_PER_1000_BENES      VARCHAR(20),
    HH_VISITS_PER_1000_BENES        VARCHAR(20),
    HOSPC_MDCR_PYMT_AMT             VARCHAR(20),
    HOSPC_MDCR_PYMT_PCT             VARCHAR(20),
    HOSPC_MDCR_PYMT_PC              VARCHAR(20),
    HOSPC_MDCR_PYMT_PER_USER        VARCHAR(20),
    HOSPC_MDCR_STDZD_PYMT_AMT       VARCHAR(20),
    HOSPC_MDCR_STDZD_PYMT_PCT       VARCHAR(20),
    HOSPC_MDCR_STDZD_PYMT_PC        VARCHAR(20),
    HOSPC_MDCR_STDZD_PYMT_PER_USER  VARCHAR(20),
    BENES_HOSPC_CNT                 VARCHAR(20),
    BENES_HOSPC_PCT                 VARCHAR(20),
    HOSPC_CVRD_STAYS_PER_1000_BENES VARCHAR(20),
    HOSPC_CVRD_DAYS_PER_1000_BENES  VARCHAR(20),
    EM_MDCR_PYMT_AMT                VARCHAR(20),
    EM_MDCR_PYMT_PCT                VARCHAR(20),
    EM_MDCR_PYMT_PC                 VARCHAR(20),
    EM_MDCR_PYMT_PER_USER           VARCHAR(20),
    EM_MDCR_STDZD_PYMT_AMT          VARCHAR(20),
    EM_MDCR_STDZD_PYMT_PCT          VARCHAR(20),
    EM_MDCR_STDZD_PYMT_PC           VARCHAR(20),
    EM_MDCR_STDZD_PYMT_PER_USER     VARCHAR(20),
    BENES_EM_CNT                    VARCHAR(20),
    BENES_EM_PCT                    VARCHAR(20),
    EM_EVNTS_PER_1000_BENES         VARCHAR(20),
    PRCDRS_MDCR_PYMT_AMT            VARCHAR(20),
    PRCDRS_MDCR_PYMT_PCT            VARCHAR(20),
    PRCDRS_MDCR_PYMT_PC             VARCHAR(20),
    PRCDRS_MDCR_PYMT_PER_USER       VARCHAR(20),
    PRCDRS_MDCR_STDZD_PYMT_AMT      VARCHAR(20),
    PRCDRS_MDCR_STDZD_PYMT_PCT      VARCHAR(20),
    PRCDRS_MDCR_STDZD_PYMT_PC       VARCHAR(20),
    PRCDRS_MDCR_STDZD_PYMT_PER_USER VARCHAR(20),
    BENES_PRCDRS_CNT                VARCHAR(20),
    BENES_PRCDRS_PCT                VARCHAR(20),
    PRCDR_EVNTS_PER_1000_BENES      VARCHAR(20),
    TESTS_MDCR_PYMT_AMT             VARCHAR(20),
    TESTS_MDCR_PYMT_PCT             VARCHAR(20),
    TESTS_MDCR_PYMT_PC              VARCHAR(20),
    TESTS_MDCR_PYMT_PER_USER        VARCHAR(20),
    TESTS_MDCR_STDZD_PYMT_AMT       VARCHAR(20),
    TESTS_MDCR_STDZD_PYMT_PCT       VARCHAR(20),
    TESTS_MDCR_STDZD_PYMT_PC        VARCHAR(20),
    TESTS_MDCR_STDZD_PYMT_PER_USER  VARCHAR(20),
    BENES_TESTS_CNT                 VARCHAR(20),
    BENES_TESTS_PCT                 VARCHAR(20),
    TESTS_EVNTS_PER_1000_BENES      VARCHAR(20),
    IMGNG_MDCR_PYMT_AMT             VARCHAR(20),
    IMGNG_MDCR_PYMT_PCT             VARCHAR(20),
    IMGNG_MDCR_PYMT_PC              VARCHAR(20),
    IMGNG_MDCR_PYMT_PER_USER        VARCHAR(20),
    IMGNG_MDCR_STDZD_PYMT_AMT       VARCHAR(20),
    IMGNG_MDCR_STDZD_PYMT_PCT       VARCHAR(20),
    IMGNG_MDCR_STDZD_PYMT_PC        VARCHAR(20),
    IMGNG_MDCR_STDZD_PYMT_PER_USER  VARCHAR(20),
    BENES_IMGNG_CNT                 VARCHAR(20),
    BENES_IMGNG_PCT                 VARCHAR(20),
    IMGNG_EVNTS_PER_1000_BENES      VARCHAR(20),
    DME_MDCR_PYMT_AMT               VARCHAR(20),
    DME_MDCR_PYMT_PCT               VARCHAR(20),
    DME_MDCR_PYMT_PC                VARCHAR(20),
    DME_MDCR_PYMT_PER_USER          VARCHAR(20),
    DME_MDCR_STDZD_PYMT_AMT         VARCHAR(20),
    DME_MDCR_STDZD_PYMT_PCT         VARCHAR(20),
    DME_MDCR_STDZD_PYMT_PC          VARCHAR(20),
    DME_MDCR_STDZD_PYMT_PER_USER    VARCHAR(20),
    BENES_DME_CNT                   VARCHAR(20),
    BENES_DME_PCT                   VARCHAR(20),
    DME_EVNTS_PER_1000_BENES        VARCHAR(20),
    OP_DLYS_MDCR_PYMT_AMT           VARCHAR(20),
    OP_DLYS_MDCR_PYMT_PCT           VARCHAR(20),
    OP_DLYS_MDCR_PYMT_PC            VARCHAR(20),
    OP_DLYS_MDCR_PYMT_PER_USER      VARCHAR(20),
    OP_DLYS_MDCR_STDZD_PYMT_AMT     VARCHAR(20),
    OP_DLYS_MDCR_STDZD_PYMT_PCT     VARCHAR(20),
    OP_DLYS_MDCR_STDZD_PYMT_PC      VARCHAR(20),
    OP_DLYS_MDCR_STDZD_PYMT_PER_USER VARCHAR(20),
    BENES_OP_DLYS_CNT               VARCHAR(20),
    BENES_OP_DLYS_PCT               VARCHAR(20),
    OP_DLYS_VISITS_PER_1000_BENES   VARCHAR(20),
    FQHC_RHC_MDCR_PYMT_AMT          VARCHAR(20),
    FQHC_RHC_MDCR_PYMT_PCT          VARCHAR(20),
    FQHC_RHC_MDCR_PYMT_PC           VARCHAR(20),
    FQHC_RHC_MDCR_PYMT_PER_USER     VARCHAR(20),
    FQHC_RHC_MDCR_STDZD_PYMT_AMT    VARCHAR(20),
    FQHC_RHC_MDCR_STDZD_PYMT_PCT    VARCHAR(20),
    FQHC_RHC_MDCR_STDZD_PYMT_PC     VARCHAR(20),
    FQHC_RHC_MDCR_STDZD_PYMT_PU     VARCHAR(20),
    BENES_FQHC_RHC_CNT              VARCHAR(20),
    BENES_FQHC_RHC_PCT              VARCHAR(20),
    FQHC_RHC_VISITS_PER_1000_BENES  VARCHAR(20),
    AMBLNC_MDCR_PYMT_AMT            VARCHAR(20),
    AMBLNC_MDCR_PYMT_PCT            VARCHAR(20),
    AMBLNC_MDCR_PYMT_PC             VARCHAR(20),
    AMBLNC_MDCR_PYMT_PER_USER       VARCHAR(20),
    AMBLNC_MDCR_STDZD_PYMT_AMT      VARCHAR(20),
    AMBLNC_MDCR_STDZD_PYMT_PCT      VARCHAR(20),
    AMBLNC_MDCR_STDZD_PYMT_PC       VARCHAR(20),
    AMBLNC_MDCR_STDZD_PYMT_PER_USER VARCHAR(20),
    BENES_AMBLNC_CNT                VARCHAR(20),
    BENES_AMBLNC_PCT                VARCHAR(20),
    AMBLNC_EVNTS_PER_1000_BENES     VARCHAR(20),
    TRTMNTS_MDCR_PYMT_AMT           VARCHAR(20),
    TRTMNTS_MDCR_PYMT_PCT           VARCHAR(20),
    TRTMNTS_MDCR_PYMT_PC            VARCHAR(20),
    TRTMNTS_MDCR_PYMT_PER_USER      VARCHAR(20),
    TRTMNTS_MDCR_STDZD_PYMT_AMT     VARCHAR(20),
    TRTMNTS_MDCR_STDZD_PYMT_PCT     VARCHAR(20),
    TRTMNTS_MDCR_STDZD_PYMT_PC      VARCHAR(20),
    TRTMNTS_MDCR_STDZD_PYMT_PER_USER VARCHAR(20),
    BENES_TRTMNTS_CNT               VARCHAR(20),
    BENES_TRTMNTS_PCT               VARCHAR(20),
    TRTMNTS_EVNTS_PER_1000_BENES    VARCHAR(20),
    PTB_OTHR_SRVCS_MDCR_PYMT_AMT    VARCHAR(20),
    PTB_OTHR_SRVCS_MDCR_STDZD_PYMT  VARCHAR(20),
    TOT_PBPMT_RDCTN_AMT             VARCHAR(20),
    TOT_PBPMT_RDCTN_PCC             VARCHAR(20),
    PQI03_DBTS_AGE_LT_65            VARCHAR(20),
    PQI03_DBTS_AGE_65_74            VARCHAR(20),
    PQI03_DBTS_AGE_GE_75            VARCHAR(20),
    PQI05_COPD_ASTHMA_AGE_40_64     VARCHAR(20),
    PQI05_COPD_ASTHMA_AGE_65_74     VARCHAR(20),
    PQI05_COPD_ASTHMA_AGE_GE_75     VARCHAR(20),
    PQI07_HYPRTNSN_AGE_LT_65        VARCHAR(20),
    PQI07_HYPRTNSN_AGE_65_74        VARCHAR(20),
    PQI07_HYPRTNSN_AGE_GE_75        VARCHAR(20),
    PQI08_CHF_AGE_LT_65             VARCHAR(20),
    PQI08_CHF_AGE_65_74             VARCHAR(20),
    PQI08_CHF_AGE_GE_75             VARCHAR(20),
    PQI11_BCTRL_PNA_AGE_LT_65       VARCHAR(20),
    PQI11_BCTRL_PNA_AGE_65_74       VARCHAR(20),
    PQI11_BCTRL_PNA_AGE_GE_75       VARCHAR(20),
    PQI12_UTI_AGE_LT_65             VARCHAR(20),
    PQI12_UTI_AGE_65_74             VARCHAR(20),
    PQI12_UTI_AGE_GE_75             VARCHAR(20),
    PQI15_ASTHMA_AGE_LT_40          VARCHAR(20),
    PQI16_LWRXTRMTY_AMPUTN_AGE_LT_65 VARCHAR(20),
    PQI16_LWRXTRMTY_AMPUTN_AGE_65_74 VARCHAR(20),
    PQI16_LWRXTRMTY_AMPUTN_AGE_GE_75 VARCHAR(20)
);
GO

PRINT 'Created table raw.medicare_spending (247 columns).';
GO

-- ---------------------------------------------------------------------
-- STEP 3: BULK INSERT from the CSV
-- ---------------------------------------------------------------------
-- File: Medicare_GV_by_National_State_County.csv (~50MB, CRLF, UTF-8)
--
-- Notes (lessons applied from script 02 + 03):
--   * FORMAT='CSV' is REQUIRED. The National rows have empty FIPS coded
--     as "" (literal quoted empty string), and the parser only honors
--     FIELDQUOTE when FORMAT='CSV' is set.
--   * ROWTERMINATOR='0x0d0a' (CRLF) -- this file uses CRLF. Using
--     '0x0a' (LF only) reproducibly fails with "invalid column value"
--     on the last column when paired with FORMAT='CSV' and CRLF source.
-- ---------------------------------------------------------------------
BULK INSERT raw.medicare_spending
FROM 'C:\Users\carln\Desktop\Project Data Analyst 1\data_raw\Medicare_GV_by_National_State_County\Medicare_GV_by_National_State_County.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0d0a',
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    TABLOCK,
    MAXERRORS = 0
);
GO

PRINT 'BULK INSERT completed.';
GO

-- ---------------------------------------------------------------------
-- STEP 4: Verify the load
-- ---------------------------------------------------------------------
DECLARE @loaded_rows INT;
SELECT @loaded_rows = COUNT(*) FROM raw.medicare_spending;

PRINT '------------------------------------------------------------';
PRINT 'LOAD COMPLETE';
PRINT '------------------------------------------------------------';
PRINT 'Rows loaded into raw.medicare_spending: ' + CAST(@loaded_rows AS VARCHAR(20));
PRINT 'Expected:                                33,639';
PRINT '------------------------------------------------------------';
GO

-- Year coverage -- should be 2014..2023, ~3,363 rows each
SELECT YEAR, COUNT(*) AS num_rows
FROM raw.medicare_spending
GROUP BY YEAR
ORDER BY YEAR;
GO

-- Geography hierarchy -- expected: County 31,959 / State 1,650 / National 30
SELECT BENE_GEO_LVL, COUNT(*) AS num_rows
FROM raw.medicare_spending
GROUP BY BENE_GEO_LVL
ORDER BY num_rows DESC;
GO

-- Headline KPI sanity: top 5 counties by 2022 standardized payment per capita.
-- A senior reviewer wants to see at least one row of the actual KPI value to
-- confirm the column survived the load with its decimal places intact.
SELECT TOP 5
    YEAR,
    BENE_GEO_DESC,
    BENE_GEO_CD,
    BENES_TOTAL_CNT,
    TOT_MDCR_STDZD_PYMT_PC
FROM raw.medicare_spending
WHERE BENE_GEO_LVL = 'County'
  AND BENE_AGE_LVL = 'All'
  AND YEAR = '2022'
ORDER BY TRY_CAST(TOT_MDCR_STDZD_PYMT_PC AS FLOAT) DESC;
GO
