# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This repo is the **modernizer tool and the report**, not an application. It holds the research/report docs plus the deterministic migration tooling built so far (`tools/dbmigrate/`, with its iteration plans/records in `docs/`). The applications live in sibling repos under `%USERPROFILE%\Documents\dev\aspnet\`:

- `master-antique-repair` — the legacy ASP.NET Web Forms app (Phase 1, complete; the migration *source*). Its `Scripts\` and `docs\` still hold the original copies of the dbmigrate tooling; the copies here are the ones to evolve.
- `master-antique-repair-modern` — Phase 2 target (Angular / Spring Boot / Oracle), currently only an initial commit. README.md links it as `master-antique-repair-claude` on GitHub.

Commands: the only runnable tooling is `tools\dbmigrate\dbmigrate.cmd <export|import|verify|selftest|report|all> --target sqlite|sqlite-linux|mysql` (Windows, from a plain command prompt; needs the legacy app's LocalDB database as source, Docker Desktop for the `-linux`/`mysql` targets). Config is `tools\dbmigrate\migration\migration.config.json` (paths relative to `tools\dbmigrate\`; output goes to gitignored `tools\dbmigrate\export\<target>\` because it contains password hashes). Dialects are in `tools\dbmigrate\migration\dialects\` (`sqlite.ps1`, `mysql.ps1`); a new database, such as Oracle or PostgreSQL, is another file implementing the same `New-Dialect` interface. Exit codes: 0 ok, 1 verify differences, 2 error, 3 refused. There is no build/lint/test tooling beyond that.

## What this repo is

A two-phase legacy-to-modern migration exercise (see [README.md](README.md)) simulating a common engagement pattern: modernizing legacy .NET applications to Java/Angular for federal customers. The goal is not production-grade code — it's demonstrating *how* an AI-assisted migration is reasoned through, including what would be flagged as risk. This repo is where Claude Code is used to plan and drive the Phase 2 modernization.

### Migration iterations done so far (database layer)
Iteration 1 = SQL Server → SQLite on Windows; iteration 2 = SQLite in a Dockerized Linux container; plus a MySQL-in-Docker extra; PostgreSQL is planned as iteration 3. Plans and step-by-step records: [docs/DMPLAN_1.md](docs/DMPLAN_1.md), [docs/DM1.md](docs/DM1.md), [docs/DMPLAN_2.md](docs/DMPLAN_2.md), [docs/DM2.md](docs/DM2.md), [docs/DM_MySQL.md](docs/DM_MySQL.md). These docs are copied verbatim from the legacy repo, so their `Scripts\...` paths mean `tools\dbmigrate\...` here. There is no Oracle dialect yet even though Phase 2 targets Oracle.

### Phase 1 — Legacy Build (complete, in sibling repo)
- Stack: ASP.NET Framework 4.7.2, C#, MVC or WebForms, SQL Server (or SQLite)
- A small domain with 3–4 related entities (e.g., Requests → Assignees → Status History), CRUD, a 3+ state approval/status workflow, hardcoded-role login, and a filtered/paginated list view
- Required: layered architecture (UI / business logic / data access separated — no logic in code-behind), server-side validation, logging of workflow state changes (this becomes the Phase 2 audit trail), and a README explaining structure and how to run it

### Phase 2 — AI-Assisted Modernization (in progress: DB migration tooling exists; app not started)
- Stack: Angular 21, Spring Boot 3, Oracle (README intro says Java 21 / Spring Boot 4.0 — unresolved discrepancy, confirm with the user before choosing)
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
- [docs/AntiqueRepair.md](docs/AntiqueRepair.md) — summary of the real Phase 1 app (`MasterAntiqueRepair`): layout, status, the Phase 2 parity baseline (audit log, soft-delete filtered index, Identity password hashes), the `dbmigrate` export tooling, and setup gotchas.
- [docs/ASPNET.md](docs/ASPNET.md) — how the alternative `CaseTracker` ASP.NET Framework 4.7.2 scaffolds (Web Forms and MVC 5) were created and how to recreate them via `scripts/New-CaseTrackerWebForms.ps1` and `scripts/New-CaseTrackerMvc.ps1`. Covers why Visual Studio's wizard can't be used here and a verified MVC assembly-version gotcha.

## Working in this repo going forward

- The real Phase 1 app is **`MasterAntiqueRepair`**, an ASP.NET Web Forms Website project (antique repair shop domain) in its own git repo at `%USERPROFILE%\Documents\dev\aspnet\master-antique-repair`, with its own CLAUDE.md/README. Read [docs/AntiqueRepair.md](docs/AntiqueRepair.md) first. As of the last review (2026-09-21) Phase 1 is functionally complete: Users/Tickets/Comments/AuditLog, a SUBMITTED → INPROGRESS → COMPLETED workflow, ASP.NET Identity auth, Services/Repositories layering, and a `Scripts\dbmigrate.cmd` export pipeline (SQLite/MySQL done, PostgreSQL planned). It has no test project. That app is the Phase 2 parity baseline, and its audit-log format is what Phase 2 must preserve. The sibling's own CLAUDE.md is the detailed source, so re-read it before relying on the summary here.
- The `CaseTracker` scaffolds in [docs/ASPNET.md](docs/ASPNET.md) (under `%USERPROFILE%\source\repos`) are reference/alternative scaffolding, not the live project. The scripts `scripts/New-CaseTrackerMvc.ps1` and `scripts/New-CaseTrackerWebForms.ps1` are tracked in git but currently deleted in the working tree, so ASPNET.md's links to them dangle unless the deletion is reverted.
- Phase 1's deterministic regression seed (`Seed-RegressionData.ps1` in the legacy repo: 1 manager, 3 employees, 8 customers, 24 tickets — 8 per state — 26 comments, 77 audit rows) is the concrete parity baseline for Phase 2. Phase 1 traits Phase 2 must reproduce or explain: TPH `Users` table with a `Discriminator`, the filtered unique index `IX_Users_Name_Active` (soft delete frees the username), Identity PBKDF2 password hashes, add-only comments, and audit rows that never store comment text.
- `app/` does not currently exist; Phase 2 code goes in `master-antique-repair-modern`, not here. `.gitignore` covers Visual Studio output (`bin/`, `obj/`, `.vs/`, `*.user`, `*.suo`).
- Keep the audit/workflow-state-change logging format consistent between Phase 1 and Phase 2 — RESEARCH.md's methodology explicitly measures Phase 2 against the Phase 1 behavioral baseline (transitions, log format), and Phase 2's auditability requirement is to preserve or improve on it.
- RESEARCH.md is an internal working draft for engagement-team reference, not a public/client deliverable (see its Disclaimer section) — keep that framing if extending it.
