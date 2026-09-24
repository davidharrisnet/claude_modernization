# export-oracle: exporting the database from SQL Server to sanitized Oracle files, on Windows

export-oracle takes the MasterAntiqueRepair database from **SQL Server (LocalDB)** and exports it as **Oracle** files (Oracle AI Database 26ai) that are checked into git, so that a Linux machine can build an Oracle database from them ([import-oracle](../import-oracle/README.md)). It is a proof of concept alongside the PostgreSQL path ([export-postgresql](../export-postgresql/README.md)): Phase 2 stays on PostgreSQL. It is **export only**: there is no Docker and no target database, so it does not verify a database; it proves that the export is repeatable, that no password leaves SQL Server, that the row counts match the live source, and that the SQL follows Oracle's rules. Passwords are removed on purpose before anything is written.

## What it does

1. **Exports.** Reads the structure of the SQL Server database and every row, removes each user's password data in memory, converts the names to lowercase snake_case (`CreatedAt` becomes `created_at`; Oracle stores them in upper case) and the types to Oracle's, and writes three files: the schema (`01-schema.sql`), the data (`02-data-sanitized.sql`) and a record of the source (`source-metadata.json`) that import-oracle uses to check its database. Running it twice on unchanged data gives identical files.
2. **Tests itself.** Thirteen tests prove the export is repeatable, that no credential value read from the source appears in any output file, that the tool refuses to export unsanitized data, that every table's row count equals a live count of the source, that the SQL files are pure ASCII with no overlong line, that every name is a valid Oracle identifier and that the source holds no empty string, and that the report rebuilds identically.
3. **Reports.** Writes a Word export report with charts, built only from the record of the source.

## Where it runs

A Windows machine with Windows PowerShell 5.1 and SQL Server LocalDB holding the legacy application's database. It needs the live SQL Server connection, so it cannot run on Linux or macOS. No Docker, no Oracle and no Word installation are needed. Because there is no Oracle here, the load into Oracle is proven by import-oracle, not by this tool.

## What it produces

All in `tools/phase1/dbmigrate/export-oracle/`, checked in; credentials are removed, so nothing here is secret.

| Output | What it is |
|---|---|
| [01-schema.sql](../../../../tools/phase1/dbmigrate/export-oracle/01-schema.sql) | Oracle schema for SQL*Plus: 8 tables, named keys and foreign keys with their delete rules, 11 indexes, defaults. Nothing needs quoting |
| [02-data-sanitized.sql](../../../../tools/phase1/dbmigrate/export-oracle/02-data-sanitized.sql) | 155 rows as `INSERT`s in pure ASCII, then an identity restart per auto-numbered table. Every user's `password_hash` and `security_stamp` is empty and `must_reset_password` is true |
| [source-metadata.json](../../../../tools/phase1/dbmigrate/export-oracle/source-metadata.json) | The record of the source at export: structure, row counts, a SHA-256 fingerprint per table, ten business summaries, expectations, and the hashes of the two SQL files. No credentials, no SQL to execute |
| [selftest-results.json](../../../../tools/phase1/dbmigrate/export-oracle/selftest-results.json) | Self-test results |
| [MigrationExportReport.docx](MigrationExportReport.docx) | The export report: what was exported, the schema with source-to-target names, summaries, sanitizing, differences, reproducibility |

## Latest results

Last run: 2026-09-24, `export-oracle.cmd all --target oracle`, SQL Server 2025 (RC1) LocalDB.

**Self-test 13 of 13 passed; 155 rows in 8 tables exported.** Every table's fingerprint, row count and business summary equals the PostgreSQL export's, because the fingerprint is computed in a database-independent form from the same source.

| Area | Tests | Result |
|---|---|---|
| Repeatable export | 3 | Schema, data and record of the source identical across two runs (apart from the run time) |
| No credentials | 3 | No credential value read from the source (24 values) appears in any output file; the tool refuses to run with sanitizing off (exit 2); users are all sanitized and no two active usernames differ only by case |
| Row counts | 2 | Every table's count equals a live `COUNT(*)` of the source; the total equals the recorded 155 |
| Oracle rules | 4 | No SQL line over 2,000 characters; both SQL files pure ASCII; every identifier valid and not reserved; no empty string in the source |
| Report | 1 | The report rebuilds byte-identically from the same record |

The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed), 26 comments, 78 audit log entries, 3 roles.

## Run it

**With Claude Code:** open this repository in VS Code (or a terminal) with Claude Code on the Windows machine and type:

```
Run export-oracle.
```

Claude Code follows the tool's instructions ([tools/phase1/dbmigrate/export-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/export-oracle/CLAUDE.md)): it runs the command below, checks the results against the ones above, and hands the three files over to import-oracle.

**By hand:** from a plain command prompt in the repository root, with the legacy application's LocalDB database available:

```
tools\phase1\dbmigrate\export-oracle\export-oracle.cmd all --target oracle
```

The commands are `export`, `selftest`, `report` and `all`. The exit code is 0 on success, 1 if the self-test found differences, 2 for a configuration, tool or connection error (including a refusal to export unsanitized data or a source value Oracle cannot store faithfully), 3 if refused. Options and rules to remember: [tools/phase1/dbmigrate/export-oracle/README.md](../../../../tools/phase1/dbmigrate/export-oracle/README.md).

**Hand-off to import-oracle:** after a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json` unchanged into `tools\phase1\dbmigrate\import-oracle\input\` and commit both folders together, so the Linux machine gets them with `git pull`; then run import-oracle there.

## Limits and known differences

- **The load is not proven here.** This tool cannot show that Oracle accepts the SQL; import-oracle does, and a rendering problem found there is fixed here and the export repeated. import-oracle loaded the current files unchanged and verified every row (2026-09-24); two literal forms the current data does not use (long text split over lines, `CLOB` values) are still unproven.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at first login.
- **Names changed, data did not.** Table, column, constraint and index names are lowercase snake_case in the SQL (Oracle stores them in upper case); every data value is exactly as in the source.
- **Oracle 23ai or later.** `BOOLEAN` and multi-row `INSERT` do not exist on 19c; a 19c target needs `NUMBER(1)` with a `CHECK` and single-row inserts.
- **Empty text cannot be migrated as is.** Oracle stores an empty string as NULL, so the export stops if the source contains one. The current data has none; a real system would need a decision from its data owner.
- **Times have no time zone.** `datetime` becomes `TIMESTAMP(3)` without time zone, values unchanged. Whether the legacy application stored UTC or local time is unknown, so no conversion was made.
- **Usernames ignore case only through an index.** SQL Server compared text case-insensitively; Oracle does not. Username uniqueness is enforced by a function-based unique index on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END` (Oracle has no partial index), so an application must compare `LOWER(name) = LOWER(input)`. Role names use a plain case-sensitive index.
- **Long text near 4,000 bytes.** `VARCHAR2(n CHAR)` also has a 4,000-byte limit unless the database allows extended strings; import-oracle checks the setting.
- **The record of the source guards against mistakes, not tampering.** It comes from the same run as the SQL files.
- **The files still hold real project data**: usernames, timestamps and comment text, though no credentials.
- **The report was checked structurally**, not rendered page by page in Word.

## Related documents

- [tools/phase1/dbmigrate/export-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/export-oracle/CLAUDE.md): the detailed instructions for running and maintaining this tool (written for Claude Code).
- [../import-oracle/](../import-oracle/): the load and verification of these files in Oracle in Docker.
- [../export-postgresql/](../export-postgresql/): the PostgreSQL export this tool was derived from.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy (§7 why database-agnostic files are impossible, §10 the Oracle decisions).
