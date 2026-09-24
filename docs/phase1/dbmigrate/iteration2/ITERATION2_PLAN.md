# Plan: Iteration 2 - SQL Server to a SQLite database that lives only in a Docker Linux container

The plan and design for iteration 2. What actually happened, with the results, is recorded in [ITERATION2.md](ITERATION2.md); the detailed verification evidence is `MigrationVerificationReport2.docx` and the operating instructions are `SQLiteDatabaseGuide2.docx` (both in this folder). The iteration 1 plan is [ITERATION1_PLAN.md](../iteration1/ITERATION1_PLAN.md) (record: [ITERATION1.md](../iteration1/ITERATION1.md)).

## Context

Rule: every iteration must
1. **export** the data from the MasterAntiqueRepair database,
2. **populate** it into a **new database**,
3. **verify** the data is identical, and
4. **write** `MigrationVerificationReport{N}.docx`, N = the iteration number.

| Iteration | What | Report |
|---|---|---|
| 1 | SQL Server -> SQLite, native on Windows (done) | `MigrationVerificationReport1.docx` |
| **2** | **SQL Server -> SQLite created, checked and kept inside a Docker Linux container (this plan)** | `MigrationVerificationReport2.docx` |
| 3 | SQL Server -> PostgreSQL in Docker (later) | `MigrationVerificationReport3.docx` |

MySQL in Docker was built earlier as extra work and is not a numbered iteration.

**Why iteration 2 exists.** The goal is to move the ASP.NET application to Linux. Iteration 1 proved the migration on Windows with the Windows SQLite build. Iteration 2 builds the new database with the **Linux** SQLite build, inside a container, and **never copies the database to Windows**. All interaction with the database (loading, verification queries, rule tests, comparison, inspection) is done in the container.

## Where Linux takes over

| Stage | Runs on | Why |
|---|---|---|
| Export from SQL Server | **Windows** | The source is SQL Server LocalDB, which exists only on Windows; the tooling is Windows PowerShell 5.1 (`System.Data.SqlClient`, `System.Drawing`, `dbmigrate.cmd`). |
| Handoff: `01-schema.sql`, `02-data.sql` | text files | Plain SQLite SQL (UTF-8 without BOM, LF). The only artifacts that cross from Windows to Linux. |
| Load, integrity checks, queries, rule tests, `sqldiff`, the database file itself | **Linux container** | Needs only `sqlite3` and `sqldiff`. |
| Verification orchestration, results JSON, Word report and guide | Windows | Compares against the live SQL Server source; reads the database only through `docker exec`. |

Running the whole tool on Linux is not supported (LocalDB, Windows-only .NET types). A future step could make import and verify Windows-free after the export: the export would also write a manifest (row counts, a SHA-256 per table, the schema description) and Linux scripts using `sqlite3` and `sha256sum` would recompute and compare. That is not part of this iteration; `SQLiteDatabaseGuide2.docx` section 9 shows how to load the exported files into a Linux SQLite by hand.

## Layout

```
tools/phase1/dbmigrate/iteration2/
  dbmigrate.cmd                 wrapper: dbmigrate <export|import|verify|selftest|report|guide|all> --target sqlite-linux
  migration/                    DbMigrate.ps1, Common.ps1, Export/Import/Verify/SelfTest/Report/Guide.ps1,
                                dialects/sqlite.ps1, migration.config.json
  01-schema.sql, 02-data.sql, import-log.txt,
  verification-results.json, selftest-results.json      (outputs; gitignored: the data file holds password hashes)
docs/phase1/dbmigrate/iteration2/
  ITERATION2_PLAN.md, ITERATION2.md, MigrationVerificationReport2.docx, SQLiteDatabaseGuide2.docx
```

Nothing is written anywhere else, and **no database file is written on Windows**. The database exists only at `/data/masterantique.sqlite` inside the container `mar-sqlite`.

## Design

### 1. Report name follows the iteration
Optional keys per target in `migration.config.json`: `iteration`, `iterationTitle`, `outputSubdir`, `reportDir`, `guideFile`. The report is written as `MigrationVerificationReport{iteration}.docx`; the results JSON records `Iteration` and `IterationTitle`, and the Word title page and header say "Iteration N".

### 2. The `sqlite-linux` target
```
"sqlite-linux": {
  "dialect": "sqlite", "iteration": 2, "iterationTitle": "SQLite in a Dockerized Linux container",
  "outputSubdir": "iteration2", "reportDir": "docs/phase1/dbmigrate/iteration2", "guideFile": "SQLiteDatabaseGuide2.docx",
  "runner": { "mode": "docker", "container": "mar-sqlite", "image": "alpine:3.20", "autoStart": true },
  "file": "/data/masterantique.sqlite" }
```
- The container `mar-sqlite` is created on first use from the stock `alpine:3.20` image: `docker run -d --name mar-sqlite alpine:3.20 sh -c "apk add --no-cache sqlite sqlite-tools && mkdir -p /data && exec tail -f /dev/null"`. The tool waits until `sqlite3`, `sqldiff` and `/data` exist. **No custom image is built.**
- The database file lives in the container's own file system (`/data`), not on a Windows bind mount, so the test exercises Linux file semantics. There is no `docker cp` of the database, no volume and no published port.
- The client runs through `docker exec -i`; SQL is piped in as UTF-8.

### 3. The SQLite dialect is runner-aware
`migration\dialects\sqlite.ps1` supports two runners, `local` (`sqlite3.exe`, as in iteration 1) and `docker`. In docker mode the client, existence check, fingerprint (`sha256sum`), import (`rm -f` only with `--recreate`, `mkdir -p`, load, integrity checks), scratch copies for the rule tests (`cp`/`rm -f` under `/data`) and the independent comparison (`sqldiff`) all run in the container. The dialect's display name is "SQLite (Linux container)". The shared code (export, verify, self-test, report) goes through the dialect interface.

### 4. The four steps in one command
`tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux [--recreate]`
1. **Export** from the source database -> `01-schema.sql`, `02-data.sql` (Windows).
2. **Populate a new database** in the Linux container (`/data/masterantique.sqlite`, created by Linux `sqlite3`). It stays there.
3. **Verify identical:** the same 41 checks as iteration 1 plus the self-test (repeatable export, in-container `sqldiff`, damaged-copy detection).
4. **Report and guide:** `docs\phase1\dbmigrate\iteration2\MigrationVerificationReport2.docx` and `SQLiteDatabaseGuide2.docx`.

### 5. The guide: `SQLiteDatabaseGuide2.docx`
Generated by `migration\Guide.ps1` from the live database in the container. Besides the schema, value meanings and example queries (sections 4-7) it contains:
- **Section 3, interacting with the database in the Dockerized Linux container (3.1-3.11):** checking the container, interactive session, read-only access, one-off queries from Windows, running a Windows-side .sql script through stdin, taking query results (not the database) out, scratch copies, integrity/`sqldiff`/backup, lifecycle and persistence, using it from a Linux application (JDBC), troubleshooting.
- **Section 9, moving to Linux: loading the exported schema and data into a Linux SQLite:** where Windows stops and Linux takes over, which files to carry (with size and SHA-256 from the run), getting them to Linux (`docker cp`, `scp`, piping), building the database (in the container from Windows, in the container from files, or on a plain Linux host), checking it without SQL Server, and what can and cannot be proven on Linux.

## Verification plan

1. Full pipeline from `cmd.exe`: exit 0, 41 of 41 checks, 155 of 155 rows, self-test passed, report and guide present.
2. It really is Linux, and the database is only there: the results name Alpine and SQLite 3.45.3; `docker exec mar-sqlite uname -a` and a count query inside the container; no `.sqlite` file exists anywhere under `tools\phase1\dbmigrate\iteration2\` or `docs\phase1\dbmigrate\iteration2\`.
3. Cross-check against iteration 1 without any database copy: `01-schema.sql` and `02-data.sql` are byte-identical to iteration 1's (same SHA-256), and the per-table SHA-256 fingerprints in both results files are identical.
4. Awkward data (CRLF, tabs, backslashes, quotes, emoji, CJK text, an empty text, NULLs, a year-9999 date, a soft-deleted user with an odd name) added to the source temporarily: all rows identical, then removed and the source restored.
5. Negative test and exit codes: a damaged copy (inside the container) is reported as FAILED with the exact table, row and column; `import` without `--recreate` exits 3; an unknown target exits 2.
6. Regression: `tools\phase1\dbmigrate\iteration1\dbmigrate.cmd all --target sqlite` still passes.
7. Guide: every command in sections 3 and 9 was run against the container (a scratch database built from the two exported files by piping equals the real one under `sqldiff`).
8. Documents: links resolve and quoted numbers match the results files.

## Risks and notes

- The first container start needs internet access (`apk add`); it is slower.
- The database exists only in the container. `docker stop`/`start` and Docker restarts keep it; `docker rm -f mar-sqlite` deletes it, and re-running the pipeline with `--recreate` rebuilds it from the source.
- The exported SQL files and the database contain password hashes and must be protected.
- Not tested: the Docker daemon stopping mid-run (the tool reports a clear error at the start of a run if the daemon is off).
- Inspect the database with, for example: `docker exec mar-sqlite sqlite3 -header -column /data/masterantique.sqlite "SELECT COUNT(*) FROM Users;"`
