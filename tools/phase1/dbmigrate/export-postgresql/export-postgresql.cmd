@echo off
rem export-postgresql wrapper: export-postgresql <export|selftest|report|all> --target postgres
rem SQL Server LocalDB -> sanitized PostgreSQL schema + data files + source-metadata.json + Word export report.
rem See CLAUDE.md in this folder and ..\..\..\..\docs\phase1\dbmigrate\export-postgresql\README.md. Exit codes: 0 ok, 1 selftest differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
