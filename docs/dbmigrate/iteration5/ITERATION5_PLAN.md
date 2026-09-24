# Plan: Iteration 5 - Linux: load the iteration 4 export into a PostgreSQL database in a Docker container, and verify the data is the same

**Status: EXECUTED (2026-09-23).** This is the plan as it was actually carried out, written so the work can be repeated, or rebuilt from scratch, by a person or a new Claude session with no memory of the original conversation. Result of the run: **verification 80 of 80 checks, 155 of 155 rows identical; self-test 7 of 7.** The record of the run, with real numbers, is [ITERATION5.md](ITERATION5.md). The original design version of this plan (before execution) is in git history at commit `60d6267`; §9 lists every place the execution departed from it.

Read this file top to bottom. For background, also read [../iteration4/ITERATION4_PLAN.md](../iteration4/ITERATION4_PLAN.md) (the Windows export that produced this iteration's input) and [../../DATA_MIGRATION.md](../../DATA_MIGRATION.md) §8 (decision log for iterations 4 and 5).

## 1. Goal

The Windows machine exported the legacy SQL Server database (iteration 4) into three files checked into git, with copies in `tools/dbmigrate/iteration5/input/`: `01-schema.sql`, `02-data-sanitized.sql` and `source-metadata.json`. On a Linux machine:

1. Create a fully populated **PostgreSQL** database from the two SQL files, inside a **Docker container**.
2. **Verify** that the database is the same as the SQL Server source, using `source-metadata.json` (the Linux machine cannot reach SQL Server).
3. Prove the verification tooling itself can be trusted (self-test).
4. Write an HTML verification report, and record what happened.

**Non-goals:** exporting from SQL Server (iteration 4, Windows); a baked or published Docker image (no Dockerfile); Oracle; running on Windows.

## 2. Repeating the run (the tool already exists)

On a Linux machine with Docker Engine running, bash and `sha256sum`, from the repository root:

```
tools/dbmigrate/iteration5/ingest.sh all --recreate
```

Expected output ends with `VERIFICATION PASSED - 80 of 80 checks; 155 of 155 rows verified identical`, `SELFTEST PASSED - 7 of 7`, `REPORT WRITTEN: ...` and exit code 0. It rewrites `tools/dbmigrate/iteration5/verification-results.json`, `selftest-results.json` and `docs/dbmigrate/iteration5/MigrationVerificationReport5.html`. If the input files are ever refreshed from iteration 4, copy all three into `input/` (never edit them by hand) and run the same command.

The rest of this plan describes how the tool was built, so it can be rebuilt or changed.

## 3. Principles

1. **The database lives only in the container.** It is never copied to the host and no port is published; all interaction is `docker exec ... psql`.
2. **No secrets anywhere.** The input is sanitized (credentials NULL, `must_reset_password` true). The container's password is random, handed over as a file that is deleted after start-up, and never stored or printed.
3. **Honest verification.** Checks are against `source-metadata.json`, which iteration 4 produced by a code path separate from the SQL rendering, so it is a real end-to-end check of the export and the load. It guards against mistakes, not tampering.
4. **Nothing executable is read from a data file.** Every query is written in `verify.sql` and built with `format('%I', ...)` from names in the metadata.
5. **Fail loudly and specifically.** Every check prints PASS or FAIL with the table or rule concerned; distinct exit codes.
6. **The delivered database is never modified by testing.** Rule tests are rolled back; the self-test uses its own temporary container.
7. **Repeatable.** One command from a fresh clone; `--recreate` rebuilds; outputs are deterministic apart from the run time.

## 4. Settled decisions (as executed)

| # | Decision | As executed |
|---|---|---|
| 5 | Database setup | The container creates the database at first start (`POSTGRES_DB`). The SQL files carry no environment details. A small non-secret settings file supplies names. |
| 6 | PostgreSQL version | 15 or later; the tool refuses an older server (exit 2). |
| 7 | Tooling | bash + Docker only. `psql` runs inside the container. No host `psql`, Python, Java or `jq`. |
| 9 | Reading the metadata | A static `verify.sql` loads the JSON with `\set meta \`cat ...\`` into a temp table as `jsonb` and builds every query itself. |
| 10 | Where the SQL is proven to load | In this container; a rendering bug is fixed in iteration 4's `postgres.ps1` and re-exported, never patched by hand here. |
| 13 | Report | `docs/dbmigrate/iteration5/MigrationVerificationReport5.html`: one self-contained HTML file, built from the results JSON. |
| 15 | Container | Image **`postgres:16.1`** (pinned; already on the machine, and the version iteration 4's load proof used). Container `mar-postgres`, database and user `masterantique`, schema `public`, no published port, no named volume (`docker rm -f -v` deletes the container with the image's anonymous data volume; `--recreate` does exactly that). |
| 16 | A PostgreSQL database guide | **Settled: HTML**, `docs/dbmigrate/iteration5/PostgreSQLDatabaseGuide.html`. Covers psql from bash, application logins (`mar_app`, `mar_readonly`), three network routes (container address, shared Docker network, localhost-only proxy), and a Spring Boot 4.1.1 JPA/JDBC project (Gradle Groovy/Kotlin, Maven) with a first-login password-change mock-up. Every command and file in it was run against a temporary copy of the database. |

## 5. The input contract with iteration 4

Iteration 5 depends on these files and fields. If iteration 4 changes them, this plan and `verify.sql` change with them.

- **Files:** `input/01-schema.sql` (8 tables, 11 indexes, one transaction), `input/02-data-sanitized.sql` (multi-row `INSERT`s and a `setval` per identity table, one transaction), `input/source-metadata.json`.
- **`source-metadata.json`:** `schemaVersion` (1); `meta` (`source`, `minPostgresVersion` 15, `schemaFile`/`schemaSha256`, `dataFile`/`dataSha256`, `sanitizeCredentials`); `run` (`runTimeUtc`, `toolGitCommit` of the export; the only non-deterministic part); `tables[]` in load order (`sourceName`, `targetName`, `rowCount`, `identityLast`, `rowSha256`, `columns[]` with `sourceName`, `sourceType`, `kind` in `int|bit|datetime|string|binary|guid`, `targetName`, `targetType`, `dataType`, `maxLength`, `nullable`, `default`, `identity`, `synthetic`; `primaryKey[]`; `foreignKeys[]` with `targetName`, `columns`, `refTable`, `refColumns`, `onDelete`; `indexes[]` with `targetName`, `unique`, `columns[]` of `column`/`expression`/`descending`, `filter`); `summaries[]` (`name`, `sourceSql` for documentation only, `expectedRows`); `expectations` (`totalRows` 155, `usersSanitized`, `usersCount` 12, `noDuplicateActiveUsernamesIgnoringCase`); `renameMap`, `excludedTables`, `knownDifferences`.
- **Canonical row form and hash** (independent of any database): per table, each row becomes cells joined by `|` in column order; a NULL cell is `~`; otherwise `i:<decimal>`, `b:1|0`, `t:yyyy-MM-dd HH:mm:ss.fff`, `s:<lowercase hex of the UTF-8 bytes>` (`x:` hex for binary, `g:` lowercase guid). Rows are sorted by their own text in byte order (`COLLATE "C"`), joined by LF, and the UTF-8 text is hashed with SHA-256 (lowercase hex). An empty table hashes the empty string (`e3b0c442...`).
- **Summary rows:** cells joined by `|`, NULL as the empty string, timestamps `yyyy-MM-dd HH:mm:ss.fff`, booleans 1/0; compared as rows sorted in byte order.

## 6. Layout

```
tools/dbmigrate/iteration5/
  ingest.sh                   the tool: load | verify | selftest | report | all
  verify.sql                  static verification, run by psql in the container
  report.sql                  renders the HTML report from the results JSON
  ingest.conf.example         non-secret settings (copy to ingest.conf to override)
  README.md                   how to run it and how to reach the database
  .gitattributes              *.sql *.json *.sh *.md ingest.conf.example: text eol=lf
  .gitignore                  ingest.conf, *.log
  input/                      01-schema.sql, 02-data-sanitized.sql, source-metadata.json (from iteration 4)
  verification-results.json   OUTPUT of verify (the report's source)
  selftest-results.json       OUTPUT of selftest
docs/dbmigrate/iteration5/
  ITERATION5_PLAN.md (this file)   ITERATION5.md (record of the run)
  MigrationVerificationReport5.html   OUTPUT of report
  PostgreSQLDatabaseGuide.html        how to connect: psql, logins, network routes, Spring Boot (decision 16)
```

## 7. Execution, step by step

The work was done in six steps, each reviewed before the next. To rebuild, follow the same order.

### Step 1 - Scaffolding

- `.gitattributes` pins `*.sql`, `*.json`, `*.sh`, `*.md` and `ingest.conf.example` to LF: the metadata records hashes of the LF form, string literals may contain raw LF, and bash breaks on CRLF.
- `.gitignore` (per-iteration, as in iteration 3) ignores `ingest.conf` and `*.log`.
- `ingest.conf.example`, bash `key=value`, sourced by `ingest.sh`; without `ingest.conf` the same values are built-in defaults:
  ```
  CONTAINER=mar-postgres
  PG_IMAGE=postgres:16.1
  PG_DATABASE=masterantique
  PG_USER=masterantique
  PG_SCHEMA=public
  INPUT_DIR=input        # relative to the script folder, or absolute
  ```

### Step 2 - `ingest.sh load`

Commands: `load [--recreate]`, `verify [--db <name>] [--out <path>]`, `selftest`, `report`, `all [--recreate]`; `--config <path>` overrides the settings file. Exit codes: **0** ok, **1** verification or self-test differences, **2** configuration, tool or Docker error, **3** refused. Setting values are validated against `^[A-Za-z0-9_.:/-]+$`.

`load`, in order:

1. `docker info` must work, else exit 2 ("Docker is not running or not reachable").
2. **Transfer integrity, before anything starts:** `sha256sum` of both SQL files must equal `schemaSha256` and `dataSha256`, read from the metadata with `grep -o '"<key>": *"[0-9a-f]\{64\}"'`. A mismatch exits 2 and no container is created.
3. If the container exists: without `--recreate` print `REFUSED` and exit 3; with it, `docker rm -f -v`.
4. Pull the image only if it is not present.
5. Generate a random password (`/dev/urandom` → base64 → alphanumerics) into a file in a `mktemp -d` folder (mode 700, file 644). `docker create` with `POSTGRES_DB`, `POSTGRES_USER` and `POSTGRES_PASSWORD_FILE=/tmp/.pgpw` and **no `-p`**; `docker cp` the file into the created container; delete the host copy; `docker start`. (The file, not `POSTGRES_PASSWORD`, keeps the password out of the container configuration and `docker inspect`.)
6. **Wait for readiness** (up to 120 s, polling each second): the log must contain `PostgreSQL init process complete` (the image first runs a temporary server, then restarts) and `psql -c 'select 1'` must succeed twice in a row. Exit 2 if the container stops or time runs out. Then `docker exec ... rm -f /tmp/.pgpw`.
7. `SHOW server_version_num` must be ≥ 150000 and `SHOW server_encoding` must be `UTF8`, else exit 2.
8. If `PG_SCHEMA` is not `public`, `CREATE SCHEMA IF NOT EXISTS`. Every `psql` call passes `-e PGOPTIONS="-c search_path=$PG_SCHEMA"`.
9. `docker cp` the three input files into the container's `/tmp`.
10. `psql -X -q -v ON_ERROR_STOP=1 -U $PG_USER -d $PG_DATABASE -f /tmp/01-schema.sql -f /tmp/02-data-sanitized.sql`. On error exit 2 and leave the container for inspection (reload with `--recreate`).
11. Print the row count per table and the total, then `LOAD COMPLETE`.

All `psql` calls are `docker exec -i ... psql -X -v ON_ERROR_STOP=1 -U $PG_USER -d <db>` over the local socket, which the official image trusts, so no password is needed.

### Step 3 - `verify.sql` and `ingest.sh verify`

`ingest.sh verify` copies `source-metadata.json` and `verify.sql` into the container and runs `psql -q -A -t` with variables `schema_sha`, `data_sha` (host `sha256sum` of the input files), `run_time` (UTC), `tool_commit` (`git rev-parse --short HEAD`, or `unknown`), `image`, `container` and `outfile=/tmp/verification-results.json`. It copies the JSON out (default `tools/dbmigrate/iteration5/verification-results.json`, or `--out`), prints each check as `PASS|FAIL  category  name -- detail`, then `VERIFICATION PASSED - N of N checks; R of R rows verified identical (database D)` (or `FAILED`) and exits 1 if any check failed, 2 if `verify.sql` itself failed. Before each run it deletes the old `/tmp/verification-results.json` in the container: Linux's `protected_regular` rule stops even root from overwriting a file in `/tmp` that another user owns, which broke `verify` after `report` until this was added.

`verify.sql` structure:

- Load the metadata into a temp table `meta(j jsonb)` and the variables into `run_info`. Results go to temp tables `results(seq, status, category, name, detail)`, `table_results`, `summary_results` and `seq_snapshot`. Helper functions live in `pg_temp`: `chk(ok, category, name, detail)` (NULL counts as FAIL), `norm_default` (strip casts and quotes, lowercase), `norm_expr` (strip casts, parentheses, quotes, spaces, lowercase; so `lower(name::text)` equals `lower(name)`), `jdiff` (readable difference between two JSON arrays), `ts` (timestamp → `yyyy-MM-dd HH:mm:ss.fff` or empty).
- Every group of checks is a `DO` block; errors inside are caught and recorded as FAIL, so a broken database produces failures, not a crash.

Checks (80 on this data):

| # | Category | Checks |
|---|---|---|
| 1 | environment (3) | server version ≥ `minPostgresVersion`; encoding UTF8; metadata `schemaVersion` = 1 |
| 2 | integrity (2) | host SHA-256 of each SQL file equals the metadata |
| 3 | counts (9) and hashes (8) | per table, one query built from the column list: `SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(r, E'\n' ORDER BY r COLLATE "C"), ''), 'UTF8')), 'hex') FROM (SELECT concat_ws('\|', <cells>) AS r FROM <table>) x`, with each cell `coalesce('<prefix>:' \|\| <value>, '~')` per `kind` (boolean: `CASE WHEN c THEN '1' WHEN NOT c THEN '0' END`, so NULL stays `~`); compare with `rowCount` and `rowSha256`; plus total rows = `expectations.totalRows` |
| 4 | schema (34) | exactly the expected base tables; per table: columns in order (name, `information_schema` data type, max length, nullability, normalized default, identity `BY DEFAULT`), primary key columns in order (`pg_constraint`), foreign keys (name, columns, referenced table and columns, delete action from `confdeltype`), indexes other than the primary key (name, unique, normalized keys from `pg_get_indexdef`, descending from `indoption`, normalized `pg_get_expr(indpred)`); no invalid index |
| 5 | summaries (10) | ten static PostgreSQL queries keyed by the metadata's summary names (users by type; active vs soft-deleted; users per role; tickets by state; assigned vs unassigned; audit events by action; comments per ticket distribution; comment and commented-ticket totals; ticket date ranges; account and audit date ranges), run with `EXECUTE`, rows sorted `COLLATE "C"` and compared with `expectedRows`; a metadata summary without a query, or a query without a metadata summary, fails |
| 6 | sanitization (4) | `sanitizeCredentials` true; user count = `usersCount`; no user with a password hash or security stamp or without `must_reset_password`; no two active usernames equal ignoring case |
| 7 | rules (10) | **first**, each identity sequence's `pg_sequences.last_value` equals `identityLast` (NULL = never used), without `nextval`, snapshotted; **then** three behaviour tests, each in a block that ends by raising a private error (SQLSTATE `P0999`) so everything it did is rolled back, with explicit ids ≥ 1000001 so no sequence moves: the upper-case form of an active username is rejected (`unique_violation`); after soft-deleting that user, the same name can be inserted; a comment with a non-existent user and ticket is rejected (`foreign_key_violation`); **last**, no test rows remain and no sequence moved |

Output: the check lines, a `SUMMARY<TAB>passed<TAB>total<TAB>rowsVerified<TAB>rowsTotal` line, and (via `\o :outfile`) a `jsonb_pretty` document with `status`, `checksPassed`, `checksTotal`, `rowsVerified`, `rowsTotal`, `database`, `environment` (server version, encoding, image, container, schema), `run` (`runTimeUtc`, `toolGitCommit`), `source`, `sourceExport`, `inputs` (file, expected and actual SHA-256), `tables`, `summaries`, `checks`, `schemaModel` (from the metadata, for the report), `knownDifferences`, `excludedTables`.

### Step 4 - `ingest.sh selftest`

Requires the delivered container to be running (it is compared against), but never modifies it. It uses a separate container `<CONTAINER>-selftest` via a temporary settings file, and removes it (`docker rm -f -v`) at the end. Tests:

1. **Repeatable load:** `load --recreate` + `verify` twice in the self-test container; both exit 0, check lines identical, results JSON identical apart from the `runTimeUtc` lines.
2. **Delivered database matches a fresh load:** `verify` of the delivered container (to a temporary output) gives the same check lines.
3. **Damaged copy detected:** `CREATE DATABASE ingest_selftest_damaged TEMPLATE masterantique` in the self-test container; edit one comment's text, delete the last ticket, drop `ix_users_name_active`; `verify --db` must exit 1 with FAIL lines for tickets (count, hash), comments (hash), the users indexes and the case rule, and no hash failure for untouched tables. Drop the database.
4. **Tampered metadata detected:** copy the inputs, zero the first `rowSha256` (roles); `verify` must exit 1 with exactly one failure, naming roles.
5. **Corrupted input refused:** copy the inputs, change one byte of the data file (`Customer` → `Customes`), point at an unused container name; `load` must exit 2 with "transfer integrity check failed" and create no container.
6. **Existing database protected:** `load` without `--recreate` on the self-test container must exit 3.
7. **Docker unavailable:** with `DOCKER_HOST=unix:///nonexistent/docker.sock`, the tool must exit 2 with "Docker is not running". (Simulated, so other containers on the machine are not stopped.)

Writes `tools/dbmigrate/iteration5/selftest-results.json` (`status`, `passed`, `total`, `tests[]` of `name`, `status`, `detail`; no timestamps) and prints `SELFTEST PASSED - 7 of 7`. On failure it keeps its working folder and says where.

### Step 5 - `ingest.sh report`

Copies `verification-results.json` and `selftest-results.json` (or a `null` stub) into the container as `/tmp/report-results.json` and `/tmp/report-selftest.json`, plus `report.sql`, and runs `report.sql` with `psql` **in the default `postgres` database**: `psql` is only the template engine; the migrated data is not read. `report.sql` escapes every value for HTML (`pg_temp.h`) and writes `/tmp/report.html`, which is copied to `docs/dbmigrate/iteration5/MigrationVerificationReport5.html`.

Page content: title and PASS/FAIL banner ("N of N checks passed · R of R rows verified identical · self-test S of S passed"); executive summary with four tiles; scope and method in plain English with a per-category table; tables with source and loaded counts and hashes; schema per table (source → PostgreSQL columns and types, keys, foreign keys, indexes) and the schema checks; the ten business summaries with CSS bar charts where every row is `label|count` (notes for ticket states 0/1/2 = SUBMITTED/INPROGRESS/COMPLETED and numeric audit actions); credential sanitization; rule tests; tooling self-test; known differences and "what this verification is and is not"; all checks; reproducibility (commands, run time, commit, server version, image, container, file hashes, source and export details). Self-contained (inline CSS, no external files), light and dark themes, `lang`, real headings, table headers with `scope`, wide tables scroll inside their own box at phone width. The same JSON always gives a byte-identical file.

`all` runs load, verify, selftest (in a subshell), report; exit 2 if any step errored, 1 if verify or selftest found differences, else 0.

### Step 6 - Documentation

- `tools/dbmigrate/iteration5/README.md`: how to run it, commands, options, exit codes, settings, working with the database, files.
- `docs/dbmigrate/iteration5/ITERATION5.md`: the record of the run with real numbers, differences from the original plan, things noticed, limitations.
- `docs/DATA_MIGRATION.md`: §3 roadmap row 5, §8.7 and §8.8 status ("planning only" replaced), §9 document map.
- `CLAUDE.md`: the iteration 5 commands bullet and the iterations summary.

## 8. Acceptance criteria (all met on 2026-09-23)

1. `ingest.sh all --recreate` exits 0 with `VERIFICATION PASSED - 80 of 80 checks; 155 of 155 rows verified identical`, `SELFTEST PASSED - 7 of 7` and the report written.
2. `ingest.sh load` without `--recreate` on an existing container exits 3.
3. Negative cases (automated in the self-test): a changed byte in the data file exits 2 before any container exists; a changed hash in the metadata makes `verify` exit 1 naming the table; a damaged database copy makes `verify` exit 1 naming the tables, the index and the rule; Docker unreachable exits 2 with a clear message.
4. The database exists only in the container: no published port (`docker ps` shows `5432/tcp` without a host mapping), no data files on the host, no Docker volume left behind by the self-test.
5. No password in the repository, the container configuration (`docker inspect`) or any output.
6. The report opens offline, its numbers match `verification-results.json`, and a rebuild from the same JSON is byte-identical.

Not yet tested: a fresh clone on Windows and Linux (line endings, §6 `.gitattributes`).

## 9. Differences from the original design plan (commit `60d6267`)

| Original plan | As executed | Why |
|---|---|---|
| Image `postgres:16` | `postgres:16.1` | Already on the machine, pinned for repeatability, and the version iteration 4's load proof used. |
| Password in `POSTGRES_PASSWORD` | `POSTGRES_PASSWORD_FILE`, file deleted after start-up | An environment variable is stored in the container configuration and shown by `docker inspect`. |
| Expected file hashes read through the database after the container is up | Read with `grep` on the host before anything starts | The only reason for the database route was "no `jq`"; now a corrupted file is refused before a container exists. |
| A failing hash names the table and column (optional `columnSha256`) | Names the table only | The metadata has no per-column hashes; adding them is a change to iteration 4. |
| Self-test reloads and damages the delivered container | Separate temporary container | Running the self-test can never damage or replace the delivered database. |
| Negative tests were manual acceptance steps | Automated in `selftest` | Repeatable on every run. |
| Report built with bash and text tools | Rendered by `psql` in the container (`report.sql`) | HTML from JSON in bash without `jq` is fragile; `psql` in the container is allowed tooling. |
| Boolean cell `CASE WHEN c THEN '1' ELSE '0' END` | `CASE WHEN c THEN '1' WHEN NOT c THEN '0' END` | The original turns NULL into `0` instead of `~` (no nullable boolean exists here, so the result was unaffected). |
| Four rule tests | Four, plus "the rule tests left the database unchanged" | Guards against the `nextval` problem found in iteration 4. |

## 10. Risks and known limits

- Verification is against a record made at export, not the live SQL Server database; it guards against mistakes, not tampering.
- The canonical hash depends on iteration 4 and `verify.sql` agreeing byte for byte (empty-table hash, 3-digit timestamps, hex of UTF-8). A hash mismatch with matching counts usually means a formatting disagreement; check the canonical form before suspecting the data.
- `psql`'s `\set var \`cmd\`` runs a shell command in the container; the tool only runs `cat` on files it copied there. Keep it that way.
- Timestamps have no time zone and the source zone is unknown; no conversion is made.
- Usernames are case-insensitive only through the `lower(name)` index; Phase 2 sign-in must compare `lower(name) = lower(:input)`.
- The input files contain sanitized but real project data (usernames, timestamps, comment text).
- A container `mar-postgres-iter4` from iteration 4's build proof is still running on the original machine; it is unrelated to this tool.
