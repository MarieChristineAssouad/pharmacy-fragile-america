# Pharmacy-Fragile America

**Rural pharmacy access vs. Medicare spending. A US county level case study (through 2023).**

[![Live Dashboard](https://img.shields.io/badge/Live_Dashboard-CE0E2D?style=for-the-badge&logo=tableau&logoColor=white)](https://public.tableau.com/app/profile/marie.christine.assouad/viz/Pharmacy-FragileAmerica/Dashboard2)
[![SQL Pipeline](https://img.shields.io/badge/SQL_Pipeline-7F8489?style=for-the-badge&logo=microsoftsqlserver&logoColor=white)](#pipeline)
[![The Data](https://img.shields.io/badge/The_Data-7F8489?style=for-the-badge)](#data)
[![Key Insights](https://img.shields.io/badge/Key_Insights-7F8489?style=for-the-badge)](#insights)
[![Descriptive not Causal](https://img.shields.io/badge/Descriptive_not_Causal-7F8489?style=for-the-badge)](#descriptive)

> **In one line:** In rural America, counties with **0 to 1 pharmacies** spend about **\$754 more per senior** on Medicare every year, roughly **\$91 million** across **156 counties**, and the gap is getting wider.

### 🔗 [Explore the live interactive dashboard on Tableau Public →](https://public.tableau.com/app/profile/marie.christine.assouad/viz/Pharmacy-FragileAmerica/Dashboard2)

![Dashboard preview](images/dashboard.png)

---

## ⚡ Key takeaways (30 second read)

- **Question:** Do rural counties with fewer pharmacies have higher Medicare spending per senior?
- **Answer:** Yes. The fewer the pharmacies, the higher the spending, step by step.
- **The cost:** about **+\$754 per senior**, roughly **\$91M every year**, across **156 fragile counties** (120,724 seniors).
- **The twist:** the pattern is **hidden by big cities** and only appears once rural counties are viewed on their own. This is **Simpson's paradox**.
- **The focus:** just **15 counties** carry about **75%** of the cost, so the opportunity is small and targetable.

---

## 📊 The numbers at a glance

| Metric | Value |
|---|---|
| 📍 Fragile rural counties (0 to 1 pharmacy) | **156** |
| 👥 Seniors living in those counties | **120,724** |
| 📈 Extra Medicare spend per senior, per year | **+\$754** |
| 💵 Total extra Medicare spend, per year | **about \$91 million** |
| 🎯 Share of that cost in just 15 counties | **about 75% (\$70M)** |

*Descriptive, not causal. Every figure reflects data through 2023.*

---

## ❓ The problem

For many seniors in rural America, the nearest pharmacy can be an hour's drive away. When a refill is that far, more people miss doses, get sicker, and land in the hospital, and a hospital stay costs Medicare far more than a refill ever would.

> **The question this project answers:** Do rural areas with fewer pharmacies have higher Medicare spending per senior, and if so, where should a company act first?

---

<a id="data"></a>

## 🧩 The data and how it was built

Three public federal datasets, joined on the county (FIPS code):

| Source | What it provides |
|---|---|
| **NPPES** | Pharmacy count per county |
| **USDA RUCC** | Rural score, 1 (urban) to 9 (deeply rural) |
| **CMS Medicare** | Medicare spending per senior, by year |

![How the three datasets join by county](images/data_sources_schema.png)

The raw files were cleaned and combined in three stages, an **ELT** pipeline (Extract, Load, Transform) built in SQL Server:

- **Raw:** load each file exactly as it arrived, nothing changed.
- **Clean:** trim text, safely convert numbers, mark hidden or blank values, pad every county code to 5 digits.
- **Curated:** join into one final table, one row per county each year, ready for analysis.

![The raw, clean, curated pipeline](images/pipeline_schema.png)

---

<a id="insights"></a>

## 🔑 Key insights

**1. Fewer pharmacies, higher Medicare spending per senior.**
In rural counties, spend rises step by step as pharmacies disappear: about **\$11,156** per senior with the most pharmacies, up to **\$12,838** with none. The fragile counties spend **+\$754 per senior**.

**2. Big cities hide the pattern. It only shows once you isolate rural counties.**
Looking at every county together, the trend looked backwards. Cities have many pharmacies *and* very high spending, which masks the truth. Split out the rural counties and the pattern flips. This reversal is **Simpson's paradox**.

**3. The gap is not new, and it is widening.**
The fragile counties spent more every year from 2019 to 2023. The gap grew from about **\$220** in 2019 to about **\$754** in 2023, more than tripling in five years.

**4. The cost is concentrated. A few counties carry most of it.**
Just **15 counties** account for about **\$70M of the \$91M** (roughly **75%**), because they combine high spend per senior with enough seniors to matter.

---

## ✅ Recommendations

1. **Start with the 15 counties that concentrate the cost.** Largest share of the cost, smallest footprint.
2. **Capture value on both sides: access and downstream savings.** Better medication access lowers avoidable hospital admissions, so integrated players (pharmacy plus insurance or health system) win most.
3. **Use low cost store formats suited to small markets.** A physical presence offers what delivery cannot: counseling, vaccinations, and immediate access when a prescription runs out.
4. **Act now, the cost of inaction is rising.** The gap keeps widening, so delay only raises the eventual cost.

*A company specific version (tailored to CVS Health) is in the [full case study](case-study/Pharmacy_Fragile_America_Case_Study.pdf).*

---

<details>
<summary><b>⚠️ Honest limitations (click to expand)</b></summary>

<br>

1. **This is a pattern, not proof.** The link is strong but this study alone does not prove cause and effect.
2. **The data ends in 2023.** Check against newer data before acting.
3. **The pharmacy count is a snapshot.** Closed pharmacies drop off the national list, so this measures access as it stands, not the full history of closures.
4. **Small counties can be noisy.** A few hundred seniors means one very sick person can swing the average.
5. **Total Medicare spending, not drug spending alone.** The separate Part D drug benefit was not included.

</details>

<a id="pipeline"></a>

<details>
<summary><b>🛠️ How it was built, technical detail (SQL pipeline)</b></summary>

<br>

A layered **raw, clean, curated** architecture in SQL Server (an ELT pattern). Each layer lives in its own schema so every number traces back to its source.

**Raw layer** loads each source file as it arrived, keeping original column names:
`01_create_database.sql` · `02_load_raw_pharmacies.sql` (NPPES) · `03_load_raw_rucc.sql` (USDA) · `04_load_raw_medicare.sql` (CMS) · `07_load_raw_zip_to_fips.sql`

**Clean layer** applies one consistent cleaning idiom and renames columns to lowercase_snake_case:

```sql
-- safe casting: strip whitespace, treat the CMS suppression marker '*' and empty strings
-- as NULL, and convert without crashing on bad values
TRY_CAST(NULLIF(NULLIF(LTRIM(RTRIM(col)), '*'), '') AS <target_type>) AS new_col

-- FIPS normalization: source files often drop the leading zero (Excel turns 01xxx into 1xxx),
-- so every county code is padded back to 5 characters
RIGHT('00000' + LTRIM(RTRIM(col)), 5)
```
`05_build_clean_medicare.sql` · `06_build_clean_rucc.sql` · `08_build_clean_zip_to_fips.sql` · `09_build_clean_pharmacies.sql`
Each clean script ends with a validation block (row counts, distribution checks, and a spot check that ties back to the prior script's headline number).

**Curated layer** joins the clean tables into the final analysis table, one row per county per year:
`10_build_curated_county_year_panel.sql` · `11_build_curated_fact_county_year.sql`, exported to the CSVs that feed Tableau.

**Analysis notes:** population weighted averages (`SUM(value × seniors) / SUM(seniors)`), the rural view filters to RUCC 4 to 9, and the urban vs. rural split is what surfaces Simpson's paradox.

</details>

<details>
<summary><b>🗂️ Repository structure</b></summary>

<br>

```
pharmacy-fragile-america/
├── README.md
├── images/         # dashboard preview and schema diagrams
├── sql/            # the full SQL pipeline, scripts 01 to 11
├── data/           # curated CSV outputs that feed Tableau
└── case-study/     # the full written case study (Word)
```

</details>

---

## 🧰 Tools and data sources

**Tools:** SQL Server (ELT pipeline) · Tableau (interactive dashboard) · population weighted analysis.

**Data:** NPPES (pharmacies) · USDA Rural-Urban Continuum Codes · CMS Medicare Geographic Variation Public Use File. Market context sources are listed in the case study.

---

<a id="descriptive"></a>

## 🧭 Why this study is descriptive, not causal

This project shows that fewer pharmacies and higher Medicare spending happen **together** in rural counties. It does **not** prove that one causes the other.

A **descriptive** finding says two things move together. A **causal** finding says one thing makes the other happen, which is a much stronger claim that needs far more proof.

Think of ice cream and drowning: both rise in summer, so they move together, but ice cream does not cause drowning. Hot weather drives both. In the same way, fewer pharmacies and higher spending could both be driven by something else, such as lower income, worse health, or distance from a hospital.

So this study reports a strong, consistent pattern that is worth acting on, but it does not claim pharmacies are the proven cause. Proving cause would need controlling for those other factors, ideally over time. Calling it descriptive is a deliberate choice to stay honest about what the data can and cannot show.

---

*Built by Marie Christine Assouad · Data vintage: CMS through 2023 · Descriptive, not causal.*
