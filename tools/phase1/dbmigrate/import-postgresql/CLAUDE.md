# import-postgresql — instructions for Claude Code

This folder is the import-postgresql tool: it loads the PostgreSQL export written by export-postgresql into a PostgreSQL
container on Linux and verifies it against the export's record of the source. It runs when the user says
**`Run import-postgresql`**. The human description is `docs/phase1/dbmigrate/import-postgresql/README.md`; the strategy
and security policy for the database migration is `docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5 security, §8 decisions).
The Windows side that writes the input files is `tools/phase1/dbmigrate/export-postgresql/CLAUDE.md`.

## Rules

1. **Never edit `input/` by hand.** It holds export-postgresql's three output files. To refresh them, re-export on Windows
   (`Run export-postgresql`) and copy all three together.
2. **Never fix rendering bugs here.** If the SQL fails to load or a hash disagrees because of how export-postgresql wrote
   the SQL, fix `tools/phase1/dbmigrate/export-postgresql/migration/dialects/postgres.ps1` and re-export.
3. **Never test on the delivered database.** Use another container through `--config` (see "Testing changes").
   `mar-postgres` is changed only by `load --recreate` / `all --recreate`.
4. **No secrets.** The database password is random, passed as a file, deleted after start-up, and never printed or
   stored. Keep it that way; application logins are made with the guide's `mar-roles.sql`, never in this tool.
5. **Nothing executable comes from a data file.** `verify.sql` builds every query itself (`format('%I', ...)`) from
   names in the metadata; `\set var \`cmd\`` only ever runs `cat` on files the tool copied into the container.
6. **Generated files are never edited by hand**: `verification-results.json`, `selftest-results.json`,
   `docs/.../MigrationVerificationReport.html`, `docs/.../PostgreSQLDatabaseGuide.html` (see `guide/README.md`).
7. **Keep LF line endings** (`.gitattributes`): the metadata records hashes of the LF form, and bash breaks on CRLF.

## Run

From the repository root, on Linux with Docker Engine running (bash, `sha256sum`; nothing else on the host):

```
tools/phase1/dbmigrate/import-postgresql/ingest.sh all --recreate
```

Expected: exit 0, `VERIFICATION PASSED - 80 of 80 checks; 155 of 155 rows verified identical`,
`SELFTEST PASSED - 7 of 7`, `REPORT WRITTEN: ...`. Commands: `load [--recreate]`, `verify [--db <name>] [--out <path>]`,
`selftest`, `report`, `all [--recreate]`; `--config <path>` replaces the settings. Exit codes: 0 ok, 1 differences,
2 configuration/tool/Docker error, 3 refused (container exists, no `--recreate`). After a successful run, update the
"Latest results" section of the docs README if any number changed.

## Settings

`ingest.conf.example` (bash `key=value`, sourced; copy to `ingest.conf`, which is gitignored). Built-in defaults:
`CONTAINER=mar-postgres`, `PG_IMAGE=postgres:16.1`, `PG_DATABASE=masterantique`, `PG_USER=masterantique`,
`PG_SCHEMA=public`, `INPUT_DIR=input` (relative to this folder, or absolute). Values must match
`^[A-Za-z0-9_.:/-]+$`. The image is pinned to 16.1; the tool refuses a server older than 15.

## Layout

```
ingest.sh                   the tool
verify.sql                  verification, run by psql inside the container
report.sql                  renders the HTML report from the results JSON (psql as template engine)
ingest.conf.example         settings
input/                      01-schema.sql, 02-data-sanitized.sql, source-metadata.json (from export-postgresql)
verification-results.json   written by verify (the report's source)
selftest-results.json       written by selftest
guide/                      sources of the database guide (own README)
README.md                   how to run the tool (for people)
.gitattributes, .gitignore  LF endings; ignores ingest.conf, *.log, guide build output
```

The repository root is found by counting folders up from this one (`REPO_ROOT="$HERE/../../../.."` in `ingest.sh`,
five levels in `guide/build-guide.py`); fix those if this folder moves.

## How `load` works

1. `docker info` must succeed, else exit 2.
2. **Transfer integrity before anything starts:** `sha256sum` of both SQL files must equal `schemaSha256` and
   `dataSha256` in the metadata (read with `grep -o '"<key>": *"[0-9a-f]\{64\}"'`, no `jq`); a mismatch exits 2 and no
   container is created.
3. Existing container: exit 3, or with `--recreate` `docker rm -f -v` (removes its anonymous data volume too).
4. Pull the image only if missing.
5. Random password (`/dev/urandom` → alphanumerics) written to a file in a `mktemp -d` folder; `docker create` with
   `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD_FILE=/tmp/.pgpw` and **no `-p`**; `docker cp` the file in; delete
   the host copy; `docker start`. Why a file: an environment variable would be stored in the container configuration
   and shown by `docker inspect`.
6. Wait (≤120 s) until the log contains `PostgreSQL init process complete` **and** `select 1` succeeds twice in a row.
   Why: the image first runs a temporary server for initialisation and then restarts; `pg_isready` alone passes too
   early. Then remove `/tmp/.pgpw` from the container.
7. `server_version_num` ≥ 150000 and `server_encoding` = `UTF8`, else exit 2.
8. If `PG_SCHEMA` is not `public`, create it; every psql call passes `-e PGOPTIONS="-c search_path=$PG_SCHEMA"`.
9. `docker cp` the input files to `/tmp`; `psql -X -q -v ON_ERROR_STOP=1 -f /tmp/01-schema.sql -f /tmp/02-data-sanitized.sql`.
   On error exit 2 and leave the container for inspection.
10. Print row counts, then `LOAD COMPLETE`.

All psql calls are `docker exec -i <container> psql -X -v ON_ERROR_STOP=1 -U <user> -d <db>` over the local socket,
which the image trusts, so no password is needed.

## How `verify` works

`ingest.sh verify` copies the metadata and `verify.sql` into the container, **deletes the old
`/tmp/verification-results.json` there first** (why: Linux's `protected_regular` rule stops even root from overwriting
a file in `/tmp` owned by another user, and `report` copies files in as the host user), and runs
`psql -q -A -t` with `schema_sha`, `data_sha` (host hashes), `run_time`, `tool_commit`, `image`, `container`,
`outfile`. It prints one line per check (`PASS|FAIL  category  name -- detail`) and a summary, copies the JSON out
(default `verification-results.json`, or `--out`), and exits 1 on any FAIL, 2 if `verify.sql` fails.

`verify.sql`: metadata into temp table `meta(j jsonb)`; results into temp tables; helpers in `pg_temp` (`chk` — NULL
counts as FAIL; `norm_default`, `norm_expr` — strip casts, quotes, parentheses, spaces, case, so `lower(name::text)`
equals `lower(name)`; `jdiff`; `ts`). Every group is a `DO` block that catches errors and records FAIL, so a broken
database gives failures, not a crash.

| Category (count) | What is checked |
|---|---|
| environment (3) | server version ≥ `minPostgresVersion`; UTF8; metadata `schemaVersion` 1 |
| integrity (2) | host SHA-256 of each SQL file = metadata |
| counts (9), hashes (8) | per table one query from the column list: `count(*)` and `sha256` over `string_agg(row, E'\n' ORDER BY row COLLATE "C")`, each cell `coalesce('<prefix>:' \|\| value, '~')`; booleans `CASE WHEN c THEN '1' WHEN NOT c THEN '0' END` (a plain `ELSE '0'` would turn NULL into `0`); plus total rows |
| schema (34) | exact set of base tables; per table columns in order (name, type, length, nullability, normalized default, identity `BY DEFAULT`), primary key, foreign keys (name, columns, target, `confdeltype`), indexes (unique, keys via `pg_get_indexdef`, direction, predicate); no invalid index |
| summaries (10) | static PostgreSQL queries keyed by the metadata's summary names, rows sorted `COLLATE "C"`, compared with `expectedRows`; a missing query or an extra one fails |
| sanitization (4) | `sanitizeCredentials`; user count; no password hash or security stamp, all `must_reset_password`; no active usernames equal ignoring case |
| rules (10) | **first** each identity sequence's `pg_sequences.last_value` = `identityLast`, read without `nextval` (why: `nextval` is never rolled back, so it would move sequences permanently); **then** three behaviour tests, each ending with a private error (SQLSTATE `P0999`) that rolls everything back, using explicit ids ≥ 1000001: upper-case duplicate of an active username rejected, soft-deleted username reusable, orphan comment rejected; **last** no test rows left and no sequence moved |

A failing hash names the table, not the column (the metadata has no per-column hashes). A hash mismatch with matching
counts usually means export-postgresql and `verify.sql` disagree on the canonical form (empty-table hash, 3-digit
timestamps, hex of UTF-8); check that before suspecting the data.

## How `selftest` works

Needs the delivered container running (compared against) but never changes it; everything else happens in a temporary
container `<CONTAINER>-selftest`, removed at the end. Seven tests: two fresh loads give identical results (JSON
compared without the `runTimeUtc` lines); the delivered database gives the same check lines; a damaged copy (one
comment edited, last ticket deleted, `ix_users_name_active` dropped, made with `CREATE DATABASE ... TEMPLATE`) makes
verify exit 1 naming tickets, comments, the users index and the case rule; a zeroed `rowSha256` for roles gives
exactly one failure; one changed byte in the data file makes `load` exit 2 before any container exists; `load`
without `--recreate` exits 3; `DOCKER_HOST=unix:///nonexistent/docker.sock` gives exit 2 (simulated, so no other
container is stopped). Writes `selftest-results.json` (no timestamps; identical between good runs).

## How `report` works

Copies the two results files into the container under **its own names** (`/tmp/report-results.json`,
`/tmp/report-selftest.json`, or a `null` stub) and runs `report.sql` in the default **`postgres`** database: psql is
only the template engine, the migrated data is not read. Output `/tmp/report.html` →
`docs/phase1/dbmigrate/import-postgresql/MigrationVerificationReport.html`. Self-contained HTML (inline CSS, light/dark,
phone width); the same JSON always gives the same bytes. `all` runs load, verify, selftest (subshell), report; exit 2
if any step errored, 1 if verify or selftest found differences.

## Input contract with export-postgresql

If export-postgresql changes any of this, `verify.sql` changes with it.

- `01-schema.sql` (8 tables, 11 indexes, one transaction); `02-data-sanitized.sql` (multi-row `INSERT`s and a
  `setval` per identity table, one transaction).
- `source-metadata.json`: `schemaVersion` 1; `meta` (`source`, `minPostgresVersion` 15, `schemaFile`/`schemaSha256`,
  `dataFile`/`dataSha256`, `sanitizeCredentials`); `run` (`runTimeUtc`, `toolGitCommit`: the only non-deterministic
  part); `tables[]` in load order (`sourceName`, `targetName`, `rowCount`, `identityLast`, `rowSha256`, `columns[]`
  with `kind` in `int|bit|datetime|string|binary|guid`, `targetName`, `dataType`, `maxLength`, `nullable`, `default`,
  `identity`, `synthetic`; `primaryKey[]`; `foreignKeys[]`; `indexes[]` with `columns[]` of
  `column`/`expression`/`descending` and `filter`); `summaries[]` (`name`, `sourceSql` — documentation only, never
  executed — `expectedRows`); `expectations` (`totalRows` 155, `usersSanitized`, `usersCount` 12,
  `noDuplicateActiveUsernamesIgnoringCase`); `renameMap`, `excludedTables`, `knownDifferences`.
- Canonical row form: cells joined by `|` in column order; NULL `~`; `i:<decimal>`, `b:1|0`,
  `t:yyyy-MM-dd HH:mm:ss.fff`, `s:<lowercase hex of UTF-8>` (`x:` binary, `g:` guid); rows sorted by their own text in
  byte order, joined by LF, SHA-256 lowercase hex; an empty table hashes the empty string.
- Summary rows: cells joined by `|`, NULL as empty, timestamps as above, booleans 1/0, compared sorted in byte order.

## The database guide

`docs/phase1/dbmigrate/import-postgresql/PostgreSQLDatabaseGuide.html` (also published at
https://claude.ai/artifact/Xhzati1QXvcqPcmt1aQkfD) is generated by `guide/build-guide.py` from `guide/guide.tpl.html`;
every code block is a tested file in `guide/`. Change the file, re-test on a temporary copy, rebuild, republish
(`--artifact <path>`). How: `guide/README.md`. Facts it depends on: the image's `pg_hba.conf` trusts the local socket
and uses `scram-sha-256` over TCP; applications need a login (`mar-roles.sql`, passwords via `\getenv`) and a network
route (container address — use `{{index .NetworkSettings.Networks "bridge" "IPAddress"}}`, the shorter template
concatenates addresses once a second network is attached — a shared Docker network, or an `alpine/socat` proxy on
127.0.0.1). The Phase 2 backend was built from `guide/mar-db-client/` (`docs/phase2/model/MODEL_PLAN.md`).

## Testing changes

Never on `mar-postgres`. Point the tool at another container:

```
sed -e 's/^CONTAINER=.*/CONTAINER=mar-postgres-test/' -e "s|^INPUT_DIR=.*|INPUT_DIR=$PWD/tools/phase1/dbmigrate/import-postgresql/input|" \
    tools/phase1/dbmigrate/import-postgresql/ingest.conf.example > /tmp/test.conf
tools/phase1/dbmigrate/import-postgresql/ingest.sh load --config /tmp/test.conf
tools/phase1/dbmigrate/import-postgresql/ingest.sh verify --config /tmp/test.conf --out /tmp/test-results.json
docker rm -f -v mar-postgres-test
```

Before finishing a change: `ingest.sh all --recreate` passes with the numbers above, `selftest-results.json` is
unchanged, and `guide/build-guide.py` leaves `git status` clean unless the guide was meant to change.

## Known limits

- Verification is against the export's record, not the live SQL Server; it catches mistakes, not tampering.
- Timestamps carry no time zone and the source zone is unknown; no conversion is made.
- Usernames are case-insensitive only through the `lower(name)` index; applications must compare `lower(name) = lower(:input)`.
- The input files contain sanitized but real project data (usernames, timestamps, comment text).
- A fresh clone on Windows and Linux has not been tested for line endings.
