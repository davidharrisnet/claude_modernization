# export-postgresql: exporting the database from SQL Server to sanitized PostgreSQL files, on Windows

export-postgresql takes the MasterAntiqueRepair database from **SQL Server (LocalDB)** and exports it as **PostgreSQL** files that are checked into git, so that a Linux machine can build a PostgreSQL database from them ([import-postgresql](../import-postgresql/README.md)). It is **export only**: there is no Docker and no target database, so it does not verify a database; it proves that the export is repeatable, that no password leaves SQL Server, and that the row counts match the live source. Passwords are removed on purpose before anything is written.

## What it does

1. **Exports.** Reads the structure of the SQL Server database and every row, removes each user's password data in memory, converts the names to PostgreSQL's lowercase snake_case (`CreatedAt` becomes `created_at`) and the types to PostgreSQL's, and writes three files: the schema (`01-schema.sql`), the data (`02-data-sanitized.sql`) and a record of the source (`source-metadata.json`) that import-postgresql uses to check its database. Running it twice on unchanged data gives identical files.
2. **Tests itself.** Nine tests prove the export is repeatable, that no credential value read from the source appears in any output file, that the tool refuses to export unsanitized data, that every table's row count equals a live count of the source, and that the report rebuilds identically.
3. **Reports.** Writes a Word export report with charts, built only from the record of the source.

## Where it runs

A Windows machine with Windows PowerShell 5.1 and SQL Server LocalDB holding the legacy application's database. It needs the live SQL Server connection, so it cannot run on Linux or macOS. No Docker, no PostgreSQL and no Word installation are needed. Because there is no PostgreSQL here, the load into PostgreSQL is proven by import-postgresql, not by this tool.

## What it produces

All in `tools/phase1/dbmigrate/export-postgresql/`, checked in; credentials are removed, so nothing here is secret.

| Output | What it is |
|---|---|
| [01-schema.sql](../../../../tools/phase1/dbmigrate/export-postgresql/01-schema.sql) | PostgreSQL 15+ schema: 8 tables, keys and foreign keys with their delete rules, 11 indexes, defaults. Nothing needs quoting |
| [02-data-sanitized.sql](../../../../tools/phase1/dbmigrate/export-postgresql/02-data-sanitized.sql) | 155 rows as `INSERT`s, then a sequence reset per auto-numbered table. Every user's `password_hash` and `security_stamp` is empty and `must_reset_password` is true |
| [source-metadata.json](../../../../tools/phase1/dbmigrate/export-postgresql/source-metadata.json) | The record of the source at export: structure, row counts, a SHA-256 fingerprint per table, ten business summaries, expectations, and the hashes of the two SQL files. No credentials, no SQL to execute |
| [selftest-results.json](../../../../tools/phase1/dbmigrate/export-postgresql/selftest-results.json) | Self-test results |
| [MigrationExportReport.docx](MigrationExportReport.docx) | The export report: what was exported, the schema with source-to-target names, summaries, sanitizing, differences, reproducibility |

## Latest results

Last run: 2026-09-24, `export-postgresql.cmd all --target postgres`, SQL Server 2025 (RC1) LocalDB.

**Self-test 9 of 9 passed; 155 rows in 8 tables exported.** The two SQL files are byte-identical to the previous run's (SHA-256 `67e94060…` and `301f79cf…`), which are the files import-postgresql verified.

| Area | Tests | Result |
|---|---|---|
| Repeatable export | 3 | Schema, data and record of the source identical across two runs (apart from the run time) |
| No credentials | 3 | No credential value read from the source (24 values) appears in any output file; the tool refuses to run with sanitizing off (exit 2); users are all sanitized and no two active usernames differ only by case |
| Row counts | 2 | Every table's count equals a live `COUNT(*)` of the source; the total equals the recorded 155 |
| Report | 1 | The report rebuilds byte-identically from the same record |

| Table (SQL Server → PostgreSQL) | Rows | Fingerprint |
|---|---|---|
| Roles → roles | 3 | `c0a2efd128356144` |
| Users → users | 12 | `fa415e1421e2d4a8` |
| AuditLogs → audit_logs | 78 | `c6e4f24be7acad70` |
| Tickets → tickets | 24 | `c34f64ec58233df7` |
| Comments → comments | 26 | `c954517fcb3a64cb` |
| UserClaims → user_claims | 0 | `e3b0c44298fc1c14` (empty table) |
| UserLogins → user_logins | 0 | `e3b0c44298fc1c14` (empty table) |
| UserRoles → user_roles | 12 | `44553a2bae5a2d40` |

The fingerprint is the first 16 characters of the SHA-256 over all sanitized rows in the record's canonical form. The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed), 26 comments, 78 audit log entries, 3 roles.

## Run it

**With Claude Code:** open this repository in VS Code (or a terminal) with Claude Code on the Windows machine and type:

```
Run export-postgresql.
```

Claude Code follows the tool's instructions ([tools/phase1/dbmigrate/export-postgresql/CLAUDE.md](../../../../tools/phase1/dbmigrate/export-postgresql/CLAUDE.md)): it runs the command below, checks the results against the ones above, and hands the three files over to import-postgresql.

**By hand:** from a plain command prompt in the repository root, with the legacy application's LocalDB database available:

```
tools\phase1\dbmigrate\export-postgresql\export-postgresql.cmd all --target postgres
```

The commands are `export`, `selftest`, `report` and `all`. The exit code is 0 on success, 1 if the self-test found differences, 2 for a configuration, tool or connection error (including a refusal to export unsanitized data), 3 if refused. Options and rules to remember: [tools/phase1/dbmigrate/export-postgresql/README.md](../../../../tools/phase1/dbmigrate/export-postgresql/README.md).

**Hand-off to import-postgresql:** after a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json` unchanged into `tools\phase1\dbmigrate\import-postgresql\input\` and commit both folders together, so the Linux machine gets them with `git pull`; then run import-postgresql there.

## Limits and known differences

- **The load is not proven here.** This tool cannot show that PostgreSQL accepts the SQL; import-postgresql does, and a rendering problem found there is fixed here and the export repeated.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at first login.
- **Names changed, data did not.** Table, column, foreign key and index names are lowercase snake_case; every data value is exactly as in the source.
- **Times have no time zone.** `datetime` becomes `TIMESTAMP` without time zone, values unchanged. Whether the legacy application stored UTC or local time is unknown, so no conversion was made; Phase 2 must decide.
- **Usernames ignore case only through an index.** SQL Server compared text case-insensitively; PostgreSQL does not. Username uniqueness is enforced by a `lower(name)` index, so an application must compare `lower(name) = lower(input)`. Usernames are stored as typed. Role names use a plain case-sensitive index.
- **The record of the source guards against mistakes, not tampering.** It comes from the same run as the SQL files; anyone who can edit both can make them agree.
- **The files still hold real project data**: usernames, timestamps and comment text, though no credentials.
- **The report was checked structurally** (valid package, well-formed XML, every image referenced) and rebuilds identically; it was not rendered page by page in Word.

## Related documents

- [tools/phase1/dbmigrate/export-postgresql/CLAUDE.md](../../../../tools/phase1/dbmigrate/export-postgresql/CLAUDE.md): the detailed instructions for running and maintaining this tool (written for Claude Code).
- [../import-postgresql/](../import-postgresql/): the load and verification of these files in PostgreSQL in Docker.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy (§7 why database-agnostic files are impossible, §8 the PostgreSQL decisions).
