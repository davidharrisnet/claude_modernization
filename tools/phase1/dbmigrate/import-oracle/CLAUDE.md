# import-oracle — instructions for Claude Code

This folder is the import-oracle tool: it loads the Oracle export written by export-oracle into an Oracle AI Database 26ai Free
container on Linux and verifies it against the export's record of the source. It runs when the user says **`Run import-oracle`**.
It is a proof of concept alongside PostgreSQL (Phase 2 stays on PostgreSQL). The human description is
`docs/phase1/dbmigrate/import-oracle/README.md`; the strategy and security policy is `docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5
security, §10 the Oracle decisions). The Windows side that writes the input files is `tools/phase1/dbmigrate/export-oracle/CLAUDE.md`.
The tool is self-contained: it needs no PostgreSQL folder. It has a PostgreSQL counterpart, import-postgresql, with the same design
(commands, exit codes, check categories, self-test); if that folder is present, keep the two alike when changing either.

## Rules

1. **Never edit `input/` by hand.** It holds export-oracle's three output files. To refresh them, re-export on Windows
   (`Run export-oracle`) and copy all three together.
2. **Never fix rendering bugs here.** If the SQL fails to load or a hash disagrees because of how export-oracle wrote the SQL, name
   the statement and the rule in `tools/phase1/dbmigrate/export-oracle/migration/dialects/oracle.ps1` that must change, and let the
   user re-run the export. Do not patch the SQL or `input/`.
3. **Never test on the delivered database.** Use another container through `--config` (see "Testing changes"). `mar-oracle` is
   changed only by `load --recreate` / `all --recreate`.
4. **No secrets.** The tool never needs a password: it logs in as SYS by operating-system authentication inside the container, and
   the application schema has none (see "How `load` works"). No password in git, a file left behind, a command line or the output.
5. **Nothing executable comes from a data file.** `verify.sql` builds every query itself from metadata names that must match
   `^[a-z][a-z0-9_]*$` and pass `DBMS_ASSERT.SIMPLE_SQL_NAME`; the metadata's `sourceSql` is never run.
6. **Generated files are never edited by hand**: `verification-results.json`, `selftest-results.json`,
   `docs/phase1/dbmigrate/import-oracle/MigrationVerificationReport.html`, `docs/.../OracleDatabaseGuide.html` (see `guide/README.md`).
7. **Keep LF line endings** (`.gitattributes`): the metadata records hashes of the LF form, and bash breaks on CRLF.
8. **Only bash and Docker on the host for the tool** (plus `sha256sum`, `grep`, `sed`, `awk`): `sqlplus` runs inside the container.
   No Python, Java, `jq` or host Oracle client in `ingest.sh`. The database guide is separate: its
   builder is Python 3 (standard library) and its sample project needs Java 21 with Gradle or Maven.
9. **No commit and no git command that changes anything.** The user reviews `git status` and commits.

## Run

From the repository root, on Linux with Docker Engine running:

```
tools/phase1/dbmigrate/import-oracle/ingest.sh all --recreate
```

Expected (about 6 minutes, three database starts): exit 0, `VERIFICATION PASSED - 86 of 86 checks; 155 of 155 rows verified
identical`, `SELFTEST PASSED - 7 of 7`, `REPORT WRITTEN: ...`. Commands: `load [--recreate]`, `verify [--schema <name>] [--out
<path>]`, `selftest`, `report`, `all [--recreate]`; `--config <path>` replaces the settings. Exit codes: 0 ok, 1 differences,
2 configuration/tool/Docker error, 3 refused (container exists, no `--recreate`). After a successful run, update the "Latest results"
section of the docs README if any number changed.

Look around: `docker exec -it mar-oracle sqlplus / as sysdba`, then `ALTER SESSION SET CONTAINER = FREEPDB1;` and
`ALTER SESSION SET CURRENT_SCHEMA = masterantique;`.

## Settings

`ingest.conf.example` (bash `key=value`, sourced; copy to `ingest.conf`, which is gitignored). Built-in defaults:
`CONTAINER=mar-oracle`, `ORA_IMAGE=gvenzl/oracle-free:23.26.3-faststart`, `ORA_PDB=FREEPDB1`, `ORA_USER=masterantique`,
`INPUT_DIR=input` (relative to this folder, or absolute). Values must match `^[A-Za-z0-9_.:/-]+$`; `ORA_PDB` and `ORA_USER` must be
plain identifiers. The tool refuses a server older than 23 or a character set other than `AL32UTF8`.

## Environment (confirmed on the Linux machine)

- **Image** `gvenzl/oracle-free:23.26.3-faststart` (community image, Docker Hub, no login; about 1.7 GB to download, 7.7 GB on disk).
  The database is prebuilt in the image, so a container is ready in about 30 seconds. Why not the official
  `container-registry.oracle.com/database/free`: its registry needs a token even to list tags, and it prints a generated password in the log.
- `v$version`: "Oracle AI Database 26ai Free Release 23.26.3.0.0"; `v$instance.version_full` 23.26.3.0.0; `compatible` 23.6.0.
- Pluggable database / service `FREEPDB1`; default tablespace `USERS`; `NLS_CHARACTERSET` `AL32UTF8`; `MAX_STRING_SIZE` `STANDARD`;
  `NLS_LENGTH_SEMANTICS` `BYTE` (the export's `CHAR` lengths are explicit, so this does not matter).
- Readiness: the log line `DATABASE IS READY TO USE!`, then `SELECT 1 FROM dual` in the pluggable database twice in a row.
- `sqlplus` is on the `oracle` user's PATH (the default `docker exec` user); there is no SQLcl; there is no `ps` or `which`.
- The image sets `NLS_LANG=.AL32UTF8`; the tool also passes `NLS_LANG=AMERICAN_AMERICA.AL32UTF8` so output is UTF-8.

## Layout

```
ingest.sh                   the tool
verify.sql                  verification, one PL/SQL block run by sqlplus inside the container
report.sql                  renders the HTML report from the results JSON (PL/SQL as the template engine, in the root container)
ingest.conf.example         settings
input/                      01-schema.sql, 02-data-sanitized.sql, source-metadata.json (from export-oracle)
verification-results.json   written by verify (the report's source)
selftest-results.json       written by selftest
guide/                      sources of the database guide (own README)
README.md                   how to run the tool (for people)
.gitattributes, .gitignore  LF endings; ignores ingest.conf, *.log, guide build output
```

The repository root is found by counting folders up from this one (`REPO_ROOT="$HERE/../../../.."` in `ingest.sh`); fix it if this
folder moves.

## How `load` works

1. `docker info` must succeed, else exit 2.
2. **Transfer integrity before anything starts:** `sha256sum` of both SQL files must equal `schemaSha256` and `dataSha256` in the
   metadata (read with `grep -o`, no `jq`); a mismatch exits 2 and no container is created.
3. Existing container: exit 3, or with `--recreate` `docker rm -f -v`.
4. Pull the image only if missing.
5. **Passwords.** The image insists on a SYS/SYSTEM password at first start. It gets a random one through `ORACLE_PASSWORD_FILE`
   (a file `docker cp`'d to `/tmp/.orapw` before start; why: an environment variable is shown by `docker inspect`, which here shows
   only the file path). No `-p`. After readiness the file is deleted **as root** (why: `docker cp` gives it the host uid, and the
   `oracle` user cannot delete it from the sticky `/tmp`). Then SYS, SYSTEM and **PDBADMIN** get fresh random passwords through
   sqlplus's stdin that nobody keeps, and PDBADMIN is locked. Why PDBADMIN: it is the pluggable database's administrator (role
   `PDB_DBA`) and keeps the password it was given when the image was built; the entrypoint resets only SYS and SYSTEM. Don't use
   `ORACLE_RANDOM_PASSWORD`: it is 8 characters derived from the clock and printed in the log.
6. Version (≥ 23) and character set (`AL32UTF8`) checked, else exit 2.
7. `docker cp` the two SQL files to `/tmp/marload/`; as SYS: `CREATE USER masterantique NO AUTHENTICATION DEFAULT TABLESPACE users
   QUOTA UNLIMITED ON users` (a schema-only account: nobody can log in as it), `ALTER SESSION SET CURRENT_SCHEMA = masterantique`,
   `@01-schema.sql`, `@02-data-sanitized.sql`. Unqualified `CREATE TABLE`, `CREATE INDEX` and `INSERT` land in that schema (confirmed;
   nothing is created in SYS). On error exit 2 and leave the container for inspection: DDL commits by itself, so the objects created
   before the error stay (confirmed: the scripts' `WHENEVER SQLERROR EXIT FAILURE` stops sqlplus with exit 1 at the first error).
8. Print row counts, then `LOAD COMPLETE`.

All sqlplus calls are `docker exec -i <container> sqlplus -S -L / as sysdba` with the script on stdin. As SYS with `CURRENT_SCHEMA`
set, the `USER_*` views still describe SYS: use `DBA_*` filtered by `OWNER = 'MASTERANTIQUE'`.

## How `verify` works

`ingest.sh verify` copies the metadata and `verify.sql` to `/tmp/marverify/` in the container and feeds sqlplus a prologue of
`DEFINE` lines (pluggable database, schema, host SHA-256 of both SQL files, run time, tool commit, image, container; each checked
against a strict pattern), then `@verify.sql`. `verify.sql` creates a directory object on that folder, reads the JSON with
`DBMS_LOB.LOADCLOBFROMFILE` into `JSON_OBJECT_T`, runs every check in one PL/SQL block, prints one line per check (`PASS|FAIL` TAB
category TAB name TAB detail), a `SUMMARY` line and the results JSON between `JSON-BEGIN` and `JSON-END` (pretty-printed with
`JSON_SERIALIZE ... PRETTY`), rolls back, and drops the directory object; `ingest.sh` removes the folder, writes the JSON (default
`verification-results.json`, or `--out`) and exits 1 on any FAIL, 2 if sqlplus fails. Every query on the migrated schema is dynamic
SQL, and every group catches its own errors, so a missing table or column is a FAIL, not a crash.

| Category (count) | What is checked |
|---|---|
| environment (4) | version ≥ `minOracleVersion` (23); `AL32UTF8`; `MAX_STRING_SIZE` recorded; metadata `schemaVersion` 1 |
| integrity (2) | host SHA-256 of each SQL file = metadata |
| counts (9), hashes (8) | per table `count(*)` and the canonical content hash (below) = `rowCount` / `rowSha256`; total rows |
| schema (35) | exact set of tables; per table columns in order (name, `DATA_TYPE`, `CHAR_LENGTH` with `CHAR_USED = 'C'`, precision, scale, nullability, `DATA_DEFAULT_VC` normalized, identity `BY DEFAULT`), primary key (`pk_<table>` and columns), foreign keys (name, columns, target, `DELETE_RULE`), indexes (name, uniqueness, keys with expressions from `DBA_IND_EXPRESSIONS`, direction; LOB indexes and the primary-key index excluded); no unusable or disabled index; no name in `V$RESERVED_WORDS` with `RESERVED = 'Y'` |
| summaries (10) | ten Oracle queries keyed by the metadata's summary names, `ORDER BY` under `NLS_SORT = BINARY`, compared with `expectedRows`; a missing or extra query fails |
| sanitization (4) | `sanitizeCredentials`; user count; no password hash or security stamp, all `must_reset_password`; no active usernames equal ignoring case |
| rules (14) | **first** each identity's `DBA_SEQUENCES.LAST_NUMBER` = `identityLast + 1` (1 for the never-restarted empty `user_claims`), read without `NEXTVAL`; **then** seven tests, each between `SAVEPOINT` and `ROLLBACK TO`, with explicit ids ≥ 1000001: upper-case duplicate of an active username rejected (ORA-00001), soft-deleted username reusable, two soft-deleted users with the same name allowed, orphan comment rejected (ORA-02291), `BOOLEAN` rejects `'maybe'` (ORA-61800), a `CHR`/`UNISTR` literal with quote, backslash, ampersand, TAB/CR/LF, é and an emoji comes back as the expected UTF-8 bytes, 2,000 two-byte characters fit in `comments.text` while 1,334 three-byte ones are rejected (ORA-12899) under `STANDARD`; **last** no test rows left and no sequence moved |

**Canonical content hash.** Must equal `rowSha256` byte for byte. `table_hash` builds one `SELECT` from the metadata's columns
(`TO_CHAR(n)`; `CASE WHEN c THEN '1' WHEN NOT c THEN '0' END`; `TO_CHAR(ts, 'YYYY-MM-DD HH24:MI:SS.FF3')`; strings as stored), fetches
with `DBMS_SQL` (a `CLOB` column into a CLOB), makes each cell (`~` for NULL, `i:`, `b:`, `t:`, `s:` + `LOWER(RAWTOHEX(UTL_RAW.CAST_TO_RAW(v)))`;
a CLOB through `DBMS_LOB.CONVERTTOBLOB` to UTF-8 then hex), joins cells with `|`, and counts rows in an associative array indexed by the row
text; with `NLS_SORT = BINARY` its keys come back in byte order (confirmed). The rows are joined with LF into a CLOB and hashed with
`DBMS_CRYPTO.HASH(clob, HASH_SH256)`; an empty CLOB hashes to `e3b0c442…` (confirmed), so empty tables need no special case. A hash
mismatch with matching counts usually means the canonical form disagrees (3-digit timestamps, hex of UTF-8); check that before
suspecting the data.

## How `selftest` works

Needs the delivered container running (compared against) but never changes it; everything else happens in `<CONTAINER>-selftest`,
removed at the end. Seven tests: two fresh loads give identical results (JSON compared without the
`runTimeUtc` lines); the delivered database gives the same check lines (why no system-generated names such as `ISEQ$$_…` may appear
in a detail); a damaged copy (a second schema `ingest_selftest_damaged` loaded from the same files in the self-test container, then one
comment edited, the last ticket deleted, `ix_users_name_active` dropped) makes verify exit 1 naming tickets, comments, the users
index and the case rule; a zeroed `rowSha256` for roles gives exactly one failure; one changed byte in the data file makes `load`
exit 2 before any container exists; `load` without `--recreate` exits 3; `DOCKER_HOST=unix:///nonexistent/docker.sock` gives exit 2.
Writes `selftest-results.json` (no timestamps).

## How `report` works

Copies the two results files (or a `null` stub for a missing self-test) and `report.sql` to `/tmp/marreport/` and runs `report.sql`
in the container's **root** (no pluggable database: it reads only the JSON). It builds the page in a CLOB and prints it between
`HTML-BEGIN` and `HTML-END`; `ingest.sh` writes it to `docs/phase1/dbmigrate/import-oracle/MigrationVerificationReport.html`.
Self-contained HTML (inline CSS, light/dark, phone width), sections: summary, method, tables, schema, summaries, sanitization, rules, self-test, known differences, all checks, reproducibility; the same JSON always gives
the same bytes (checked). `all` runs load, verify, selftest (subshell), report; exit 2 if any step errored, 1 if verify or selftest
found differences.

## The database guide

`docs/phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html` is generated by `guide/build-guide.py` from
`guide/guide.tpl.html`; every code block is a tested file in `guide/`. Change the file, re-test on a temporary copy
(`mar-oracle-guide`, never `mar-oracle`), rebuild. How: `guide/README.md`. Facts it depends on, all tested: applications log in
as `mar_app` / `mar_readonly` created by `mar-roles.sql` (passwords as SQL*Plus `DEFINE` values on stdin with `SET VERIFY OFF`;
Oracle 23ai schema privileges `GRANT ... ANY TABLE ON SCHEMA masterantique`, which also cover identity columns); the logins do not
own the tables, so each session needs `ALTER SESSION SET CURRENT_SCHEMA = masterantique` (Hikari `connection-init-sql` in
Spring Boot); the JDBC URL names the service, `jdbc:oracle:thin:@//host:port/FREEPDB1`; network routes
(container address, shared Docker network, `alpine/socat` proxy on 127.0.0.1:1522); sign-in must compare
`CASE WHEN deleted_at IS NULL THEN LOWER(name) END = LOWER(:input)` to use the index; SQL*Plus commits on `EXIT` unless
`SET EXITCOMMIT OFF`.

## Gotchas (SQL*Plus and Oracle)

- **SQL*Plus substitutes `&name` everywhere**, in PL/SQL text and comments too, and then waits for input, swallowing the next lines.
  `verify.sql` uses substitution for its `DEFINE` values, so it contains no other ampersand (`CHR(38)` in the round-trip test);
  `report.sql` starts with `SET DEFINE OFF` because the HTML has entities.
- **A line starting with `@` runs a script**, even inside a PL/SQL string: `report.sql` writes `CHR(64) || 'media ...'` for CSS.
- **`ALTER SESSION SET CONTAINER` resets the DBMS_OUTPUT buffer**: `SET SERVEROUTPUT ON` comes after it.
- **`EXIT` commits by default**: `WHENEVER SQLERROR EXIT FAILURE ROLLBACK` and `EXIT SUCCESS ROLLBACK` in `verify.sql`; DDL (`DROP
  DIRECTORY`) comes only after the final `ROLLBACK`.
- **`JSON_ELEMENT_T.parse('null')` fails** (ORA-40587), so `report.sql` tests for the word first.
- **`RPAD` cuts silently at 4,000 bytes** under `MAX_STRING_SIZE = STANDARD`: long test strings are built in a PL/SQL loop.
- **`LAST_NUMBER` is the next value only until the sequence is used**; after that it is the cache's high-water mark (cache 20). The
  check is valid right after a load, which is when verify runs; a delivered database that an application has used will fail it.
- **`BOOLEAN` converts** numbers (non-zero is TRUE) and the words `yes/no/on/off/true/false/t/f/y/n/1/0`; only other text is rejected.
- `DATA_DEFAULT_VC` (23ai) reads a default without the LONG `DATA_DEFAULT`; `DBA_IND_EXPRESSIONS.COLUMN_EXPRESSION` is a LONG, read
  in a PL/SQL cursor loop; it shows `CASE  WHEN "DELETED_AT" IS NULL THEN LOWER("NAME") END `, compared after removing quotes, spaces
  and parentheses.
- The function-based index adds a hidden virtual column `SYS_NC00017$` to `users`; `DBA_TAB_COLUMNS` does not list it.

## Input contract with export-oracle

If export-oracle changes any of this, `verify.sql` changes with it. The metadata contract is defined in
`tools/phase1/dbmigrate/export-oracle/CLAUDE.md` ("Contracts"); the Oracle-specific parts: `meta.minOracleVersion`; `columns[]` with
`dataType` in `ALL_TAB_COLUMNS` spelling, `maxLength` in characters, `precision`, `scale`; `indexes[].columns[].expression` as the full
key expression; `foreignKeys[].onDelete` `NO ACTION` for an omitted clause. The column kinds handled are `int`, `bit`, `datetime`,
`string` (`binary` and `guid` are refused by the export and would fail here). `01-schema.sql` and `02-data-sanitized.sql` are SQL*Plus
scripts, pure ASCII, LF, with `WHENEVER SQLERROR EXIT FAILURE` and `SET DEFINE OFF`; the data ends with `COMMIT` and one
`ALTER TABLE ... MODIFY (id GENERATED BY DEFAULT AS IDENTITY (RESTART START WITH n))` per identity table with rows.

## Testing changes

Never on `mar-oracle`. Point the tool at another container:

```
sed -e 's/^CONTAINER=.*/CONTAINER=mar-oracle-test/' -e "s|^INPUT_DIR=.*|INPUT_DIR=$PWD/tools/phase1/dbmigrate/import-oracle/input|" \
    tools/phase1/dbmigrate/import-oracle/ingest.conf.example > /tmp/test.conf
tools/phase1/dbmigrate/import-oracle/ingest.sh load --config /tmp/test.conf
tools/phase1/dbmigrate/import-oracle/ingest.sh verify --config /tmp/test.conf --out /tmp/test-results.json
docker rm -f -v mar-oracle-test
```

Free is limited to about 2 GB of memory per database; three running Oracle containers are too many for this 12 GB machine alongside
the PostgreSQL ones. Before finishing a change: `ingest.sh all --recreate` passes with the numbers above and `selftest-results.json`
is unchanged.

## Known limits

- Verification is against the export's record, not the live SQL Server; it catches mistakes, not tampering.
- Oracle 23ai or later only (`BOOLEAN`, multi-row `INSERT`); not 19c.
- `MAX_STRING_SIZE = STANDARD`: a `VARCHAR2(n CHAR)` value is also limited to 4,000 bytes (the current data is far below it).
- A row whose canonical text exceeds 32,767 characters (a CLOB over about 16 KB) cannot be hashed and fails its table; every CLOB in
  the current data is NULL.
- Timestamps carry no time zone and the source zone is unknown; no conversion is made.
- Usernames are case-insensitive only through the function-based index; applications must compare `LOWER(name) = LOWER(:input)`.
- `ingest.sh` creates no application login or network route (the schema has no password); the guide's `mar-roles.sql` and
  network routes do that, by hand, when an application needs them.
- The input files contain sanitized but real project data (usernames, timestamps, comment text).
