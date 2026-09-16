# aspnet_claude_modernization

## Introduction
This repository is the report of experiments using Claude code to convert ASP.NET Framework 4.7.2, C#, WebForms projects into Java 21/Angular 21/ Spring Boot 4.0. The legacy ASP.NET project created for this experiment,  [Master Antique Repair](https://github.com/davidharrisnet/master-antique-repair) which is deployed on request at [fxbmuz.com](https://fxbmuz.com/) provides the key architectural components for a modular cluade conversion. 

The converted project [Mater Antique Repair Claude](https://github.com/davidharrisnet/master-antique-repair-claude.git)

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

### Strategies


### Experiments
* Model
* View
* Controller
* Security
  * Authenticaion
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





 



 
