# import-postgresql: the migrated database in PostgreSQL, in Docker

import-postgresql takes the MasterAntiqueRepair database, exported from SQL Server by [export-postgresql](../export-postgresql/README.md), loads it into a
**PostgreSQL** database running in a **Docker container** on Linux, and **proves that nothing changed on the way**:
every table, every row and every rule matches the original. It is the last step of the database migration; the
Phase 2 application uses this database.

## What it does

1. **Checks the input.** The three files from export-postgresql (the schema, the data, and a record of the source database)
   must be exactly the files that were exported; a single changed byte stops everything.
2. **Builds the database.** A PostgreSQL 16.1 container named `mar-postgres` is created and the schema and data are
   loaded into it. The container publishes no network port and its password is never stored, so the database cannot
   be reached by accident.
3. **Verifies it.** 80 checks compare the new database with the record of the source: row counts, a fingerprint of
   every table's full contents, the structure (columns, keys, indexes), ten business questions, the removal of all
   passwords, and the database rules (for example, two active users cannot have the same name in different case).
4. **Tests itself.** The checker proves on a separate, temporary database that it gives the same answer every time and
   catches damaged data, tampered records and corrupted files. The delivered database is never touched by testing.
5. **Reports.** It writes a one-page verification report for reviewers.

## Where it runs

A Linux machine with Docker Engine. Nothing else is needed on the machine: the PostgreSQL tools run inside the
container. It cannot reach the original SQL Server database, which is why it checks against the record of it made at
export time.

## What it produces

| Output | What it is |
|---|---|
| The `mar-postgres` container | The migrated database: `masterantique`, 8 tables, 155 rows |
| [MigrationVerificationReport.html](MigrationVerificationReport.html) | The verification report: results, tables, structure, business summaries, rules, how to reproduce |
| [PostgreSQLDatabaseGuide.html](PostgreSQLDatabaseGuide.html) | How to connect to the database: from a first query in the terminal to a Spring Boot application, including the password change every migrated user must make |

## Latest results

Last run: 2026-09-24, `ingest.sh all --recreate`, PostgreSQL 16.1.

**80 of 80 checks passed; 155 of 155 rows identical to the source; self-test 7 of 7 passed.**

| Area | Checks | Result |
|---|---|---|
| Environment | 3 | PostgreSQL 16.1, UTF-8, expected record format |
| File integrity | 2 | Both files exactly as exported |
| Row counts | 9 | Every table, and 155 rows in total |
| Content fingerprints | 8 | Every table's full contents identical to the source |
| Structure | 34 | Tables, columns, keys, foreign keys, indexes as designed |
| Business questions | 10 | Same answers as the source (users by type and role, tickets by state, audit events, comments, date ranges) |
| Passwords removed | 4 | No user has a password; every user must set a new one |
| Database rules | 10 | Case-insensitive unique usernames, reuse of deleted usernames, links between tables, new ids continue after the migrated ones |

The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed),
26 comments, 78 audit log entries, 3 roles.

## Run it

**With Claude Code:** open this repository in VS Code (or a terminal) with Claude Code and type:

```
Run import-postgresql.
```

Claude Code follows the tool's instructions (`tools/phase1/dbmigrate/import-postgresql/CLAUDE.md`): it runs the command
below, checks the results against the ones above, and reports.

**By hand:** on the Linux machine, from the repository root:

```
tools/phase1/dbmigrate/import-postgresql/ingest.sh all --recreate
```

It rebuilds the database, verifies it, runs the self-test and writes the report. Details of every command:
[tools/phase1/dbmigrate/import-postgresql/README.md](../../../../tools/phase1/dbmigrate/import-postgresql/README.md).

**The model that uses this database** is not part of this tool: it is Phase 2 code in the separate repository
`master-antique-repair-claude`. With this repository open in Claude Code, type `Run model-postgresql` (or
`Rebuild the model.` to rebuild its code); Claude Code follows
[docs/phase2/model/postgresql/CLAUDE.md](../../../phase2/model/postgresql/CLAUDE.md). Running import-postgresql again removes the
database login and network route the model uses; the demonstration recreates them.

## Limits and known differences

- **Checked against a record, not the live source.** The comparison is with the record export-postgresql made at export. It
  catches mistakes in the export and the load, not deliberate tampering with both the record and the files.
- **Names changed, data did not.** Table and column names are now lowercase with underscores (`created_at`,
  `user_id`); every data value is exactly as in the source.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at
  first login.
- **Times have no time zone.** Whether the legacy application stored UTC or local time is unknown, so no conversion was
  made.
- **Usernames ignore case only through an index.** An application must compare `lower(name) = lower(input)` when a
  user signs in.
- **Oddities from the source are kept.** Some tickets are dated before their customer's account, audit ids are not in
  time order, and a few second comments are older than the first. These are in the original data and are not
  migration errors.

## Related documents

- [tools/phase1/dbmigrate/import-postgresql/CLAUDE.md](../../../../tools/phase1/dbmigrate/import-postgresql/CLAUDE.md): the detailed
  instructions for running and maintaining this tool (written for Claude Code).
- [../export-postgresql/](../export-postgresql/): the export that produced this tool's input.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy.
- [docs/phase2/model/postgresql/CLAUDE.md](../../../phase2/model/postgresql/CLAUDE.md): the Spring Boot model built on this
  database.
