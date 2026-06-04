USE msdb;
GO

IF EXISTS (SELECT job_id FROM sysjobs WHERE name=N'AgriAI_Nightly_Summary')
    EXEC sp_delete_job @job_name=N'AgriAI_Nightly_Summary';
GO

EXEC sp_add_job @job_name=N'AgriAI_Nightly_Summary';
EXEC sp_add_jobstep
    @job_name=N'AgriAI_Nightly_Summary',
    @step_name=N'Aggregate Daily Summary',
    @subsystem=N'TSQL',
    @database_name=N'agri_ai',
    @command=N'EXEC sp_aggregate_daily_summary
               @summary_date=CAST(DATEADD(DAY,-1,GETDATE()) AS DATE);';
EXEC sp_add_schedule
    @schedule_name=N'AgriAI_Midnight',
    @freq_type=4, @freq_interval=1,
    @active_start_time=000000;
EXEC sp_attach_schedule
    @job_name=N'AgriAI_Nightly_Summary',
    @schedule_name=N'AgriAI_Midnight';
EXEC sp_add_jobserver @job_name=N'AgriAI_Nightly_Summary';
GO