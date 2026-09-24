# Database migration entry point. Normally called through tools\phase1\dbmigrate\iteration1\dbmigrate.cmd:
#   dbmigrate export|import|verify|report|all --target sqlite [--config path] [--recreate] [--db file] [--out file]
# Exit codes: 0 ok, 1 verification found differences, 2 config/tool/connection error, 3 refused.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Export.ps1')
. (Join-Path $PSScriptRoot 'Import.ps1')
. (Join-Path $PSScriptRoot 'Verify.ps1')
. (Join-Path $PSScriptRoot 'SelfTest.ps1')
. (Join-Path $PSScriptRoot 'Report.ps1')
. (Join-Path $PSScriptRoot 'Guide.ps1')

function Show-Usage {
    Write-Host @'
Usage: dbmigrate <command> --target <name> [options]

Commands:
  export    SQL Server -> <outputDir>\<target>\01-schema.sql, 02-data.sql
  import    load the exported SQL into the target database
  verify    compare source and target, write verification-results.json (exit 1 on differences)
  selftest  prove the tooling: repeatable export, sqldiff, and a damaged copy must be caught
  report    build the Word report from verification-results.json
  guide     build the Word database guide for a sqlite target (needs an existing database file)
  all       export, import (--recreate implied), verify, selftest, report, guide (sqlite targets)

Options:
  --target <name>   target block in the config file (required; e.g. sqlite)
  --config <path>   config file (default tools\phase1\dbmigrate\iteration1\migration\migration.config.json)
  --recreate        replace an existing target database on import
  --db <file>       verify: check this database file instead of the configured one
  --out <file>      report: output .docx path

Exit codes: 0 ok | 1 verification differences | 2 config/tool/connection error | 3 refused
'@
}

function Read-CliArgs([object[]]$Tokens) {
    $o = @{ Command = $null; Target = $null; Config = $null; Recreate = $false; Db = $null; Out = $null }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = [string]$Tokens[$i]
        switch -Regex ($t) {
            '^(--target|-t)$' { $i++; $o.Target = [string]$Tokens[$i]; break }
            '^--config$' { $i++; $o.Config = [string]$Tokens[$i]; break }
            '^--db$' { $i++; $o.Db = [string]$Tokens[$i]; break }
            '^--out$' { $i++; $o.Out = [string]$Tokens[$i]; break }
            '^--recreate$' { $o.Recreate = $true; break }
            '^(--help|-h|/\?)$' { $o.Command = 'help'; break }
            '^-' { throw (New-MigrationError "Unknown option '$t'. Run 'dbmigrate --help'." 2) }
            default { if (-not $o.Command) { $o.Command = $t } else { throw (New-MigrationError "Unexpected argument '$t'." 2) } }
        }
    }
    return $o
}

try {
    $cli = Read-CliArgs $args
    if (-not $cli.Command -or $cli.Command -eq 'help') { Show-Usage; exit 0 }
    if (-not $cli.Target) { throw (New-MigrationError "--target is required." 2) }
    $config = Get-MigrationConfig $cli.Config
    [void](Get-TargetSettings $config $cli.Target)

    $exit = 0
    switch ($cli.Command) {
        'export' { [void](Invoke-Export $config $cli.Target $null $false) }
        'import' { [void](Invoke-Import $config $cli.Target $cli.Recreate) }
        'verify' {
            $res = Invoke-Verify $config $cli.Target $cli.Db $null $false
            if (-not $res.Passed) { $exit = 1 }
        }
        'selftest' {
            $st = Invoke-SelfTest $config $cli.Target
            if (-not $st.Passed) { $exit = 1 }
        }
        'report' { [void](Invoke-Report $config $cli.Target $cli.Out) }
        'guide' { [void](Invoke-Guide $config $cli.Target $cli.Out) }
        'all' {
            [void](Invoke-Export $config $cli.Target $null $false)
            [void](Invoke-Import $config $cli.Target $true)
            $res = Invoke-Verify $config $cli.Target $null $null $false
            $st = Invoke-SelfTest $config $cli.Target
            [void](Invoke-Report $config $cli.Target $cli.Out)
            if ($config.targets.($cli.Target).dialect -eq 'sqlite') { [void](Invoke-Guide $config $cli.Target $null) }
            if (-not $res.Passed -or -not $st.Passed) { $exit = 1 }
        }
        default { throw (New-MigrationError "Unknown command '$($cli.Command)'. Run 'dbmigrate --help'." 2) }
    }
    exit $exit
} catch {
    $ex = $_.Exception
    while ($ex -and $ex -isnot [MigrationException] -and $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -is [MigrationException]) {
        [Console]::Error.WriteLine("ERROR: $($ex.Message)")
        exit $ex.ExitCode
    }
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 2
}
