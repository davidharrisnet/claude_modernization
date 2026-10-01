---
name: import-controller
description: Runs the Oracle controller demonstration (Phase 2 REST API with Swagger UI on the migrated Oracle database mar-oracle, model/oracle/ in the Phase 2 repo, Linux only) - build, unit tests, smoke test. The Linux half of /export-controller. Use when the user types /import-controller or says "Run import-controller".
---

# /import-controller

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `Linux` means continue. Anything else (`MINGW*`, `MSYS*`, `CYGWIN*` = Windows,
`Darwin` = macOS) means stop: say "import-controller runs only on Linux; this machine reports `<output>`" and run nothing.

## Then

The instructions for this demonstration live with the plan, not here. Before running anything:

1. Read `~/dev/claude_work/claude_modernization/docs/phase2/controller/oracle/CLAUDE.md` in full and follow its section 6
   (`Run import-controller`). Once the code exists, `model/oracle/CLAUDE.md` in the Phase 2 repo carries the same section;
   if the two disagree, the code's copy wins. Which endpoints exist is set by `docs/phase2/controller/CONTROLLER.md` (the
   contract); where the plan differs from it, the contract wins - report the difference.
2. Beyond Linux, it needs Java 21, Docker, the Phase 2 repo and a freshly loaded, verified `mar-oracle` (built by
   `/import-oracle`). If any is missing, stop and say so.
3. This skill runs the demonstration; it does not build the API. If the controller code is not there yet, stop and say
   so - implementing it is the `controller` agent's job.

The run uses the one database, `mar-oracle`, and its smoke test writes to it: afterwards `mar-oracle` no longer matches the
export, and `/import-oracle all --recreate` restores it. Report the build/test results and smoke-test numbers you actually
got, with failures quoted.
