# Export of the view: decisions

This report records the decisions behind `/export-view`, the Windows skill that turns the legacy Web Forms pages into
the hand-off for the Phase 2 Angular view. Facts taken from the legacy application cite the file or class they come
from (paths are relative to `master-antique-repair/MasterAntiqueRepair/`). Items marked *to verify on first run* are
not yet confirmed and must be settled by the skill's first run, not assumed.

## 1. Purpose and scope

- `/export-view` runs on Windows only. It reads the legacy application and the approved
  `docs/phase2/controller/CONTROLLER.md`, and writes two files in `docs/phase2/view/`:
  - **`VIEW.md`**: the view contract (pages, routes, role access, navigation, controls and the controller actions
    behind them, exact text, accessibility fixes, what is not carried forward).
  - **`STYLE.md`**: the styling hand-off (Bootstrap 3.3.7 to 5.3 class mapping, the custom CSS, icons, colours).
- Both files are **self-contained**: anything the Angular build needs is written in them, not referenced. **The Linux
  side never reads the legacy application**, even though a copy exists on that machine
  (`~/dev/claude_work/master-antique-repair/`): the exercise shows that the hand-off files are enough. `/import-view`
  resolves an unclear point by a recorded decision and reports what VIEW.md should say, so the contract is corrected
  on Windows. Only `/export-view` reads the legacy code.
- The skill reads only. It never changes the legacy repository and runs no git command that changes anything.
- Decision: **one skill, two files.** Both files come from the same reading of the same pages (a page's markup gives
  its structure and its classes together), so one pass keeps them consistent. They are separate files because they
  are reviewed for different things and used at different times: VIEW.md is the contract revisited whenever the view
  changes; STYLE.md is a mostly mechanical translation used once when the Angular project is scaffolded. Keeping them
  apart keeps the VIEW.md diff free of class-mapping noise.

## 2. Prerequisites and order

The layers are built in order: model, then controller, then view. The view is meaningless without the actions it
calls, so the order is enforced on both machines, each checking what it can see:

| Where | Gate | Why there |
|---|---|---|
| Windows, `/export-view` | `CONTROLLER.md` says `Status: approved`; otherwise the skill stops and runs nothing. | VIEW.md cites controller action numbers; an unapproved contract can still be renumbered. |
| Linux, the view import | `model/oracle/` and the controller layer build and their tests pass; otherwise nothing is scaffolded. | Only the Phase 2 repository (Linux only, not present on Windows) shows whether the layers were actually built. |

Rejected: a single Windows gate reading a "controller done" note written from Linux. It trusts a note rather than a
build.

## 3. Output contract and approval

- **VIEW.md** starts as `Status: proposed`. Only the user sets `approved`, after reviewing the git diff. Linux builds
  only from an approved VIEW.md.
- **STYLE.md** has **no status line**. It is a mechanical translation that rides on VIEW.md's approval; its changes
  still appear in the same git diff before commit.
- Both files are tracked and rewritten from scratch on each run; `git diff` is the review.

## 4. VIEW.md structure

For every carried-forward page, in a fixed order (Account pages alphabetically, then the other pages alphabetically,
then the master page), as with CONTROLLER.md:

1. **Route** (Angular path, kebab-case) and the legacy page it replaces.
2. **Access**: the role(s) that may open it (from `RepairAuthHelper.RequireRole`), or anyone.
3. **Layout tree**: headings, panels and sections, forms and fields, tables and their columns, buttons, modals,
   collapsible sections, tabs, in markup order.
4. **Controls to actions**: every button, form or list cites the CONTROLLER.md action number it calls. A control with
   no action is an error to report; a CONTROLLER.md action that no control uses is listed at the end of the file.
5. **Exact text**: page title, labels, captions, placeholders, client-side validator messages and the server messages
   the page shows, word for word.
6. **Lists**: page size and choices, sort order, filters, empty-list text.
7. **Dates and numbers**: the legacy display format for each (see §8).
8. **Accessibility fixes** for that page (see §7).

Then: **Navigation** (menus per role, landing routes, log off), **Phase 2 additions**, **Not carried forward**, and
**Unused controller actions**.

## 5. Roles, routing and access control

### Legacy behaviour (from the source)

- **Menu** (`Site.master`): each item is hidden by default (`visible="false"`) and shown per role by
  `Context.User.IsInRole` in `Site.Master.cs`:

  | Menu item | Page | Role |
  |---|---|---|
  | My Repairs | `CustomerView` | Customer |
  | My Tickets | `EmployeeView` | Employee |
  | Administration | `ManagerView` | Manager |
  | Audit Log | `AuditLogView` | Manager |
  | Search | `TicketDetailView` | Manager |
  | Metrics | `Metrics` | Manager |

  `SubmitRepair` has no menu item; it is reached from the "Submit a new repair request" button on `CustomerView`.
- **Anonymous** menu: Sign up, Log in. **Signed in**: "Hello, {username}!" and Log off (`LoginStatus`, then to `~/`).
- **Brand link**: wrench icon and "Home" to `~/`.
- **Landing after login** (`Account/Login.aspx.cs`): a safe local `ReturnUrl` first (`IdentityHelper.IsLocalUrl`
  rejects `//` and `/\` prefixes, so no open redirect); otherwise Employee to `EmployeeView`, Manager to
  `ManagerView`, Customer to `CustomerView`, anything else to `~/`.
- **After sign-up**: to `CustomerView` (`Account/CustomerSignUp.aspx.cs`).
- **Unauthorised access** (`RepairAuthHelper.RequireRole`): redirect to `Account/Login`, both when not signed in and
  when signed in with the wrong role.
- **Home** (`Default.aspx`): anonymous visitors see Sign Up and Log In; signed-in users see one button to their view
  ("Go to My Repairs", "Go to My Tickets" or "Go to Administration", `Default.aspx.cs`).

### Phase 2 decisions

- Routes mirror the legacy pages one to one (Account pages under `account/`). Exact paths are written by the skill.
- **Route guards are presentation only.** An Angular guard decides what the UI shows and where it sends the user; it
  is never the access check. Every authorisation decision stays on the server, which already enforces it per
  CONTROLLER.md. A guard must never be the only protection of any data or action.
- **Return URL**: kept, and restricted to internal Angular routes (the equivalent of `IsLocalUrl`); an absolute or
  protocol-relative URL is ignored.
- **Wrong-role access**: the legacy app sends a signed-in user with the wrong role to the login page. Phase 2 shows a
  "not authorised" page instead, because sending an authenticated user to log in again is confusing and hides the
  reason. This is a deliberate, recorded parity change.
- **API responses**: 401 clears the client's signed-in state and goes to login with the current route as return URL;
  403 shows the "not authorised" page. Neither shows server error details.
- **Role source**: the client learns the user's role from the server after login, never from anything the user can
  edit. Roles come from `user_roles` (CONTROLLER.md, "Rules the legacy code enforces").

## 6. Security decisions

- **First-login password change (Phase 2 addition).** The migration sets every `password_hash` and `security_stamp`
  to NULL and `must_reset_password` to true, and the Phase 2 model's `LoginService` forces a password change on first
  login. No legacy page has this screen, so reading the `.aspx` files never finds it. VIEW.md records it under
  **Phase 2 additions**: a screen reached right after a login that requires a password change, no other route
  reachable until it is done, same password rules as CONTROLLER.md action 1.
- **Security component.** Sign-up, login, forgot and reset password (actions 1 to 5), the password fields of the
  manager's add and edit forms (16, 17, 20, 21) and log off belong to `docs/phase2/security/`. VIEW.md lays these
  screens out, but their rules come from the controller and security contracts, not from the view.
- **Reset link shown on screen.** `Account/ForgotPassword` shows the generated reset link on the page because no email
  is configured, with the notice that it expires in 1 hour and can be used once. It also says "No account found with
  that username." for an unknown name, which tells anyone which usernames exist. Both are carried forward for parity
  and **flagged as security risks** (account enumeration, reset link handed to whoever typed the username); fixing
  them is a security-component decision.
- **Unencoded output in the legacy pages.** These controls write their text without HTML encoding:
  - `asp:Literal` without `Mode="Encode"`: `Account/CustomerSignUp` ErrorMessage, `Account/ForgotPassword`
    ResultMessage, `Account/Login` FailureText, `Account/ResetPassword` ErrorMessage, `ManagerView`
    Add/Edit Employee/Customer ErrorMessage, `TicketDetailView` StateLiteral, CustomerLiteral, AssignedToLiteral,
    EmployeeCommentsAuthorLiteral, CustomerCommentsAuthorLiteral, CommentSearchErrorLiteral, and the `Metrics` value
    literals.
  - `asp:Label` also writes its text unencoded: `CustomerView` and `EmployeeView` CommentErrorLabel.
  - Most carry fixed server strings or numbers (exception messages from `AuthService`, `AccountService`,
    `CommentService` and the Identity validators, none of which echo user input), or HTML built in code-behind with
    the user-supplied part encoded (`TicketDetailView.BuildPersonLink` calls `HttpUtility.HtmlEncode` on the username;
    `StateLiteral` builds a label span from the enum).
  - **One exploitable case (stored XSS)**: `Metrics` BusiestEmployeeLiteral writes "{username} ({n} closed)" with the
    employee's username unencoded (`MetricsService` sets the label from the username). Usernames have no character
    restriction (`IdentityConfig.ActiveUsernameValidator` checks only required and unique), and managers set employee
    usernames, so a username containing HTML runs as script on the Metrics page of every manager. Found by the first
    `/export-view` run; Phase 2's interpolation-only rule removes it. Recorded as a Phase 1 defect, not a parity
    requirement.
  - `Metrics` injects JSON into a script block (`ChartDataLiteral`, `JsonConvert.SerializeObject(...)` with `</`
    escaped).
- **Phase 2 rule for output**: all text through Angular interpolation; no `innerHTML`, no `bypassSecurityTrust*`, no
  HTML built from strings. Status labels and person links become components or templates. Chart data arrives as JSON
  from the API and is passed to the chart as data, never as script.
- **Third-party script**: `Metrics.aspx` loads Chart.js 4.4.0 from `cdn.jsdelivr.net` without an integrity hash. Phase
  2 installs the chart library as an npm dependency, bundled and version-pinned, so no script is loaded from a CDN at
  run time.
- **CSRF and session.** The legacy app uses an OWIN cookie (`HttpOnly`, `Secure` same as the request,
  `App_Code/Startup.Auth.cs`) plus the Web Forms anti-XSRF token in `Site.Master.cs` (`ViewStateUserKey`). How the
  Angular client authenticates (cookie with an XSRF token, or a token in a header) and handles session expiry is a
  **security-component decision**; the view follows it. Recorded here as a dependency, not decided by the view.
- **Audit**: the view writes no audit rows. Audit rows are written by the server actions listed in CONTROLLER.md.
- **Client-side validation** repeats the server rules for usability only; the server's validation is authoritative
  and its messages are shown when it rejects input.
- **Autocomplete**: the legacy form has `autocomplete="off"` on the whole page and on both login fields; sign-up,
  forgot password, reset password and the manager forms use `username` and `new-password`. Phase 2 uses the standard `username`, `current-password` and `new-password` values so password managers work
  correctly; this is a deliberate change.

## 7. Bootstrap 3.3.7 to 5.3

Decision: this is a **migration, not a version bump**. Bootstrap 3 class names are translated on the Windows side and
written in STYLE.md as a table, so the Linux side does not guess. Bootstrap's own JavaScript is not used: interactive
components come from **ng-bootstrap**, so there is no jQuery and no DOM manipulation outside Angular.

### Classes that change (usage counts across all pages and `Site.master`)

| Bootstrap 3 | Count | Bootstrap 5.3 |
|---|---|---|
| `panel`, `panel-default` | 9, 9 | `card` |
| `panel-heading`, `panel-title` | 9, 2 | `card-header`, `card-title` |
| `panel-body` | 9 | `card-body` |
| `panel-collapse` | 2 | `collapse` (ng-bootstrap `ngbCollapse`) |
| `panel-title-toggle` (custom) | 2 | ng-bootstrap accordion (replaces the custom toggle and its chevron CSS) |
| `glyphicon`, `glyphicon-*` (wrench, inbox, ok, ok-circle, info-sign, chevron-down) | 9 | Bootstrap Icons `bi bi-*` (tools, inbox, check, check-circle, info-circle, chevron-down) |
| `form-group` | 45 | `mb-3` |
| `control-label` | 23 | `form-label`, or `col-form-label` in horizontal forms |
| `form-horizontal` | 9 | `row` per field with `col-*` label and input columns |
| `form-inline` | 5 | `row g-2 align-items-center` with `col-auto` |
| `help-block` | 2 | `form-text` |
| `col-md-offset-2`, `-3`, `-4` | 3, 2, 4 | `offset-md-2`, `-3`, `-4` |
| `btn-default` | 5 | `btn-secondary` (or `btn-outline-secondary` where it sits beside a primary button) |
| `btn-xs` | 1 | `btn-sm` (no extra-small size in Bootstrap 5) |
| `table-condensed` | 6 | `table-sm` |
| `dl-horizontal` | 3 | `dl` with `row`, `dt class="col-sm-3"`, `dd class="col-sm-9"` |
| `label`, `label-default` / `-warning` / `-info` / `-success` | 8 (7 markup, 1 code-behind) | `badge text-bg-secondary` / `-warning` / `-info` / `-success` |
| `jumbotron` | 1 | removed in 5: `p-5 mb-4 rounded-3` with the background utility |
| `bg-primary` on the jumbotron | 1 | `text-bg-primary` |
| `navbar-inverse` | 1 | `navbar-dark bg-dark` (`data-bs-theme="dark"`) |
| `navbar-fixed-top` | 1 | `fixed-top` |
| `navbar-header`, `navbar-toggle`, `icon-bar` | 1, 1, 3 | `navbar-toggler` with `navbar-toggler-icon` |
| `navbar-right` | 1 | `ms-auto` |
| `navbar-nav` items | 2 | `nav-item` and `nav-link` on each item |
| `nav-pills nav-stacked` (TicketDetailView tabs) | 1 | `nav nav-pills flex-column` (ng-bootstrap `ngbNav`) |
| `modal` with `data-toggle` | 3 | ng-bootstrap `NgbModal` |
| `collapse` with `data-toggle` | 3 | ng-bootstrap `ngbCollapse` |
| `popover-toggle` with `data-toggle="popover"` | 7 | ng-bootstrap `ngbPopover` on a `button` |
| `close` | 3 | `btn-close` with `aria-label="Close"` |
| `col-sm-*`, `col-md-*` | many | unchanged names; the breakpoints keep their widths |

### Classes that do not change

`btn`, `btn-primary`, `btn-success`, `btn-info`, `btn-danger`, `btn-link`, `btn-sm`, `btn-lg`, `table`, `row`,
`container`, `col-md-*`, `col-sm-*`, `text-danger`, `text-success`, `text-muted`, `text-primary`, `text-info`,
`text-center`, `lead`, `fade`, `form-control`, `nav`, `navbar`, `navbar-brand`, `navbar-collapse`, `navbar-text`,
`tab-content`, `modal-*` structure classes.

### Custom CSS (`Content/Site.css`, 97 lines)

Copied verbatim into STYLE.md, each rule marked:

| Rule | Decision |
|---|---|
| `body` padding-top 50px for the fixed navbar | **adapt**: Bootstrap 5's navbar height differs; keep the offset, value measured on the new navbar |
| sticky footer (`body`, `body > form`, `.body-content` flex column, `footer` `margin-top: auto`) | **adapt**: no `form` wrapper in Angular; apply to the app shell (`d-flex flex-column min-vh-100`) |
| `input, select, textarea { max-width: 280px }` | **keep** |
| `.jumbotron` margin at 768px and up | **adapt** to the jumbotron replacement |
| `.table-fixed { table-layout: fixed }` | **keep** (aligns columns across several tables) |
| `.popover-toggle { cursor: pointer }` | **obsolete**: the trigger becomes a `button` |
| `.panel-title-toggle` and the chevron rotation | **obsolete**: replaced by the ng-bootstrap accordion |

`bootstrap-theme.css` (the Bootstrap 3 gradient theme) is not carried forward. It ships with the project but is never
loaded (`Bundle.config` bundles only `bootstrap.css` and `Site.css`), so the legacy look is already Bootstrap's flat
default.

### Icons and colours

- Glyphicons are replaced by **Bootstrap Icons**, installed from npm, never loaded from a CDN. Every icon that carries
  meaning on its own gets an accessible label; decorative icons get `aria-hidden="true"`.
- Colours are Bootstrap's defaults in both versions (no custom palette in `Site.css`). The Bootstrap 5 defaults differ
  slightly in shade; this is accepted as a parity gap.

## 8. Accessibility (WCAG 2.1 AA)

Decision: **fix, do not copy.** VIEW.md lists each issue on the page where it occurs; the skill checks for:

- form labels not tied to their input (`AssociatedControlID` missing, or plain text used as a label);
- validator messages not announced: Phase 2 ties each message to its field with `aria-describedby`, sets
  `aria-invalid`, and puts page-level errors in an `aria-live` region;
- icon-only buttons and links without a text alternative;
- the comment popover trigger: a `span` with `role="button"` and `tabindex="0"` (keyboard reachable, but not a real
  button); Phase 2 uses a `button`;
- heading order (pages use `h2` for the title; `Default` uses `h1`, `h2` and `h4`), so each page has one `h1` and no
  skipped levels;
- data tables without header cells or captions;
- modals: focus moved in, trapped and returned on close (ng-bootstrap does this);
- colour contrast of the status badges and `text-muted` on the Bootstrap 5 palette;
- the page `<title>`: the legacy form `"{Page title} - Master Antique Repair"` is kept for every route;
- `lang="en"` on the document, as in `Site.master`.

## 9. Parity details

- **Exact text** is carried word for word, including the trailing full stop in page headings (`<h2><%: Title %>.</h2>`).
- **Lists**: `AuditLogView` pages with 10 rows by default and a "Rows per page" choice of 10 or 20 (CONTROLLER.md
  action 14); every other list and its ordering is taken from CONTROLLER.md and the page markup.
- **Comment truncation**: comments show the first 60 characters (80 in the text search results) with the full text in
  a popover (`UiHelpers.Truncate`).
- **Dates**: the legacy app formats dates on the server with the general short format `{0:g}` / `ToString("g")` in the
  server's culture (no `<globalization>` element in `Web.config`, so the machine culture, typically en-US
  `M/d/yyyy h:mm tt`), and `MMM d` for the Metrics day. Audit timestamps are server local time (`DateTime.Now`).
  Phase 2 formats dates in the browser with Angular's `DatePipe` using the equivalent `short` format and the en-US
  locale. How timestamps are stored and sent (local time versus UTC with an offset) is decided by the controller; the
  view shows the time the API gives it and states the time zone where it matters (the audit log).
- **Status labels**: SUBMITTED warning, INPROGRESS info, COMPLETED success (`UiHelpers.StatusLabelClass`), kept as
  badge colours.

## 10. Not carried forward

| Legacy item | Decision | Reason |
|---|---|---|
| `Site.Mobile.master`, `ViewSwitcher.ascx` | dropped | The Web Forms template's separate mobile layout; Bootstrap 5's responsive grid replaces it. |
| `bootstrap-theme.css` | dropped | Bootstrap 3 only and never loaded (see §7). |
| jQuery, `MsAjaxBundle`, the `WebForms*.js` scripts (`Site.master` `ScriptManager`) | dropped | Web Forms and Bootstrap 3 plumbing; Angular and ng-bootstrap replace them. |
| `Default.aspx` | **carried forward** as the home route | It is a page, not a gap: the welcome panel and the role-specific button (§5). |

Any other page the run finds with no CONTROLLER.md action is added to this table in VIEW.md with its reason.

## 11. Decisions made by Claude Code

The user set the direction (one skill, two files, Bootstrap 5, no approval for STYLE.md, prerequisites enforced, stale
pages noted) and delegated the remaining choices for this iteration to Claude Code, on the condition that each is
documented. These are those choices, so they can be reviewed or overridden later:

| # | Decision | Section | Reason |
|---|---|---|---|
| 1 | Split prerequisite check: approved CONTROLLER.md on Windows, built and tested model and controller on Linux | §2 | Each machine checks what it can see; a single note-based gate trusts a note rather than a build |
| 2 | Bootstrap classes translated on Windows and written as a table in STYLE.md | §7 | The translation is reviewed with the contract instead of being guessed at build time |
| 3 | ng-bootstrap instead of Bootstrap's JavaScript | §7 | No jQuery, no DOM manipulation outside Angular |
| 4 | Bootstrap Icons replace Glyphicons | §7 | Glyphicons were removed in Bootstrap 4; Bootstrap Icons is the project's own set |
| 5 | `btn-default` to `btn-secondary`, `btn-xs` to `btn-sm`, `jumbotron` to utility classes, `label` to `badge` | §7 | Nearest 5.3 equivalent; the removed classes have no direct replacement |
| 6 | `bootstrap-theme.css` dropped; Bootstrap 5 default colours accepted | §7 | No 5.3 equivalent; slight shade differences accepted as a parity gap |
| 7 | `Site.css` rules marked keep, adapt or obsolete individually | §7 | The sticky footer and `table-fixed` still matter; the toggle and popover rules are replaced by components |
| 8 | Chart.js, Bootstrap and Bootstrap Icons from npm, never a CDN | §6, §7 | The legacy CDN script had no integrity hash; bundled and pinned versions remove that risk |
| 9 | Route guards are presentation only; the server stays the access check | §5 | A client-side check can be bypassed |
| 10 | Wrong-role access shows a "not authorised" page instead of the login page | §5 | Sending a signed-in user to log in again hides the reason; deliberate parity change |
| 11 | 401 goes to login with a return URL; 403 shows "not authorised"; no server error details shown | §5 | Clear behaviour without leaking server internals |
| 12 | Return URL limited to internal Angular routes | §5 | Keeps the legacy `IsLocalUrl` protection against open redirects |
| 13 | Standard `username`, `current-password`, `new-password` autocomplete values instead of `autocomplete="off"` | §6 | Password managers work; deliberate parity change |
| 14 | Interpolation only: no `innerHTML`, `bypassSecurityTrust*` or HTML built from strings | §6 | Removes the legacy unencoded-`Literal` pattern even though no case was exploitable |
| 15 | Reset link on screen and "No account found" carried forward, flagged as risks | §6 | Parity now; fixing them belongs to the security component |
| 16 | First-login password change recorded as a Phase 2 addition in VIEW.md | §6 | The `.aspx` files cannot show it, so it would otherwise be missed |
| 17 | One `h1` per page, no skipped heading levels; the legacy title format kept | §8 | WCAG 2.1 AA; the legacy pages use `h2` titles |
| 18 | Comment popover trigger becomes a real `button` | §8 | The legacy `span role="button"` is not a native control |
| 19 | Dates formatted in the browser with `DatePipe` `short` and en-US | §9 | Matches the legacy `{0:g}` in the default server culture |
| 20 | Routes in kebab-case, Account pages under `account/` | §4 | Angular convention; one route per legacy page |
| 21 | `Default.aspx` carried forward as the home route, not listed as a gap | §10 | It has content and a role-specific button |
| 22 | When the source contradicts this report, the run follows the source and reports the difference | skill | The code is the fact; the report is corrected afterwards |

Decisions made by the first `/export-view` run (2026-10-02), recorded in VIEW.md under **Decisions made on this run**:

| # | Decision | Where | Reason |
|---|---|---|---|
| 23 | Routes are the kebab-case legacy page names (`/customer-view`, `/account/customer-sign-up`, ...); home is `/` | VIEW.md, all pages | Mechanical and traceable to the legacy page |
| 24 | Query parameters keep their legacy names (`id`, `customerId`, `employeeId`, `userId`, `code`, `returnUrl`) | Reset password, Search, Log in | Cross-links and reset links stay recognisable |
| 25 | A not-found page for unknown routes, and a not-authorised page (`/not-authorised`) | Phase 2 additions | A single-page app must handle both itself |
| 26 | Delete confirmation becomes an accessible modal with the legacy `confirm()` text | Administration | `confirm()` cannot be styled or tested and breaks focus handling |
| 27 | Client-side errors shown once, next to the field, instead of in both a validation summary and the field | Sign up, Log in, Reset password, Submit a repair | Duplicate announcements for screen readers; same messages |
| 28 | Repeated row buttons and "View" links get ticket-specific accessible names; visible text unchanged | Audit log, My repairs, My tickets | WCAG 2.4.6 and 4.1.2 |
| 29 | Every Metrics chart gets an accessible name and a data-table alternative | Metrics | Canvas charts have no text alternative (WCAG 1.1.1) |
| 30 | Skip link, `main` landmark, and the name "Toggle navigation" on the navbar toggler | Header | WCAG 2.4.1; the legacy toggler has no accessible name |
| 31 | The header's username and role come from the security component | Header | CONTROLLER.md has no "current user" action |
| 32 | A non-numeric audit entity id keeps meaning "no filter" | Audit log | Parity with `int.TryParse` |
| 33 | Legacy silent no-ops (take, complete, submit, comment) show the API's error | My repairs, My tickets, Submit a repair | The API returns explicit errors (CONTROLLER.md "Silent no-ops") |
| 34 | The return URL is not passed on to sign-up | Log in | Sign-up ignores it in the legacy app |
| 35 | Chart colours move to the Bootstrap 5.3 equivalents of the legacy palette, same order | STYLE.md | Matches the theme change; keeps the same-colour-per-person rule |
| 36 | `btn-default` beside a primary button becomes `btn-outline-secondary` | STYLE.md | Keeps the legacy visual weight (Bootstrap 3's default button was light) |
| 37 | Selects use `form-select`; legacy inline styles become utilities or two named classes (`.metrics-scroll`, `.metrics-pie`) | STYLE.md | 5.3 styles selects separately; no inline styles in Angular templates |

Decisions made when writing the Linux skill `/import-view` (2026-10-02):

| # | Decision | Where | Reason |
|---|---|---|---|
| 38 | The Angular project lives in `view/angular/` of the Phase 2 repo, project name `mar-view` | import-view | Beside `model/oracle/`, one folder per component |
| 39 | Endpoints are found from the live `/v3/api-docs` by the "Action N:" prefix of each operation summary, not from VIEW.md | import-view | VIEW.md has no URLs by design; the controller already tags every operation with its action number |
| 40 | Precedence: VIEW.md for structure and text, STYLE.md for look, `/v3/api-docs` for URLs and shapes | import-view | Each file is authoritative for one thing; differences are reported |
| 41 | Security screens are built with their server calls stubbed, plus a development-only sign-in stand-in that sets `X-Acting-User-Id` from memory | import-view | The API has no authentication yet (controller-oracle decision 4); only `AuthService` and the interceptor change when the security component arrives |
| 42 | The stand-in never stores the user in `localStorage`, `sessionStorage` or a cookie, and the production build must not contain it | import-view | A header naming any user id is an impersonation switch; it must not survive a reload or ship |
| 43 | A dev-server proxy sends `/api` to `127.0.0.1:8080` | import-view | One origin for the browser, so the API needs no CORS change |
| 44 | The smoke test uses read actions only | import-view | It runs against the long-lived `mar-oracle-controller` copy; writes would change the parity data |
| 45 | The run makes its own secondary decisions and records them in `IMPORT_VIEW_REPORT.md` | import-view | Same rule as this table: decide, then document |

Later runs add their decisions to this table.

## 12. Risks and open items

- **Action renumbering**: if CONTROLLER.md is re-exported and renumbered, VIEW.md's references go stale. Mitigated by
  the approval gate and re-running `/export-view` after any controller change.
- **Session and CSRF** depend on the security component, which is not written yet (§6).
- **Reset link on screen and account enumeration** carried forward from Phase 1 as known risks (§6).
- **Wrong-role behaviour** changes from "redirect to login" to "not authorised" (§5).
- **Look**: the Bootstrap 5 rendering will be close to the legacy look but not pixel-identical; a stated parity gap.
- **Date and time zone** display depends on the controller's timestamp format (§9).
- **No legacy UI tests** exist, so parity is checked by hand against VIEW.md; Phase 2 adds the Angular component test
  suite the brief requires.
- **Phase 1 stored XSS** on the Metrics page (§6): a legacy defect to mention in the migration notes.
- **No "current user" action** in CONTROLLER.md: the header's username and role depend on the security component.
- The per-page accessibility findings are in VIEW.md.
