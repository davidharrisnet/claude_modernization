# Iteration 1: Migrating the MasterAntiqueRepair database from SQL Server to SQLite

**Runs on Windows.** This iteration needs a live SQL Server LocalDB connection and Windows PowerShell — both Windows-only. It cannot be executed on Linux or macOS; see [docs/phase1/dbmigrate/DATA_MIGRATION.md](../DATA_MIGRATION.md) for how iteration 3 works around that by starting from already-exported files instead.

**What this document is.** A step-by-step, plain-language account of the whole migration in iteration 1: what was moved, how, how we know it arrived intact, and what to watch for. It is written so parts of it can be lifted into a project report.

**How it relates to the other documents.**

| Document | Purpose |
|---|---|
| [ITERATION1_PLAN.md](ITERATION1_PLAN.md) | The plan and design *before* the work (the intended approach). |
| **ITERATION1.md (this file)** | The migration as it was carried out, step by step, with the results. |
| `MigrationVerificationReport1.docx` (this folder) | The detailed verification report (Word, with charts): every check, hash and test. Read it for the evidence. |

Iteration 1 covers one migration: the repair-shop database in **SQL Server (LocalDB)** to a new **SQLite** database file, run natively on Windows.

---

## 1. Purpose and scope

The repair-shop application keeps its data in a SQL Server database. Iteration 1 proves the data and its rules can be exported and rebuilt in a different database engine, SQLite, with nothing lost or changed. Every iteration follows the same four steps:

1. **Export** the data from the source database.
2. **Populate** the data into a **new** database.
3. **Verify** the data is identical.
4. **Report** the result in `MigrationVerificationReport{N}.docx` (N = iteration number).

The migration is done by scripts, not by hand and not by an AI model: the same source always produces the same files. That makes it repeatable and checkable.

**In scope:** all eight application tables, their structure, keys, relationships, indexes, default values and every row.
**Deliberately not migrated:** the `__MigrationHistory` table. It is bookkeeping for the application's database-migration tool (Entity Framework) and has no meaning in SQLite.

## 2. The source database

| Item | Value |
|---|---|
| Server | SQL Server LocalDB, instance `(localdb)\MSSQLLocalDB` |
| Database | `aspnet-MasterAntiqueRepair-e93a6129-7f74-4486-97e8-8d4ab1a709b4` (the live application database) |
| Access | Windows authentication; the migration only **reads** from it |

The eight application tables, as they stood in the run recorded here:

| Table | What it holds | Columns | Rows |
|---|---|---|---|
| `Roles` | The three roles: Customer, Employee, Manager | 2 | 3 |
| `Users` | All accounts (customers, employees, managers); soft-deleted accounts are kept with a deletion date | 15 | 12 |
| `UserRoles` | Which role each user has | 2 | 12 |
| `Tickets` | Repair requests, their state and dates | 8 | 24 |
| `Comments` | Comments posted on tickets | 5 | 26 |
| `AuditLogs` | The record of user actions | 6 | 78 |
| `UserClaims`, `UserLogins` | Identity plumbing; empty in this database | 4 and 3 | 0 and 0 |
| **Total** | | 45 columns | **155 rows** |

Features the copy has to preserve: **auto-numbered ids** on six tables; **nine foreign keys** (seven that delete dependent rows automatically, two that do not); **eleven indexes**; five columns with default values; and one important rule, a **unique-username index that ignores deleted accounts**, so a deleted user's name can be reused. Account rows also contain password hashes, which is why the export folder is kept out of source control.

## 3. Tools and environment

- **Windows PowerShell 5.1** (already part of Windows) runs everything.
- **SQLite command-line tools**, version 3.53.4 (`sqlite3.exe`), plus `sqldiff.exe` for an independent comparison.
- One launcher, run from a normal command prompt: `tools\phase1\dbmigrate\dbmigrate.cmd`. Settings live in `tools\phase1\dbmigrate\migration\migration.config.json`.
- No Docker, no Word installation and no other software is needed for iteration 1.

## 4. The migration, step by step

### Step 1 - Export: read the source and write two SQL files

Command: `tools\phase1\dbmigrate\dbmigrate.cmd export --target sqlite`

1. **Read the structure.** The script asks SQL Server to describe itself (its catalog): tables, columns and their types, primary keys, relationships, indexes, default values and the auto-number counters. This becomes a neutral description of the database.
2. **Decide the order.** Tables that other tables depend on must be created and filled first (for example `Users` before `Tickets`). The script works this order out itself.
3. **Read every row** in a fixed order and convert each value to one agreed text form (for example, dates always as `2026-09-07 08:20:34.0000000`, yes/no as `1`/`0`). This "canonical form" is what later lets both databases be compared exactly.
4. **Write two files** into `tools\phase1\dbmigrate\iteration1\`:
   - `01-schema.sql` (about 4 KB): the instructions that create the empty tables, keys, relationships and indexes.
   - `02-data.sql` (about 16 KB): the instructions that insert every row, in batches of 100, and set the auto-number counters to continue from where the source left off.

How SQL Server concepts are expressed in SQLite:

| SQL Server | SQLite |
|---|---|
| Whole-number types | `INTEGER` |
| Yes/no (`bit`) | `INTEGER` 0/1, protected by a rule that only allows 0 or 1 |
| Text (`nvarchar`) | `VARCHAR(n)` / `TEXT` (SQLite records but does not enforce the length) |
| Dates (`datetime`) | Text in ISO format |
| Auto-number ids | `INTEGER PRIMARY KEY AUTOINCREMENT`, counter set from the source |
| Relationships and their delete rules | Declared inside each table definition, delete rules kept |
| Unique-username index that ignores deleted accounts | A native SQLite *partial* index (`WHERE DeletedAt IS NULL`) |
| Index names repeated across tables (for example `IX_UserId`) | Prefixed with the table name, because SQLite index names must be unique database-wide |

Safety rules built in: an unrecognised column type or an index rule the script cannot translate **stops the export with an error** instead of guessing. The output is **deterministic**: run twice, the files are identical byte for byte.

### Step 2 - Populate: build a new SQLite database

Command: `tools\phase1\dbmigrate\dbmigrate.cmd import --target sqlite --recreate`

1. A **new, empty** database file is created: `tools\phase1\dbmigrate\iteration1\masterantique.sqlite`. Without `--recreate` the script refuses to touch an existing file.
2. `01-schema.sql` runs, then `02-data.sql`. The run stops at the first error.
3. **Immediate self-checks** by SQLite: an integrity check (must say `ok`) and a relationship check (must find no orphaned rows).

The source database is never modified. The result is a file of about 100 KB.

### Step 3 - Verify: prove the copy is identical

Command: `tools\phase1\dbmigrate\dbmigrate.cmd verify --target sqlite`, then `tools\phase1\dbmigrate\dbmigrate.cmd selftest --target sqlite`

Verification reads the source and the new database independently and compares them. Six kinds of evidence:

| # | Evidence | What it shows |
|---|---|---|
| 1 | **Row counts** | Every table has the same number of rows in both databases. |
| 2 | **Row-by-row content** | Every value of every row matches. Values are compared as exact bytes, so line breaks, quotes, accents and emoji cannot hide a difference, and an empty text is told apart from "no value". A fingerprint (SHA-256) of each table's rows is computed on both sides and must be equal. |
| 3 | **Structure** | Tables, columns (name, order, type, required or not, default), primary keys, relationships and their delete rules, indexes, the partial-index rule and auto-number tables all match what SQL Server defined. |
| 4 | **Business summaries** | The same questions asked of both databases give the same answers: users by type and by role, active vs deleted users, tickets by state, audit events by action, date ranges. |
| 5 | **Rule tests** (on a throw-away copy, so the delivered file is untouched) | A duplicate active username is rejected; a deleted user's name can be reused; a row pointing at a non-existent parent is rejected; a yes/no column refuses values other than 0/1; the next new id continues from the source's counter. |
| 6 | **Integrity** | SQLite's own integrity and orphan-row checks are clean. |

Credential columns (password hashes and security stamps) are compared like everything else but are **never printed** in any output.

**Self-test of the tooling itself.** It shows the checks can be trusted:

| Test | Result |
|---|---|
| A second export is byte-identical to the first (schema and data) | Passed |
| A separately built copy equals the delivered database according to SQLite's own `sqldiff` tool | Passed |
| A deliberately damaged copy (one comment altered, one ticket removed) is reported as FAILED, and the exact table, row and column are named | Passed |

### Step 4 - Report: write the verification report

Command: `tools\phase1\dbmigrate\dbmigrate.cmd report --target sqlite`

The script produces a Word document with a green PASSED or red FAILED banner, charts, per-table counts and fingerprints, the structure comparison, the rule tests, the self-test, a list of differences (or "None"), known differences, reproduction commands and a sign-off block. It needs no copy of Word to be created. It contains the full evidence for step 3.

All four steps run together with `tools\phase1\dbmigrate\dbmigrate.cmd all --target sqlite`.

## 5. Results

The run recorded here was made on 21 September 2026 (03:14 UTC) with tooling commit `79fff02`.

| Measure | Result |
|---|---|
| Checks passed | **41 of 41** (16 row checks, 10 business summaries, 8 structure, 2 integrity, 5 rule tests) |
| Rows verified identical | **155 of 155** |
| Differences found | **None** |
| Self-test | 6 of 6 passed |
| Command exit code | 0 |

Per-table result (the fingerprint is the first 16 characters of the SHA-256 of all rows; source and new database fingerprints were equal for every table):

| Table | Rows in SQL Server | Rows in SQLite | Fingerprint | Result |
|---|---|---|---|---|
| Roles | 3 | 3 | `083c2efe5cfe6dcb` | Pass |
| Users | 12 | 12 | `a90ce7a28ea15036` | Pass |
| AuditLogs | 78 | 78 | `f6f5c61f2a17b80f` | Pass |
| Tickets | 24 | 24 | `387438d6fd501090` | Pass |
| Comments | 26 | 26 | `0f8d22818a8b725a` | Pass |
| UserClaims | 0 | 0 | `e3b0c44298fc1c14` (empty table) | Pass |
| UserLogins | 0 | 0 | `e3b0c44298fc1c14` (empty table) | Pass |
| UserRoles | 12 | 12 | `400a46fd1a653d2b` | Pass |

Files produced (in `tools\phase1\dbmigrate\iteration1\`, which is gitignored because it contains password hashes):

| File | What it is |
|---|---|
| `01-schema.sql`, `02-data.sql` | The export |
| `masterantique.sqlite` | The new SQLite database |
| `import-log.txt` | What the load reported |
| `verification-results.json`, `selftest-results.json` | Machine-readable results |
| `MigrationVerificationReport1.docx` | The detailed Word verification report |

Note on the report file name: from iteration 1 on, the report carries the iteration number. When iteration 1 was run the tool still wrote the un-numbered name `MigrationVerificationReport.docx` and the copy was renamed to `MigrationVerificationReport1.docx` by hand. Since iteration 2 the tool names it automatically from the target's `iteration` setting (iteration 1 = `MigrationVerificationReport1.docx`), and the report was rebuilt from the same recorded results with a small wording fix (a variable name that had been printed literally in one bullet); the verification results themselves were not re-run.

The test data was also stressed once: awkward rows (line breaks, tabs, backslashes, quotes, emoji, Chinese and Japanese text, an empty text, missing values, a date in the year 9999, a deleted user with an accented name) were added temporarily to the source. All 160 rows came through identically; the rows were then removed and the source restored.

## 6. Problems met and how they were resolved

The verification found real defects while the tooling was being built, which is what it is for:

| Problem | How it showed up | Fix |
|---|---|---|
| The SQLite shell on Windows silently turned a line break (CR+LF) inside a text value into LF | One comment differed by one byte; the row-by-row check named the table, row and column | Text containing control characters is now written as explicit character codes that the shell cannot alter. |
| "No value" (NULL) was being turned into an empty text | A generated line was malformed | Values are held so that "no value" stays distinct. |
| Five columns had default values that were only warned about, not exported | Noticed in the export output | Defaults are now exported, and any default the script cannot translate is a hard error. |
| Index names such as `IX_UserId` repeat across five tables, but SQLite requires unique names | Anticipated from the source structure | Repeated names get a table prefix. |
| Several layout defects in the Word report (a flattened table, a blank page, a clipped chart) | Found by viewing the rendered pages | Fixed and re-checked visually. |

## 7. Known differences and limitations

- SQLite has no date type: dates are stored as ISO-format text. Yes/no columns are stored as 0/1.
- SQLite does not enforce text lengths; the declared lengths are kept for documentation.
- SQLite compares text **case-sensitively**; the SQL Server database does not. The migrated data already obeys SQL Server's rules, but new rows inserted directly into SQLite are not protected against names that differ only by case (for example "Bob" and "bob").
- The export files and the SQLite file contain password hashes; handle them as sensitive.
- Iteration 1 ran natively on Windows. It says nothing yet about how the database behaves on Linux; that is the point of iteration 2.

## 8. How to repeat it

From a Windows command prompt in the repository root (`c:\Users\Bilbo\Documents\dev\aspnet\claude_modernization`):

```
tools\phase1\dbmigrate\dbmigrate.cmd all --target sqlite
```

Expect `VERIFICATION PASSED - 41 of 41 checks passed; 155 of 155 source rows verified identical`, then `SELF-TEST PASSED`, then the report path; `echo %ERRORLEVEL%` prints `0`. Exit codes: `0` success, `1` verification found differences, `2` configuration or tool error, `3` refused because the target already exists and `--recreate` was not given.

For an independent look, ask SQLite directly: `C:\Apps\sqlite-tools-win-x64-3530400\sqlite3.exe tools\phase1\dbmigrate\iteration1\masterantique.sqlite "select count(*) from Users;"` prints 12, matching SQL Server.

## 9. Conclusion

The SQL Server database was exported by a repeatable script, rebuilt as a new SQLite database, and verified to be identical in structure and in all 155 rows, with the deleted-user username rule, relationships and auto-numbering intact, and with the verification method itself shown to catch damage. Iteration 1 meets all four steps. Its detailed evidence is in `MigrationVerificationReport1.docx`.

## 10. Later addition: credential sanitization (2026-09-22)

After iteration 3 established a project-wide security policy (`docs/phase1/dbmigrate/DATA_MIGRATION.md` §5.2) — for a one-time bootstrap migration, invalidate credentials as part of the migration itself rather than carrying real password hashes forward — this iteration's tooling was refactored to do the same, per the plan in `docs/phase1/dbmigrate/SANITIZE_FIRST_REFACTOR.md`, and re-run.

**What changed.** Unlike iteration 3 (which sanitizes an already-written file with a text transform, since it has no live source to re-query), this iteration exports live from SQL Server, so sanitization happens **in memory**, before any SQL text is ever rendered or written to disk: a new function, `Protect-SensitiveData` (`migration/Common.ps1`), mutates the in-memory table model and row data for `Users` right after they're read — `PasswordHash`/`SecurityStamp` become `NULL`, and a new `MustResetPassword` column is added and set to `1`. `Export.ps1` calls it before `RenderSchema`/`RenderData`; `Verify.ps1` calls the same function on freshly-read source rows before comparing, so both sides of every comparison are sanitized identically and the existing generic row-comparison logic needs no special case. The exported data file is now named `02-data-sanitized.sql` (not `02-data.sql`) whenever a target has `"sanitizeCredentials": true` set in `migration.config.json` — true for all three targets (`sqlite`, `sqlite-linux`, `mysql`) as of this change — so the filename itself signals whether it's safe to move or commit.

**A real bug found by actually running it.** `sqlite.ps1`'s `Sqlite-Query` was piping `.mode list`/`.separator |` as stdin dot-commands alongside the query itself; this doesn't reliably parse on the sqlite3 3.53.4 build installed here. Fixed by passing `-list -separator |` as CLI flags instead. Unrelated to sanitization, only surfaced because this iteration is actually executable end-to-end on this machine.

**Results of the re-run** (`tools/phase1/dbmigrate/iteration1/verification-results.json`, run 2026-09-22 17:16:35 UTC, `sqlite3 3.53.4`): **42 of 42 checks passed** (41 from before, plus one new `Sanitization` category check: *"Every Users row has PasswordHash/SecurityStamp NULL and MustResetPassword = 1"* — passed, `0 row(s) not sanitized`), **155 of 155 rows verified identical**, self-test 6 of 6 passed. `MigrationVerificationReport1.docx` and `SQLiteDatabaseGuide1.docx` were regenerated from these results and now describe the sanitization policy in place of the old "copied byte-for-byte" claim about credentials.

**What this changes about iteration 1's verification claim.** Before: 100% byte-for-byte fidelity, including credentials. Now: 100% fidelity for every column except credentials, which are deliberately and verifiably invalidated — a different, and now policy-correct, claim. No raw `02-data.sql` (the file that would carry real password hashes) was committed at any point in this change.
