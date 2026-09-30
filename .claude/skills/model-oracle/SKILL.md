---
name: model-oracle
description: Runs the Oracle model demonstration (Phase 2 model layer on the migrated Oracle database, model/oracle/ in master-antique-repair-claude, Linux only). Use when the user types /model-oracle or says "Run model-oracle".
---

# /model-oracle

The instructions for this demonstration live in the application repo, not here. Before running anything:

1. Read `~/dev/claude_work/master-antique-repair-claude/model/oracle/CLAUDE.md` in full and follow it. It is the single source
   of truth; if it and this file ever disagree, it wins. How the model was built and how to rebuild it:
   `docs/phase2/model/oracle/CLAUDE.md` in this repo.
2. Check the machine first: it runs on the Linux machine and needs import-oracle's `mar-oracle` container. If that repo path
   does not exist here (for example on Windows), stop and say so.
