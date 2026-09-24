# Iteration 1: the database in SQLite, on Windows

Iteration 1 takes the MasterAntiqueRepair database from **SQL Server (LocalDB)**, rebuilds it as a new **SQLite** database file on Windows, and **proves that nothing changed on the way**: every table, every row and every rule matches the original, except the password data, which is removed on purpose. It is the first of the database migration iterations and the only one that compares the new database with the live source.

## What it does

1. **Exports.** Reads the structure of the SQL Server database (tables, columns, keys, relationships, indexes, defaults, auto-number counters) and every row, removes the password data (see "Limits"), and writes two SQL files: the schema and the data. Running it twice on unchanged data gives identical files.
2. **Imports.** Creates a new, empty SQLite database file and loads the two files into it, then runs SQLite's own integrity and orphan-row checks.
3. **Verifies.** 42 checks compare the SQLite database with SQL Server itself: row counts, a fingerprint (SHA-256) of every table's full contents, the structure (columns, keys, relationships, indexes), ten business questions, the rules of the database (for example, two active users cannot share a name) and the removal of all passwords.
4. **Tests itself.** Proves the checker gives the same answer every time, agrees with SQLite's own `sqldiff` tool, and catches damage: a copy with one comment altered and one ticket removed must be reported as failed, naming the table, row and column.
5. **Reports.** Writes a Word verification report with charts, and a Word guide to the SQLite database (schema, meaning of values, example queries).

The same tool can also load the data into **MySQL** in Docker (`--target mysql`, an additional target, not a separate iteration); see "Limits".

## Where it runs

A Windows machine with Windows PowerShell 5.1, SQL Server LocalDB holding the legacy application's database, and the SQLite command-line tools (`sqlite3.exe` 3.53.4 and `sqldiff.exe`, in the folder named in the tool's settings). It needs the live SQL Server connection, so it cannot run on Linux or macOS. No Docker and no Word installation are needed for the SQLite target.

## What it produces

| Output | What it is |
|---|---|
| [tools/phase1/dbmigrate/iteration1/masterantique.sqlite](../../../../tools/phase1/dbmigrate/iteration1/masterantique.sqlite) | The migrated database: 8 tables, 155 rows, no passwords |
| `01-schema.sql`, `02-data-sanitized.sql` (same folder) | The export: the SQL that builds the database. The data file contains no credentials |
| `verification-results.json`, `selftest-results.json`, `import-log.txt` (same folder) | The machine-readable results and the load log |
| [MigrationVerificationReport1.docx](MigrationVerificationReport1.docx) | The verification report: every check, fingerprint and test, with charts |
| [SQLiteDatabaseGuide1.docx](SQLiteDatabaseGuide1.docx) | How to work with the database: structure, meaning of values, example queries |

## Latest results

Last run: 2026-09-24, `dbmigrate.cmd all --target sqlite`, SQL Server 2025 (RC1) LocalDB, SQLite 3.53.4 on Windows.

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

The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed), 26 comments, 78 audit log entries, 3 roles, 12 role assignments.

## Run it

**With Claude Code:** open this repository in VS Code (or a terminal) with Claude Code on the Windows machine and type:

```
Repeat iteration 1.
```

Claude Code follows the iteration's instructions ([tools/phase1/dbmigrate/iteration1/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration1/CLAUDE.md)): it runs the command below, checks the results against the ones above and reports.

**By hand:** from a plain command prompt in the repository root:

```
tools\phase1\dbmigrate\iteration1\dbmigrate.cmd all --target sqlite
```

It exports, imports (replacing the database file), verifies, self-tests and writes both Word documents. Expect `VERIFICATION PASSED - 42 of 42 checks passed; 155 of 155 source rows verified identical` and `SELF-TEST PASSED`. The exit code is 0 on success, 1 if verification found differences, 2 for a configuration or tool error, 3 if the target already exists and replacing was not requested. The individual commands are `export`, `import`, `verify`, `selftest`, `report` and `guide`.

To look at the result yourself, ask SQLite directly: `sqlite3 tools\phase1\dbmigrate\iteration1\masterantique.sqlite "select count(*) from Users;"` prints 12.

## Limits and known differences

- **Passwords were removed on purpose.** Every user's password hash and security stamp is empty and a new `MustResetPassword` column is set to 1, so no usable credential is carried over. Everything else is identical to the source. The removal happens in memory before anything is written, so no file ever holds a real hash.
- **Dates are text.** SQLite has no date type; dates are stored as ISO-format text (`2026-09-07 08:20:34.0000000`) and yes/no columns as 0 and 1.
- **Text lengths are not enforced.** SQLite records the declared lengths but does not check them.
- **Text comparison is case-sensitive.** SQL Server's is not. The migrated data already obeys SQL Server's rules, but a new row inserted directly into SQLite is not protected against a name that differs only by case ("Bob" and "bob").
- **`__MigrationHistory` is not migrated.** It is bookkeeping for the application's database-migration tool (Entity Framework) and has no meaning in SQLite.
- **Windows only, and Windows SQLite only.** It says nothing about how the database behaves on Linux; [iteration 2](../iteration2/README.md) uses the Linux build of SQLite.
- **The MySQL target is not part of the latest run.** Its last recorded run was before the passwords were removed (44 of 44 checks); run it again before relying on it.

## Related documents

- [tools/phase1/dbmigrate/iteration1/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration1/CLAUDE.md): the detailed instructions for repeating and maintaining this iteration (written for Claude Code).
- [../iteration2/](../iteration2/): the same migration with the SQLite database in a Linux container.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy for all iterations.
