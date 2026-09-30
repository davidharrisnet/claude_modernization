# Data Migration Strategy

> **Location.** Since 2026-09-23 this document and the two tool folders live in `docs/phase1/dbmigrate/`, and the tooling in `tools/phase1/dbmigrate/` (previously `docs/DATA_MIGRATION.md`, `docs/dbmigrate/`, `tools/dbmigrate/`). Older commits and the generated reports show the old paths and the earlier numbered-iteration names.

This is the parent document for the database migration: `tools/phase1/dbmigrate/` and `docs/phase1/dbmigrate/`. The migration is two tools, each with two documents for two readers — a `README.md` for people in `docs/phase1/dbmigrate/<tool>/` (what the tool does and its latest results) and a `CLAUDE.md` with the instructions for Claude Code in `tools/phase1/dbmigrate/<tool>/` — plus the generated report (and, for `import-oracle`, the database guide). Both documents describe the current state only; git holds the history. This document sits above them: it's the strategy, the decisions, and the security policy both tools follow. Read this first; go to a tool's docs for the detailed proof that it worked.

| Tool | What it does | Runs on | Run it by typing |
|---|---|---|---|
| `export-oracle` | SQL Server LocalDB → sanitized Oracle files | Windows | `/export-oracle` or `Run export-oracle` |
| `import-oracle` | those files → a verified Oracle AI Database 26ai Free in Docker | Linux | `/import-oracle` or `Run import-oracle` |

## 1. Purpose and scope

This project's Phase 2 target is Angular / Spring Boot / **Oracle**, as the exercise brief (`README.md`) names. Before application code exists, the data layer is proven out on its own, against the real Phase 1 database (`MasterAntiqueRepair`, SQL Server LocalDB). The migration follows a four-step discipline so results are comparable and auditable:

1. **Export** the data from the source database into portable, plain-text SQL.
2. **Populate** a new, independent target database from that export.
3. **Verify** the target is identical to the source (where no live source connection is possible, identical to the record of the source made at export — see §5.3).
4. **Report** the result as a stakeholder-readable document, plus a plain-language record of what was done.

The point of this discipline is that the migration is provably deterministic: the same source always produces the same export, and the same export always produces the same verified target. No step relies on an AI model's judgment at run time — the export, load, verify and report logic is checked-in script, not a one-off action.

## 2. Steps: the migration pipeline

```
SQL Server (LocalDB)
      │  export-oracle (Windows): reads catalog + rows, sanitizes credentials IN MEMORY,
      │                           renders Oracle SQL*Plus scripts, records the source in a metadata file
      ▼
01-schema.sql + 02-data-sanitized.sql + source-metadata.json   ← the only artifacts; credential-free, checked into git
      │  hand-off: copied into tools/phase1/dbmigrate/import-oracle/input/ and committed
      ▼
      │  import-oracle (Linux): checks the files against the recorded hashes, loads them into
      │                         Oracle in a Docker container, verifies, self-tests, reports
      ▼
Oracle database (container mar-oracle, pluggable database FREEPDB1, schema masterantique)
      │  verify: row counts, canonical content hashes, schema facts, business-summary queries,
      │          behaviour/rule tests, tooling self-test
      ▼
verification-results.json  →  MigrationVerificationReport.html
                          →  OracleDatabaseGuide.html
```

**Export** reads the source database's own catalog (tables, columns, types, keys, indexes, defaults, identity state), works out a safe table load order, and converts every row to one canonical text form — so two exports of unchanged source data are byte-identical, and any database built from the export can be compared by hashing. This is what makes steps 3 and 4 possible without hand-inspection.

**Sanitize** happens inside the export, in memory, after the rows are read and before anything is rendered or written (see §5.2). The raw credential values never reach a file, so there is no raw export to protect, transfer or delete; only the sanitized files exist.

**Populate** is done by an Oracle container that the load step creates, and by nothing else: the export renders Oracle SQL through one **dialect** module (`oracle.ps1`: rename map, type mapping, schema and data rendering), and the Linux tool loads that SQL with `sqlplus` inside the container.

**Verify** is deliberately over-built relative to "does the row count match": it checks row counts, full canonical-content hashes per table, schema facts (keys, indexes, constraints), business-level summary queries (the kind of question the application asks), and behaviour tests that exercise application-level rules (for example the soft-delete username reuse rule) that are rolled back. On top of that, a **self-test** proves the tooling itself is trustworthy: a second export must be byte-identical to the first, and a deliberately damaged copy must be caught and named precisely.

**Report** produces a verification report (results, tables, structure, summaries, aimed at a technical reviewer or an engagement lead), a Word export report from the Windows side, and a database guide (connection routes, application logins, a tested Spring Boot project, aimed at whoever has to work with the database next).

## 3. Status

| Tool | Status | Docs |
|---|---|---|
| `export-oracle` | **Built and run** (self-test 13 of 13); its SQL loads into Oracle unchanged (proven by import-oracle) | `docs/phase1/dbmigrate/export-oracle/` |
| `import-oracle` | **Built and run** (verification 86 of 86 checks, 155 of 155 rows identical; self-test 7 of 7) on Oracle AI Database 26ai Free 23.26.3; database guide written (decision 16) | `docs/phase1/dbmigrate/import-oracle/` |

Each tool is self-contained under `tools/phase1/dbmigrate/<tool>/` — its own copy of whatever tooling and input files it needs — so its results can be reproduced without depending on the other tool's state; the only coupling is the three-file hand-off (§8.1).

## 4. Extending the export to a new target database

To add a target (for example in another project):

1. Add a new file under `tools/phase1/dbmigrate/export-oracle/migration/dialects/` next to `oracle.ps1`, implementing the same `RenderSchema`/`RenderData` interface (naming, types, defaults, filtered indexes, statement mechanics for that database).
2. Add a `target` block to `migration.config.json` naming the dialect and where the report should land.
3. No change is needed to `Export.ps1`, `Metadata.ps1` or the self-test — they only ever call through the dialect interface (the metadata's canonical row form is database-independent).
4. Write the loading and verifying tool for that database (the equivalent of `import-oracle`), with its `CLAUDE.md` (instructions for Claude Code) and `README.md` (description and latest results), following the shape of the existing ones.

## 5. Security

This section is the part of the strategy every future migration — and eventually every real migration this tool is pointed at — must follow. It was tightened after a real (low-stakes, but instructive) lapse; the lesson is written up here so it doesn't get relearned.

### 5.1 What went wrong once, and why it matters going forward

Early in this project, `.gitignore` excluded the tool output folders specifically because exported data files contained real, credential-equivalent data (password hashes, security stamps) copied byte-for-byte from the source, which a faithful migration must do. A later commit removed that exclusion and committed the raw export — including real PBKDF2 hashes for the project's seeded test accounts — to a public GitHub branch. Because `MasterAntiqueRepair` is a synthetic exercise app, no real person's credentials were exposed, and the repository's history for that branch was subsequently rewritten (`git filter-repo`, force-pushed) to remove the affected files from history entirely.

**The reason this belongs in the strategy document, not just an incident footnote:** this tool is meant to be pointed at real legacy enterprise systems later, with real users and real data. A `.gitignore` line is not a security control — it's one file away from being silently removed, exactly as happened here. The policy below is what actually needs to hold, independent of any single config file.

### 5.2 Credential and sensitive-data policy

**A migration must carry every column faithfully, including credential columns — verification depends on it.** The problem is never the export step; it's what happens to the export afterward. The policy:

1. **Never let raw exported credential data enter a committed or distributed artifact.** Not git, not a Docker image layer, not a shared drive. Best of all, never write it at all.
2. **For a one-time bootstrap migration (legacy → new system, cutover), invalidate credentials as part of the migration itself, rather than trying to carry them forward securely.** `export-oracle` reads the rows, sets every migrated account's password hash and security stamp to `NULL` in memory (`Protect-SensitiveData`), and adds an explicit `MustResetPassword` column set to `true`. Only sanitized text is ever rendered or written, so the files contain no usable credential. This is deliberately a data-layer decision, not an afterthought: the target system never needs to understand the legacy password-hash format at all, and no downstream artifact (backup, image, registry push) needs to be treated as a secret indefinitely. The tool **refuses to run** with sanitizing switched off (exit 2), so an unsanitized file cannot be produced by mistake.
3. **Verification of the sanitization step is not optional.** It's not enough to assume the transform worked — the tools verify, in code, that (a) every row's credential columns are actually invalidated in the delivered target (`import-oracle` sanitization checks), (b) no credential value read from the source appears in any output file (`export-oracle` self-test), and (c) every *other* column is provably unchanged from the source, so "sanitize" can't silently become "corrupt" (the per-table content hashes are computed over the sanitized rows, and the credential columns hash as `NULL`, so no credential is ever hashed either).
4. **Sanitize on the machine that produced the export, immediately, not later or elsewhere.** Because sanitizing happens in memory inside the export, the raw values never leave the process. Only `01-schema.sql`, the sanitized data file and the metadata ever cross a machine boundary. If a raw copy is genuinely ever needed off the originating machine (rare), encrypt it first (e.g. `age`/`gpg`) — the transport medium doesn't matter once the file itself is encrypted; an unencrypted file on a USB drive is not meaningfully more secure than one sent over a network, since the drive can just as easily be lost.
5. **This generalizes beyond passwords.** A real legacy enterprise database will have other sensitive columns this project hasn't had to handle yet: PII (SSNs, dates of birth, addresses), payment data, health data, security answers. The forward-looking version of this policy is a **declared, per-table sensitive-column list** in `migration.config.json` (not yet built — see §6), so a future migration doesn't have to hand-write a bespoke transform per project the way `Protect-SensitiveData` is written for `MasterAntiqueRepair.Users`. Whether the right transform for a given sensitive column is "null it," "hash it differently," "mask it," or "leave it and treat the whole artifact as a protected secret" is a decision to make per column, with the customer/data owner, not a default this tool should silently choose.

### 5.3 Verification must not inherit unearned trust

A verification step that only checks "does this match what a previous run already claimed was correct" isn't actually verifying anything — it's propagating whatever that previous run got wrong. The standing rule for any step that can't reach a live source system: **check against a record made by an independent code path.** `import-oracle` cannot reach SQL Server, so it verifies against `source-metadata.json`, which `export-oracle` builds from the source catalog and the same in-memory rows but **not** from the rendered SQL. A renderer bug therefore shows up as a disagreement between the loaded database and the record. What this does not guard against is tampering: anyone who can edit both the record and the SQL can make them agree (§8.5).

### 5.4 Distributable artifacts (images, backups, exports)

- Never bake unsanitized data into a Docker image layer. A layer persists in the image's history even if a later layer deletes the file, and images get pulled, cached, and pushed to registries — a much wider blast radius than a single file on disk.
- A sanitized artifact (§5.2) is safe to distribute precisely because there's no secret left in it to protect. An unsanitized one (any raw export, any pre-sanitization database file) must never leave the machine that produced it, and must never be pushed to a registry, public or private. The `mar-oracle` database is created only from the sanitized files and is never published to a host port.
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
- **Automating the hand-off copy** from `export-oracle` to `import-oracle`; it is done by hand.

## 7. Database-agnostic exports: what is and isn't possible

**Status: considered and set aside.** The export was first framed as producing one set of files loadable into any database. This section records why that is not possible; the export as decided targets Oracle (§8).

**The original goal.** Produce schema and data files that are checked into git, pulled on a Linux machine, and loaded into whichever database is required. Nothing in the files should be specific to one database, and the data must be credential-sanitized (§5.2).

**Finding: completely database-agnostic SQL files are not possible.** SQL itself differs per database at exactly the points this schema uses.

| Feature in this schema | Why no single SQL spelling works across databases (for example SQLite and Oracle) |
|---|---|
| Filtered unique index `IX_Users_Name_Active` (`WHERE DeletedAt IS NULL`; soft delete frees the username) | Native in SQLite; Oracle needs a function-based index; a portable composite unique index on `(Name, DeletedAt)` behaves differently per database (NULLs are distinct in SQLite, compared in Oracle). The rule cannot be enforced by portable DDL. |
| Auto-increment (`Id` columns) | `AUTOINCREMENT`, `GENERATED ... AS IDENTITY` and sequences have no common form. The fallback is a plain `INTEGER PRIMARY KEY` with explicit ids, which loses "the next id continues the sequence". |
| Timestamps (`CreatedAt`, `DeletedAt`, ...) | No date or timestamp literal is accepted everywhere; Oracle rejects a plain string unless a session setting matches. A single script means storing timestamps as text. |
| Long text (`PasswordHash`, `SecurityStamp`, `PhoneNumber`, claim columns) | `TEXT` does not exist in Oracle and `CLOB` does not exist elsewhere; it has to become `VARCHAR(n)`, and Oracle counts `VARCHAR` in bytes by default (multi-byte text can overflow; 4000-byte limit). |
| Load mechanics | `PRAGMA` and `BEGIN` versus implicit transactions, multi-row `INSERT ... VALUES` (not in older Oracle), Oracle treating `''` as NULL, identifier case folding (quoted names then required forever), `&` prompts in SQL*Plus. |

A "lowest common denominator" SQL script that every database accepts unchanged is possible only by giving things up: timestamps stored as text, no filtered unique rule, no identity, one-row `INSERT`s, no transaction or `PRAGMA` statements.

**What can be agnostic is a description, not SQL.** Two kinds of artifact must be kept apart:

1. **Loadable files** (SQL): always target one database's dialect, so they can never be fully agnostic.
2. **Neutral files**: the schema as structured data (logical types, keys, foreign keys with delete actions, indexes with the filter as structured data, not SQL text) and the data as typed records (real `null` versus empty string, ISO timestamps, true/false). These are agnostic, but need a small **per-database renderer** to become SQL. The renderer runs on the Linux side, so the checked-in files stay neutral and each target's SQL is generated at load time.

The two properties cannot both hold: files fed straight to a database must be SQL (not agnostic), and files that are agnostic need a translator before a database can use them.

**Why the sanitize-first seam is the right place.** `Invoke-Export` already holds the schema model and the rows in memory before any dialect renders SQL, and credentials are sanitized there (§5.2). A neutral export would be one more output at the same point, so everything it writes would be credential-free by construction.

**Decision:** neither route was taken. The export is Oracle-specific (§8). Another target is another dialect at the same seam (§4); its metadata would match this export's row fingerprints because the canonical form is database-independent.

## 8. Oracle: the two tools

**Goal.** Move the SQL Server database to Oracle in two separate, repeatable, command-line tools that need no Claude session to run:

- **`export-oracle` (Windows, export only):** export the SQL Server database into sanitized **Oracle** schema and data files (SQL*Plus scripts) plus a metadata file, checked into git. **No Docker, no target database.** Description: `docs/phase1/dbmigrate/export-oracle/README.md`; instructions for Claude: `tools/phase1/dbmigrate/export-oracle/CLAUDE.md`.
- **`import-oracle` (Linux, Docker):** read those files, create a fully populated **Oracle AI Database 26ai Free** database in a **Docker container** (`gvenzl/oracle-free:23.26.3-faststart`), and verify the data is the same as the source it was exported from, with PL/SQL run by `sqlplus` inside the container. Description: `docs/phase1/dbmigrate/import-oracle/README.md`; instructions for Claude: `tools/phase1/dbmigrate/import-oracle/CLAUDE.md`.

The decisions below are shared by both tools; §8.8 is the full decision log.

### 8.1 Where each stage runs

| Stage | Runs on | Why |
|---|---|---|
| Export (read SQL Server, sanitize, render Oracle files, write the metadata JSON) | Windows | The source is SQL Server LocalDB; the tooling is Windows PowerShell. |
| Check-in and hand-off | git | The three files below are the only artifacts that cross to Linux. After a successful export they are copied (manually) into `tools/phase1/dbmigrate/import-oracle/input/` and committed. |
| Load, verify, report (`import-oracle`) | Linux | bash and Docker only: an Oracle container (`mar-oracle`) holds the database; `sqlplus` runs inside it. No Python, no Java, no host Oracle client. |

The Windows side is PowerShell tooling with one dialect file, `oracle.ps1`, implementing the `RenderSchema`/`RenderData` interface. It is called at the sanitize-first seam: after `Protect-SensitiveData` and before anything is written, so raw credentials never reach disk (§5.2). The export only renders text; the tool does not import into or query an Oracle server on Windows.

### 8.2 Outputs (checked in)

| File | Content |
|---|---|
| `01-schema.sql` | Oracle DDL as a SQL*Plus script: tables, named primary keys, foreign keys with delete actions, indexes, defaults. Pure ASCII, LF. |
| `02-data-sanitized.sql` | The data as Oracle `INSERT`s, credentials sanitized (`PasswordHash`/`SecurityStamp` NULL, `MustResetPassword` true), one `COMMIT`, then the identity restarts. |
| `source-metadata.json` | The metadata report from the SQL Server source, used by the Linux side to verify the new database (§8.5). Contains counts and hashes of sanitized rows only: no credentials and no personal data. It holds no SQL to be executed (the source queries are recorded as documentation only). |
| `docs/phase1/dbmigrate/export-oracle/MigrationExportReport.docx` | The export report (Word), built on Windows from `source-metadata.json`; for people, not consumed by `import-oracle`. It carries no PASS/FAIL against a target. |

### 8.3 SQL Server to Oracle mapping

| Topic | Oracle rule | Why |
|---|---|---|
| Integers, identity | `NUMBER(10)` (`NUMBER(19)`, `NUMBER(5)`); `GENERATED BY DEFAULT AS IDENTITY` with a named primary key (`pk_<table>`); after the load `ALTER TABLE ... MODIFY (id GENERATED BY DEFAULT AS IDENTITY (RESTART START WITH last+1))` | Accepts the explicit ids in the data; the next id continues from the maximum |
| Booleans | Native `BOOLEAN` (23ai and later) | 26ai is the target (decision 6) |
| Timestamps | `TIMESTAMP(3)`, no time zone; literal `TIMESTAMP '...'` | Decision 3 |
| Text | `VARCHAR2(n CHAR)`; `nvarchar(max)` becomes `CLOB` | Source lengths are in characters; a `VARCHAR2` is also limited to 4000 bytes unless `MAX_STRING_SIZE=EXTENDED` (checked on load) |
| Soft-delete unique rule | Function-based unique index on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END` | Oracle has no partial index; a B-tree index stores no all-NULL key, so filtered-out rows never collide (decision 2) |
| Foreign keys | `ON DELETE CASCADE` kept; `NO ACTION` written by leaving the clause out | Oracle rejects the words; its default is no action |
| Empty string | The export **refuses** a source that contains one | Oracle stores `''` as NULL, which would silently change the data and break "NULL stays distinct from the empty string"; the current data has none (decision 17) |
| String literals | Pure ASCII: control characters `CHR(n)`, other characters `UNISTR('\XXXX')`, plain runs `'...'`, joined with `\|\|` and spread over lines when long | The SQL*Plus client reads through `NLS_LANG`, splits input at lines and blank lines and rejects lines of about 2,499 characters; none of that can touch the data |
| Transactions | No `BEGIN`/`COMMIT` around DDL; data in one `COMMIT`; scripts start with `WHENEVER SQLERROR EXIT FAILURE` and `SET DEFINE OFF` | DDL commits by itself; `&` must not prompt |
| Inserts | Multi-row `INSERT ... VALUES` (23ai and later), 100 rows per statement | Decision 12 |

### 8.4 Names and case

- **Identifiers are unquoted lowercase snake_case** (`created_at`, `password_hash`, `user_id`) from an explicit rename map in `tools/phase1/dbmigrate/export-oracle/migration/dialects/oracle.ps1` (its rules are in `tools/phase1/dbmigrate/export-oracle/CLAUDE.md`); Oracle stores them in upper case, so nothing needs quoting. Every identifier is checked against the reserved-word list, a pattern and 128 bytes, and the export stops on a problem. Index and constraint names are schema-wide, so the table-prefix rule for colliding names (for example `IX_UserId`) applies. The metadata JSON records the source name and target name of every table and column, and verification maps between them explicitly.
- **Data is never lowercased.** Only identifiers change. Comment text and ticket descriptions (case carries meaning in a grammatical sentence), role names (`Manager`), usernames and emails are all stored exactly as in the source, so the fidelity claim stays "every column identical except credentials, which are sanitized". A username lowercased in storage cannot be shown as the user typed it (the case is unrecoverable), so usernames are deliberately not lowercased for user-friendliness.
- **Usernames are case-insensitive**, as they were in SQL Server (its default collation is case-insensitive; Oracle's comparison is case-sensitive by default). The rule goes in the index, not in the data (decision 2): `CREATE UNIQUE INDEX ix_users_name_active ON users (CASE WHEN deleted_at IS NULL THEN LOWER(name) END)`. "Bob" and "bob" cannot both be active, and the soft-delete reuse rule still holds. **Phase 2 requirement:** authentication must compare `CASE WHEN deleted_at IS NULL THEN LOWER(name) END = LOWER(:input)` so the query uses the index.
- **Email** is likewise treated as case-insensitive but stored as entered, compared by the application with `LOWER()`. The legacy schema has no email index, so there is no database rule now; if email uniqueness is added later it uses the same `LOWER()` index form. **URLs:** there is no URL column today; if one is introduced, only the scheme and host are case-insensitive (the path and query can be case-sensitive), so the rule would be "host lowercased, the rest as entered", decided when it appears.

### 8.5 The metadata JSON and Linux-side verification

`source-metadata.json` is written on Windows from the SQL Server catalog and the same in-memory rows the SQL is rendered from (after sanitizing), by a code path independent of the SQL rendering. It contains:

- **Structure:** tables, columns (source type, target name and Oracle data-dictionary type with `precision` and `scale`, nullability, defaults), primary keys, foreign keys with delete actions, indexes including the full key expression of the soft-delete, case-insensitive index; `minOracleVersion` 23.
- **Data facts:** row count per table and a SHA-256 per table over a canonical row form (defined independent of any database: rows sorted ascending by their own canonical text, so no primary-key or collation knowledge is needed; integers in decimal, booleans as 0/1, timestamps as `yyyy-MM-dd HH:mm:ss.fff`, strings as hex of their UTF-8 bytes, NULL distinct from the empty string). Sanitized rows only, so no credential is hashed.
- **Business summaries:** counts of the kind the application asks (users by type, tickets by state, audit events by action, and so on).
- **Expectations:** credential columns NULL and `MustResetPassword` true for every user; the active-username rule holds.
- **Provenance:** SHA-256 of `01-schema.sql` and `02-data-sanitized.sql`, source database name, tool version, and the run time (the only non-deterministic field, kept in its own section).

The Linux ingest step (`import-oracle`: bash and Docker only; `sqlplus` runs inside the container as SYS by operating-system authentication; a static `verify.sql` reads the JSON into `JSON_OBJECT_T` and builds every query itself, so the JSON needs no SQL text):

1. Confirms the SQL files match the recorded SHA-256 values (transfer integrity) before any container exists.
2. Starts the Oracle container (`mar-oracle`; no published port; no password kept), checks the version (23 or later) and character set (`AL32UTF8`), creates the password-less schema `masterantique` in `FREEPDB1`, and loads `01-schema.sql` then `02-data-sanitized.sql`, stopping at the first error.
3. Recomputes the per-table canonical hashes from the database it built, and compares row counts, schema (columns, types, keys, foreign keys, indexes with their expressions) and the business summaries against the JSON. A mismatch fails with the exact table and column.
4. Runs the rule tests, each rolled back to a savepoint: duplicate active username rejected, including differing only by case; soft-deleted username reusable; orphan foreign key rejected; the identity continues from the maximum; `BOOLEAN` rejects a non-boolean; multi-byte and control-character text round-trips.
5. Checks the sanitization expectations.
6. Writes `verification-results.json` and `MigrationVerificationReport.html` (a self-contained HTML report generated inside the container by `report.sql`).

**What this verification is and isn't.** It verifies the loaded database against a manifest, not against the live source, because the Linux machine cannot reach SQL Server. It is still a real end-to-end check of the renderer and the load, since the manifest comes from an independent code path. It guards against mistakes, not tampering: anyone with write access could edit both the manifest and the SQL.

### 8.6 What cannot be proven on Windows

Windows can prove that the export is deterministic (two exports byte-identical), that the row counts in the generated SQL match the source, and that the credentials are sanitized. It cannot prove the SQL loads, because `export-oracle` is export only and has no Oracle. The load is proven by `import-oracle`, in a Docker container on the Linux machine; a rendering bug found there is fixed in `export-oracle`'s `oracle.ps1` and the export is re-run (decision 10).

### 8.7 What is verified

`export-oracle` passes its 13 self-tests. `import-oracle` (Oracle AI Database 26ai Free 23.26.3) loads its SQL unchanged and verifies 86 of 86 checks with 155 of 155 rows identical; self-test 7 of 7. Confirmed on the database: identity `RESTART START WITH` (the next id is `identityLast + 1`), `BOOLEAN` with `DEFAULT FALSE NOT NULL`, multi-row `INSERT`, `TIMESTAMP(3)` literals, unquoted `timestamp`/`action`/`state`/`text`/`name`/`description` (none reserved), `SET DEFINE OFF`, the `WHENEVER SQLERROR` lines (a failed script stops with exit 1 and leaves its DDL behind), the function-based index (case-insensitive for active users, deleted users absent), and `CHR`/`UNISTR` literals including a surrogate-pair emoji (a round-trip test in the verification). **Found:** `MAX_STRING_SIZE` is `STANDARD`, so a `VARCHAR2(2000 CHAR)` value is also limited to 4,000 bytes (2,000 two-byte characters fit; 1,334 three-byte characters do not); `BOOLEAN` silently converts numbers and words such as `'yes'`. **Not exercised by the current data:** `TO_CLOB(...)` literals (every CLOB is NULL) and expressions spread over several lines (the longest data line is 306 characters); export-oracle's stress test with awkward data, loaded by import-oracle, would cover them.

### 8.8 Decisions

| # | Decision | Answer | Reasoning |
|---|---|---|---|
| 1 | Identifier style | **Unquoted lowercase snake_case** (`created_at`, `user_id`) from an explicit rename map | Readable, matches Spring Boot's default naming, and nothing needs quoting. Needs a written, reviewable rename map; names differ from the legacy schema (a parity note, not a data change). |
| 2 | Case-insensitive names | **Usernames stored as typed; a function-based unique index on `CASE WHEN deleted_at IS NULL THEN LOWER(name) END`; authentication lowers both the stored name and the input.** Email stored as typed with no database rule. **No data is lowercased.** | Storing lowercase would lose the case the user typed and show it wrongly on the page. Free text such as comments keeps its case because case carries meaning. Cost: mixed-case names can be stored, and lookups must use `LOWER()`. |
| 3 | `datetime` column type | **`TIMESTAMP(3)` (without time zone)** | A faithful 1:1 mapping: SQL Server `datetime` has no time zone, so values are stored exactly as they are with no interpretation. A time-zone type would need an assumed source zone. **Caveat to keep:** it is not known whether the legacy application stored UTC or local times (only `LockoutEndDateUtc` is UTC by name), so no conversion is made and a Phase 2 mapping must decide the zone. Millisecond precision, as at the source. |
| 4 | `roles.name` unique index | **Plain, case-sensitive unique index** (`ix_roles_name`) | Roles are created only programmatically, never typed by a user, so the database does not need to enforce case-insensitivity; keeping role names consistent is a convention for the technical team and Claude Code. |
| 5 | Identity columns | **`GENERATED BY DEFAULT AS IDENTITY`**, restarted after the load at the last source id + 1 | It accepts the explicit ids in the data; `ALWAYS` would reject them. |
| 6 | Oracle version | **Oracle AI Database 26ai Free** (the 23ai code line), in Docker on the Linux machine; 26ai features (`BOOLEAN`, multi-row `INSERT`) are allowed; the tool refuses a server older than 23 | Free, runs in a container (limits: about 2 CPU threads, 2 GB RAM, 12 GB data, far above this data). Caveat: many real systems run 19c, where those two features do not exist; switching is a small change in `oracle.ps1` (`NUMBER(1)` with a `CHECK`, single-row inserts). |
| 7 | Linux tooling (`import-oracle`) | **bash and Docker only**; `sqlplus` runs inside the container. No Python, no Java, no host Oracle client. | Smallest prerequisite set; verification is PL/SQL run through `sqlplus`. |
| 8 | Windows tooling (`export-oracle`) | **Self-contained PowerShell tooling** with an `oracle.ps1` dialect | Reproducible without depending on another tool's folder. |
| 9 | How verification reads the metadata (`import-oracle`) | **A static `verify.sql` reads `source-metadata.json` into `JSON_OBJECT_T`; every query is built from metadata names that must be plain identifiers; the JSON's SQL text is never run** | One source of truth; nothing executable is read from a data file. |
| 10 | Where the generated SQL is proven to load | **In the Docker container on the Linux machine, by `import-oracle`** | That container is the deliverable; no separate throwaway database. A rendering bug found there is fixed in `export-oracle`. |
| 11 | Output file names (`export-oracle`) | **`01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`** in `tools/phase1/dbmigrate/export-oracle/` | The `-sanitized` name says the file is safe to commit. |
| 12 | Data load statements (`export-oracle`) | **Multi-row `INSERT ... VALUES`** (100 rows per statement), one `COMMIT` | Readable; a bulk loader is unnecessary at 155 rows. |
| 13 | Verification report (`import-oracle`) | **`MigrationVerificationReport.html`**, generated from `verification-results.json` by `report.sql` inside the container | The Word generator needs PowerShell and `System.Drawing`; HTML needs no conversion tool and rebuilds byte-identically. |
| 14 | Metadata and export report (`export-oracle`) | **`source-metadata.json` is written at export; a Word export report `MigrationExportReport.docx` is built from it on Windows** | The data about the source database is recorded at export. The export verifies nothing against a target, so it produces an export report, not a verification report. |
| 15 | Container, image and passwords (`import-oracle`) | **`gvenzl/oracle-free:23.26.3-faststart`, container `mar-oracle`, pluggable database `FREEPDB1`, schema `masterantique` as a `NO AUTHENTICATION` account; the start-up password through `ORACLE_PASSWORD_FILE`, then SYS, SYSTEM and PDBADMIN given random passwords nobody keeps (PDBADMIN locked); the tool uses operating-system authentication; no published port** | No password in git, `docker inspect`, a file or the output. The official registry needs a token even to list tags and prints its generated password; the community image's random-password option is weak and logged; PDBADMIN keeps its build-time password unless changed. `docker rm -f -v` removes the database, and `--recreate` does exactly that. |
| 16 | Database guide (`import-oracle`) | **`docs/phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html`**, tested against a copy of the database | SQL*Plus in the container, application logins, network routes, plain JDBC and a Spring Boot 4.1.1 JPA project with the first-login password change. |
| 17 | Empty strings | **Refuse them** in the export | Oracle stores `''` as NULL; a silent conversion is worse than a stopped export. |

## 9. Document map

| Tool | Description (README, for people) | Instructions for Claude (CLAUDE.md) | Report | Database guide |
|---|---|---|---|---|
| `export-oracle` | `docs/phase1/dbmigrate/export-oracle/README.md` | `tools/phase1/dbmigrate/export-oracle/CLAUDE.md` | `MigrationExportReport.docx` (an export report; no verification) | — |
| `import-oracle` | `docs/phase1/dbmigrate/import-oracle/README.md` | `tools/phase1/dbmigrate/import-oracle/CLAUDE.md` | `MigrationVerificationReport.html` | `OracleDatabaseGuide.html` |

This document should be updated whenever a tool is added or the security policy in §5 changes in a way that should apply retroactively to how future migrations are reviewed.
