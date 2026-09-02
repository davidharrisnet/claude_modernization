# Scaffolding the Phase 1 ASP.NET App (.NET Framework 4.7.2)

Phase 1 allows MVC or Web Forms (see [README.md](../README.md)). Both exist as independent scaffolds, kept side by side for comparison:

- **Web Forms** — `CaseTracker.Web`, via [scripts/New-CaseTrackerWebForms.ps1](../scripts/New-CaseTrackerWebForms.ps1)
- **MVC 5** — `CaseTracker.Mvc`, via [scripts/New-CaseTrackerMvc.ps1](../scripts/New-CaseTrackerMvc.ps1)

## Why scripts, not the VS wizard

This VS install has no classic "ASP.NET Web Application (.NET Framework)" template (Web Forms/MVC) — only the unified template targeting modern .NET (8/9/10). But the MSBuild tooling (`Microsoft.WebApplication.targets`) and the 4.7.2 targeting pack are present once the **ASP.NET and web development** workload is installed, so both projects are hand-authored (old-style `.csproj`) and build-verified instead of wizard-generated.

Both scripts auto-detect the VS install and, if needed, install the workload via:

```powershell
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe" modify `
    --installPath "<vsInstallPath>" `
    --add Microsoft.VisualStudio.Workload.NetWeb `
    --add Microsoft.Net.Component.4.7.2.TargetingPack `
    --includeRecommended --passive --norestart --wait
```

## Web Forms

`New-CaseTrackerWebForms.ps1` writes `CaseTracker.Web` (`.csproj`, `Web.config`, `Global.asax`, `Default.aspx` + code-behind) under `<RepoRoot>\<ProjectName>` (defaults: `%USERPROFILE%\source\repos`, `legacy-app`), then builds it with MSBuild. No NuGet needed — Web Forms is entirely `System.Web`/framework assemblies.

```powershell
.\scripts\New-CaseTrackerWebForms.ps1                                            # defaults
.\scripts\New-CaseTrackerWebForms.ps1 -RepoRoot "D:\repos" -ProjectName "Foo"    # custom
.\scripts\New-CaseTrackerWebForms.ps1 -SkipWorkloadInstall                       # workload already confirmed
```

## MVC 5

`New-CaseTrackerMvc.ps1` writes `CaseTracker.Mvc` (`.csproj`, `Web.config`/`Views\Web.config`, `Global.asax`, `App_Start\RouteConfig.cs`, `Controllers\HomeController.cs`, minimal Razor views) under `<RepoRoot>\<ProjectName>` (defaults: `%USERPROFILE%\source\repos`, `legacy-app-mvc`), then restores and builds.

MVC isn't part of the framework — it's the NuGet package `Microsoft.AspNet.Mvc` (+ `WebPages`/`Razor`/`Microsoft.Web.Infrastructure`). The `.csproj` uses `<PackageReference>` with `<RestoreProjectStyle>PackageReference</RestoreProjectStyle>` (works in non-SDK projects, NuGet 4.6+), so `msbuild /t:restore` fetches everything — no `nuget.exe` needed.

**Gotcha, verified not assumed:** `Microsoft.AspNet.Mvc 5.2.9` produces `System.Web.Mvc.dll` with assembly version `5.2.9.0` — *not* the commonly-assumed fixed `5.2.0.0`. `Web.config`/`Views\Web.config` binding redirects and `factoryType`/`pageBaseType` references need the real version or Razor views fail at runtime (not build time) with "could not load file or assembly". Confirmed via:

```powershell
Get-ChildItem "$env:USERPROFILE\.nuget\packages\microsoft.aspnet.mvc" -Recurse -Filter "System.Web.Mvc.dll" |
    Select -First 1 -Expand FullName | % { [Reflection.AssemblyName]::GetAssemblyName($_).Version }   # -> 5.2.9.0
```

The script hardcodes this as `$MvcAssemblyVersion` — re-verify and update it if `$MvcPackageVersion` changes.

```powershell
.\scripts\New-CaseTrackerMvc.ps1                                                                    # defaults
.\scripts\New-CaseTrackerMvc.ps1 -RepoRoot "D:\repos" -ProjectName "Foo" -MvcPackageVersion "5.2.9"  # custom
.\scripts\New-CaseTrackerMvc.ps1 -SkipWorkloadInstall                                               # workload already confirmed
```

Both scripts are idempotent — re-running overwrites the same content and rebuilds to confirm nothing regressed.
