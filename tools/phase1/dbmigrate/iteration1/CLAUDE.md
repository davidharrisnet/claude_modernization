# Iteration 1 — instructions for Claude Code

This folder is the iteration 1 tool: it exports the MasterAntiqueRepair database from SQL Server LocalDB, rebuilds it as a
SQLite file on Windows, and verifies the copy against the live source. The human description is
`docs/phase1/dbmigrate/iteration1/README.md`; the strategy and security policy for all iterations is
`docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5 security). Iteration 2 is a separate copy of this tool whose SQLite runs in a
Linux container (`tools/phase1/dbmigrate/iteration2/CLAUDE.md`); a fix made here usually has to be made there too.

## Rules

1. **Windows only, from a plain command prompt.** The export needs the live SQL Server LocalDB and Windows PowerShell 5.1;
   nothing here runs on Linux or macOS. Run it as `tools\phase1\dbmigrate\iteration1\dbmigrate.cmd` from `cmd.exe`
   (Git Bash rewrites `/`-paths in hand-typed commands).
2. **Credentials are sanitized in memory, before anything is rendered or written**, and `sanitizeCredentials` stays `true` in
   every target of `migration\migration.config.json`. Why: a raw export was once committed (DATA_MIGRATION.md §5.1); with
   the flag off the data file is named `02-data.sql`, holds real password hashes, and no `.gitignore` here covers it.
3. **The source is only read.** The one exception is a deliberate stress test (see "Testing changes"), which must remove
   what it added and restore the auto-number counters.
4. **Never guess.** An unsupported source type, an index filter the dialect cannot translate, or a default it cannot
   translate is a hard error (exit 2), never a silent fallback. Why: a dropped rule would still "pass" verification of the data.
5. **The export is deterministic**: sorted metadata, invariant culture, UTF-8 without BOM, LF newlines, no clock, host or
   user name in `01-schema.sql` / `02-data-sanitized.sql`. Two exports of unchanged data must be byte-identical (the self-test checks it).
6. **Generated files are never edited by hand**: `01-schema.sql`, `02-data-sanitized.sql`, `masterantique.sqlite`,
   `import-log.txt`, `verification-results.json`, `selftest-results.json`, and the two Word documents in
   `docs/phase1/dbmigrate/iteration1/`. Change the tool and regenerate.
7. **Credential columns are compared but never printed** (`$script:RedactedColumns` in `Common.ps1`, `<redacted>` in mismatch output).
8. **Do not commit.** The user reviews `git status` and commits.

## Run

From the repository root, in a command prompt:

```
tools\phase1\dbmigrate\iteration1\dbmigrate.cmd all --target sqlite
```

Expected: exit 0, `VERIFICATION PASSED - 42 of 42 checks passed; 155 of 155 source rows verified identical.`,
`SELF-TEST PASSED`, then the paths of the report and the guide. Commands: `export`, `import [--recreate]`,
`verify [--db <file>]`, `selftest`, `report [--out <file>]`, `guide [--out <file>]`, `all` (export, import with `--recreate`
implied, verify, self-test, report, guide). `--config <path>` replaces the settings file. Exit codes: 0 ok, 1 verification
or self-test found differences, 2 configuration, tool or connection error, 3 refused (target exists, no `--recreate`).
After a successful run, update the "Latest results" section of the docs README if any number or the date changed.

## Settings

`migration\migration.config.json` (paths relative to the repository root): `source` (`server` `(localdb)\MSSQLLocalDB`,
`database` `aspnet-MasterAntiqueRepair-e93a6129-…`), `outputDir` `tools/phase1/dbmigrate`, and one block per target:

| Target | Keys |
|---|---|
| `sqlite` (this iteration) | `dialect` `sqlite`, `iteration` 1, `iterationTitle`, `outputSubdir` `iteration1`, `reportDir` `docs/phase1/dbmigrate/iteration1`, `guideFile` `SQLiteDatabaseGuide1.docx`, `exe` and `diffExe` (`C:\Apps\sqlite-tools-win-x64-3530400\sqlite3.exe`, `sqldiff.exe`, 64-bit; the 32-bit x86 tools cannot load into 64-bit PowerShell), `file` (the `.sqlite` path), `sanitizeCredentials` |
| `sqlite-linux` | a leftover block with no output folder; the Linux-container target is run from iteration 2's copy of the tool, not from here |
| `mysql` | `dialect` `mysql`, `runner` (`docker`, container `mar-mysql`, image `mysql:8.4`), `database`, `user`, `passwordEnv` `MAR_MYSQL_PASSWORD` (the root password comes from that environment variable; if it is unset, `mysql.ps1` falls back to a throwaway test-container password written in the code), `sanitizeCredentials`. Has no `iteration` number, so its report is `MigrationVerificationReport-mysql.docx`. Needs Docker Desktop |

## Layout

```
dbmigrate.cmd                       wrapper (CRLF): powershell -NoProfile -ExecutionPolicy Bypass -File migration\DbMigrate.ps1
migration\DbMigrate.ps1             command line, dispatcher, exit codes
migration\Common.ps1                config, SQL Server catalog -> neutral model, canonical values, hashing, process runner,
                                    Protect-SensitiveData
migration\Export.ps1                export, and Get-TargetPaths (output and report file names)
migration\Import.ps1                import
migration\Verify.ps1                verify (results JSON, console summary)
migration\SelfTest.ps1              selftest
migration\Report.ps1                Word verification report (OpenXML written directly, charts drawn with System.Drawing)
migration\Guide.ps1                 Word database guide (sqlite targets)
migration\dialects\sqlite.ps1       SQLite dialect (runner mode `local` here)
migration\dialects\mysql.ps1        MySQL dialect (Docker)
migration\migration.config.json     settings
01-schema.sql, 02-data-sanitized.sql, masterantique.sqlite, import-log.txt,
verification-results.json, selftest-results.json      outputs (checked in; no credentials)
README.md                           lives in docs/phase1/dbmigrate/iteration1/ (for people)
```

The repository root is found by counting folders up from the script: `migration\Common.ps1` uses `'..\..\..\..\..'` (five
levels up from `tools\phase1\dbmigrate\iteration1\migration`). Fix that count if this folder moves. `dbmigrate.cmd` comments
and the help text in `DbMigrate.ps1` name the folder too.

## How the tool works

### export

`Invoke-Export` (`Export.ps1`):

1. Reads the SQL Server catalog (`sys.tables`, `columns`, `indexes`, `foreign_keys`, `default_constraints`, `identity_columns`)
   into a neutral model: tables (all of `dbo` except `__MigrationHistory`, which is Entity Framework bookkeeping), columns
   (type, length, nullability, identity, default), primary key, indexes with their filter, foreign keys with their delete
   action. Tables are ordered by Kahn's topological sort with an alphabetical tie-break, so parents load before children.
2. Reads every row in primary-key order into canonical text: dates `yyyy-MM-dd HH:mm:ss.fffffff`, bits `1`/`0`, NULL stays
   `$null` (never turned into an empty string).
3. **Sanitizes**: `Protect-SensitiveData` (`Common.ps1`) mutates the in-memory model and rows of `Users` only: `PasswordHash`
   and `SecurityStamp` become NULL in every row and a synthetic column `MustResetPassword` (bit, not null, default 0) is
   appended and set to `1`. Because the dialect renders SQL only from the model and rows, the new column appears in the
   schema and data automatically and the dialects never know about sanitizing. The names are hardcoded (`Users`,
   `PasswordHash`, `SecurityStamp`); a `Users` table without those columns is an error.
4. The dialect renders `01-schema.sql` and the data file; the file is named `02-data-sanitized.sql` when the target has
   `sanitizeCredentials`, else `02-data.sql`. Both are written with `Write-TextFile` (UTF-8 without BOM, LF).

The SQLite rendering: identifiers double-quoted in their source case, `dbo.` dropped; whole-number types `INTEGER`; `bit`
`INTEGER` with `CHECK (col IN (0,1))`; `nvarchar(n)` `VARCHAR(n)`, `(max)` `TEXT`; `datetime` `DATETIME` holding ISO text;
`varbinary` `BLOB` (`X'…'`); a single-column identity primary key `INTEGER PRIMARY KEY AUTOINCREMENT`, composite keys a table
constraint. Foreign keys are declared inside `CREATE TABLE` (SQLite cannot add them later) with their delete action kept.
The filtered unique index `IX_Users_Name_Active` becomes a native partial index (`WHERE "DeletedAt" IS NULL`); the filter
translator accepts only `[col] IS [NOT] NULL` shapes and throws on anything else. Index names that repeat across tables
(`IX_UserId` exists on five) get the table name as a prefix, because SQLite index names are database-wide. Data is
multi-row `INSERT`s (100 rows per statement, explicit column lists, primary-key order) between `PRAGMA foreign_keys=OFF; BEGIN;`
and `COMMIT; PRAGMA foreign_keys=ON; PRAGMA foreign_key_check;`, with `sqlite_sequence` set from the source's identity
`last_value`. Strings are `'…'` with `''` doubling; a string containing NUL is rejected; control characters other than TAB and LF
are written as `char(n)` expressions (see Gotchas).

### import

`Invoke-Import`: refuses (exit 3) if the `.sqlite` file exists and `--recreate` was not given (`all` implies it; only that one
file is deleted). Runs `01-schema.sql`, then the data file, through `sqlite3 -bail` with the SQL piped in as UTF-8 bytes on
stdin (`System.Diagnostics.Process`, stdout and stderr read asynchronously so a full pipe cannot deadlock), then
`PRAGMA integrity_check` (must be `ok`) and `PRAGMA foreign_key_check` (must be empty). Writes `import-log.txt`.

### verify

`Invoke-Verify` reads the source and the database independently and writes `verification-results.json`. It exits 1 on any
failure. The 42 checks:

| Category (count) | What is checked |
|---|---|
| table counts (8) | rows per table, source versus SQLite |
| table content (8) | per table, every cell of every row (compared by primary key, then field by field) and a SHA-256 over all rows, both sides equal |
| Schema (8) | tables; columns (name, order, type, NOT NULL, primary-key position, default); primary key columns; foreign keys (column, target, delete action); indexes (name, unique, partial); index columns; partial-index filters; auto-increment tables |
| Integrity (2) | `PRAGMA integrity_check`; `PRAGMA foreign_key_check` |
| summaries (10) | one SQL text run on both engines (double-quoted identifiers work in both), rows sorted ordinally, compared: users by type, active vs soft-deleted, users per role, tickets by state, assigned vs unassigned, audit events by action, comments per ticket, comment and ticket totals, ticket date ranges, account and audit date ranges |
| Behaviour (5) | on a temporary copy of the database, so the delivered file is untouched: duplicate active username rejected; reusing a soft-deleted username allowed; orphan foreign key rejected; a yes/no column rejects values other than 0/1; a new `Roles` row gets the previous maximum id + 1 |
| Sanitization (1) | no `Users` row has a `PasswordHash` or `SecurityStamp`, and every row has `MustResetPassword = 1` |

**How sanitizing is verified:** `Verify.ps1` calls the same `Protect-SensitiveData` on the freshly read source rows, so both
sides of every comparison are sanitized identically. The generic row-by-row comparison then proves that every column except
the two credential columns is unchanged, and no special case is needed. The Sanitization check asserts the database itself.

**Canonical cell form:** each cell is compared as the SQLite storage class (`i` integer for int and bit, `t` text, `b` blob;
proven by `typeof()`) `:` the hex of its UTF-8 text (SQLite's own `hex()` for blobs); NULL is `~`. Hex means line breaks,
tabs, quotes and emoji cannot break the parsing, and NULL is distinct from the empty string. A table's hash is the SHA-256 of its
sorted cell lines joined by LF.

The results JSON also records the tool versions, the export files' SHA-256, the database fingerprint, the git commit and
`RunTimeUtc` (the only non-deterministic field).

### selftest

`Invoke-SelfTest` proves the tool: (1) a second export into a temporary folder is byte-identical (schema and data); (2) a
database imported from that second export equals the delivered one according to `sqldiff` (the engine's own tool, not ours);
(3) a scratch copy with one comment's text changed and the last ticket deleted makes `verify` fail, naming
`Comments` / `Id=<n>` / `Text` and `Tickets` / `Id=<n>` / `(row)` `MISSING`. Six tests (2 determinism, 1 `sqldiff`, 3 negative),
written to `selftest-results.json`. Scratch databases and the temporary folder are removed afterwards.

### report and guide

`Invoke-Report` builds `MigrationVerificationReport1.docx` from `verification-results.json` alone (the file name comes from
the target's `iteration` setting): OpenXML written directly through `System.IO.Compression`, no copy of Word needed, charts
drawn with `System.Drawing`, a fixed zip order so the same JSON always gives the same bytes. `Invoke-Guide` builds
`SQLiteDatabaseGuide1.docx` from the live database file (schema, value meanings, example queries), so it cannot drift from it;
it never queries or prints credential columns. Report and guide text about sanitizing depends on the target's
`sanitizeCredentials` setting.

## Contracts

- Input: the live SQL Server database named in the settings, Windows authentication, read-only (`SqlLocalDB.exe start` is run first
  as a cold-start guard).
- Output `01-schema.sql`, `02-data-sanitized.sql`: plain SQLite SQL, UTF-8 without BOM, LF. Byte-identical to iteration 2's
  files (same source, same rules); no other iteration reads this folder.
- Output `masterantique.sqlite`: checked in, contains no credentials (`Users`: 12 rows, no hash, no stamp, `MustResetPassword` 1).

## Gotchas

- **Control characters are written as `char(n)`**: the Windows `sqlite3` shell reads stdin in text mode, which rewrites CRLF to
  LF inside a string value and treats Ctrl-Z as end of input. Raw bytes changed one comment by one byte; the row-by-row
  verification named the table, row and column. This also makes git line-ending conversion harmless for the data file.
- **Query output shape is set with CLI flags (`-list -separator |`)**, not with `.mode`/`.separator` sent on stdin: sqlite3
  3.53.4 does not parse dot-commands reliably in the same stdin write as the query.
- **NULL must stay distinct from the empty string** all the way through (`$null` in the model, `~` in the canonical form, `NULL`
  in the SQL). Turning NULL into `''` once produced a malformed statement and would hide real differences.
- **Column defaults are exported, and an untranslatable default is an error.** Five columns have defaults; they were once only
  warned about and lost.
- **Use the 64-bit SQLite tools.** A 32-bit `sqlite3.dll` cannot be loaded by 64-bit PowerShell, and the CLI is simpler than
  native interop anyway.
- **`Protect-SensitiveData` appends a column to the model in place**, so it must run exactly once per table per process
  (Export once; Verify once per table it reads). Calling it twice adds `MustResetPassword` twice.
- **Expect exactly the hashes of a clean run to change only where the data changed.** Users' fingerprint differs from an
  unsanitized run by design; every other table's fingerprint equals iteration 2's.

## Testing changes

- Run `all --target sqlite` and compare with the numbers above; `01-schema.sql`, `02-data-sanitized.sql` and
  `masterantique.sqlite` must be byte-identical to the checked-in ones unless the change was meant to alter them
  (`verification-results.json` differs only in `RunTimeUtc`, `GitCommit` and `TargetLocation`).
- **Stress test with awkward data** after a change to rendering, reading or hashing: temporarily add rows to the source with line
  breaks, tabs, backslashes, quotes, emoji, Chinese and Japanese text, an empty text, NULLs, a date in the year 9999, and a
  soft-deleted user with an accented name; run `all` and require every row identical; then delete the rows and restore the
  auto-number counters (`DBCC CHECKIDENT`) so the source is back to 155 rows.
- **Negative test for a new check:** damage a copy (`selftest` does this for comments and tickets) or put a fake hash in a copy's
  `Users` row and confirm the check fails and names the row.
- Regression: iteration 2's copy must be re-run after a change that also applies to it.

## Known limits

- Sanitizing is hardcoded to `Users.PasswordHash`, `Users.SecurityStamp` and the added `MustResetPassword` column. A
  config-driven per-table list of sensitive columns is not built (DATA_MIGRATION.md §5.2.5, §6).
- Nothing prevents setting `sanitizeCredentials` to `false` (iteration 4 refuses to run that way; this tool does not).
- SQLite has no date type (ISO text), does not enforce text lengths, and compares text case-sensitively; new rows inserted
  directly are not protected against case-only duplicate usernames.
- The SQLite build (3.53.4) is Windows-specific; database files may differ byte-wise from a Linux build while holding identical content.
- The MySQL target has not been run since sanitizing was added; its last recorded run was 44 of 44 checks without it.
- No `.gitattributes` in this folder (iteration 4 has one); line endings rely on the tool writing LF and on `char(n)` escapes.
