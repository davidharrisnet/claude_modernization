# Plan: Iteration 5 - Linux: load the iteration 4 export into a PostgreSQL database in a Docker container, and verify the data is the same

**Status: planning. Nothing is built yet.** Decisions 5, 6, 7, 9, 10, 13 and 15 are settled; 16 (a database guide) is open. **The input is ready:** iteration 4 has been built and run (2026-09-23), and its three output files are already in `tools/dbmigrate/iteration5/input/` (byte-identical to `tools/dbmigrate/iteration4/`). Section 4 below describes the metadata exactly as iteration 4 built it. During iteration 4's build the generated SQL was loaded into PostgreSQL 16 and all 8 table counts and canonical hashes matched (see `ITERATION4.md`), so the contract in section 4 is proven, not just designed.

**This plan is written for a new Claude session on the Linux machine with no memory of the design conversation.** Read it top to bottom, then read `docs/dbmigrate/iteration4/ITERATION4_PLAN.md` (the Windows export that produced this iteration's input) and `docs/DATA_MIGRATION.md` §5 (security policy). Everything you need to build and run the tool is here. The tool, once built, is a command-line script that needs no AI to run.

## 1. What you are to do (the task in one paragraph)

The Windows machine has already exported the legacy SQL Server database (iteration 4) into three files that are checked into git: `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json`. Copies are in `tools/dbmigrate/iteration5/input/`. On this Linux machine, **read the schema and data files, create a fully populated PostgreSQL database inside a Docker container, and verify that the data in the new database is the same as the source it was exported from**, using `source-metadata.json` (you cannot reach SQL Server from here). Then write the verification report and record what happened.

- **Tool:** `tools/dbmigrate/iteration5/ingest.sh <load|verify|selftest|report|all> [--recreate]`, bash only, plus Docker.
- **Host prerequisites:** Docker Engine (running), bash, `sha256sum`, `docker cp`/`docker exec` access for the current user, and internet access the first time (to pull the PostgreSQL image). **No `psql` on the host, no Python, no Java, no Microsoft tooling.** `psql` runs inside the container.
- **Self-contained:** it reads only `tools/dbmigrate/iteration5/`. It never reads `tools/dbmigrate/iteration1|2|3|4/`.
- Directories: `tools/dbmigrate/iteration5/` and `docs/dbmigrate/iteration5/`.

**Non-goals:** exporting from SQL Server (iteration 4, Windows); a baked or published Docker image; Oracle; running on Windows.

## 2. Principles

1. **The database lives only in the container.** It is never copied to the host. All interaction goes through `docker exec`. (The two SQL files and the metadata JSON are copied *into* the container with `docker cp`; they are inputs, not the database.)
2. **No secrets in git.** The input is sanitized (credentials NULL, `must_reset_password` true). The container's own password is generated at start-up and never stored or printed.
3. **Honest verification.** The tool verifies against `source-metadata.json`, not the live source. That is a real end-to-end check of the iteration 4 renderer and the load, because the metadata was produced by an independent code path. It guards against mistakes, not tampering: anyone with write access could edit both the metadata and the SQL.
4. **Fail loudly and specifically.** Every failure names the table and column (or check) and sets a distinct exit code.
5. **Repeatable.** From a fresh clone, one command reproduces the result; `--recreate` rebuilds it.

## 3. Decision log (iteration 5)

Numbering follows the shared decision list (1-4, 2b, 8, 11, 12, 14 belong to the iteration 4 export).

| # | Decision | Status | Answer / default |
|---|---|---|---|
| 5 | Database and schema setup | **Settled** | The tool starts a PostgreSQL container, which creates the database at first start (`POSTGRES_DB`). The SQL files are environment-free (no database, owner or schema names). A small config file supplies container name, image, database, user and schema (default `public`). The password is generated at container creation, never stored. Nothing is published to the host (no `-p`). |
| 6 | PostgreSQL version | **Settled** | **15 or later.** Default image `postgres:16` (Debian-based, UTF-8). The tool refuses an image whose server reports a version below 15 (exit 2). |
| 7 | Tooling | **Settled** | **bash + Docker only.** `psql`, `createdb` and every PostgreSQL tool run inside the container. Verification is SQL run through `psql`. No Python, no Java, no host PostgreSQL client. |
| 9 | How verification consumes `source-metadata.json` | **Settled** | **Chosen:** a static `verify.sql` reads the JSON with `jsonb`. The JSON holds only structure, counts, hashes and expected results, **no SQL text**. A static, checked-in `verify.sql` reads it with `psql` (`\set meta \`cat /tmp/source-metadata.json\`` inside the container, then `:'meta'::jsonb`) and builds every query itself in PL/pgSQL with `format('%I', ...)` from the metadata's table and column names, so nothing executable is read from a data file. The ten business-summary queries are static in `verify.sql`, keyed by name; the JSON holds their expected rows. **Rejected alternative:** iteration 4 generating a `verify.sql` with the expected values embedded (two generated artifacts to keep consistent, and the JSON would be only a report). |
| 10 | Where the generated SQL is proven to load | **Settled** | In the Docker container on the Linux machine, as part of this iteration. That container **is** the deliverable; no separate throwaway PostgreSQL is needed. (Any rendering bug found here goes back to iteration 4.) |
| 13 | The verification report | **Settled** | **`MigrationVerificationReport5.html`**, in `docs/dbmigrate/iteration5/`. Iteration 5 owns it (section 8). It is HTML, not Word: the earlier reports were built with PowerShell and `System.Drawing` on Windows, which is not available here, and no conversion tool (LibreOffice) is needed. Generated on Linux by `ingest.sh report` from `verification-results.json`, with bash and standard text tools; `psql -H` may render tables. |
| 15 | Container details | **Settled** | **Image** `postgres:16` (must be 15 or later; the tool refuses an older server). **Names:** container `mar-postgres`, database and user `masterantique`. **Password:** generated at container creation, never stored or printed; inside the container `docker exec ... psql` connects over the local socket without one. **Network:** no published port, so nothing on the host or network can reach the database. **Storage:** the database lives in the container's own storage (as in iteration 2), with no named volume; `docker stop`/`start` keeps it, `docker rm -f -v` deletes it, and `--recreate` does exactly that. |
| 16 | A PostgreSQL database guide (how to interact with the Dockerized database) | **Open** | Iterations 1-3 each produced a database guide. Iteration 5 has none yet. A guide covering `docker exec ... psql`, one-off queries, scripts, safe experiments, lifecycle and troubleshooting would fit. Decide whether to write one and in which format (HTML or Markdown). |

The hand-off of the three input files from iteration 4 is a manual copy (into `input/`, committed from Windows); automating it is out of scope for now.

## 4. The contract with iteration 4

Iteration 5 depends on these files and fields. If iteration 4 changes them, this plan changes with it.

**Files** (copied into `tools/dbmigrate/iteration5/input/` on Windows at hand-off, then committed): `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`.

**`source-metadata.json`:**
- `schemaVersion` (1); `meta`: `iteration`, `source` (server, database, version), `minPostgresVersion` (15), `schemaFile`/`schemaSha256` and `dataFile`/`dataSha256` (SHA-256 of the two SQL files), `sanitizeCredentials`. The separate top-level `run` section (`runTimeUtc`, `toolGitCommit`) is the only non-deterministic part; ignore it when verifying.
- `tables[]` in load order: `sourceName`, `targetName`, `rowCount`, `identityLast` (or null), `rowSha256`, `columns[]` in column order (`sourceName`, `sourceType`, `kind` in `int|bit|datetime|string|binary|guid`, `targetName`, `targetType`, `dataType` and `maxLength` as `information_schema` reports them, `nullable`, `default`, `identity`, `synthetic`), `primaryKey[]` (target names, in order), `foreignKeys[]` (`targetName`, `columns`, `refTable`, `refColumns`, `onDelete`), `indexes[]` (`targetName`, `unique`, `columns[]` with `column`, `expression` (e.g. `lower(name)`) and `descending`, and the partial `filter` such as `deleted_at IS NULL`).
- `summaries[]`: `name`, `sourceSql` (SQL Server text, **documentation only, never execute it**) and `expectedRows` for the ten business summaries. `expectedRows` are sorted ordinally; cells are joined by `|`; **NULL is the empty string**; timestamps are `yyyy-MM-dd HH:mm:ss.fff`; booleans 1/0. Iteration 5 writes its own PostgreSQL query for each summary, keyed by `name`, and formats its output the same way.
- `renameMap`, `excludedTables`, `knownDifferences` (for the report).
- `expectations`: `totalRows` (155), `usersSanitized` (every `users` row has NULL `password_hash` and `security_stamp` and `must_reset_password` true), `usersCount` (12), `noDuplicateActiveUsernamesIgnoringCase`.

**Canonical row form and hash** (defined independent of any database; computed on Windows from the sanitized in-memory rows and recomputed here in SQL):
- **Rows sorted ascending by their own canonical text (ordinal, byte order), not by primary key**, joined by LF; cells joined by `|` in column order; a NULL cell is `~`; otherwise a one-letter prefix and a value: `i:<decimal>`, `b:1|0` (boolean), `t:yyyy-MM-dd HH:mm:ss.fff` (timestamp), `s:<lowercase hex of the UTF-8 bytes>` (string). The table hash is the lowercase hex SHA-256 of the UTF-8 text. An **empty table hashes the empty string** (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- PostgreSQL side: per cell `coalesce('i:'||col::text,'~')`, `coalesce('b:'||(case when col then '1' else '0' end),'~')`, `coalesce('t:'||to_char(col,'YYYY-MM-DD HH24:MI:SS.MS'),'~')`, `coalesce('s:'||encode(convert_to(col,'UTF8'),'hex'),'~')`; row = `concat_ws('|', cells)` (every cell is coalesced, so `concat_ws` never drops one); table = `encode(sha256(convert_to(coalesce(string_agg(row, E'\n' ORDER BY row COLLATE "C"), ''), 'UTF8')), 'hex')`. `sha256()` is built in. **Proven:** a dynamic PL/pgSQL `DO` block that loops over `tables[]`/`columns[]` in the JSON (loaded with `\set meta \`cat /tmp/source-metadata.json\`` and `CREATE TEMP TABLE meta AS SELECT :'meta'::jsonb AS j`), builds each query with `format('%I', targetName)` and a `CASE` on `kind`, and compares with `rowSha256`, matched all 8 tables on PostgreSQL 16 (so `verify.sql` needs no SQL text from the JSON).

## 5. Layout

```
tools/dbmigrate/iteration5/
  README.md                how to run it (no Claude needed)
  ingest.sh                load | verify | selftest | report | all
  ingest.conf.example      non-secret settings; copy to ingest.conf (ingest.conf is gitignored)
  verify.sql               static verification, reads source-metadata.json (decision 9)
  input/                   01-schema.sql, 02-data-sanitized.sql, source-metadata.json (copied from iteration 4 at hand-off)
  verification-results.json   OUTPUT of verify (the report's source)
  .gitattributes           *.sql, *.json, *.sh: text eol=lf
docs/dbmigrate/iteration5/
  ITERATION5_PLAN.md (this file)   ITERATION5.md (written after the real run)
  MigrationVerificationReport5.html   (this iteration's responsibility; decision 13)
```

`ingest.conf` (bash `key=value`, sourced; non-secret): `CONTAINER=mar-postgres`, `PG_IMAGE=postgres:16`, `PG_DATABASE=masterantique`, `PG_USER=masterantique`, `PG_SCHEMA=public`, `INPUT_DIR=input`.

## 6. Commands and exit codes

`ingest.sh load [--recreate]`, `verify`, `selftest`, `report`, `all [--recreate]` (load, verify, selftest, report). `--config <path>` overrides `ingest.conf`.

Exit codes (same convention as iterations 1-3): **0** ok, **1** verification differences, **2** configuration, tool or Docker error (Docker not running, image cannot be pulled, transfer-integrity failure, server older than 15), **3** refused (the container or its populated database already exists and `--recreate` was not given).

### 6.1 `load`
1. Read the config. Confirm `docker` works (`docker info`); exit 2 with a clear message if not.
2. **Transfer integrity:** `sha256sum` of `input/01-schema.sql` and `input/02-data-sanitized.sql` must equal `schemaSha256` and `dataSha256` in the metadata (exit 2 on mismatch). Read the expected values without `jq`: ask the database for them after the container is up (`select :'meta'::jsonb -> 'meta' ->> 'schemaSha256'`), so do this check after step 4 and before step 5.
3. If the container exists: without `--recreate` exit 3; with `--recreate`, `docker rm -f -v $CONTAINER`.
4. Start the container: `docker run -d --name $CONTAINER -e POSTGRES_DB=$PG_DATABASE -e POSTGRES_USER=$PG_USER -e POSTGRES_PASSWORD=<random, generated here, not stored> $PG_IMAGE`. No published port. Wait until `pg_isready` succeeds inside the container (bounded wait, then exit 2). Note: the official image restarts the server once during first-time initialisation, so poll until `psql -c 'select 1'` succeeds against the *database* twice in a row, not merely `pg_isready`.
5. Check `SHOW server_version_num` >= 150000 and `SHOW server_encoding` = UTF8 (exit 2 otherwise).
6. `docker cp` the three input files into the container's `/tmp`. If `PG_SCHEMA` is not `public`: `CREATE SCHEMA IF NOT EXISTS`. Set `PGOPTIONS="-c search_path=$PG_SCHEMA"` on every later `docker exec` (`-e PGOPTIONS=...`).
7. `docker exec $CONTAINER psql -X -v ON_ERROR_STOP=1 -U $PG_USER -d $PG_DATABASE -f /tmp/01-schema.sql -f /tmp/02-data-sanitized.sql`. Stop at the first error and print it. Both files run their own `BEGIN`/`COMMIT`.

Inside the container the official image trusts local socket connections, so `docker exec ... psql` needs no password.

### 6.2 `verify`
Read-only against the database except for the rolled-back rule tests. Runs `docker exec ... psql -X -q -A -t -v ON_ERROR_STOP=1 -f /tmp/verify.sql` (copy `verify.sql` in with `docker cp`); `verify.sql` prints one line per check, `PASS<TAB>category<TAB>name<TAB>detail` or `FAIL<TAB>...`. `ingest.sh` counts the `FAIL` lines, prints a summary (`VERIFICATION PASSED - N of N checks; N of N rows verified identical`), records every check, count, hash and tool version in `tools/dbmigrate/iteration5/verification-results.json` (the report's source), and exits 1 if any failed. Checks:

1. **Environment:** `server_version_num` >= 150000; `server_encoding` = UTF8.
2. **Row counts** per table against `rowCount`.
3. **Content hashes:** per-table canonical hash (section 4) against `rowSha256`. A mismatch names the table; to name the column, also compute a per-column hash on mismatch against an optional `columnSha256` field (add it to the iteration 4 contract if wanted).
4. **Schema:** from `information_schema` and `pg_catalog`, compare columns (name, type, nullability, default), primary keys, foreign keys with delete actions, indexes (unique, partial predicate, the `lower(name)` expression on `ix_users_name_active`, the plain unique `ix_roles_name`) and identity columns (`GENERATED BY DEFAULT`) with the metadata; no invalid indexes (`pg_index.indisvalid`).
5. **Business summaries:** the ten queries (static in `verify.sql`, snake_case names) against `expectedRows`.
6. **Sanitization:** every `users` row has NULL `password_hash` and `security_stamp` and `must_reset_password` true.
7. **Rule tests**, each a PL/pgSQL `DO` block with `EXCEPTION` handling, all inside a transaction that is rolled back:
   - inserting a second **active** user whose name differs only by case from an existing one raises `unique_violation`;
   - a **soft-deleted** username can be reused (set `deleted_at` on the existing row, then the insert succeeds);
   - an orphan foreign key (`comments` with a non-existent user and ticket) raises `foreign_key_violation`;
   - each identity sequence state equals `identityLast` (read `pg_sequences.last_value`; **do not call `nextval`**, it is not rolled back and would burn an id). **Ordering matters (found during iteration 4's PostgreSQL check):** `nextval` is not rolled back even when the insert fails, so any rule-test insert that relies on the identity default advances the sequence permanently (a test run moved `users_id_seq` from 12 to 14 and `comments_id_seq` from 26 to 27). Therefore **check the sequence states first, before the rule tests, and give every test insert an explicit id well above the data (for example 1000001 and up)**, which `GENERATED BY DEFAULT` accepts without touching the sequence.

### 6.3 `selftest`
Proves the tooling, like iterations 1-3: (1) `load` twice from a clean state produces identical `verify` results (determinism); (2) in the same container, `CREATE DATABASE selftest TEMPLATE $PG_DATABASE`, change one comment and delete one ticket there, and run `verify` against `selftest`; it must exit 1 and name the table and column; then drop `selftest`. (`verify` therefore takes an optional `--db <name>`.)

## 7. Git and repeatability

- Check in `ingest.sh`, `ingest.conf.example`, `verify.sql`, `README.md`, `input/*`, `.gitattributes`, and the results JSON and report once produced. Gitignore `ingest.conf` and local logs.
- `.gitattributes` pins `*.sql`, `*.json`, `*.sh` to LF. The metadata records SHA-256 hashes of the LF form, string literals may contain raw LF, and bash scripts break with CRLF. Verify after a fresh clone on Linux.
- A fresh clone plus `ingest.conf` and a running Docker Engine must be enough to reproduce the result. No other setup.

## 8. The verification report (`MigrationVerificationReport5.html`)

Iteration 5 owns this file (decision 13). It follows the content pattern of `MigrationVerificationReport{N}.docx` in iterations 1-3 but is a single, self-contained HTML file (inline CSS, no external assets, viewable offline). Contents: an executive summary and PASS/FAIL banner ("N of N checks passed, N of N rows verified identical"), a scope and method section in plain English, per-table row counts and hashes, the schema comparison, the ten business summaries, the rule tests, known differences, and a reproducibility section (commands, input file hashes, tool versions, image tag, run time). Simple charts, if any, are inline SVG or CSS bars. Basic accessibility: real headings, table headers, and text alternatives. Its source is `verification-results.json` (section 6.2), which `verify.sql` can assemble as a `jsonb` document that `psql` prints (no `jq`). `ingest.sh report` builds the HTML from that JSON with bash and standard text tools; a rebuild from the same JSON is byte-identical except for the run-time section.

## 9. Acceptance criteria (definition of done)

On a Linux machine with only Docker Engine, bash and `sha256sum`, from a fresh clone:

1. `ingest.sh all` exits 0 and prints `VERIFICATION PASSED`, with every check PASS: 155 of 155 rows, all eight table hashes, schema, ten summaries, sanitization, four rule tests; and `SELFTEST PASSED`.
2. `ingest.sh load` run again without `--recreate` exits **3**.
3. `ingest.sh all --recreate` rebuilds and passes again (repeatable).
4. Negative tests: a changed byte in a copy of `input/02-data-sanitized.sql` exits **2** (transfer integrity); a changed hash in a copy of the metadata makes `verify` exit **1** naming the table; Docker stopped exits **2** with a clear message.
5. The database exists only in the container: no PostgreSQL data files on the host, no published port.
6. Nothing in the repository contains a password, and `verify` output contains no credential values.
7. `ingest.sh report` writes `MigrationVerificationReport5.html`; it opens in a browser offline, its numbers match `verification-results.json`, and rebuilding it from the same JSON gives an identical file (apart from the run-time section).

## 10. Build order for a fresh session

1. Read this plan, `ITERATION4_PLAN.md` and `DATA_MIGRATION.md` §5. Confirm the three files are in `input/` and that their hashes match the metadata. All decisions are settled except 16 (database guide, section 3); confirm that one with the user, and do not reopen the others.
2. Write `.gitattributes`, `ingest.conf.example`, and `ingest.sh load` (section 6.1); run it and inspect the database with `docker exec ... psql`.
3. Write `verify.sql` and the `verify` path (section 6.2), starting with counts and hashes, then schema, summaries, sanitization, rule tests. Write `verification-results.json`.
4. Write `selftest` (section 6.3) and run the acceptance criteria (section 9), including the negative tests.
5. Write the report step (section 8); write the database guide if decision 16 says so; write `README.md`; write `docs/dbmigrate/iteration5/ITERATION5.md` (what actually happened, real numbers); update `docs/DATA_MIGRATION.md` (§3 roadmap, §8 and §9 document map) and the commands paragraph of `CLAUDE.md`.
6. If a SQL rendering bug is found, fix it in iteration 4's `postgres.ps1` on the Windows machine, re-export, and re-copy the three files; do not patch the SQL by hand.

## 11. Risks and known limits

- Verification is against a manifest produced on Windows, not the live SQL Server database (principle 3).
- `psql`'s `\set var \`cmd\`` runs a shell command inside the container; the tool only ever runs `cat` on a path it created. Keep it that way.
- The canonical hash depends on iteration 4 and this tool agreeing on the form byte for byte (empty-table hash, timestamp truncation to 3 digits, hex of UTF-8). A mismatch on a single table with matching counts usually means a formatting disagreement; check the canonical form before suspecting the data.
- PostgreSQL defaults are reported by `information_schema` in a different form from the SQL (for example `false` versus `'false'::boolean`); normalize before comparing.
- Timestamps carry no time zone and the source zone (UTC or local) is unknown (iteration 4, decision 3); this tool makes no conversion.
- Usernames are case-insensitive only through the `lower()` index; Phase 2 authentication must compare `lower(name) = lower(:input)`.
- The first `docker run` needs internet access to pull the image; the official image restarts once during first-time initialisation (step 4 of `load` handles it).
- The input files contain sanitized but real project data (usernames, timestamps, comment text).
