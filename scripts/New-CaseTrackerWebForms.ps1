<#
.SYNOPSIS
    Scaffolds the Phase 1 legacy ASP.NET Web Forms (.NET Framework 4.7.2) project
    (CaseTracker.Web) from scratch, including the Visual Studio workload it needs.

.DESCRIPTION
    Visual Studio's "New Project" wizard does not ship a classic
    "ASP.NET Web Application (.NET Framework)" / Web Forms template in this VS
    version, even with the "ASP.NET and web development" workload installed.
    The MSBuild tooling to build such a project (Microsoft.WebApplication.targets)
    is present once that workload is installed, so this script writes the
    project files by hand instead of relying on the wizard, then verifies the
    result builds.

.PARAMETER RepoRoot
    Directory that will contain the project folder. Defaults to the
    conventional Visual Studio location, $env:USERPROFILE\source\repos.

.PARAMETER ProjectName
    Name of the project folder created under RepoRoot. Defaults to "legacy-app".

.PARAMETER SkipWorkloadInstall
    Skip the Visual Studio workload check/install step (use if you've already
    confirmed the ASP.NET and web development workload is installed).

.EXAMPLE
    .\New-CaseTrackerWebForms.ps1

.EXAMPLE
    .\New-CaseTrackerWebForms.ps1 -RepoRoot "D:\repos" -ProjectName "CaseTrackerLegacy"
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $env:USERPROFILE "source\repos"),
    [string]$ProjectName = "legacy-app",
    [switch]$SkipWorkloadInstall
)

$ErrorActionPreference = "Stop"

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
    # devenv.exe lives at <installationPath>\Common7\IDE\devenv.exe
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
    # This elevates (UAC) and can take several minutes.
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
$webRoot = Join-Path $projectRoot "CaseTracker.Web"
$propertiesRoot = Join-Path $webRoot "Properties"

New-Item -ItemType Directory -Force -Path $propertiesRoot | Out-Null

$projectGuid = "{376F8F94-08FA-416E-80B9-4EA25110A61D}"
$assemblyGuid = "7505f197-792c-40c4-8e71-957e1e3c71c6"

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
    <RootNamespace>CaseTracker.Web</RootNamespace>
    <AssemblyName>CaseTracker.Web</AssemblyName>
    <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
    <MvcBuildViews>false</MvcBuildViews>
    <UseIISExpress>true</UseIISExpress>
    <IISExpressSSLPort />
    <IISExpressAnonymousAuthentication />
    <IISExpressWindowsAuthentication />
    <IISExpressUseClassicPipelineMode />
    <TargetFrameworkProfile />
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
    <Reference Include="System.Web.DynamicData" />
    <Reference Include="System.Web.Entity" />
    <Reference Include="System.Web.ApplicationServices" />
    <Reference Include="System.ComponentModel.DataAnnotations" />
    <Reference Include="System" />
    <Reference Include="System.Data" />
    <Reference Include="System.Core" />
    <Reference Include="System.Data.DataSetExtensions" />
    <Reference Include="System.Web.Extensions" />
    <Reference Include="System.Xml.Linq" />
    <Reference Include="System.Drawing" />
    <Reference Include="System.Web" />
    <Reference Include="System.Xml" />
    <Reference Include="System.Configuration" />
    <Reference Include="System.Web.Services" />
    <Reference Include="System.EnterpriseServices" />
  </ItemGroup>
  <ItemGroup>
    <Compile Include="Default.aspx.cs">
      <DependentUpon>Default.aspx</DependentUpon>
      <SubType>ASPXCodeBehind</SubType>
    </Compile>
    <Compile Include="Default.aspx.designer.cs">
      <DependentUpon>Default.aspx</DependentUpon>
    </Compile>
    <Compile Include="Global.asax.cs">
      <DependentUpon>Global.asax</DependentUpon>
    </Compile>
    <Compile Include="Properties\AssemblyInfo.cs" />
  </ItemGroup>
  <ItemGroup>
    <Content Include="Default.aspx" />
    <Content Include="Global.asax" />
    <Content Include="Web.config" />
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
          <DevelopmentServerPort>44300</DevelopmentServerPort>
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
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "CaseTracker.Web.csproj")

@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.web>
    <compilation debug="true" targetFramework="4.7.2" />
    <httpRuntime targetFramework="4.7.2" />
  </system.web>
</configuration>
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "Web.config")

'<%@ Application Codebehind="Global.asax.cs" Inherits="CaseTracker.Web.Global" Language="C#" %>' |
    Set-Content -Encoding UTF8 (Join-Path $webRoot "Global.asax")

@"
using System;

namespace CaseTracker.Web
{
    public class Global : System.Web.HttpApplication
    {
        protected void Application_Start(object sender, EventArgs e)
        {
        }
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "Global.asax.cs")

@"
<%@ Page Title="Home Page" Language="C#" AutoEventWireup="true" CodeBehind="Default.aspx.cs" Inherits="CaseTracker.Web.Default" %>

<!DOCTYPE html>
<html>
<head runat="server">
    <title>Case Tracker</title>
</head>
<body>
    <form id="form1" runat="server">
        <div>
            <h1>Case Tracker</h1>
            <p>ASP.NET Web Forms (.NET Framework 4.7.2) scaffold is running.</p>
        </div>
    </form>
</body>
</html>
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "Default.aspx")

@"
using System;

namespace CaseTracker.Web
{
    public partial class Default : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
        }
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "Default.aspx.cs")

@"
namespace CaseTracker.Web
{
    public partial class Default
    {
        protected System.Web.UI.HtmlControls.HtmlForm form1;
    }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $webRoot "Default.aspx.designer.cs")

@"
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("CaseTracker.Web")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyProduct("CaseTracker.Web")]
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
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "CaseTracker.Web", "CaseTracker.Web\CaseTracker.Web.csproj", "$projectGuid"
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
"@ | Set-Content -Encoding UTF8 (Join-Path $projectRoot "CaseTracker.sln")

Write-Host "Project files written to: $projectRoot"

# --- 3. Build to verify the toolchain works ---

$msbuildExe = Get-MSBuildPath -InstallPath $vsInstallPath
& $msbuildExe (Join-Path $projectRoot "CaseTracker.sln") /p:Configuration=Debug /v:minimal /nologo
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}

# Clean up build output so the scaffold stays artifact-free
Remove-Item -Recurse -Force (Join-Path $webRoot "bin") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $webRoot "obj") -ErrorAction SilentlyContinue

Write-Host "Done. Open $projectRoot\CaseTracker.sln in Visual Studio to run it with IIS Express."
