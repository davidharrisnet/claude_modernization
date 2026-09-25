# Project Status

### September 25, 2026
#### Weekly Report
Several Iteration lead to the current state
* **Iteration 1 (21 Sep), SQLite on Windows.** The first end-to-end migration: export from SQL Server LocalDB, build a SQLite database, verify it is identical to the source, and write a report.
* **Iteration 2 (21 Sep), SQLite in Docker on Linux.** The same migration, with the new database created and checked inside a Linux container. Dockerizing the database was the decision that made everything after it repeatable: a disposable, verifiable target that needs nothing installed but Docker.
* **Iteration 3 (22 Sep), an independently verified image built entirely on Linux.** Review caught two real problems: the verifier trusted results inherited from earlier iterations, and real password hashes had been committed to git. The fix was to sanitize first: the export now nulls `PasswordHash` and `SecurityStamp` and sets `MustResetPassword`, so every migrated user resets their password on first login. This became a rule for every later tool.
* **Iteration 4 (23 Sep), export for PostgreSQL.** The upgrade from SQLite to a database that could be the real target. It became `export-postgresql`.
* **Iteration 5 (23 Sep), PostgreSQL in Docker.** It became `import-postgresql`. Its database guide (how to connect, including from Spring Boot) seeded the plan for the Phase 2 model.
* **Oracle (24 Sep).** Phase 2 explicitly lists Oracle, so the same pair was built for it: `export-oracle` and `import-oracle`, targeting Oracle AI Database 26ai Free. Every Oracle detail that could not be tested on Windows was confirmed on Linux without changing the export.

#### Phase 1
Current State (main)
**The database migration is done, for two targets.**

| Tool | Runs on | Result |
|---|---|---|
| `export-postgresql` | Windows | Sanitized PostgreSQL schema and data from SQL Server |
| `import-postgresql` | Linux | 80 of 80 checks, 155 of 155 rows identical, self-test 7 of 7 |
| `export-oracle` | Windows | Sanitized Oracle files, self-test 13 of 13, row fingerprints equal to the PostgreSQL export's |
| `import-oracle` | Linux | 86 of 86 checks, 155 of 155 rows identical, self-test 7 of 7 |

#### Phase 2
**The Phase 2 model has started.** In [master-antique-repair-modern](https://github.com/davidharrisnet/master-antique-repair-modern)

* 'Run model-oracle' and 'Run model-postresql' 
The claude commands build out the spring-boot architecture that demostrates a user login into the database and changing their password. 

### September 24, 2026
#### Report
Simplified the database migration to the PostgreSQL path only. Iterations 1-3 (SQLite and MySQL) were removed from the working tree; they remain in git history and the `model-iteration*` branches. Iteration 4 is now `export-postgresql` and iteration 5 is `import-postgresql`, and the prompts to run them are `Run export-postgresql` (Windows) and `Run import-postgresql` (Linux). The documentation was rewritten for the two tools: see [docs/phase1/dbmigrate/DATA_MIGRATION.md](docs/phase1/dbmigrate/DATA_MIGRATION.md).

Then added an Oracle proof of concept alongside PostgreSQL (Phase 2 stays on PostgreSQL). `export-oracle` is built and passes its self-test (13 of 13): it produces sanitized Oracle AI Database 26ai files whose row fingerprints equal the PostgreSQL export's. `import-oracle` was then built on the Linux machine: it loads those files unchanged into Oracle AI Database 26ai Free in Docker and verifies them, 86 of 86 checks and 155 of 155 rows identical, self-test 7 of 7 ([MigrationVerificationReport.html](docs/phase1/dbmigrate/import-oracle/MigrationVerificationReport.html)). Every Oracle detail export-oracle could not test on Windows was confirmed; no correction to `export-oracle` was needed. See [DATA_MIGRATION.md](docs/phase1/dbmigrate/DATA_MIGRATION.md) section 10.

#### What's Next

1. Generalize the database export. This worked for the AntiqueRepair demo, but can it work for another database? 
1. Controller -- move on to creating REST access points

### September 23, 2026
#### Report
Successfully converted the Windows SQL Server database to sanitized schema and data files, which were then ported to a Dockerized PostgreSQL database. 

Learned lessons about data security. Sanitization involved setting the Users table's PasswordHash and SecurityStamp to NULL and introducing a MustResetPassword field set to 1. This will require users to reset their passwords the next time they log in.

See:
* export-postgresql (then iteration 4), the export from SQL Server (Windows): [docs/phase1/dbmigrate/export-postgresql/](docs/phase1/dbmigrate/export-postgresql/) and its report [MigrationExportReport.docx](docs/phase1/dbmigrate/export-postgresql/MigrationExportReport.docx)
* import-postgresql (then iteration 5), the PostgreSQL database in Docker (Linux): [README.md](docs/phase1/dbmigrate/import-postgresql/README.md), [MigrationVerificationReport.html](docs/phase1/dbmigrate/import-postgresql/MigrationVerificationReport.html) (80 of 80 checks, 155 of 155 rows identical) and [PostgreSQLDatabaseGuide.html](docs/phase1/dbmigrate/import-postgresql/PostgreSQLDatabaseGuide.html) (how to connect, including from Spring Boot)

Used Claude to create the Spring Boot 4.1.1 model layer in `master-antique-repair-claude/model/postgresql/`. It connects to the PostgreSQL database, maps the migrated tables with JPA, and demonstrates the first-login password change every migrated user must make. See [docs/phase2/model/postgresql/CLAUDE.md](docs/phase2/model/postgresql/CLAUDE.md).

Also reorganised the repository by phase (`docs/phase1/`, `tools/phase1/`, `docs/phase2/`), regression-tested the database tools after the move, and gave the import tool a `README.md` for people and a `CLAUDE.md` for Claude Code.

#### What's Next
* Phase 2: the controller (REST API), security (Spring Security, real identity check for the first-login password change) and the view (Angular), each with its own plan under `docs/phase2/`.