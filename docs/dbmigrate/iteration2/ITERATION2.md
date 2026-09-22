# Iteration 2: Migrating the MasterAntiqueRepair database from SQL Server to SQLite inside a Docker Linux container

**Orchestrated from Windows.** The *target* database lives inside a Linux container, but the tool driving this iteration is still Windows PowerShell, needing a live SQL Server LocalDB connection and Docker Desktop — this iteration cannot be run from a Linux or macOS host. Only iteration 3 runs its tooling entirely on Linux; see [docs/DATA_MIGRATION.md](../../DATA_MIGRATION.md).

**What this document is.** A step-by-step, plain-language account of iteration 2: the same migration as iteration 1, but with the new SQLite database created and verified inside a Linux container. It is written so parts of it can be lifted into a project report.

**Provenance.** This file was recreated from the earlier record of the first iteration 2 run (git commit `bbc6fcd`, `DM2.md`) with paths updated to the current layout. The numbers below are from that recorded run (21 September 2026, 15:50 UTC). The pipeline was re-run on the same day at 22:28 UTC (`all --target sqlite-linux --recreate`, exit 0) with identical results: 41 of 41 checks, 155 of 155 rows, self-test passed, the same export hashes (`f0b3a4bb...`, `d800a8c7...`), and the same database fingerprint inside the container (`436c7b68...`).

| Document | Purpose |
|---|---|
| [ITERATION2_PLAN.md](ITERATION2_PLAN.md) | The plan and design for iteration 2, written before the work. |
| **ITERATION2.md (this file)** | The migration as carried out, step by step, with results. |
| `MigrationVerificationReport2.docx` (this folder) | The detailed verification report (Word, with charts). |
| [ITERATION1.md](../iteration1/ITERATION1.md) | The same record for iteration 1 (SQLite on Windows). Read it first for the background; this file only repeats what differs. |

---

## 1. Purpose and what is different from iteration 1

The database is going to run on Linux. Iteration 1 proved the migration using the Windows build of SQLite. Iteration 2 repeats it with the new database **created and checked by the Linux build of SQLite**, running in a Docker container on the same PC. That shows the result loads and behaves on Linux, and lets us compare a Windows-built database with a Linux-built one.

Every iteration follows the same four steps: **export**, **populate a new database**, **verify it is identical**, **write `MigrationVerificationReport{N}.docx`**. For iteration 2, N is 2.

| | Iteration 1 | Iteration 2 |
|---|---|---|
| Where SQLite runs | Windows, `sqlite3.exe` 3.53.4 | A Linux container: Alpine Linux v3.20, `sqlite3` 3.45.3 |
| Where the database file is created | `tools\dbmigrate\iteration1\masterantique.sqlite` on the PC | `/data/masterantique.sqlite` **inside the container**, and only there: it is never copied to Windows |
| Command | `tools\dbmigrate\iteration1\dbmigrate.cmd all --target sqlite` | `tools\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux` |
| Report | `MigrationVerificationReport1.docx` | `MigrationVerificationReport2.docx` |

What did **not** change: the source database (SQL Server LocalDB, read-only), the export logic, the checks, and the report generator. SQL Server LocalDB only exists on Windows, so Docker hosts the target only; export, verification and the report still run on Windows.

### Where Linux takes over

The wider goal is to move the ASP.NET application to Linux. The export must run on **Windows** (LocalDB source, Windows PowerShell tooling). Its two output files, `01-schema.sql` and `02-data.sql`, are plain SQLite SQL text (UTF-8 without BOM, LF) and are the only things that cross from Windows to Linux. From there a Linux process needs only `sqlite3`: loading, integrity checks, queries, rule tests and `sqldiff` all run in the container, and the database file never leaves it. Verification against the live SQL Server source is still orchestrated from Windows, which reads the database only through `docker exec`. `SQLiteDatabaseGuide2.docx` section 9 shows how to load the exported files into a Linux SQLite by hand; making import and verify Windows-free after the export (a manifest of counts and per-table hashes plus Linux scripts) is a possible later step, not part of this iteration.

## 2. Environment

| Item | Value |
|---|---|
| Docker | Docker Desktop 24.0.6 with the WSL2 backend, already installed |
| Linux kernel | 5.15.133.1-microsoft-standard-WSL2 |
| Container | `mar-sqlite`, image `alpine:3.20`, operating system Alpine Linux v3.20 |
| SQLite in the container | 3.45.3 (`sqlite3` and `sqldiff`, installed with `apk add sqlite sqlite-tools`) |
| Source | SQL Server LocalDB `(localdb)\MSSQLLocalDB`, database `aspnet-MasterAntiqueRepair-e93a6129-...` (same 8 tables and 155 rows as iteration 1) |
| Run recorded here | 21 September 2026, 15:50 UTC |
| Tooling | `tools\dbmigrate\iteration2\dbmigrate.cmd` from a normal command prompt; deterministic PowerShell, no AI in the loop |

Docker was already installed, so nothing had to be installed. The first run downloads the small Alpine image and installs SQLite in the container, which needs internet access.

## 3. Step 0 - What had to be built first

Three small changes to the tooling, all tested against iteration 1 afterwards:

1. **A Linux target.** A new target `sqlite-linux` in `tools\dbmigrate\iteration2\migration\migration.config.json` tells the tool to run SQLite inside a container instead of on Windows. The tool creates the container on first use, waits until SQLite is ready, and runs every SQLite command through `docker exec`. The SQLite code (`migration\dialects\sqlite.ps1`) works either way; the Windows behaviour is unchanged.
2. **A numbered report.** Each target can carry an iteration number. The report file is named `MigrationVerificationReport{N}.docx` and its title page and header say "Iteration N".
3. **A guide that works through the container.** `SQLiteDatabaseGuide2.docx` explains how to interact with the database with `docker exec` (section 3) and how to load the exported schema and data into a Linux SQLite (section 9). The database itself is not copied out of the container.

## 4. The migration, step by step

Run as one command from a Windows command prompt in the repository root:

```
tools\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux
```

### Step 1 - Export

The tool reads SQL Server's description of itself (tables, columns, keys, relationships, indexes, defaults, auto-number counters), works out the order in which tables must be built, reads every row and converts it to one agreed text form, and writes two files into `tools\dbmigrate\iteration2\`:

- `01-schema.sql` (4,040 bytes): creates the empty tables, keys, relationships and indexes.
- `02-data.sql` (16,023 bytes): inserts every row and sets the auto-number counters.

These are **byte-for-byte identical** to iteration 1's files (the same SHA-256, `f0b3a4bb...` for the schema and `d800a8c7...` for the data). That is expected, because it is the same source and the same rules, and it shows the export is repeatable.

### Step 2 - Populate a new database, in Linux

The tool starts (first time: creates) the container `mar-sqlite`, then inside it:

1. Creates a **new, empty** SQLite database `/data/masterantique.sqlite` (it refuses to overwrite an existing one unless `--recreate` is given).
2. Runs `01-schema.sql`, then `02-data.sql`, stopping at the first error.
3. Runs SQLite's own integrity check (result `ok`) and its relationship check (no orphaned rows).
4. Leaves the finished file (102,400 bytes, SHA-256 `436c7b68...` in the recorded run) where it is, inside the container. Nothing is copied to Windows; its size and fingerprint are read with `docker exec`.

### Step 3 - Verify identical

The same six kinds of evidence as iteration 1 (see [ITERATION1.md](../iteration1/ITERATION1.md)), all now read through the Linux SQLite: row counts, row-by-row content with a fingerprint per table, structure, ten business summaries, five rule tests on a throw-away copy inside the container, and integrity checks. Credential columns are compared but never printed.

The **self-test** of the tooling also ran in the container: a second export is byte-identical to the first; a separately loaded copy equals the delivered database according to the container's own `sqldiff`; and a deliberately damaged copy (one comment altered, one ticket removed) is reported as FAILED with the exact table, row and column named.

### Step 4 - Write the report

`docs\dbmigrate\iteration2\MigrationVerificationReport2.docx` (105,156 bytes, 11 pages, 9 charts in the recorded run). Its title page reads "SQL Server to SQLite (Linux container)" and "Iteration 2 - SQLite in a Dockerized Linux container", and names the Linux, kernel and SQLite versions. Rebuilding it from the same results gives a byte-identical file.

## 5. Results (recorded run)

| Measure | Result |
|---|---|
| Checks passed | **41 of 41** (16 row checks, 10 business summaries, 8 structure, 2 integrity, 5 rule tests) |
| Rows verified identical | **155 of 155** |
| Differences found | **None** |
| Self-test | 6 of 6 passed |
| Exit code | 0 |

Per-table result (fingerprint = first 16 characters of the SHA-256 of all rows). The fingerprints are the same as in iteration 1 for every table:

| Table | Rows in SQL Server | Rows in SQLite (Linux) | Fingerprint | Result |
|---|---|---|---|---|
| Roles | 3 | 3 | `083c2efe5cfe6dcb` | Pass |
| Users | 12 | 12 | `a90ce7a28ea15036` | Pass |
| AuditLogs | 78 | 78 | `f6f5c61f2a17b80f` | Pass |
| Tickets | 24 | 24 | `387438d6fd501090` | Pass |
| Comments | 26 | 26 | `0f8d22818a8b725a` | Pass |
| UserClaims | 0 | 0 | `e3b0c44298fc1c14` (empty) | Pass |
| UserLogins | 0 | 0 | `e3b0c44298fc1c14` (empty) | Pass |
| UserRoles | 12 | 12 | `400a46fd1a653d2b` | Pass |

Files produced in `tools\dbmigrate\iteration2\` (gitignored: the data file contains password hashes): `01-schema.sql`, `02-data.sql`, `import-log.txt`, `verification-results.json`, `selftest-results.json`. `MigrationVerificationReport2.docx` and `SQLiteDatabaseGuide2.docx` are written to `docs\dbmigrate\iteration2\`. The database is only at `/data/masterantique.sqlite` in the container `mar-sqlite`; there is no `.sqlite` file on Windows.

### It really ran on Linux
- The results file records the client as *sqlite3 3.45.3 on Alpine Linux v3.20, Linux kernel 5.15.133.1-microsoft-standard-WSL2 (container mar-sqlite, image alpine:3.20)*.
- Asked directly inside the container, `uname -a` reports a Linux kernel, `sqlite3 -version` reports 3.45.3, and `select count(*) from Users` returns 12 with `pragma integrity_check` returning `ok`.

### Cross-checks against iteration 1
| Check | Result |
|---|---|
| `01-schema.sql` and `02-data.sql` compared with `tools\dbmigrate\iteration1\` | Byte-identical |
| Per-table row fingerprints in the two results files | All eight identical |
| `sqldiff` inside the container between the delivered database and one built independently from the same two files | No differences |

The iteration 1 and iteration 2 databases are deliberately **not** compared as files: the Linux database is never copied to Windows. The comparison rests on the identical export files and the identical per-table row fingerprints, both computed from the source. (Different SQLite versions also write some internal file-header bookkeeping differently, so two databases with identical content need not be byte-identical.)

### Stress test with awkward data
Awkward rows (line breaks, tabs, backslashes, quotes, emoji, Chinese and Japanese text, an empty text, missing values, a date in the year 9999, a deleted user with an accented name) were added temporarily to the source. **160 of 160** rows came through identically, and inspecting them inside the container confirmed the line break, the emoji and the backslashes are stored exactly, and that the empty text and the missing value stay different from each other. The rows were then removed and the source restored to its original counts and auto-number counters, and the run above was repeated on the real data.

### Other checks
- Running `import` again without `--recreate` is refused (exit code 3); an unknown target exits with 2.
- Regression: iteration 1's SQLite target still passes 41 of 41 and writes `MigrationVerificationReport1.docx`; the MySQL extra passed 44 of 44.
- Report: opens in Microsoft Word (11 pages, 9 pictures, 10 tables) and each page was rendered and read back.

## 6. Problems met and how they were resolved

The Linux run itself passed on the first attempt. Checking the finished report found one defect, and one habit worth recording:

| Problem | How it showed up | Fix |
|---|---|---|
| A literal `$tn` printed in the report ("... the $tn database therefore ...") | Found when reading the rendered page of the report | A text template used the wrong kind of quotes. Fixed; the iteration 1 and MySQL reports were rebuilt from their existing results (no re-verification) so all three are correct. |
| Hand-typed test commands were rewritten by Git Bash (`/data/...` became a Windows path) | An error when querying the container by hand | Only affects commands typed in Git Bash, not the tool itself. Avoided with `MSYS_NO_PATHCONV=1`. |

## 7. Known differences and limitations

- SQLite has no date type: dates are ISO-format text; yes/no columns are 0/1; text lengths are recorded but not enforced.
- SQLite compares text **case-sensitively**, the SQL Server database does not; the migrated data obeys SQL Server's rules, but new rows inserted straight into SQLite are not protected against case-only duplicates such as "Bob" and "bob".
- The two SQLite versions (3.53.4 on Windows, 3.45.3 in the container) may write database files with different raw bytes but identical content.
- The exported data file and the database contain password hashes and must be protected.
- The database exists only in the container. `docker rm -f mar-sqlite` deletes it; re-run the pipeline with `--recreate` to rebuild it. The container was created from the stock `alpine:3.20` image, with no custom image, volume or published port.
- The export must run on Windows; only the loading and everything after it can run on Linux (see "Where Linux takes over").
- Not tested: Docker stopping in the middle of a run. (The tool reports a clear error at the start of a run if Docker is not running.)

## 8. How to repeat it

Start Docker Desktop, wait until it reports running, then from a Windows command prompt in the repository root:

```
tools\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux --recreate
```

Expect `VERIFICATION PASSED - 41 of 41 checks passed; 155 of 155 source rows verified identical`, then `SELF-TEST PASSED`, then the report path; `echo %ERRORLEVEL%` prints `0`. Exit codes: `0` success, `1` verification found differences, `2` configuration or tool error, `3` refused because the target already exists and `--recreate` was not given.

To look inside the container yourself: `docker exec mar-sqlite sqlite3 /data/masterantique.sqlite "select count(*) from Users;"` prints 12. `SQLiteDatabaseGuide2.docx` (section 3) has the full set of commands. When finished, `docker rm -f mar-sqlite` removes the container and the database in it (the small Alpine image stays on disk).

## 9. Conclusion

The SQL Server database was exported by a repeatable script, rebuilt as a new SQLite database **inside a Linux container**, and verified to be identical in structure and in all 155 rows, with the deleted-user username rule, relationships and auto-numbering intact. The export files match iteration 1 exactly, the row fingerprints match iteration 1 for every table, and the container's own `sqldiff` finds no difference between the delivered database and one built independently from the same files. The database was never copied to Windows. Iteration 2 meets all four steps. Its detailed evidence is in `MigrationVerificationReport2.docx`.

## 10. Later addition: credential sanitization (2026-09-22)

Same change, same reason, as [ITERATION1.md §10](../iteration1/ITERATION1.md#10-later-addition-credential-sanitization-2026-09-22) — this iteration's tooling is a separate copy, so the identical edit (`Protect-SensitiveData` in `migration/Common.ps1`, called from `Export.ps1` and `Verify.ps1`, plus the `Sqlite-Query` stdin-parsing fix in `sqlite.ps1`) was applied here too and re-run against the Linux-container target, per `docs/dbmigrate/SANITIZE_FIRST_REFACTOR.md`. This file only records what differs.

**Results of the re-run** (`tools/dbmigrate/iteration2/verification-results.json`, run 2026-09-22 17:17:43 UTC, `sqlite3 3.45.3 on Alpine Linux v3.20`): **42 of 42 checks passed**, **155 of 155 rows verified identical**, self-test 6 of 6 passed — the same totals as iteration 1's re-run, as expected since both exported from the same source with the same policy. The sanitization check (*"Every Users row has PasswordHash/SecurityStamp NULL and MustResetPassword = 1"*) passed with `0 row(s) not sanitized`. `MigrationVerificationReport2.docx` and `SQLiteDatabaseGuide2.docx` were regenerated accordingly.

As with iteration 1: no raw `02-data.sql` was committed — only `02-data-sanitized.sql`, and iteration 2's verification claim changes the same way (full fidelity except credentials, which are now deliberately invalidated rather than carried through byte-for-byte).
