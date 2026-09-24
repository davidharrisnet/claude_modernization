# Iteration 2: the database in SQLite, inside a Linux container

Iteration 2 takes the MasterAntiqueRepair database from **SQL Server (LocalDB)**, rebuilds it as a **SQLite** database that lives **inside a Linux Docker container**, and **proves that nothing changed on the way**: every table, every row and every rule matches the original, except the password data, which is removed on purpose. The SQLite that builds and checks the database is the Linux build, so the result is known to load and behave on Linux. The database file is never copied to Windows.

It is [iteration 1](../iteration1/README.md) with one difference: the target runs in a container. The source, the export, the checks and the reports are the same.

## What it does

1. **Exports.** Reads the structure and every row of the SQL Server database, removes the password data (see "Limits") and writes two SQL files, the schema and the data. They are byte-for-byte the same files iteration 1 writes.
2. **Starts the container.** On first use it creates `mar-sqlite` from the stock `alpine:3.20` image and installs SQLite in it; later runs reuse it.
3. **Imports.** Creates a new, empty database `/data/masterantique.sqlite` inside the container, loads the two files into it with the Linux `sqlite3`, and runs SQLite's own integrity and orphan-row checks.
4. **Verifies.** 42 checks compare the database with SQL Server itself: row counts, a fingerprint (SHA-256) of every table's full contents, the structure, ten business questions, the rules of the database and the removal of all passwords. Everything is read through `docker exec`.
5. **Tests itself.** Proves the checker gives the same answer every time, agrees with the container's own `sqldiff`, and catches damage (a copy with one comment altered and one ticket removed must be reported as failed, naming the table, row and column).
6. **Reports.** Writes a Word verification report with charts and a Word guide to working with the database in the container.

## Where it runs

A Windows machine with Windows PowerShell 5.1, SQL Server LocalDB holding the legacy application's database, and **Docker Desktop running** (WSL2 backend). The export needs the live SQL Server connection, so the tool cannot run on Linux or macOS; only the database lives on Linux. The first run downloads the small Alpine image and installs SQLite in the container, which needs internet access.

## What it produces

| Output | What it is |
|---|---|
| The `mar-sqlite` container | The migrated database at `/data/masterantique.sqlite`: 8 tables, 155 rows, no passwords. It exists only there |
| `01-schema.sql`, `02-data-sanitized.sql` (in `tools/phase1/dbmigrate/iteration2/`) | The export: the SQL that builds the database. The data file contains no credentials |
| `verification-results.json`, `selftest-results.json`, `import-log.txt` (same folder) | The machine-readable results and the load log |
| [MigrationVerificationReport2.docx](MigrationVerificationReport2.docx) | The verification report: every check, fingerprint and test, with charts |
| [SQLiteDatabaseGuide2.docx](SQLiteDatabaseGuide2.docx) | How to work with the database in the container (`docker exec`, from an application on Linux), its structure, example queries, and how to load the export into any Linux SQLite |

## Latest results

Last run: 2026-09-24, `dbmigrate.cmd all --target sqlite-linux`, SQL Server 2025 (RC1) LocalDB, SQLite 3.45.3 on Alpine Linux 3.20 in Docker Desktop (WSL2 kernel 5.15.133.1).

**42 of 42 checks passed; 155 of 155 rows identical to the source; self-test 6 of 6 passed.**

| Area | Checks | Result |
|---|---|---|
| Row counts | 8 | Every table has the same number of rows as the source |
| Content fingerprints | 8 | Every table's full contents identical to the source |
| Structure | 8 | Tables, columns, keys, relationships and their delete rules, indexes (including the active-username rule), auto-number tables as designed |
| Business questions | 10 | Same answers as the source (users by type and role, tickets by state, audit events, comments, date ranges) |
| Integrity | 2 | SQLite's integrity check `ok`; no orphaned rows |
| Database rules | 5 | Duplicate active username rejected; a deleted user's name can be reused; orphan comment rejected; yes/no columns only accept 0 and 1; new ids continue after the migrated ones |
| Passwords removed | 1 | No user has a password hash or security stamp; every user must set a new password |

The totals and the per-table fingerprints are identical to iteration 1's, and the export files are byte-identical. The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed), 26 comments, 78 audit log entries, 3 roles, 12 role assignments.

## Run it

**With Claude Code:** start Docker Desktop and wait until it reports running; open this repository in VS Code (or a terminal) with Claude Code on the Windows machine and type:

```
Repeat iteration 2.
```

Claude Code follows the iteration's instructions ([tools/phase1/dbmigrate/iteration2/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration2/CLAUDE.md)): it runs the command below, checks the results against the ones above and reports.

**By hand:** from a plain command prompt in the repository root:

```
tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux
```

It exports, replaces the database in the container, verifies, self-tests and writes both Word documents. Expect `VERIFICATION PASSED - 42 of 42 checks passed; 155 of 155 source rows verified identical` and `SELF-TEST PASSED`. The exit code is 0 on success, 1 if verification found differences, 2 for a configuration, tool or Docker error, 3 if the database already exists and replacing was not requested. The individual commands are `export`, `import`, `verify`, `selftest`, `report` and `guide`.

To look at the result yourself: `docker exec mar-sqlite sqlite3 /data/masterantique.sqlite "select count(*) from Users;"` prints 12. `docker rm -f mar-sqlite` removes the container and the database in it (the small Alpine image stays on disk); running the iteration again rebuilds it.

## Limits and known differences

- **Passwords were removed on purpose.** Every user's password hash and security stamp is empty and a new `MustResetPassword` column is set to 1, so no usable credential is carried over. Everything else is identical to the source. The removal happens in memory before anything is written.
- **The database exists only in the container.** Stopping and starting Docker keeps it; removing the container deletes it. There is no volume, no published port and no copy on Windows.
- **The export must run on Windows.** Only loading and everything after it happens on Linux. The guide shows how to build the database from the two exported files on any Linux host.
- **Dates are text, text lengths are not enforced, text comparison is case-sensitive.** These are properties of SQLite. SQL Server's comparison is case-insensitive, so a new row inserted directly is not protected against a name that differs only by case ("Bob" and "bob").
- **Two SQLite versions.** Windows iteration 1 uses 3.53.4 and this container 3.45.3; the file format is the same, but two databases with identical content need not be byte-identical, which is why the two are compared by content, not as files.
- **`__MigrationHistory` is not migrated.** It is bookkeeping for the application's database-migration tool (Entity Framework).
- **Not tested:** Docker stopping in the middle of a run. The tool reports a clear error at the start of a run if Docker is not running.

## Related documents

- [tools/phase1/dbmigrate/iteration2/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration2/CLAUDE.md): the detailed instructions for repeating and maintaining this iteration (written for Claude Code).
- [../iteration1/](../iteration1/): the same migration with SQLite native on Windows.
- [../iteration3/](../iteration3/): the same database baked into a Docker image, built and verified entirely on Linux.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy for all iterations.
