USE master;
GO
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'agri_ai')
    CREATE DATABASE agri_ai;
GO
USE agri_ai;
GO

CREATE TABLE users (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    uuid          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    full_name     NVARCHAR(120) NOT NULL,
    email         NVARCHAR(255) NOT NULL UNIQUE,
    password_hash NVARCHAR(255) NOT NULL,
    role          NVARCHAR(20)  DEFAULT 'farmer'
                  CHECK (role IN ('farmer','agronomist','admin')),
    is_active     BIT DEFAULT 1,
    created_at    DATETIME2 DEFAULT SYSDATETIME(),
    updated_at    DATETIME2 DEFAULT SYSDATETIME(),
    last_login    DATETIME2 NULL
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_uuid  ON users(uuid);
GO

CREATE TABLE refresh_tokens (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash NVARCHAR(255) NOT NULL UNIQUE,
    expires_at DATETIME2 NOT NULL,
    revoked    BIT DEFAULT 0,
    created_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

CREATE TABLE farms (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       NVARCHAR(120) NOT NULL,
    region     NVARCHAR(100),
    country    NVARCHAR(100) DEFAULT 'India',
    created_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

CREATE TABLE fields (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    farm_id       INT NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    name          NVARCHAR(100) NOT NULL,
    area_hectares DECIMAL(8,2),
    latitude      DECIMAL(10,7),
    longitude     DECIMAL(10,7),
    soil_type     NVARCHAR(20) DEFAULT 'loam'
                  CHECK (soil_type IN ('clay','loam','sandy','silt','peat')),
    created_at    DATETIME2 DEFAULT SYSDATETIME()
);
CREATE INDEX idx_fields_farm ON fields(farm_id);
GO

CREATE TABLE crops (
    id               INT IDENTITY(1,1) PRIMARY KEY,
    name             NVARCHAR(100) NOT NULL,
    variety          NVARCHAR(100),
    season           NVARCHAR(20)
                     CHECK (season IN ('kharif','rabi','zaid','annual')),
    optimal_ph_min   DECIMAL(4,2),
    optimal_ph_max   DECIMAL(4,2),
    optimal_temp_min DECIMAL(5,2),
    optimal_temp_max DECIMAL(5,2),
    water_req_mm     INT,
    growth_days      INT,
    avg_yield_ton_ha DECIMAL(6,2)
);
GO

CREATE TABLE field_crops (
    id           INT IDENTITY(1,1) PRIMARY KEY,
    field_id     INT NOT NULL REFERENCES fields(id),
    crop_id      INT NOT NULL REFERENCES crops(id),
    sown_date    DATE NOT NULL,
    harvest_date DATE NULL,
    stage        NVARCHAR(20) DEFAULT 'sowing'
                 CHECK (stage IN ('sowing','germination','vegetative',
                                  'flowering','fruiting','harvest','completed')),
    actual_yield DECIMAL(8,2) NULL
);
CREATE INDEX idx_field_crops_field ON field_crops(field_id);
GO

CREATE TABLE soil_readings (
    id             BIGINT IDENTITY(1,1) PRIMARY KEY,
    field_id       INT NOT NULL REFERENCES fields(id),
    ph             DECIMAL(4,2),
    moisture_pct   DECIMAL(5,2),
    nitrogen_ppm   DECIMAL(7,2),
    phosphorus_ppm DECIMAL(7,2),
    potassium_ppm  DECIMAL(7,2),
    temperature_c  DECIMAL(5,2),
    recorded_at    DATETIME2 DEFAULT SYSDATETIME(),
    source         NVARCHAR(20) DEFAULT 'manual'
                   CHECK (source IN ('sensor','manual','csv_import'))
);
CREATE INDEX idx_soil_field_time ON soil_readings(field_id, recorded_at);
GO

CREATE TABLE agent_observations (
    id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    field_id      INT NOT NULL REFERENCES fields(id),
    stress_index  DECIMAL(5,2),
    anomaly_flags NVARCHAR(MAX) NULL,
    observation   NVARCHAR(MAX),
    observed_at   DATETIME2 DEFAULT SYSDATETIME()
);
CREATE INDEX idx_obs_field ON agent_observations(field_id);
GO

CREATE TABLE agent_memory (
    id                 BIGINT IDENTITY(1,1) PRIMARY KEY,
    field_id           INT NOT NULL REFERENCES fields(id),
    memory_type        NVARCHAR(30)
                       CHECK (memory_type IN ('soil_pattern','yield_correlation',
                                              'anomaly_history','weather_pattern')),
    content            NVARCHAR(MAX) NOT NULL,
    confidence_score   DECIMAL(4,3)  DEFAULT 1.000,
    created_at         DATETIME2 DEFAULT SYSDATETIME(),
    last_reinforced_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

CREATE TABLE alerts (
    id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    field_id    INT NOT NULL REFERENCES fields(id),
    alert_type  NVARCHAR(30) NOT NULL
                CHECK (alert_type IN ('moisture_low','moisture_high','ph_anomaly',
                                      'temperature_spike','nutrient_deficiency',
                                      'agent_advisory')),
    severity    NVARCHAR(10) DEFAULT 'medium'
                CHECK (severity IN ('low','medium','high','critical')),
    message     NVARCHAR(MAX),
    is_resolved BIT DEFAULT 0,
    created_at  DATETIME2 DEFAULT SYSDATETIME()
);
CREATE INDEX idx_alerts_field ON alerts(field_id, is_resolved);
GO

CREATE TABLE csv_imports (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    user_id       INT NOT NULL REFERENCES users(id),
    filename      NVARCHAR(255),
    rows_imported INT DEFAULT 0,
    status        NVARCHAR(10) DEFAULT 'pending'
                  CHECK (status IN ('pending','success','failed')),
    error_log     NVARCHAR(MAX),
    imported_at   DATETIME2 DEFAULT SYSDATETIME()
);
GO

CREATE TABLE daily_summaries (
    id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    field_id     INT NOT NULL REFERENCES fields(id),
    summary_date DATE NOT NULL,
    avg_moisture DECIMAL(5,2),
    avg_ph       DECIMAL(4,2),
    avg_temp     DECIMAL(5,2),
    stress_score DECIMAL(5,2),
    alert_count  INT DEFAULT 0,
    CONSTRAINT uq_field_date UNIQUE (field_id, summary_date)
);
GO

-- NL→SQL query audit log
CREATE TABLE nl_query_log (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id         INT NOT NULL REFERENCES users(id),
    natural_query   NVARCHAR(MAX) NOT NULL,
    generated_sql   NVARCHAR(MAX),
    executed        BIT DEFAULT 0,
    result_rows     INT DEFAULT 0,
    error_message   NVARCHAR(MAX) NULL,
    created_at      DATETIME2 DEFAULT SYSDATETIME()
);
GO