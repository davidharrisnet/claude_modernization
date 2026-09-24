# Iteration 4 — instructions for Claude Code

This folder is the iteration 4 tool: it exports the MasterAntiqueRepair database from SQL Server LocalDB into sanitized
**PostgreSQL** schema and data files plus a metadata record, and builds a Word export report. It is export only: no Docker,
no PostgreSQL, no target database. The human description is `docs/phase1/dbmigrate/iteration4/README.md`; a shorter how-to
for people is `README.md` in this folder; the strategy and security policy for all iterations is
`docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5 security, §7 why the export is PostgreSQL-specific, §8 the shared decisions —
numbered 1–4, 2b, 8, 11, 12, 14 for this iteration; the full decision log is §8.8, do not repeat or reopen it here). The Linux side that
loads and verifies these files is iteration 5: `tools/phase1/dbmigrate/iteration5/CLAUDE.md`.

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
   SQL), so iteration 5 can use it as a real check of the renderer and the load. Do not derive it from the SQL text.
6. **Never guess.** A source table, column, index or type with no mapping, and an index filter or default that cannot be translated,
   is a hard error (exit 2) naming what is missing. Add the mapping; never work around it.
7. **The export is deterministic**: sorted metadata, invariant culture, UTF-8 without BOM, LF newlines. Two exports of unchanged data
   are byte-identical apart from the metadata's `run` section (the self-test checks it).
8. **Hand-off rule:** after a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json`
   unchanged into `tools\phase1\dbmigrate\iteration5\input\` and tell the user to commit both folders together. If the two SQL files
   changed, say so first: iteration 5's input needs refreshing and iteration 5 must be repeated on Linux. If only the metadata's
   `run` section changed, iteration 5's copy is still valid (it checks the SQL files' hashes) but differs from this folder's.
9. **Generated files are never edited by hand**: `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`,
   `selftest-results.json`, `docs/phase1/dbmigrate/iteration4/MigrationExportReport4.docx`.
10. **A rendering bug found by iteration 5 is fixed here** (`migration\dialects\postgres.ps1`), then the export is repeated and handed
    off again; never patch iteration 5's `input\`.
11. **Do not commit.** The user reviews `git status` and commits.

## Run

From the repository root, in a command prompt, with the legacy application's LocalDB database available:

```
tools\phase1\dbmigrate\iteration4\dbmigrate4.cmd all --target postgres
```

Expected: `Exported 8 tables (credentials sanitized)` with 155 rows, nine `PASS` self-test lines, `SELF-TEST PASSED`, then the report path
(`MigrationExportReport4.docx`, about 54 KB); exit 0. Commands: `export`, `selftest`, `report [--out <file>]`, `all` (export, self-test,
report). `--config <path>` replaces the settings file. Exit codes: 0 ok, 1 self-test differences, 2 configuration, tool or connection
error (including the refusal to export unsanitized data), 3 refused. After a successful run, update the "Latest results" section of
the docs README if any number or the date changed, then do the hand-off (rule 8).

## Settings

`migration\migration.config.json` (paths relative to the repository root): `source` (`server` `(localdb)\MSSQLLocalDB`, `database`
`aspnet-MasterAntiqueRepair-e93a6129-…`), `outputDir` `tools/phase1/dbmigrate`, and one target `postgres`: `dialect` `postgres`,
`iteration` 4, `iterationTitle`, `outputSubdir` `iteration4`, `reportDir` `docs/phase1/dbmigrate/iteration4`, `reportFile`
`MigrationExportReport4.docx`, `sanitizeCredentials` `true`, `caseInsensitiveUniqueIndexes` `[{ "table": "Users", "column": "Name" }]`
(the unique index on that column is built on `lower(name)`).

## Layout

```
dbmigrate4.cmd                      wrapper (CRLF)
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
from `tools\phase1\dbmigrate\iteration4\migration`). Fix that count if this folder moves.

## How the tool works

### export

`Invoke-Export` (`Export.ps1`): refuses if `sanitizeCredentials` is off; reads the SQL Server catalog into the model and every row into
canonical text (as in iteration 1's tool, `iteration1/CLAUDE.md`), plus the ten business summaries and `@@VERSION`; keeps every original credential
value **in memory only** for the self-test's leak check; runs `Protect-SensitiveData` (`PasswordHash` and `SecurityStamp` become
NULL, a synthetic column `MustResetPassword` is appended and is `1` for every user); renders the schema and data through the
dialect; builds the metadata; writes the three files (UTF-8 without BOM, LF). `__MigrationHistory` is excluded on purpose (Entity
Framework bookkeeping).

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

`report` builds `MigrationExportReport4.docx` from `source-metadata.json` alone (`ExportReport.ps1`, helpers in `Report.ps1`): OpenXML written
directly, charts drawn with `System.Drawing`, a fixed zip order, so the same metadata always gives the same bytes. Sections: executive
summary with an EXPORT COMPLETE banner, scope and method, results at a glance, table inventory, schema (source-to-target names and types),
business summaries with charts, credential sanitization, known differences and exclusions, reproducibility and hand-off, appendix with the
full row hashes. It carries no verification PASS/FAIL against a target.

## Contracts

- **`source-metadata.json`** (`schemaVersion` 1; iteration 5's `verify.sql` reads exactly this, so a change here is a change there):
  `meta` (`iteration`, `description`, `source` server/database/version, `minPostgresVersion` 15, `schemaFile`/`schemaSha256`,
  `dataFile`/`dataSha256` — SHA-256 of the LF files, `sanitizeCredentials`); `canonicalForm`; `tables[]` in load order (`sourceName`,
  `targetName`, `rowCount`, `identityLast`, `rowSha256`, `columns[]` with `sourceName`, `sourceType`, `kind`, `targetName`, `targetType`,
  `dataType`, `maxLength`, `nullable`, `default`, `identity`, `synthetic`; `primaryKey[]`; `foreignKeys[]`; `indexes[]` with `columns[]` of
  `column`/`expression`/`descending` and `filter`); `summaries[]` (`name`, `sourceSql` — documentation only, never executed —
  `expectedRows`); `expectations` (`totalRows` 155, `usersSanitized`, `usersCount` 12, `noDuplicateActiveUsernamesIgnoringCase`);
  `renameMap`; `excludedTables`; `knownDifferences`; `run` (`runTimeUtc`, `toolGitCommit`: the only non-deterministic part). It contains no
  credentials, personal data, raw comment text or executable SQL.
- **Canonical row form (must match iteration 5's `verify.sql` byte for byte):** cells joined by `|` in column order; NULL `~`; `i:<decimal>`,
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
- **Rule-test inserts on PostgreSQL must give explicit high ids** (see iteration 5): `nextval` is never rolled back, so tests using the identity
  default move the sequences permanently.
- **Usernames are stored as typed**; authentication in Phase 2 must compare `lower(name) = lower(:input)` or the `lower()` index is not used and the
  case rule is not honoured. Email has no database rule (the legacy schema has none; the column is NULL in every row).
- **After pruning or copying the tooling, check `Get-Dialect` still exists in `Common.ps1`** (a trimmed copy once lost it).

## Testing changes

- Run `all --target postgres`: exit 0, self-test 9 of 9, three files rewritten. `git diff` must show `01-schema.sql` and `02-data-sanitized.sql`
  unchanged unless the change was meant to alter them, and `source-metadata.json` changed only in `run`.
- After a change to rendering, the formal proof is iteration 5 on Linux with the new files. Windows cannot prove that PostgreSQL accepts the SQL.
- After adding a source column or table, expect the export to stop naming the missing rename-map entry; add it, then re-run.

## Known limits

- The load into PostgreSQL is not proven on Windows; that is iteration 5.
- Timestamps carry no time zone and the source zone (UTC or local) is unknown; no conversion is made.
- The metadata is produced by the same run as the SQL: it catches mistakes, not tampering.
- The files contain sanitized but real project data (usernames, timestamps, comment text).
- The export report was checked structurally (15 package parts, well-formed XML, five images referenced), not rendered page by page in Word.
