USE agri_ai;
GO

INSERT INTO crops (name,variety,season,optimal_ph_min,optimal_ph_max,
    optimal_temp_min,optimal_temp_max,water_req_mm,growth_days,avg_yield_ton_ha)
VALUES
    (N'Rice',     N'Sona Masuri',N'kharif',5.5,6.5,25,35,1200,120,4.5),
    (N'Wheat',    N'HD-2967',    N'rabi',  6.0,7.0,15,25,450, 120,3.8),
    (N'Sugarcane',N'Co-86032',   N'annual',6.0,7.5,25,35,1500,360,70.0),
    (N'Cotton',   N'Bt Cotton',  N'kharif',5.8,7.0,25,35,700, 180,1.8),
    (N'Maize',    N'DHM-117',    N'kharif',5.8,7.0,20,30,600, 90, 5.5),
    (N'Tomato',   N'Hybrid',     N'zaid',  6.0,7.0,20,30,400, 90, 25.0);

-- Demo user password: demo123
INSERT INTO users (full_name,email,password_hash,role)
VALUES (N'Demo Farmer',N'demo@agriai.com',
    N'$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMqJqhcanFp8.AQOU.Um.zj5C2',N'farmer');

INSERT INTO farms (user_id,name,region)
VALUES (1,N'Demo Farm',N'Tamil Nadu');

INSERT INTO fields (farm_id,name,area_hectares,latitude,longitude,soil_type)
VALUES
    (1,N'North Field',2.5,13.0827,80.2707,N'loam'),
    (1,N'South Field',1.8,13.0750,80.2650,N'clay'),
    (1,N'East Field', 3.2,13.0900,80.2800,N'sandy');

INSERT INTO field_crops (field_id,crop_id,sown_date,stage)
VALUES (1,1,'2024-06-01',N'vegetative'),
       (2,2,'2024-11-01',N'flowering'),
       (3,5,'2024-06-15',N'germination');

INSERT INTO soil_readings
    (field_id,ph,moisture_pct,nitrogen_ppm,phosphorus_ppm,potassium_ppm,temperature_c,source)
VALUES
    (1,6.2,42.0,180,90,210,29.5,N'manual'),
    (1,6.1,35.0,175,88,205,31.0,N'manual'),
    (1,5.9,18.0,170,85,200,34.0,N'manual'),
    (2,7.2,65.0,200,95,220,26.0,N'manual'),
    (2,7.0,58.0,195,92,215,27.5,N'manual'),
    (3,6.5,45.0,160,80,190,28.0,N'manual'),
    (3,6.3,38.0,155,78,185,30.0,N'manual');
GO