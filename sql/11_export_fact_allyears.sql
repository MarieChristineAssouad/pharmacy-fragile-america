/* =====================================================================
   11_export_fact_allyears.sql
   Purpose: Export the curated fact table for MULTIPLE years (2019-2023)
   so Tableau can build a change-over-time trend row + sparklines.

   The current Tableau workbook is connected to fact_county_year_2023.csv
   (single year). The trend panel needs several years.

   HOW TO USE (run in SSMS — NOT from chat; the Cowork Linux sandbox
   cannot reach local SQL Server):
     1. Tools > Options > Query Results > SQL Server > Results to Grid >
        CHECK "Include column headers when copying or saving results".
        Then close & reopen this query tab (setting only applies to new tabs).
     2. Run this script (F5).
     3. Right-click the results grid > Save Results As >
        fact_county_year_allyears.csv  (save in the "Create Data Project 1" folder).
     4. In Tableau: Data > New Data Source > Text File > pick that CSV.
        Keep the existing 2023 source for all existing sheets; the trend
        sheet(s) use this new multi-year source.

   Same columns as the 2023 export (SELECT * from the same view), so field
   names match what you already know.
   ===================================================================== */

SELECT *
FROM curated.fact_county_year
WHERE year_id BETWEEN 2019 AND 2023
ORDER BY county_fips, year_id;
