# Iteration 2 — instructions for Claude Code

This folder is the iteration 2 tool: it exports the MasterAntiqueRepair database from SQL Server LocalDB, rebuilds it as a
SQLite database **inside a Linux container** (`mar-sqlite`), and verifies it against the live source. The human description
is `docs/phase1/dbmigrate/iteration2/README.md`; the strategy and security policy for all iterations is
`docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5 security).

This folder is a **separate copy of iteration 1's tool** (`tools/phase1/dbmigrate/iteration1/`), with the SQLite dialect
running in Docker instead of natively. Everything that is the same (export rendering, canonical cell form, the check
list, self-test, report and guide generators, sanitizing) is described once in `tools/phase1/dbmigrate/iteration1/CLAUDE.md`;
read that file first. This file covers what differs. A fix made in one copy usually has to be made in the other.

## Rules

1. **Windows only, from a plain command prompt, with Docker Desktop running.** The export needs the live SQL Server
   LocalDB and Windows PowerShell 5.1; the target needs the Docker daemon. Run it as
   `tools\phase1\dbmigrate\iteration2\dbmigrate.cmd` from `cmd.exe`. In Git Bash, hand-typed container commands need
   `MSYS_NO_PATHCONV=1` (otherwise `/data/...` is rewritten to a Windows path); the tool itself is not affected.
2. **The database never leaves the container.** No `docker cp` of the `.sqlite`, no volume, no published port, no
   `.sqlite` file anywhere on Windows. Only query results and the export files come out. Why: the point of this iteration is
   that the database is created, read and checked by the Linux SQLite on Linux file semantics.
3. **Credentials are sanitized in memory before anything is rendered or written**, and `sanitizeCredentials` stays `true`.
   Why: a raw export was once committed (DATA_MIGRATION.md §5.1); with the flag off the data file is named `02-data.sql`,
   holds real password hashes, and no `.gitignore` here covers it.
4. **The source is only read**, except for a deliberate stress test that restores it (see iteration 1's "Testing changes").
5. **Never guess** (unsupported types and untranslatable filters or defaults are exit 2) and **keep the export deterministic**
   (same rules as iteration 1); the export files must stay byte-identical to iteration 1's.
6. **Generated files are never edited by hand**: `01-schema.sql`, `02-data-sanitized.sql`, `import-log.txt`,
   `verification-results.json`, `selftest-results.json`, and the two Word documents in `docs/phase1/dbmigrate/iteration2/`.
7. **Credential columns are compared but never printed.**
8. **Do not commit.** The user reviews `git status` and commits.

## Run

Start Docker Desktop and wait until it reports running. From the repository root, in a command prompt:

```
tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux
```

Expected: exit 0, `VERIFICATION PASSED - 42 of 42 checks passed; 155 of 155 source rows verified identical.`,
`SELF-TEST PASSED`, then the paths of the report and the guide. Commands: `export`, `import [--recreate]`, `verify [--db <path>]`,
`selftest`, `report [--out <file>]`, `guide [--out <file>]`, `all` (export, import with `--recreate` implied, verify,
self-test, report, guide). `--config <path>` replaces the settings file. Exit codes: 0 ok, 1 verification or self-test found
differences, 2 configuration, tool, connection or Docker error (including "Docker daemon is not running"), 3 refused
(database exists, no `--recreate`). After a successful run, update the "Latest results" section of the docs README if any
number or the date changed.

## Settings

`migration\migration.config.json` (paths relative to the repository root): `source` (`server` `(localdb)\MSSQLLocalDB`,
`database` `aspnet-MasterAntiqueRepair-e93a6129-…`), `outputDir` `tools/phase1/dbmigrate`, and one target, `sqlite-linux`:
`dialect` `sqlite`, `iteration` 2, `iterationTitle`, `outputSubdir` `iteration2`, `reportDir`
`docs/phase1/dbmigrate/iteration2`, `guideFile` `SQLiteDatabaseGuide2.docx`, `runner` (`mode` `docker`, `container`
`mar-sqlite`, `image` `alpine:3.20`, `autoStart` `true`), `file` `/data/masterantique.sqlite` (a path inside the container),
`sanitizeCredentials`. `dialects\mysql.ps1` is still in the folder but the config has no MySQL target; the MySQL extra is run
from iteration 1's copy.

## Layout

```
dbmigrate.cmd                       wrapper (CRLF)
migration\DbMigrate.ps1             command line, dispatcher, exit codes
migration\Common.ps1                config, SQL Server catalog -> model, canonical values, hashing, Docker runner
                                    (Invoke-Docker, Assert-DockerRunning, Confirm-DockerContainer), Protect-SensitiveData
migration\Export.ps1, Import.ps1, Verify.ps1, SelfTest.ps1, Report.ps1, Guide.ps1
migration\dialects\sqlite.ps1       SQLite dialect, runner mode `docker`
migration\dialects\mysql.ps1        unused here
migration\migration.config.json     settings
01-schema.sql, 02-data-sanitized.sql, import-log.txt, verification-results.json, selftest-results.json
                                    outputs (checked in; no credentials). No .sqlite file exists on Windows
README.md                           lives in docs/phase1/dbmigrate/iteration2/ (for people)
```

The repository root is found by counting folders up from the script: `migration\Common.ps1` uses `'..\..\..\..\..'` (five
levels up from `tools\phase1\dbmigrate\iteration2\migration`). Fix that count if this folder moves.

## How the tool differs from iteration 1

- **Container.** `Sqlite-EnsureContainer` (`dialects\sqlite.ps1`) runs
  `docker run -d --name mar-sqlite alpine:3.20 sh -c "apk add --no-cache sqlite sqlite-tools && mkdir -p /data && exec tail -f /dev/null"`
  on first use (no custom image), starts a stopped container, then polls every 2 s, up to 90 times, until `sqlite3`, `sqldiff`
  and `/data` exist; if not, exit 2 (the first start needs internet for `apk add`). The result is remembered per process.
- **Every SQLite action goes through `docker exec -i mar-sqlite …`** with the SQL piped in as UTF-8 on stdin: import
  (`rm -f` only with `--recreate`, `mkdir -p /data`, load schema then data, `PRAGMA integrity_check`, `foreign_key_check`),
  row reads, queries (`-list -separator |`), the fingerprint (`sha256sum` of the file), scratch copies for the rule tests and
  the self-test (`cp` and `rm -f` under `/data`), and `sqldiff`. The dialect's display name is "SQLite (Linux container)".
- **The results record the client** as `sqlite3 <version> on <Alpine PRETTY_NAME>, Linux kernel <uname -r> (container
  mar-sqlite, image alpine:3.20)`; the report title page and header say "Iteration 2".
- **No copy out.** Unlike iteration 1's dialect, `Import` has no `Publish` step, so nothing is copied out of the container.
- **The guide** (`SQLiteDatabaseGuide2.docx`) is generated from the live database in the container. Section 3 (3.1–3.11)
  explains working with it through `docker exec` (container check, interactive session, read-only access, one-off queries,
  running a Windows-side script through stdin, taking results out, scratch copies, health checks and `sqldiff`, lifecycle and
  persistence, use from a Linux application over JDBC, troubleshooting). Section 9 (9.1–9.6) shows how to load the exported
  files into any Linux SQLite and what can and cannot be proven there without SQL Server.

Verification, self-test, canonical form, report and sanitizing are as in iteration 1: 42 checks (8 table counts, 8 table
contents, 8 schema, 2 integrity, 10 summaries, 5 behaviour, 1 sanitization) and 6 self-tests (2 determinism, 1 `sqldiff`, 3 negative),
all reading the database only through the container.

## Contracts

- Input: the live SQL Server database named in the settings, Windows authentication, read-only.
- Output `01-schema.sql`, `02-data-sanitized.sql`: plain SQLite SQL, UTF-8 without BOM, LF, byte-identical to iteration 1's
  (SHA-256 `72d62510…` and `4752e8c4…` in the 2026-09-24 run). No later iteration consumes them (iteration 3 has its own
  schema and needs a raw data file that this tool no longer writes; see iteration 3's "Known limits").
- Output database: `/data/masterantique.sqlite` in container `mar-sqlite`, only there.

## Gotchas

- **Docker Desktop must be up before the run**, not merely installed: `docker info` failing is exit 2 with a message. The
  daemon stopping mid-run is untested.
- **A second `import` is refused (exit 3)** unless `--recreate`; `all` recreates by removing only the database file in the
  container, not the container.
- **Hand-typed test commands under Git Bash** need `MSYS_NO_PATHCONV=1`, or `/data/masterantique.sqlite` becomes a Windows path.
- **Different SQLite versions write different file headers.** Windows 3.53.4 and the container's 3.45.3 give identical content but
  not necessarily identical bytes, so databases are compared by content (fingerprints, `sqldiff`), never as files.
- **`docker rm -f mar-sqlite` deletes the database** (no volume); the next `all` rebuilds it from the source.
- **Text templates in the report and guide generators use double-quoted PowerShell strings**: a literal `$name` in one prints
  as an empty or wrong value; use single quotes or escape it, and read the rendered text after changing them.

## Testing changes

- Run `all --target sqlite-linux` and compare with the numbers above; the two export files must equal iteration 1's
  (compare `Get-FileHash`), and `verification-results.json` differs from the checked-in one only in `RunTimeUtc`, `GitCommit`.
- Prove it is Linux and only there: `docker exec mar-sqlite uname -a`, `sqlite3 -version` (3.45.3),
  `select count(*) from Users;` (12), `pragma integrity_check;` (`ok`), and no `.sqlite` file under
  `tools\phase1\dbmigrate\iteration2\` or `docs\phase1\dbmigrate\iteration2\`.
- Run `import` twice without `--recreate` (second exit 3) and an unknown target (exit 2).
- For changes to reading, rendering or hashing, run the stress test with awkward data described in iteration 1's
  "Testing changes", and confirm inside the container that the line break, the emoji and the backslashes are stored
  exactly and the empty text stays different from NULL.
- Regression: iteration 1's `all --target sqlite` still passes after a change to shared code.

## Known limits

- The export needs Windows; the database is only on Linux for loading and checking.
- The database is only in the container and is lost when the container is removed.
- Sanitizing is hardcoded to `Users.PasswordHash`, `Users.SecurityStamp` and the added `MustResetPassword` column; nothing
  prevents setting `sanitizeCredentials` to `false`.
- SQLite has no date type (ISO text), does not enforce text lengths and compares text case-sensitively.
- Docker stopping mid-run and the stock image being unavailable offline (first start) are not handled beyond an error message.
