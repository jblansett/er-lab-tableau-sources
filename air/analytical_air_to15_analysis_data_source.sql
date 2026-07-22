WITH base AS (
    SELECT
        s.id,
        s.date_time,
        p.project_name,
        p.city,
        p.state,
        p.latitude                  AS project_lat,
        p.longitude                 AS project_lon,
        s.sdg_id,
        s.primary_identifier,
        s.secondary_identifier,
        s.sample_type,
        lr.matrix_id,
        s.latitude                  AS sample_lat,
        s.longitude                 AS sample_lon,
        l.latitude                  AS location_lat,
        l.longitude                 AS location_lon,
        lt.name                     AS location_type,
        l.location_code,
        l.location_description,
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
        mrls_inh_acute.mrl_value    AS mrl_acute_value,
        mrls_inh_acute.mrl_unit     AS mrl_acute_unit,
        mrls_inh_int.mrl_value      AS mrl_int_value,
        mrls_inh_int.mrl_unit       AS mrl_int_unit,
        mrls_inh_chronic.mrl_value  AS mrl_chronic_value,
        mrls_inh_chronic.mrl_unit   AS mrl_chronic_unit,
        -- Conversion factor to ppbv based on lab-submitted result_units.
        -- The WHERE clause guarantees only the six known units reach this CASE,
        -- so ELSE NULL is defensive and unreachable in practice.
        CASE LOWER(lr.result_units)
            WHEN 'ppm'  THEN 1000.0
            WHEN 'ppmv' THEN 1000.0
            WHEN 'ppb'  THEN 1.0
            WHEN 'ppbv' THEN 1.0
            WHEN 'ppt'  THEN 0.001
            WHEN 'pptv' THEN 0.001
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
        ON s.location_id = l.id
    LEFT JOIN location_types AS lt
        ON l.location_type_id = lt.id
    LEFT JOIN atsdr_mrls AS mrls_inh_acute
        ON lr.cas_no = mrls_inh_acute.cas_number
        AND LOWER(mrls_inh_acute.mrl_unit) IN ('ppm', 'ppb')
        AND mrls_inh_acute.duration = 'Acute'
        AND mrls_inh_acute.route = 'Inhalation'
    LEFT JOIN atsdr_mrls AS mrls_inh_int
        ON lr.cas_no = mrls_inh_int.cas_number
        AND LOWER(mrls_inh_int.mrl_unit) IN ('ppm', 'ppb')
        AND mrls_inh_int.duration = 'Intermediate'
        AND mrls_inh_int.route = 'Inhalation'
    LEFT JOIN atsdr_mrls AS mrls_inh_chronic
        ON lr.cas_no = mrls_inh_chronic.cas_number
        AND LOWER(mrls_inh_chronic.mrl_unit) IN ('ppm', 'ppb')
        AND mrls_inh_chronic.duration = 'Chronic'
        AND mrls_inh_chronic.route = 'Inhalation'
    WHERE p.project_number = <Parameters.Enter Project Number>
        AND s.is_usable = TRUE
        AND COALESCE(s.exclude_sample, FALSE) = FALSE
        AND s.deleted_at IS NULL
        AND s.siera_type = 'Sample-Pickup'
        AND s.siera_subtype IN ('Minican', 'Summa Canister')
        AND lr.samp_no IS NOT NULL
        AND LOWER(lr.result_units) IN ('ppm', 'ppb', 'ppt', 'ppmv', 'ppbv', 'pptv')
)
SELECT
    id AS "Siera ID",
    date_time::date AS "Sample Date",
    project_name AS "Project Name",
    city AS "Project City",
    state AS "Project State",
    project_lat AS "Project Latitude",
    project_lon AS "Project Longitude",
    sdg_id AS "SDG ID",
    primary_identifier AS "Primary Identifier",
    secondary_identifier AS "Secondary Identifier",
    date_time AS "Date Time",
    sample_type AS "Sample Type",
    matrix_id AS "Matrix",
    sample_lat AS "Sample Latitude",
    sample_lon AS "Sample Longitude",
    location_lat AS "Location Latitude",
    location_lon AS "Location Longitude",
    location_type AS "Location Type",
    location_code AS "Location Code",
    location_description AS "Fixed Location Description",
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
    analyte AS "Analyte",
    cas_no AS "CAS Number",
    'ppbv' AS "Result Units",
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
            || ' ppbv'
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
            || ' ppbv'
    END AS "Result Formatted",
    -- ATSDR MRL: Inhalation, Acute
    CASE
        WHEN LOWER(mrl_acute_unit) = 'ppm' THEN mrl_acute_value * 1000
        WHEN LOWER(mrl_acute_unit) = 'ppb' THEN mrl_acute_value
    END AS "ATSDR MRL - Inhalation, Acute (ppbv)",
    RTRIM(RTRIM(TO_CHAR(
        CASE
            WHEN LOWER(mrl_acute_unit) = 'ppm' THEN mrl_acute_value * 1000
            WHEN LOWER(mrl_acute_unit) = 'ppb' THEN mrl_acute_value
        END,
        'FM999,999,999,999,990.9999999999'
    ), '0'), '.') AS "ATSDR MRL - Inhalation, Acute (ppbv) String",
    -- ATSDR MRL: Inhalation, Intermediate
    CASE
        WHEN LOWER(mrl_int_unit) = 'ppm' THEN mrl_int_value * 1000
        WHEN LOWER(mrl_int_unit) = 'ppb' THEN mrl_int_value
    END AS "ATSDR MRL - Inhalation, Intermediate (ppbv)",
    RTRIM(RTRIM(TO_CHAR(
        CASE
            WHEN LOWER(mrl_int_unit) = 'ppm' THEN mrl_int_value * 1000
            WHEN LOWER(mrl_int_unit) = 'ppb' THEN mrl_int_value
        END,
        'FM999,999,999,999,990.9999999999'
    ), '0'), '.') AS "ATSDR MRL - Inhalation, Intermediate (ppbv) String",
    -- ATSDR MRL: Inhalation, Chronic
    CASE
        WHEN LOWER(mrl_chronic_unit) = 'ppm' THEN mrl_chronic_value * 1000
        WHEN LOWER(mrl_chronic_unit) = 'ppb' THEN mrl_chronic_value
    END AS "ATSDR MRL - Inhalation, Chronic (ppbv)",
    RTRIM(RTRIM(TO_CHAR(
        CASE
            WHEN LOWER(mrl_chronic_unit) = 'ppm' THEN mrl_chronic_value * 1000
            WHEN LOWER(mrl_chronic_unit) = 'ppb' THEN mrl_chronic_value
        END,
        'FM999,999,999,999,990.9999999999'
    ), '0'), '.') AS "ATSDR MRL - Inhalation, Chronic (ppbv) String"
FROM base
