# MasterAntiqueRepair (Phase 1 legacy app)

The actual Phase 1 legacy build lives **outside this repo**, at `../aspnet/master-antique-repair` (i.e. `%USERPROFILE%\Documents\dev\aspnet\master-antique-repair` — a sibling of `asp_modernization`, not under `%USERPROFILE%\source\repos`). It supersedes the `CaseTracker` Web Forms/MVC scaffolds described in [ASPNET.md](ASPNET.md) as the real Phase 1 domain project; those scripts may still be useful as a from-scratch scaffolding reference, but `MasterAntiqueRepair` is the one being built out.

It's its own git repo with its own `CLAUDE.md`/`README.md` — read those there for full detail. Notes below are a summary for this repo's context.

## What it is

An ASP.NET **Web Forms "Website" project** (classic pre-2010 project type, no `.csproj`, `packages.config` NuGet), originally scaffolded from Visual Studio's template as "PizzaGo" and fully renamed to `MasterAntiqueRepair` (folder, `.sln`, C# namespace, LocalDB catalog name). Domain: an antique repair shop — not yet built out (see Status below).

Two projects in the solution:
- **`MasterAntiqueRepair`** — the Website project itself. No central entry point; code-behind (`*.aspx.cs`) compiled per-page. Shared C# goes in `App_Code/`.
- **`MasterAntiqueRepairData`** — a real Class Library (has a `.csproj`), holding EF6 `DbContext`/entity classes that need Code First Migrations. Required as a separate project because EF6 migrations tooling (`Enable-Migrations`/`Add-Migration`/`Update-Database`) doesn't work directly against a classic Website Project (`Get-Project` reports `Type: Web Site`, and the PowerShell tooling needs real MSBuild project properties).

Both target .NET Framework 4.7.2 and must stay on the **exact same EF version** (currently EntityFramework 6.5.1) across both projects' `packages.config` — a mismatch breaks the migrations tooling.

## Data / auth

- LocalDB via EF6 Code First, `DefaultConnection` in `Web.config` → `(LocalDb)\MSSQLLocalDB`, `.mdf` auto-created in `App_Data/` on first use (`CreateDatabaseIfNotExists`).
- Authentication was refactored off ASP.NET Identity's `UserManager`/`ApplicationUser` onto the domain model directly (`Customer`/`Employee`/`Manager` in `MasterAntiqueRepairData`): PBKDF2 password hashing (`Rfc2898DeriveBytes`, 10k iterations, per-password salt) instead of `Microsoft.AspNet.Identity.PasswordHasher`, sign-in still goes through the existing OWIN cookie middleware (`DefaultAuthenticationTypes.ApplicationCookie`) so the cookie transport didn't need to change. The old Identity classes (`ApplicationUser`, `ApplicationDbContext`, `UserManager`, external-login pages) are left in place but unused.
- Public `Register.aspx` only creates `Customer` accounts today; `Employee`/`Manager` provisioning isn't wired up yet.
- `TestDbContext`/`TestItem`/`User` in `MasterAntiqueRepairData` are a scratch proof-of-concept for the migrations workflow (exercised by `TestEF.aspx`) — expected to be replaced once the real domain entities (Requests/Assignees/Status History-equivalent for antique repair) are added.

## Status (as of last review)

No domain functionality built yet — `Default.aspx`/`About.aspx`/`Contact.aspx` are still the unmodified VS template scaffold. What exists so far is infrastructure: project renaming, LocalDB + EF6 migrations set up (including the separate class-library workaround), and the domain-backed auth refactor. The Phase 1 functional requirements from [README.md](../README.md) (3–4 related entities, CRUD, 3+ state workflow, list/search view with filtering and pagination, workflow state-change logging) are still outstanding.

## Known gotchas (see the project's own README.md for full detail)

- Fresh clone/restore can fail with missing `Bin/roslyn/csc.exe` or an `microsoft.aspnet.web.optimization.webforms.dll` auto-refresh error — NuGet restore doesn't run packages' `install.ps1`. Fix: `Update-Package Microsoft.CodeDom.Providers.DotNetCompilerPlatform -reinstall` then `Install-Package Microsoft.AspNet.Web.Optimization.WebForms -Version 1.1.3` in Package Manager Console.
- EF6 migrations PowerShell tooling invokes `msbuild.exe` by bare name — needs MSBuild's directory on `PATH`, and Visual Studio must be restarted after adding it.
- `Add-Migration`/`Update-Database` must be run with **Default project** set to `MasterAntiqueRepairData` in Package Manager Console, not the website project.

## Relevance to this repo

- Keep [CLAUDE.md](../CLAUDE.md)'s note about preserving the workflow-state-change logging format in mind once this app's audit logging is built — that's the Phase 1 baseline Phase 2 will be measured against.
- `docs/ASPNET.md`'s `CaseTracker` scaffold scripts are not what's being built out for Phase 1 delivery; treat them as reference/alternative scaffolding rather than the live project.
