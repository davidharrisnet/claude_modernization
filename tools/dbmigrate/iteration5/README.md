# Iteration 5: load the PostgreSQL export into Docker and verify it (Linux)

Loads iteration 4's three files (`input/01-schema.sql`, `input/02-data-sanitized.sql`, `input/source-metadata.json`) into a PostgreSQL database inside a Docker container, and verifies the database against `source-metadata.json`. **bash + Docker only**: `psql` runs inside the container; no host PostgreSQL client, Python, Java or `jq`. No Claude session is needed to run it.

- Plan: `docs/dbmigrate/iteration5/ITERATION5_PLAN.md`. Record of the real run: `docs/dbmigrate/iteration5/ITERATION5.md`.
- The input comes from iteration 4 (Windows export): `docs/dbmigrate/iteration4/ITERATION4.md`.

## Run it

Needs Docker Engine (running), bash and `sha256sum`. From the repository root:

```
tools/dbmigrate/iteration5/ingest.sh all --recreate
```

| Command | What it does |
|---|---|
| `load` | Checks the two SQL files against the SHA-256 recorded in the metadata, starts container `mar-postgres` (no published port, random password that is never stored), waits for PostgreSQL, refuses a server older than 15 or not UTF-8, loads the schema then the data (stops at the first error). Refuses (exit 3) if the container already exists, unless `--recreate`. |
| `verify` | Runs `verify.sql` in the container: environment, file integrity, row counts, per-table content hashes, schema (columns, keys, foreign keys, indexes), the ten business summaries, sanitization, rule tests (rolled back). Prints one line per check and writes `verification-results.json`. |
| `selftest` | Proves the tooling on a separate, temporary container `mar-postgres-selftest` (the delivered database is never touched): repeatable load, a damaged copy is caught, a tampered metadata hash is caught, a corrupted input file is refused, an existing database is protected, Docker unavailable is reported. Writes `selftest-results.json`. |
| `report` | Builds `docs/dbmigrate/iteration5/MigrationVerificationReport5.html` from the two results files (rendered by `psql` in the container's `postgres` database; the migrated data is not read). |
| `all` | load, verify, selftest, report |

Options: `--recreate` (load, all), `--config <path>`, `--db <name>` and `--out <path>` (verify). Exit codes: 0 ok, 1 verification or self-test differences, 2 configuration, tool or Docker error, 3 refused.

Settings: built-in defaults (container `mar-postgres`, image `postgres:16.1`, database and user `masterantique`, schema `public`, input folder `input`). To change them, copy `ingest.conf.example` to `ingest.conf` (gitignored). No setting is secret.

## Working with the database

The full guide, including application logins, network routes and a Spring Boot project, is `docs/dbmigrate/iteration5/PostgreSQLDatabaseGuide.html`. The quick version:

```
docker exec -it mar-postgres psql -U masterantique -d masterantique     # interactive; no password needed inside
docker exec mar-postgres psql -U masterantique -d masterantique -c 'select name, discriminator from users'
docker stop mar-postgres / docker start mar-postgres                     # keeps the data
docker rm -f -v mar-postgres                                             # deletes the container and its data
```

The database lives only in the container and publishes no port; an application reaches it only through one of the routes the guide describes.

## Files

| File | Content |
|---|---|
| `ingest.sh` | The tool |
| `verify.sql` | Static verification; reads the metadata as `jsonb` and builds every query itself (nothing executable is read from the JSON) |
| `report.sql` | Renders the HTML report from the results JSON |
| `ingest.conf.example` | Non-secret settings |
| `input/` | The three files from iteration 4 (checked in; credentials sanitized) |
| `verification-results.json`, `selftest-results.json` | Outputs of the last run (checked in) |
