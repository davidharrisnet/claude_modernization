# import-oracle: load the Oracle export into Docker and verify it (Linux) — skeleton

**Not built yet.** This folder holds the input files from export-oracle and the directions for the Linux machine. The tool (`ingest.sh`) will be built on the first `Run import-oracle` there, following `CLAUDE.md` in this folder; this README then becomes a how-to like `tools/phase1/dbmigrate/import-postgresql/README.md`.

- What the tool will do and its results once built: `docs/phase1/dbmigrate/import-oracle/README.md`. Directions for Claude Code: `CLAUDE.md` in this folder.
- The input comes from export-oracle (Windows export): `docs/phase1/dbmigrate/export-oracle/README.md`.

## Files

| File | Content |
|---|---|
| `CLAUDE.md` | The build directions for the Linux Claude Code session: what to read, the rules, the environment to verify, the load/verify/self-test/report plan, the Oracle traps to test |
| `input/` | The three files from export-oracle (checked in; credentials sanitized): `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json` |
| `ingest.conf.example` | Non-secret settings (container `mar-oracle`, image, pluggable database `FREEPDB1`, schema user); values marked to verify |
| `.gitattributes`, `.gitignore` | LF line endings; ignores `ingest.conf` and `*.log` |
