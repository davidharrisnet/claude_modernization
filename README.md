# mission_modernization
An examintion of challenges and strategies to convert legacy .NET to modern Java/Angular

One of our most common engagement patterns is modernizing/renovating legacy .NET applications to a Java/Angular stack for federal customers. This exercise simulates that end-to-end: you'll build a small legacy app, then migrate it using Claude as your AI pair, documenting your technical decisions along the way. This isn't about producing production-grade code — it's about demonstrating how you reason through a migration, including what you'd flag as risk.

 

PHASE 1 — Legacy Build

Stack: ASP.NET Framework 4.7.2, C#, MVC or WebForms, SQL Server (or SQLite is fine)

 

Functional requirements:

A single core domain with 3–4 related entities (e.g., a simple case/request tracking app: Requests → Assignees → Status History)
Basic CRUD for each entity
One approval/status-transition workflow with at least 3 states (e.g., Submitted → In Review → Closed)
A simple login/role check (hardcoded roles are fine)
One list/search view with filtering and pagination
 

Non-functional requirements:

Layered architecture (UI / business logic / data access clearly separated — no logic in code-behind)
Server-side input validation
Logging of workflow state changes (this becomes your audit trail in Phase 2)
A short README explaining the structure and how to run it
 

PHASE 2 — AI-Assisted Modernization

Stack: Angular 21, Spring Boot 3, Oracle

 

Functional requirements:

Feature parity with Phase 1 (same entities, workflow, and auth boundary). Where you can't get exact 1:1 parity, note it and explain why.
A REST API in Spring Boot backing the Angular SPA (no server-rendered views)
A data migration plan/script from the SQL Server schema to Oracle or something database, noting any type or logic differences
 

Non-functional requirements:

Security: server-side validation, no secrets in source, basic protection against injection/XSS
Testability: at least one unit test suite per layer (Spring service layer, Angular component)
Maintainability: clear separation of concerns — no logic in controllers or components
Accessibility: basic WCAG 2.1 AA conformance on the Angular UI (labels, keyboard navigation, contrast)
Documentation: a short migration notes doc
Auditability: preserve or improve on the workflow logging from Phase 1
 

DELIVERABLES

1. Working legacy app matching the Phase 1 scope

2. Working modernized app matching the Phase 2 scope, with any parity gaps explained

3. A 1–2-page(s) migration notes doc: key decisions, risks you'd flag in a real migration, what you'd do differently with more time

4. A brief walkthrough of how you used Claude in the process — what you had it do, and what you double-checked or overrode

 
