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
| 1 | SQL Server → SQLite, native | Windows | Done | `docs/dbmigrate/iteration1/` |
| 2 | SQL Server → SQLite inside a Docker Linux container, loaded at container-runtime | Windows orchestrates; target is Linux | Done | `docs/dbmigrate/iteration2/` |
| 3 | SQL Server (via iteration 2's export) → SQLite baked into a Docker image at build time; verification and tooling run **entirely on Linux**, with **no dependency on iteration 1/2's stored results** and **credentials sanitized before anything is built or committed** | Linux, end to end | Done | `docs/dbmigrate/iteration3/` |
| — | MySQL in Docker | Windows | Extra work, not a numbered iteration | (results embedded in iteration 1/2 regression runs) |
| 4+ | PostgreSQL in Docker; eventually Oracle (the actual Phase 2 target) | TBD | Not started | — |

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

- **Config-driven sensitive-column declarations** (§5.2.5) — today, sanitization is a bespoke script per iteration; it should become a `migration.config.json`-declared policy the export/verify pipeline enforces generically.
- **Moving `sanitize.py` to run at export time** (§5.2.4, decided but not yet implemented) — iteration 3 currently sanitizes after the raw file already reached the Linux machine. Open sub-question: iteration 3's `verify.py` cross-checks sanitized output against the raw source to prove non-credential columns are unchanged (`check_credential_sanitization`) — once sanitize runs upstream, that specific cross-check needs to also run there (right after sanitizing, before the raw file is discarded), not be dropped, since it's already caught one real bug this project.
- **PostgreSQL and Oracle dialects** — the roadmap's next two targets; Oracle is the actual Phase 2 destination and doesn't exist yet.
- **A formal data-classification step before export** — right now, sensitive columns are identified by inspection (a human, or Claude, reading the schema). A real engagement should start with an explicit classification pass (PII/PCI/PHI/credential/none) per column, signed off by the data owner, before any export tooling runs.

## 7. Document map

| Iteration | Plan | Record | Verification report | Database guide |
|---|---|---|---|---|
| 1 | `docs/dbmigrate/iteration1/ITERATION1_PLAN.md` | `ITERATION1.md` | `MigrationVerificationReport1.docx` | `SQLiteDatabaseGuide1.docx` |
| 2 | `docs/dbmigrate/iteration2/ITERATION2_PLAN.md` | `ITERATION2.md` | `MigrationVerificationReport2.docx` | `SQLiteDatabaseGuide2.docx` |
| 3 | `docs/dbmigrate/iteration3/ITERATION3_PLAN.md` | `ITERATION3.md` | `MigrationVerificationReport3.docx` | `SQLiteDatabaseGuide3.docx` |

This document should be updated whenever a new iteration starts (add its row to §3 and §7) or whenever the security policy in §5 changes in a way that should apply retroactively to how future iterations are reviewed.
