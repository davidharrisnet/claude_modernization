# Project Status

### September 24, 2026
#### To do (on the Windows machine)
Convert the documentation of iterations 1–4 to the new pattern (already done for iteration 5): each iteration gets a
`README.md` for people in `docs/phase1/dbmigrate/iterationN/` and a `CLAUDE.md` for Claude Code in
`tools/phase1/dbmigrate/iterationN/`, replacing `ITERATIONN.md` and `ITERATIONN_PLAN.md`.

1. **Pull `main`.**
2. **Check the Windows setup:** SQL Server LocalDB with the MasterAntiqueRepair database, and Docker Desktop running
   (iteration 2 needs it).
3. **Open the repository in VS Code with Claude Code and type:**
   ```
   Follow docs/phase1/dbmigrate/DOCS_CONVERSION_PLAN.md
   ```
   Claude Code will:
   - re-run iterations 1, 2 and 4 first, to prove the move to `phase1/` did not break them (expected: 42 of 42
     checks and self-test 6 of 6 for iterations 1 and 2; self-test 9 of 9 for iteration 4);
   - write the new `README.md` and `CLAUDE.md` for iterations 1–4 and delete the old `ITERATIONN*.md` files;
   - delete the finished `SANITIZE_FIRST_REFACTOR.md` and the LibreOffice lock file committed by mistake;
   - fix every link, update `DATA_MIGRATION.md` and `CLAUDE.md`, then delete the plan itself.
4. **If Claude stops because iteration 4's export changed:** iteration 5's input must be refreshed. Copy the three
   files (`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`) from `tools\phase1\dbmigrate\iteration4\`
   into `tools\phase1\dbmigrate\iteration5\input\`, commit, and later on the Linux machine type `Repeat iteration 5.`
5. **Review:** open one or two of the new READMEs, and check `git status` lists only the expected changes.
6. **Commit and push:** `git add -A` (so the moved and deleted files are recorded correctly), commit, push.

Claude Code will not commit; that is always my step.

### September 23, 2026
#### Report
Successfully converted the Windows SQL Server database to sanitized schema and data files, which were then ported to a Dockerized PostgreSQL database. 

Learned lessons about data security. Sanitization involved setting the Users table's PasswordHash and SecurityStamp to NULL and introducing a MustResetPassword field set to 1. This will require users to reset their passwords the next time they log in.

See:
* Iteration 4, the export from SQL Server (Windows): [docs/phase1/dbmigrate/iteration4/](docs/phase1/dbmigrate/iteration4/) and its report [MigrationExportReport4.docx](docs/phase1/dbmigrate/iteration4/MigrationExportReport4.docx)
* Iteration 5, the PostgreSQL database in Docker (Linux): [README.md](docs/phase1/dbmigrate/iteration5/README.md), [MigrationVerificationReport5.html](docs/phase1/dbmigrate/iteration5/MigrationVerificationReport5.html) (80 of 80 checks, 155 of 155 rows identical) and [PostgreSQLDatabaseGuide.html](docs/phase1/dbmigrate/iteration5/PostgreSQLDatabaseGuide.html) (how to connect, including from Spring Boot)

Used Claude to create a Spring Boot 4.1.1 backend (the model layer) in `master-antique-repair-claude/backend/`. It connects to the PostgreSQL database, maps the migrated tables with JPA, and demonstrates the first-login password change every migrated user must make. See [docs/phase2/model/MODEL_PLAN.md](docs/phase2/model/MODEL_PLAN.md).

Also reorganised the repository by phase (`docs/phase1/`, `tools/phase1/`, `docs/phase2/`), regression-tested iterations 3 and 5 after the move, and gave iteration 5 a `README.md` for people and a `CLAUDE.md` for Claude Code.

#### What's Next
* Convert iterations 1–4 to the same `README.md` / `CLAUDE.md` pattern (on the Windows machine; see September 24).
* Phase 2: the controller (REST API), security (Spring Security, real identity check for the first-login password change) and the view (Angular), each with its own plan under `docs/phase2/`.