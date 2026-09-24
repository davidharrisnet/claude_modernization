# Iteration 4: SQL Server -> sanitized PostgreSQL export (Windows)

Exports the MasterAntiqueRepair SQL Server LocalDB database into PostgreSQL-specific files. **Export only**: no Docker, no PostgreSQL, no target database. Credentials are sanitized in memory before anything is written, and the tool refuses to export unsanitized data.

- Plan: `docs/phase1/dbmigrate/iteration4/ITERATION4_PLAN.md`. Record of the real run: `docs/phase1/dbmigrate/iteration4/ITERATION4.md`.
- The Linux side that loads and verifies these files is iteration 5: `docs/phase1/dbmigrate/iteration5/README.md`.

## Run it

From a plain Windows command prompt in the repository root. The legacy app's LocalDB database must exist (`(localdb)\MSSQLLocalDB`, database name in `migration\migration.config.json`).

```
tools\phase1\dbmigrate\iteration4\dbmigrate4.cmd all --target postgres
```

| Command | What it does |
|---|---|
| `export` | Reads SQL Server, sanitizes, writes `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json` in this folder |
| `selftest` | Proves the tooling: repeatable export, no credential in any output file, refuses to run unsanitized, row counts match the live source, the report rebuilds byte-identically. Writes `selftest-results.json` |
| `report` | Builds `docs\phase1\dbmigrate\iteration4\MigrationExportReport4.docx` from `source-metadata.json` |
| `all` | export, selftest, report |

Options: `--target postgres` (required), `--config <path>`, `--out <file>` (report path). Exit codes: 0 ok, 1 self-test differences, 2 error, 3 refused.

## Outputs (checked in)

| File | Content |
|---|---|
| `01-schema.sql` | PostgreSQL 15+ DDL, lowercase snake_case, nothing needs quoting |
| `02-data-sanitized.sql` | The data as `INSERT`s; `password_hash` and `security_stamp` NULL, `must_reset_password` true; ends with a `setval` per identity table |
| `source-metadata.json` | Record of the source at export: structure, row counts, SHA-256 per table, business summaries, expectations, file hashes. No credentials, no SQL to execute |
| `selftest-results.json` | Self-test results |

## Hand-off to iteration 5

After a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json` into `tools\phase1\dbmigrate\iteration5\input\` and commit both folders. Iteration 5 reads only its own `input\` folder.

## Rules to remember

- Only identifiers are lowercased (snake_case, from an explicit rename map in `migration\dialects\postgres.ps1`); data values never are.
- Usernames are stored as typed; uniqueness is case-insensitive through the `lower(name)` partial unique index. Phase 2 authentication must compare `lower(name) = lower(:input)`.
- `datetime` becomes `TIMESTAMP` without time zone; the source time zone (UTC or local) is not known and no conversion is made.
- A new source table, column or index makes the export fail with a message naming the missing rename-map entry. Add it to the map, do not work around it.
- `.gitattributes` pins `*.sql`, `*.json` and `*.md` to LF. Keep it: the metadata records hashes of the LF form.
