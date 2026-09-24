# import-oracle: the migrated database in Oracle, in Docker

import-oracle takes the MasterAntiqueRepair database, exported from SQL Server by [export-oracle](../export-oracle/README.md), loads it into an **Oracle AI Database 26ai Free** database running in a **Docker container** on Linux, and **proves that nothing changed on the way**: every table, every row and every rule matches the original. It is a proof of concept alongside the PostgreSQL path; Phase 2 uses PostgreSQL. It is self-contained: the Oracle tools, database, guide and model need nothing from the PostgreSQL ones.

## What it does

1. **Checks the input.** The three files from export-oracle (the schema, the data, and a record of the source database) must be exactly the files that were exported; a single changed byte stops everything before a database is created.
2. **Builds the database.** An Oracle container named `mar-oracle` is created and the schema and data are loaded into a schema `masterantique`. The container publishes no network port. No password is stored anywhere: the tool works inside the container without one, the schema has none (nobody can log in as it), and the administrator accounts are given random passwords that nobody keeps.
3. **Verifies it.** Checks compare the new database with the record of the source: row counts, a fingerprint of every table's full contents, the structure (columns, types, keys, indexes), ten business questions, the removal of all passwords, and the database rules (for example, two active users cannot have the same name in different case, and a deleted user's name can be reused).
4. **Tests itself** on a separate temporary database: it gives the same answer every time and catches damaged data, a tampered record, corrupted files, an existing database and Docker being unavailable.
5. **Reports.** Writes a verification report for reviewers.

## Where it runs

A Linux machine with Docker Engine. Nothing else is needed on the machine: the Oracle tools run inside the container. It cannot reach the original SQL Server database, which is why it checks against the record of it made at export time.

## What it produces

| Output | What it is |
|---|---|
| The `mar-oracle` container | The migrated database: Oracle AI Database 26ai Free 23.26.3, schema `masterantique`, 8 tables, 155 rows |
| [MigrationVerificationReport.html](MigrationVerificationReport.html) (this folder) | The verification report |
| [OracleDatabaseGuide.html](OracleDatabaseGuide.html) (this folder) | How to use the database: SQL*Plus in the container, application logins, network routes, plain JDBC, a Spring Boot 4.1.1 project with JPA, and the first-login password change; every command and file tested on a copy |

## Latest results

Run on 2026-09-24 against the export of the same day:

- **Verification passed: 86 of 86 checks; 155 of 155 rows identical** to the source in all 8 tables.
- **Self-test passed: 7 of 7.**
- **The Oracle SQL written by export-oracle loads unchanged.** Every Oracle rule it could not test on Windows holds: the identity columns continue after the loaded ids, and multi-row inserts, `BOOLEAN` columns and millisecond timestamps load. The column names `timestamp`, `action`, `state`, `text`, `name` and `description` work unquoted and none is a reserved word. Text written as `CHR`/`UNISTR` pieces (quotes, backslash, `&`, line breaks, accents, an emoji) comes back byte for byte. The username index is case-insensitive and ignores deleted users.
- **Found on this database:** it limits a text value to 4,000 bytes (`MAX_STRING_SIZE = STANDARD`). A 2,000-character comment in two-byte characters fits, but one of 1,334 three-byte characters does not (the current data is far below the limit). A `BOOLEAN` column accepts numbers and words such as `yes` as true/false and rejects other text.

## Run it

**With Claude Code** on the Linux machine, with this repository open:

```
Run import-oracle.
```

Claude Code follows [tools/phase1/dbmigrate/import-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/import-oracle/CLAUDE.md), runs the tool, checks the numbers and reports back. It does not commit; the user does.

**By hand**, from the repository root (about 6 minutes; the first run also downloads a 1.7 GB image):

```
tools/phase1/dbmigrate/import-oracle/ingest.sh all --recreate
```

Commands and options: [tools/phase1/dbmigrate/import-oracle/README.md](../../../../tools/phase1/dbmigrate/import-oracle/README.md).

## Limits and known differences

- **Checked against a record, not the live source.** The record is made by export-oracle at export time; it catches mistakes in the export and the load, not tampering.
- **Names changed, data did not.** Table and column names are lowercase in the SQL (`created_at`) and stored in upper case by Oracle; every data value is exactly as in the source.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at first login.
- **Oracle 23ai or later.** `BOOLEAN` and multi-row `INSERT` are not available on 19c.
- **Text is limited to 4,000 bytes per value** on this database's settings, even in a 2,000-character column.
- **Times have no time zone.** Whether the legacy application stored UTC or local time is unknown, so no conversion was made.
- **Usernames ignore case only through an index.** An application must compare `LOWER(name) = LOWER(input)` when a user signs in.
- **An application needs two steps first.** The schema has no login and the container no published port; [OracleDatabaseGuide.html](OracleDatabaseGuide.html) creates the application logins and a network route.

## Related documents

- [tools/phase1/dbmigrate/import-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/import-oracle/CLAUDE.md): how the tool works and how to maintain it (written for Claude Code).
- [../export-oracle/](../export-oracle/): the export that produced this tool's input.
- The Oracle model built on this database: `master-antique-repair-claude/model/oracle/`, planned and documented in [docs/phase2/model/oracle/CLAUDE.md](../../../phase2/model/oracle/CLAUDE.md).
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy (§10 the Oracle decisions).
