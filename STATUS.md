# Project Status

### September 24, 2026
#### Report
Simplified the database migration to the PostgreSQL path only. Iterations 1-3 (SQLite and MySQL) were removed from the working tree; they remain in git history and the `model-iteration*` branches. Iteration 4 is now `export-postgresql` and iteration 5 is `import-postgresql`, and the prompts to run them are `Run export-postgresql` (Windows) and `Run import-postgresql` (Linux). The documentation was rewritten for the two tools: see [docs/phase1/dbmigrate/DATA_MIGRATION.md](docs/phase1/dbmigrate/DATA_MIGRATION.md).

#### To do
1. **On the Linux machine:** pull, then type `Run import-postgresql.` It regenerates the verification report, the database guide and the results files, which were last generated under the old names (they carry the metadata key rename `iteration` to `tool`, and the report and guide titles).
2. **Review:** check `git status` lists only the expected changes (deleted `iteration1-3` folders, renamed `export-postgresql` and `import-postgresql` folders).
3. **Commit and push.** Claude Code will not commit; that is always my step.
### September 23, 2026
#### Report
Successfully converted the Windows SQL Server database to sanitized schema and data files, which were then ported to a Dockerized PostgreSQL database. 

Learned lessons about data security. Sanitization involved setting the Users table's PasswordHash and SecurityStamp to NULL and introducing a MustResetPassword field set to 1. This will require users to reset their passwords the next time they log in.

See:
* export-postgresql (then iteration 4), the export from SQL Server (Windows): [docs/phase1/dbmigrate/export-postgresql/](docs/phase1/dbmigrate/export-postgresql/) and its report [MigrationExportReport.docx](docs/phase1/dbmigrate/export-postgresql/MigrationExportReport.docx)
* import-postgresql (then iteration 5), the PostgreSQL database in Docker (Linux): [README.md](docs/phase1/dbmigrate/import-postgresql/README.md), [MigrationVerificationReport.html](docs/phase1/dbmigrate/import-postgresql/MigrationVerificationReport.html) (80 of 80 checks, 155 of 155 rows identical) and [PostgreSQLDatabaseGuide.html](docs/phase1/dbmigrate/import-postgresql/PostgreSQLDatabaseGuide.html) (how to connect, including from Spring Boot)

Used Claude to create a Spring Boot 4.1.1 backend (the model layer) in `master-antique-repair-claude/backend/`. It connects to the PostgreSQL database, maps the migrated tables with JPA, and demonstrates the first-login password change every migrated user must make. See [docs/phase2/model/MODEL_PLAN.md](docs/phase2/model/MODEL_PLAN.md).

Also reorganised the repository by phase (`docs/phase1/`, `tools/phase1/`, `docs/phase2/`), regression-tested the database tools after the move, and gave the import tool a `README.md` for people and a `CLAUDE.md` for Claude Code.

#### What's Next
* Phase 2: the controller (REST API), security (Spring Security, real identity check for the first-login password change) and the view (Angular), each with its own plan under `docs/phase2/`.