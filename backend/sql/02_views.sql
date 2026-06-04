USE agri_ai;
GO

CREATE OR ALTER VIEW vw_field_agent_context AS
SELECT
    f.id AS field_id, f.name AS field_name, f.soil_type,
    fa.name AS farm_name, fa.id AS farm_id,
    u.full_name AS farmer_name, u.id AS user_id,
    c.name AS crop_name, fc.stage AS crop_stage,
    DATEDIFF(DAY, fc.sown_date, CAST(SYSDATETIME() AS DATE)) AS days_since_sowing,
    c.growth_days AS total_growth_days,
    c.optimal_ph_min, c.optimal_ph_max,
    c.optimal_temp_min, c.optimal_temp_max,
    c.water_req_mm,
    sr.ph, sr.moisture_pct, sr.nitrogen_ppm,
    sr.phosphorus_ppm, sr.potassium_ppm, sr.temperature_c,
    sr.recorded_at AS last_reading_at,
    AVG(s7.moisture_pct) OVER (PARTITION BY f.id) AS avg_moisture_7d,
    AVG(s7.ph)           OVER (PARTITION BY f.id) AS avg_ph_7d,
    (SELECT COUNT(*) FROM alerts a
     WHERE a.field_id = f.id AND a.is_resolved = 0) AS active_alerts
FROM fields f
JOIN farms fa ON fa.id = f.farm_id
JOIN users u  ON u.id  = fa.user_id
LEFT JOIN field_crops fc
    ON fc.field_id = f.id AND fc.stage != 'completed'
LEFT JOIN crops c ON c.id = fc.crop_id
LEFT JOIN soil_readings sr ON sr.id = (
    SELECT TOP 1 id FROM soil_readings
    WHERE field_id = f.id ORDER BY recorded_at DESC
)
LEFT JOIN soil_readings s7
    ON s7.field_id = f.id
    AND s7.recorded_at >= DATEADD(DAY,-7,SYSDATETIME());
GO

CREATE OR ALTER VIEW vw_dashboard_overview AS
SELECT
    f.id AS field_id, f.name AS field_name,
    f.latitude, f.longitude, f.area_hectares,
    fa.id AS farm_id, fa.name AS farm_name, fa.user_id,
    c.name AS crop_name, fc.stage,
    ao.stress_index,
    CASE
        WHEN ao.stress_index IS NULL THEN 'unknown'
        WHEN ao.stress_index < 30   THEN 'healthy'
        WHEN ao.stress_index < 60   THEN 'warning'
        ELSE 'critical'
    END AS health_status,
    (SELECT COUNT(*) FROM alerts a
     WHERE a.field_id = f.id AND a.is_resolved = 0) AS open_alerts,
    sr.moisture_pct, sr.ph, sr.temperature_c,
    sr.recorded_at AS last_reading_at
FROM fields f
JOIN farms fa ON fa.id = f.farm_id
LEFT JOIN field_crops fc
    ON fc.field_id = f.id AND fc.stage != 'completed'
LEFT JOIN crops c ON c.id = fc.crop_id
LEFT JOIN agent_observations ao ON ao.id = (
    SELECT TOP 1 id FROM agent_observations
    WHERE field_id = f.id ORDER BY observed_at DESC
)
LEFT JOIN soil_readings sr ON sr.id = (
    SELECT TOP 1 id FROM soil_readings
    WHERE field_id = f.id ORDER BY recorded_at DESC
);
GO

CREATE OR ALTER VIEW vw_field_trends AS
SELECT
    field_id, recorded_at, moisture_pct, ph, temperature_c,
    AVG(moisture_pct) OVER (
        PARTITION BY field_id ORDER BY recorded_at
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moisture_7d_rolling_avg,
    AVG(ph) OVER (
        PARTITION BY field_id ORDER BY recorded_at
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS ph_7d_rolling_avg,
    LAG(moisture_pct,1) OVER (
        PARTITION BY field_id ORDER BY recorded_at
    ) AS prev_moisture,
    moisture_pct - LAG(moisture_pct,1) OVER (
        PARTITION BY field_id ORDER BY recorded_at
    ) AS moisture_delta,
    RANK() OVER (
        PARTITION BY CAST(recorded_at AS DATE)
        ORDER BY moisture_pct DESC
    ) AS moisture_rank_today
FROM soil_readings;
GO

CREATE OR ALTER VIEW vw_alerts_feed AS
SELECT
    a.id, a.field_id, f.name AS field_name,
    fa.name AS farm_name, fa.user_id,
    a.alert_type, a.severity, a.message,
    a.is_resolved, a.created_at,
    DATEDIFF(HOUR, a.created_at, SYSDATETIME()) AS hours_ago
FROM alerts a
JOIN fields f ON f.id = a.field_id
JOIN farms fa ON fa.id = f.farm_id;
GO

-- Z-score anomaly scoring — pure T-SQL statistics
CREATE OR ALTER VIEW vw_anomaly_scores AS
SELECT
    field_id, recorded_at, moisture_pct, ph, temperature_c,
    AVG(moisture_pct) OVER (PARTITION BY field_id) AS mean_moisture,
    STDEV(moisture_pct) OVER (PARTITION BY field_id) AS stddev_moisture,
    CASE
        WHEN STDEV(moisture_pct) OVER (PARTITION BY field_id) = 0 THEN 0
        ELSE (moisture_pct - AVG(moisture_pct) OVER (PARTITION BY field_id))
             / STDEV(moisture_pct) OVER (PARTITION BY field_id)
    END AS moisture_zscore,
    NTILE(4) OVER (
        PARTITION BY field_id ORDER BY moisture_pct
    ) AS moisture_quartile
FROM soil_readings;
GO

CREATE OR ALTER VIEW vw_regional_benchmark AS
SELECT
    fa.region, c.name AS crop_name,
    COUNT(DISTINCT f.id)          AS field_count,
    ROUND(AVG(sr.moisture_pct),2) AS avg_moisture,
    ROUND(AVG(sr.ph),2)           AS avg_ph,
    ROUND(AVG(ao.stress_index),2) AS avg_stress
FROM fields f
JOIN farms fa ON fa.id = f.farm_id
LEFT JOIN field_crops fc ON fc.field_id = f.id
LEFT JOIN crops c ON c.id = fc.crop_id
LEFT JOIN soil_readings sr
    ON sr.field_id = f.id
    AND sr.recorded_at >= DATEADD(DAY,-30,SYSDATETIME())
LEFT JOIN agent_observations ao
    ON ao.field_id = f.id
    AND ao.observed_at >= DATEADD(DAY,-7,SYSDATETIME())
GROUP BY fa.region, c.name;
GO