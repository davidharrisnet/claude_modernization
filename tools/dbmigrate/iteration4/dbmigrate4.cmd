@echo off
rem Iteration 4 export wrapper: dbmigrate4 <export|selftest|report|all> --target postgres
rem SQL Server LocalDB -> sanitized PostgreSQL schema + data files + source-metadata.json + Word export report.
rem See ..\..\..\docs\dbmigrate\iteration4\ITERATION4_PLAN.md. Exit codes: 0 ok, 1 selftest differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
