# Report: Master Antique Repair modernization

## Introduction

This project set out to learn how to use Claude Code to convert a legacy ASP.NET project into a modern architecture.
It has two phases: Phase 1 builds a legacy application, and Phase 2 modernizes it with Claude Code's help. The work
was an iterative process, and much of it was learning Claude itself.

The project was cut short by changing priorities, so it is wrapped up here in an incomplete form. This report records
what was done, what was learned, and what future work should be.

| Repository | What it holds |
|---|---|
| `master-antique-repair` | Phase 1: the legacy ASP.NET Web Forms application (the migration source) |
| `claude_modernization` (this one) | The migration tooling, the plans, the contracts and the reports that drove Phase 2 |
| `master-antique-repair-claude` (project name `master-antique-repair-modern`) | Phase 2: the Spring Boot application on Oracle |

| Part | Status |
|---|---|
| Phase 1 legacy application | **Complete**, in `master-antique-repair` |
| Phase 2 model (database migration and Spring Boot model) | **Complete** |
| Phase 2 controller (REST API with Swagger) | **Proven possible** |
| Phase 2 security | Not started |
| Phase 2 view (Angular) | Not started |

---

## Phase 1: the legacy build

### Requirements

**PHASE 1 — Legacy Build**
Stack: ASP.NET Framework 4.7.2, C#, WebForms, SQL Server

Functional requirements:

* A single core domain with 3–4 related entities (e.g., a simple case/request tracking app: Requests → Assignees → Status History)
* Basic CRUD for each entity
* One approval/status-transition workflow with at least 3 states (e.g., Submitted → In Review → Closed)
* A simple login/role check (hardcoded roles are fine)
* One list/search view with filtering and pagination

Non-functional requirements:

* Layered architecture (UI / business logic / data access clearly separated — no logic in code-behind)
* Server-side input validation
* Logging of workflow state changes (this becomes your audit trail in Phase 2)
* A short README explaining the structure and how to run it

### What we did

The Phase 1 requirements were installed on a Windows 10 machine with Microsoft Visual Studio 2017, and Claude was used
to build out **MasterAntiqueRepair** quickly. It is a repair-shop tracker: customers submit repair requests for antique
items, employees pick up the tickets and complete them, and managers administer accounts and oversee the work.

| Requirement | How it was met |
|---|---|
| Entities | `User` (one table for Customer, Employee and Manager, told apart by a `Discriminator` column), `Ticket`, `Comment` and `AuditLog`, plus the role tables `Roles` and `UserRoles` |
| CRUD | Tickets created, read and moved through their states; comments added (add-only: edit and delete were removed on purpose); employees and customers added, renamed and soft-deleted by the manager |
| Workflow | `SUBMITTED → INPROGRESS → COMPLETED`: a customer submits, an employee takes an unassigned ticket ("Assign to Me"), the same employee completes it |
| Login and roles | Three roles (Customer, Employee, Manager), checked server-side on every page by `RepairAuthHelper.RequireRole` |
| List and search | A Search page with four tabs (ticket, customer, employee, comment text), and the manager's Audit Log with an Entity Id filter and 10 or 20 rows per page |
| Layering | A real three-layer split: the `.aspx` pages are the view; the code-behind acts as the controller and calls exactly one service; the model is the services, the repositories and the domain classes that carry the rules (`Employee.TakeTicket`, `Ticket.CreateSubmitted`, …) in `MasterAntiqueRepairData` |
| Validation | Server-side: text required, trimmed, at most 2,000 characters, no control characters other than CR, LF and TAB; unique active usernames |
| Audit logging | An `AuditLog` row for every state change and account action: timestamp, actor, action code, entity type and id, never comment text or ticket descriptions |
| README | In the Phase 1 repository |

**Beyond the requirements.** The requirements ask only for a simple login and role check. What was built goes further:
ASP.NET Identity sign-in, account lockout, per-IP rate limiting, password reset and a security review (see
[Security](#security)). Bootstrap CSS styling, a Metrics page and a mobile layout were also not required.

---

## Phase 2: the AI-assisted modernization

### How the approach was found

Phase 2 was an iterative process of learning Claude, working through Claude Academy alongside the project. The
database was attempted several times, each attempt a git branch (`model-iteration*`): SQLite on Windows, then SQLite
in Docker on Linux, then the same with the credentials sanitized first, then PostgreSQL, and finally Oracle, the
database the brief names.

The work eventually settled on **Claude Code skills and subagents**. Each skill and agent has its own configuration
and instructions, so it can specialize, and the project's main `CLAUDE.md` does not fill up with every detail.

The project was then divided architecturally into **model, view and controller**, with a strong testing component in
each to verify that the conversion worked.

### The export/import pattern

Every skill pair follows the same pattern across two machines:

- **Export** runs on Windows, where the Phase 1 source lives. It reads that source and writes an artifact that can
  be reviewed.
- **Import** runs on Linux, where the Phase 2 stack lives. It takes only that artifact, builds the Phase 2 part from
  it, and verifies the result.

| Skill | Runs on | Reads | Produces |
|---|---|---|---|
| `/export-oracle` | Windows | The SQL Server database | A sanitized Oracle schema, the data, and a record of the source |
| `/import-oracle` | Linux | Those files | The Oracle database in Docker, verified, with an HTML report |
| `/model-oracle` | Linux | The migrated database | A demonstration of the Spring Boot model on a temporary copy |
| `/export-controller` | Windows | The legacy pages and code-behind | The controller contract `CONTROLLER.md` |
| `/import-controller` | Linux | The approved contract | The REST API with Swagger, its tests and a smoke test |

Two subagents own their layers: `model-oracle` (the entities, repositories and their tests) and `controller` (the REST
API, held to the contract).

### Requirements

**PHASE 2 — AI-Assisted Modernization**
Stack: Angular 21, Spring Boot 3, Oracle

Functional requirements:

* Feature parity with Phase 1 (same entities, workflow, and auth boundary). Where you can't get exact 1:1 parity, note it and explain why.
* A REST API in Spring Boot backing the Angular SPA (no server-rendered views)
* A data migration plan/script from the SQL Server schema to Oracle or something database, noting any type or logic differences

Non-functional requirements:

* Security: server-side validation, no secrets in source, basic protection against injection/XSS
* Testability: at least one unit test suite per layer (Spring service layer, Angular component)
* Maintainability: clear separation of concerns — no logic in controllers or components
* Accessibility: basic WCAG 2.1 AA conformance on the Angular UI (labels, keyboard navigation, contrast)
* Documentation: a short migration notes doc
* Auditability: preserve or improve on the workflow logging from Phase 1

### What we accomplished

**Stack used:** Oracle AI Database 26ai Free in Docker, and Spring Boot 4.1.1 on Java 21 (the brief names Spring Boot
3 in one place and 4.0 in another). Angular was not started.

#### Model: complete

`export-oracle`, run on Windows, produced the sanitized data files and the schema. `import-oracle`, run on Linux,
built the Oracle database and populated it. Its testing step verified every table against the record the export made
of SQL Server, row by row:

| Table | SQL Server (at export) | Oracle |
|---|---|---|
| roles | 3 | 3 |
| users | 12 | 12 |
| tickets | 24 | 24 |
| comments | 26 | 26 |
| audit_logs | 79 | 79 |
| user_roles | 12 | 12 |
| user_claims | 0 | 0 |
| user_logins | 0 | 0 |
| **Total** | **156** | **156** |

86 of 86 checks passed. The detailed report is
[MigrationVerificationReport.html](docs/phase2/dbmigrate/import-oracle/MigrationVerificationReport.html), and the
strategy is in [DATA_MIGRATION.md](docs/phase2/dbmigrate/DATA_MIGRATION.md).

The type and logic differences between SQL Server and Oracle:

- **Names:** unquoted lowercase snake_case (`created_at`), from a written, reviewed rename map. Data is never changed.
- **Soft delete with unique usernames:** SQL Server's filtered unique index becomes a function-based index on
  `CASE WHEN deleted_at IS NULL THEN LOWER(name) END`, which also keeps usernames case-insensitive as they were.
- **Booleans** become the native `BOOLEAN` type, **timestamps** `TIMESTAMP(3)` without a time zone, and **identity
  columns** continue from the last migrated id.
- **Empty strings:** Oracle stores `''` as NULL, so the export refuses any source that contains one rather than
  changing data silently.

The Spring Boot model (`model/oracle/` in the Phase 2 repository):

- JPA entities for every table in use. Hibernate checks them against the migrated schema and refuses to start if they
  disagree, so the schema belongs to the migration.
- The Phase 1 rules on the model classes: the ticket workflow, add-only comments on completed tickets, the text rules,
  soft delete and the legacy audit codes.
- Every migrated user must set a new password at first sign-in (see [Security](#security)).

#### Controller: proven possible

- **The contract.** `export-controller`, run on Windows, read the legacy pages to derive what became the REST APIs and
  the actions on the database: [CONTROLLER.md](docs/phase2/controller/CONTROLLER.md), 29 numbered actions grouped by
  role, with the rules the legacy code enforces. It was approved before any code was written, and the API offers only
  those actions, not CRUD on every table.
- **The service.** `import-controller`, run on Linux, read the contract and produced a working Swagger service in which
  every action that is possible today (6–29) is replicated.
  - *Note:* sign-up, login and password reset (actions 1–5) are not included. They wait for the security component.
- **Testability:** 107 unit tests on the Spring service layer, all passing.
- **Separation of concerns:** the services hold the logic; the controllers only map requests to them.
- **Auditability:** preserved. The audit log uses the same codes and fields, and never stores comment text.
- **Auth boundary:** partly done. Roles are checked on every action, but there is no real sign-in yet: each request
  names its user in a header, so the server listens on `127.0.0.1` only.

#### Parity gaps and deliberate differences

- **No authentication yet**; the acting-user header is a local-only stand-in.
- **Explicit errors where Phase 1 silently did nothing** (a ticket that is not yours, taking a taken ticket,
  commenting before completion): 404 or 409 instead of no response.
- **Two flagged fixes:** completing an already completed ticket is refused (Phase 1 completed it again and moved the
  date), and an invalid completion comment is refused before anything changes (Phase 1 crashed after the state change).
- **Passwords:** every migrated user must set a new password; new accounts are created without one.
- **Column names** differ from the legacy schema (snake_case); the data does not.
- **Unused tables:** `user_claims` and `user_logins` (ASP.NET Identity, 0 rows) are migrated but have no use case.

**Not in this phase:** the Angular SPA, WCAG 2.1 AA, Angular component tests and the migration notes document.

---

## Security

Security should be a skill of its own (see [Next steps](#next-steps)). This section records what was done in each phase.

### Phase 1: the ASP.NET project

- **Sign-in:** ASP.NET Identity with PBKDF2 password hashing, an HttpOnly auth cookie, and safe redirects after login.
- **Brute force:** account lockout after 5 failed attempts for 15 minutes, and a per-IP rate limit of 20 attempts in
  15 minutes for login, sign-up and password reset.
- **Password reset:** a token valid for one hour (no email is configured, so the link is shown on screen).
- **Security review**, with fixes for:
  - stored cross-site scripting (XSS), by encoding output everywhere user text is shown;
  - oversized input, with a 2,000-character limit on comments and descriptions;
  - insecure direct object references (IDOR), with server-side ownership checks on every change;
  - cross-site request forgery (CSRF), with anti-forgery tokens;
  - SQL injection, which is not a live risk because all data access goes through EF6.
- **HTTPS:** enforcement that can be switched on per environment.

### Phase 2: what we did

- **Passwords sanitized.** The export removes every password hash and security stamp in memory, before anything is
  written, and refuses to run otherwise. No legacy credential reaches Oracle or git.
- **Forced password reset.** Every migrated user must set a new password at first sign-in. A new password must be at
  least 12 characters and is stored as a bcrypt hash. The change also needs an identity check, which refuses
  everything until real security exists, so an account cannot be taken over by someone who knows only its username.
- **No secrets in source.** The database administrator passwords are random and kept nowhere. The application uses
  least-privilege logins (`mar_app`, `mar_readonly`) whose passwords live only in a private file outside every
  repository. The database container publishes no port.
- **The API** never sends or accepts a password or security stamp, queries only through bound parameters (no
  injection), and listens on `127.0.0.1` only.
- **Text length.** Oracle limits a text value to 4,000 bytes, which accented or other multi-byte text can reach before
  the 2,000-character limit. The model enforces both limits.
- **Verification guards against mistakes, not tampering.** The import is checked against the export's own record,
  so anyone who can edit the export can edit that record too.

Two problems were caught by review and fixed:

- **Password hashes committed.** Real password hashes were committed to git in an early iteration. The fix became the
  rule for every tool: sanitize first, in memory, before anything is written.
- **A verifier that trusted old results.** An early verifier accepted results inherited from a previous run. Every
  verification now compares against an independent record of the source, built by a separate code path.

Against the Phase 2 security requirement: server-side validation is done, there are no secrets in source, and
injection is covered by bound parameters. XSS protection belongs to the Angular view, which is not started.

---

## Next steps

1. **Angular regression tests** that mock all the REST actions on the database, to verify that everything works as
   designed.
2. **The view**, following the same pattern: `export-view` on Windows and `import-view` on Linux, to create the
   Angular pages and the routes between them. Styling may get a separate skill, but it is one technology that stays
   the same: Bootstrap CSS.
3. **Security**, as its own skills: `export-security` on Windows to read the ASP.NET authentication and security code,
   `import-security` on Linux to build Spring Security from it, and possibly `security-analysis`. Security in 2026
   should be more robust than in 2017, so the target is better than parity. This is its own deep area of research:
   using LLMs to look aggressively for vulnerabilities.
4. **Housekeeping:** bring [README.md](README.md) up to date. Its Report and Results sections still describe the
   PostgreSQL tools, which are no longer in the working tree.

---

## Lessons learned

- **Plan complicated actions before you let Claude act.** Claude tends to produce voluminous output, and without a
  plan you won't know what it did: it can go rogue.
- **Use `/brainstorm` mode.** This project created a `/brainstorm` skill in which Claude listens to the requests and
  reviews each step of the plan with you, iteratively, until it is satisfactory. Once the plan is complete, exit
  brainstorm mode and implement it.
- **Be prepared to `/rewind`.** If the result is wrong, rewind, re-enter `/brainstorm` and fix the plan.
- **Turn a good plan into a skill.** Once you are satisfied, the skill preserves the steps, so the work can be
  repeated exactly.
