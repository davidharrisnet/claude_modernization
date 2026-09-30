---
name: export-oracle
description: Runs or changes the export-oracle tool (Windows only) - SQL Server LocalDB to sanitized Oracle 01-schema.sql, 02-data-sanitized.sql and source-metadata.json plus a Word export report. Use when the user types /export-oracle or says "Run export-oracle", or asks to change that tool.
argument-hint: "[export|selftest|report|all]"
---

# /export-oracle

The instructions for this tool live with the tool, not here. Before running or changing anything:

1. Read `tools/phase1/dbmigrate/export-oracle/CLAUDE.md` in full and follow it. It is the single source of truth (rules,
   commands, exit codes, input contracts, the hand-off to import-oracle); if it and this file ever disagree, it wins.
2. Check the machine first: export-oracle needs Windows, a live SQL Server LocalDB and Windows PowerShell 5.1. On Linux, stop
   and say so; do not try to emulate the export.
3. If an argument was given (`export`, `selftest`, `report` or `all`), run that step; otherwise do what the tool's CLAUDE.md
   says a plain `Run export-oracle` means.

Report the exit code with the meaning the tool's CLAUDE.md gives it. The refusal to export unsanitized data is the safeguard
working: report it, never work around it.
