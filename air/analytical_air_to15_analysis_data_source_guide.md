# TO-15 Canister Air Data Source Guide

**File:** `analytical_air_to15_analysis_data_source.sql`  
**Database:** `sample_cteh_com` — `public` schema  
**EDD Spec Reference:** Onterris Response and Recovery Laboratory EDD Specification v2.1.2  

---

## Purpose

This data source returns analytical results for canister-based ambient air samples (Minicanister and Summa Canister) for a single Onterris project. It is intended as a Tableau data source for reporting air monitoring results and comparing them against ATSDR Minimum Risk Levels (MRLs). All results and MRL values are normalized to **ppbv** (parts per billion by volume).

---

## Scope and Filters

The query is scoped to one project at a time via the `project_number` parameter. Records are included only when **all** of the following are true:

- `siera.siera_type = 'Sample-Pickup'` and `siera_subtype IN ('Minican', 'Summa Canister')` — air canister samples only, as curated by the field team in SIERA. This is the authoritative matrix filter; `matrix_id` from the lab EDD is **not** used as a filter (see Data Quality Notes).
- `siera.is_usable = TRUE`, `exclude_sample = FALSE`, `deleted_at IS NULL` — only active, valid SIERA records.
- `labresults.sample_type_code ILIKE '%trg%'` — site samples only (TRG, TRGDL, TRGRE). QC samples (blanks, spikes, duplicates, etc.) are intentionally excluded.
- `labresults.result_type_code = 'A'` — target analytes only. Surrogates (`S`), internal standards (`I`), and tentatively identified compounds (`T`/TICs) are excluded.
- `LOWER(labresults.result_units) IN ('ppm', 'ppb', 'ppt', 'ppmv', 'ppbv', 'pptv')` — vapor-phase concentration units only. The filter is case-insensitive; the six units in this list are the only recognized vapor-phase units and all will be normalized to ppbv.
- `labresults.samp_no IS NOT NULL` — only SIERA samples that have received lab results. Samples awaiting results are excluded by design; other workflows track data receipt status.

---

## Unit Normalization

All result values and limits (`Result`, `MDL`, `LOQ`, `RL`) are multiplied by a `conversion_factor` computed per row in the CTE, based on the lab-submitted `result_units`. The output is always in **ppbv**.

| Lab-submitted unit | conversion_factor | Notes |
|---|---|---|
| `ppm` or `ppmv` | 1000 | Multiply by 1000 to convert to ppb |
| `ppb` or `ppbv` | 1 | Already in ppb; pass through |
| `ppt` or `pptv` | 0.001 | Divide by 1000 to convert to ppb |
| Any other value | NULL (never reached) | ELSE NULL is defensive — the WHERE clause guarantees only the six units above reach the CTE |

Because the WHERE filter is an exclusive inclusive list, the ELSE NULL branch is unreachable in practice. It is retained so that if the filter is ever relaxed, unrecognized units produce NULL results in Tableau rather than silently incorrect values.

The `"Result Units"` column is hardcoded to `'ppbv'` in the output regardless of what the lab submitted.

---

## Key Column Reference

### Sample Identity
| Column | Source | Notes |
|---|---|---|
| `Siera ID` | `siera.id` | Internal SIERA primary key |
| `Primary Identifier` | `siera.primary_identifier` | Client sample ID; used to join to lab results via `labresults.samp_no` |
| `Secondary Identifier` | `siera.secondary_identifier` | Optional secondary label |
| `Sample Type` | `siera.sample_type` | SIERA-side sample type (distinct from the lab's `sample_type_code`) |
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
| `Analysis` | `labresults.analysis` | EDD fraction code (e.g., `V`, `M`, `PC`). May be NULL or blank if lab omits it |
| `Analysis Description` | Computed | Human-readable decode of `Analysis`. Returns NULL for NULL/blank `Analysis`; returns the raw code for unrecognized values as a data quality signal |

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
| `Result` | `labresults.result × conversion_factor` | Numeric result normalized to ppbv. For non-detections, the underlying `result` contains MDL, LOQ, or RL — whichever is lower (per EDD spec §2.1.0) |
| `Result Units` | Hardcoded | Always `'ppbv'` regardless of lab-submitted units |
| `Method Detection Limit` | `labresults.mdl × conversion_factor` | MDL normalized to ppbv |
| `Limit of Quantitation` | `labresults.limit_of_quantitation × conversion_factor` | LOQ normalized to ppbv |
| `Reporting Limit` | `labresults.reporting_limit × conversion_factor` | RL normalized to ppbv |
| `Result Formatted` | Computed | Display-ready string combining converted result value, qualifier, and hardcoded unit `ppbv`. See Detection Logic section |
| `Lab Result Qualifier` | `labresults.lab_result_qualifier` | Raw qualifier string from lab (e.g., `U`, `UJ`, `J`, `R`) |
| `Detected?` | Computed | Boolean. `TRUE` = detected; `FALSE` = non-detect |

---

## Detection Logic

Detection status is determined by whether the `Lab Result Qualifier` contains the letter `U` (case-insensitive):

- **Detected (`TRUE`):** qualifier is NULL, blank, or does not contain `U` — includes qualifiers like `J`, `J+`, `J-`, `R`, `PM`, or no qualifier at all.
- **Non-detect (`FALSE`):** qualifier contains `U` anywhere in the string — covers `U`, `UJ`, `U H Q III`, etc.

**`Result Formatted`** is a display string built as follows:

- **Detected:** `[trimmed numeric value] ([qualifier if present]) ppbv`  
  Example: `9.82 ppbv` or `9.82 (J) ppbv`
- **Non-detect:** `< [trimmed numeric value] ([remaining qualifiers after U is stripped]) ppbv`  
  Example: `< 0.5 ppbv` or `< 0.5 (J) ppbv` (from qualifier `UJ`)

Trailing zeros and unnecessary decimal points are stripped from numeric values in both cases. The unit string in `Result Formatted` is always hardcoded to `ppbv`.

**Note on `R` qualifier (Rejected):** Per the EDD spec, `R` means the result is rejected and the presence or absence of the analyte cannot be verified. This data source treats `R`-qualified results as **detected** because the `R` qualifier does not contain `U`. Project technical directors and data management should review any `R`-qualified results before client reporting.

---

## ATSDR MRL Columns

Three sets of ATSDR Minimum Risk Level columns are joined for the **Inhalation** route only, covering Acute, Intermediate, and Chronic durations. Each set provides a numeric column (in ppbv) and a formatted string column.

**Unit handling:** Only MRL records with `mrl_unit` of `ppm` or `ppb` (case-insensitive) are joined — other unit types in `atsdr_mrls` are excluded from the JOIN condition. MRL values in `ppm` are multiplied by 1000 to convert to ppbv; values in `ppb` are passed through unchanged.

**Important:** Result values in this data source may originate from `ppt`/`pptv` lab submissions (e.g., 500 pptv = 0.5 ppbv after normalization). The conversion is already applied in the `Result` column, so all comparisons against ATSDR MRL columns in ppbv are valid at face value.

MRL columns return NULL when no matching ATSDR record exists for a given CAS number, route, and duration combination.

---

## Data Quality Notes

1. **`matrix_id` is lab-reported and not used as a filter.** Labs occasionally submit incorrect matrix codes. The `siera_subtype` field — curated in-house by the field team — is the authoritative source for matrix type in this data source. `Matrix` is included as an informational column only.

2. **`Analysis` (fraction code) may be NULL or blank.** Labs occasionally omit this field. `Analysis Description` will return NULL in these cases. This should be flagged to the lab for correction on resubmittal.

3. **`Validation Status` is Onterris-side only.** This field is populated by the data management team during internal QA/QC review. It is not sourced from the lab EDD and will be blank for results that have not yet been reviewed.

4. **The join between SIERA and lab results uses `primary_identifier = samp_no`.** If a sample's `primary_identifier` does not match the lab's `samp_no` exactly, the result row will not join and the sample will not appear in this data source. Data management should verify sample ID consistency when results are expected but not appearing.

5. **Only one result type is returned (`result_type_code = 'A'`).** Surrogate recoveries, internal standard responses, and TICs are not included. These are available in the `labresults` table directly if needed.

---

## What This Data Source Does NOT Include

- QC samples of any kind (blanks, spikes, duplicates, LCS, etc.)
- Surrogate compounds, internal standards, or TICs
- Non-vapor-phase result units (e.g., `mg/m³`, `µg/m³`) — use the integrated air metals data source for those
- Samples that have not yet received lab results
- SIERA records marked unusable, excluded, or deleted
- ATSDR MRLs for routes other than Inhalation
