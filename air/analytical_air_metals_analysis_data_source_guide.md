# Integrated Air Metals Data Source Guide

**File:** `analytical_air_metals_analysis_data_source.sql`  
**Database:** `sample_cteh_com` — `public` schema  
**EDD Spec Reference:** Onterris Response and Recovery Laboratory EDD Specification v2.1.2  

---

## Purpose

This data source returns analytical results for integrated air sample metals analysis (e.g., mod. NIOSH 7303 / ICP-MS) for a single Onterris project. It is intended as a Tableau data source for reporting airborne metals concentrations and comparing them against ATSDR Minimum Risk Levels (MRLs). All result and detection limit values are normalized to **µg/m³** at query time regardless of the units submitted by the lab.

---

## Scope and Filters

The query is scoped to one project at a time via the `project_number` parameter. Records are included only when **all** of the following are true:

- `siera.siera_type = 'Sample-Pickup'` and `siera_subtype = 'Integrated Air Sample'` — air pump/filter samples only, as curated by the field team in SIERA. This is the authoritative matrix filter; `matrix_id` from the lab EDD is **not** used as a filter (see Data Quality Notes).
- `siera.is_usable = TRUE`, `exclude_sample = FALSE`, `deleted_at IS NULL` — only active, valid SIERA records.
- `labresults.sample_type_code ILIKE '%trg%'` — site samples only (TRG, TRGDL, TRGRE). QC samples are intentionally excluded.
- `labresults.result_type_code = 'A'` — target analytes only. Surrogates (`S`), internal standards (`I`), and TICs (`T`) are excluded.
- `lr.result_units NOT ILIKE ANY (ARRAY['ppm%', 'ppb%', 'ppt%'])` — excludes vapor-phase concentration units, which are not applicable to this sample type.
- `LOWER(lr.result_units) NOT IN ('ug', 'mg', 'ng', 'pg', 'g', 'kg')` — excludes dry weight / mass-only units. Labs occasionally store non-concentration results (e.g., temperature, ignitability) alongside metals; these are filtered out by excluding known mass-only unit strings. Additional physical parameter units may appear but will not carry mass-only unit strings and are not expected to interfere with reporting.
- `labresults.samp_no IS NOT NULL` — only SIERA samples that have received lab results.

---

## Unit Normalization

Result values and detection limits are converted to µg/m³ at query time by multiplying against a `conversion_factor` derived from the lab's submitted `result_units`. The factor is computed once per row in the base CTE and applied to `Result`, `Method Detection Limit`, `Limit of Quantitation`, `Reporting Limit`, and `Result Formatted`.

| Lab-submitted unit | conversion_factor | Output |
|---|---|---|
| kg/m³ | × 1,000,000,000 | µg/m³ |
| g/m³ | × 1,000,000 | µg/m³ |
| mg/m³ | × 1,000 | µg/m³ |
| µg/m³ (ug/m³, μg/m³) | × 1 | µg/m³ |
| ng/m³ | × 0.001 | µg/m³ |
| pg/m³ | × 0.000001 | µg/m³ |
| Any other unit | NULL | NULL |

Unit matching uses `ILIKE` prefix patterns (e.g., `'mg/m%'`) to handle variations in how labs write the m³ denominator. **Unrecognized units produce a NULL `conversion_factor`**, which propagates to NULL in all converted columns. This is intentional — a NULL `Result` paired with a hardcoded `µg/m³` label is immediately visible in Tableau and signals a unit that needs to be added to the conversion logic or flagged as a data quality issue. It is preferable to a silently wrong number.

The `"Result Units"` column is hardcoded to `µg/m³` regardless of conversion outcome. The lab's original submitted unit is available in `labresults.result_units` directly if needed for verification or troubleshooting.

---

## Key Column Reference

### Sample Identity
| Column | Source | Notes |
|---|---|---|
| `Siera ID` | `siera.id` | Internal SIERA primary key |
| `Primary Identifier` | `siera.primary_identifier` | Client sample ID; used to join to lab results via `labresults.samp_no` |
| `Secondary Identifier` | `siera.secondary_identifier` | Optional secondary label |
| `Sample Type` | `siera.sample_type` | SIERA-side sample type |
| `SDG ID` | `siera.sdg_id` | Sample Delivery Group — matches the lab COC grouping |

### Lab Result Identity
| Column | Source | Notes |
|---|---|---|
| `Sample ID` | `labresults.samp_no` | Lab's client sample ID; should match `Primary Identifier` |
| `Laboratory COC` | `labresults.lab_coc_no` | Lab-assigned SDG/COC number |
| `Lab Batch No` | `labresults.lab_batch_no` | Instrument or analysis batch |
| `Validation Status` | `labresults.qa_level` | Populated by Onterris data management during internal QA/QC; not from the lab EDD |

### Analysis Classification
| Column | Source | Notes |
|---|---|---|
| `Matrix` | `labresults.matrix_id` | Lab-reported matrix code (e.g., `A` = Air). Informational only — see Data Quality Notes |
| `Analysis` | `labresults.analysis` | EDD fraction code (e.g., `M` for Metals). May be NULL or blank if lab omits it |
| `Analysis Description` | Computed | Human-readable decode of `Analysis`. Returns NULL for NULL/blank `Analysis`; returns the raw code for unrecognized values as a data quality signal |

**Analysis fraction codes** (full set — most records in this data source are expected to be `M`):

| Code | Description |
|---|---|
| `V` | Volatiles |
| `B` | Semi-Volatiles |
| `P` | Pesticides/PCBs |
| `M` | Metals |
| `C` | Non-Metals/Other Inorganics |
| `T` | Total Petroleum Hydrocarbons |
| `F` | Dioxins/Furans |
| `H` | Herbicides |
| `R` | Radiological |
| `PC` | Physical Characteristic |

### Result Columns
| Column | Source | Notes |
|---|---|---|
| `Result` | `labresults.result × conversion_factor` | Numeric result in µg/m³. NULL if unit is unrecognized — see Unit Normalization |
| `Result Units` | Hardcoded `'µg/m³'` | Always µg/m³ — reflects target output unit, not original lab-submitted unit |
| `Method Detection Limit` | `labresults.mdl × conversion_factor` | MDL in µg/m³ |
| `Limit of Quantitation` | `labresults.limit_of_quantitation × conversion_factor` | LOQ in µg/m³ |
| `Reporting Limit` | `labresults.reporting_limit × conversion_factor` | RL in µg/m³ |
| `Lab Result Qualifier` | `labresults.lab_result_qualifier` | Raw qualifier string from lab |
| `Detected?` | Computed | Boolean. `TRUE` = detected; `FALSE` = non-detect |
| `Result Formatted` | Computed | Display-ready string in µg/m³ — see Detection Logic section |
| `Analyte` | `INITCAP(labresults.analyte)` | Title-cased. Labs commonly submit metal names in ALL CAPS (e.g., `LEAD` → `Lead`) |

---

## Detection Logic

Identical to the TO-15 data source. Detection status is determined by whether `Lab Result Qualifier` contains the letter `U` (case-insensitive):

- **Detected (`TRUE`):** qualifier is NULL, blank, or does not contain `U` — includes `J`, `J+`, `J-`, `R`, `PM`, or no qualifier.
- **Non-detect (`FALSE`):** qualifier contains `U` anywhere — covers `U`, `UJ`, compound strings like `U H Q III`, etc.

**`Result Formatted`** is built as follows (values in µg/m³ after conversion):

- **Detected:** `[trimmed value] ([qualifier if present]) µg/m³`  
  Example: `1.23 µg/m³` or `1.23 (J) µg/m³`
- **Non-detect:** `< [trimmed value] ([remaining qualifiers after U stripped]) µg/m³`  
  Example: `< 0.05 µg/m³` or `< 0.05 (J) µg/m³` (from qualifier `UJ`)

**Note on `R` qualifier (Rejected):** Treated as detected in this data source. Project technical directors and data management should review any `R`-qualified results before client reporting.

---

## ATSDR MRL Columns

Three sets of ATSDR MRL columns are joined for the **Inhalation** route — Acute, Intermediate, and Chronic — each providing a numeric column and a formatted string column, both in µg/m³.

The MRL join handles four source unit variants and converts each to µg/m³:

| MRL source unit | Conversion |
|---|---|
| mg/m³ | × 1000 |
| µg/m³ (ug/m3, µg/m3, μg/m3) | × 1 |
| ng/m³ | ÷ 1000 |
| pg/m³ | ÷ 1,000,000 |

The join itself is restricted to these four unit variants, so any MRL record stored with a different unit string will not match and the MRL columns will return NULL. Results and MRL columns are both in µg/m³, so direct numeric comparison in Tableau is valid without further conversion.

MRL columns return NULL when no matching ATSDR record exists for a given CAS number, route, and duration.

---

## Data Quality Notes

1. **Unrecognized `result_units` values produce NULL in all converted columns.** If `Result` is NULL but the row is otherwise populated, the lab submitted a unit string not covered by the conversion logic. Check `labresults.result_units` directly to identify the unit, add it to the `conversion_factor` CASE in the query if it is a legitimate mass/volume unit, or flag it as a data quality issue. In Tableau, filtering for rows where `Result` is NULL is the recommended way to audit for unit gaps.

2. **`matrix_id` is lab-reported and not used as a filter.** The `siera_subtype = 'Integrated Air Sample'` filter is authoritative. `Matrix` is included as an informational column only.

3. **`Analysis` (fraction code) may be NULL or blank.** Labs occasionally omit this field. `Analysis Description` will return NULL in these cases. Flag to the lab for correction on resubmittal.

4. **`Analyte` is title-cased via `INITCAP`.** This normalizes common ALL CAPS lab submissions. If an analyte name contains an acronym (e.g., `ICP`) it will be downcased (`Icp`). This is cosmetic and does not affect filtering or aggregation.

5. **`Validation Status` is Onterris-side only.** Populated by data management during internal QA/QC review; blank for unreviewed results.

6. **The join between SIERA and lab results uses `primary_identifier = samp_no`.** Mismatched sample IDs will cause results to silently disappear from the data source.

7. **Non-metals results may appear if a lab submits them with mass/volume units.** The unit exclusion logic removes dry weight units and vapor-phase units, but any physical parameter result submitted with a mass/volume unit string (e.g., a temperature in a non-standard unit) could pass through. Data management should review unexpected analytes.

---

## What This Data Source Does NOT Include

- QC samples of any kind (blanks, spikes, duplicates, LCS, etc.)
- Surrogates, internal standards, or TICs
- Results in vapor-phase units (ppm, ppb, ppt and variants)
- Results in dry weight / mass-only units (ug, mg, ng, pg, g, kg)
- Samples that have not yet received lab results
- SIERA records marked unusable, excluded, or deleted
- ATSDR MRLs for routes other than Inhalation
