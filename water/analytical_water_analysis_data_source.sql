-- Analytical Water Sampling Results
-- Subtypes: Drinking Water, Groundwater, Surface Water, Waste Water, Waste Characterization
-- All results converted to µg/L where possible; non-aqueous units (e.g. degC, %REC) return NULL result
WITH base AS (
    SELECT
        s.id,
        s.date_time,
        p.project_name,
        p.city,
        p.state,
        p.latitude                  AS project_lat,
        p.longitude                 AS project_lon,
        pl.name                     AS plan_name,
        atr.name                    AS assessment_name,
        atr.label                   AS assessment_label,
        atr.assessment_status       AS assessment_status,
        s.comments                  AS field_comments,
        s.sdg_id,
        s.primary_identifier,
        s.secondary_identifier,
        s.sample_type,
        s.siera_subtype,
        lr.matrix_id,
        s.latitude                  AS sample_lat,
        s.longitude                 AS sample_lon,
        l.latitude                  AS location_lat,
        l.longitude                 AS location_lon,
        lt.name                     AS location_type,
        l.id                        AS location_id,
        l.location_code,
        l.location_description,
        -- Field water quality parameters (varchar columns require safe cast in outer SELECT)
        s.ysi_color,
        s.ysi_odor,
        s.ysi_turbidity_ntu,
        s.ysi_temp_c,
        s.ysi_do_mgl,
        s.ysi_c_us,
        s.ysi_ph,
        s.orp_mv,
        s.tds_gl,
        s.salinity_ppt,
        s.cl2_free_mg_l,
        s.cl2_total_mg_l,
        -- Depth
        s.depth_from_ft_num,
        s.depth_to_ft_num,
        s.excavation_depth_ft_num,
        s.total_depth_from_ft,
        s.total_depth_to_ft,
        -- Lab result columns
        lr.lab_name,
        lr.lab_coc_no,
        lr.samp_no,
        lr.lab_batch_no,
        lr.qa_comment,
        lr.qa_level,
        lr.analysis,
        lr.analytical_method,
        lr.analyte,
        lr.cas_no,
        lr.result_units,
        lr.result,
        lr.mdl,
        lr.limit_of_quantitation,
        lr.reporting_limit,
        lr.lab_result_qualifier,
        -- Conversion factor to µg/L based on lab-submitted result_units.
        -- Non-aqueous units (e.g. degC, %REC, NTU) return NULL, which surfaces
        -- as NULL result columns in Tableau for auditing rather than silently wrong values.
        CASE
            WHEN lr.result_units ILIKE 'kg/L%'  THEN 1000000000.0
            WHEN lr.result_units ILIKE 'g/L%'   THEN 1000000.0
            WHEN lr.result_units ILIKE 'mg/L%'  THEN 1000.0
            WHEN lr.result_units ILIKE 'ug/L%'
              OR lr.result_units ILIKE 'µg/L%'
              OR lr.result_units ILIKE 'μg/L%'  THEN 1.0
            WHEN lr.result_units ILIKE 'ng/L%'  THEN 0.001
            WHEN lr.result_units ILIKE 'pg/L%'  THEN 0.000001
            ELSE NULL
        END AS conversion_factor
    FROM siera AS s
    JOIN projects AS p
        ON s.project_id = p.id
    LEFT JOIN labresults AS lr
        ON s.project_id = lr.project_id
        AND s.primary_identifier = lr.samp_no
        AND lr.sample_type_code ILIKE '%trg%'
        AND lr.result_type_code = 'A'
    LEFT JOIN locations AS l
        ON s.project_id = l.project_id
        AND s.location_id = l.id
    LEFT JOIN location_types AS lt
        ON l.location_type_id = lt.id
    LEFT JOIN plans AS pl
        ON s.project_id = pl.project_id
        AND s.plan_id = pl.id
    LEFT JOIN assessment_tracker_records AS atr
        ON s.project_id = atr.project_id
        AND s.atr_id = atr.id
    WHERE p.project_number = <Parameters.Enter Project Number>
        AND s.is_usable = TRUE
        AND COALESCE(s.exclude_sample, FALSE) = FALSE
        AND s.deleted_at IS NULL
        AND s.siera_type = 'Sample-Pickup'
        AND s.siera_subtype IN ('Drinking Water', 'Groundwater', 'Surface Water', 'Waste Water', 'Waste Characterization')
        AND lr.samp_no IS NOT NULL
)
SELECT
    id AS "Siera ID",
    date_time::date AS "Sample Date",
    date_time AS "Date Time",
    project_name AS "Project Name",
    city AS "Project City",
    state AS "Project State",
    project_lat AS "Project Latitude",
    project_lon AS "Project Longitude",
    plan_name AS "Plan Name",
    assessment_name AS "Assessment Name",
    assessment_label AS "Assessment Label",
    assessment_status AS "Assessment Status",
    field_comments AS "Field Comments",
    sdg_id AS "SDG ID",
    primary_identifier AS "Primary Identifier",
    secondary_identifier AS "Secondary Identifier",
    sample_type AS "Sample Type",
    siera_subtype AS "Sample Subtype",
    matrix_id AS "Matrix",
    sample_lat AS "Sample Latitude",
    sample_lon AS "Sample Longitude",
    location_lat AS "Location Latitude",
    location_lon AS "Location Longitude",
    location_type AS "Location Type",
    location_id AS "Location ID",
    location_code AS "Location Code",
    location_description AS "Fixed Location Description",
    -- Field water quality parameters
    ysi_color AS "Sample Color",
    ysi_odor AS "Sample Odor",
    CASE WHEN TRIM(ysi_turbidity_ntu) ~ '^-?\d*\.?\d+$'
         THEN TRIM(ysi_turbidity_ntu)::numeric
         ELSE NULL
    END AS "Turbidity (NTU)",
    CASE WHEN TRIM(ysi_temp_c) ~ '^-?\d*\.?\d+$'
         THEN TRIM(ysi_temp_c)::numeric
         ELSE NULL
    END AS "Temperature (°C)",
    CASE WHEN TRIM(ysi_do_mgl) ~ '^-?\d*\.?\d+$'
         THEN TRIM(ysi_do_mgl)::numeric
         ELSE NULL
    END AS "Dissolved Oxygen (mg/L)",
    CASE WHEN TRIM(ysi_c_us) ~ '^-?\d*\.?\d+$'
         THEN TRIM(ysi_c_us)::numeric
         ELSE NULL
    END AS "Conductivity (mS/cm)",
    CASE WHEN TRIM(ysi_ph) ~ '^-?\d*\.?\d+$'
         THEN TRIM(ysi_ph)::numeric
         ELSE NULL
    END AS "pH",
    orp_mv AS "Oxygen Reduction Potential (mV)",
    tds_gl AS "Total Dissolved Solids (g/L)",
    salinity_ppt AS "Salinity (ppt)",
    cl2_free_mg_l AS "Free Chlorine (mg/L)",
    cl2_total_mg_l AS "Total Chlorine (mg/L)",
    -- Data quality: non-numeric entries in field instrument columns
    NULLIF(
        array_to_string(
            ARRAY[
                CASE WHEN TRIM(ysi_turbidity_ntu) IS NOT NULL
                          AND TRIM(ysi_turbidity_ntu) != ''
                          AND TRIM(ysi_turbidity_ntu) !~ '^-?\d*\.?\d+$'
                     THEN 'Turbidity: ''' || TRIM(ysi_turbidity_ntu) || ''''
                END,
                CASE WHEN TRIM(ysi_temp_c) IS NOT NULL
                          AND TRIM(ysi_temp_c) != ''
                          AND TRIM(ysi_temp_c) !~ '^-?\d*\.?\d+$'
                     THEN 'Temperature: ''' || TRIM(ysi_temp_c) || ''''
                END,
                CASE WHEN TRIM(ysi_do_mgl) IS NOT NULL
                          AND TRIM(ysi_do_mgl) != ''
                          AND TRIM(ysi_do_mgl) !~ '^-?\d*\.?\d+$'
                     THEN 'Dissolved Oxygen: ''' || TRIM(ysi_do_mgl) || ''''
                END,
                CASE WHEN TRIM(ysi_c_us) IS NOT NULL
                          AND TRIM(ysi_c_us) != ''
                          AND TRIM(ysi_c_us) !~ '^-?\d*\.?\d+$'
                     THEN 'Conductivity: ''' || TRIM(ysi_c_us) || ''''
                END,
                CASE WHEN TRIM(ysi_ph) IS NOT NULL
                          AND TRIM(ysi_ph) != ''
                          AND TRIM(ysi_ph) !~ '^-?\d*\.?\d+$'
                     THEN 'pH: ''' || TRIM(ysi_ph) || ''''
                END
            ],
            ', '
        ),
        ''
    ) AS "Water Quality QC Issues",
    -- Depth
    depth_from_ft_num AS "Sample Depth From (ft)",
    depth_to_ft_num AS "Sample Depth To (ft)",
    excavation_depth_ft_num AS "Excavation Depth (ft)",
    total_depth_from_ft AS "Total Depth From (ft)",
    total_depth_to_ft AS "Total Depth To (ft)",
    -- Lab result columns
    lab_name AS "Laboratory",
    lab_coc_no AS "Laboratory COC",
    samp_no AS "Sample ID",
    lab_batch_no AS "Lab Batch No",
    qa_comment AS "Lab QA Comment",
    qa_level AS "Validation Status",
    analysis AS "Analysis",
    CASE NULLIF(TRIM(analysis), '')
        WHEN 'V'  THEN 'Volatiles'
        WHEN 'B'  THEN 'Semi-Volatiles'
        WHEN 'P'  THEN 'Pesticides/PCBs'
        WHEN 'M'  THEN 'Metals'
        WHEN 'C'  THEN 'Non-Metals/Other Inorganics'
        WHEN 'T'  THEN 'Total Petroleum Hydrocarbons'
        WHEN 'F'  THEN 'Dioxins/Furans'
        WHEN 'H'  THEN 'Herbicides'
        WHEN 'R'  THEN 'Radiological'
        WHEN 'PC' THEN 'Physical Characteristic'
        ELSE NULLIF(TRIM(analysis), '')
    END AS "Analysis Description",
    analytical_method AS "Analytical Method",
    INITCAP(analyte) AS "Analyte",
    cas_no AS "CAS Number",
    'µg/L' AS "Result Units",
    result * conversion_factor AS "Result",
    mdl * conversion_factor AS "Method Detection Limit",
    limit_of_quantitation * conversion_factor AS "Limit of Quantitation",
    reporting_limit * conversion_factor AS "Reporting Limit",
    lab_result_qualifier AS "Lab Result Qualifier",
    CASE
        WHEN lab_result_qualifier IS NULL
            OR lab_result_qualifier = ''
            OR lab_result_qualifier NOT ILIKE '%u%'
            THEN TRUE
        ELSE FALSE
    END AS "Detected?",
    CASE
        WHEN lab_result_qualifier IS NULL
            OR lab_result_qualifier = ''
            OR lab_result_qualifier NOT ILIKE '%u%'
        THEN
            RTRIM(
                RTRIM(
                    TO_CHAR(
                        result * conversion_factor,
                        'FM999,999,999,999,990.9999999999'
                    ),
                    '0'
                ),
                '.'
            )
            ||
            CASE
                WHEN NULLIF(TRIM(lab_result_qualifier), '') IS NOT NULL
                    THEN ' (' || TRIM(lab_result_qualifier) || ')'
                ELSE ''
            END
            || ' µg/L'
        ELSE
            '< '
            ||
            RTRIM(
                RTRIM(
                    TO_CHAR(
                        result * conversion_factor,
                        'FM999,999,999,999,990.9999999999'
                    ),
                    '0'
                ),
                '.'
            )
            ||
            CASE
                WHEN NULLIF(
                    TRIM(REGEXP_REPLACE(lab_result_qualifier, 'u', '', 'gi')),
                    ''
                ) IS NOT NULL
                    THEN ' (' ||
                         TRIM(REGEXP_REPLACE(lab_result_qualifier, 'u', '', 'gi'))
                         || ')'
                ELSE ''
            END
            || ' µg/L'
    END AS "Result Formatted"
FROM base
