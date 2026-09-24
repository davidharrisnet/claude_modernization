# Plan: Iteration 3 - an independently-verified, credential-sanitized Docker image, built entirely on Linux

The plan and design for iteration 3. What actually happened, with the results, is recorded in [ITERATION3.md](ITERATION3.md); the detailed verification evidence is `MigrationVerificationReport3.docx` and the operating instructions are `SQLiteDatabaseGuide3.docx` (both in this folder). Iteration 2's plan and record are [ITERATION2_PLAN.md](../iteration2/ITERATION2_PLAN.md) / [ITERATION2.md](../iteration2/ITERATION2.md); iteration 1's are the equivalent files under [../iteration1/](../iteration1/).

## A note on the roadmap

`ITERATION2_PLAN.md`'s own roadmap table named iteration 3 as "SQL Server -> PostgreSQL in Docker (later)". This plan deliberately repurposes the iteration 3 slot for the work below instead, requested directly for this session. PostgreSQL remains a future, unnumbered-for-now iteration.

## Context

Iteration 1 built SQLite natively on Windows. Iteration 2 proved the same data works inside a Docker Linux container, loaded at runtime via `docker exec` after the container starts. This iteration takes the natural next step named in `SQLiteDatabaseGuide2.docx` §9.6 — removing the Windows dependency after export — but goes further than originally scoped, for two reasons surfaced during review of an earlier draft of this same iteration:

**It must not borrow correctness from another iteration.** An earlier draft of this iteration's `verify.py` read `tools/phase1/dbmigrate/iteration2/verification-results.json` as its expected-answers oracle and diffed against `tools/phase1/dbmigrate/iteration1/masterantique.sqlite` as the reference file. That is not independent verification — it inherits iteration 1/2's stored answers rather than re-establishing correctness on its own. **Iteration 3's verification must run entirely on this Linux server and must not consult any output artifact from another iteration.**

**Real credentials should never reach a distributable artifact.** The exported `02-data.sql` contains real PBKDF2 password hashes for the seeded accounts. A correct migration must carry every column of every table faithfully — that includes credentials — but nothing requires the *distributed* artifact (a Docker image, or anything committed to git) to still contain a *usable* credential. This project's use case is a one-time legacy→modern bootstrap where forcing a password reset on next login is acceptable, so the credential columns can be invalidated as part of the migration itself, and the resulting artifact contains no real secret at all.

Solving the second problem also solves the first: instead of just re-checking data iteration 2 already checked, iteration 3 does something genuinely new (sanitizes credentials) and verifies *that transformation* independently — which is a self-contained check by construction, not a re-run of someone else's answer key.

## Design

### 1. Credential sanitization (`sanitize.py`)
Before either database is built, `sanitize.py` reads the raw, real-hash `02-data.sql` (a transient, gitignored input — never committed, regenerated locally from `tools/phase1/dbmigrate/iteration2/02-data.sql` when needed) and rewrites the `Users` INSERT statement:
- Every row's `PasswordHash` and `SecurityStamp` become `NULL`.
- A new column, `MustResetPassword INTEGER NOT NULL DEFAULT 0` (added to iteration 3's own `01-schema.sql` — a deliberate, documented divergence from iterations 1/2's schema, not accidental drift), is set to `1` for every migrated row.
- Every other column is passed through unchanged.

The output, `02-data-sanitized.sql`, contains **no real credential material** and is the only data file ever baked into the Docker image or committed to git. `.gitignore` (scoped to `tools/phase1/dbmigrate/iteration3/`) excludes the raw file.

### 2. Two independent builds, cross-checked against each other
`verify.py` builds a second database — a throwaway "local control" copy — directly with the local `sqlite3` CLI already on this host (no Docker), from the exact same `01-schema.sql` + `02-data-sanitized.sql` used for the Docker image. Every check compares **the Docker-built database against this local control database**:
- Schema facts (table/column/PK/FK/index counts, the partial active-username index, auto-increment tables) — introspected on both, compared to each other.
- The same 10 business-summary queries as iterations 1/2 — run on both, compared to each other.
- Per-table canonically-ordered row dumps, hashed — computed on both, compared to each other.
- Integrity/foreign-key checks and 5 behaviour tests — run directly against the Docker image (self-contained; unchanged from the earlier draft).
- **New:** a sanitization check — confirms every `Users` row in both builds has `PasswordHash`/`SecurityStamp` NULL and `MustResetPassword = 1`, and cross-checks every *other* `Users` column against the raw (pre-sanitization) source to prove the transformation touched exactly the credential columns and nothing else.

No check reads `tools/phase1/dbmigrate/iteration1/` or `tools/phase1/dbmigrate/iteration2/`'s output files. The input SQL text's lineage (same export as iterations 1/2) is still documented as historical context in this file and in `ITERATION3.md` — that's a provenance fact, not a verification dependency.

### 3. Layout
```
tools/phase1/dbmigrate/iteration3/
  01-schema.sql                  copied from iteration2, + MustResetPassword column
  02-data.sql                    gitignored - raw, real hashes, transient input only
  02-data-sanitized.sql          committed - credentials redacted, this is what gets built
  sanitize.py                    the redaction step
  Dockerfile                     bakes 01-schema.sql + 02-data-sanitized.sql in at build time
  build.sh                       runs sanitize.py if needed, then docker build + docker run
  verify.py / verify.sh          builds the local control db, cross-checks against the docker image
  selftest.py / selftest.sh      determinism / independent-copy / negative-test
  dbmigrate3.sh                  dispatcher: build | verify | selftest | all
  _local/                        gitignored - the throwaway control database, rebuilt each verify run
docs/phase1/dbmigrate/iteration3/
  ITERATION3_PLAN.md, ITERATION3.md, MigrationVerificationReport3.docx, SQLiteDatabaseGuide3.docx
```

## Verification plan

1. `./dbmigrate3.sh all --recreate`: exit 0.
2. `grep -rn "iteration1\|iteration2" verify.py` returns nothing — confirms no dependency on other iterations' output.
3. Every `Users.PasswordHash`/`SecurityStamp` is `NULL` and `MustResetPassword = 1` in the built image; every other `Users` column matches the raw source.
4. `git check-ignore 02-data.sql` succeeds; only `02-data-sanitized.sql` is tracked.
5. Negative test: deliberately un-sanitize a row in the local control build and confirm the sanitization check fails and names the row (done once during development, not part of the normal run).

## Note on an earlier exposure

Commit `7a4257b` briefly removed `.gitignore`'s protection for `tools/phase1/dbmigrate/iteration*/` and committed the real, unsanitized `02-data.sql`/`masterantique.sqlite` for iterations 1/2. Those accounts are synthetic (a learning exercise, not real people), so this was not a real-world incident, but the repository's history was cleaned up anyway (`git filter-repo`) so it doesn't read as a real practice mistake. See `ITERATION3.md` for the one-line summary; this iteration's own pipeline (§1 above) is the concrete fix going forward — sanitize before anything is committed or baked into an artifact, don't rely on gitignore alone.
