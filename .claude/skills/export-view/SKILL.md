---
name: export-view
description: Writes the view hand-off docs/phase2/view/VIEW.md and STYLE.md (Windows only) by reading the legacy Web Forms pages - routes, role access, navigation, controls tied to the approved CONTROLLER.md actions, exact text, accessibility fixes, and the Bootstrap 3.3.7 to 5.3 style mapping; the Linux side builds the Angular project from them once the user approves VIEW.md. Use when the user types /export-view or says "Run export-view".
---

# /export-view

## OS check - first, before anything else

Run `uname -s` with the Bash tool. `MINGW*`, `MSYS*` or `CYGWIN*` means Windows: continue. Anything else (`Linux`,
`Darwin`) means stop: say "export-view runs only on Windows; this machine reports `<output>`" and run nothing.

## Prerequisite - second

Read `docs/phase2/controller/CONTROLLER.md`. If it does not contain the line `Status: approved`, stop: say
"export-view needs an approved CONTROLLER.md (it reports `<the status line>`)" and run nothing. VIEW.md cites its
action numbers, which can still change while it is proposed.

## What it does

Reads the legacy application and rewrites two files from scratch in `docs/phase2/view/`:

- `VIEW.md`: the view contract the Linux side builds the Angular project from.
- `STYLE.md`: the styling hand-off (Bootstrap 3.3.7 to 5.3).

Both are tracked in git, so overwriting them is intended; `git diff` is the review. Run it in this session, not
through an agent, so the page-by-page reasoning stays visible. The decisions behind every rule here are in
`docs/phase2/view/EXPORT_VIEW_DECISIONS.md`; read it first and follow it. If the source contradicts it, follow the
source, say so in the output file and in the report to the user.

**Both files must be self-contained.** The Linux side builds from them alone and never reads the legacy code: never
write "see the legacy page"; write what the page has.

## Source (read only)

The legacy repo `master-antique-repair` is a sibling of this repo (`..\master-antique-repair` from the repository
root). Read, in this fixed order so the page order is stable between runs:

1. `MasterAntiqueRepair/MasterAntiqueRepair/Account/*.aspx` and their `.aspx.cs`, alphabetically.
2. `MasterAntiqueRepair/MasterAntiqueRepair/*.aspx` and their `.aspx.cs`, alphabetically (`Default.aspx` included).
3. `MasterAntiqueRepair/MasterAntiqueRepair/Site.master` and `Site.Master.cs`: the menu per role, the
   anonymous/signed-in areas, log off, the page title format; `Site.Mobile.master` and `ViewSwitcher.ascx` only to
   list them as not carried forward.
4. `MasterAntiqueRepair/MasterAntiqueRepair/App_Code/`: `RepairAuthHelper` (page roles, wrong-role redirect),
   `IdentityModels.cs` (`IsLocalUrl`, `RedirectToReturnUrl`), `UiHelpers` (truncation, status label classes),
   `Startup.Auth.cs` (cookie settings).
5. `MasterAntiqueRepair/MasterAntiqueRepair/Content/Site.css`, and the Bootstrap version from `Content/bootstrap.css`
   and `packages.config`.
6. `docs/phase2/controller/CONTROLLER.md` (approved): the action numbers and server messages.

Base every statement on code you read; never invent a page, control, message or rule. Where the code is unclear, say
so in the file.

## VIEW.md format

1. Title `# View contract: the Phase 2 Angular pages`, a short paragraph naming the sources read and the
   CONTROLLER.md it was built against, and the line `Status: proposed` (always; only the user changes it to
   `approved`).
2. **Navigation**: the menu items per role (label, route, role), the anonymous and signed-in header areas, the brand
   link, the landing route per role after login and after sign-up, the return-URL rule (internal routes only), log
   off, wrong-role and not-signed-in behaviour (per EXPORT_VIEW_DECISIONS §5), the page title format.
3. **Pages**, one section each, in the source order above. For each page:
   - **Route** (kebab-case Angular path; Account pages under `account/`) and the legacy page.
   - **Access**: role(s) from `RepairAuthHelper.RequireRole`, or "anyone".
   - **Layout**: a nested list in markup order - headings, cards (legacy panels), forms and fields (label, input type,
     autocomplete), tables (columns, in order), buttons, modals, collapsible sections, tabs, popovers.
   - **Actions**: each control or list with the CONTROLLER.md action number it calls ("Assign to Me -> action 11").
     A control without an action is listed under **Unclear** on that page.
   - **Text**: page title, labels, button captions, placeholders, empty-list text, client-side validator messages and
     the server messages this page shows, word for word in quotes.
   - **Lists**: page size and choices, sort order, filters.
   - **Dates and numbers**: the legacy format of each displayed value (for example `{0:g}`, `0.0`, `MMM d`).
   - **Accessibility fixes**: the WCAG 2.1 AA issues found on this page (the checklist in EXPORT_VIEW_DECISIONS §8)
     and the fix for each.
   - **Security notes**: unencoded output on this page (`asp:Literal` without `Mode="Encode"`, raw `<%= %>`, HTML
     built in code-behind) and what it carries; any page-specific risk.
4. **Phase 2 additions**: screens no legacy page has, at least the first-login password change (EXPORT_VIEW_DECISIONS
   §6), each marked "(new, not in Phase 1: reason)".
5. **Not carried forward**: a table of legacy pages, controls and scripts left out, each with its reason.
6. **Unused controller actions**: CONTROLLER.md actions no control calls (log off and API-only actions included, with
   the reason), or "none".
7. **Decisions made on this run**: every choice the run made that EXPORT_VIEW_DECISIONS.md does not already cover
   (decision, page, reason), or "none". Make the choice rather than stopping to ask; document it here.
8. **Rules for the Angular build**: the cross-cutting rules from EXPORT_VIEW_DECISIONS that the Linux side must follow
   (guards are presentation only and the server is the access check; interpolation only, no `innerHTML` or
   `bypassSecurityTrust*`; 401 and 403 handling; no CDN scripts; ng-bootstrap rather than Bootstrap's JavaScript;
   session and CSRF follow the security component).

Plain markdown, no endpoint URLs, TypeScript or component code: the Linux side decides those.

## STYLE.md format

No status line (it rides on VIEW.md's approval).

1. Title `# Style hand-off: Bootstrap 3.3.7 to 5.3`, a short paragraph naming the sources read and the legacy
   Bootstrap version found.
2. **Target**: Bootstrap 5.3, Bootstrap Icons and ng-bootstrap, all from npm; no jQuery, no CDN.
3. **Class mapping**: a table of every Bootstrap 3 class the pages and `Site.master` use that changes in 5.3, with its
   usage count and the 5.3 equivalent; then the classes used that do not change. Count the classes from the markup on
   this run (`class` and `CssClass` attributes and classes written in code-behind, such as `UiHelpers`); start from the
   table in EXPORT_VIEW_DECISIONS §7 and add any class it lacks.
4. **Interactive components**: each modal, collapse, popover and tab set, by page, with the ng-bootstrap component that
   replaces it.
5. **Icons**: each glyphicon used, by page, with its Bootstrap Icons name and whether it is decorative or needs a label.
6. **Status badges**: state to badge colour (`UiHelpers.StatusLabelClass`).
7. **Custom CSS**: `Site.css` copied verbatim in a fenced block, then a table of its rules marked keep, adapt or
   obsolete with the reason.
8. **Layout shell**: fixed dark navbar, container, sticky footer with `&copy; {year} - Master Antique Repair`.

## Finish

- Report the number of pages, routes per role, controls per page, unused controller actions, accessibility findings
  and not-carried-forward items, and what changed against the previous files (run `git diff --stat` and
  `git diff docs/phase2/view/`, read-only).
- Report anything that contradicted EXPORT_VIEW_DECISIONS.md and every decision made on this run, so the report's
  §11 table can be updated.
- Tell the user to review the diff, set `Status: approved` in VIEW.md themselves, commit, and then build on Linux. The
  Linux side scaffolds the Angular project only from an approved VIEW.md, and only after the model and controller
  build and pass their tests.
- Never change the legacy repo, never set the status to approved, no git command that changes anything, and ignore
  `STATUS.md`.
