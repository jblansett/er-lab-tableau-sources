# Analytical Water Data Source Guide

**File:** `analytical_water_analysis_data_source.sql`  
**Database:** `sample_cteh_com` — `public` schema  
**EDD Spec Reference:** Onterris Response and Recovery Laboratory EDD Specification v2.1.2

---

## Purpose

This data source returns analytical laboratory results for water samples collected during Onterris emergency response projects. It covers five water sample subtypes: Drinking Water, Groundwater, Surface Water, Waste Water, and Waste Characterization. It is intended as a Tableau data source for reporting water analytical results in a standardized format.

This data source also includes field water quality parameter columns (instrument readings) alongside lab results. These will be NULL for any sample where field parameters were not recorded — this is expected and not a data issue.

**For field water quality parameters only (no lab results),** use `water_quality_parameters_data_source.sql` instead.

---

## Scope and Filters

The query is scoped to one project at a time via the `project_number` parameter. Records are included only when **all** of the following are true:

- `siera.siera_type = 'Sample-Pickup'` and `siera_subtype IN ('Drinking Water', 'Groundwater', 'Surface Water', 'Waste Water', 'Waste Characterization')` — water samples only, as curated in SIERA. This is the authoritative matrix filter; `matrix_id` from the lab EDD is not used as a filter.
- `siera.is_usable = TRUE`, `exclude_sample = FALSE`, `deleted_at IS NULL` — only active, valid SIERA records.
- `labresults.sample_type_code ILIKE '%trg%'` — site samples only (TRG, TRGDL, TRGRE). QC samples are intentionally excluded.
- `labresults.result_type_code = 'A'` — target analytes only. Surrogates, internal standards, and TICs are excluded.
- `labresults.samp_no IS NOT NULL` — only SIERA samples that have received lab results.

There is no `result_units` WHERE filter. All result rows pass through regardless of unit, and the `conversion_factor` CTE handles normalization. Rows with unrecognized units return NULL for all converted result columns — see Unit Normalization section.

---

## Unit Normalization

All result values and limits (`Result`, `MDL`, `LOQ`, `RL`) are multiplied by a `conversion_factor` computed per row in the CTE, based on the lab-submitted `result_units`. The output target unit is **µg/L**.

| Lab-submitted unit (ILIKE pattern) | conversion_factor | Notes |
|---|---|---|
| `kg/L%` | 1,000,000,000 | |
| `g/L%` | 1,000,000 | |
| `mg/L%` | 1,000 | Most common lab-submitted unit |
| `ug/L%`, `µg/L%`, `μg/L%` | 1 | Already in µg/L; pass through |
| `ng/L%` | 0.001 | |
| `pg/L%` | 0.000001 | |
| Any other value | NULL | Non-aqueous units (e.g., `degC`, `%REC`, `NTU`) or unrecognized strings |

Unit matching uses `ILIKE` prefix patterns (e.g., `ILIKE 'mg/L%'`) to accommodate minor variations in how labs format unit strings. All three Unicode variants of the microgram symbol are matched for µg/L.

**NULL result behavior:** When `conversion_factor` is NULL, all converted columns (`Result`, `MDL`, `LOQ`, `RL`, `Result Formatted`) return NULL. In Tableau, filter on `Result IS NULL` to identify any rows with unrecognized units and report them to the lab for correction on resubmittal.

The `"Result Units"` column is hardcoded to `'µg/L'` in the output regardless of what the lab submitted.

---

## Key Column Reference

### Sample Identity
| Column | Source | Notes |
|---|---|---|
| `Siera ID` | `siera.id` | Internal SIERA primary key |
| `Primary Identifier` | `siera.primary_identifier` | Client sample ID; used to join to lab results via `labresults.samp_no` |
| `Secondary Identifier` | `siera.secondary_identifier` | Optional secondary label |
| `Sample Type` | `siera.sample_type` | SIERA-side sample type |
| `Sample Subtype` | `siera.siera_subtype` | Water sample category (Drinking Water, Groundwater, Surface Water, Waste Water, Waste Characterization). Use this to filter by water type in Tableau |
| `SDG ID` | `siera.sdg_id` | Sample Delivery Group |
| `Field Comments` | `siera.comments` | Free-text field comments entered in SIERA |

### Plan and Assessment Context
| Column | Source | Notes |
|---|---|---|
| `Plan Name` | `plans.name` | Sampling plan this record is associated with. NULL if not assigned |
| `Assessment Name` | `assessment_tracker_records.name` | Assessment this record is tied to. NULL if not assigned |
| `Assessment Label` | `assessment_tracker_records.label` | Short label for the assessment |
| `Assessment Status` | `assessment_tracker_records.assessment_status` | Current status of the associated assessment |

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
| `Matrix` | `labresults.matrix_id` | Lab-reported matrix code. Informational only — not used as a filter |
| `Analysis` | `labresults.analysis` | EDD fraction code (e.g., `V`, `M`). May be NULL or blank if lab omits it |
| `Analysis Description` | Computed | Human-readable decode of `Analysis`. Returns NULL for NULL/blank; returns raw code for unrecognized values |

**Analysis fraction codes:**

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
| `Result` | `labresults.result × conversion_factor` | Numeric result normalized to µg/L. NULL if unit is unrecognized |
| `Result Units` | Hardcoded | Always `'µg/L'` |
| `Method Detection Limit` | `labresults.mdl × conversion_factor` | MDL normalized to µg/L |
| `Limit of Quantitation` | `labresults.limit_of_quantitation × conversion_factor` | LOQ normalized to µg/L |
| `Reporting Limit` | `labresults.reporting_limit × conversion_factor` | RL normalized to µg/L |
| `Result Formatted` | Computed | Display-ready string with converted value, qualifier, and hardcoded unit `µg/L` |
| `Lab Result Qualifier` | `labresults.lab_result_qualifier` | Raw qualifier string from lab |
| `Detected?` | Computed | Boolean. `TRUE` = detected; `FALSE` = non-detect |

### Field Water Quality Parameters
These columns are pulled from SIERA and reflect readings from handheld field instruments. They will be NULL for samples where field parameters were not recorded.

| Column | Source column | Notes |
|---|---|---|
| `Sample Color` | `ysi_color` | Qualitative; varchar |
| `Sample Odor` | `ysi_odor` | Qualitative; varchar |
| `Turbidity (NTU)` | `ysi_turbidity_ntu` | Safe cast applied; see Water Quality QC Issues |
| `Temperature (°C)` | `ysi_temp_c` | Safe cast applied |
| `Dissolved Oxygen (mg/L)` | `ysi_do_mgl` | Safe cast applied |
| `Conductivity (mS/cm)` | `ysi_c_us` | Safe cast applied. Column name is legacy; values stored in mS/cm |
| `pH` | `ysi_ph` | Safe cast applied |
| `Oxygen Reduction Potential (mV)` | `orp_mv` | Numeric; no cast needed |
| `Total Dissolved Solids (g/L)` | `tds_gl` | Numeric; no cast needed |
| `Salinity (ppt)` | `salinity_ppt` | Numeric; no cast needed |
| `Free Chlorine (mg/L)` | `cl2_free_mg_l` | Numeric; no cast needed |
| `Total Chlorine (mg/L)` | `cl2_total_mg_l` | Numeric; no cast needed |
| `Water Quality QC Issues` | Computed | Comma-separated list of field parameter columns containing non-numeric text. NULL if all clean. See Water Quality QC Issues section |

---

## Detection Logic

Detection status is determined by whether `Lab Result Qualifier` contains the letter `U` (case-insensitive):

- **Detected (`TRUE`):** qualifier is NULL, blank, or does not contain `U`
- **Non-detect (`FALSE`):** qualifier contains `U` anywhere in the string

**`Result Formatted`** examples:
- Detected: `45.2 µg/L` or `45.2 (J) µg/L`
- Non-detect: `< 1.0 µg/L` or `< 1.0 (J) µg/L` (from qualifier `UJ`)

**Note on `R` qualifier (Rejected):** `R`-qualified results are treated as detected because `R` does not contain `U`. Review `R`-qualified results with the project TD before client reporting.

---

## Water Quality QC Issues Column

The `Water Quality QC Issues` column aggregates non-numeric entries in the five safe-cast field parameter columns into a single comma-separated string.

**Format:** `Field: 'bad_value'[, Field: 'bad_value'...]`

- All clean → `NULL`
- One issue → `pH: '7,8'`
- Multiple issues → `Turbidity: 'NA', pH: '7,8'`

Filter on `Water Quality QC Issues IS NOT NULL` in Tableau to isolate records needing correction. Fields covered: Turbidity, Temperature, Dissolved Oxygen, Conductivity, pH.

---

## Data Quality Notes

1. **`matrix_id` is lab-reported and not used as a filter.** The `siera_subtype` field is the authoritative source for water sample type. `Matrix` is informational only.

2. **NULL result columns indicate an unrecognized unit.** Filter on `Result IS NULL` in Tableau to find these rows. The `result_units` column will show the original lab-submitted unit string for auditing.

3. **Field water quality columns will be NULL for most lab result rows.** This is expected — field parameters are recorded once per sample event, not once per analyte. All analyte rows for a given sample will carry the same field parameter values (or all NULL if none were recorded).

4. **`Analysis` (fraction code) may be NULL or blank.** `Analysis Description` returns NULL in these cases and should be flagged to the lab for correction.

5. **`Validation Status` is Onterris-side only.** Populated by the data management team during internal QA/QC. Blank for results not yet reviewed.

6. **The join between SIERA and lab results uses `primary_identifier = samp_no`.** Mismatches between these fields will cause results to not appear. Verify sample ID consistency when expected results are missing.

7. **`Sample Subtype` reflects SIERA categorization, not the lab's matrix code.** Use `Sample Subtype` to filter by water type in Tableau. The five subtypes in this data source may have different applicable screening values — confirm the appropriate standards with the project TD before reporting.

---

## What This Data Source Does NOT Include

- QC samples (blanks, spikes, duplicates, LCS, etc.)
- Surrogate compounds, internal standards, or TICs
- Samples that have not yet received lab results
- SIERA records marked unusable, excluded, or deleted
- Health-based screening values or MRLs — these are not joined in this data source
- Non-water SIERA subtypes — for air samples use the air data sources; soil/wipe sources are in development
