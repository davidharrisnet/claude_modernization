# Iteration 3: the database baked into a Docker image, built and verified entirely on Linux

Iteration 3 takes the exported MasterAntiqueRepair database files, **bakes them into a Docker image** so that the finished SQLite database is ready the moment a container starts, and **proves the result is correct without any Microsoft tooling and without trusting any other iteration's results**. The database carries no usable password: credentials are removed before anything is built or committed, so the image can be shared without carrying a secret.

## What it does

1. **Removes the passwords.** `sanitize.py` reads the raw exported data file and writes a copy in which every user's password hash and security stamp is empty and a new `MustResetPassword` column is 1. Every other value is passed through untouched. Only this sanitized copy is ever built into an image or committed.
2. **Builds the image.** `docker build` loads the schema and the sanitized data into SQLite inside an Alpine Linux image (`masterantique-sqlite:iteration3`, about 19.5 MB). The build fails if the files do not load cleanly or SQLite's integrity check is not `ok`, so a working image is a working database by construction. A container `mar-sqlite-iter3` is started from it.
3. **Verifies it independently.** 44 checks compare the image's database with a second database built at the same moment from the same two files by a different route: the plain `sqlite3` program on the host, no Docker. Neither is treated as the reference; agreement between the two is the evidence. The checks cover structure, row counts, a fingerprint of every table's full contents, ten business questions, SQLite's own integrity checks, five database rules (run on a scratch copy, so the delivered database is never touched) and the removal of all passwords.
4. **Tests itself.** Proves that a second build gives an identical database, that an independent copy matches, and that a deliberately damaged copy is caught.
5. **Reports.** Writes a Word verification report with charts.

## Where it runs

A Linux machine with Docker Engine, bash, Python 3 and the `sqlite3` command-line program. It has no connection to SQL Server and needs none: it starts from files already exported and its verification does not read anything produced by iteration 1 or 2. Building the Word report additionally needs Python with `matplotlib` and `pandoc`.

## What it produces

| Output | What it is |
|---|---|
| The image `masterantique-sqlite:iteration3` and container `mar-sqlite-iter3` | The migrated database at `/data/masterantique.sqlite`: 8 tables, 155 rows, no passwords |
| `01-schema.sql`, `02-data-sanitized.sql` (in `tools/phase1/dbmigrate/iteration3/`) | What is baked into the image. The data file contains no credentials |
| `verification-results.json`, `selftest-results.json` (same folder) | The machine-readable results |
| [MigrationVerificationReport3.docx](MigrationVerificationReport3.docx) | The verification report: every check, fingerprint and test, with charts |
| [SQLiteDatabaseGuide3.docx](SQLiteDatabaseGuide3.docx) | How to work with the database: structure, meaning of values, example queries, distributing the image. Its source is [guide.md](../../../../tools/phase1/dbmigrate/iteration3/guide.md) |

## Latest results

Last run: 2026-09-24, `dbmigrate3.sh all --recreate` on Linux (Docker Engine, SQLite 3.45.3 in the image).

**44 of 44 checks passed; 155 of 155 rows identical between the two independently built databases; self-test 3 of 3 passed.**

| Area | Checks | Result |
|---|---|---|
| Structure | 8 | Tables, columns, keys, foreign keys, indexes, the active-username rule and auto-number tables equal in both databases |
| Integrity | 2 | SQLite's integrity check `ok`; no orphaned rows |
| Database rules | 5 | Duplicate active username rejected; a deleted user's name can be reused; orphan comment rejected; yes/no columns only accept 0 and 1; new ids continue after the migrated ones |
| Passwords removed | 3 | No user has a password hash or security stamp in either build; every user must set a new password; every other user column matches the raw export (skipped when the raw file is absent) |
| Table row counts | 8 | Every table has the same number of rows in both builds |
| Content fingerprints | 8 | Every table's full contents identical in both builds |
| Business questions | 10 | Same answers in both builds (users by type and role, tickets by state, audit events, comments, date ranges) |

The last run produced a `02-data-sanitized.sql` and a `selftest-results.json` byte-identical to the previous run's. The data: 12 users (1 manager, 3 employees, 8 customers), 24 repair tickets (8 submitted, 8 in progress, 8 completed), 26 comments, 78 audit log entries, 3 roles.

## Run it

**With Claude Code:** open this repository with Claude Code on the Linux machine and type:

```
Repeat iteration 3.
```

Claude Code follows the iteration's instructions ([tools/phase1/dbmigrate/iteration3/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration3/CLAUDE.md)): it runs the command below, checks the results against the ones above and reports.

**By hand:** on the Linux machine, from `tools/phase1/dbmigrate/iteration3/` (Docker running):

```
./dbmigrate3.sh all --recreate
```

It sanitizes, rebuilds the image and container, verifies and self-tests. Expect `VERIFICATION PASSED - 44 of 44 checks passed; 155 of 155 rows verified identical (local build vs. docker image)` and `SELF-TEST PASSED - 3 of 3 passed`. The exit code is 0 on success, 1 if verification or the self-test found differences, 2 for a configuration or tool error, 3 if the container already exists and replacing was not requested. The commands are `build`, `verify`, `selftest` and `all`. The Word report is rebuilt with `python3 report.py`.

To look at the result yourself: `docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite "select id, name, passwordhash, mustresetpassword from users limit 3;"` shows the first three users with an empty password and `MustResetPassword` 1.

## Limits and known differences

- **It cannot check the export against SQL Server.** There is no SQL Server on the Linux machine, so it proves the image is sound and equals an independently built copy of the same input, not that the input still equals the live source. That is what iterations 1 and 2 do.
- **Passwords were removed on purpose.** No usable credential is carried over; every user must set a new password at first login. The database fingerprint therefore differs from an unsanitized database's, by design.
- **The image cannot be patched.** Changing the data means rebuilding the image; that is the price of portability.
- **No `sqldiff` on the Linux host.** A canonically ordered, hashed `.dump` comparison between the two builds takes its place.
- **A rebuild needs a raw export.** `build.sh` insists on a raw, unsanitized `02-data.sql` in the folder; iterations 1 and 2 no longer produce one, so a rebuild from a fresh clone needs that file from the machine that still has it. See the instructions file for the details.
- **The differences of every SQLite iteration apply**: dates are ISO text, text lengths are not enforced, and text comparison is case-sensitive, so a new row inserted directly is not protected against a name that differs only by case.

## Related documents

- [tools/phase1/dbmigrate/iteration3/CLAUDE.md](../../../../tools/phase1/dbmigrate/iteration3/CLAUDE.md): the detailed instructions for repeating and maintaining this iteration (written for Claude Code).
- [../iteration2/](../iteration2/): the same data loaded into a running container from Windows.
- [../DATA_MIGRATION.md](../DATA_MIGRATION.md): the migration strategy and security policy for all iterations (§5.2 sanitizing, §5.3 independent verification).
