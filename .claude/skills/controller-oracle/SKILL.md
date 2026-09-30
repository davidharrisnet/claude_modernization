---
name: controller-oracle
description: Runs the Oracle controller demonstration (Phase 2 REST API with Swagger UI over a copy of the migrated Oracle database, model/oracle/ in the Phase 2 repo, Linux only) - build, unit tests, database copy mar-oracle-controller, smoke test. Use when the user types /controller-oracle or says "Run controller-oracle".
---

# /controller-oracle

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `Linux` means continue. Anything else (`MINGW*`, `MSYS*`, `CYGWIN*` = Windows,
`Darwin` = macOS) means stop: say "controller-oracle runs only on Linux; this machine reports `<output>`" and run nothing.

## Then

The instructions for this demonstration live with the plan, not here. Before running anything:

1. Read `~/dev/claude_work/claude_modernization/docs/phase2/controller/oracle/CLAUDE.md` in full and follow its section 6
   (`Run controller-oracle`). Once the code exists, `model/oracle/CLAUDE.md` in the Phase 2 repo carries the same section;
   if the two disagree, the code's copy wins. Which endpoints exist is set by `docs/phase2/controller/CONTROLLER.md` (the
   contract); where the plan differs from it, the contract wins - report the difference.
2. Beyond Linux, it needs Java 21, Docker, import-oracle's input files and the Phase 2 repo. If any is missing, stop and
   say so.
3. This skill runs the demonstration; it does not build the API. If the controller code is not there yet, stop and say
   so - implementing it is the `controller` agent's job.

Never write to `mar-oracle`; the run uses its own copy `mar-oracle-controller`. Report the build/test results and smoke-test
numbers you actually got, with failures quoted.
