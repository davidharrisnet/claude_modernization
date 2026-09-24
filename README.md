# aspnet_claude_modernization

## Introduction
This repository is the collecion of experiments using Claude code to convert ASP.NET Framework 4.7.2, C#, WebForms projects into Java 21/Angular 21/ Spring Boot 4.0/PostgreSQL. The legacy ASP.NET project created for this experiment,  [Master Antique Repair](https://github.com/davidharrisnet/master-antique-repair) which is deployed on request at [fxbmuz.com](https://fxbmuz.com/) provides the key architectural [components](#components).

This project, then is a collection of experiments scoped by these components - model, view, controller and security. Each of which has several iterations described in the documention and mirrored in the git branches. For instance converting the database, the model component, had six iterations and six code branches, model-iteration1 to model-iteration6. The working tree keeps only the final PostgreSQL path, two tools called export-postgresql and import-postgresql, documented in docs/phase1/dbmigrate/DATA_MIGRATION.md; the earlier iterations remain in git history and those branches.


## Requirements

**PHASE 1 — Legacy Build**
Stack: 
* ASP.NET Web Forms, C#, .NET Framework 4.7.2
* Entity Framework 6 (Code First + Migrations)
* SQL Server
* Bootstrap 3 / jQuery, via System.Web.Optimization bundling

Functional requirements:

*	A single core domain with 3–4 related entities (e.g., a simple case/request tracking app: Requests → Assignees → Status History)
*	Basic CRUD for each entity
*	One approval/status-transition workflow with at least 3 states (e.g., Submitted → In Review → Closed)
*	A simple login/role check (hardcoded roles are fine)
*	One list/search view with filtering and pagination

Non-functional requirements:

*	Layered architecture (UI / business logic / data access clearly separated — no logic in code-behind)*	Server-side input validation
*	Logging of workflow state changes (this becomes your audit trail in Phase 2)
*	A short README explaining the structure and how to run it
  
**PHASE 2 — AI-Assisted Modernization**
Stack: Angular 21, Spring Boot 3, Oracle

Functional requirements:

* Feature parity with Phase 1 (same entities, workflow, and auth boundary). Where you can't get exact 1:1 parity, note it and explain why.
*	A REST API in Spring Boot backing the Angular SPA (no server-rendered views)
*	A data migration plan/script from the SQL Server schema to Oracle or something database, noting any type or logic differences

Non-functional requirements:

*	Security: server-side validation, no secrets in source, basic protection against injection/XSS
*	Testability: at least one unit test suite per layer (Spring service layer, Angular component)
*	Maintainability: clear separation of concerns — no logic in controllers or components
*	Accessibility: basic WCAG 2.1 AA conformance on the Angular UI (labels, keyboard navigation, contrast)
*	Documentation: a short migration notes doc
*	Auditability: preserve or improve on the workflow logging from Phase 1

**DELIVERABLES**
1. Working legacy app matching the Phase 1 scope
2. Working modernized app matching the Phase 2 scope, with any parity gaps explained
3. A 1–2-page(s) migration notes doc: key decisions, risks you'd flag in a real migration, what you'd do differently with more time
4. A brief walkthrough of how you used Claude in the process — what you had it do, and what you double-checked or overrode

## Report

### Claude Code

**Running the database migration.** Open this repository in VS Code (or a terminal) with Claude Code and type one of:

```
Run export-postgresql.
Run import-postgresql.
Run export-oracle.
Run import-oracle.
```

The first runs on the Windows machine (SQL Server LocalDB, sanitized PostgreSQL files out); the second on the Linux
machine (those files loaded into PostgreSQL in Docker and verified). The last two are an Oracle proof of concept
alongside PostgreSQL: `export-oracle` produces sanitized Oracle files (Oracle AI Database 26ai), and
`Run import-oracle` on the Linux machine loads them into an Oracle container and verifies them. Claude Code reads the tool's own instructions,
`tools/phase1/dbmigrate/<tool>/CLAUDE.md`, and follows them: the command, the expected results, the checks, and the
rules (such as never testing on the delivered database). Each tool's human description is
`docs/phase1/dbmigrate/<tool>/README.md`.

**The model (Phase 2).** "Run import-postgresql" rebuilds and verifies the database only. The Spring Boot
model that uses it lives in the separate repository `master-antique-repair-claude` (`model/postgresql/`). With this
repository open in Claude Code, type:

```
Run model-postgresql
```

or, to rebuild the model code from scratch, `Rebuild the model.` Claude Code follows
`docs/phase2/model/postgresql/CLAUDE.md`: it creates the database login and the local network route the model needs, runs
the model (connection check), then the first-login password change. Run import-postgresql first if the database does not
exist; running it again also removes the model's login and route, which the demonstration then recreates.

### Components
These experiments took on a modular approach, focusing on each project component as separate tasks. 

* Model
Converting SQL Server to PostgreSQL
* View
Angular
* Controller

    Spring Boot
* Security
  * Authenticaion
    Spring Boot
  * Risk Mitigation

#### Angular
#### Spring-Boot
#### SQLite
#### Java

## Results

### How the model got here
The model component (the database) was built in iterations, each a git branch (`model-iteration*`), over four days in September 2026. SQLite was the test case: the point was to prove the export, load and verify pipeline before committing to a target database.

* **Iteration 1 (21 Sep), SQLite on Windows.** The first end-to-end migration: export from SQL Server LocalDB, build a SQLite database, verify it is identical to the source, and write a report.
* **Iteration 2 (21 Sep), SQLite in Docker on Linux.** The same migration, with the new database created and checked inside a Linux container. Dockerizing the database was the decision that made everything after it repeatable: a disposable, verifiable target that needs nothing installed but Docker.
* **Iteration 3 (22 Sep), an independently verified image built entirely on Linux.** Review caught two real problems: the verifier trusted results inherited from earlier iterations, and real password hashes had been committed to git. The fix was to sanitize first: the export now nulls `PasswordHash` and `SecurityStamp` and sets `MustResetPassword`, so every migrated user resets their password on first login. This became a rule for every later tool.
* **Iteration 4 (23 Sep), export for PostgreSQL.** The upgrade from SQLite to a database that could be the real target. It became `export-postgresql`.
* **Iteration 5 (23 Sep), PostgreSQL in Docker.** It became `import-postgresql`. Its database guide (how to connect, including from Spring Boot) seeded the plan for the Phase 2 model.
* **Oracle (24 Sep).** Phase 2 explicitly lists Oracle, so the same pair was built for it: `export-oracle` and `import-oracle`, targeting Oracle AI Database 26ai Free. Every Oracle detail that could not be tested on Windows was confirmed on Linux without changing the export.

On 24 Sep the working tree was reduced to the four final tools. Iterations 1–3 remain in git history and the `model-iteration*` branches.

### Where things landed
**The database migration is done, for two targets.**

| Tool | Runs on | Result |
|---|---|---|
| `export-postgresql` | Windows | Sanitized PostgreSQL schema and data from SQL Server |
| `import-postgresql` | Linux | 80 of 80 checks, 155 of 155 rows identical, self-test 7 of 7 |
| `export-oracle` | Windows | Sanitized Oracle files, self-test 13 of 13, row fingerprints equal to the PostgreSQL export's |
| `import-oracle` | Linux | 86 of 86 checks, 155 of 155 rows identical, self-test 7 of 7 |

**The Phase 2 model has started.** In `master-antique-repair-claude`, `model/postgresql/` is a Spring Boot 4.1.1 (Java 21) model layer on the migrated PostgreSQL database: JPA entities for the migrated tables, repositories, and a `LoginService` that enforces the password change on first login, with unit tests. Hibernate runs with `ddl-auto=validate` so the schema belongs to the migration. `model/oracle/` is the same layer on the Oracle database, self-contained and independent of the PostgreSQL one. Each was seeded by its import tool's database guide.

**Not started:** the controller (REST API), security (Spring Security, a real identity check, lockout, audit logging in the legacy format) and the view (Angular).

**Lessons.** Sanitize credentials before anything is written, not after. Verify against an independent record of the source, not against a previous run's output. A disposable Docker target makes every run repeatable.

## Further Work
Random Samples
* https://github.com/PavlosTzitzos/asp.net-samples
* https://github.com/f2calv/WebAppDI
* https://github.com/search?q=asp.net+4.7.2&type=repositories





 



 
