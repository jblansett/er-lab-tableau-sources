SELECT
    s.id AS "Siera ID",
    s.date_time::date AS "Sample Date",
    s.date_time AS "Date Time",
    p.project_name AS "Project Name",
    p.city AS "Project City",
    p.state AS "Project State",
    p.latitude AS "Project Latitude",
    p.longitude AS "Project Longitude",
    pl."name" as "Plan Name",
    atr."name" as "Assessment Name",
    atr.label as "Assessment Label",
    atr.assessment_status as "Assessment Status",
    s."comments" as "Field Comments",
    s.sdg_id AS "SDG ID",
    s.primary_identifier AS "Primary Identifier",
    s.secondary_identifier AS "Secondary Identifier",
    s.sample_type AS "Sample Type",
    s.latitude AS "Sample Latitude",
    s.longitude AS "Sample Longitude",
    l.latitude AS "Location Latitude",
    l.longitude AS "Location Longitude",
    lt.name AS "Location Type",
    l.id as "Location ID",
    l.location_code AS "Location Code",
    l.location_description AS "Fixed Location Description",
    -- Field water quality parameters
    s.ysi_color AS "Sample Color",
    s.ysi_odor AS "Sample Odor",
    CASE WHEN TRIM(s.ysi_turbidity_ntu) ~ '^-?\d*\.?\d+$'
         THEN TRIM(s.ysi_turbidity_ntu)::numeric
         ELSE NULL
    END AS "Turbidity (NTU)",
    CASE WHEN TRIM(s.ysi_temp_c) ~ '^-?\d*\.?\d+$'
         THEN TRIM(s.ysi_temp_c)::numeric
         ELSE NULL
    END AS "Temperature (°C)",
    CASE WHEN TRIM(s.ysi_do_mgl) ~ '^-?\d*\.?\d+$'
         THEN TRIM(s.ysi_do_mgl)::numeric
         ELSE NULL
    END AS "Dissolved Oxygen (mg/L)",
    CASE WHEN TRIM(s.ysi_c_us) ~ '^-?\d*\.?\d+$'
         THEN TRIM(s.ysi_c_us)::numeric
         ELSE NULL
    END AS "Conductivity (mS/cm)",
    CASE WHEN TRIM(s.ysi_ph) ~ '^-?\d*\.?\d+$'
         THEN TRIM(s.ysi_ph)::numeric
         ELSE NULL
    END AS "pH",
    s.orp_mv AS "Oxygen Reduction Potential (mV)",
    s.tds_gl AS "Total Dissolved Solids (g/L)",
    s.salinity_ppt AS "Salinity (ppt)",
    s.cl2_free_mg_l AS "Free Chlorine (mg/L)",
    s.cl2_total_mg_l AS "Total Chlorine (mg/L)",
    -- Data quality: non-numeric entries in field instrument columns.
    -- Returns NULL if all fields are clean; otherwise a comma-separated list
    -- of the offending field names and the bad values they contain.
    -- Example: "Turbidity: 'NA', pH: '7,8'"
    NULLIF(
        array_to_string(
            ARRAY[
                CASE WHEN TRIM(s.ysi_turbidity_ntu) IS NOT NULL
                          AND TRIM(s.ysi_turbidity_ntu) != ''
                          AND TRIM(s.ysi_turbidity_ntu) !~ '^-?\d*\.?\d+$'
                     THEN 'Turbidity: ''' || TRIM(s.ysi_turbidity_ntu) || ''''
                END,
                CASE WHEN TRIM(s.ysi_temp_c) IS NOT NULL
                          AND TRIM(s.ysi_temp_c) != ''
                          AND TRIM(s.ysi_temp_c) !~ '^-?\d*\.?\d+$'
                     THEN 'Temperature: ''' || TRIM(s.ysi_temp_c) || ''''
                END,
                CASE WHEN TRIM(s.ysi_do_mgl) IS NOT NULL
                          AND TRIM(s.ysi_do_mgl) != ''
                          AND TRIM(s.ysi_do_mgl) !~ '^-?\d*\.?\d+$'
                     THEN 'Dissolved Oxygen: ''' || TRIM(s.ysi_do_mgl) || ''''
                END,
                CASE WHEN TRIM(s.ysi_c_us) IS NOT NULL
                          AND TRIM(s.ysi_c_us) != ''
                          AND TRIM(s.ysi_c_us) !~ '^-?\d*\.?\d+$'
                     THEN 'Conductivity: ''' || TRIM(s.ysi_c_us) || ''''
                END,
                CASE WHEN TRIM(s.ysi_ph) IS NOT NULL
                          AND TRIM(s.ysi_ph) != ''
                          AND TRIM(s.ysi_ph) !~ '^-?\d*\.?\d+$'
                     THEN 'pH: ''' || TRIM(s.ysi_ph) || ''''
                END
            ],
            ', '
        ),
        ''
    ) AS "Water Quality QC Issues",
    s.depth_from_ft_num as "Sample Depth From (ft)",
    s.depth_to_ft_num as "Sample Depth To (ft)",
    s.excavation_depth_ft_num as "Excavation Depth (ft)",
    s.total_depth_from_ft as "Total Depth From (ft)",
    s.total_depth_to_ft as "Total Depth To (ft)"
FROM siera AS s
JOIN projects AS p
    ON p.project_number = <Parameters.Project Number>
    AND s.project_id = p.id
LEFT JOIN locations AS l
    ON s.project_id = l.project_id
    AND s.location_id = l.id
LEFT JOIN location_types AS lt
    ON l.location_type_id = lt.id
LEFT JOIN plans pl
    ON s.project_id = pl.project_id
    AND s.plan_id = pl.id
LEFT JOIN assessment_tracker_records atr
    ON s.project_id = atr.project_id
    AND s.atr_id = atr.id
WHERE s.is_usable = TRUE
    AND COALESCE(s.exclude_sample, FALSE) = FALSE
    AND s.deleted_at IS NULL
    AND (
        s.ysi_color IS NOT NULL
        OR s.ysi_odor IS NOT NULL
        OR s.ysi_turbidity_ntu IS NOT NULL
        OR s.ysi_temp_c IS NOT NULL
        OR s.ysi_do_mgl IS NOT NULL
        OR s.ysi_c_us IS NOT NULL
        OR s.ysi_ph IS NOT NULL
        OR s.orp_mv IS NOT NULL
        OR s.tds_gl IS NOT NULL
        OR s.salinity_ppt IS NOT NULL
        OR s.cl2_free_mg_l IS NOT NULL
        OR s.cl2_total_mg_l IS NOT NULL
    )
