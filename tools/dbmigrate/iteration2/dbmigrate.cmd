@echo off
rem Database migration wrapper (iteration 2): dbmigrate <export|import|verify|selftest|report|guide|all> --target sqlite-linux [options]
rem See ..\..\..\docs\dbmigrate\iteration2\ITERATION2.md and ITERATION2_PLAN.md. Exit codes: 0 ok, 1 verify differences, 2 error, 3 refused.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migration\DbMigrate.ps1" %*
exit /b %ERRORLEVEL%
