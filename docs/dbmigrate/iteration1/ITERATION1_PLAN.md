> **Implementation status:** built and verified. Entry point `tools\dbmigrate\dbmigrate.cmd` (commands `export`, `import`, `verify`, `selftest`, `report`, `all`); code in `tools\dbmigrate\migration\`. SQLite and MySQL (in Docker) dialects exist; the dialect interface (target ids, Exists, Import, ReadRows, Query, SchemaChecks, Behaviour, Clone/Diff for the self-test, DisplayName/KnownDifferences for the report) is what a PostgreSQL dialect would implement. Beyond this plan it also added a `selftest` command (byte-identical re-export, `sqldiff`, damaged-copy detection) and column-default support. See README "Exporting to SQLite" and `claude.log` entry 89.

# Plan: Deterministic SQL Server -> SQLite export / import / verify (iteration 1)

## Context
Iteration 1 scope: **create a SQLite database from the MasterAntiqueRepair SQL Server LocalDB database and inject all of its data**, then empirically prove the copy is identical and produce a stakeholder report. Everything is a deterministic script (no model in the loop) run from a plain command prompt. **No Docker** (per user). The design stays multi-dialect (PostgreSQL / MySQL are later iterations - each is just another dialect file + config block; no docker runner will be built, they'd need locally installed clients, none of which exist on this machine today).

Environment: Windows PowerShell 5.1 (built-in `System.Data.SqlClient`, `System.Drawing`, `System.IO.Compression`), `sqlcmd`, and the SQLite command-line tools in `C:\Apps\sqlite-tools-win-x64-3530400` (`sqlite3` 3.53.4) - all already installed. So the tooling is **pure PowerShell + the `sqlite3` CLI**, nothing to install. LocalDB `MSSQLLocalDB` is running; the source catalog `aspnet-MasterAntiqueRepair-e93a6129-...` exists (read-only queried already).

Source facts (observed): 8 app tables + `__MigrationHistory` (excluded, EF-only). Row counts: Users 12, Roles 3, UserRoles 12, UserClaims 0, UserLogins 0, Tickets 24, Comments 26, AuditLogs 78. Types in use: int, bit, nvarchar(n/max), datetime, (varbinary only in the excluded table). Filtered unique index `IX_Users_Name_Active ... WHERE ([DeletedAt] IS NULL)` (soft-delete username reuse rule) plus `RoleNameIndex`. **Index names collide across tables** (`IX_UserId` x5, EF-style) but are schema-global in SQLite, so colliding names get a `<Table>_` prefix (deterministic rule).

**SQLite tools on disk**: use the **64-bit** `C:\Apps\sqlite-tools-win-x64-3530400` (`sqlite3.exe` 3.53.4 verified running, `sqldiff.exe`, `sqlite3_analyzer.exe`, `sqlite3_rsync.exe`). The x86 folder is ignored (32-bit DLL can't load into 64-bit PowerShell). `C:\Apps\sqlite-dll-win-x64-3530400\sqlite3.dll` is loadable in principle via P/Invoke but is **not used**: the CLI does everything needed, is simpler, and avoids native-interop code in a script. The config's `exe` points at the x64 tools `sqlite3.exe` (PATH `sqlite3` is the fallback). `sqldiff.exe` is used as an **independent second check**: export twice, import each into its own `.sqlite`, and `sqldiff` them - must report no differences (also proves determinism at the database level, not just file bytes). Its version is recorded in the results JSON.

## Command-prompt interface
`tools\dbmigrate\dbmigrate.cmd` -> `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dbmigrate\migration\DbMigrate.ps1 %*`
```
dbmigrate export  --target sqlite [--config path]
dbmigrate import  --target sqlite [--recreate]
dbmigrate verify  --target sqlite
dbmigrate report  --target sqlite [--out file.docx]
dbmigrate all     --target sqlite     (export -> import -> verify -> report)
```
Exit codes: `0` success/all checks pass, `1` verification found differences, `2` config/tool/connection error, `3` refused (target exists without `--recreate`). Non-interactive, batch-friendly. Args parsed from `$args` by hand (`--flag value`) so the `--` style works from cmd.exe.

## Configuration: `tools/dbmigrate/migration/migration.config.json`
```
{ "source":  { "server": "(localdb)\\MSSQLLocalDB", "database": "aspnet-MasterAntiqueRepair-e93a6129-..." },
  "outputDir": "export",
  "targets": { "sqlite": { "dialect": "sqlite", "exe": "C:\\Apps\\sqlite-tools-win-x64-3530400\\sqlite3.exe", "diffExe": "C:\\Apps\\sqlite-tools-win-x64-3530400\\sqldiff.exe", "file": "tools/dbmigrate/export/iteration1/masterantique.sqlite" } } }
```
`--target` picks a block; `dialect` picks `dialects/<name>.ps1`. Unknown dialect -> exit 2 listing implemented ones.

## Architecture
```
tools/dbmigrate/dbmigrate.cmd
tools/dbmigrate/migration/
  DbMigrate.ps1        dispatcher, arg parsing, exit codes
  Common.ps1           SQL Server catalog introspection -> neutral model, topo-sort, canonical value form, hashing, process runner
  dialects/sqlite.ps1  type map, DDL/DML rendering, client invocation, read-back SQL
  Export.ps1  Import.ps1  Verify.ps1  Report.ps1
  migration.config.json
```
**Neutral model** from `sys.tables/columns/types/indexes/index_columns/foreign_keys/foreign_key_columns/identity_columns`: tables, columns (type, length, nullability, identity + `last_value`), PK, indexes (+ filter), FKs (+ delete action). Table order = Kahn topological sort, alphabetical tie-break (computed, not hard-coded). Unsupported source types (float, decimal, ...) are a **hard error**, never a silent guess; supported now: int family, bit, (n)varchar/(n)char/text, datetime family, varbinary, uniqueidentifier.

**SQLite dialect rules**
- Quoting `"Name"`, preserving case; `dbo.` dropped.
- Types: int/bigint/smallint/tinyint -> `INTEGER`; bit -> `INTEGER` + `CHECK (col IN (0,1))`; nvarchar(n) -> `VARCHAR(n)`, (max) -> `TEXT` (documentation only, SQLite doesn't enforce); datetime -> `DATETIME` holding ISO text `yyyy-MM-dd HH:mm:ss.fffffff`; varbinary -> `BLOB` (`X'..'`).
- Single-column identity PK -> `INTEGER PRIMARY KEY AUTOINCREMENT` (inline); composite PK -> table `PRIMARY KEY (...)`.
- **FKs inline in `CREATE TABLE`** (SQLite can't add them later), tables in topological order, `ON DELETE CASCADE/NO ACTION/SET NULL` preserved from the catalog.
- Indexes via `CREATE [UNIQUE] INDEX`; the filtered unique index becomes a native SQLite partial index (`WHERE "DeletedAt" IS NULL`). Filter translator accepts only `[col] IS [NOT] NULL` shapes and **errors on anything else** rather than dropping a rule.
- Data: `PRAGMA foreign_keys=OFF; BEGIN; multi-row INSERTs (100 rows/statement, explicit column lists, PK order); sqlite_sequence set from the source identity `last_value`; COMMIT; PRAGMA foreign_keys=ON; PRAGMA foreign_key_check;`.
- Literals: ints/bits raw; strings `'..'` with `''` doubling; blobs `X'..'`; NULL. Strings containing NUL are rejected.

**Determinism**: sorted metadata, `ORDER BY` PK, invariant culture, UTF-8 **without BOM**, LF newlines, no clock/host in export headers. `export` twice -> byte-identical (hash-compared).

**Process handling**: `sqlite3` is driven through `System.Diagnostics.Process` with the SQL piped to stdin as UTF-8 bytes (avoids PowerShell 5.1 quoting/code-page problems with emoji and quotes) and stdout/stderr read asynchronously (no pipe deadlock); `-bail` so the first error aborts.

## Outputs (`tools/dbmigrate/export/iteration1/`, gitignored - contains credential-equivalent password hashes)
`01-schema.sql`, `02-data.sql`, `masterantique.sqlite`, `import-log.txt`, `verification-results.json`, `MigrationVerificationReport.docx`.

## Import
Refuses if the `.sqlite` exists unless `--recreate` (deletes only that file). Runs schema then data via `sqlite3 -bail`; then `PRAGMA integrity_check` (must be `ok`) and `PRAGMA foreign_key_check` (must be empty). Exit `2` on any client error with its stderr shown.

## Verify (empirical proof) -> `verification-results.json`, exit `1` on any difference
Read-only on the source; the target is only queried (behaviour tests run on a temp **copy** of the `.sqlite`).
1. **Row counts** per table, SQL Server vs SQLite, delta, PASS/FAIL.
2. **Row-by-row content equivalence.** Both sides are reduced to one canonical text per value and each cell is **hex-encoded** (SQLite side inside the query: `CASE WHEN c IS NULL THEN '~' ELSE substr(typeof(c),1,1)||':'||hex(c) END`), so newlines, tabs, quotes, emoji cannot break parsing and NULL is distinct from empty string. `typeof()` also proves storage class (a date stored as text, a bool as integer). Rows are keyed by PK, compared field by field; per-table **SHA-256 of the canonical rows** computed on both sides and compared. Mismatches list table/PK/column/both values (capped; `PasswordHash`/`SecurityStamp` compared but **redacted** in all output).
3. **Schema objects**: tables, columns (names/order/nullability), PKs, indexes (uniqueness, partial filter), FKs (columns, referenced table/column, cascade), AUTOINCREMENT columns, via `sqlite_master` and `pragma_table_info/foreign_key_list/index_list`. Counts shown side by side.
4. **Domain-level counts** (one SQL text runs on both engines - double-quoted identifiers work in both): users by `Discriminator`, active vs soft-deleted users, users per role, tickets by `State`, assigned vs unassigned tickets, audit rows by `Action`, comment/ticket totals, MIN/MAX of key dates.
5. **Behaviour tests on a temp copy**: duplicate active username is rejected; reusing a soft-deleted username succeeds (proves the partial index works); orphan FK insert is rejected; inserting a Role with no Id gets `previous max + 1` (sequence carried over correctly).
6. `PRAGMA integrity_check` + `foreign_key_check` clean.
JSON also records tool versions (SQL Server, sqlite3), script git commit, input/output file SHA-256s, run time (only non-deterministic field).

## Stakeholder Word report (`Report.ps1`) -> `.docx` with graphics
No Word install needed. Charts rendered to PNG with `System.Drawing` (fixed size/fonts/palette); the document is written directly as OpenXML through `System.IO.Compression.ZipArchive` (real Title/Heading/Table styles so an auto table of contents works, header/footer, alt text on images, fixed zip entry order/timestamps -> byte-reproducible from the same JSON). Rejected: Word COM automation (needs Word) and adding an npm/Python toolchain.
Contents: (1) title + executive summary with a PASS/FAIL banner and "N of N checks passed, N of N rows verified identical"; (2) scope/method in plain English and why matching SHA-256 hashes mean identical data; (3) graphics: check-outcome donut, grouped bar chart of row counts SQL Server vs SQLite, per-table status strip (counts / content / hash), schema-objects chart, business charts (users by role, active vs soft-deleted, tickets by state, audit events by action); (4) detail tables (counts with delta, per-table hashes, schema comparison, behaviour tests); (5) differences found ("None" or an itemised list, credentials redacted); (6) intentional exclusions/known differences (`__MigrationHistory`, `dbo` dropped, dates stored as ISO text, `Discriminator` kept as a column, password hashes copied byte-for-byte, VARCHAR lengths not enforced by SQLite); (7) reproducibility (commands, git commit, file hashes, run date); (8) sign-off block + appendix.

## Files to touch
- New: everything under `tools/dbmigrate/migration/` and `tools/dbmigrate/dbmigrate.cmd`.
- Edit: `.gitignore` (`export/`), `README.md` (short "Exporting to SQLite" section: prerequisites, commands, exit codes), `CLAUDE.md` (one Build/run bullet), append to `claude.log`.
- Reuse: connection defaults and `SqlLocalDB.exe start` guard from the legacy repo's `Scripts/Reset-Database.ps1`.

## Work order
1. `Common.ps1`, `dialects/sqlite.ps1`, `Export.ps1` -> generate SQL; `Import.ps1` -> build the `.sqlite`.
2. `Verify.ps1` (+ negative test).
3. `DbMigrate.ps1` + `dbmigrate.cmd`, `all` command.
4. `Report.ps1`, then docs/`.gitignore`/`claude.log`.
Iterate on any failure until every step passes.

## Verification (end-to-end, all local, no Docker)
1. Add awkward rows to the source first: a comment with quotes, newlines, tabs, backslashes and emoji; NULL dates; a soft-deleted user (via `sqlcmd`; existing seed scripts if needed).
2. From a plain **cmd.exe** prompt: `tools\dbmigrate\dbmigrate all --target sqlite` -> exit 0, all checks PASS, `.sqlite` opens in `sqlite3` and per-table counts match the source counts above.
3. Determinism: run `export` twice -> identical file hashes; render the report twice from one JSON -> identical hash.
4. Negative test: update one comment and delete one row in a copy of the `.sqlite`, run `verify` against it -> exit 1 naming the exact table/PK/column; report shows the FAIL banner and red chart elements.
5. Report: unzip the `.docx`, confirm every XML part is well-formed and every image relationship resolves; render to PDF via Word/LibreOffice if present, otherwise inspect the embedded PNGs directly and validate the package structure.
