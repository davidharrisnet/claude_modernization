# export-postgresql — instructions for Claude Code

This folder is the export-postgresql tool: it exports the MasterAntiqueRepair database from SQL Server LocalDB into sanitized
**PostgreSQL** schema and data files plus a metadata record, and builds a Word export report. It runs when the user says
**`Run export-postgresql`**. It is export only: no Docker, no PostgreSQL, no target database. The human description is
`docs/phase1/dbmigrate/export-postgresql/README.md`; a shorter how-to for people is `README.md` in this folder; the strategy and
security policy for the database migration is `docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5 security, §7 why the export is
PostgreSQL-specific, §8 the decisions; the full decision log is §8.8, do not repeat or reopen it here). The Linux side that loads
and verifies these files is import-postgresql: `tools/phase1/dbmigrate/import-postgresql/CLAUDE.md`.

## Rules

1. **Windows only, from a plain command prompt.** The export needs the live SQL Server LocalDB and Windows PowerShell 5.1.
2. **Credentials are sanitized in memory before anything is rendered**, and the tool **refuses to run** with `sanitizeCredentials`
   false (exit 2). Why: a raw export was once committed (DATA_MIGRATION.md §5.1), so an unsanitized file must never be
   producible by this tool. Never weaken that check.
3. **Only identifiers are lowercased, never data.** Comment text, descriptions, role names, usernames and emails are stored exactly
   as in the source; the fidelity claim is "every column identical except credentials". Why: lowercasing a username loses the case
   the user typed.
4. **The SQL carries no environment details**: no database name, owner, schema name or password.
5. **The metadata comes from a different code path than the SQL** (the source catalog and the same in-memory rows, not the rendered
   SQL), so import-postgresql can use it as a real check of the renderer and the load. Do not derive it from the SQL text.
6. **Never guess.** A source table, column, index or type with no mapping, and an index filter or default that cannot be translated,
   is a hard error (exit 2) naming what is missing. Add the mapping; never work around it.
7. **The export is deterministic**: sorted metadata, invariant culture, UTF-8 without BOM, LF newlines. Two exports of unchanged data
   are byte-identical apart from the metadata's `run` section (the self-test checks it).
8. **Hand-off rule:** after a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json`
   unchanged into `tools\phase1\dbmigrate\import-postgresql\input\` and tell the user to commit both folders together. If the two SQL files
   changed, say so first: import-postgresql's input needs refreshing and `Run import-postgresql` must be repeated on Linux. If only the
   metadata's `run` section changed, import-postgresql's copy is still valid (it checks the SQL files' hashes) but differs from this folder's.
9. **Generated files are never edited by hand**: `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`,
   `selftest-results.json`, `docs/phase1/dbmigrate/export-postgresql/MigrationExportReport.docx`.
10. **A rendering bug found by import-postgresql is fixed here** (`migration\dialects\postgres.ps1`), then the export is repeated and handed
    off again; never patch import-postgresql's `input\`.
11. **Do not commit.** The user reviews `git status` and commits.
12. **The source is only read.** The one exception is a deliberate stress test (see "Testing changes"), which must remove what it
    added and restore the auto-number counters.

## Run

From the repository root, in a command prompt, with the legacy application's LocalDB database available:

```
tools\phase1\dbmigrate\export-postgresql\export-postgresql.cmd all --target postgres
```

Expected: `Exported 8 tables (credentials sanitized)` with 155 rows, nine `PASS` self-test lines, `SELF-TEST PASSED`, then the report path
(`MigrationExportReport.docx`, about 54 KB); exit 0. Commands: `export`, `selftest`, `report [--out <file>]`, `all` (export, self-test,
report). `--config <path>` replaces the settings file. Exit codes: 0 ok, 1 self-test differences, 2 configuration, tool or connection
error (including the refusal to export unsanitized data), 3 refused. After a successful run, update the "Latest results" section of
the docs README if any number or the date changed, then do the hand-off (rule 8).

## Settings

`migration\migration.config.json` (paths relative to the repository root): `source` (`server` `(localdb)\MSSQLLocalDB`, `database`
`aspnet-MasterAntiqueRepair-e93a6129-…`), `outputDir` `tools/phase1/dbmigrate`, and one target `postgres`: `dialect` `postgres`,
`outputSubdir` `export-postgresql`, `reportDir` `docs/phase1/dbmigrate/export-postgresql`, `reportFile`
`MigrationExportReport.docx`, `sanitizeCredentials` `true`, `caseInsensitiveUniqueIndexes` `[{ "table": "Users", "column": "Name" }]`
(the unique index on that column is built on `lower(name)`).

## Layout

```
export-postgresql.cmd               wrapper (CRLF)
migration\DbMigrate.ps1             command line, dispatcher, exit codes
migration\Common.ps1                config, SQL Server catalog -> model, canonical values, hashing, Protect-SensitiveData
migration\Export.ps1                export, Get-TargetPaths, the refusal, the in-memory credential list for the self-test
migration\Metadata.ps1              source-metadata.json, business summaries, canonical row form and hash
migration\SelfTest.ps1              selftest
migration\Report.ps1                OpenXML and chart helpers
migration\ExportReport.ps1          the export report, built from source-metadata.json
migration\dialects\postgres.ps1     PostgreSQL dialect: rename map, types, rendering (renders text only, never connects)
migration\migration.config.json     settings
01-schema.sql, 02-data-sanitized.sql, source-metadata.json, selftest-results.json      outputs (checked in)
README.md                           how to run it, for people
.gitattributes                      *.sql, *.json, *.ps1, *.md pinned to LF; *.cmd to CRLF
```

The repository root is found by counting folders up from the script: `migration\Common.ps1` uses `'..\..\..\..\..'` (five levels up
from `tools\phase1\dbmigrate\export-postgresql\migration`). Fix that count if this folder moves.

## How the tool works

### export

`Invoke-Export` (`Export.ps1`): refuses if `sanitizeCredentials` is off; reads the SQL Server catalog (`sys.tables`, `columns`, `indexes`,
`foreign_keys`, `default_constraints`, `identity_columns`) into a neutral model: tables (all of `dbo` except `__MigrationHistory`, Entity
Framework bookkeeping, excluded on purpose), columns (type, length, nullability, identity, default), primary key, indexes with their
filter, foreign keys with their delete action. Tables are ordered by Kahn's topological sort with an alphabetical tie-break, so parents
load before children. Every row is read in primary-key order into canonical text: dates as `yyyy-MM-dd HH:mm:ss.fff`, bits as `1`/`0`,
NULL stays `$null` (never turned into an empty string). The ten business summaries and `@@VERSION` are read too. Every original
credential value is kept **in memory only** for the self-test's leak check. `Protect-SensitiveData` then runs: `PasswordHash` and
`SecurityStamp` become NULL, a synthetic column `MustResetPassword` is appended and is `1` for every user. The dialect renders the
schema and data from the model and rows alone, so it never knows about sanitizing. The metadata is built, and the three files are written
(UTF-8 without BOM, LF).

### Names

`postgres.ps1` holds an **explicit rename map** (`New-PgNameMap`), not an algorithm (one would mishandle acronyms): every table and
column, and every index. Lowercase-only names map to themselves (`Id`→`id`). Lookups (`Pg-Table`, `Pg-Column`, `Pg-IndexName`) throw
naming the missing entry, so a new source column is never silently renamed differently. All identifiers are unquoted in the output;
`timestamp`, `text`, `action`, `state`, `name` and `description` are legal unquoted column names on PostgreSQL 15+.
- Foreign keys: `fk_<table>_<reftable>_<columns joined by _>` in target names (`fk_tickets_users_customer_id`); this replaces the source
  names, which contain dots and a stale table name.
- Indexes: the model's `TargetName` (the source name, prefixed with the table where source names collided, e.g. `IX_UserId` exists on five tables) mapped to
  `ix_<table>_<columns>`: `RoleNameIndex`→`ix_roles_name`, `IX_Users_Name_Active`→`ix_users_name_active`, `IX_Customer_Id`→`ix_tickets_customer_id`, `IX_RoleId`→`ix_user_roles_role_id`, etc. Index and constraint names are schema-wide in
  PostgreSQL and must not collide.

### Types

| Source kind | PostgreSQL | Notes |
|---|---|---|
| `int` identity, single-column primary key | `INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY` | any other identity shape is an error |
| `int` / `bigint` / `smallint` / `tinyint` | `INTEGER` / `BIGINT` / `SMALLINT` / `SMALLINT` | |
| `bit` | `BOOLEAN` | default `0`/`1` becomes `FALSE`/`TRUE`; literals `true`/`false` |
| `datetime` | `TIMESTAMP` (no time zone) | literal `'yyyy-MM-dd HH:mm:ss.fff'`; the source has millisecond precision |
| `nvarchar(n)` | `VARCHAR(n)` | |
| `nvarchar(max)`, `text`, `ntext` | `TEXT` | |
| `varbinary` / `uniqueidentifier` | `BYTEA` / `UUID` | not present in this schema |

Anything else, and a default on a datetime, binary or guid column, is an error.

### Schema file

Header comment, `BEGIN;`, one `CREATE TABLE` per table in dependency order (Kahn's topological sort, alphabetical tie-break) with inline
`CONSTRAINT … FOREIGN KEY … ON DELETE CASCADE|NO ACTION` (sorted by name), composite primary keys as table constraints (`user_logins`,
`user_roles`), then the indexes sorted by name, `COMMIT;`. `ix_users_name_active` is a unique **partial expression index** on
`lower(name)` `WHERE deleted_at IS NULL` (soft delete frees the username; case-insensitive because SQL Server compared case-insensitively);
`ix_roles_name` is a plain, case-sensitive unique index (roles are created only by the program). Filters are translated only for
`[col] IS [NOT] NULL` shapes (AND-ed); anything else is an error so a rule is never silently dropped.

### Data file

Header, `SET client_encoding = 'UTF8'; SET standard_conforming_strings = on;`, `BEGIN;`, per table in dependency order multi-row
`INSERT INTO t (cols) VALUES …` (100 rows per statement, explicit column lists, primary-key order), then for each identity table
`SELECT setval(pg_get_serial_sequence('t','id'), <IdentityLast>);`, `COMMIT;`. Strings: `'…'` with `''` doubling; a NUL is rejected; every
control character except TAB and LF (notably CR) is written as `chr(n)` concatenation. Booleans `true`/`false`, NULL as `NULL`.

### selftest

`Invoke-SelfTest` needs the live source and a previous export; writes `selftest-results.json` (exit 1 if any test fails). Nine tests: a
second export into a temporary folder has a byte-identical schema, data and metadata (the whole `run` section aside); no credential value
read from the source (values of 8+ characters; 24 in the last run) appears in any of the six output files of the two exports; the tool refuses
to export with `sanitizeCredentials` off (exit 2, tested on a modified copy of the config); every table's `rowCount` equals a live
`COUNT(*)`; the total equals `expectations.totalRows`; the metadata's expectations hold (users sanitized, no duplicate active username
ignoring case); the export report built twice from the same metadata is byte-identical. The last detail line of the results holds the
report's hash, which changes whenever the metadata's `run` section does.

### report

`report` builds `MigrationExportReport.docx` from `source-metadata.json` alone (`ExportReport.ps1`, helpers in `Report.ps1`): OpenXML written
directly, charts drawn with `System.Drawing`, a fixed zip order, so the same metadata always gives the same bytes. Sections: executive
summary with an EXPORT COMPLETE banner, scope and method, results at a glance, table inventory, schema (source-to-target names and types),
business summaries with charts, credential sanitization, known differences and exclusions, reproducibility and hand-off, appendix with the
full row hashes. It carries no verification PASS/FAIL against a target.

## Contracts

- **`source-metadata.json`** (`schemaVersion` 1; import-postgresql's `verify.sql` reads exactly this, so a change here is a change there):
  `meta` (`tool`, `description`, `source` server/database/version, `minPostgresVersion` 15, `schemaFile`/`schemaSha256`,
  `dataFile`/`dataSha256` — SHA-256 of the LF files, `sanitizeCredentials`); `canonicalForm`; `tables[]` in load order (`sourceName`,
  `targetName`, `rowCount`, `identityLast`, `rowSha256`, `columns[]` with `sourceName`, `sourceType`, `kind`, `targetName`, `targetType`,
  `dataType`, `maxLength`, `nullable`, `default`, `identity`, `synthetic`; `primaryKey[]`; `foreignKeys[]`; `indexes[]` with `columns[]` of
  `column`/`expression`/`descending` and `filter`); `summaries[]` (`name`, `sourceSql` — documentation only, never executed —
  `expectedRows`); `expectations` (`totalRows` 155, `usersSanitized`, `usersCount` 12, `noDuplicateActiveUsernamesIgnoringCase`);
  `renameMap`; `excludedTables`; `knownDifferences`; `run` (`runTimeUtc`, `toolGitCommit`: the only non-deterministic part). It contains no
  credentials, personal data, raw comment text or executable SQL.
- **Canonical row form (must match import-postgresql's `verify.sql` byte for byte):** cells joined by `|` in column order; NULL `~`; `i:<decimal>`,
  `b:1|0`, `t:yyyy-MM-dd HH:mm:ss.fff`, `s:<lowercase hex of UTF-8>` (`x:` binary, `g:` guid); rows **sorted ascending by their own canonical
  text in byte order** (no primary-key or collation knowledge needed; `COLLATE "C"` in SQL), joined by LF, SHA-256 lowercase hex; an empty
  table hashes the empty string (`e3b0c442…`); sanitized columns hash as `~`, so no credential is ever hashed.
- **Summary rows:** cells joined by `|`, NULL as the empty string, timestamps as above, booleans 1/0, sorted in byte order.
- Outputs `01-schema.sql` and `02-data-sanitized.sql`: PostgreSQL 15+ SQL, UTF-8 without BOM, LF.

## Gotchas

- **Rows are sorted by their canonical text, not by primary key.** A string primary key would sort differently in SQL Server and PostgreSQL
  (collations).
- **The git commit and run time live in `run`, not `meta`.** Recording the commit in `meta` made the metadata differ after every commit; the
  determinism test ignores `run`.
- **Pin line endings** (`.gitattributes`): the metadata records the hashes of the LF form and string literals may contain raw LF; git
  conversion on Windows would break both the transfer check and the data. CR in data is written as `chr(13)` for the same reason.
- **NULL must stay distinct from the empty string** all the way through (`$null` in the model, `~` in the canonical form, `NULL` in the
  SQL). Turning NULL into `''` once produced a malformed statement and would hide real differences.
- **`Protect-SensitiveData` appends a column to the model in place**, so it must run exactly once per table per process. Calling it twice
  adds `MustResetPassword` twice. Its names (`Users`, `PasswordHash`, `SecurityStamp`) are hardcoded; a `Users` table without those
  columns is an error.
- **Column defaults are exported, and an untranslatable default is an error.** Defaults were once only warned about and lost.
- **Rule-test inserts on PostgreSQL must give explicit high ids** (see import-postgresql): `nextval` is never rolled back, so tests using the identity
  default move the sequences permanently.
- **Usernames are stored as typed**; authentication in Phase 2 must compare `lower(name) = lower(:input)` or the `lower()` index is not used and the
  case rule is not honoured. Email has no database rule (the legacy schema has none; the column is NULL in every row).
- **After pruning or copying the tooling, check `Get-Dialect` still exists in `Common.ps1`** (a trimmed copy once lost it).

## Testing changes

- Run `all --target postgres`: exit 0, self-test 9 of 9, three files rewritten. `git diff` must show `01-schema.sql` and `02-data-sanitized.sql`
  unchanged unless the change was meant to alter them, and `source-metadata.json` changed only in `run`.
- After a change to rendering, the formal proof is `Run import-postgresql` on Linux with the new files. Windows cannot prove that PostgreSQL accepts the SQL.
- After adding a source column or table, expect the export to stop naming the missing rename-map entry; add it, then re-run.
- **Stress test with awkward data** after a change to rendering, reading or hashing: temporarily add rows to the source with line breaks,
  tabs, backslashes, quotes, emoji, Chinese and Japanese text, an empty text, NULLs, a date in the year 9999 and a soft-deleted user with an
  accented name; run `all` and load the result with import-postgresql on Linux, requiring every row identical; then delete the rows and
  restore the auto-number counters (`DBCC CHECKIDENT`) so the source is back to 155 rows.
- **Negative test for a new self-test check:** damage a copy of an output (or put a fake hash in a `Users` row) and confirm the check fails
  and names it.

## Known limits

- The load into PostgreSQL is not proven on Windows; that is import-postgresql.
- Sanitizing is hardcoded to `Users.PasswordHash`, `Users.SecurityStamp` and the added `MustResetPassword` column; a config-driven list of
  sensitive columns is not built (DATA_MIGRATION.md §5.2.5, §6).
- Timestamps carry no time zone and the source zone (UTC or local) is unknown; no conversion is made.
- The metadata is produced by the same run as the SQL: it catches mistakes, not tampering.
- The files contain sanitized but real project data (usernames, timestamps, comment text).
- The export report was checked structurally (15 package parts, well-formed XML, five images referenced), not rendered page by page in Word.
