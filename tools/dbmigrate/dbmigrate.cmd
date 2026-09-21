@echo off
rem Database migration wrapper: dbmigrate <export|import|verify|report|all> --target sqlite [options]
rem See ..\..\docs\DMPLAN_1.md, DM1.md, DMPLAN_2.md, DM2.md, DM_MySQL.md and README.md. Exit codes: 0 ok, 1 verify differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
