# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This repository currently contains only planning/research documentation — no application code exists yet. There is no build, lint, or test tooling to run. When code is added (per the phases below), update this file with the actual commands (dotnet build/test, mvn/gradle, ng test, etc.) and architecture notes.

## What this repo is

A two-phase legacy-to-modern migration exercise (see [README.md](README.md)) simulating a common engagement pattern: modernizing legacy .NET applications to Java/Angular for federal customers. The goal is not production-grade code — it's demonstrating *how* an AI-assisted migration is reasoned through, including what would be flagged as risk.

### Phase 1 — Legacy Build (not yet started)
- Stack: ASP.NET Framework 4.7.2, C#, MVC or WebForms, SQL Server (or SQLite)
- A small domain with 3–4 related entities (e.g., Requests → Assignees → Status History), CRUD, a 3+ state approval/status workflow, hardcoded-role login, and a filtered/paginated list view
- Required: layered architecture (UI / business logic / data access separated — no logic in code-behind), server-side validation, logging of workflow state changes (this becomes the Phase 2 audit trail), and a README explaining structure and how to run it

### Phase 2 — AI-Assisted Modernization (not yet started)
- Stack: Angular 21, Spring Boot 3, Oracle
- Feature parity with Phase 1 (same entities, workflow, auth boundary); any parity gaps must be noted and explained
- A REST API in Spring Boot backing the Angular SPA (no server-rendered views)
- A data migration plan/script from SQL Server schema to Oracle, noting type/logic differences
- Required: server-side validation and injection/XSS protections, no secrets in source, one unit test suite per layer (Spring service layer, Angular component), clear separation of concerns (no logic in controllers/components), WCAG 2.1 AA basics on the Angular UI, a migration notes doc, and preserved/improved workflow audit logging

### Deliverables
1. Working legacy app (Phase 1 scope)
2. Working modernized app (Phase 2 scope), with parity gaps explained
3. A 1–2 page migration notes doc: key decisions, risks to flag in a real migration, what would be done differently with more time
4. A brief walkthrough of how Claude was used — what it did, and what was double-checked or overridden

## Documentation in this repo

- [README.md](README.md) — the exercise brief and requirements for both phases (source of truth for scope)
- [docs/RESEARCH.md](docs/RESEARCH.md) — draft internal paper ("AI-Assisted Modernization of Legacy .NET Applications to Java/Angular"). Contains the .NET↔Java concept/technology mapping tables (EF↔Hibernate, NuGet↔Maven, IIS↔Tomcat/Jetty, async/await↔CompletableFuture/Virtual Threads, etc.), migration strategies under consideration (clean boundaries, hybrid interop via JNBridgePro/API gateways, GenAI-assisted translation, Strangler Fig pattern), and cited references (Fowler, Feathers, Newman, OWASP, WCAG). Still an outline in progress — many sections are headers only.
- [docs/NET_JAVA.md](docs/NET_JAVA.md) — short scratch notes on .NET vs Java technical differences (concurrency, logging context, WCF-to-REST/gRPC); table is partially filled in.
- [docs/ASPNET.md](docs/ASPNET.md) — how the Phase 1 ASP.NET Framework 4.7.2 scaffolds (Web Forms and MVC 5) were created and how to recreate them via `scripts/New-CaseTrackerWebForms.ps1` and `scripts/New-CaseTrackerMvc.ps1`. Covers why Visual Studio's wizard can't be used here and a verified MVC assembly-version gotcha.

## Working in this repo going forward

- Two Phase 1 scaffolds already exist outside this repo, under `%USERPROFILE%\source\repos` (`legacy-app` for Web Forms, `legacy-app-mvc` for MVC 5) — see [docs/ASPNET.md](docs/ASPNET.md) before re-scaffolding.
- Keep the audit/workflow-state-change logging format consistent between Phase 1 and Phase 2 — RESEARCH.md's methodology explicitly measures Phase 2 against the Phase 1 behavioral baseline (transitions, log format), and Phase 2's auditability requirement is to preserve or improve on it.
- RESEARCH.md is an internal working draft for engagement-team reference, not a public/client deliverable (see its Disclaimer section) — keep that framing if extending it.
