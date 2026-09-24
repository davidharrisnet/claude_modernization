# Iteration 4 entry point. Normally called through tools\dbmigrate\iteration4\dbmigrate4.cmd:
#   dbmigrate4 export|selftest|report|all --target postgres [--config path] [--out file]
# Exit codes: 0 ok, 1 selftest found differences, 2 config/tool/connection error, 3 refused.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Export.ps1')
. (Join-Path $PSScriptRoot 'Metadata.ps1')
. (Join-Path $PSScriptRoot 'SelfTest.ps1')
. (Join-Path $PSScriptRoot 'Report.ps1')
. (Join-Path $PSScriptRoot 'ExportReport.ps1')

function Show-Usage {
    Write-Host @'
Usage: dbmigrate4 <command> --target <name> [options]

Commands:
  export    SQL Server -> 01-schema.sql, 02-data-sanitized.sql, source-metadata.json (PostgreSQL 15+; credentials sanitized)
  selftest  prove the tooling: repeatable export, no credential in any output, refuses to run unsanitized,
            row counts match the live source, and the report rebuilds byte-identically
  report    build the Word export report (MigrationExportReport4.docx) from source-metadata.json
  all       export, selftest, report

Options:
  --target <name>   target block in the config file (required; postgres)
  --config <path>   config file (default tools\dbmigrate\iteration4\migration\migration.config.json)
  --out <file>      report: output .docx path

Exit codes: 0 ok | 1 selftest differences | 2 config/tool/connection error | 3 refused
'@
}

function Read-CliArgs([object[]]$Tokens) {
    $o = @{ Command = $null; Target = $null; Config = $null; Out = $null }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = [string]$Tokens[$i]
        switch -Regex ($t) {
            '^(--target|-t)$' { $i++; $o.Target = [string]$Tokens[$i]; break }
            '^--config$' { $i++; $o.Config = [string]$Tokens[$i]; break }
            '^--out$' { $i++; $o.Out = [string]$Tokens[$i]; break }
            '^(--help|-h|/\?)$' { $o.Command = 'help'; break }
            '^-' { throw (New-MigrationError "Unknown option '$t'. Run 'dbmigrate4 --help'." 2) }
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
        'selftest' {
            $st = Invoke-SelfTest $config $cli.Target
            if (-not $st.Passed) { $exit = 1 }
        }
        'report' { [void](Invoke-Report $config $cli.Target $cli.Out) }
        'all' {
            [void](Invoke-Export $config $cli.Target $null $false)
            $st = Invoke-SelfTest $config $cli.Target
            [void](Invoke-Report $config $cli.Target $cli.Out)
            if (-not $st.Passed) { $exit = 1 }
        }
        default { throw (New-MigrationError "Unknown command '$($cli.Command)'. Run 'dbmigrate4 --help'." 2) }
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
