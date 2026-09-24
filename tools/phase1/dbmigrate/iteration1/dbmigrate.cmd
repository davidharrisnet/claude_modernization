@echo off
rem Database migration wrapper: dbmigrate <export|import|verify|report|all> --target sqlite [options]
rem See CLAUDE.md in this folder and ..\..\..\..\docs\phase1\dbmigrate\iteration1\README.md. Exit codes: 0 ok, 1 verify differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
