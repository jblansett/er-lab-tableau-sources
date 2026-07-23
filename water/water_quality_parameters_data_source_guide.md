# Water Quality Parameters Data Source Guide

**File:** `water_quality_parameters_data_source.sql`  
**Database:** `sample_cteh_com` — `public` schema  
**EDD Spec Reference:** N/A — this data source pulls field instrument readings from SIERA, not lab results

---

## Purpose

This data source returns field water quality parameter readings recorded in SIERA for a single Onterris project. Readings are captured in the field using handheld instruments (e.g., HORIBA water quality monitors) and entered into SIERA by field staff. This data source is intended for Tableau workbooks visualizing field water quality trends and QC review.

**This is not a lab results data source.** For analytical water chemistry results (metals, VOCs, etc.), use the appropriate analytical water data source.

---

## Scope and Filters

The query is scoped to one project at a time via the `project_number` parameter. Records are included only when **all** of the following are true:

- `siera.is_usable = TRUE`, `exclude_sample = FALSE`, `deleted_at IS NULL` — only active, valid SIERA records.
- At least one water quality field is non-NULL — the query self-selects records that have instrument readings rather than filtering on `siera_subtype`. This is intentional because water quality parameters may be recorded across multiple sample subtypes (grab samples, purge water, surface water, etc.) and relying on subtype would miss valid records if the field team miscategorized a sample.

There is no `siera_subtype` filter. Records appear based on whether instrument data was recorded, not on how the sample was categorized.

---

## Key Column Reference

### Project and Sample Identity
| Column | Source | Notes |
|---|---|---|
| `Siera ID` | `siera.id` | Internal SIERA primary key |
| `Sample Date` | `siera.date_time::date` | Date portion only |
| `Date Time` | `siera.date_time` | Full timestamp |
| `Primary Identifier` | `siera.primary_identifier` | Client sample ID |
| `Secondary Identifier` | `siera.secondary_identifier` | Optional secondary label |
| `Sample Type` | `siera.sample_type` | SIERA-side sample type |
| `SDG ID` | `siera.sdg_id` | Sample Delivery Group |
| `Field Comments` | `siera.comments` | Free-text comments entered by field staff |

### Plan and Assessment Context
| Column | Source | Notes |
|---|---|---|
| `Plan Name` | `plans.name` | The sampling plan this record is associated with in SIERA. NULL if not assigned to a plan |
| `Assessment Name` | `assessment_tracker_records.name` | Assessment the record is tied to. NULL if not assigned |
| `Assessment Label` | `assessment_tracker_records.label` | Short label for the assessment |
| `Assessment Status` | `assessment_tracker_records.assessment_status` | Current status of the associated assessment |

### Location
| Column | Source | Notes |
|---|---|---|
| `Location ID` | `locations.id` | Internal location primary key |
| `Location Code` | `locations.location_code` | Short location identifier |
| `Fixed Location Description` | `locations.location_description` | Description of the fixed location |
| `Location Type` | `location_types.name` | Category of location (e.g., monitoring well, surface water) |
| `Sample Latitude/Longitude` | `siera.latitude/longitude` | GPS coordinates recorded at time of sampling |
| `Location Latitude/Longitude` | `locations.latitude/longitude` | Coordinates of the fixed location record |

### Water Quality Parameters
| Column | Source column | Type | Unit | Notes |
|---|---|---|---|---|
| `Sample Color` | `ysi_color` | varchar | — | Qualitative description (e.g., "clear", "murky brown") |
| `Sample Odor` | `ysi_odor` | varchar | — | Qualitative description (e.g., "none", "petroleum") |
| `Turbidity (NTU)` | `ysi_turbidity_ntu` | varchar → numeric | NTU | Safe cast applied; see Data Quality Notes |
| `Temperature (°C)` | `ysi_temp_c` | varchar → numeric | °C | Safe cast applied |
| `Dissolved Oxygen (mg/L)` | `ysi_do_mgl` | varchar → numeric | mg/L | Safe cast applied |
| `Conductivity (mS/cm)` | `ysi_c_us` | varchar → numeric | mS/cm | Safe cast applied. Column name is a legacy artifact from older YSI instruments; values are stored in mS/cm as read directly from current instruments (e.g., HORIBA) |
| `pH` | `ysi_ph` | varchar → numeric | — | Safe cast applied |
| `Oxygen Reduction Potential (mV)` | `orp_mv` | numeric | mV | No cast needed |
| `Total Dissolved Solids (g/L)` | `tds_gl` | numeric | g/L | No cast needed |
| `Salinity (ppt)` | `salinity_ppt` | numeric | ppt | No cast needed |
| `Free Chlorine (mg/L)` | `cl2_free_mg_l` | numeric | mg/L | No cast needed |
| `Total Chlorine (mg/L)` | `cl2_total_mg_l` | numeric | mg/L | No cast needed |

### Depth Columns
| Column | Source | Notes |
|---|---|---|
| `Sample Depth From (ft)` | `siera.depth_from_ft_num` | Upper bound of sample interval |
| `Sample Depth To (ft)` | `siera.depth_to_ft_num` | Lower bound of sample interval |
| `Excavation Depth (ft)` | `siera.excavation_depth_ft_num` | Excavation depth at time of sampling |
| `Total Depth From (ft)` | `siera.total_depth_from_ft` | Total depth interval upper bound |
| `Total Depth To (ft)` | `siera.total_depth_to_ft` | Total depth interval lower bound |

Depth columns are included for context but are not part of the water quality presence filter — a record with only depth values and no instrument readings will not appear in this data source.

---

## Safe Cast Logic

Five water quality columns are stored as `character varying` in the database due to legacy schema design. They are cast to `numeric` using a regex check before casting:

```sql
CASE WHEN TRIM(ysi_temp_c) ~ '^-?\d*\.?\d+$'
     THEN TRIM(ysi_temp_c)::numeric
     ELSE NULL
END
```

- If the value is a valid number (including negative values and decimals), it is cast and returned.
- If the value is non-numeric (e.g., `NA`, `sensor broken`, `7,8`), it returns NULL and the bad value is captured in the `Water Quality QC Issues` column.
- NULL and blank values are passed through as NULL — these indicate the parameter was not recorded and are not flagged as QC issues.

---

## Water Quality QC Issues Column

The `Water Quality QC Issues` column aggregates all non-numeric entries found in the five safe-cast columns into a single comma-separated string. This allows QC review directly in Tableau without needing to inspect each column individually.

**Format:** `Field: 'bad_value'[, Field: 'bad_value'...]`  
**Examples:**
- All clean → `NULL`
- One issue → `Turbidity: 'NA'`
- Multiple issues → `Turbidity: 'NA', pH: '7,8'`

`NULL` indicates no data quality issues were detected in the numeric fields. In Tableau, filter on `Water Quality QC Issues IS NOT NULL` to isolate records that need correction.

Fields covered: Turbidity, Temperature, Dissolved Oxygen, Conductivity, pH.  
Fields NOT covered: Color and Odor (qualitative, varchar by design); ORP, TDS, Salinity, Chlorine (stored as numeric, cannot contain bad text).

---

## Data Quality Notes

1. **Column names reflect legacy instrument naming.** The `ysi_*` prefix refers to YSI brand instruments no longer in use. Current instruments (e.g., HORIBA) report the same parameters in the same units. The aliases in this data source use instrument-neutral labels.

2. **Conductivity is stored in mS/cm.** Despite the column name `ysi_c_us` (suggesting µS/cm), values are entered as read from the instrument display, which reports in mS/cm. No unit conversion is applied.

3. **No `siera_subtype` filter is applied.** Records self-select based on the presence of water quality data. This means a sample of any subtype will appear if it has instrument readings. Review `Sample Type` and location columns to identify unexpected record types.

4. **Plan and Assessment columns will be NULL** for samples not linked to a plan or assessment in SIERA. This is expected behavior, not a data issue.

5. **Field Comments are free text** entered by field staff and are not validated. They may be blank, abbreviated, or inconsistent across projects.

---

## What This Data Source Does NOT Include

- Lab analytical results of any kind — use the appropriate analytical water data source
- QC samples (blanks, duplicates, spikes)
- SIERA records marked unusable, excluded, or deleted
- Records with no water quality instrument readings recorded
- ATSDR MRLs or other health-based screening values (not applicable to field parameters)
