# Phase 2 view layer

The view layer is the Angular 21 single-page application of the modernized Master Antique Repair application. It
reproduces the Phase 1 Web Forms pages on Bootstrap 5.3, calling only the actions of the approved controller contract.

| File | What it is |
|---|---|
| [VIEW.md](VIEW.md) | **The view contract**: routes, role access, navigation, every page's layout, exact text, the controller action behind each control, accessibility fixes, security notes. Has a `Status:` line; Linux builds only from `approved`. |
| [STYLE.md](STYLE.md) | **The style hand-off**: Bootstrap 3.3.7 to 5.3 class mapping, interactive components, icons, badges, chart colours, the legacy `Site.css` and what happens to each rule. No status; it rides on VIEW.md's approval. |
| [EXPORT_VIEW_DECISIONS.md](EXPORT_VIEW_DECISIONS.md) | Every decision behind the two files and the import, with its reason (§11 is the full table), and the risks. |
| `IMPORT_VIEW_REPORT.md` | Written by `/import-view` on Linux: versions, gate results, tests, smoke test, decisions made on that run, parity gaps. |

## Prerequisite: the API must be running

**`/import-view` needs the controller API running on the Linux machine at `http://127.0.0.1:8080/v3/api-docs`.** It
reads that page to find the endpoint behind every action, and smoke-tests the built pages against the live API. If
`curl -sf 127.0.0.1:8080/v3/api-docs` does not answer, the run stops before writing anything. Start the API with
`/controller-oracle`, which leaves it and its database copy `mar-oracle-controller` running.

## How it is produced

Two skills, one per machine:

- **`/export-view`** (Windows) reads the legacy application and writes `VIEW.md` (`Status: proposed`) and `STYLE.md`.
  It refuses to run unless `docs/phase2/controller/CONTROLLER.md` is approved.
- **`/import-view`** (Linux) builds the Angular project in `view/angular/` of `master-antique-repair-claude` from
  them. It refuses to run unless `VIEW.md` is approved, the model and controller build and pass their tests, and the
  API is running.

**Only `/export-view` reads the legacy application.** `/import-view` builds from `VIEW.md`, `STYLE.md`, the decisions
report, `CONTROLLER.md` and the running API alone, and never reads `master-antique-repair`, even though a copy exists
on the Linux machine. That is the point of the hand-off: the two files must be enough. When something in them is
unclear, the Linux run makes a recorded decision and reports what `VIEW.md` should say, and the fix is made by
re-running `/export-view` on Windows.

## Run order

On Windows:

1. Run `/export-view`.
2. Review the diff of `docs/phase2/view/`.
3. In `VIEW.md`, change `Status: proposed` to `Status: approved` yourself.
4. Commit and push this repo (`docs/phase2/view/`, `.claude/skills/export-view/`, `.claude/skills/import-view/`,
   `CLAUDE.md`).

On Linux:

5. Pull this repo into `~/dev/claude_work/claude_modernization`.
6. Check the API is up: `curl -sf 127.0.0.1:8080/v3/api-docs`. If nothing answers, run `/controller-oracle`.
7. Run `/import-view`.
8. Review the diff in both repos (`view/angular/` in `master-antique-repair-claude`, `IMPORT_VIEW_REPORT.md` here) and
   commit both.

If `CONTROLLER.md` changes later, re-run `/export-view` (its action numbers may have moved), approve again, and re-run
`/import-view`.

## Security

Until the security component (`docs/phase2/security/`) exists, the API identifies the user by an `X-Acting-User-Id`
header. The Angular build therefore has its sign-up, login and password screens with their server calls stubbed,
and a development-only sign-in stand-in that is held in memory and left out of the production build. Route guards
only shape the UI; the API makes every access decision.
