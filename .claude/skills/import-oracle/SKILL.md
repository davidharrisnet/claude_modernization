---
name: import-oracle
description: Runs or changes the import-oracle tool (Linux + Docker only) - loads export-oracle's three files into the mar-oracle container, verifies them against source-metadata.json, runs the self-test and writes the verification report. Use when the user types /import-oracle or says "Run import-oracle", or asks to change that tool.
argument-hint: "[load|verify|selftest|report|all] [--recreate]"
---

# /import-oracle

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `Linux` means continue. Anything else (`MINGW*`, `MSYS*`, `CYGWIN*` = Windows,
`Darwin` = macOS) means stop: say "import-oracle runs only on Linux; this machine reports `<output>`" and run nothing.
Changing the tool's files (not running it) is allowed on any OS.

## Then

The instructions for this tool live with the tool, not here. Before running or changing anything:

1. Read `tools/phase1/dbmigrate/import-oracle/CLAUDE.md` in full and follow it. It is the single source of truth (rules,
   commands, exit codes, input contract, gotchas); if it and this file ever disagree, it wins.
2. Beyond Linux, import-oracle needs Docker (`ingest.sh`, `sqlplus` inside the container). If `docker info` fails, stop
   and say so.
3. If arguments were given (`load`, `verify`, `selftest`, `report` or `all`, optionally `--recreate`), run that; otherwise do
   what the tool's CLAUDE.md says a plain `Run import-oracle` means.

Report the exit code with the meaning the tool's CLAUDE.md gives it. Never edit `input/` by hand and
never fix export-side SQL here: a load or hash failure caused by the export is named and sent back to export-oracle.
