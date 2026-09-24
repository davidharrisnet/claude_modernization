# Iteration 3: an independently-verified, credential-sanitized Docker image, built entirely on Linux

**What this document is.** A step-by-step, plain-language account of iteration 3 as actually carried out, including a correction made mid-iteration after review caught two real problems in an earlier draft. It is written so parts of it can be lifted into a project report.

| Document | Purpose |
|---|---|
| [ITERATION3_PLAN.md](ITERATION3_PLAN.md) | The plan and design *before* the work (already reflects the corrected design). |
| **ITERATION3.md (this file)** | The work as carried out, step by step, with the results. |
| `MigrationVerificationReport3.docx` (this folder) | The detailed verification report, in the same section shape as iterations 1 and 2. |
| [ITERATION2.md](../iteration2/ITERATION2.md) | The record for iteration 2. Read it first for background. |

---

## 1. Purpose, and what changed mid-iteration

The goal: bake the exported schema and data into a Docker image, with the tooling and the verification itself running entirely on Linux — no PowerShell, no Windows, and (unlike iteration 2, which still needed Windows to orchestrate against a live SQL Server) no dependency on any other iteration at verification time either.

A first working draft of this iteration built and passed 41 of 41 checks, matching iterations 1 and 2's totals exactly — but on review, two real problems were found in *how* it verified itself, not in the database it produced:

1. **Not actually independent.** The draft's `verify.py` read `tools/phase1/dbmigrate/iteration2/verification-results.json` as its source of "correct" answers, and diffed the built database against `tools/phase1/dbmigrate/iteration1/masterantique.sqlite`. That means its checking logic inherited iteration 1/2's stored results rather than re-establishing correctness on its own — if either of those stored artifacts had ever been wrong, the draft would have agreed with the error instead of catching it.
2. **Real credentials in a distributable artifact.** The draft copied `02-data.sql` (real PBKDF2 password hashes for the 12 seeded accounts) verbatim and baked it into the Docker image. Separately, an earlier commit (`7a4257b`) had already committed that same raw data to git after removing a `.gitignore` protection meant to keep it out.

Both were fixed together: since this project's use case is a one-time legacy→modern bootstrap where forcing a password reset on next login is acceptable, there is no need to carry a *usable* credential into the target at all. Sanitizing credentials as part of the migration is both the security fix and a genuinely independent thing for iteration 3 to verify — a real transformation, checked on its own terms, not a re-run of an inherited answer.

## 2. Environment

Unchanged from the working draft: plain Linux Docker Engine 29.7.2 (no Docker Desktop, no WSL2), `alpine:3.20` base image, SQLite 3.45.3 baked into the image, local `sqlite3` 3.51.0 (via this host's own Python distribution) used for the independent control build. No PowerShell, no live SQL Server connection anywhere in this iteration.

## 3. What had to change

- **`sanitize.py`** (new) — reads the raw `02-data.sql`, rewrites every `Users` row's `PasswordHash`/`SecurityStamp` to `NULL`, sets a new `MustResetPassword` column to `1`, and writes `02-data-sanitized.sql`. Verified this session: 12 of 12 rows sanitized; a `diff` against the raw file shows only the 13-line `Users` INSERT block changed (the header plus its 12 rows) — every other line, across `AuditLogs`, `Tickets`, `Comments`, `UserRoles`, byte-identical.
- **`01-schema.sql`** — gained one column: `"MustResetPassword" INTEGER NOT NULL DEFAULT 0 CHECK ("MustResetPassword" IN (0, 1))` on `Users`. This is now iteration 3's own schema, deliberately diverging from iterations 1/2's.
- **`Dockerfile`** — now `COPY`s `02-data-sanitized.sql`, never the raw file.
- **`.gitignore`** (new, scoped to `tools/phase1/dbmigrate/iteration3/`) — excludes `02-data.sql` (raw, real hashes, transient) and `_local/` (the throwaway control database). Only `02-data-sanitized.sql` is committed.
- **`verify.py`** — rewritten. It no longer opens any file under `tools/phase1/dbmigrate/iteration1/` or `tools/phase1/dbmigrate/iteration2/`. Instead it builds a second database — a "local control" copy — directly with the local `sqlite3` CLI (no Docker), from the same `01-schema.sql`/`02-data-sanitized.sql` used for the image, and cross-checks the Docker-built database against that. It also gained three sanitization checks.
- **`build.sh`** — runs `sanitize.py` automatically before `docker build` if the sanitized file is missing or `--recreate` was given.

## 4. The migration, step by step

```
./dbmigrate3.sh all --recreate
```

### Step 1 — Sanitize + Build
`sanitize.py` ran first (invoked by `build.sh`), redacting all 12 `Users` rows. `docker build` then loaded `01-schema.sql` (with the new column) and `02-data-sanitized.sql`, and confirmed `PRAGMA integrity_check` returned `ok` as a build-time gate. Resulting image: **19.5 MB**, tag `masterantique-sqlite:iteration3`. `docker run -d --name mar-sqlite-iter3` started the idle container.

### Step 2 — Verify (independent, two builds)
`verify.py` built a second, throwaway database with the plain `sqlite3` CLI (`tools/phase1/dbmigrate/iteration3/_local/masterantique.sqlite`, gitignored) from the identical two input files, then cross-checked it against the running Docker container:

- **Schema facts** (8 checks): table/column/PK/FK/index counts, the partial active-username index, auto-increment tables — introspected independently on both databases, compared to each other. All matched.
- **Integrity** (2 checks): `PRAGMA integrity_check` → `ok`; `PRAGMA foreign_key_check` → empty, on the Docker image.
- **10 business-summary queries** (users by type, tickets by state, audit events by action, etc.) — run on both databases, compared to each other. All matched.
- **16 table checks** (row count + canonical-dump content hash, for all 8 tables, ×2) — both databases agree on 155 rows total (Roles 3, Users 12, AuditLogs 78, Tickets 24, Comments 26, UserClaims 0, UserLogins 0, UserRoles 12) and identical per-table content hashes.
- **5 behaviour tests** — unchanged from the working draft, run on a scratch copy of the Docker image so the delivered database is never touched: duplicate active username rejected, soft-deleted username reusable, orphan FK insert rejected, boolean CHECK enforcement, identity sequence continuity. All 5 passed.
- **3 sanitization checks** (new): every `Users` row in both the local and Docker builds has `PasswordHash`/`SecurityStamp` NULL and `MustResetPassword = 1`; and all 12 rows' non-credential columns (`Name`, `CreatedAt`, `Discriminator`, `DeletedAt`, `Email`, and the rest) were cross-checked against the raw source and found unchanged. **A deliberate negative test during development** — manually re-introducing a fake hash into the local control build — was correctly caught and reported as a failed check, confirming this isn't a check that trivially passes.

**Result: 44 of 44 checks passed; 155 of 155 rows verified identical between the two independent builds.**

Directly confirmed on the built image:
```
docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite \
  "SELECT Id, Name, PasswordHash, SecurityStamp, MustResetPassword FROM Users LIMIT 3;"
1|manager|||1
2|employee1|||1
3|employee2|||1
```
No credential values anywhere in the delivered database.

### Step 3 — Self-test
Unchanged in shape from the working draft: (1) a second build produces an identical dump; (2) an independent scratch copy inside the container matches the delivered database; (3) a deliberately damaged copy is caught and named. **3 of 3 passed.**

## 5. Results (this run)

| Measure | Result |
|---|---|
| Checks passed | **44 of 44** (8 schema, 2 integrity, 5 behaviour, 3 sanitization, 10 business summaries, 16 table count/content) |
| Rows verified identical | **155 of 155**, between two independently-built databases |
| Differences found | **None** |
| Self-test | 3 of 3 passed |
| Image size | 19.5 MB |
| Database fingerprint (this build) | `5a6bc47fc11cf20a9a07a40ca9eadae75dc122efe0f07fee8ed500d9a10ec81a` — intentionally *different* from iteration 2's `436c7b68...`, because the data itself is now different (credentials redacted, one column added). This is expected, not a discrepancy. |
| Credential exposure in the delivered artifact | **None** — verified directly by query, not just by inspecting the SQL text |
| Exit code | 0 |

## 6. What this iteration can and cannot prove

- **Can prove:** the built image is internally sound, matches an independently-built control database in every schema fact, business answer, and row of data, behaves correctly under the same rule tests as iterations 1/2, and contains no live credential material.
- **Cannot prove:** that the *original* export (the schema/data lineage this iteration's input ultimately came from) still matches a live SQL Server source today — this iteration has no SQL Server connection at all, and deliberately does not lean on iteration 1/2's stored verification as a substitute for that. That boundary was already drawn by `SQLiteDatabaseGuide2.docx` §9.6; iteration 3 sits inside it more strictly than the first draft did.

## 7. On the earlier exposure

Commit `7a4257b` removed a `.gitignore` protection and committed the raw, real-hash `02-data.sql`/`masterantique.sqlite` for iterations 1/2, and that commit was pushed to a public branch before this was noticed. The accounts involved are synthetic — this exercise's whole purpose is practicing a real migration pattern before applying it to a real project — so this was not a real-world incident. The repository's history for the affected branch was cleaned up regardless (`git filter-repo`, then a force-push), so the mistake doesn't remain visible in the project's history, and iteration 3's own pipeline is the concrete fix going forward: `02-data.sql` is gitignored again, and the only data file this iteration ever bakes into an image or commits to git (`02-data-sanitized.sql`) contains no real credential material at all.

## 8. Known differences and limitations

- No `sqldiff` binary is available on this Linux host; canonically-ordered, hashed `.dump` comparison substitutes for it, between the two independently-built databases.
- The built image has no update path: changing the data means rebuilding the image, not patching a running container — the direct trade-off for portability.
- All other known differences carried over from iterations 1/2 (SQLite has no date type, case-sensitive text comparison, `VARCHAR` lengths unenforced) still apply unchanged.

## 9. How to repeat it

From `tools/phase1/dbmigrate/iteration3/` on a Linux host with Docker (and, if `02-data.sql` isn't already present, a copy of it from `tools/phase1/dbmigrate/iteration2/02-data.sql` first — it's gitignored and transient):

```
./dbmigrate3.sh all --recreate
```

Expect `VERIFICATION PASSED - 44 of 44 checks passed; 155 of 155 rows verified identical (local build vs. docker image)`, then `SELF-TEST PASSED - 3 of 3 passed`, exit code 0.

## 10. Conclusion

Iteration 3 meets the original goal (a Docker image built from the exported schema and data, ready to use the moment the container starts) and two additional bars raised during its own review: verification runs entirely on this Linux server without consulting any other iteration's output, and the delivered artifact carries no usable credential material, by deliberate design suited to a one-time bootstrap where a forced password reset is an acceptable trade-off. Every check that could be run without a live source passed (44 of 44), the tooling's own self-test passed (3 of 3), and a negative test during development confirmed the new sanitization check actually catches a real violation rather than trivially passing.

## 11. Regression after the move to `phase1/` (2026-09-23)

The iteration's folders moved from `docs/dbmigrate/iteration3/` and `tools/dbmigrate/iteration3/` to `docs/phase1/dbmigrate/iteration3/` and `tools/phase1/dbmigrate/iteration3/`. `report.py` and `verify.py` find the repository root by counting folders up from their own location, so each gained one level. The whole iteration was then re-run from the new location:

- `./dbmigrate3.sh all --recreate` (image and container rebuilt, data re-sanitized from the local `02-data.sql`): exit 0, **VERIFICATION PASSED - 44 of 44 checks; 155 of 155 rows identical**, **SELF-TEST PASSED - 3 of 3**.
- `02-data-sanitized.sql` and `selftest-results.json`: byte-identical to the committed versions. `verification-results.json`: identical except the recorded `GitCommit`.
- `python3 report.py` (Anaconda Python; it needs `matplotlib`, which the system Python lacks) wrote `MigrationVerificationReport3.docx` into the new folder. Compared with the previous version, only the tool path, the recorded commit and the document's creation date differ; the text and all charts are unchanged.
