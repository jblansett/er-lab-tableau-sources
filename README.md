# Onterris Consulting Lab Data SQL

SQL data sources for Tableau workbooks reporting analytical laboratory results from environmental sampling. Queries target the `sample_cteh_com` database, `public` schema.

## Structure

Data sources and their documentation are organized by analytical matrix. Each folder contains the SQL query files, corresponding guide documents, and any associated Tableau workbooks.

```
air/        Airborne contaminant data sources (TO-15 VOCs, integrated air metals)
water/      Water data sources (groundwater, surface water) — in development
soil/       Soil data sources — in development
```

## Air Data Sources

| File | Description |
|---|---|
| `analytical_air_to15_analysis_data_source.sql` | Canister air samples (Minican / Summa Canister) analyzed by TO-15. Results in vapor-phase units (ppb, ppm, etc.). Includes ATSDR inhalation MRLs in ppbv. |
| `analytical_air_metals_analysis_data_source.sql` | Integrated air samples analyzed for metals (mod. NIOSH 7303 / ICP-MS). Results normalized to µg/m³ via unit-aware conversion. Includes ATSDR inhalation MRLs in µg/m³. |

Each SQL file has a corresponding `_guide.md` with documentation intended for both data management staff and AI agents working with the data source.

## Usage

All queries are parameterized by Onterris project number:

```sql
WHERE p.project_number = <Parameters.Enter Project Number>
```

In Tableau, this maps to a string parameter prompt at data source load time.

## Reference

- **EDD Specification:** Onterris Response and Recovery Laboratory EDD Specification v2.1.2
- **Database:** `sample_cteh_com` — `public` schema
