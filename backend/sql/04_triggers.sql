USE agri_ai;
GO

CREATE OR ALTER TRIGGER trg_soil_anomaly
ON soil_readings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @field_id INT, @ph DECIMAL(4,2),
            @moisture DECIMAL(5,2), @temp DECIMAL(5,2),
            @prev_moisture DECIMAL(5,2);

    SELECT @field_id=field_id, @ph=ph,
           @moisture=moisture_pct, @temp=temperature_c
    FROM inserted;

    SELECT TOP 1 @prev_moisture=moisture_pct
    FROM soil_readings
    WHERE field_id=@field_id
      AND id NOT IN (SELECT id FROM inserted)
    ORDER BY recorded_at DESC;

    IF @moisture IS NOT NULL AND @moisture < 20
        INSERT INTO alerts (field_id,alert_type,severity,message)
        VALUES (@field_id,'moisture_low','critical',
            CONCAT(N'Moisture critically low: ',@moisture,N'%. Irrigation needed.'));

    IF @ph IS NOT NULL AND (@ph < 5.0 OR @ph > 8.5)
        INSERT INTO alerts (field_id,alert_type,severity,message)
        VALUES (@field_id,'ph_anomaly',
            CASE WHEN @ph<4.0 OR @ph>9.0 THEN 'critical' ELSE 'high' END,
            CONCAT(N'pH out of safe range: ',@ph));

    IF @prev_moisture IS NOT NULL AND @moisture IS NOT NULL
       AND (@prev_moisture-@moisture) > 15
        INSERT INTO alerts (field_id,alert_type,severity,message)
        VALUES (@field_id,'moisture_low','high',
            CONCAT(N'Rapid moisture drop: ',@prev_moisture,N'% → ',@moisture,N'%'));

    IF @temp IS NOT NULL AND @temp > 42
        INSERT INTO alerts (field_id,alert_type,severity,message)
        VALUES (@field_id,'temperature_spike','high',
            CONCAT(N'High temperature: ',@temp,N'C'));

    EXEC sp_compute_stress_index @field_id;
END;
GO