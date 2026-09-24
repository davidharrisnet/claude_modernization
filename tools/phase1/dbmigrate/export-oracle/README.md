# export-oracle: SQL Server -> sanitized Oracle export (Windows)

Exports the MasterAntiqueRepair SQL Server LocalDB database into Oracle-specific files (Oracle AI Database 26ai). **Export only**: no Docker, no Oracle, no target database. Credentials are sanitized in memory before anything is written, and the tool refuses to export unsanitized data. It is a proof of concept alongside the PostgreSQL path.

- Description and latest results: `docs/phase1/dbmigrate/export-oracle/README.md`. Instructions for Claude Code: `CLAUDE.md` in this folder.
- The Linux side that loads and verifies these files is import-oracle: `docs/phase1/dbmigrate/import-oracle/README.md`.

## Run it

From a plain Windows command prompt in the repository root. The legacy app's LocalDB database must exist (`(localdb)\MSSQLLocalDB`, database name in `migration\migration.config.json`).

```
tools\phase1\dbmigrate\export-oracle\export-oracle.cmd all --target oracle
```

| Command | What it does |
|---|---|
| `export` | Reads SQL Server, sanitizes, writes `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json` in this folder |
| `selftest` | Proves the tooling: repeatable export, no credential in any output file, refuses to run unsanitized, row counts match the live source, four Oracle checks (line length, pure ASCII, valid identifiers, no empty strings), the report rebuilds byte-identically. Writes `selftest-results.json` |
| `report` | Builds `docs\phase1\dbmigrate\export-oracle\MigrationExportReport.docx` from `source-metadata.json` |
| `all` | export, selftest, report |

Options: `--target oracle` (required), `--config <path>`, `--out <file>` (report path). Exit codes: 0 ok, 1 self-test differences, 2 error, 3 refused.

## Outputs (checked in)

| File | Content |
|---|---|
| `01-schema.sql` | SQL*Plus script: Oracle DDL, lowercase snake_case names (Oracle stores them in upper case), named constraints, a function-based index for the active-username rule |
| `02-data-sanitized.sql` | The data as multi-row `INSERT`s in pure ASCII (`CHR`/`UNISTR` for special characters); `password_hash` and `security_stamp` NULL, `must_reset_password` true; ends with an identity restart per table |
| `source-metadata.json` | Record of the source at export: structure, row counts, SHA-256 per table, business summaries, expectations, file hashes. No credentials, no SQL to execute |
| `selftest-results.json` | Self-test results |

## Hand-off to import-oracle

After a successful export, copy `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json` into `tools\phase1\dbmigrate\import-oracle\input\` and commit both folders. import-oracle reads only its own `input\` folder.

## Rules to remember

- Only identifiers are lowercased (snake_case, from an explicit rename map in `migration\dialects\oracle.ps1`); data values never are.
- Oracle folds unquoted names to upper case: do not quote the names in lowercase when querying the database.
- Usernames are stored as typed; uniqueness is case-insensitive through a function-based unique index on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END`. Authentication must compare `LOWER(name) = LOWER(:input)`.
- Oracle stores an empty string as NULL, so the export stops (exit 2) if the source holds one; the current data has none.
- `BOOLEAN` and multi-row `INSERT` need Oracle 23ai or later; not 19c.
- `datetime` becomes `TIMESTAMP(3)` without time zone; the source time zone is not known and no conversion is made.
- A new source table, column or index makes the export fail with a message naming the missing rename-map entry; an identifier that is an Oracle reserved word also fails. Fix the map, do not work around it.
- The Oracle rules were written without an Oracle database to test them; import-oracle is the proof and may send corrections back to `oracle.ps1`.
- `.gitattributes` pins `*.sql`, `*.json` and `*.md` to LF. Keep it: the metadata records hashes of the LF form.
