# Data Migration Strategy

> **Location.** Since 2026-09-23 this document and the two tool folders live in `docs/phase1/dbmigrate/`, and the tooling in `tools/phase1/dbmigrate/` (previously `docs/DATA_MIGRATION.md`, `docs/dbmigrate/`, `tools/dbmigrate/`). Older commits and the generated reports show the old paths and the earlier numbered-iteration names.

This is the parent document for the database migration: `tools/phase1/dbmigrate/` and `docs/phase1/dbmigrate/`. The migration is two tools for PostgreSQL and, since 2026-09-24, two more for an Oracle proof of concept, each with two documents for two readers — a `README.md` for people in `docs/phase1/dbmigrate/<tool>/` (what the tool does and its latest results) and a `CLAUDE.md` with the instructions for Claude Code in `tools/phase1/dbmigrate/<tool>/` — plus the generated report (and, for `import-postgresql`, the database guide). Both documents describe the current state only; git holds the history. This document sits above them: it's the strategy, the decisions, and the security policy both tools follow. Read this first; go to a tool's docs for the detailed proof that it worked.

| Tool | What it does | Runs on | Run it by typing |
|---|---|---|---|
| `export-postgresql` | SQL Server LocalDB → sanitized PostgreSQL files | Windows | `Run export-postgresql` |
| `import-postgresql` | those files → a verified PostgreSQL database in Docker | Linux | `Run import-postgresql` |
| `export-oracle` | SQL Server LocalDB → sanitized Oracle files (proof of concept, §10) | Windows | `Run export-oracle` |
| `import-oracle` | those files → a verified Oracle AI Database 26ai Free in Docker (proof of concept, §10) | Linux | `Run import-oracle` |

## 1. Purpose and scope

This project's Phase 2 target is Angular / Spring Boot / **PostgreSQL**. The exercise brief (`README.md`) names Oracle; on 2026-09-23 the user decided that Phase 2 uses PostgreSQL, and on 2026-09-24 added an Oracle proof of concept alongside it (§10) that does not change the Phase 2 database. Before application code exists, the data layer is proven out on its own, against the real Phase 1 database (`MasterAntiqueRepair`, SQL Server LocalDB). The migration follows a four-step discipline so results are comparable and auditable:

1. **Export** the data from the source database into portable, plain-text SQL.
2. **Populate** a new, independent target database from that export.
3. **Verify** the target is identical to the source (where no live source connection is possible, identical to the record of the source made at export — see §5.3).
4. **Report** the result as a stakeholder-readable document, plus a plain-language record of what was done.

The point of this discipline is that the migration is provably deterministic: the same source always produces the same export, and the same export always produces the same verified target. No step relies on an AI model's judgment at run time — the export, load, verify and report logic is checked-in script, not a one-off action.

## 2. Steps: the migration pipeline

```
SQL Server (LocalDB)
      │  export-postgresql (Windows): reads catalog + rows, sanitizes credentials IN MEMORY,
      │                               renders PostgreSQL text, records the source in a metadata file
      ▼
01-schema.sql + 02-data-sanitized.sql + source-metadata.json   ← the only artifacts; credential-free, checked into git
      │  hand-off: copied into tools/phase1/dbmigrate/import-postgresql/input/ and committed
      ▼
      │  import-postgresql (Linux): checks the files against the recorded hashes, loads them into
      │                             PostgreSQL in a Docker container, verifies, self-tests, reports
      ▼
PostgreSQL database (container mar-postgres)
      │  verify: row counts, canonical content hashes, schema facts, business-summary queries,
      │          behaviour/rule tests, tooling self-test
      ▼
verification-results.json  →  MigrationVerificationReport.html
                          →  PostgreSQLDatabaseGuide.html
```

**Export** reads the source database's own catalog (tables, columns, types, keys, indexes, defaults, identity state), works out a safe table load order, and converts every row to one canonical text form — so two exports of unchanged source data are byte-identical, and any database built from the export can be compared by hashing. This is what makes steps 3 and 4 possible without hand-inspection.

**Sanitize** happens inside the export, in memory, after the rows are read and before anything is rendered or written (see §5.2). The raw credential values never reach a file, so there is no raw export to protect, transfer or delete; only the sanitized files exist.

**Populate** is done by a PostgreSQL container that the load step creates, and by nothing else: the export renders PostgreSQL SQL through one **dialect** module (`postgres.ps1`: rename map, type mapping, schema and data rendering), and the Linux tool loads that SQL with `psql` inside the container.

**Verify** is deliberately over-built relative to "does the row count match": it checks row counts, full canonical-content hashes per table, schema facts (keys, indexes, constraints), business-level summary queries (the kind of question the application asks), and behaviour tests that exercise application-level rules (for example the soft-delete username reuse rule) inside a transaction that is rolled back. On top of that, a **self-test** proves the tooling itself is trustworthy: a second export must be byte-identical to the first, and a deliberately damaged copy must be caught and named precisely.

**Report** produces a verification report (results, tables, structure, summaries, aimed at a technical reviewer or an engagement lead), a Word export report from the Windows side, and a database guide (connection routes, application logins, a tested Spring Boot project, aimed at whoever has to work with the database next).

## 3. Status

| Tool | Status | Docs |
|---|---|---|
| `export-postgresql` | **Built and run 2026-09-23** (self-test 9 of 9; the generated SQL was loaded into PostgreSQL 16 during the build and all 8 table counts and hashes matched); re-run 2026-09-24: self-test 9 of 9, SQL files unchanged | `docs/phase1/dbmigrate/export-postgresql/` |
| `import-postgresql` | **Built and run 2026-09-23** (verification 80 of 80 checks, 155 of 155 rows identical; self-test 7 of 7); database guide written (decision 16) | `docs/phase1/dbmigrate/import-postgresql/` |
| `export-oracle` | **Built and run 2026-09-24** (self-test 13 of 13; every table's row fingerprint, row count and business summary equals the PostgreSQL export's); its SQL loads into Oracle unchanged (proven by import-oracle) | `docs/phase1/dbmigrate/export-oracle/` |
| `import-oracle` | **Built and run 2026-09-24** (verification 86 of 86 checks, 155 of 155 rows identical; self-test 7 of 7) on Oracle AI Database 26ai Free 23.26.3 | `docs/phase1/dbmigrate/import-oracle/` |

`import-postgresql` is the migration to the final Phase 2 database; the Oracle pair is a proof of concept (§10).

Each tool is self-contained under `tools/phase1/dbmigrate/<tool>/` — its own copy of whatever tooling and input files it needs — so its results can be reproduced without depending on the other tool's state; the only coupling is the three-file hand-off (§8.1).

## 4. Extending the export to a new target database

To add a target (for example in another project; this one's final target, PostgreSQL, is done):

1. Add a new file under `tools/phase1/dbmigrate/export-postgresql/migration/dialects/` next to `postgres.ps1`, implementing the same `RenderSchema`/`RenderData` interface (naming, types, defaults, filtered indexes, statement mechanics for that database).
2. Add a `target` block to `migration.config.json` naming the dialect and where the report should land.
3. No change is needed to `Export.ps1`, `Metadata.ps1` or the self-test — they only ever call through the dialect interface (the metadata's canonical row form is database-independent).
4. Write the loading and verifying tool for that database (the equivalent of `import-postgresql`), with its `CLAUDE.md` (instructions for Claude Code) and `README.md` (description and latest results), following the shape of the existing ones.

## 5. Security

This section is the part of the strategy every future migration — and eventually every real migration this tool is pointed at — must follow. It was tightened after a real (low-stakes, but instructive) lapse; the lesson is written up here so it doesn't get relearned.

### 5.1 What went wrong once, and why it matters going forward

Early in this project, `.gitignore` excluded the tool output folders specifically because exported data files contained real, credential-equivalent data (password hashes, security stamps) copied byte-for-byte from the source, which a faithful migration must do. A later commit removed that exclusion and committed the raw export — including real PBKDF2 hashes for the project's seeded test accounts — to a public GitHub branch. Because `MasterAntiqueRepair` is a synthetic exercise app, no real person's credentials were exposed, and the repository's history for that branch was subsequently rewritten (`git filter-repo`, force-pushed) to remove the affected files from history entirely.

**The reason this belongs in the strategy document, not just an incident footnote:** this tool is meant to be pointed at real legacy enterprise systems later, with real users and real data. A `.gitignore` line is not a security control — it's one file away from being silently removed, exactly as happened here. The policy below is what actually needs to hold, independent of any single config file.

### 5.2 Credential and sensitive-data policy

**A migration must carry every column faithfully, including credential columns — verification depends on it.** The problem is never the export step; it's what happens to the export afterward. The policy:

1. **Never let raw exported credential data enter a committed or distributed artifact.** Not git, not a Docker image layer, not a shared drive. Best of all, never write it at all.
2. **For a one-time bootstrap migration (legacy → new system, cutover), invalidate credentials as part of the migration itself, rather than trying to carry them forward securely.** `export-postgresql` reads the rows, sets every migrated account's password hash and security stamp to `NULL` in memory (`Protect-SensitiveData`), and adds an explicit `MustResetPassword` column set to `true`. Only sanitized text is ever rendered or written, so the files contain no usable credential. This is deliberately a data-layer decision, not an afterthought: the target system never needs to understand the legacy password-hash format at all, and no downstream artifact (backup, image, registry push) needs to be treated as a secret indefinitely. The tool **refuses to run** with sanitizing switched off (exit 2), so an unsanitized file cannot be produced by mistake.
3. **Verification of the sanitization step is not optional.** It's not enough to assume the transform worked — the tools verify, in code, that (a) every row's credential columns are actually invalidated in the delivered target (`import-postgresql` sanitization checks), (b) no credential value read from the source appears in any output file (`export-postgresql` self-test), and (c) every *other* column is provably unchanged from the source, so "sanitize" can't silently become "corrupt" (the per-table content hashes are computed over the sanitized rows, and the credential columns hash as `NULL`, so no credential is ever hashed either).
4. **Sanitize on the machine that produced the export, immediately, not later or elsewhere.** Because sanitizing happens in memory inside the export, the raw values never leave the process. Only `01-schema.sql`, the sanitized data file and the metadata ever cross a machine boundary. If a raw copy is genuinely ever needed off the originating machine (rare), encrypt it first (e.g. `age`/`gpg`) — the transport medium doesn't matter once the file itself is encrypted; an unencrypted file on a USB drive is not meaningfully more secure than one sent over a network, since the drive can just as easily be lost.
5. **This generalizes beyond passwords.** A real legacy enterprise database will have other sensitive columns this project hasn't had to handle yet: PII (SSNs, dates of birth, addresses), payment data, health data, security answers. The forward-looking version of this policy is a **declared, per-table sensitive-column list** in `migration.config.json` (not yet built — see §6), so a future migration doesn't have to hand-write a bespoke transform per project the way `Protect-SensitiveData` is written for `MasterAntiqueRepair.Users`. Whether the right transform for a given sensitive column is "null it," "hash it differently," "mask it," or "leave it and treat the whole artifact as a protected secret" is a decision to make per column, with the customer/data owner, not a default this tool should silently choose.

### 5.3 Verification must not inherit unearned trust

A verification step that only checks "does this match what a previous run already claimed was correct" isn't actually verifying anything — it's propagating whatever that previous run got wrong. The standing rule for any step that can't reach a live source system: **check against a record made by an independent code path.** `import-postgresql` cannot reach SQL Server, so it verifies against `source-metadata.json`, which `export-postgresql` builds from the source catalog and the same in-memory rows but **not** from the rendered SQL. A renderer bug therefore shows up as a disagreement between the loaded database and the record. What this does not guard against is tampering: anyone who can edit both the record and the SQL can make them agree (§8.5).

### 5.4 Distributable artifacts (images, backups, exports)

- Never bake unsanitized data into a Docker image layer. A layer persists in the image's history even if a later layer deletes the file, and images get pulled, cached, and pushed to registries — a much wider blast radius than a single file on disk.
- A sanitized artifact (§5.2) is safe to distribute precisely because there's no secret left in it to protect. An unsanitized one (any raw export, any pre-sanitization database file) must never leave the machine that produced it, and must never be pushed to a registry, public or private. The `mar-postgres` database is created only from the sanitized files and is never published to a host port.
- Treat `.gitignore` as a convenience, not a control. The actual control is not producing the sensitive artifact where it could be committed in the first place, plus reviewing `git status`/`git diff` before any commit that touches `tools/phase1/dbmigrate/`.

### 5.5 Git hygiene

- If sensitive data is ever committed, removing it from the working tree in a later commit is not sufficient — it remains retrievable from history indefinitely. Use `git filter-repo` (or equivalent) to remove it from every commit, then force-push the affected branch(es).
- For **real** data (unlike this project's synthetic accounts), history rewriting is necessary hygiene but is **not** the primary mitigation — a public push can never be guaranteed fully erased (caching, existing clones, forks). The primary mitigation is always **rotating/invalidating the exposed credential**, exactly as §5.2 already does by design for the migration itself.
- Scope any history rewrite precisely (the specific paths, on the specific branches actually affected) — verified via `git log --all -- <path>` before and after — rather than a broad rewrite that touches unrelated history.

### 5.6 Checklist for every future migration

- [ ] Does the target ever receive raw, unsanitized sensitive data? If yes, is that file gitignored and never baked into a distributed artifact? (Better: is it never written at all?)
- [ ] Does verification cross-check an independently-produced result, or does it trust a stored answer from another run?
- [ ] Are credential/PII columns declared and handled deliberately (not accidentally carried through by default)?
- [ ] Would `git status` before committing show anything under `tools/phase1/dbmigrate/` that shouldn't be there?

## 6. What's not built yet

- **Config-driven sensitive-column declarations** (§5.2.5) — today, sanitization is a bespoke, hardcoded transform (`Users.PasswordHash`/`SecurityStamp` → `MustResetPassword`); it should become a `migration.config.json`-declared policy the export pipeline enforces generically, for any table/column, not just this one.
- **A formal data-classification step before export** — right now, sensitive columns are identified by inspection (a human, or Claude, reading the schema). A real engagement should start with an explicit classification pass (PII/PCI/PHI/credential/none) per column, signed off by the data owner, before any export tooling runs.

## 7. Database-agnostic exports: what is and isn't possible

**Status: considered and set aside.** The export was first framed as producing one set of files loadable into any database (SQLite, PostgreSQL or Oracle). This section records why that is not possible; the export as decided targets PostgreSQL only (§8).

**The original goal.** Produce schema and data files that are checked into git, pulled on a Linux machine, and loaded into whichever database is required. Nothing in the files should be specific to one database, and the data must be credential-sanitized (§5.2).

**Finding: completely database-agnostic SQL files are not possible.** SQL itself differs per database at exactly the points this schema uses.

| Feature in this schema | Why no single SQL spelling works on SQLite, PostgreSQL and Oracle |
|---|---|
| Filtered unique index `IX_Users_Name_Active` (`WHERE DeletedAt IS NULL`; soft delete frees the username) | Native in SQLite and PostgreSQL; Oracle needs a function-based index; a portable composite unique index on `(Name, DeletedAt)` behaves differently per database (NULLs are distinct in PostgreSQL and SQLite, compared in Oracle). The rule cannot be enforced by portable DDL. |
| Auto-increment (`Id` columns) | `AUTOINCREMENT`, `GENERATED ... AS IDENTITY` and sequences have no common form. The fallback is a plain `INTEGER PRIMARY KEY` with explicit ids, which loses "the next id continues the sequence". |
| Timestamps (`CreatedAt`, `DeletedAt`, ...) | No date or timestamp literal is accepted by all three; Oracle rejects a plain string unless a session setting matches. A single script means storing timestamps as text. |
| Long text (`PasswordHash`, `SecurityStamp`, `PhoneNumber`, claim columns) | `TEXT` does not exist in Oracle and `CLOB` does not exist in PostgreSQL; it has to become `VARCHAR(n)`, and Oracle counts `VARCHAR` in bytes (multi-byte text can overflow; 4000-byte limit). |
| Load mechanics | `PRAGMA` and `BEGIN` versus implicit transactions, multi-row `INSERT ... VALUES` (not in older Oracle), Oracle treating `''` as NULL, identifier case folding (quoted names then required forever), `&` prompts in SQL*Plus. |

A "lowest common denominator" SQL script that all three accept unchanged is possible only by giving things up: timestamps stored as text, no filtered unique rule, no identity, one-row `INSERT`s, no transaction or `PRAGMA` statements.

**What can be agnostic is a description, not SQL.** Two kinds of artifact must be kept apart:

1. **Loadable files** (SQL): always target one database's dialect, so they can never be fully agnostic.
2. **Neutral files**: the schema as structured data (logical types, keys, foreign keys with delete actions, indexes with the filter as structured data, not SQL text) and the data as typed records (real `null` versus empty string, ISO timestamps, true/false). These are agnostic, but need a small **per-database renderer** to become SQL. The renderer runs on the Linux side, so the checked-in files stay neutral and each target's SQL is generated at load time.

The two properties cannot both hold: files fed straight to a database must be SQL (not agnostic), and files that are agnostic need a translator before a database can use them.

**Why the sanitize-first seam is the right place.** `Invoke-Export` already holds the schema model and the rows in memory before any dialect renders SQL, and credentials are sanitized there (§5.2). A neutral export would be one more output at the same point, so everything it writes would be credential-free by construction.

**Decision:** neither route was taken. The export is PostgreSQL-specific (§8). An Oracle target is another dialect at the same seam, not a reuse of the PostgreSQL files: §10 builds it as a proof of concept, and its metadata matches PostgreSQL's row fingerprints because the canonical form is database-independent.

## 8. PostgreSQL: the two tools

**Goal.** Move the SQL Server database to PostgreSQL in two separate, repeatable, command-line tools that need no Claude session to run. Each has its own detailed plan that a fresh session can be pointed to:

- **`export-postgresql` (Windows, export only):** export the SQL Server database into sanitized **PostgreSQL** schema and data files plus a metadata file, checked into git. **No Docker, no target database.** Description: `docs/phase1/dbmigrate/export-postgresql/README.md`; instructions for Claude: `tools/phase1/dbmigrate/export-postgresql/CLAUDE.md`; directories `tools/phase1/dbmigrate/export-postgresql/` and `docs/phase1/dbmigrate/export-postgresql/`.
- **`import-postgresql` (Linux, Docker):** read those files, create a fully populated PostgreSQL database in a **Docker container**, and verify the data is the same as the source it was exported from. Description: `docs/phase1/dbmigrate/import-postgresql/README.md`; instructions for Claude: `tools/phase1/dbmigrate/import-postgresql/CLAUDE.md`; directories `tools/phase1/dbmigrate/import-postgresql/` and `docs/phase1/dbmigrate/import-postgresql/`.

The decisions below are shared by both plans; §8.8 is the full decision log.

### 8.1 Where each stage runs

| Stage | Runs on | Why |
|---|---|---|
| Export (read SQL Server, sanitize, render PostgreSQL files, write the metadata JSON) | Windows | The source is SQL Server LocalDB; the tooling is Windows PowerShell. |
| Check-in and hand-off | git | The three files below are the only artifacts that cross to Linux. After a successful export they are copied (manually) into `tools/phase1/dbmigrate/import-postgresql/input/` and committed. |
| Load, verify, report (`import-postgresql`) | Linux | bash and Docker only: a `postgres:16` container (`mar-postgres`) holds the database; `psql` runs inside it. No Python, no Java, no host PostgreSQL client. |

The Windows side is PowerShell tooling with one dialect file, `postgres.ps1`, implementing the `RenderSchema`/`RenderData` interface. It is called at the sanitize-first seam: after `Protect-SensitiveData` and before anything is written, so raw credentials never reach disk (§5.2). The export only renders text; the tool does not import into or query a PostgreSQL server on Windows.

### 8.2 Outputs (checked in)

| File | Content |
|---|---|
| `01-schema.sql` | PostgreSQL DDL: tables, keys, foreign keys with delete actions, indexes, defaults. |
| `02-data-sanitized.sql` | The data as PostgreSQL `INSERT`s, credentials sanitized (`PasswordHash`/`SecurityStamp` NULL, `MustResetPassword` true), ending with the identity-sequence resets. |
| `source-metadata.json` | The metadata report from the SQL Server source, used by the Linux side to verify the new database (§8.5). Contains counts and hashes of sanitized rows only: no credentials and no personal data. It holds no SQL to be executed (the source queries are recorded as documentation only). |
| `docs/phase1/dbmigrate/export-postgresql/MigrationExportReport.docx` | The export report (Word), built on Windows from `source-metadata.json`; for people, not consumed by `import-postgresql`. It carries no PASS/FAIL against a target. |

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

Statement mechanics: tables are loaded in dependency order inside one transaction; `BEGIN`/`COMMIT` are valid in PostgreSQL; standard string literals with `''` doubling are safe (`standard_conforming_strings` is on by default). Strings containing NUL are rejected.

### 8.4 Names and case

- **Identifiers are lowercased** so nothing needs quoting: `users`, not `"Users"`. PostgreSQL folds unquoted names to lowercase, so keeping the source's mixed case would force quoted names in every query, `psql` session, JDBC call and Hibernate mapping for ever. No two source identifiers differ only by case, and none is a PostgreSQL reserved word, so lowercasing cannot collide. Index names are schema-wide, so the table-prefix rule for colliding names (for example `IX_UserId`) applies.
- **Decided (decision 1, §8.8): snake_case** (`created_at`, `password_hash`, `user_id`), the PostgreSQL convention and Spring Boot's default mapping. Plain lowercase (`createdat`) was rejected as a mechanical but unreadable mapping that Spring's default naming would not match. The rename map lives in `tools/phase1/dbmigrate/export-postgresql/migration/dialects/postgres.ps1` (its rules are in `tools/phase1/dbmigrate/export-postgresql/CLAUDE.md`); the metadata JSON records the source name and target name of every table and column, and verification maps between them explicitly.
- **Data is never lowercased.** Only identifiers change. Comment text and ticket descriptions (case carries meaning in a grammatical sentence), role names (`Manager`), usernames and emails are all stored exactly as in the source, so the fidelity claim stays "every column identical except credentials, which are sanitized". A username lowercased in storage cannot be shown as the user typed it (the case is unrecoverable), so usernames are deliberately not lowercased for user-friendliness.
- **Usernames are case-insensitive**, as they were in SQL Server (its default collation is case-insensitive; PostgreSQL's is case-sensitive). The rule goes in the index, not in the data (decision 2, §8.8): `CREATE UNIQUE INDEX ... ON users (lower(name)) WHERE deleted_at IS NULL`. "Bob" and "bob" cannot both be active, and the soft-delete reuse rule still holds. **Phase 2 requirement:** authentication must compare `lower(name) = lower(:input)` (lowering both the stored name and the user's input) so the query uses the index. `citext` and ICU nondeterministic collations were considered and set aside (extension dependency; `LIKE` limitations). A `CHECK (name = lower(name))` was considered and rejected because it would force lowercase storage.
- **Email** is likewise treated as case-insensitive but stored as entered, compared by the application with `lower()`. The legacy schema has no email index, so there is no database rule now; if email uniqueness is added later it uses the same `lower()` index form. **URLs:** there is no URL column today; if one is introduced, only the scheme and host are case-insensitive (the path and query can be case-sensitive), so the rule would be "host lowercased, the rest as entered", decided when it appears.

### 8.5 The metadata JSON and Linux-side verification

`source-metadata.json` is written on Windows from the SQL Server catalog and the same in-memory rows the SQL is rendered from (after sanitizing), by a code path independent of the SQL rendering. It contains:

- **Structure:** tables, columns (source type, target name and type, nullability, defaults), primary keys, foreign keys with delete actions, indexes including the soft-delete filter and the case-insensitive expression.
- **Data facts:** row count per table and a SHA-256 per table over a canonical row form (defined independent of any database: rows sorted ascending by their own canonical text, so no primary-key or collation knowledge is needed; integers in decimal, booleans as 0/1, timestamps as `yyyy-MM-dd HH:mm:ss.fff`, strings as hex of their UTF-8 bytes, NULL distinct from the empty string). Sanitized rows only, so no credential is hashed.
- **Business summaries:** counts of the kind the application asks (users by type, tickets by state, audit events by action, and so on).
- **Expectations:** credential columns NULL and `MustResetPassword` true for every user; the active-username rule holds.
- **Provenance:** SHA-256 of `01-schema.sql` and `02-data-sanitized.sql`, source database name, tool version, and the run time (the only non-deterministic field, kept in its own section).

The Linux ingest step (`import-postgresql`: bash and Docker only; `psql` runs inside the container; a static `verify.sql` reads the JSON with `jsonb`, so the JSON needs no SQL text):

1. Confirms the SQL files match the recorded SHA-256 values (transfer integrity).
2. Starts the `postgres:16` container (`mar-postgres`; no published port; a generated password that is never stored) and loads `01-schema.sql` then `02-data-sanitized.sql` with `psql` inside it, stopping at the first error.
3. Recomputes the per-table canonical hashes from the database it built, and compares row counts, schema (columns, types, keys, foreign keys, the partial index) and the business summaries against the JSON. A mismatch fails with the exact table and column.
4. Runs the rule tests inside a transaction that is rolled back (no scratch copy needed): duplicate active username rejected, including differing only by case; soft-deleted username reusable; orphan foreign key rejected; the identity continues from the maximum.
5. Checks the sanitization expectations.
6. Writes `verification-results.json` and `MigrationVerificationReport.html` (a self-contained HTML report generated on Linux).

**What this verification is and isn't.** It verifies the loaded database against a manifest, not against the live source, because the Linux machine cannot reach SQL Server. It is still a real end-to-end check of the renderer and the load, since the manifest comes from an independent code path. It guards against mistakes, not tampering: anyone with write access could edit both the manifest and the SQL.

### 8.6 What cannot be proven on Windows

Windows can prove that the export is deterministic (two exports byte-identical), that the row counts in the generated SQL match the source, and that the credentials are sanitized. It cannot prove the SQL loads, because `export-postgresql` is export only and has no PostgreSQL. The load is proven by `import-postgresql`, in a Docker container on the Linux machine; a rendering bug found there is fixed in `export-postgresql`'s `postgres.ps1` and the export is re-run (decision 10: no separate throwaway PostgreSQL is needed).

### 8.7 Open items

- **Decision 16 (settled 2026-09-23):** `import-postgresql` has a PostgreSQL database guide, in HTML: `docs/phase1/dbmigrate/import-postgresql/PostgreSQLDatabaseGuide.html` (psql from bash, application logins, network routes, and a tested Spring Boot 4.1.1 JPA/JDBC project with a first-login password change). All decisions are settled (§8.8).
- Automating the hand-off copy from `export-postgresql` to `import-postgresql` is out of scope for now.
- Both tools are built and run (2026-09-23); their READMEs describe the results, with real numbers.

### 8.8 Summary of the effort and decision points

**Effort so far (both tools built and run on 2026-09-23; see their READMEs).** The export started as "database-agnostic files loadable into SQLite, PostgreSQL or Oracle". Working through the actual schema showed that is not possible with SQL text (§7), so the goal became a PostgreSQL-specific export: a `postgres.ps1` dialect at the sanitize-first seam on Windows, three checked-in files (`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`), and a Linux tool that loads the files into a PostgreSQL Docker container and verifies the database against the metadata JSON. The design was settled one decision at a time; every decision is settled below. Both tools were then built and run: the export on Windows (self-test 9 of 9), and the load and verification on Linux (80 of 80 checks, all 155 rows identical, self-test 7 of 7). `import-postgresql` pinned the image to `postgres:16.1` (decision 15 said `postgres:16`).

**Settled decisions**

| # | Decision | Answer | Reasoning |
|---|---|---|---|
| 1 | How to lowercase identifiers | **snake_case** (`created_at`, `user_id`) | Readable, PostgreSQL convention, matches Spring Boot's default naming. Needs a written, reviewable rename map; names differ from the legacy schema (a parity note, not a data change). |
| 2 | Case-insensitive names | **Usernames stored as typed; a `lower()` partial unique index on `users.name` (where `deleted_at IS NULL`); authentication lowers both the stored name and the input.** Email stored as typed with no database rule. **No data is lowercased.** | Storing lowercase would lose the case the user typed and show it wrongly on the page. Free text such as comments keeps its case because case carries meaning. Cost: mixed-case names can be stored, and lookups must use `lower()`. |
| 3 | `datetime` column type | **`TIMESTAMP` (without time zone)** | A faithful 1:1 mapping: SQL Server `datetime` has no time zone, so values are stored exactly as they are with no interpretation. `TIMESTAMPTZ` would need an assumed source zone. **Caveat to keep:** it is not known whether the legacy application stored UTC or local times (only `LockoutEndDateUtc` is UTC by name), so no conversion is made and a Phase 2 mapping must decide the zone. Literals are rendered with 3 fractional digits (the source has millisecond precision). |
| 2b | `roles.name` unique index (`export-postgresql`) | **Plain, case-sensitive unique index** (`ix_roles_name`) | Roles are created only programmatically, never typed by a user, so the database does not need to enforce case-insensitivity; keeping role names consistent is a convention for the technical team and Claude Code. |
| 4 | Identity columns (`export-postgresql`) | **`GENERATED BY DEFAULT AS IDENTITY`** | It accepts the explicit ids in the data; the data file ends with a `setval` per identity table so the next id continues from the maximum. `ALWAYS` would need `OVERRIDING SYSTEM VALUE` in every insert. |
| 5 | Database and schema setup (`import-postgresql`) | **The tool starts a PostgreSQL container that creates the database; the SQL files are environment-free; a small config file supplies names; default schema `public`; the password is generated and never stored; nothing is published to the host.** | Keeps environment details and secrets out of git. No superuser or extension is needed. |
| 6 | PostgreSQL version (`import-postgresql`) | **15 or later** (image `postgres:16`; the tool refuses an older server) | 14 reaches end of life in November 2026, and 15 gives clean ownership of the `public` schema. |
| 7 | Linux tooling (`import-postgresql`) | **bash and Docker only**; `psql` runs inside the container. No Python, no Java, no host PostgreSQL client. | Smallest prerequisite set; verification is SQL run through `psql`. |
| 8 | Windows tooling (`export-postgresql`) | **Self-contained PowerShell tooling** with a `postgres.ps1` dialect | Reproducible without depending on another tool's folder. |
| 9 | How verification reads the metadata (`import-postgresql`) | **A static `verify.sql` reads `source-metadata.json` with `jsonb`; the JSON holds no SQL text** | One source of truth; nothing executable is read from a data file. |
| 10 | Where the generated SQL is proven to load | **In the Docker container on the Linux machine, by `import-postgresql`** | That container is the deliverable; no separate throwaway PostgreSQL. A rendering bug found there is fixed in `export-postgresql`. |
| 11 | Output file names (`export-postgresql`) | **`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`** in `tools/phase1/dbmigrate/export-postgresql/` | The `-sanitized` name says the file is safe to commit. |
| 12 | Data load statements (`export-postgresql`) | **Multi-row `INSERT ... VALUES`** (100 rows per statement) in one transaction | Readable, and `COPY` is unnecessary at 155 rows. |
| 13 | Verification report (`import-postgresql`) | **`MigrationVerificationReport.html`**, generated on Linux from `verification-results.json` with bash and standard text tools | The Word generator needs PowerShell and `System.Drawing`; HTML needs no conversion tool and rebuilds byte-identically. |
| 14 | Metadata and export report (`export-postgresql`) | **`source-metadata.json` is written at export; a Word export report `MigrationExportReport.docx` is built from it on Windows** | The data about the source database is recorded at export. The export verifies nothing against a target, so it produces an export report, not a verification report. |
| 15 | Container details (`import-postgresql`) | **`postgres:16`, container `mar-postgres`, database and user `masterantique`, generated password, no published port, database stored in the container's own storage (no named volume)** | The database lives only in the container; `docker rm -f -v` removes it, and `--recreate` does exactly that. |

**Decision 16 (settled 2026-09-23): a PostgreSQL database guide, in HTML** (`docs/phase1/dbmigrate/import-postgresql/PostgreSQLDatabaseGuide.html`), tested against a copy of the database. Spring Boot 4.1.1 was confirmed with the user for its examples.

## 9. Document map

| Tool | Description (README, for people) | Instructions for Claude (CLAUDE.md) | Report | Database guide |
|---|---|---|---|---|
| `export-postgresql` | `docs/phase1/dbmigrate/export-postgresql/README.md` | `tools/phase1/dbmigrate/export-postgresql/CLAUDE.md` | `MigrationExportReport.docx` (an export report; no verification) | — |
| `import-postgresql` | `docs/phase1/dbmigrate/import-postgresql/README.md` | `tools/phase1/dbmigrate/import-postgresql/CLAUDE.md` | `MigrationVerificationReport.html` | `PostgreSQLDatabaseGuide.html` |
| `export-oracle` | `docs/phase1/dbmigrate/export-oracle/README.md` | `tools/phase1/dbmigrate/export-oracle/CLAUDE.md` | `MigrationExportReport.docx` (an export report; no verification) | — |
| `import-oracle` | `docs/phase1/dbmigrate/import-oracle/README.md` | `tools/phase1/dbmigrate/import-oracle/CLAUDE.md` | `MigrationVerificationReport.html` | `OracleDatabaseGuide.html` |

## 10. Oracle: a proof of concept alongside PostgreSQL

**Goal.** Show the same migration reasoned through for Oracle, the database the exercise brief names, using what the PostgreSQL pair taught. Phase 2 stays on PostgreSQL (decision 17). Two tools, as for PostgreSQL:

- **`export-oracle` (Windows, export only; built 2026-09-24):** a self-contained copy of `export-postgresql`'s tooling with one different dialect file, `oracle.ps1`. Description: `docs/phase1/dbmigrate/export-oracle/README.md`; instructions: `tools/phase1/dbmigrate/export-oracle/CLAUDE.md`.
- **`import-oracle` (Linux, Docker; built 2026-09-24):** loads the three files into an **Oracle AI Database 26ai Free** container (`gvenzl/oracle-free:23.26.3-faststart`) and verifies them against the metadata with PL/SQL run by `sqlplus` inside the container. Description: `docs/phase1/dbmigrate/import-oracle/README.md`; instructions: `tools/phase1/dbmigrate/import-oracle/CLAUDE.md`.

The pipeline (§2), the hand-off (three files copied into `import-oracle/input/`), the security policy (§5: sanitize in memory, refuse unsanitized, verify against an independently made record) and the design of both tools are the PostgreSQL ones. What changes is the dialect and the load and verify mechanics.

### 10.1 What Oracle changes (the dialect rules)

| Topic | Oracle rule | Why |
|---|---|---|
| Identifiers | Unquoted lowercase snake_case from the same explicit rename map; Oracle stores them in upper case. Every identifier is checked against the reserved-word list, a pattern and 128 bytes, and the export stops on a problem | Quoting lowercase names would be needed everywhere for ever; a future column could be a reserved word |
| Integers, identity | `NUMBER(10)` (`NUMBER(19)`, `NUMBER(5)`); `GENERATED BY DEFAULT AS IDENTITY` with a named primary key; after the load `ALTER TABLE ... MODIFY (id GENERATED BY DEFAULT AS IDENTITY (RESTART START WITH last+1))` | Accepts the explicit ids in the data; the equivalent of PostgreSQL's `setval` |
| Booleans | Native `BOOLEAN` (23ai and later) | 26ai is the target (decision 18) |
| Timestamps | `TIMESTAMP(3)`, no time zone; literal `TIMESTAMP '...'` | Same reasoning as decision 3 |
| Text | `VARCHAR2(n CHAR)`; `nvarchar(max)` becomes `CLOB` | Source lengths are in characters; a `VARCHAR2` is also limited to 4000 bytes unless `MAX_STRING_SIZE=EXTENDED` (checked on load) |
| Soft-delete unique rule | Function-based unique index on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END` | Oracle has no partial index; a B-tree index stores no all-NULL key, so filtered-out rows never collide (decision 2 still holds for case) |
| Foreign keys | `ON DELETE CASCADE` kept; `NO ACTION` written by leaving the clause out | Oracle rejects the words; its default is no action |
| Empty string | The export **refuses** a source that contains one | Oracle stores `''` as NULL, which would silently change the data and break "NULL stays distinct from the empty string"; the current data has none |
| String literals | Pure ASCII: control characters `CHR(n)`, other characters `UNISTR('\XXXX')`, plain runs `'...'`, joined with `\|\|` and spread over lines when long | The SQL*Plus client reads through `NLS_LANG`, splits input at lines and blank lines and rejects lines of about 2,499 characters; none of that can touch the data |
| Transactions | No `BEGIN`/`COMMIT` around DDL; data in one `COMMIT`; scripts start with `WHENEVER SQLERROR EXIT FAILURE` and `SET DEFINE OFF` | DDL commits by itself; `&` must not prompt |
| Inserts | Multi-row `INSERT ... VALUES` (23ai and later), 100 rows per statement | As decision 12 |
| Metadata | Same canonical row form and hashes; `minOracleVersion` 23; Oracle data-dictionary types with `precision` and `scale`; the index key expression in full | The hashes are database-independent: every table's fingerprint, row count and summary equals the PostgreSQL export's (verified 2026-09-24) |

### 10.2 Decisions

| # | Decision | Answer | Reasoning |
|---|---|---|---|
| 17 | Oracle and PostgreSQL | **Oracle is an additional proof of concept; Phase 2 stays on PostgreSQL** (user, 2026-09-24) | The brief names Oracle; the PostgreSQL decision (2026-09-23) stands for the application |
| 18 | Oracle version | **Oracle AI Database 26ai Free** (the 23ai code line renamed), in Docker on the Linux machine; 26ai features (`BOOLEAN`, multi-row `INSERT`) are allowed | Free, runs in a container like PostgreSQL (limits: about 2 CPU threads, 2 GB RAM, 12 GB data, far above this data). Caveat: many real systems run 19c, where those two features do not exist; switching is a small change in `oracle.ps1` (`NUMBER(1)` with a `CHECK`, single-row inserts) |
| 19 | Identifier style | **Unquoted lowercase snake_case** from the rename map (assumed by default, not separately confirmed) | Nothing needs quoting; same names as PostgreSQL |
| 20 | Where Oracle runs | **Linux machine, in Docker**; export on Windows as before | The user's environment; keeps "bash and Docker only" for the import |
| 21 | Empty strings | **Refuse them** in the export | Silent NULL conversion is worse than a stopped export |
| 22 | Build order | **Export built and run first; the import built on the Linux machine from directions in its `CLAUDE.md`** (both 2026-09-24) | Windows cannot prove the SQL loads; the unverified facts were listed for the first Linux run, which confirmed every one without a correction to `oracle.ps1` |
| 23 | Oracle image and passwords | **`gvenzl/oracle-free:23.26.3-faststart`**; the start-up password through `ORACLE_PASSWORD_FILE`, then SYS, SYSTEM and PDBADMIN given random passwords nobody keeps (PDBADMIN locked); the tool uses operating-system authentication; the schema is a `NO AUTHENTICATION` account | The official registry needs a token even to list tags and prints its generated password; the community image's random-password option is weak and logged; PDBADMIN keeps its build-time password unless changed. The PostgreSQL rule (no password in `docker inspect`, none stored) holds |

### 10.3 Status and what is verified

`export-oracle` passes its 13 self-tests and its cross-check against PostgreSQL. `import-oracle` (2026-09-24, Oracle AI Database 26ai Free 23.26.3) loads its SQL unchanged and verifies 86 of 86 checks with 155 of 155 rows identical; self-test 7 of 7. The Oracle rules written without a database are **confirmed**: identity `RESTART START WITH` (the next id is `identityLast + 1`), `BOOLEAN` with `DEFAULT FALSE NOT NULL`, multi-row `INSERT`, `TIMESTAMP(3)` literals, unquoted `timestamp`/`action`/`state`/`text`/`name`/`description` (none reserved), `SET DEFINE OFF`, the `WHENEVER SQLERROR` lines (a failed script stops with exit 1 and leaves its DDL behind), the function-based index (case-insensitive for active users, deleted users absent), and `CHR`/`UNISTR` literals including a surrogate-pair emoji (a round-trip test in the verification). **Found:** `MAX_STRING_SIZE` is `STANDARD`, so a `VARCHAR2(2000 CHAR)` value is also limited to 4,000 bytes (2,000 two-byte characters fit; 1,334 three-byte characters do not); `BOOLEAN` silently converts numbers and words such as `'yes'`. **Not exercised by the current data:** `TO_CLOB(...)` literals (every CLOB is NULL) and expressions spread over several lines (the longest data line is 306 characters); export-oracle's stress test with awkward data, loaded by import-oracle, would cover them.

This document should be updated whenever a tool is added or the security policy in §5 changes in a way that should apply retroactively to how future migrations are reviewed.
