# aspnet_claude_modernization

## Introduction
This repository is the collecion of experiments using Claude code to convert ASP.NET Framework 4.7.2, C#, WebForms projects into Java 21/Angular 21/ Spring Boot 4.0/PostgreSQL. The legacy ASP.NET project created for this experiment,  [Master Antique Repair](https://github.com/davidharrisnet/master-antique-repair) which is deployed on request at [fxbmuz.com](https://fxbmuz.com/) provides the key architectural [components](#components).

This project, then is a collection of experiments scoped by these components - model, view, controller and security. Each of which has several iterations described in the documention and mirrored in the git branches. For instance converting the database, the model component, had six iterations, documented in docs/phase1/dbmigrate/DATA_MIGRATION.md and with six code branches, model-iteration1 to model-iteration6.


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

**Repeating an iteration.** Open this repository in VS Code (or a terminal) with Claude Code and type, for example:

```
Repeat iteration 5.
```

Claude Code reads the iteration's own instructions, `tools/phase1/dbmigrate/iterationN/CLAUDE.md`, and follows them:
the command, the expected results, the checks, and the rules (such as never testing on the delivered database). Each
iteration's human description is `docs/phase1/dbmigrate/iterationN/README.md`.

**The backend (Phase 2 model).** "Repeat iteration 5" rebuilds and verifies the database only. The Spring Boot
backend that uses it lives in the separate repository `master-antique-repair-claude` (`backend/`). With this
repository open in Claude Code, type:

```
Run the backend demonstration.
```

or, to rebuild the backend code from scratch, `Rebuild the backend.` Claude Code follows
`docs/phase2/model/MODEL_PLAN.md`: it creates the database login and the local network route the backend needs, runs
the backend (connection check), then the first-login password change. Run iteration 5 first if the database does not
exist; repeating iteration 5 also removes the backend's login and route, which the demonstration then recreates.

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


## Further Work
Random Samples
* https://github.com/PavlosTzitzos/asp.net-samples
* https://github.com/f2calv/WebAppDI
* https://github.com/search?q=asp.net+4.7.2&type=repositories





 



 
