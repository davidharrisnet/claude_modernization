# Plan (for Claude Code on Windows): convert iterations 1–4 to README.md + CLAUDE.md

**Status: to do, on the Windows machine.** Written on Linux on 2026-09-23. This is a one-off task plan for Claude Code:
the user opens this repository on Windows and types *"Follow docs/phase1/dbmigrate/DOCS_CONVERSION_PLAN.md"*. When
every step is done, delete this file (last step). The pattern itself is already settled with the user; do not
reopen it.

## 1. The pattern (settled)

Each iteration has exactly two documents, for two different readers:

| File | Reader | Contents |
|---|---|---|
| `docs/phase1/dbmigrate/iterationN/README.md` (replaces `ITERATIONN.md`) | People opening the folder | High-level, present-tense description: what the iteration does, where it runs, what it produces, its latest results (dated), how to run it (with Claude Code and by hand), its limits, related documents. **No history** of how it came about. |
| `tools/phase1/dbmigrate/iterationN/CLAUDE.md` (replaces `ITERATIONN_PLAN.md`) | Claude Code, loaded automatically in that folder | The local instructions for repeating and maintaining the iteration: rules never to break, how to run it, settings, layout, how the tool works step by step, input/output contracts, gotchas with a one-line reason, how to test a change, known limits. **No history** either. |

The Word reports (`MigrationVerificationReportN.docx`, `SQLiteDatabaseGuideN.docx`, `MigrationExportReport4.docx`)
stay in the docs folder unchanged: they are generated outputs.

**The finished example is iteration 5. Read both files before writing anything and copy their shape, section names
and tone:** `docs/phase1/dbmigrate/iteration5/README.md` and `tools/phase1/dbmigrate/iteration5/CLAUDE.md`.

### What "no history" means

Remove, from both files: "a first draft did X", "review found Y", "later addition", "what changed mid-iteration",
"differences from the plan / as executed / built:", "problems met and how they were resolved" told as a story,
"regression after the move", status lines ("Status: EXECUTED ..."), step narratives ("the work was done in six
steps"), and lists of documents updated. Git keeps all of it.

Keep, as **one-line reasons** inside the rule or step they explain: anything that stops a repeat of a real mistake
(for example "credentials are sanitized in memory before anything is written, because a raw export was once
committed — see DATA_MIGRATION.md §5.1"). Facts about the current design stay; the story of how they were reached goes.

### README sections (same order as iteration 5)

1. Title + one paragraph: what the iteration does, in plain words.
2. **What it does**: numbered steps, plain language.
3. **Where it runs**: machine, prerequisites, why (for example "needs the live SQL Server LocalDB, so Windows only").
4. **What it produces**: table of outputs with links.
5. **Latest results**: date, command, headline numbers, a short table by area. Use the numbers from the run in
   step 3 of this plan (Windows) or from the latest recorded run, and say which.
6. **Run it**: "With Claude Code: open this repository and type `Repeat iteration N.`" and "By hand:" the command
   (backslash form for the Windows `.cmd` tools).
7. **Limits and known differences**: plain language.
8. **Related documents**: `tools/phase1/dbmigrate/iterationN/CLAUDE.md` (for Claude Code), neighbouring iterations,
   `../DATA_MIGRATION.md`.

### CLAUDE.md sections (same order as iteration 5)

Intro (what the folder is; where the README and DATA_MIGRATION.md are) · **Rules** (numbered) · **Run** (command,
expected output, exit codes) · **Settings** (`migration\migration.config.json` for 1, 2, 4) · **Layout** (files, plus
the repo-root depth note below) · **How the tool works** (one subsection per command: export / import / verify /
selftest / report / guide / build / all, as applicable) · **Contracts** (what it reads and writes, formats, hashes) ·
**Gotchas** (each with a one-line why) · **Testing changes** · **Known limits**.

Repo-root depth (put in every CLAUDE.md "Layout"): scripts find the repository root by counting folders up from
their own location. Iterations 1, 2, 4: `migration\Common.ps1` uses `'..\..\..\..\..'` (five levels) since the move
to `phase1\`. Iteration 3: `report.py` and `verify.py` use `HERE.parent.parent.parent.parent`.

## 2. Per-iteration notes

Sources for each: the old `ITERATIONN.md` and `ITERATIONN_PLAN.md` (read fully), the tool folder, its
`verification-results.json` / `selftest-results.json`, and `DATA_MIGRATION.md` §3 (roadmap row).

**Iteration 1 — SQL Server → SQLite, native, Windows.** Tool: `tools\phase1\dbmigrate\iteration1\dbmigrate.cmd
<export|import|verify|selftest|report|guide|all> --target sqlite|mysql` (PowerShell under `migration\`, dialects in
`migration\dialects\`: `sqlite.ps1`, `mysql.ps1`; the MySQL target runs in Docker Desktop and is the "MySQL extra" —
describe it in the README as an additional target, not a separate iteration). Latest recorded result (re-run with
credential sanitization, 2026-09-22): **42 of 42 checks, 155 of 155 rows, self-test 6 of 6**. Credential
sanitization happens in memory at export (sanitize-first); fold the still-useful facts from
`docs/phase1/dbmigrate/SANITIZE_FIRST_REFACTOR.md` (what is sanitized, where in the code, how it is verified) into
this CLAUDE.md. Outputs in the tool folder include a sanitized `masterantique.sqlite` (checked: no password hashes)
and `import-log.txt` (a historical log; leave it).

**Iteration 2 — SQL Server → SQLite in a Linux Docker container, driven from Windows.** Tool:
`tools\phase1\dbmigrate\iteration2\dbmigrate.cmd ... --target sqlite-linux` (also `sqlite`, `mysql`). Needs SQL
Server LocalDB, PowerShell and Docker Desktop. Latest recorded result (2026-09-22): **42 of 42 checks, 155 of 155
rows, self-test 6 of 6**, same totals as iteration 1. Same sanitize-first facts as iteration 1 (fold into this
CLAUDE.md too). The README says what it adds over iteration 1 in one sentence, as a fact about the design ("the
target runs in a Linux container"), not as a story.

**Iteration 3 — SQLite baked into a Docker image, entirely on Linux.** (Its tool runs only on Linux; converting its
documents is text work and can be done on Windows.) Tool: `tools/phase1/dbmigrate/iteration3/dbmigrate3.sh
<build|verify|selftest|all> [--recreate]`; `report.py` builds the Word report (needs `matplotlib`; on the Linux
machine that is the Anaconda `python3`). Input: `01-schema.sql` and the raw `02-data.sql` copied from iteration 2
(gitignored, transient; `sanitize.py` writes `02-data-sanitized.sql`, which is what gets baked in and committed).
Verification builds an independent control database with the plain `sqlite3` CLI and cross-checks it against the
image (the rule in DATA_MIGRATION.md §5.3: never trust a stored answer from another run). Latest result (regression
on Linux, 2026-09-24): **44 of 44 checks, 155 of 155 rows, self-test 3 of 3**; `02-data-sanitized.sql` and
`selftest-results.json` byte-identical to the previous run. Keep the credential-exposure lesson as one "why" line
pointing to DATA_MIGRATION.md §5.1, not as the section "On the earlier exposure". `tools/.../iteration3/guide.md` is
the human database guide for this iteration: keep it; link it from the README.

**Iteration 4 — SQL Server → sanitized PostgreSQL files, export only, Windows.** Tool:
`tools\phase1\dbmigrate\iteration4\dbmigrate4.cmd <export|selftest|report|all> --target postgres` (PostgreSQL dialect
`migration\dialects\postgres.ps1`, metadata `migration\Metadata.ps1`, Word report `migration\ExportReport.ps1`).
Writes `01-schema.sql`, `02-data-sanitized.sql`, `source-metadata.json`, `selftest-results.json` and
`docs\...\MigrationExportReport4.docx`; refuses to run with `sanitizeCredentials` false (exit 2). Latest recorded
result (2026-09-23): **self-test 9 of 9**, 155 rows in 8 tables. Keep in CLAUDE.md: the rename map rules and "fail on
an unmapped name", the type mapping, the canonical row form and hash (it must match iteration 5's `verify.sql`
byte for byte), the metadata format, and the **hand-off rule**: after a successful export, copy the three files
unchanged into `tools\phase1\dbmigrate\iteration5\input\` and commit both folders together. Decision numbers
(1–4, 2b, 8, 11, 12, 14) are shared with iteration 5 and listed in DATA_MIGRATION.md §8.8 — refer there instead of
repeating the decision log. The `nextval` lesson now lives in iteration 5's CLAUDE.md; drop it from iteration 4.

## 3. Steps

1. **Read** this plan, iteration 5's README.md and CLAUDE.md, and `docs/phase1/dbmigrate/DATA_MIGRATION.md` §3, §5, §8.
2. **Pull** the latest commit (the `phase1\` move and iteration 5's conversion must be present).
3. **Regression-test iterations 1, 2 and 4 on Windows first.** The move to `phase1\` changed their repo-root depth
   (`Common.ps1`) and the paths in `migration\migration.config.json` (`outputDir: tools/phase1/dbmigrate`,
   `reportDir: docs/phase1/dbmigrate/iterationN`); these edits were made on Linux and have **never been run**. From a
   plain command prompt in the repository root:
   ```
   tools\phase1\dbmigrate\iteration1\dbmigrate.cmd all --target sqlite
   tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target sqlite-linux
   tools\phase1\dbmigrate\iteration4\dbmigrate4.cmd all --target postgres
   ```
   Expect the totals above (42/42 and 6/6; 42/42 and 6/6; 9/9). Outputs must land in the new folders
   (`tools\phase1\dbmigrate\iterationN\`, `docs\phase1\dbmigrate\iterationN\`); nothing may appear under old
   `tools\dbmigrate\` or `docs\dbmigrate\` paths. If iteration 4's `01-schema.sql` or `02-data-sanitized.sql` changed,
   stop and tell the user (iteration 5's input would need refreshing). Fix any path problem in the tool, re-run, and
   use these runs' numbers and dates in the READMEs.
4. **For each of iterations 1, 2, 3, 4:** write `docs\phase1\dbmigrate\iterationN\README.md` and
   `tools\phase1\dbmigrate\iterationN\CLAUDE.md` (sections in §1, facts in §2); then delete `ITERATIONN.md` and
   `ITERATIONN_PLAN.md`.
5. **Fold and delete `docs\phase1\dbmigrate\SANITIZE_FIRST_REFACTOR.md`** (its useful facts are now in iterations 1
   and 2's CLAUDE.md; it is a finished plan and still says "planned, not implemented", which is wrong).
6. **Remove the committed LibreOffice lock file** `docs\phase1\dbmigrate\iteration3\.~lock.MigrationVerificationReport3.docx#`
   and add `.~lock.*#` to the root `.gitignore`.
7. **Repoint every reference.** Find them:
   ```powershell
   Get-ChildItem -Recurse -File -Include *.md,*.html,*.ps1,*.cmd,*.sh,*.py,*.json,*.sql |
     Where-Object { $_.FullName -notmatch '\\(\.git|input)\\' } |
     Select-String -Pattern 'ITERATION[1-4](_PLAN)?\.md|SANITIZE_FIRST_REFACTOR'
   ```
   Replace `…/iterationN/ITERATIONN.md` with `…/iterationN/README.md` and `…/iterationN/ITERATIONN_PLAN.md` with
   `tools/phase1/dbmigrate/iterationN/CLAUDE.md`. Places known to have them: root `CLAUDE.md` (iteration bullets and
   the "Layout by phase" paragraph), `docs\phase1\dbmigrate\DATA_MIGRATION.md` (§3 roadmap, §6, §8, §9 document map —
   change its columns to *Description (README) | Instructions for Claude (CLAUDE.md) | Reports*), the iteration READMEs
   (neighbour links), `tools\phase1\dbmigrate\iteration4\README.md`, and strings inside the PowerShell report
   generators (`Report.ps1`, `Guide.ps1`, `ExportReport.ps1`). Changing a generator's text changes its next report;
   that is fine.
8. **Update the root `CLAUDE.md`:** in the "Layout by phase" paragraph, change "iterations 1–4 being converted" to
   state that all five iterations follow the pattern, and remove the sentence about this plan.
9. **Check:** the command in step 7 finds nothing; every relative link in the changed Markdown files resolves (for
   each `](path)` in a file, `Test-Path (Join-Path $file.DirectoryName $path)`); `git status` shows only the intended
   files. Do not commit: the user commits.
10. **Delete this file** (`DOCS_CONVERSION_PLAN.md`).

## 4. Rules while doing this

- Never commit, push, or run other git write commands; the user does. Read-only git (`status`, `diff`, `log`) is fine.
- Never write raw exported data (`02-data.sql`, an unsanitized `.sqlite`) anywhere it could be committed
  (DATA_MIGRATION.md §5).
- Keep line endings as they are (`.gitattributes` in the iteration folders pins `*.md`, `*.sql`, `*.json`, `*.ps1` to
  LF and `*.cmd` to CRLF where present).
- If a fact in the old documents contradicts the tool or the results files, the tool and results win; mention the
  contradiction to the user.
