# import-oracle: the migrated database in Oracle, in Docker

**Status: skeleton, not built yet.** The input files and the build directions exist; the tool will be built and run on the Linux machine.

import-oracle will take the MasterAntiqueRepair database, exported from SQL Server by [export-oracle](../export-oracle/README.md), load it into an **Oracle AI Database 26ai Free** database running in a **Docker container** on Linux, and **prove that nothing changed on the way**: every table, every row and every rule matches the original. It is a proof of concept alongside the PostgreSQL path ([import-postgresql](../import-postgresql/README.md)); Phase 2 uses PostgreSQL.

## What it will do

1. **Check the input.** The three files from export-oracle (the schema, the data, and a record of the source database) must be exactly the files that were exported; a single changed byte stops everything.
2. **Build the database.** An Oracle container named `mar-oracle` is created and the schema and data are loaded into it. The container publishes no network port and no password is stored.
3. **Verify it.** Checks compare the new database with the record of the source: row counts, a fingerprint of every table's full contents, the structure (columns, keys, indexes), ten business questions, the removal of all passwords, and the database rules (for example, two active users cannot have the same name in different case).
4. **Test itself** on a separate temporary database that it gives the same answer every time and catches damaged data, tampered records and corrupted files.
5. **Report.** Write a one-page verification report for reviewers.

## Where it will run

A Linux machine with Docker Engine. Nothing else is needed on the machine: the Oracle tools run inside the container. It cannot reach the original SQL Server database, which is why it checks against the record of it made at export time.

## What it will produce

| Output | What it is |
|---|---|
| The `mar-oracle` container | The migrated database: 8 tables, 155 rows |
| `MigrationVerificationReport.html` (this folder) | The verification report |

## Latest results

None yet. Built and run on the Linux machine, then this section is filled in with the real numbers.

## Run it

**With Claude Code** on the Linux machine, with this repository open:

```
Run import-oracle.
```

The first run is a build run: Claude Code follows [tools/phase1/dbmigrate/import-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/import-oracle/CLAUDE.md), which tells it what to read (the input files, the PostgreSQL tool as a template, export-oracle's list of unverified Oracle facts), how to build and run the tool, and what to report back. It does not commit; the user does.

## Limits and known differences (expected)

- **Checked against a record, not the live source.** The record is made by export-oracle at export time; it catches mistakes in the export and the load, not tampering.
- **Names changed, data did not.** Table and column names are lowercase in the SQL (`created_at`) and stored in upper case by Oracle; every data value is exactly as in the source.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at first login.
- **Oracle 23ai or later.** `BOOLEAN` and multi-row `INSERT` are not available on 19c.
- **Times have no time zone.** Whether the legacy application stored UTC or local time is unknown, so no conversion was made.
- **Usernames ignore case only through an index.** An application must compare `LOWER(name) = LOWER(input)` when a user signs in.

## Related documents

- [tools/phase1/dbmigrate/import-oracle/CLAUDE.md](../../../../tools/phase1/dbmigrate/import-oracle/CLAUDE.md): the build directions for the Linux session (written for Claude Code).
- [../export-oracle/](../export-oracle/): the export that produced this tool's input.
- [../import-postgresql/](../import-postgresql/): the finished PostgreSQL equivalent, used as the template.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy (§10 the Oracle decisions).
