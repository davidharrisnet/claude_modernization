<#
.SYNOPSIS
    Scaffolds an ASP.NET MVC 5 (.NET Framework 4.7.2) project (CaseTracker.Mvc)
    as an alternative to the Web Forms scaffold in New-CaseTrackerWebForms.ps1.

.DESCRIPTION
    Same rationale as New-CaseTrackerWebForms.ps1: this VS installation's "New
    Project" wizard has no classic "ASP.NET Web Application (.NET Framework)"
    template, so the project is hand-authored (old-style, non-SDK .csproj)
    instead of wizard-generated.

    Unlike Web Forms, MVC 5 isn't part of the .NET Framework itself — it ships
    as NuGet packages (Microsoft.AspNet.Mvc and its dependencies: WebPages,
    Razor, Microsoft.Web.Infrastructure). The .csproj uses PackageReference
    (supported in non-SDK projects since NuGet 4.6+ / VS2017 15.9+), so
    `msbuild /t:restore` fetches them — no separate nuget.exe needed.

    IMPORTANT: the assembly-version-vs-package-version mismatch. NuGet package
    Microsoft.AspNet.Mvc 5.2.9 produces System.Web.Mvc.dll with assembly
    version 5.2.9.0 (verified via [System.Reflection.AssemblyName]::GetAssemblyName
    against the restored DLL) - do not assume it stays fixed at 5.2.0.0 the way
    older MVC releases did; Microsoft.AspNet.WebPages/Razor 3.2.9 produce
    assembly version 3.0.0.0. If you bump $MvcPackageVersion, re-verify the
    resolved System.Web.Mvc.dll assembly version and update $MvcAssemblyVersion
    (and the binding redirect / Views\Web.config it feeds) to match - a stale
    value here is a runtime "could not load file or assembly" away, not
    something the build will catch.

.PARAMETER RepoRoot
    Directory that will contain the project folder. Defaults to the
    conventional Visual Studio location, $env:USERPROFILE\source\repos.

.PARAMETER ProjectName
    Name of the project folder created under RepoRoot. Defaults to "legacy-app-mvc".

.PARAMETER MvcPackageVersion
    Microsoft.AspNet.Mvc NuGet package version to restore. Defaults to "5.2.9".

.PARAMETER SkipWorkloadInstall
    Skip the Visual Studio workload check/install step (use if you've already
    confirmed the ASP.NET and web development workload is installed).

.EXAMPLE
    .\New-CaseTrackerMvc.ps1

.EXAMPLE
    .\New-CaseTrackerMvc.ps1 -RepoRoot "D:\repos" -ProjectName "CaseTrackerMvc"
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $env:USERPROFILE "source\repos"),
    [string]$ProjectName = "legacy-app-mvc",
    [string]$MvcPackageVersion = "5.2.9",
    [switch]$SkipWorkloadInstall
)

$ErrorActionPreference = "Stop"

# System.Web.Mvc.dll's assembly version for Microsoft.AspNet.Mvc 5.2.9 (verified against the
# restored package, not assumed). Update this if $MvcPackageVersion changes - see .DESCRIPTION.
$MvcAssemblyVersion = "5.2.9.0"
$WebPagesAssemblyVersion = "3.0.0.0"

function Get-VSInstallationPath {
    $devenv = Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio" -Recurse -Filter devenv.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $devenv) {
        $devenv = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio" -Recurse -Filter devenv.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if (-not $devenv) {
        throw "No Visual Studio installation found under Program Files. Install Visual Studio (Community edition is fine) first."
    }
    return $devenv.Directory.Parent.Parent.FullName
}

function Test-AspNetWebWorkloadInstalled {
    param([string]$InstallPath)
    $targets = Get-ChildItem (Join-Path $InstallPath "MSBuild") -Recurse -Filter "Microsoft.WebApplication.targets" -ErrorAction SilentlyContinue
    $targetingPack = Test-Path "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.7.2"
    return ($null -ne $targets) -and $targetingPack
}

function Install-AspNetWebWorkload {
    param([string]$InstallPath)
    $installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
    if (-not (Test-Path $installer)) {
        throw "Visual Studio Installer not found at '$installer'."
    }
    Write-Host "Installing 'ASP.NET and web development' workload + .NET Framework 4.7.2 targeting pack..."
    & $installer modify `
        --installPath "$InstallPath" `
        --add Microsoft.VisualStudio.Workload.NetWeb `
        --add Microsoft.Net.Component.4.7.2.TargetingPack `
        --includeRecommended `
        --passive --norestart --wait
    if ($LASTEXITCODE -ne 0) {
        throw "vs_installer.exe modify failed with exit code $LASTEXITCODE."
    }
}

function Get-MSBuildPath {
    param([string]$InstallPath)
    $msbuild = Get-ChildItem (Join-Path $InstallPath "MSBuild\Current\Bin\amd64\MSBuild.exe") -ErrorAction SilentlyContinue
    if (-not $msbuild) {
        $msbuild = Get-ChildItem (Join-Path $InstallPath "MSBuild\Current\Bin\MSBuild.exe") -ErrorAction SilentlyContinue
    }
    if (-not $msbuild) {
        throw "MSBuild.exe not found under '$InstallPath'."
    }
    return $msbuild.FullName
}

# --- 1. Ensure the ASP.NET Framework web tooling is present ---

$vsInstallPath = Get-VSInstallationPath
Write-Host "Using Visual Studio at: $vsInstallPath"

if (-not $SkipWorkloadInstall) {
    if (Test-AspNetWebWorkloadInstalled -InstallPath $vsInstallPath) {
        Write-Host "ASP.NET web workload + .NET Framework 4.7.2 targeting pack already installed."
    } else {
        Install-AspNetWebWorkload -InstallPath $vsInstallPath
    }
}

# --- 2. Create the project structure ---

$projectRoot = Join-Path $RepoRoot $ProjectName
$appRoot = Join-Path $projectRoot "CaseTracker.Mvc"
$controllersRoot = Join-Path $appRoot "Controllers"
$appStartRoot = Join-Path $appRoot "App_Start"
$viewsRoot = Join-Path $appRoot "Views"
$viewsHomeRoot = Join-Path $viewsRoot "Home"
$viewsSharedRoot = Join-Path $viewsRoot "Shared"
$propertiesRoot = Join-Path $appRoot "Properties"

foreach ($dir in @($controllersRoot, $appStartRoot, $viewsHomeRoot, $viewsSharedRoot, $propertiesRoot)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$projectGuid = "{9B5A50AE-537D-4E24-AFF4-D80F2C8C276E}"
$assemblyGuid = "a20ae3a8-a200-4612-a4e3-4a313a5ee417"

@"
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="`$(MSBuildExtensionsPath)\`$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('`$(MSBuildExtensionsPath)\`$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <PropertyGroup>
    <Configuration Condition=" '`$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '`$(Platform)' == '' ">AnyCPU</Platform>
    <ProductVersion></ProductVersion>
    <SchemaVersion>2.0</SchemaVersion>
    <ProjectGuid>$projectGuid</ProjectGuid>
    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
    <OutputType>Library</OutputType>
    <AppDesignerFolder>Properties</AppDesignerFolder>
    <RootNamespace>CaseTracker.Mvc</RootNamespace>
    <AssemblyName>CaseTracker.Mvc</AssemblyName>
    <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
    <MvcBuildViews>false</MvcBuildViews>
    <UseIISExpress>true</UseIISExpress>
    <IISExpressSSLPort />
    <IISExpressAnonymousAuthentication />
    <IISExpressWindowsAuthentication />
    <IISExpressUseClassicPipelineMode />
    <TargetFrameworkProfile />
    <RestoreProjectStyle>PackageReference</RestoreProjectStyle>
  </PropertyGroup>
  <PropertyGroup Condition=" '`$(Configuration)|`$(Platform)' == 'Debug|AnyCPU' ">
    <DebugSymbols>true</DebugSymbols>
    <DebugType>full</DebugType>
    <Optimize>false</Optimize>
    <OutputPath>bin\</OutputPath>
    <DefineConstants>DEBUG;TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <PropertyGroup Condition=" '`$(Configuration)|`$(Platform)' == 'Release|AnyCPU' ">
    <DebugType>pdbonly</DebugType>
    <Optimize>true</Optimize>
    <OutputPath>bin\</OutputPath>
    <DefineConstants>TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="System" />
    <Reference Include="System.Data" />
    <Reference Include="System.Core" />
    <Reference Include="System.Web.Extensions" />
    <Reference Include="System.Web" />
    <Reference Include="System.Web.Abstractions" />
    <Reference Include="System.Web.Routing" />
    <Reference Include="System.Xml" />
    <Reference Include="System.Configuration" />
    <Reference Include="Microsoft.CSharp" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNet.Mvc" Version="$MvcPackageVersion" />
  </ItemGroup>
  <ItemGroup>
    <Compile Include="Controllers\HomeController.cs" />
    <Compile Include="App_Start\RouteConfig.cs" />
    <Compile Include="Global.asax.cs">
      <DependentUpon>Global.asax</DependentUpon>
    </Compile>
    <Compile Include="Properties\AssemblyInfo.cs" />
  </ItemGroup>
  <ItemGroup>
    <Content Include="Global.asax" />
    <Content Include="Web.config" />
    <Content Include="Views\Web.config" />
    <Content Include="Views\Home\Index.cshtml" />
    <Content Include="Views\Shared\_Layout.cshtml" />
    <Content Include="Views\_ViewStart.cshtml" />
  </ItemGroup>
  <PropertyGroup>
    <VisualStudioVersion Condition="'`$(VisualStudioVersion)' == ''">10.0</VisualStudioVersion>
    <VSToolsPath Condition="'`$(VSToolsPath)' == ''">`$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v`$(VisualStudioVersion)</VSToolsPath>
  </PropertyGroup>
  <Import Project="`$(MSBuildBinPath)\Microsoft.CSharp.targets" />
  <Import Project="`$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'`$(VSToolsPath)' != ''" />
  <ProjectExtensions>
    <VisualStudio>
      <FlavorProperties GUID="{349c5851-65df-11da-9384-00065b846f21}">
        <WebProjectProperties>
          <UseIIS>False</UseIIS>
          <AutoAssignPort>True</AutoAssignPort>
          <DevelopmentServerPort>44301</DevelopmentServerPort>
          <DevelopmentServerVPath>/</DevelopmentServerVPath>
          <IISUrl>
          </IISUrl>
          <NTLMAuthentication>False</NTLMAuthentication>
          <UseCustomServer>False</UseCustomServer>
          <CustomServerUrl>
          </CustomServerUrl>
          <SaveServerSettingsInUserFile>False</SaveServerSettingsInUserFile>
        </WebProjectProperties>
      </FlavorProperties>
    </VisualStudio>
  </ProjectExtensions>
</Project>
"@ | Set-Content -Encoding UTF8 (Join-Path $appRoot "CaseTracker.Mvc.csproj")

@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <configSections>
    <sectionGroup name="system.web.webPages.razor" type="System.Web.WebPages.Razor.Configuration.RazorWebSectionGroup, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35">
      <section name="host" type="System.Web.WebPages.Razor.Configuration.HostSection, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" requirePermission="false" />
      <section name="pages" type="System.Web.WebPages.Razor.Configuration.RazorPagesSection, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" requirePermission="false" />
    </sectionGroup>
  </configSections>

  <system.web>
    <compilation debug="true" targetFramework="4.7.2">
      <assemblies>
        <add assembly="System.Web.Abstractions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" />
        <add assembly="System.Web.Routing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" />
      </assemblies>
    </compilation>
    <httpRuntime targetFramework="4.7.2" />
  </system.web>

  <system.web.webPages.razor>
    <host factoryType="System.Web.Mvc.MvcWebRazorHostFactory, System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" />
    <pages pageBaseType="System.Web.Mvc.WebViewPage">
      <namespaces>
        <add namespace="System.Web.Mvc" />
        <add namespace="System.Web.Mvc.Ajax" />
        <add namespace="System.Web.Mvc.Html" />
        <add namespace="System.Web.Routing" />
      </namespaces>
    </pages>
  </system.web.webPages.razor>

  <runtime>
    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
      <dependentAssembly>
        <assemblyIdentity name="System.Web.Mvc" publicKeyToken="31bf3856ad364e35" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-$MvcAssemblyVersion" newVersion="$MvcAssemblyVersion" />
      </dependentAssembly>
      <dependentAssembly>
        <assemblyIdentity name="System.Web.WebPages" publicKeyToken="31bf3856ad364e35" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-$WebPagesAssemblyVersion" newVersion="$WebPagesAssemblyVersion" />
      </dependentAssembly>
      <dependentAssembly>
        <assemblyIdentity name="System.Web.Razor" publicKeyToken="31bf3856ad364e35" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-$WebPagesAssemblyVersion" newVersion="$WebPagesAssemblyVersion" />
      </dependentAssembly>
      <dependentAssembly>
        <assemblyIdentity name="System.Web.WebPages.Razor" publicKeyToken="31bf3856ad364e35" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-$WebPagesAssemblyVersion" newVersion="$WebPagesAssemblyVersion" />
      </dependentAssembly>
      <dependentAssembly>
        <assemblyIdentity name="Microsoft.Web.Infrastructure" publicKeyToken="31bf3856ad364e35" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
      </dependentAssembly>
    </assemblyBinding>
  </runtime>

  <system.webServer>
    <modules runAllManagedModulesForAllRequests="true" />
  </system.webServer>
</configuration>
"@ | Set-Content -Encoding UTF8 (Join-Path $appRoot "Web.config")

'<%@ Application Codebehind="Global.asax.cs" Inherits="CaseTracker.Mvc.MvcApplication" Language="C#" %>' |
    Set-Content -Encoding UTF8 (Join-Path $appRoot "Global.asax")

@"
using System.Web.Mvc;
using System.Web.Routing;

namespace CaseTracker.Mvc
{
    public class MvcApplication : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            RouteConfig.RegisterRoutes(RouteTable.Routes);
        }
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $appRoot "Global.asax.cs")

@"
using System.Web.Mvc;
using System.Web.Routing;

namespace CaseTracker.Mvc
{
    public class RouteConfig
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.IgnoreRoute("{resource}.axd/{*pathInfo}");

            routes.MapRoute(
                name: "Default",
                url: "{controller}/{action}/{id}",
                defaults: new { controller = "Home", action = "Index", id = UrlParameter.Optional }
            );
        }
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $appStartRoot "RouteConfig.cs")

@"
using System.Web.Mvc;

namespace CaseTracker.Mvc.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            return View();
        }
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $controllersRoot "HomeController.cs")

@"
@{
    Layout = "~/Views/Shared/_Layout.cshtml";
}
"@ | Set-Content -Encoding UTF8 (Join-Path $viewsRoot "_ViewStart.cshtml")

@"
<!DOCTYPE html>
<html>
<head>
    <title>@ViewBag.Title - Case Tracker</title>
</head>
<body>
    <div>
        @RenderBody()
    </div>
</body>
</html>
"@ | Set-Content -Encoding UTF8 (Join-Path $viewsSharedRoot "_Layout.cshtml")

@"
@{
    ViewBag.Title = "Home";
}

<h1>Case Tracker</h1>
<p>ASP.NET MVC 5 (.NET Framework 4.7.2) scaffold is running.</p>
"@ | Set-Content -Encoding UTF8 (Join-Path $viewsHomeRoot "Index.cshtml")

@"
<?xml version="1.0"?>
<configuration>
  <configSections>
    <sectionGroup name="system.web.webPages.razor" type="System.Web.WebPages.Razor.Configuration.RazorWebSectionGroup, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35">
      <section name="host" type="System.Web.WebPages.Razor.Configuration.HostSection, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" requirePermission="false" />
      <section name="pages" type="System.Web.WebPages.Razor.Configuration.RazorPagesSection, System.Web.WebPages.Razor, Version=$WebPagesAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" requirePermission="false" />
    </sectionGroup>
  </configSections>

  <system.web.webPages.razor>
    <host factoryType="System.Web.Mvc.MvcWebRazorHostFactory, System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" />
    <pages pageBaseType="System.Web.Mvc.WebViewPage">
      <namespaces>
        <add namespace="System.Web.Mvc" />
        <add namespace="System.Web.Mvc.Ajax" />
        <add namespace="System.Web.Mvc.Html" />
        <add namespace="System.Web.Routing" />
        <add namespace="CaseTracker.Mvc" />
      </namespaces>
    </pages>
  </system.web.webPages.razor>

  <appSettings>
    <add key="webpages:Enabled" value="false" />
  </appSettings>

  <system.web>
    <httpHandlers>
      <add path="*" verb="*" type="System.Web.HttpNotFoundHandler"/>
    </httpHandlers>

    <pages
        validateRequest="false"
        pageParserFilterType="System.Web.Mvc.ViewTypeParserFilter, System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
        pageBaseType="System.Web.Mvc.ViewPage, System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
        userControlBaseType="System.Web.Mvc.ViewUserControl, System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35">
      <controls>
        <add assembly="System.Web.Mvc, Version=$MvcAssemblyVersion, Culture=neutral, PublicKeyToken=31bf3856ad364e35" namespace="System.Web.Mvc" tagPrefix="mvc" />
      </controls>
    </pages>
  </system.web>

  <system.webServer>
    <handlers>
      <remove name="BlockViewHandler"/>
      <add name="BlockViewHandler" path="*" verb="*" preCondition="integratedMode" type="System.Web.HttpNotFoundHandler" />
    </handlers>
  </system.webServer>
</configuration>
"@ | Set-Content -Encoding UTF8 (Join-Path $viewsRoot "Web.config")

@"
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("CaseTracker.Mvc")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyProduct("CaseTracker.Mvc")]
[assembly: AssemblyCopyright("Copyright (c) 2026")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]
[assembly: ComVisible(false)]
[assembly: Guid("$assemblyGuid")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
"@ | Set-Content -Encoding UTF8 (Join-Path $propertiesRoot "AssemblyInfo.cs")

@"

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 18
VisualStudioVersion = 18.0.00000.0
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CaseTracker.Mvc", "CaseTracker.Mvc\CaseTracker.Mvc.csproj", "$projectGuid"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		$projectGuid.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		$projectGuid.Debug|Any CPU.Build.0 = Debug|Any CPU
		$projectGuid.Release|Any CPU.ActiveCfg = Release|Any CPU
		$projectGuid.Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
"@ | Set-Content -Encoding UTF8 (Join-Path $projectRoot "CaseTracker.Mvc.sln")

Write-Host "Project files written to: $projectRoot"

# --- 3. Restore NuGet packages and build to verify the toolchain works ---

$msbuildExe = Get-MSBuildPath -InstallPath $vsInstallPath
$slnPath = Join-Path $projectRoot "CaseTracker.Mvc.sln"

& $msbuildExe $slnPath /t:Restore /v:minimal /nologo
if ($LASTEXITCODE -ne 0) {
    throw "NuGet restore failed with exit code $LASTEXITCODE."
}

& $msbuildExe $slnPath /p:Configuration=Debug /v:minimal /nologo
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}

# Clean up build output so the scaffold stays artifact-free
Remove-Item -Recurse -Force (Join-Path $appRoot "bin") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $appRoot "obj") -ErrorAction SilentlyContinue

Write-Host "Done. Open $slnPath in Visual Studio to run it with IIS Express."
