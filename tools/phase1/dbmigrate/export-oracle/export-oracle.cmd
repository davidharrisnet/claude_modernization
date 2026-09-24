@echo off
rem export-oracle wrapper: export-oracle <export|selftest|report|all> --target oracle
rem SQL Server LocalDB -> sanitized Oracle schema + data files + source-metadata.json + Word export report.
rem See CLAUDE.md in this folder and ..\..\..\..\docs\phase1\dbmigrate\export-oracle\README.md. Exit codes: 0 ok, 1 selftest differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
