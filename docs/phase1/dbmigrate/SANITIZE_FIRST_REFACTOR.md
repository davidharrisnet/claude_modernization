# Plan: sanitize-first refactor for iteration 1 and iteration 2

**Status: planned, not implemented.** Written on Linux, where iterations 1/2 cannot be run or tested (no PowerShell, no SQL Server LocalDB — see `CLAUDE.md`). This document is meant to be read and executed on the Windows machine. Everything below is design, not verified code.

## Why

`docs/phase1/dbmigrate/DATA_MIGRATION.md` §5.2 established the project-wide policy after iteration 3: for a one-time bootstrap migration, credentials should be invalidated as part of the migration itself (`PasswordHash`/`SecurityStamp` → `NULL`, `MustResetPassword` → `1`), and no raw credential data should ever be written somewhere it could be committed or transferred. Iterations 1 and 2 currently don't do this at all — they export, carry, and verify real password hashes end-to-end, which is exactly the gap that led to the `.gitignore` regression this project already had once (`docs/phase1/dbmigrate/DATA_MIGRATION.md` §5.1).

## The key design difference from iteration 3

Iteration 3's `sanitize.py` operates on an **already-written file** (`02-data.sql`) with a regex-based text transform, because iteration 3 has no live source to re-query. Iterations 1/2 are different: `Export.ps1`'s `Invoke-Export` builds the schema and data **in memory** (`Get-SourceModel` for schema, `Read-SourceRows` per table for data) and only then calls the dialect's `RenderSchema`/`RenderData` to produce the SQL text that gets written to disk.

This means iterations 1/2 can do something iteration 3 structurally cannot: **sanitize the in-memory data before it is ever serialized to disk**, so a raw, unsanitized `02-data.sql` never exists as a file at all — not even transiently. That's a stronger security property than iteration 3 achieved (iteration 3 has to trust that the raw file, however briefly, doesn't leak), and it's the right target for 1/2 specifically because their export is a live process, not a file copy.

## Design

### 1. A new sanitization step, called from inside `Invoke-Export` (`Export.ps1`)

Add a function — proposed name `Protect-SensitiveData($Model, $RowsByTable, $Settings)` — called in `Invoke-Export` right after `Read-SourceRows` populates `$rowsByTable`, and *before* `$dialect.RenderSchema`/`RenderData` are called:

```powershell
$model = Get-SourceModel $conn
$rowsByTable = @{}
foreach ($t in $model.Tables) { $rowsByTable[$t.Name] = Read-SourceRows $conn $t }
# NEW:
Protect-SensitiveData $model $rowsByTable $settings
$schema = & $dialect.RenderSchema $model $Config.source.database
$data = & $dialect.RenderData $model $rowsByTable
```

`Protect-SensitiveData` does two things, both in-memory, both before anything touches disk:

1. **Mutates `$Model`**: appends a synthetic column definition to the `Users` table's column list — `MustResetPassword`, integer, not null, default `0`, not a key, not identity. Because `RenderSchema` builds DDL purely from `$Model.Tables[...].Columns`, this one change makes the new column show up in the generated schema automatically, for *any* dialect (`sqlite.ps1`, `mysql.ps1`) — no per-dialect regex, no touching the dialect files at all.
2. **Mutates `$rowsByTable["Users"]`**: for every row, sets `PasswordHash` and `SecurityStamp` to `$null`, and appends the value `1` for the new `MustResetPassword` column (matching the column order just added to `$Model`). Because `RenderData` builds INSERT statements from `$Model`'s column list plus `$rowsByTable`'s row values, this is consistent by construction — there's no separate place that could disagree about column order.

This should be config-gated, not unconditional — add a target-level flag, e.g. `"sanitizeCredentials": true` in `migration.config.json`'s `sqlite`/`mysql` target blocks (default absent/false, so nothing changes for a target that doesn't opt in — though realistically every target should opt in given the policy). Minimal version: hardcode the table/columns (`Users.PasswordHash`, `Users.SecurityStamp`, add `MustResetPassword`) the same way iteration 3's `sanitize.py` does. Don't build the fully generalized "declared sensitive columns per table" config feature (`docs/phase1/dbmigrate/DATA_MIGRATION.md` §5.2.5) as part of this refactor — that's a separate, larger piece of work; note it as a follow-on, but keep this change's blast radius matched to what iteration 3 already proved out.

### 2. The problem this creates in `Verify.ps1` — and the fix

This is the part that's easy to miss: `Verify.ps1` compares the target's data back against a **fresh read of the live SQL Server source** for every column. Once `Protect-SensitiveData` nulls out `PasswordHash`/`SecurityStamp` in the exported/target data, the source side of that comparison still has the *real* hash — so every `Users` row will show up as a content mismatch on those two columns, and the existing pass/fail logic will (incorrectly, given the new policy) report `FAILED`.

`Verify.ps1` needs a carve-out for declared sensitive columns, mirroring what iteration 3's `check_credential_sanitization` does standalone:

- For `Users.PasswordHash` and `Users.SecurityStamp` specifically: don't compare source-vs-target equality. Instead assert the target value is `NULL` for every row, and assert `MustResetPassword = 1`. Report this as its own check category (e.g. `"Sanitization"`, matching iteration 3's `verification-results.json` shape) rather than folding it into the normal per-row content hash, so a report reader can see "credentials deliberately redacted" rather than "content mismatch."
- For every *other* column, the existing source-vs-target comparison is unchanged and should still catch a real regression.
- The per-table canonical-content hash (`SourceHash`/`TargetHash` in `verification-results.json`) is computed over *all* columns today, including credentials — once credentials differ by design, source and target hashes for `Users` will legitimately never match again. Either exclude `PasswordHash`/`SecurityStamp` from the canonical form used for that specific table's hash (cleanest — keeps the hash meaningful for detecting real content drift in the remaining columns), or accept that `Users`' hash-based check is retired in favor of the explicit per-column checks above (simpler, but loses a check). Recommend the former: it's a small change to the canonical-row-building step (`ConvertTo-Canonical`/`Read-SourceRows` call site in `Common.ps1`, or a table-specific column filter passed into the hashing function) and it keeps `Users` verifiable by hash for everything that should still match.

### 3. What this changes about iteration 1/2's own verification claim

Before this refactor, iteration 1/2's reports assert **100% byte-for-byte fidelity including credentials** — that was a deliberate, correct claim at the time (see `Report.ps1`'s §9 "Password hashes and security stamps were copied byte-for-byte"). After this refactor, the claim becomes **100% fidelity for every column except credentials, which are deliberately and verifiably invalidated** — a different, and now policy-correct, claim. `Report.ps1`'s §2 (scope and method) and §9 (exclusions) text needs updating to state this explicitly, the same way iteration 3's report does, rather than silently changing what "PASSED" means without saying so.

### 4. File-by-file change list

Apply identically to `tools/phase1/dbmigrate/iteration1/` and `tools/phase1/dbmigrate/iteration2/` — they're separate copies of the same tooling, so the same edits happen twice (or make the change once and re-sync the copies, whichever this project's convention prefers by the time this is implemented):

- `migration/Export.ps1` — add `Protect-SensitiveData`, call it in `Invoke-Export` as shown above.
- `migration/Common.ps1` — if the config flag (`sanitizeCredentials`) needs a shared helper to read, add it near `Get-TargetSettings`; otherwise `Protect-SensitiveData` can read `$Settings.sanitizeCredentials` directly.
- `migration/Verify.ps1` — the carve-out described in §2: skip source-vs-target equality for declared sensitive columns, add the explicit sanitization checks, adjust the `Users` table's canonical-hash column set.
- `migration/Report.ps1` — update the hardcoded narrative text (§2, §9) to describe sanitization instead of asserting full byte-for-byte fidelity, when the target has `sanitizeCredentials` enabled. Reuse `$m.KnownDifferences` (already a mechanism `Verify.ps1` populates and `Report.ps1` renders) to carry the "credentials sanitized, one-time bootstrap, reset required" note, same pattern iteration 3 used.
- `migration.config.json` (both iterations) — add `"sanitizeCredentials": true` to the `sqlite`/`sqlite-linux`/`mysql` target blocks.
- No dialect file changes needed (`sqlite.ps1`, `mysql.ps1`) — the point of mutating `$Model`/`$rowsByTable` before `RenderSchema`/`RenderData` is that dialects stay unaware of sanitization entirely.

### 5. Re-running and re-documenting

Once implemented and passing on Windows:
- `dbmigrate.cmd all --target sqlite --recreate` (iteration 1) and `dbmigrate.cmd all --target sqlite-linux --recreate` (iteration 2) — expect the same row counts as before (155 total), but the `Users` table's checks now show the new sanitization category instead of a plain content-hash pass, and the schema check count changes by one column.
- Update `ITERATION1.md`/`ITERATION2.md` with the real re-run results (this project's convention throughout: these files record what actually happened, with real numbers — don't write them before the run).
- `MigrationVerificationReport{1,2}.docx` and `SQLiteDatabaseGuide{1,2}.docx` regenerate via the existing `report`/`guide` commands — no manual doc editing needed for those, `Report.ps1`/`Guide.ps1` already read from `verification-results.json`.
- Update `docs/phase1/dbmigrate/DATA_MIGRATION.md` §3 (iteration roadmap table) and §6 ("what's not built yet") once this lands — remove the "moving `sanitize.py` to run at export time" bullet, since for 1/2 the equivalent (sanitize before serialization) will be done, and note that it's specifically *not* the same code as iteration 3's (different mechanism, same policy outcome).

## Open question to resolve on the Windows side, not answered here

Should `Protect-SensitiveData`'s table/column list be hardcoded (matches iteration 3's approach, lowest risk, fastest to implement) or should this refactor be the moment the config-driven sensitive-column declaration (`docs/phase1/dbmigrate/DATA_MIGRATION.md` §5.2.5) gets built for real? Recommend hardcoded first, generalize later — but that's a call worth making deliberately when picking this up, not defaulting into either direction.
