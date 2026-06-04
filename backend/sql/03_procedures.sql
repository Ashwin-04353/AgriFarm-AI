USE agri_ai;
GO

CREATE OR ALTER PROCEDURE sp_compute_stress_index
    @field_id INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ph DECIMAL(4,2), @moisture DECIMAL(5,2), @temp DECIMAL(5,2),
            @ph_min DECIMAL(4,2)=6.0, @ph_max DECIMAL(4,2)=7.0,
            @t_min DECIMAL(5,2)=20.0, @t_max DECIMAL(5,2)=35.0,
            @ph_s DECIMAL(5,2)=0, @m_s DECIMAL(5,2)=0,
            @t_s DECIMAL(5,2)=0, @stress DECIMAL(5,2)=0;

    SELECT TOP 1
        @ph=sr.ph, @moisture=sr.moisture_pct, @temp=sr.temperature_c,
        @ph_min=COALESCE(c.optimal_ph_min,6.0),
        @ph_max=COALESCE(c.optimal_ph_max,7.0),
        @t_min=COALESCE(c.optimal_temp_min,20.0),
        @t_max=COALESCE(c.optimal_temp_max,35.0)
    FROM soil_readings sr
    LEFT JOIN field_crops fc
        ON fc.field_id=sr.field_id AND fc.stage!='completed'
    LEFT JOIN crops c ON c.id=fc.crop_id
    WHERE sr.field_id=@field_id
    ORDER BY sr.recorded_at DESC;

    IF @ph IS NOT NULL
        SET @ph_s = CASE WHEN ABS(@ph-(@ph_min+@ph_max)/2)*20 < 40
                         THEN ABS(@ph-(@ph_min+@ph_max)/2)*20 ELSE 40 END;
    IF @moisture IS NOT NULL
        SET @m_s = CASE WHEN (100-@moisture)*0.4 < 40
                        THEN (100-@moisture)*0.4 ELSE 40 END;
    IF @temp IS NOT NULL
        SET @t_s = CASE WHEN ABS(@temp-(@t_min+@t_max)/2)*2 < 20
                        THEN ABS(@temp-(@t_min+@t_max)/2)*2 ELSE 20 END;

    SET @stress = CASE WHEN @ph_s+@m_s+@t_s < 100
                       THEN @ph_s+@m_s+@t_s ELSE 100 END;

    INSERT INTO agent_observations (field_id, stress_index, observation)
    VALUES (@field_id, @stress,
        CONCAT(N'pH:',@ph,N' moisture:',@moisture,N'% temp:',@temp,N'C'));
END;
GO

CREATE OR ALTER PROCEDURE sp_optimize_irrigation
    @farm_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        f.id AS field_id, f.name AS field_name,
        c.name AS crop_name, ao.stress_index,
        c.water_req_mm,
        RANK() OVER (ORDER BY ao.stress_index DESC) AS irrigation_priority,
        CASE
            WHEN ao.stress_index > 70 THEN 'irrigate_today'
            WHEN ao.stress_index > 40 THEN 'irrigate_in_2_days'
            ELSE 'monitor'
        END AS recommended_action
    FROM fields f
    LEFT JOIN field_crops fc
        ON fc.field_id=f.id AND fc.stage!='completed'
    LEFT JOIN crops c ON c.id=fc.crop_id
    LEFT JOIN agent_observations ao ON ao.id=(
        SELECT TOP 1 id FROM agent_observations
        WHERE field_id=f.id ORDER BY observed_at DESC
    )
    WHERE f.farm_id=@farm_id;
END;
GO

-- Pure T-SQL Z-score anomaly classification
CREATE OR ALTER PROCEDURE sp_classify_anomalies
    @field_id INT
AS
BEGIN
    SET NOCOUNT ON;
    WITH stats AS (
        SELECT field_id,
               AVG(moisture_pct)   AS mean_m,
               STDEV(moisture_pct) AS std_m,
               AVG(ph)             AS mean_ph,
               STDEV(ph)           AS std_ph
        FROM soil_readings
        WHERE field_id=@field_id
        GROUP BY field_id
    )
    SELECT
        sr.id, sr.recorded_at, sr.moisture_pct, sr.ph,
        CASE
            WHEN s.std_m>0 AND ABS(sr.moisture_pct-s.mean_m)/s.std_m>2 THEN 'anomaly'
            WHEN s.std_m>0 AND ABS(sr.moisture_pct-s.mean_m)/s.std_m>1 THEN 'suspect'
            ELSE 'normal'
        END AS moisture_status,
        CASE
            WHEN s.std_ph>0 AND ABS(sr.ph-s.mean_ph)/s.std_ph>2 THEN 'anomaly'
            WHEN s.std_ph>0 AND ABS(sr.ph-s.mean_ph)/s.std_ph>1 THEN 'suspect'
            ELSE 'normal'
        END AS ph_status,
        ROUND(CASE WHEN s.std_m>0
              THEN (sr.moisture_pct-s.mean_m)/s.std_m ELSE 0 END, 3) AS zscore
    FROM soil_readings sr
    CROSS JOIN stats s
    WHERE sr.field_id=@field_id
    ORDER BY sr.recorded_at DESC;
END;
GO

-- Recursive CTE crop rotation advisor
CREATE OR ALTER PROCEDURE sp_crop_rotation_advisor
    @field_id INT
AS
BEGIN
    SET NOCOUNT ON;
    WITH rotation_history AS (
        SELECT fc.field_id, c.name AS crop_name, c.season,
               fc.sown_date,
               ROW_NUMBER() OVER (
                   PARTITION BY fc.field_id ORDER BY fc.sown_date DESC
               ) AS season_rank
        FROM field_crops fc
        JOIN crops c ON c.id=fc.crop_id
        WHERE fc.field_id=@field_id
    ),
    depletion_chain AS (
        SELECT crop_name, season, sown_date, season_rank,
               CAST(crop_name AS NVARCHAR(MAX)) AS crop_path, 1 AS depth
        FROM rotation_history WHERE season_rank=1
        UNION ALL
        SELECT r.crop_name, r.season, r.sown_date, r.season_rank,
               CAST(dc.crop_path+N' → '+r.crop_name AS NVARCHAR(MAX)),
               dc.depth+1
        FROM rotation_history r
        INNER JOIN depletion_chain dc ON r.season_rank=dc.depth+1
        WHERE dc.depth<4
    )
    SELECT
        MAX(crop_path) AS rotation_history,
        MAX(depth)     AS seasons_tracked,
        CASE MAX(CASE WHEN season_rank=1 THEN crop_name END)
            WHEN 'Rice'     THEN 'Wheat or Mustard — nitrogen restoration'
            WHEN 'Wheat'    THEN 'Sugarcane or Maize — soil recovery'
            WHEN 'Maize'    THEN 'Soybean or Groundnut — legume nitrogen fix'
            WHEN 'Cotton'   THEN 'Wheat or Chickpea — soil rest'
            ELSE 'Legume crop recommended for soil recovery'
        END AS next_crop_recommendation
    FROM depletion_chain;
END;
GO

-- MERGE-based nightly summary
CREATE OR ALTER PROCEDURE sp_aggregate_daily_summary
    @summary_date DATE
AS
BEGIN
    SET NOCOUNT ON;
    MERGE daily_summaries AS target
    USING (
        SELECT sr.field_id, @summary_date AS summary_date,
               ROUND(AVG(sr.moisture_pct),2) AS avg_moisture,
               ROUND(AVG(sr.ph),2)           AS avg_ph,
               ROUND(AVG(sr.temperature_c),2) AS avg_temp,
               COALESCE((
                   SELECT TOP 1 stress_index FROM agent_observations
                   WHERE field_id=sr.field_id ORDER BY observed_at DESC
               ),0) AS stress_score,
               (SELECT COUNT(*) FROM alerts a
                WHERE a.field_id=sr.field_id
                  AND CAST(a.created_at AS DATE)=@summary_date) AS alert_count
        FROM soil_readings sr
        WHERE CAST(sr.recorded_at AS DATE)=@summary_date
        GROUP BY sr.field_id
    ) AS source
    ON target.field_id=source.field_id
       AND target.summary_date=source.summary_date
    WHEN MATCHED THEN UPDATE SET
        avg_moisture=source.avg_moisture, avg_ph=source.avg_ph,
        avg_temp=source.avg_temp, stress_score=source.stress_score,
        alert_count=source.alert_count
    WHEN NOT MATCHED THEN INSERT
        (field_id,summary_date,avg_moisture,avg_ph,avg_temp,stress_score,alert_count)
    VALUES
        (source.field_id,source.summary_date,source.avg_moisture,
         source.avg_ph,source.avg_temp,source.stress_score,source.alert_count);
END;
GO