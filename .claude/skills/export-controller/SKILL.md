---
name: export-controller
description: Writes the controller contract docs/phase2/controller/CONTROLLER.md (Windows only) by reading the legacy Web Forms pages to find the REST actions Phase 1 permits; the Linux side builds the Swagger REST API from it once the user approves it. Use when the user types /export-controller or says "Run export-controller".
---

# /export-controller

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `MINGW*`, `MSYS*` or `CYGWIN*` means Windows: continue. Anything else (`Linux`,
`Darwin`) means stop: say "export-controller runs only on Windows; this machine reports `<output>`" and run nothing.

## What it does

Reads the legacy application and rewrites `docs/phase2/controller/CONTROLLER.md` from scratch: the list of actions the
Phase 2 REST API may offer, confined to what Phase 1 actually lets each role do (not CRUD on every table). The file is
tracked in git, so overwriting it is intended; `git diff` is the review. Run it in this session, not through an agent,
so the page-by-page reasoning stays visible.

## Source (read only)

The legacy repo `master-antique-repair` is a sibling of this repo (`..\master-antique-repair` from the repository root).
Read, in this fixed order so numbering is stable between runs:

1. `MasterAntiqueRepair/MasterAntiqueRepair/Account/*.aspx` and their `.aspx.cs`, alphabetically.
2. `MasterAntiqueRepair/MasterAntiqueRepair/*.aspx` and their `.aspx.cs`, alphabetically.
3. `MasterAntiqueRepair/MasterAntiqueRepair/Site.master` (+ `.cs`): the menu per role and log off.
4. `MasterAntiqueRepair/MasterAntiqueRepair/App_Code/` (`RepairAuthHelper.RequireRole` sets which role may open a page;
   `AuthService` for sign-up, login and password reset; `IpThrottle`; `IdentityModels.cs` for the reset-token provider)
   and `MasterAntiqueRepair/MasterAntiqueRepairData/App_Code/`: the domain classes, `Services/` (most rules and audit
   calls live here - read every service a page calls), `Repositories/` (filters and ordering), `IdentityConfig.cs`
   (password, username and lockout rules) and `AuditLog.cs` (the audit `ActionType` and `EntityKind` codes).

An action is something a page lets a user do or see: a button or command that changes data, or a list or lookup it
shows. Base every action and rule on code you read; never invent one. Where the code is unclear, say so in the file.

## CONTROLLER.md format

1. Title `# Controller use cases: the actions Phase 1 permits`, a short paragraph naming the sources read, and the line
   `Status: proposed` (always; only the user changes it to `approved`).
2. One section per role, in this order: **Anyone (not signed in)**, **Customer**, **Employee**, **Manager**. Within a
   section, actions follow the page order above.
3. Actions numbered 1, 2, 3 ... across the whole file. Each: a bold name, the legacy page in parentheses, the inputs and
   their validation, the state change or result, and the audit code it writes (legacy name, e.g. AssignTicket), or none.
4. A final section **Rules the legacy code enforces**: cross-cutting rules (who may comment on what, who may take
   tickets, soft delete, tables no page uses, what the legacy app has no action for), each citing the class or method.
   Also flag actions that depend on data not in the migrated schema, and actions that belong to the security component
   (`docs/phase2/security/`: sign-up, login, password set and reset).

Plain markdown, no endpoint URLs or Java: the Linux side decides those.

## Finish

- Report how many actions per role, and what changed against the previous file (run `git diff --stat` and
  `git diff docs/phase2/controller/CONTROLLER.md`, read-only), especially renumbered or removed actions.
- Tell the user to review the diff, set `Status: approved` themselves, commit, and then build on Linux (the `controller`
  agent implements only an approved contract; `/controller-oracle` runs the result).
- Never change the legacy repo, never set the status to approved, no git command that changes anything, and ignore
  `STATUS.md`.
