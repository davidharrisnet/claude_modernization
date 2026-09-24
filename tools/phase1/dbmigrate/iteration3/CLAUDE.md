# Iteration 3 — instructions for Claude Code

This folder is the iteration 3 tool: it sanitizes the exported data, bakes the schema and the sanitized data into a Docker
image with SQLite, and verifies the running database against a second, independently built copy, all on Linux with no
PowerShell and no SQL Server. The human description is `docs/phase1/dbmigrate/iteration3/README.md`; the strategy and
security policy for all iterations is `docs/phase1/dbmigrate/DATA_MIGRATION.md` (§5.2 sanitizing, §5.3 independent
verification). The human database guide for this iteration is `guide.md` in this folder.

## Rules

1. **Linux only** (bash, Python 3, the `sqlite3` CLI, Docker Engine). The tool text-processes files that iterations 1 and 2
   exported on Windows; it cannot reach SQL Server. Editing the documents can be done anywhere, running the tool cannot.
2. **Raw credential data never leaves this folder and is never baked, committed or pushed.** `02-data.sql` (real password
   hashes) is a transient input and is gitignored here (`.gitignore`); the `Dockerfile` copies only `02-data-sanitized.sql`; only
   that file is committed. Why: a raw export was once committed and pushed (DATA_MIGRATION.md §5.1), and a Docker layer keeps
   a deleted file in the image history (§5.4). A `.gitignore` line is a convenience, not the control: check `git status` before any commit.
3. **Verification stands alone.** `verify.py` must not read any output of iteration 1 or 2 (no results JSON, no `.sqlite`); it
   builds its own control database and cross-checks. Why: an earlier draft used iteration 2's stored results as its answer key and
   would have agreed with any error in them (DATA_MIGRATION.md §5.3). Keep `grep -n "iteration1\|iteration2" verify.py` empty.
4. **Sanitizing changes exactly two columns and adds one.** `Users.PasswordHash` and `Users.SecurityStamp` become NULL,
   `MustResetPassword` is added and is 1 for every row; nothing else may change (verified by comparing every other `Users` column
   with the raw file).
5. **Never test on the delivered database.** Behaviour tests and the self-test work on scratch copies inside the container.
6. **Generated files are never edited by hand**: `02-data-sanitized.sql`, `verification-results.json`, `selftest-results.json`,
   `docs/phase1/dbmigrate/iteration3/MigrationVerificationReport3.docx`, `SQLiteDatabaseGuide3.docx`. Change the tool or
   `guide.md` and regenerate.
7. **Do not commit.** The user reviews `git status` and commits.

## Run

From this folder, on Linux with Docker running:

```
./dbmigrate3.sh all --recreate
```

Expected: exit 0, `VERIFICATION PASSED - 44 of 44 checks passed; 155 of 155 rows verified identical (local build vs. docker image)`,
`SELF-TEST PASSED - 3 of 3 passed`. Commands: `build [--recreate]`, `verify`, `selftest`, `all [--recreate]`
(`./build.sh`, `./verify.sh`, `./selftest.sh` are the parts). Exit codes: 0 ok, 1 verification or self-test differences, 2
configuration or tool error (Docker not running, `02-data.sql` missing, container not running), 3 refused (container exists, no
`--recreate`). The Word report is built separately: `python3 report.py` (needs `matplotlib` and `pandoc`; the system Python
on the Linux machine lacks `matplotlib`, the Anaconda `python3` has it). The guide is rebuilt with
`pandoc guide.md -o ../../../../docs/phase1/dbmigrate/iteration3/SQLiteDatabaseGuide3.docx`. After a successful run, update
the "Latest results" section of the docs README if any number changed.

## Settings

There is no settings file. Fixed in the scripts: image `masterantique-sqlite:iteration3`, container `mar-sqlite-iter3`, database
`/data/masterantique.sqlite` (`build.sh`, `verify.py`, `selftest.py`); base image `alpine:3.20` with `apk add sqlite sqlite-tools`
(`Dockerfile`, SQLite 3.45.3). The control database is built with whatever `sqlite3` is on the host `PATH`.

## Layout

```
dbmigrate3.sh             dispatcher: build | verify | selftest | all
build.sh                  sanitize if needed, docker build, docker run
sanitize.py               the credential transform (02-data.sql -> 02-data-sanitized.sql)
Dockerfile                bakes 01-schema.sql + 02-data-sanitized.sql; fails the build unless integrity_check is ok
verify.sh / verify.py     independent cross-check, writes verification-results.json
selftest.sh / selftest.py determinism, independent copy, negative test, writes selftest-results.json
report.py                 Word verification report (matplotlib charts, pandoc)
guide.md                  source of the human database guide (Word, via pandoc)
01-schema.sql             schema (committed; has the MustResetPassword column)
02-data.sql               raw data with real hashes: gitignored, transient, never committed
02-data-sanitized.sql     sanitized data (committed): what is baked in
verification-results.json, selftest-results.json      outputs (committed)
_local/, _report_build/, __pycache__/                 scratch, gitignored
.gitignore                ignores 02-data.sql, _local/, __pycache__/, _report_build/
```

The repository root is found by counting folders up from the script: `report.py` (`DOCS_DIR`) and `verify.py` (`git_commit`) use
`HERE.parent.parent.parent.parent`. Fix those if this folder moves.

## How `build` works

1. `docker info` must succeed, else exit 2. `02-data.sql` must exist, else exit 2.
2. `python3 sanitize.py` runs when `--recreate` is given or `02-data-sanitized.sql` is missing.
3. If the container exists: exit 3, or with `--recreate` `docker rm -f` the container and `docker rmi -f` the image.
4. `docker build -t masterantique-sqlite:iteration3 .`, then `docker run -d --name mar-sqlite-iter3`. The image is about 19.5 MB; its
   command is `tail -f /dev/null`, so the container idles with the database inside.

`sanitize.py` finds the one `INSERT INTO "Users" (…) VALUES …;` statement with a regular expression, splits each row on
top-level commas (ignoring commas inside quoted strings), sets the `PasswordHash` and `SecurityStamp` values to `NULL`, appends
the column `"MustResetPassword"` with value `1`, and passes every other line through byte for byte. A file without that
statement is an error. It prints `Sanitized N of N Users rows`.

## How `verify` works

`verify.py` requires the container to be running (else exit 2, "Run build.sh first"), then builds the **local control database**
`_local/masterantique.sqlite` (deleted and rebuilt on each run) with the host `sqlite3` from the same two committed files, and
compares it with the container's database. It writes `verification-results.json` in the same shape as iterations 1 and 2 (so
`report.py` mirrors their report) and exits 1 on any failed check. The 44 checks:

| Category (count) | What is checked |
|---|---|
| Schema (8) | counts, taken from each database independently and compared with each other: tables, columns (name, order, type, NOT NULL, primary-key position, default), primary key columns, foreign keys, indexes, index columns, partial-index filters, auto-increment tables |
| Integrity (2) | `PRAGMA integrity_check` and `PRAGMA foreign_key_check` on the image |
| table counts (8), table content (8) | per table `COUNT(*)`, and the SHA-256 of `SELECT * … ORDER BY <primary key>` output, in both databases, compared |
| summaries (10) | the same ten business queries as iterations 1 and 2, run on both, compared |
| Behaviour (5) | on a scratch copy inside the container (`/tmp/verify-scratch.sqlite`, removed afterwards): duplicate active username rejected; reusing a soft-deleted username allowed; orphan foreign key rejected; a yes/no column rejects values other than 0/1; a new `Roles` row continues the identity sequence |
| Sanitization (3) | in each build, no `Users` row has a hash or stamp and every row has `MustResetPassword = 1` (2 checks); every other `Users` column equals the raw `02-data.sql` value, row by row (1 check, **skipped as passed with a note when `02-data.sql` is absent**) |

Neither database is the reference. A hash mismatch names only the table.

## How `selftest` works

`selftest.py` writes `selftest-results.json` (no timestamps, so it is identical between good runs) and exits 1 if a test fails:
(1) a second image is built under a temporary tag and container (`masterantique-sqlite:iteration3-selftest`,
`mar-sqlite-iter3-selftest`, removed at the end) and its `.dump` must equal the delivered database's; (2) a scratch copy inside the
container has a `.dump` equal to the live one; (3) a scratch copy with `Comments.Id = 1` changed to `DAMAGED` and `Tickets.Id = 1`
deleted must differ and contain the marker. Three tests.

## How `report` works

`report.py` reads `verification-results.json`, `selftest-results.json` and the two SQL files and writes
`MigrationVerificationReport3.docx`: charts drawn with matplotlib into `_report_build/`, the document assembled as Markdown and
converted with pandoc. It has the same sections in the same order as the OpenXML reports of iterations 1 and 2 (title, eleven numbered
sections, appendix) but is not byte-identical to them and not deterministic (the creation date changes).

## Contracts

- Inputs: `01-schema.sql` (committed, this iteration's own; `Users` has `"MustResetPassword" INTEGER NOT NULL DEFAULT 0 CHECK
  ("MustResetPassword" IN (0, 1))`, so it deliberately differs from iterations 1 and 2) and the raw `02-data.sql` (SQLite SQL, one
  `Users` INSERT with `PasswordHash` and `SecurityStamp` among its columns).
- Outputs: `02-data-sanitized.sql`; the image and container; `verification-results.json`; `selftest-results.json`.
- Result JSON: `Passed`, `GitCommit`, `Meta` (target, client version, known differences, no source server by design), `Summary`
  (`ChecksTotal`, `ChecksPassed`, `RowsSource`, `RowsVerifiedIdentical`, `Tables`), `Tables`, `Checks`, `Domain`.

## Gotchas

- **`sanitize.py` cannot be run on an already sanitized file.** It would append a second `MustResetPassword` value to every
  row. It needs the raw file.
- **Behaviour tests run in the container, the control build on the host**: the host `sqlite3` version can differ from the
  image's 3.45.3; the two are compared by content (dumps, hashes), never as files.
- **The self-test builds a whole second image**, so it needs disk space and the Docker daemon, and leaves nothing behind unless
  it crashes (then `docker rm -f mar-sqlite-iter3-selftest; docker rmi -f masterantique-sqlite:iteration3-selftest`).
- **`--recreate` re-sanitizes** from `02-data.sql`, overwriting `02-data-sanitized.sql`; a raw file that is out of date silently
  gives an out-of-date sanitized file.

## Testing changes

- Run `./dbmigrate3.sh all --recreate` and compare with the numbers above. `git diff` must show `02-data-sanitized.sql` and
  `selftest-results.json` unchanged, and `verification-results.json` changed only in `GitCommit`.
- Confirm `git check-ignore 02-data.sql` succeeds, only `02-data-sanitized.sql` is tracked, and
  `docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite "SELECT Id, Name, PasswordHash, SecurityStamp, MustResetPassword FROM Users LIMIT 3;"` shows
  empty credentials and `1`.
- After changing a check, prove it can fail: re-introduce a fake hash into the local control build (or damage a scratch copy)
  and confirm the check fails and names the row, then rerun clean.
- After changing `guide.md`, rebuild the Word guide with pandoc and read the changed sections.

## Known limits

- **A rebuild needs a raw `02-data.sql`, and nothing produces one any more.** `build.sh` exits 2 without it, and its and
  `sanitize.py`'s messages tell you to copy it from iteration 2, but iterations 1 and 2 now export only `02-data-sanitized.sql`.
  On a fresh clone the image cannot be rebuilt through `build.sh`; the committed `02-data-sanitized.sql` alone would suffice for
  `docker build`, but `build.sh` does not allow it. Decide with the user before changing this.
- Verification cannot show that the input still equals the live SQL Server database; that is iterations 1 and 2's evidence.
- No `sqldiff` on the host: canonical dump hashes replace it.
- The image has no update path: changing the data means rebuilding it.
- The report is generated with a different toolchain than iterations 1 and 2, so it is comparable in content, not identical in layout.
- SQLite differences as in every SQLite iteration: ISO-text dates, unenforced text lengths, case-sensitive text comparison.
- No `.gitattributes` in this folder: the scripts run on Linux and must keep LF endings when checked out elsewhere.
