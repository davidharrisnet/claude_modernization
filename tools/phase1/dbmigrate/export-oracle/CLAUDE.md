# export-oracle — instructions for Claude Code

This folder is the export-oracle tool: it exports the MasterAntiqueRepair database from SQL Server LocalDB into sanitized
**Oracle** (AI Database 26ai) schema and data files plus a metadata record, and builds a Word export report. It runs when the user
says **`Run export-oracle`**. It is export only: no Docker, no Oracle, no target database. It is a proof of concept alongside the
PostgreSQL path (Phase 2 stays on PostgreSQL). It is a self-contained copy of `tools/phase1/dbmigrate/export-postgresql/` with one
different dialect file, `migration\dialects\oracle.ps1`; a fix to shared code (reading the source, sanitizing, canonical form,
report helpers) usually has to be made in both copies. The human description is `docs/phase1/dbmigrate/export-oracle/README.md`; a
shorter how-to for people is `README.md` in this folder; the strategy and security policy is `docs/phase1/dbmigrate/DATA_MIGRATION.md`
(§5 security, §7 why the export is database-specific, §10 the Oracle decisions). The Linux side that loads and verifies these files is
import-oracle: `tools/phase1/dbmigrate/import-oracle/CLAUDE.md`.

## Rules

1. **Windows only, from a plain command prompt.** The export needs the live SQL Server LocalDB and Windows PowerShell 5.1.
2. **Credentials are sanitized in memory before anything is rendered**, and the tool **refuses to run** with `sanitizeCredentials`
   false (exit 2). Why: a raw export was once committed (DATA_MIGRATION.md §5.1), so an unsanitized file must never be
   producible by this tool. Never weaken that check.
3. **Only identifiers are lowercased, never data.** Comment text, descriptions, role names, usernames and emails are stored exactly
   as in the source; the fidelity claim is "every column identical except credentials". Why: lowercasing a username loses the case
   the user typed.
4. **The SQL carries no environment details**: no database name, owner, schema name, service name or password.
5. **The metadata comes from a different code path than the SQL** (the source catalog and the same in-memory rows, not the rendered
   SQL), so import-oracle can use it as a real check of the renderer and the load. Do not derive it from the SQL text.
6. **Never guess.** A source table, column, index or type with no mapping, an index filter or default that cannot be translated, a
   delete action Oracle cannot express, a binary or uniqueidentifier column, an identifier that is an Oracle reserved word, and a
   string value that is empty are all hard errors (exit 2) naming what is wrong. Add the mapping or ask the data owner; never work
   around it.
7. **The export is deterministic**: sorted metadata, invariant culture, UTF-8 without BOM, LF newlines. Two exports of unchanged data
   are byte-identical apart from the metadata's `run` section (the self-test checks it).
8. **Hand-off rule:** after a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json`
   unchanged into `tools\phase1\dbmigrate\import-oracle\input\` and tell the user to commit both folders together. If the two SQL
   files changed, say so first: import-oracle's input needs refreshing and `Run import-oracle` must be repeated on Linux. If only the
   metadata's `run` section changed, import-oracle's copy is still valid (it checks the SQL files' hashes) but differs from this
   folder's.
9. **Generated files are never edited by hand**: `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`,
   `selftest-results.json`, `docs/phase1/dbmigrate/export-oracle/MigrationExportReport.docx`.
10. **A rendering bug found by import-oracle is fixed here** (`migration\dialects\oracle.ps1`), then the export is repeated and handed
    off again; never patch import-oracle's `input\`. Every Oracle rule in this file was written before an Oracle database was
    available to test it (see "Unverified until import-oracle has run"); expect corrections.
11. **Do not commit.** The user reviews `git status` and commits. No git command that changes anything (the user's standing rule).
12. **The source is only read.** The one exception is a deliberate stress test (see "Testing changes"), which must remove what it
    added and restore the auto-number counters.

## Run

From the repository root, in a command prompt, with the legacy application's LocalDB database available:

```
tools\phase1\dbmigrate\export-oracle\export-oracle.cmd all --target oracle
```

Expected: `Exported 8 tables (credentials sanitized)` with 155 rows, thirteen `PASS` self-test lines, `SELF-TEST PASSED`, then the report
path (`MigrationExportReport.docx`, about 55 KB); exit 0. Commands: `export`, `selftest`, `report [--out <file>]`, `all` (export,
self-test, report). `--config <path>` replaces the settings file. Exit codes: 0 ok, 1 self-test differences, 2 configuration, tool or
connection error (including the refusal to export unsanitized data), 3 refused. After a successful run, update the "Latest results"
section of the docs README if any number or the date changed, then do the hand-off (rule 8).

## Settings

`migration\migration.config.json` (paths relative to the repository root): `source` (`server` `(localdb)\MSSQLLocalDB`, `database`
`aspnet-MasterAntiqueRepair-e93a6129-…`), `outputDir` `tools/phase1/dbmigrate`, and one target `oracle`: `dialect` `oracle`,
`outputSubdir` `export-oracle`, `reportDir` `docs/phase1/dbmigrate/export-oracle`, `reportFile` `MigrationExportReport.docx`,
`sanitizeCredentials` `true`, `caseInsensitiveUniqueIndexes` `[{ "table": "Users", "column": "Name" }]` (the unique index on that
column is built on `LOWER(name)`).

## Layout

```
export-oracle.cmd                   wrapper (CRLF)
migration\DbMigrate.ps1             command line, dispatcher, exit codes
migration\Common.ps1                config, SQL Server catalog -> model, canonical values, hashing, Protect-SensitiveData
migration\Export.ps1                export, Get-TargetPaths, the refusal, the in-memory credential list for the self-test
migration\Metadata.ps1              source-metadata.json, business summaries, canonical row form and hash
migration\SelfTest.ps1              selftest
migration\Report.ps1                OpenXML and chart helpers
migration\ExportReport.ps1          the export report, built from source-metadata.json
migration\dialects\oracle.ps1       Oracle dialect: rename map, reserved words, types, rendering (renders text only, never connects)
migration\migration.config.json     settings
01-schema.sql, 02-data-sanitized.sql, source-metadata.json, selftest-results.json      outputs (checked in)
README.md                           how to run it, for people
.gitattributes                      *.sql, *.json, *.ps1, *.md pinned to LF; *.cmd to CRLF
```

The repository root is found by counting folders up from the script: `migration\Common.ps1` uses `'..\..\..\..\..'` (five levels up
from `tools\phase1\dbmigrate\export-oracle\migration`). Fix that count if this folder moves.

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

`oracle.ps1` holds an **explicit rename map** (`New-OraNameMap`, the same names as the PostgreSQL map), not an algorithm: every table and
column, and every index. Lookups (`Ora-Table`, `Ora-Column`, `Ora-IndexName`) throw naming the missing entry. All identifiers are
lowercase snake_case and **unquoted** in the output, so Oracle stores them in upper case; hand-written SQL against the database must not
quote them in lowercase. `Ora-CheckIdentifiers` checks every table, column, constraint and index name against a list of Oracle reserved
words (`$script:OraReservedWords`), the pattern `^[a-z][a-z0-9_]*$` and 128 bytes; `Ora-RenderSchema` refuses to render on a problem and
the self-test repeats the check. `timestamp`, `action`, `state`, `text`, `name` and `description` are keywords but not reserved words.
- Foreign keys: `fk_<table>_<reftable>_<columns joined by _>` (`fk_tickets_users_customer_id`).
- Primary keys are named `pk_<table>` so the constraint names are the same on every load.
- Indexes: the model's `TargetName` mapped to `ix_<table>_<columns>`, as in PostgreSQL. Index and constraint names are schema-wide in
  Oracle and must not collide.

### Types

| Source kind | Oracle | Notes |
|---|---|---|
| `int` identity, single-column primary key | `NUMBER(10) GENERATED BY DEFAULT AS IDENTITY CONSTRAINT pk_<t> PRIMARY KEY` | any other identity shape is an error |
| `int` / `bigint` / `smallint` / `tinyint` | `NUMBER(10)` / `NUMBER(19)` / `NUMBER(5)` / `NUMBER(5)` | |
| `bit` | `BOOLEAN` | Oracle 23ai and later only (not 19c); default `0`/`1` becomes `FALSE`/`TRUE`; literals `TRUE`/`FALSE` |
| `datetime` | `TIMESTAMP(3)` (no time zone) | literal `TIMESTAMP 'yyyy-MM-dd HH:mm:ss.fff'` |
| `nvarchar(n)` | `VARCHAR2(n CHAR)` | more than 4000 characters is an error; a value is also limited to 4000 bytes unless `MAX_STRING_SIZE=EXTENDED` |
| `nvarchar(max)`, `text`, `ntext` | `CLOB` | a literal is `TO_CLOB('...') \|\| ...` in pieces; in the current data every CLOB value is NULL |
| `varbinary` / `uniqueidentifier` | error | not present in this schema; add a mapping and a literal form when needed |

Anything else, and a default on a datetime, binary or guid column, is an error. **Column order in a definition is `type DEFAULT x NOT NULL`**
(Oracle rejects `NOT NULL DEFAULT x`).

### Schema file

Header comment, `WHENEVER SQLERROR EXIT FAILURE`, `SET DEFINE OFF`, then one `CREATE TABLE` per table in dependency order (Kahn's topological
sort, alphabetical tie-break) with inline named constraints, then the indexes sorted by name. There is no `BEGIN`/`COMMIT`: DDL commits by
itself, so a failed load leaves the earlier objects behind (import-oracle leaves the container for inspection).
- Foreign keys: `ON DELETE CASCADE` as in the source; **`NO ACTION` is written by leaving the clause out** (Oracle rejects the words and its
  default already means no action); `SET NULL` is kept; anything else is an error.
- `ix_users_name_active` is a unique **function-based index** on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END`. Oracle has no partial
  index; a B-tree index does not store an all-NULL key, so soft-deleted rows produce no key and free the username, and `LOWER` makes it
  case-insensitive (SQL Server compared case-insensitively). `Ora-IndexColumnExpression` builds the expression for both the schema file and
  the metadata. For a filter on several conditions or columns each indexed column is wrapped in the same `CASE WHEN <filter> THEN <col> END`.
  Filters are translated only for `[col] IS [NOT] NULL` shapes (AND-ed); anything else is an error so a rule is never silently dropped.
- `ix_roles_name` is a plain, case-sensitive unique index (roles are created only by the program).

### Data file

Header, `WHENEVER SQLERROR EXIT FAILURE ROLLBACK`, `SET DEFINE OFF` (no `&` prompts), per table in dependency order multi-row
`INSERT INTO t (cols) VALUES (...), (...)` (100 rows per statement, explicit column lists, primary-key order, one row per line; the
multi-row form needs Oracle 23ai or later), one `COMMIT;`, then for each identity table with rows
`ALTER TABLE t MODIFY (id GENERATED BY DEFAULT AS IDENTITY (RESTART START WITH <IdentityLast + 1>))` so the next id continues after the last
value the source issued (Oracle's equivalent of PostgreSQL's `setval`). **The files are pure ASCII**: a string is written as plain runs
`'...'` (`''` doubling) joined with `||` to `CHR(n)` for every control character (including TAB, LF and CR) and `UNISTR('\XXXX')` for every
other character (UTF-16 code units, so an emoji is a surrogate pair). Why: SQL*Plus reads the file through the client character set
(`NLS_LANG`), splits input at lines and blank lines, and rejects lines of about 2,499 characters; none of that can now touch the data. A
plain run is at most 1,000 characters; an expression over 1,500 characters is spread over several lines; a cell that would push a line past
1,800 characters starts a new line; the self-test checks that no line exceeds 2,000. A NUL is rejected. **An empty string is refused**
(Oracle stores `''` as NULL, so the load would silently change it); there is none in the data. Booleans `TRUE`/`FALSE`, NULL as `NULL`.

### selftest

`Invoke-SelfTest` needs the live source and a previous export; writes `selftest-results.json` (exit 1 if any test fails). Thirteen tests:
a second export into a temporary folder has a byte-identical schema, data and metadata (the whole `run` section aside); no credential value
read from the source (values of 8+ characters; 24 in the last run) appears in any of the six output files of the two exports; the tool
refuses to export with `sanitizeCredentials` off (exit 2, tested on a modified copy of the config); every table's `rowCount` equals a live
`COUNT(*)`; the total equals `expectations.totalRows`; the metadata's expectations hold; **four Oracle checks**: no SQL line longer than
2,000 characters, both SQL files pure ASCII, every identifier valid (reserved words, pattern, length), no empty string in the source; and the
export report built twice from the same metadata is byte-identical. The last detail line of the results holds the report's hash, which
changes whenever the metadata's `run` section does.

### report

`report` builds `MigrationExportReport.docx` from `source-metadata.json` alone (`ExportReport.ps1`, helpers in `Report.ps1`): OpenXML written
directly, charts drawn with `System.Drawing`, a fixed zip order, so the same metadata always gives the same bytes. Sections: executive
summary with an EXPORT COMPLETE banner, scope and method, results at a glance, table inventory, schema (source-to-target names and types),
business summaries with charts, credential sanitization, known differences and exclusions, reproducibility and hand-off, appendix with the
full row hashes. It carries no verification PASS/FAIL against a target.

## Contracts

- **`source-metadata.json`** (`schemaVersion` 1; import-oracle's `verify.sql` reads exactly this, so a change here is a change there). It is
  export-postgresql's contract with these Oracle differences: `meta.minOracleVersion` 23 (not `minPostgresVersion`); `meta.tool`
  `export-oracle`; `columns[]` add `precision` and `scale` (`dataType` is the `ALL_TAB_COLUMNS.DATA_TYPE` spelling: `NUMBER`, `BOOLEAN`,
  `TIMESTAMP(3)`, `VARCHAR2`, `CLOB`; `maxLength` is the character length of a `VARCHAR2`); `indexes[].columns[].expression` is the **full key
  expression** (`CASE WHEN deleted_at IS NULL THEN LOWER(name) END`) or null for a plain column; `indexes[].filter` documents the rule in
  Oracle names (`deleted_at IS NULL`) although Oracle implements it inside the expression; `targetName`s are lowercase, Oracle's dictionary
  holds them in upper case (compare case-insensitively); `foreignKeys[].onDelete` is the source action (`NO ACTION` means no clause was
  written). Otherwise: `meta` (`source`, `schemaFile`/`schemaSha256`, `dataFile`/`dataSha256` — SHA-256 of the LF files,
  `sanitizeCredentials`); `canonicalForm`; `tables[]` in load order (`sourceName`, `targetName`, `rowCount`, `identityLast`, `rowSha256`,
  `columns[]`, `primaryKey[]`, `foreignKeys[]`, `indexes[]`); `summaries[]` (`name`, `sourceSql` — documentation only, never executed —
  `expectedRows`); `expectations` (`totalRows` 155, `usersSanitized`, `usersCount` 12, `noDuplicateActiveUsernamesIgnoringCase`);
  `renameMap`; `excludedTables`; `knownDifferences`; `run` (`runTimeUtc`, `toolGitCommit`: the only non-deterministic part). It contains no
  credentials, personal data, raw comment text or executable SQL.
- **Canonical row form (identical to export-postgresql's, database-independent; must match import-oracle's `verify.sql` byte for byte):** cells
  joined by `|` in column order; NULL `~`; `i:<decimal>`, `b:1|0`, `t:yyyy-MM-dd HH:mm:ss.fff`, `s:<lowercase hex of UTF-8>`; rows **sorted
  ascending by their own canonical text in byte order**, joined by LF, SHA-256 lowercase hex; an empty table hashes the empty string
  (`e3b0c442…`); sanitized columns hash as `~`. Because the form is database-independent, **every table's `rowSha256`, every
  `summaries[].expectedRows`, the row counts and `identityLast` must equal export-postgresql's** for the same source data. That equality is the
  cross-check of the shared reading code (last run: all eight tables equal).
- **Summary rows:** cells joined by `|`, NULL as the empty string, timestamps as above, booleans 1/0, sorted in byte order.
- Outputs `01-schema.sql` and `02-data-sanitized.sql`: SQL*Plus scripts for Oracle AI Database 26ai (23ai or later), pure ASCII, LF.

## Gotchas

- **Rows are sorted by their canonical text, not by primary key.** A string primary key would sort differently in SQL Server and Oracle
  (collations).
- **The git commit and run time live in `run`, not `meta`.** Recording the commit in `meta` made the metadata differ after every commit; the
  determinism test ignores `run`.
- **Pin line endings** (`.gitattributes`): the metadata records the hashes of the LF form; git conversion on Windows would break the
  transfer check. The data has no raw line break inside a literal (they are `CHR(10)`).
- **NULL must stay distinct from the empty string** in the model, the canonical form and the SQL, and Oracle cannot store the difference:
  that is why an empty string stops the export.
- **`Protect-SensitiveData` appends a column to the model in place**, so it must run exactly once per table per process. Calling it twice
  adds `MustResetPassword` twice. Its names (`Users`, `PasswordHash`, `SecurityStamp`) are hardcoded.
- **Column defaults are exported, and an untranslatable default is an error.**
- **Rule-test inserts on Oracle must give explicit high ids** (see import-oracle): an identity sequence is never rolled back, so a test using
  the identity default moves it permanently.
- **Usernames are stored as typed**; authentication in Phase 2 would have to compare `LOWER(name) = LOWER(:input)` or the function-based
  index is not used and the case rule is not honoured.
- **Oracle stores identifiers in upper case**: `select name from users` works, `select "name" from "users"` does not.
- **After pruning or copying the tooling, check `Get-Dialect` still exists in `Common.ps1`.**

## Unverified until import-oracle has run

Windows can prove determinism, sanitizing, counts and that the text follows the rules above; it cannot prove that Oracle accepts it. These
points were written from documentation and memory and are the first suspects if the load fails: `START WITH`/`RESTART START WITH` inside
`ALTER TABLE ... MODIFY (... GENERATED ... AS IDENTITY (...))` (fallback: `START WITH LIMIT VALUE`); multi-row `INSERT ... VALUES` and
`BOOLEAN` on 26ai Free; the SQL*Plus line limit and the `WHENEVER SQLERROR` lines; `TO_CLOB(...)`/`UNISTR` mixed with `||` inside `VALUES`;
`timestamp` and `action` as unquoted column names; the default `MAX_STRING_SIZE` for `VARCHAR2(2000 CHAR)` columns. A correction goes into
`oracle.ps1`, is recorded here, and the export is re-run and handed off again.

## Testing changes

- Run `all --target oracle`: exit 0, self-test 13 of 13, three files rewritten. `git diff` must show `01-schema.sql` and
  `02-data-sanitized.sql` unchanged unless the change was meant to alter them, and `source-metadata.json` changed only in `run`.
- **Cross-check with PostgreSQL** after any change to reading, sanitizing or the canonical form: `rowSha256`, row counts, `identityLast`
  and `summaries[].expectedRows` in this metadata equal `export-postgresql`'s.
- **Test the literal rendering on awkward strings** after a change to `Ora-StringExpr` or `Ora-RenderRow`: dot-source `migration\Common.ps1`
  and `migration\dialects\oracle.ps1` in PowerShell and call `Ora-Literal` on text with quotes, a backslash, `&`, CR/LF/TAB, accents, an emoji,
  a 2,500-character string and an empty string (must throw); read the output.
- After a change to rendering, the formal proof is `Run import-oracle` on Linux with the new files.
- After adding a source column or table, expect the export to stop naming the missing rename-map entry; add it, then re-run.
- **Stress test with awkward data** after a change to rendering, reading or hashing: temporarily add rows to the source with line breaks,
  tabs, backslashes, quotes, emoji, Chinese and Japanese text, NULLs, a date in the year 9999 and a soft-deleted user with an accented name
  (**not** an empty text: the export refuses it); run `all` and load the result with import-oracle on Linux, requiring every row identical;
  then delete the rows and restore the auto-number counters (`DBCC CHECKIDENT`) so the source is back to 155 rows.
- **Negative test for a new self-test check:** damage a copy of an output and confirm the check fails and names it.

## Known limits

- The load into Oracle is not proven on Windows; that is import-oracle.
- `BOOLEAN` and multi-row `INSERT` need Oracle 23ai or later; on 19c switch to `NUMBER(1)` with a `CHECK` and single-row inserts (a change in
  `oracle.ps1`).
- An empty string in a source (there is none) stops the export; how a real customer's empty text should migrate is a data-owner decision.
- `VARCHAR2(n CHAR)` values are limited to 4000 bytes unless `MAX_STRING_SIZE=EXTENDED`; import-oracle checks the setting.
- Sanitizing is hardcoded to `Users.PasswordHash`, `Users.SecurityStamp` and the added `MustResetPassword` column; a config-driven list of
  sensitive columns is not built (DATA_MIGRATION.md §5.2.5, §6).
- Timestamps carry no time zone and the source zone (UTC or local) is unknown; no conversion is made.
- The metadata is produced by the same run as the SQL: it catches mistakes, not tampering.
- The files contain sanitized but real project data (usernames, timestamps, comment text).
- The export report was checked structurally, not rendered page by page in Word.
