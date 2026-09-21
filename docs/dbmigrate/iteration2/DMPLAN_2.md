# DMPLAN_2 - Iteration 2: migrate to a Dockerized SQLite

The plan and design for iteration 2. What actually happened, with the results, is recorded in [DM2.md](DM2.md); the detailed verification evidence is `Scripts\export\sqlite-linux\MigrationVerificationReport2.docx`. The iteration 1 plan is [DMPLAN_1.md](DMPLAN_1.md) (record: [DM1.md](DM1.md)).

## Context

Rule: every iteration must
1. **export** the data from MasterAntiqueRepairData,
2. **populate** it into a **new database**,
3. **verify** the data is identical, and
4. **write** `MigrationVerificationReport{N}.docx`, N = the iteration number.

| Iteration | What | Report |
|---|---|---|
| 1 | SQL Server -> SQLite, native on Windows (done) | `MigrationVerificationReport1.docx` |
| **2** | **SQL Server -> SQLite created and verified inside a Docker Linux container (this plan)** | `MigrationVerificationReport2.docx` |
| 3 | SQL Server -> PostgreSQL in Docker (later) | `MigrationVerificationReport3.docx` |

MySQL in Docker was built earlier as extra work and is not a numbered iteration ([DM_MySQL.md](DM_MySQL.md)).

**Why iteration 2 exists.** The target platform is Linux. Iteration 1 proved the migration on Windows only, with the Windows SQLite build. Iteration 2 repeats the migration with the new database created and checked by the **Linux** build of SQLite, so the result is known to load and behave on Linux, and a database built on one platform is shown to equal one built on the other. The SQL Server source cannot move (LocalDB is Windows-only), so Docker hosts the **target only**; export, verification and the report still run on Windows in PowerShell.

Facts the plan relied on: Docker Desktop 24.0.6 with the WSL2 backend (Linux kernel 5.15.133.1) was running; `alpine:3.20` plus `apk add sqlite sqlite-tools` provides `sqlite3` 3.45.3 and `sqldiff`; the report file name had been hard-coded and had to follow the iteration number.

## Design

### 1. Report name follows the iteration
New optional keys per target in `Scripts\migration\migration.config.json`: `iteration` (number) and `iterationTitle`. The report is written as `MigrationVerificationReport{iteration}.docx`; a target without `iteration` (MySQL) writes `MigrationVerificationReport-<target>.docx`. The results JSON records `Iteration` and `IterationTitle`, and the Word title page and page header say "Iteration N".

### 2. A new target, `sqlite-linux`
```
"sqlite-linux": {
  "dialect": "sqlite", "iteration": 2, "iterationTitle": "SQLite in a Dockerized Linux container",
  "runner": { "mode": "docker", "container": "mar-sqlite", "image": "alpine:3.20", "autoStart": true },
  "file": "/data/masterantique.sqlite" }
```
- The container `mar-sqlite` is created on first use: `docker run -d --name mar-sqlite alpine:3.20 sh -c "apk add --no-cache sqlite sqlite-tools && mkdir -p /data && exec tail -f /dev/null"`. The tool waits until `sqlite3`, `sqldiff` and `/data` exist.
- The database file lives **inside the container** (`/data`), not on a Windows bind mount, so the test exercises Linux file semantics. After the import it is copied out with `docker cp` to `Scripts\export\sqlite-linux\masterantique.sqlite` for inspection and handover.
- No port is published; the client runs through `docker exec -i`, SQL piped in as UTF-8.

### 3. The SQLite dialect becomes runner-aware
`Scripts\migration\dialects\sqlite.ps1` supports two runners, `local` (`sqlite3.exe` on Windows, unchanged) and `docker`. In docker mode: the client, existence check, fingerprint (`sha256sum`), import (`rm -f` only with `--recreate`, `mkdir -p`, load, integrity checks, then `docker cp`), scratch copies for tests (`cp`/`rm -f` under `/data`), and the independent comparison (`sqldiff` inside the container) all run in the container. The dialect's display name becomes "SQLite (Linux container)" and its known-differences list gains a note that the Linux SQLite version differs from the Windows one. The shared code (export, verify, self-test, report) already goes through the dialect interface and changes only for the report-name plumbing.

### 4. The four steps in one command
`Scripts\dbmigrate.cmd all --target sqlite-linux`
1. **Export** from MasterAntiqueRepairData -> `Scripts\export\sqlite-linux\01-schema.sql`, `02-data.sql`.
2. **Populate a new database** in the Linux container (`/data/masterantique.sqlite`, created by Linux `sqlite3`), then copied out.
3. **Verify identical:** the same 41 checks as iteration 1 plus the self-test (repeatable export, in-container `sqldiff`, damaged-copy detection).
4. **Report:** `Scripts\export\sqlite-linux\MigrationVerificationReport2.docx`.

## Verification plan (each item was run; results are in DM2.md)

1. Full pipeline from `cmd.exe`: exit 0, 41 of 41 checks, 155 of 155 rows, self-test passed, report present.
2. It really is Linux: the results name Alpine and SQLite 3.45.3; `uname -a` inside the container shows the WSL2 kernel; a direct query inside the container returns 12 users.
3. Cross-check against iteration 1 (`Scripts\export\sqlite\`): the two SQL files are byte-identical; the per-table SHA-256 values in both results files are identical; Windows `sqldiff` between the Windows-built and Linux-built database files reports no differences.
4. Awkward data (CRLF, tabs, backslashes, quotes, emoji, CJK text, an empty text, NULLs, a year-9999 date, a soft-deleted user with an odd name) added to the source temporarily: 160 of 160, then removed and the source restored.
5. Negative test and exit codes: a damaged copy is reported as FAILED with the exact table, row and column; `import` without `--recreate` exits 3; an unknown target exits 2.
6. Regression: `all --target sqlite` (iteration 1) and `all --target mysql` still pass.
7. Report: opens in Word, renders correctly, shows "Iteration 2", and is byte-identical when rebuilt from the same results.
8. Documents: links resolve and quoted numbers match the results files.

## Risks and notes

- The first container start needs internet access (`apk add`); it is slower.
- The authoritative Linux database is the one inside the container; the copy in `Scripts\export\sqlite-linux\` is taken after the import.
- The container is left running; remove it with `docker rm -f mar-sqlite`.
- Not tested: the Docker daemon stopping mid-run (the tool reports a clear error at the start of a run if the daemon is off).
