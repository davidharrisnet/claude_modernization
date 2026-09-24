# import-oracle: load the Oracle export into Docker and verify it (Linux)

Loads the three files from export-oracle into an Oracle AI Database 26ai Free container and checks the result against the export's record of the source. A proof of concept alongside import-postgresql; Phase 2 uses PostgreSQL.

- What the tool does and its latest results: `docs/phase1/dbmigrate/import-oracle/README.md`. Instructions for Claude Code: `CLAUDE.md` in this folder.
- The input comes from export-oracle (Windows export): `docs/phase1/dbmigrate/export-oracle/README.md`.

## Run

On Linux with Docker Engine running, from the repository root (nothing else is needed on the host; `sqlplus` runs inside the container):

```
tools/phase1/dbmigrate/import-oracle/ingest.sh all --recreate
```

About 6 minutes (the first run also downloads the 1.7 GB image). Expected: `VERIFICATION PASSED - 86 of 86 checks; 155 of 155 rows verified identical`, `SELFTEST PASSED - 7 of 7`, the report written to `docs/phase1/dbmigrate/import-oracle/MigrationVerificationReport.html`, exit 0.

| Command | What it does |
|---|---|
| `load [--recreate]` | checks the files' SHA-256 against the metadata, starts `mar-oracle` (no published port), creates the password-less schema `masterantique` and loads the two SQL files |
| `verify [--schema <name>] [--out <path>]` | runs the checks and writes `verification-results.json` |
| `selftest` | proves the checker on a temporary container `mar-oracle-selftest` |
| `report` | writes the HTML report from the two results files |
| `all [--recreate]` | all four |

Exit codes: 0 ok, 1 differences found, 2 configuration, tool or Docker error, 3 refused (the container exists; add `--recreate`).

Look around (no password: operating-system authentication inside the container):

```
docker exec -it mar-oracle sqlplus / as sysdba
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = masterantique;
SELECT name, discriminator FROM users;
```

## Files

| File | Content |
|---|---|
| `ingest.sh` | The tool |
| `verify.sql` | The checks, one PL/SQL block run by `sqlplus` in the container |
| `report.sql` | Renders the HTML report (PL/SQL as the template engine) |
| `ingest.conf.example` | Settings (container, image `gvenzl/oracle-free:23.26.3-faststart`, pluggable database `FREEPDB1`, schema); copy to `ingest.conf` to change them |
| `input/` | The three files from export-oracle (checked in; credentials sanitized) |
| `verification-results.json`, `selftest-results.json` | Generated results (the report's source) |
| `guide/` | Sources of the database guide `docs/phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html` (logins, network routes, a tested Spring Boot project); see `guide/README.md` |
| `.gitattributes`, `.gitignore` | LF line endings; ignores `ingest.conf` and `*.log` |
