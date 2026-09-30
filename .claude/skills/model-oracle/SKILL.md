---
name: model-oracle
description: Runs the Oracle model demonstration (Phase 2 model layer on the migrated Oracle database, model/oracle/ in master-antique-repair-claude, Linux only). Use when the user types /model-oracle or says "Run model-oracle".
---

# /model-oracle

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `Linux` means continue. Anything else (`MINGW*`, `MSYS*`, `CYGWIN*` = Windows,
`Darwin` = macOS) means stop: say "model-oracle runs only on Linux; this machine reports `<output>`" and run nothing.

## Then

The instructions for this demonstration live in the application repo, not here. Before running anything:

1. Read `~/dev/claude_work/master-antique-repair-claude/model/oracle/CLAUDE.md` in full and follow it. It is the single source
   of truth; if it and this file ever disagree, it wins. How the model was built and how to rebuild it:
   `docs/phase2/model/oracle/CLAUDE.md` in this repo.
2. Beyond Linux, it needs import-oracle's `mar-oracle` container and the repo path above. If either is missing, stop and
   say so.
