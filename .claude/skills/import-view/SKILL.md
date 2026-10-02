---
name: import-view
description: Builds the Phase 2 Angular 21 view (Linux only) from the approved docs/phase2/view/VIEW.md and STYLE.md - scaffolds view/angular/ in master-antique-repair-claude with Bootstrap 5.3, Bootstrap Icons and ng-bootstrap, wires every page to the controller's REST API by action number, adds the component tests, runs build, tests and a smoke test, and writes the import report. Requires the controller API running at 127.0.0.1:8080/v3/api-docs (start it with /controller-oracle). Use when the user types /import-view or says "Run import-view".
---

# /import-view

**Prerequisite: the controller API must be running at `http://127.0.0.1:8080/v3/api-docs`** (started by
`/controller-oracle`). Without it this skill cannot find the endpoints or smoke-test the pages, and gate 3 stops the
run.

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `Linux` means continue. Anything else (`MINGW*`, `MSYS*`, `CYGWIN*` = Windows,
`Darwin` = macOS) means stop: say "import-view runs only on Linux; this machine reports `<output>`" and run nothing.

## Paths

| Name | Path |
|---|---|
| `$MOD` (this repo) | `~/dev/claude_work/claude_modernization` |
| `$APP` (Phase 2 repo) | `~/dev/claude_work/master-antique-repair-claude` |
| Contract | `$MOD/docs/phase2/view/VIEW.md` |
| Style | `$MOD/docs/phase2/view/STYLE.md` |
| Decisions | `$MOD/docs/phase2/view/EXPORT_VIEW_DECISIONS.md` |
| Controller contract | `$MOD/docs/phase2/controller/CONTROLLER.md` |
| API code | `$APP/model/oracle/` (its `CLAUDE.md` says how to build, test and run it) |
| **Output: Angular project** | `$APP/view/angular/` |
| **Output: report** | `$MOD/docs/phase2/view/IMPORT_VIEW_REPORT.md` |

## Gates - stop at the first that fails, and say which and why

1. **View contract approved.** `VIEW.md` contains the line `Status: approved`. Otherwise stop: "import-view needs an
   approved VIEW.md (it reports `<the status line>`)". Never edit the status.
2. **Model and controller built and tested.** Build and run the unit tests of `$APP/model/oracle/` exactly as its
   `CLAUDE.md` says (the controller-oracle run's build-and-test step). Any failure, or no controller code, stops the
   run: building the API is the `controller` agent's job, running it is `/controller-oracle`'s.
3. **API running and complete.** `curl -sf 127.0.0.1:8080/v3/api-docs` answers (if not, stop and tell the user to run
   `/controller-oracle`, which leaves the API and its database copy up). Every operation summary starts with
   "Action N:". Build a table action number -> method and path. Every action VIEW.md cites must be in it, **except
   the security-component actions 1 to 5** (see Security stand-in). A missing action stops the run; report which.
4. **Tools.** `node --version` and `npm --version` meet Angular 21's requirement (`npx @angular/cli@21 version` tells
   you); `$APP` exists and is a git repository. Otherwise stop and say what is missing.

## Read before writing anything

Read `VIEW.md`, `STYLE.md` and `EXPORT_VIEW_DECISIONS.md` in full, and `CONTROLLER.md` for the server messages and
rules. They are self-contained: build from them, not from the legacy application. If the legacy repo
(`~/dev/claude_work/master-antique-repair/`) is present you may read it, read-only, only to resolve something VIEW.md
marks as unclear; record each such lookup in the report.

**Precedence**: VIEW.md wins over STYLE.md for structure and text; STYLE.md wins for classes and look; the live
`/v3/api-docs` wins for URLs, request and response shapes. Where they disagree with each other or with the
decisions report, follow that order and report the difference.

## Security stand-in (until `docs/phase2/security/` exists)

The API has no authentication yet: every request names the acting user in the `X-Acting-User-Id` header, the server
looks up that user's role and answers 403 to a wrong role (controller-oracle plan, decision 4). The view therefore:

- Builds all security screens as VIEW.md lays them out (sign up, forgot password, log in, reset password, first-login
  password change, log off) with their client-side validation, but their submit calls a single `AuthService` whose
  server calls are **stubbed**: they show "Not available until the security component is built." and change nothing.
- Adds a **development sign-in stand-in**, only in the development build (an environment flag, absent from the
  production build): on the Log in page, below the real form and visibly marked "Development only", a user id input
  and an "Act as this user" button. It asks the API who that user is (an existing lookup action the API offers to the
  acting user, or the user lists of actions 15 and 19 called as that user), keeps the id, username and role in memory
  only (no localStorage, no cookie), and an HTTP interceptor adds `X-Acting-User-Id` to every API request. Log off
  clears it.
- Keeps the role checks in the route guards and the menu, fed from that in-memory user, knowing that they only
  shape the UI; the server's 403 is the real check.
- Puts every stand-in piece behind the `AuthService` and the interceptor, so the security component replaces those two
  and nothing else. List them in the report under "To replace when security exists".

If the API's stand-in differs from this (for example it already has authentication), follow the API and report it.

## Build

Work in `$APP/view/angular/`. If it already exists, this is a rebuild: update it in place to match the current
VIEW.md and STYLE.md, keep anything that still matches, and list what you changed; never delete work you cannot
attribute to an earlier run without asking.

1. **Scaffold** with the Angular 21 CLI defaults (standalone components, routing, strict TypeScript, the CLI's default
   test runner), project name `mar-view`, styles in SCSS. No server-side rendering.
2. **Dependencies from npm**, pinned: `bootstrap@5.3`, `bootstrap-icons`, `@ng-bootstrap/ng-bootstrap` (the release
   whose peer dependency matches Angular 21; if none does, stop and report), `chart.js@4`. No jQuery, no Bootstrap
   JavaScript bundle, nothing from a CDN, no other UI library.
3. **Dev proxy**: `proxy.conf.json` sends `/api` to `http://127.0.0.1:8080`, so the browser talks to one origin and the
   API needs no CORS change.
4. **Structure**:
   - `core/`: `AuthService` (stand-in), the API interceptor (header, 401 and 403 handling per VIEW.md "Access to
     protected routes"), the role guard, the return-URL check (internal routes only), the page-title strategy
     ("{Page title} - Master Antique Repair").
   - `api/`: one typed client per controller area, every method named after and commented with its action number
     ("action 11"), shapes taken from `/v3/api-docs`. Components never call `HttpClient` directly.
   - `shared/`: status badge, comment list with popover, confirmation modal, form-error display, visually hidden
     table caption.
   - `pages/`: one folder per VIEW.md page and Phase 2 addition, named after its route.
   - `layout/`: the shell (skip link, navbar, `main`, footer) from STYLE.md "Layout shell".
5. **Routes** exactly as VIEW.md: paths, query parameter names, page titles, role per route, landing routes, the
   wildcard not-found route and `/not-authorised`.
6. **Pages**: implement each VIEW.md page section in full - layout in order, exact text in quotes (including trailing
   full stops), lists with their ordering, paging and filters, date and number formats (`DatePipe` `short`, en-US;
   `0.0`, `0.00`, `MMM d`), every accessibility fix listed for it, and every control calling only the action VIEW.md
   names for it. A control that needs an action VIEW.md does not give it is not invented: leave it out and report it.
7. **Styling**: apply STYLE.md - the class mapping, the ng-bootstrap components per "Interactive components", Bootstrap
   Icons with `aria-hidden="true"`, the status badge colours, the chart palette, the kept and adapted `Site.css` rules
   in `styles.scss`, the two `.metrics-*` classes. No inline `style` attributes.
8. **Rules** (VIEW.md "Rules for the Angular build", all of them), in particular: interpolation only - no
   `innerHTML`, `outerHTML`, `bypassSecurityTrust*` or HTML built from strings; no logic in components beyond
   presentation (data and rules live in services); client-side validation mirrors the server and shows the server's
   message when it rejects.

## Tests

The brief requires a unit test suite for the Angular components. Write at least:

- per page: it renders its heading and title, shows the role-dependent parts only to that role (where it has any),
  and calls the right API client method (by action number) for each control, with the client mocked;
- per form: each client-side message appears, word for word, when its rule fails, and the server's message is shown on
  rejection;
- `core/`: the interceptor adds the header and handles 401 and 403; the guard redirects as VIEW.md says; the return-URL
  check rejects `//`, `/\` and absolute URLs;
- shared: the status badge maps each state to its class; the comment popover truncates at 60 (80 on Search) characters.

Name each test after the page or action it covers ("action 11: Assign to Me ...").

## Verify - stop at the first failure and report it

1. `npm ci` (or `npm install` on the first run) succeeds.
2. `ng build` (production) succeeds with no errors; report warnings. Check the production bundle contains no
   development sign-in stand-in.
3. `ng test` (headless, single run): 0 failures; report the count.
4. Security checks on the source: `grep` finds no `innerHTML`, `bypassSecurityTrust`, `http://` or `https://` script
   or style URLs, and no `localStorage`/`sessionStorage` use for the user.
5. **Smoke test** against the running API: start `ng serve` with the proxy in the background, then for one active
   Manager, Employee and Customer (look the ids up through the API): act as them with the stand-in and request each of
   their routes; each loads and its first API call returns 200. A Customer opening a Manager route gets the
   not-authorised page; an unknown route gets not-found. Use only read actions in the smoke test - never take,
   complete, comment, add, edit or delete. Stop the dev server afterwards.

## Write

- `$APP/view/angular/README.md` (for people): what the view is, how to run it (API first, then `npm start`), the
  stand-in and its limits, the test command and the latest results. Current state only, no history.
- `$APP/view/angular/CLAUDE.md` (for Claude Code): the rules above that apply to future work in that folder, the
  action-number-to-client map, and the stand-in pieces to replace.
- `$MOD/docs/phase2/view/IMPORT_VIEW_REPORT.md`, rewritten each run:
  1. Date, VIEW.md and CONTROLLER.md status lines, the Angular, ng-bootstrap, Bootstrap, Bootstrap Icons and Chart.js
     versions installed.
  2. Gate results.
  3. Pages and routes built, per role; the action -> endpoint table actually used.
  4. Test results (counts, failures quoted) and smoke-test results.
  5. **Decisions made on this run** (decision, where, reason) - make the choice rather than stopping to ask, and
     record it here.
  6. Differences found between VIEW.md, STYLE.md, the decisions report and the live API.
  7. Parity gaps (anything VIEW.md asks for that was not built, and why).
  8. To replace when security exists.

## Finish

- Report the gates, the counts (pages, routes per role, tests, smoke checks), the decisions made and the differences
  found, and point to the report.
- Tell the user to review `git diff` in both repos and commit; the decisions belong in `EXPORT_VIEW_DECISIONS.md` §11
  on the Windows side if they change the contract.
- Never edit VIEW.md, STYLE.md, CONTROLLER.md or their status lines; never change the API code (report what it lacks
  instead); never write to the `mar-oracle` container; no git command that changes anything; ignore `STATUS.md`.
