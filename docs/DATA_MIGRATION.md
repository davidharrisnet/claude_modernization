# Data Migration Strategy

This is the parent document for `tools/dbmigrate/` and `docs/dbmigrate/iteration{N}/`. Each iteration folder contains the detailed, iteration-specific evidence — a plan (`ITERATION{N}_PLAN.md`), a record of what actually happened (`ITERATION{N}.md`), and two Word documents (`MigrationVerificationReport{N}.docx`, `SQLiteDatabaseGuide{N}.docx`). This document sits above all of that: it's the strategy, the roadmap, and the security policy that every iteration is expected to follow. Read this first; go to a specific iteration's docs for the detailed proof that a given step actually worked.

## 1. Purpose and scope

This project's Phase 2 target is Angular / Spring Boot / Oracle (see `README.md`). Before application code exists, the data layer is being proven out on its own, iteration by iteration, against the real Phase 1 database (`MasterAntiqueRepair`, currently SQL Server LocalDB). Each iteration answers one question about moving that data somewhere else, and every iteration follows the same four-step discipline so results are comparable and auditable across the whole series:

1. **Export** the data from the source database into portable, plain-text SQL.
2. **Populate** a new, independent target database from that export.
3. **Verify** the target is identical to the source (or, where no live source connection is possible, identical to an independently-built control copy — see §5.3).
4. **Report** the result as a stakeholder-readable document, plus a plain-language record of what was done.

The point of this discipline is that the migration is provably deterministic: the same source always produces the same export, and the same export always produces the same verified target. No step relies on an AI model's judgment at run time — every iteration's export/import/verify/report logic is a checked-in script, not a one-off action.

## 2. Steps: the migration pipeline

```
SQL Server (LocalDB)
      │  export (reads catalog + rows, writes canonical SQL text)
      ▼
01-schema.sql + 02-data.sql (raw)   ← stays on the machine that produced it, never transferred
      │  sanitize (same machine, immediately — see §5.2)
      ▼
01-schema.sql + 02-data-sanitized.sql   ← the only artifacts that cross between environments
      │  populate (dialect-specific: local client, or docker exec, or docker build)
      ▼
Target database (SQLite / MySQL / future: PostgreSQL, Oracle)
      │  verify (row counts, canonical content hashes, schema facts, business-summary
      │          queries, behaviour/rule tests, tooling self-test)
      ▼
verification-results.json  →  MigrationVerificationReport{N}.docx
                            →  SQLiteDatabaseGuide{N}.docx (or equivalent per dialect)
                            →  ITERATION{N}.md (plain-language record)
```

**Export** reads the source database's own catalog (tables, columns, types, keys, indexes, defaults, identity/auto-increment state), works out a safe table load order, and converts every row to one canonical text form — so two exports of unchanged source data are byte-identical, and any two databases built from the same export are directly comparable by hashing. This is what makes steps 3 and 4 possible without hand-inspection.

**Sanitize** runs immediately after export, on the same machine, before the raw data file is ever written anywhere it could be copied or transferred elsewhere. It's pure text manipulation on the exported SQL (see §5.2) — no database engine involved — so there's no technical reason for it to happen later or on a different machine. The raw file's lifetime is minutes at most, confined to the one machine already authorized to have the data; only the sanitized pair ever crosses to wherever the target gets built.

**Populate** is the only step that differs per target. Each target database is a **dialect**: a self-contained module implementing one interface (`RenderSchema`, `RenderData`, `Import`, `Query`, `Run`, `Fingerprint`, `SchemaChecks`, `Behaviour`, `Diff`, …) that the rest of the pipeline calls without knowing which database it's talking to. Adding a new target database means writing one new dialect file, not touching export/verify/report. Today's dialects: `sqlite.ps1` (runner modes: local client, or a Docker container loaded at runtime) and `mysql.ps1` (Docker only). Iteration 3 added a third population mechanism for SQLite — baking the data into a Docker image at build time — without needing a new dialect at all, since it reused the same `docker`-mode transport.

**Verify** is deliberately over-built relative to "does the row count match": it checks row counts, full canonical-content hashes per table, schema facts (keys/indexes/constraints), business-level summary queries (the kind of question the application actually asks), and behaviour tests that exercise application-level rules (e.g., the soft-delete username reuse rule) on a scratch copy so the delivered database is never touched. On top of that, a **self-test** proves the tooling itself is trustworthy: a second export must be byte-identical to the first, an independently-loaded copy must match under the target engine's own comparison tooling, and a deliberately damaged copy must be caught and named precisely.

**Report** produces two documents per iteration: a verification report (charts + tables, aimed at a technical reviewer or an engagement lead) and a database guide (schema reference, example queries, and operational how-to, aimed at whoever has to actually work with the resulting database next).

## 3. Iteration roadmap

| # | What | Runs on | Status | Docs |
|---|---|---|---|---|
| 1 | SQL Server → SQLite, native | Windows | Done; credential sanitization added 2026-09-22 (§10 of `ITERATION1.md`) | `docs/dbmigrate/iteration1/` |
| 2 | SQL Server → SQLite inside a Docker Linux container, loaded at container-runtime | Windows orchestrates; target is Linux | Done; credential sanitization added 2026-09-22 (§10 of `ITERATION2.md`) | `docs/dbmigrate/iteration2/` |
| 3 | SQL Server (via iteration 2's export) → SQLite baked into a Docker image at build time; verification and tooling run **entirely on Linux**, with **no dependency on iteration 1/2's stored results** and **credentials sanitized before anything is built or committed** | Linux, end to end | Done | `docs/dbmigrate/iteration3/` |
| — | MySQL in Docker | Windows | Extra work, not a numbered iteration | (results embedded in iteration 1/2 regression runs) |
| 4 | SQL Server → sanitized **PostgreSQL** schema and data files (`01-schema.sql`, `02-data-sanitized.sql`) plus a `source-metadata.json`, checked into git, plus a Word export report. **Export only; no Docker; no target database.** Details: §8 (the earlier database-agnostic idea was considered and set aside: §7) | Windows | **Built and run 2026-09-23** (self-test 9 of 9; the generated SQL was loaded into PostgreSQL 16 during the build and all 8 table counts and hashes matched); record in `ITERATION4.md` | `docs/dbmigrate/iteration4/` |
| 5 | The iteration 4 files → a fully populated **PostgreSQL** database in a **Docker container**, verified against `source-metadata.json`, with an HTML verification report. bash + Docker only (no Python, no Java, no host PostgreSQL client). Details: §8 | Linux | Planning (decision 16, a database guide, is open) | `docs/dbmigrate/iteration5/` |
| 6+ | Oracle (the actual Phase 2 target) | TBD | Not started | — |

Each iteration is self-contained under `tools/dbmigrate/iteration{N}/` — its own copy of whatever tooling and input files it needs — so an iteration's results can be reproduced without depending on a later iteration's state. Iteration 3 is the strictest example of this: it doesn't read anything from `tools/dbmigrate/iteration1/` or `iteration2/` at verification time, only at input-copy time (see §5.3).

## 4. Extending the tool to a new target database

To add a target (PostgreSQL next, per the roadmap; eventually Oracle for the real Phase 2 cutover):

1. Add a new file under `migration/dialects/` implementing the same interface `sqlite.ps1`/`mysql.ps1` already implement (or, for a Linux-native iteration like iteration 3, the equivalent Python/bash functions verify.py expects).
2. Add a `target` block to `migration.config.json` naming the dialect, the runner (`local` client, or `docker`), and where reports/guides should land.
3. No change is needed to `Export.ps1`, `Verify.ps1`, `SelfTest.ps1`, or `Report.ps1` — they only ever call through the dialect interface.
4. Write `ITERATION{N}_PLAN.md` before starting, and `ITERATION{N}.md` after, following the same shape as the existing ones.

## 5. Security

This section is the part of the strategy every future iteration — and eventually every real migration this tool is pointed at — must follow. It was tightened materially during iteration 3 after a real (low-stakes, but instructive) lapse; the lesson is written up here so it doesn't get relearned.

### 5.1 What went wrong once, and why it matters going forward

Early in this project, `.gitignore` excluded `tools/dbmigrate/iteration*/` specifically because exported data files contain real, credential-equivalent data (password hashes, security stamps) copied byte-for-byte from the source, which a faithful migration must do. A later commit removed that exclusion and committed the raw export — including real PBKDF2 hashes for the project's seeded test accounts — to a public GitHub branch. Because `MasterAntiqueRepair` is a synthetic exercise app, no real person's credentials were exposed, and the repository's history for that branch was subsequently rewritten (`git filter-repo`, force-pushed) to remove the affected files from history entirely, then permanently re-protected via a scoped `.gitignore`.

**The reason this belongs in the strategy document, not just an incident footnote:** this tool is meant to be pointed at real legacy enterprise systems later, with real users and real data. A `.gitignore` line is not a security control — it's one file away from being silently removed, exactly as happened here. The policy below is what actually needs to hold, independent of any single config file.

### 5.2 Credential and sensitive-data policy

**A migration must carry every column faithfully, including credential columns — verification depends on it.** The problem is never the export step; it's what happens to the export afterward. The policy:

1. **Never let raw exported credential data enter a committed or distributed artifact.** Not git, not a Docker image layer, not a shared drive. The raw export is a transient working file, gitignored, that exists only long enough to be transformed or consumed locally.
2. **For a one-time bootstrap migration (legacy → new system, cutover), invalidate credentials as part of the migration itself, rather than trying to carry them forward securely.** Iteration 3 established this pattern concretely: `sanitize.py` reads the raw export, sets every migrated account's password hash and security stamp to `NULL`, and adds an explicit `MustResetPassword` column set to `1`. Only that sanitized file — containing no usable credential — is ever baked into a target database or committed to git. This is deliberately a data-layer decision, not an afterthought: it means the target system never needs to understand the legacy password-hash format at all, and no downstream artifact (image, backup, registry push) needs to be treated as a secret indefinitely.
3. **Verification of the sanitization step is not optional.** It's not enough to assume the transform worked — every iteration that sanitizes credentials must verify, in code, that (a) every row's credential columns are actually invalidated in the delivered target, and (b) every *other* column is provably unchanged from the raw source, so "sanitize" can't silently become "corrupt." (See `tools/dbmigrate/iteration3/verify.py`'s `check_credential_sanitization`.)
4. **Sanitize on the machine that produced the export, immediately, not later or elsewhere.** The transform is pure text manipulation on the exported SQL — it doesn't need a database engine, Docker, or a particular OS, so there's no reason to defer it until the file has already been copied somewhere else. This also answers the practical question of how to move the export between machines at all: don't move the raw version. Only `01-schema.sql` + the sanitized data file ever cross a machine boundary; if a raw copy is genuinely ever needed off the originating machine (rare — normally the cross-check in point 5 below happens right there instead), encrypt it first (e.g. `age`/`gpg`) — the transport medium (network, USB, whatever) doesn't matter once the file itself is encrypted; an unencrypted file on a USB drive is not meaningfully more secure than one sent over a network, since the drive can just as easily be lost.
5. **This generalizes beyond passwords.** A real legacy enterprise database will have other sensitive columns this project hasn't had to handle yet: PII (SSNs, dates of birth, addresses), payment data, health data, security answers. The forward-looking version of this policy is a **declared, per-table sensitive-column list** in `migration.config.json` (not yet built — see §6), so a future iteration doesn't have to hand-write a bespoke `sanitize.py` per project the way iteration 3 did for `MasterAntiqueRepair.Users`. Whether the right transform for a given sensitive column is "null it," "hash it differently," "mask it," or "leave it and treat the whole artifact as a protected secret" is a decision to make per column, with the customer/data owner, not a default this tool should silently choose.

### 5.3 Verification must not inherit unearned trust

A verification step that only checks "does this match what a previous run already claimed was correct" isn't actually verifying anything — it's propagating whatever that previous run got wrong. Iteration 3's first draft made exactly this mistake: it read iteration 2's stored `verification-results.json` as its answer key. The fix, now the standing rule for any iteration that can't reach a live source system: **build a second, independent copy from the same input, by a different mechanism, and cross-check the two against each other.** Agreement between two independently-built artifacts is real evidence; agreement with a stored answer from a prior run is not. Iteration 3 does this concretely by building a throwaway control database with the plain `sqlite3` CLI (no Docker) alongside the Docker-built image, and comparing schema facts, business-query answers, and per-table content hashes between the two.

### 5.4 Distributable artifacts (images, backups, exports)

- Never bake unsanitized data into a Docker image layer. A layer persists in the image's history even if a later layer deletes the file, and images get pulled, cached, and pushed to registries — a much wider blast radius than a single file on disk.
- A sanitized artifact (§5.2) is safe to distribute (`docker save`/`docker push`) precisely because there's no secret left in it to protect. An unsanitized one (any raw export, any pre-sanitization database file) must never leave the machine that produced it, and must never be pushed to a registry, public or private.
- Treat `.gitignore` as a convenience, not a control. The actual control is not producing the sensitive artifact where it could be committed in the first place, plus reviewing `git status`/`git diff` before any commit that touches `tools/dbmigrate/`.

### 5.5 Git hygiene

- If sensitive data is ever committed, removing it from the working tree in a later commit is not sufficient — it remains retrievable from history indefinitely. Use `git filter-repo` (or equivalent) to remove it from every commit, then force-push the affected branch(es).
- For **real** data (unlike this project's synthetic accounts), history rewriting is necessary hygiene but is **not** the primary mitigation — a public push can never be guaranteed fully erased (caching, existing clones, forks). The primary mitigation is always **rotating/invalidating the exposed credential**, exactly as §5.2 already does by design for the migration itself.
- Scope any history rewrite precisely (the specific paths, on the specific branches actually affected) — verified via `git log --all -- <path>` before and after — rather than a broad rewrite that touches unrelated history.

### 5.6 Checklist for every future iteration

- [ ] Does this iteration's target ever receive raw, unsanitized sensitive data? If yes, is that file gitignored and never baked into a distributed artifact?
- [ ] Does verification cross-check an independently-produced result, or does it trust a stored answer from another run?
- [ ] Are credential/PII columns declared and handled deliberately (not accidentally carried through by default)?
- [ ] Would `git status` before committing show anything under `tools/dbmigrate/iteration{N}/` that shouldn't be there?

## 6. What's not built yet

- ~~Sanitize-first for iterations 1 and 2~~ — **done** (2026-09-22). Implemented and verified on the Windows machine per [docs/dbmigrate/SANITIZE_FIRST_REFACTOR.md](dbmigrate/SANITIZE_FIRST_REFACTOR.md); results in `ITERATION1.md`/`ITERATION2.md` §10. The bullet below is the still-open piece of that plan's scope.
- **Config-driven sensitive-column declarations** (§5.2.5) — today, sanitization is a bespoke, hardcoded transform per iteration (`Users.PasswordHash`/`SecurityStamp` → `MustResetPassword`); it should become a `migration.config.json`-declared policy the export/verify pipeline enforces generically, for any table/column, not just this one.
- **Oracle dialect** — the actual Phase 2 destination; it doesn't exist yet. PostgreSQL is planned in iterations 4 and 5 (§8).
- **A formal data-classification step before export** — right now, sensitive columns are identified by inspection (a human, or Claude, reading the schema). A real engagement should start with an explicit classification pass (PII/PCI/PHI/credential/none) per column, signed off by the data owner, before any export tooling runs.

## 7. Database-agnostic exports: what is and isn't possible

**Status: considered and set aside.** Iteration 4 was first framed as producing one set of files loadable into any database (SQLite, PostgreSQL or Oracle). This section records why that is not possible; iteration 4 as decided targets PostgreSQL only (§8).

**The original goal.** Produce schema and data files that are checked into git, pulled on a Linux machine, and loaded into whichever database is required: SQLite, PostgreSQL or Oracle. Nothing in the files should be specific to one database, and the data must be credential-sanitized (§5.2).

**Finding: completely database-agnostic SQL files are not possible.** SQL itself differs per database at exactly the points this schema uses. Iterations 1-3 emit SQLite SQL (`AUTOINCREMENT`, `PRAGMA`, a partial index, dates as ISO text), which is why they cannot simply be reused for another target.

| Feature in this schema | Why no single SQL spelling works on SQLite, PostgreSQL and Oracle |
|---|---|
| Filtered unique index `IX_Users_Name_Active` (`WHERE DeletedAt IS NULL`; soft delete frees the username) | Native in SQLite and PostgreSQL; Oracle needs a function-based index; a portable composite unique index on `(Name, DeletedAt)` behaves differently per database (NULLs are distinct in PostgreSQL and SQLite, compared in Oracle). The rule cannot be enforced by portable DDL. |
| Auto-increment (`Id` columns) | `AUTOINCREMENT`, `GENERATED ... AS IDENTITY` and sequences have no common form. The fallback is a plain `INTEGER PRIMARY KEY` with explicit ids, which loses "the next id continues the sequence". |
| Timestamps (`CreatedAt`, `DeletedAt`, ...) | No date or timestamp literal is accepted by all three; Oracle rejects a plain string unless a session setting matches. A single script means storing timestamps as text. |
| Long text (`PasswordHash`, `SecurityStamp`, `PhoneNumber`, claim columns) | `TEXT` does not exist in Oracle and `CLOB` does not exist in PostgreSQL; it has to become `VARCHAR(n)`, and Oracle counts `VARCHAR` in bytes (multi-byte text can overflow; 4000-byte limit). |
| Load mechanics | `PRAGMA` and `BEGIN` versus implicit transactions, multi-row `INSERT ... VALUES` (not in older Oracle), Oracle treating `''` as NULL, identifier case folding (quoted names then required forever), `&` prompts in SQL*Plus. |

A "lowest common denominator" SQL script that all three accept unchanged is possible only by giving things up: timestamps stored as text, no filtered unique rule, no identity, one-row `INSERT`s, no transaction or `PRAGMA` statements.

**What can be agnostic is a description, not SQL.** Two kinds of artifact must be kept apart:

1. **Loadable files** (SQL): always target one database's dialect, so they can never be fully agnostic. Iterations 1-3 produce these, for SQLite.
2. **Neutral files**: the schema as structured data (logical types, keys, foreign keys with delete actions, indexes with the filter as structured data, not SQL text) and the data as typed records (real `null` versus empty string, ISO timestamps, true/false). These are agnostic, but need a small **per-database renderer** to become SQL. The renderer runs on the Linux side, so the checked-in files stay neutral and each target's SQL is generated at load time.

The two properties cannot both hold: files fed straight to a database must be SQL (not agnostic), and files that are agnostic need a translator before a database can use them.

**Why the sanitize-first seam is the right place.** `Invoke-Export` already holds the schema model and the rows in memory before any dialect renders SQL, and credentials are sanitized there (§5.2). A neutral export is one more output at the same point, so everything it writes is credential-free by construction.

**Decision:** neither route was taken. Iteration 4 is a PostgreSQL-specific export (§8). A future Oracle target would be another dialect at the same seam, not a reuse of the PostgreSQL files.

## 8. PostgreSQL (iterations 4 and 5)

**Goal.** Move the SQL Server database to PostgreSQL in two separate, repeatable, command-line iterations that need no Claude session to run. Each has its own detailed plan that a fresh session can be pointed to:

- **Iteration 4 (Windows, export only):** export the SQL Server database into sanitized **PostgreSQL** schema and data files plus a metadata file, checked into git. **No Docker, no target database.** Plan: `docs/dbmigrate/iteration4/ITERATION4_PLAN.md`; directories `tools/dbmigrate/iteration4/` and `docs/dbmigrate/iteration4/`.
- **Iteration 5 (Linux, Docker):** read those files, create a fully populated PostgreSQL database in a **Docker container**, and verify the data is the same as the source it was exported from. Plan: `docs/dbmigrate/iteration5/ITERATION5_PLAN.md`; directories `tools/dbmigrate/iteration5/` and `docs/dbmigrate/iteration5/`.

The decisions below are shared by both plans; §8.8 is the full decision log.

### 8.1 Where each stage runs

| Stage | Runs on | Why |
|---|---|---|
| Export (read SQL Server, sanitize, render PostgreSQL files, write the metadata JSON) | Windows | The source is SQL Server LocalDB; the tooling is Windows PowerShell (§5, iterations 1-2). |
| Check-in and hand-off | git | The three files below are the only artifacts that cross to Linux. After a successful export they are copied (manually) into `tools/dbmigrate/iteration5/input/` and committed. |
| Load, verify, report (iteration 5) | Linux | bash and Docker only: a `postgres:16` container (`mar-postgres`) holds the database; `psql` runs inside it. No Python, no Java, no host PostgreSQL client. |

The Windows side is iteration 4's own copy of iteration 2's tooling plus one new dialect file, `postgres.ps1`, implementing the same `RenderSchema`/`RenderData` interface as `sqlite.ps1`. It is called at the sanitize-first seam: after `Protect-SensitiveData` and before anything is written, so raw credentials never reach disk (§5.2). Iteration 4 exports only; the tool does not import into or query a PostgreSQL server on Windows.

### 8.2 Outputs (checked in)

| File | Content |
|---|---|
| `01-schema.sql` | PostgreSQL DDL: tables, keys, foreign keys with delete actions, indexes, defaults. |
| `02-data-sanitized.sql` | The data as PostgreSQL `INSERT`s, credentials sanitized (`PasswordHash`/`SecurityStamp` NULL, `MustResetPassword` true), ending with the identity-sequence resets. |
| `source-metadata.json` | The metadata report from the SQL Server source, used by the Linux side to verify the new database (§8.5). Contains counts and hashes of sanitized rows only: no credentials and no personal data. It holds no SQL to be executed (the source queries are recorded as documentation only). |
| `docs/dbmigrate/iteration4/MigrationExportReport4.docx` | The export report (Word), built on Windows from `source-metadata.json` by the existing report generator; for people, not consumed by iteration 5. It carries no PASS/FAIL against a target. |

### 8.3 SQL Server to PostgreSQL mapping

| SQL Server | PostgreSQL | Note |
|---|---|---|
| `int` (and other integer types) | `INTEGER` (`BIGINT`/`SMALLINT` to match) | |
| identity primary key | `INTEGER GENERATED BY DEFAULT AS IDENTITY` | The data supplies explicit ids; the data file ends with a sequence reset per table so the next id continues from the maximum. |
| `bit` | `BOOLEAN` | `true`/`false` literals; no `CHECK` needed. Includes the new `MustResetPassword`. |
| `nvarchar(n)` | `VARCHAR(n)` | |
| `nvarchar(max)` | `TEXT` | |
| `datetime` | `TIMESTAMP` (without time zone) | SQL Server has no time zone. Precision is milliseconds at the source, so literals are rendered with 3 fractional digits (PostgreSQL keeps 6). |
| Filtered unique index `IX_Users_Name_Active` | native partial unique index | See §8.4 for the case-insensitive form. |

Statement mechanics: tables are loaded in dependency order inside one transaction; `BEGIN`/`COMMIT` are valid in PostgreSQL; standard string literals with `''` doubling are safe (`standard_conforming_strings` is on by default). Strings containing NUL are rejected, as in the earlier dialects.

### 8.4 Names and case

- **Identifiers are lowercased** so nothing needs quoting: `users`, not `"Users"`. PostgreSQL folds unquoted names to lowercase, so keeping the source's mixed case would force quoted names in every query, `psql` session, JDBC call and Hibernate mapping for ever. No two source identifiers differ only by case, and none is a PostgreSQL reserved word, so lowercasing cannot collide. Index names are schema-wide, so the existing table-prefix rule for colliding names (for example `IX_UserId`) still applies.
- **Decided (decision 1, §8.8): snake_case** (`created_at`, `password_hash`, `user_id`), the PostgreSQL convention and Spring Boot's default mapping. Plain lowercase (`createdat`) was rejected as a mechanical but unreadable mapping that Spring's default naming would not match. The rename map is written down in `ITERATION4_PLAN.md`; the metadata JSON records the source name and target name of every table and column, and verification maps between them explicitly.
- **Data is never lowercased.** Only identifiers change. Comment text and ticket descriptions (case carries meaning in a grammatical sentence), role names (`Manager`), usernames and emails are all stored exactly as in the source, so the fidelity claim stays "every column identical except credentials, which are sanitized". A username lowercased in storage cannot be shown as the user typed it (the case is unrecoverable), so usernames are deliberately not lowercased for user-friendliness.
- **Usernames are case-insensitive**, as they were in SQL Server (its default collation is case-insensitive; PostgreSQL's is case-sensitive). The rule goes in the index, not in the data (decision 2, §8.8): `CREATE UNIQUE INDEX ... ON users (lower(name)) WHERE deleted_at IS NULL`. "Bob" and "bob" cannot both be active, and the soft-delete reuse rule still holds. **Phase 2 requirement:** authentication must compare `lower(name) = lower(:input)` (lowering both the stored name and the user's input) so the query uses the index. `citext` and ICU nondeterministic collations were considered and set aside (extension dependency; `LIKE` limitations). A `CHECK (name = lower(name))` was considered and rejected because it would force lowercase storage.
- **Email** is likewise treated as case-insensitive but stored as entered, compared by the application with `lower()`. The legacy schema has no email index, so there is no database rule now; if email uniqueness is added later it uses the same `lower()` index form. **URLs:** there is no URL column today; if one is introduced, only the scheme and host are case-insensitive (the path and query can be case-sensitive), so the rule would be "host lowercased, the rest as entered", decided when it appears.

### 8.5 The metadata JSON and Linux-side verification

`source-metadata.json` is written on Windows from the SQL Server catalog and the same in-memory rows the SQL is rendered from (after sanitizing), by a code path independent of the SQL rendering. It contains:

- **Structure:** tables, columns (source type, target name and type, nullability, defaults), primary keys, foreign keys with delete actions, indexes including the soft-delete filter and the case-insensitive expression.
- **Data facts:** row count per table and a SHA-256 per table over a canonical row form (defined independent of any database: rows sorted ascending by their own canonical text, so no primary-key or collation knowledge is needed; integers in decimal, booleans as 0/1, timestamps as `yyyy-MM-dd HH:mm:ss.fff`, strings as hex of their UTF-8 bytes, NULL distinct from the empty string). Sanitized rows only, so no credential is hashed.
- **Business summaries:** the same counts checked in earlier iterations (users by type, tickets by state, audit events by action, and so on).
- **Expectations:** credential columns NULL and `MustResetPassword` true for every user; the active-username rule holds.
- **Provenance:** SHA-256 of `01-schema.sql` and `02-data-sanitized.sql`, source database name, tool version, and the run time (the only non-deterministic field, kept in its own section).

The Linux ingest step (iteration 5: bash and Docker only; `psql` runs inside the container; a static `verify.sql` reads the JSON with `jsonb`, so the JSON needs no SQL text):

1. Confirms the SQL files match the recorded SHA-256 values (transfer integrity).
2. Starts the `postgres:16` container (`mar-postgres`; no published port; a generated password that is never stored) and loads `01-schema.sql` then `02-data-sanitized.sql` with `psql` inside it, stopping at the first error.
3. Recomputes the per-table canonical hashes from the database it built, and compares row counts, schema (columns, types, keys, foreign keys, the partial index) and the business summaries against the JSON. A mismatch fails with the exact table and column.
4. Runs the rule tests inside a transaction that is rolled back (no scratch copy needed): duplicate active username rejected, including differing only by case; soft-deleted username reusable; orphan foreign key rejected; the identity continues from the maximum.
5. Checks the sanitization expectations.
6. Writes `verification-results.json` and `MigrationVerificationReport5.html` (a self-contained HTML report generated on Linux).

**What this verification is and isn't.** It verifies the loaded database against a manifest, not against the live source, because the Linux machine cannot reach SQL Server. It is still a real end-to-end check of the renderer and the load, since the manifest comes from an independent code path. It guards against mistakes, not tampering: anyone with write access could edit both the manifest and the SQL.

### 8.6 What cannot be proven on Windows

Windows can prove that the export is deterministic (two exports byte-identical), that the row counts in the generated SQL match the source, and that the credentials are sanitized. It cannot prove the SQL loads, because iteration 4 is export only and has no PostgreSQL. The load is proven in iteration 5, in a Docker container on the Linux machine; a rendering bug found there is fixed in iteration 4's `postgres.ps1` and the export is re-run (decision 10: no separate throwaway PostgreSQL is needed).

### 8.7 Open items

- **Decision 16 (open):** whether iteration 5 gets a PostgreSQL database guide (how to interact with the Dockerized database), and in which format (HTML or Markdown). Every other decision is settled (§8.8).
- Automating the hand-off copy from iteration 4 to iteration 5 is out of scope for now.
- Both plans are written; `ITERATION4.md` and `ITERATION5.md` (what actually happened, with real numbers) are written after the real runs (§4 step 4), and the commands paragraph of `CLAUDE.md` is updated when the tools exist.

### 8.8 Summary of the effort and decision points

**Effort so far (planning only; nothing is built yet).** Iteration 4 started as "database-agnostic files loadable into SQLite, PostgreSQL or Oracle". Working through the actual schema showed that is not possible with SQL text (§7), so the goal became a PostgreSQL-specific export: a `postgres.ps1` dialect at the sanitize-first seam on Windows, three checked-in files (`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`), and (iteration 5) a Linux tool that loads the files into a PostgreSQL Docker container and verifies the database against the metadata JSON. The design was settled one decision at a time; every decision is settled below except decision 16.

**Settled decisions**

| # | Decision | Answer | Reasoning |
|---|---|---|---|
| 1 | How to lowercase identifiers | **snake_case** (`created_at`, `user_id`) | Readable, PostgreSQL convention, matches Spring Boot's default naming. Needs a written, reviewable rename map; names differ from the legacy schema (a parity note, not a data change). |
| 2 | Case-insensitive names | **Usernames stored as typed; a `lower()` partial unique index on `users.name` (where `deleted_at IS NULL`); authentication lowers both the stored name and the input.** Email stored as typed with no database rule. **No data is lowercased.** | Storing lowercase would lose the case the user typed and show it wrongly on the page. Free text such as comments keeps its case because case carries meaning. Cost: mixed-case names can be stored, and lookups must use `lower()`. |
| 3 | `datetime` column type | **`TIMESTAMP` (without time zone)** | A faithful 1:1 mapping: SQL Server `datetime` has no time zone, so values are stored exactly as they are with no interpretation. `TIMESTAMPTZ` would need an assumed source zone. **Caveat to keep:** it is not known whether the legacy application stored UTC or local times (only `LockoutEndDateUtc` is UTC by name), so no conversion is made and a Phase 2 mapping must decide the zone. Literals are rendered with 3 fractional digits (the source has millisecond precision). |
| 2b | `roles.name` unique index (iteration 4) | **Plain, case-sensitive unique index** (`ix_roles_name`) | Roles are created only programmatically, never typed by a user, so the database does not need to enforce case-insensitivity; keeping role names consistent is a convention for the technical team and Claude Code. |
| 4 | Identity columns (iteration 4) | **`GENERATED BY DEFAULT AS IDENTITY`** | It accepts the explicit ids in the data; the data file ends with a `setval` per identity table so the next id continues from the maximum. `ALWAYS` would need `OVERRIDING SYSTEM VALUE` in every insert. |
| 5 | Database and schema setup (iteration 5) | **The tool starts a PostgreSQL container that creates the database; the SQL files are environment-free; a small config file supplies names; default schema `public`; the password is generated and never stored; nothing is published to the host.** | Keeps environment details and secrets out of git. No superuser or extension is needed. |
| 6 | PostgreSQL version (iteration 5) | **15 or later** (image `postgres:16`; the tool refuses an older server) | 14 reaches end of life in November 2026, and 15 gives clean ownership of the `public` schema. |
| 7 | Linux tooling (iteration 5) | **bash and Docker only**; `psql` runs inside the container. No Python, no Java, no host PostgreSQL client. | Smallest prerequisite set; verification is SQL run through `psql`. |
| 8 | Windows tooling (iteration 4) | **Own self-contained copy** of iteration 2's tooling plus a new `postgres.ps1` dialect | Per-iteration convention: reproducible without depending on other iterations. |
| 9 | How verification reads the metadata (iteration 5) | **A static `verify.sql` reads `source-metadata.json` with `jsonb`; the JSON holds no SQL text** | One source of truth; nothing executable is read from a data file. |
| 10 | Where the generated SQL is proven to load | **In the Docker container on the Linux machine, in iteration 5** | That container is the deliverable; no separate throwaway PostgreSQL. A rendering bug found there is fixed in iteration 4. |
| 11 | Output file names (iteration 4) | **`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`** in `tools/dbmigrate/iteration4/` | Continuity with iteration 3's naming; the `-sanitized` name says the file is safe to commit. |
| 12 | Data load statements (iteration 4) | **Multi-row `INSERT ... VALUES`** (100 rows per statement) in one transaction | Readable, and `COPY` is unnecessary at 155 rows. |
| 13 | Verification report (iteration 5) | **`MigrationVerificationReport5.html`**, generated on Linux from `verification-results.json` with bash and standard text tools | The Word generator needs PowerShell and `System.Drawing`; HTML needs no conversion tool and rebuilds byte-identically. |
| 14 | Metadata and export report (iteration 4) | **`source-metadata.json` is written at export; a Word export report `MigrationExportReport4.docx` is built from it on Windows** with the existing generator | The data about the source database is recorded at export, following the earlier reports' pattern. Iteration 4 verifies nothing against a target, so it produces an export report, not a verification report. |
| 15 | Container details (iteration 5) | **`postgres:16`, container `mar-postgres`, database and user `masterantique`, generated password, no published port, database stored in the container's own storage (no named volume)** | The database lives only in the container; `docker rm -f -v` removes it, and `--recreate` does exactly that. |

**Still open.** Decision 16: whether iteration 5 produces a PostgreSQL database guide, and in which format (HTML or Markdown).

## 9. Document map

| Iteration | Plan | Record | Verification report | Database guide |
|---|---|---|---|---|
| 1 | `docs/dbmigrate/iteration1/ITERATION1_PLAN.md` | `ITERATION1.md` | `MigrationVerificationReport1.docx` | `SQLiteDatabaseGuide1.docx` |
| 2 | `docs/dbmigrate/iteration2/ITERATION2_PLAN.md` | `ITERATION2.md` | `MigrationVerificationReport2.docx` | `SQLiteDatabaseGuide2.docx` |
| 3 | `docs/dbmigrate/iteration3/ITERATION3_PLAN.md` | `ITERATION3.md` | `MigrationVerificationReport3.docx` | `SQLiteDatabaseGuide3.docx` |
| 4 | `docs/dbmigrate/iteration4/ITERATION4_PLAN.md` | `ITERATION4.md` (after the run) | `MigrationExportReport4.docx` (an export report; no verification) | — |
| 5 | `docs/dbmigrate/iteration5/ITERATION5_PLAN.md` | `ITERATION5.md` (after the run) | `MigrationVerificationReport5.html` | none yet (decision 16, open) |

This document should be updated whenever a new iteration starts (add its row to §3 and §9) or whenever the security policy in §5 changes in a way that should apply retroactively to how future iterations are reviewed.
