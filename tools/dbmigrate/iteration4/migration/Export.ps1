# export: SQL Server -> <outputDir>\<outputSubdir>\01-schema.sql, 02-data-sanitized.sql, source-metadata.json (PostgreSQL 15+).
# Iteration 4 is export only: nothing here talks to a PostgreSQL server.

function Get-TargetPaths($Config, [string]$Target) {
    $t = Get-TargetSettings $Config $Target
    $subdir = if ($t.outputSubdir) { [string]$t.outputSubdir } else { $Target }
    $outDir = Join-Path (Resolve-RepoPath $Config.outputDir) $subdir
    $reportDir = if ($t.reportDir) { Resolve-RepoPath ([string]$t.reportDir) } else { $outDir }
    $reportName = if ($t.reportFile) { [string]$t.reportFile } else { "MigrationExportReport-$Target.docx" }
    return [pscustomobject]@{
        Dir = $outDir
        Schema = Join-Path $outDir '01-schema.sql'
        Data = Join-Path $outDir '02-data-sanitized.sql'
        Meta = Join-Path $outDir 'source-metadata.json'
        Report = Join-Path $reportDir $reportName
    }
}

# Every original credential value found in the source rows, kept IN MEMORY ONLY for the self-test's "no credential in any
# output file" check. Never written anywhere.
function Get-SourceCredentialValues($Model, $RowsByTable) {
    $vals = New-Object System.Collections.ArrayList
    foreach ($t in $Model.Tables) {
        if ($t.Name -cne 'Users') { continue }
        for ($i = 0; $i -lt $t.Columns.Count; $i++) {
            if ($script:RedactedColumns -contains $t.Columns[$i].Name) {
                foreach ($r in $RowsByTable[$t.Name]) { if ($null -ne $r[$i] -and "$($r[$i])".Length -ge 8) { [void]$vals.Add([string]$r[$i]) } }
            }
        }
    }
    return , $vals
}

function Invoke-Export($Config, [string]$Target, [string]$OutDir, [bool]$Quiet) {
    $settings = Get-TargetSettings $Config $Target
    # Credentials are always sanitized: this tool refuses to write anything else (docs/DATA_MIGRATION.md 5.2).
    if (-not $settings.sanitizeCredentials) { throw (New-MigrationError "Target '$Target' has sanitizeCredentials off. Iteration 4 refuses to export unsanitized data; set it to true." 2) }
    $dialect = Get-Dialect $settings.dialect $settings
    $paths = Get-TargetPaths $Config $Target
    if ($OutDir) {
        $d = Resolve-RepoPath $OutDir
        $paths.Dir = $d; $paths.Schema = Join-Path $d '01-schema.sql'; $paths.Data = Join-Path $d '02-data-sanitized.sql'; $paths.Meta = Join-Path $d 'source-metadata.json'
    }
    $conn = Open-SourceConnection $Config.source
    try {
        $model = Get-SourceModel $conn
        $rowsByTable = @{}
        foreach ($t in $model.Tables) { $rowsByTable[$t.Name] = Read-SourceRows $conn $t }
        $sourceVersion = (Invoke-SourceQuery $conn 'SELECT @@VERSION AS v')[0].v
        $sourceVersion = (($sourceVersion -split "`n")[0]).Trim()
        $summaries = Get-SourceSummaries $conn
    } finally { $conn.Close() }

    $credentials = Get-SourceCredentialValues $model $rowsByTable

    # Sanitize in memory, before anything is rendered: a raw, unsanitized data file never exists, not even transiently.
    foreach ($t in $model.Tables) { Protect-SensitiveData $t $rowsByTable[$t.Name] }

    $schema = & $dialect.RenderSchema $model $Config.source.database $settings
    $data = & $dialect.RenderData $model $rowsByTable
    $runTime = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss', $script:Inv)
    $metaJson = New-SourceMetadata $Config $settings $model $rowsByTable $schema $data $summaries $sourceVersion $runTime
    Write-TextFile $paths.Schema $schema
    Write-TextFile $paths.Data $data
    Write-TextFile $paths.Meta $metaJson

    if (-not $Quiet) {
        Write-Host "Exported $($model.Tables.Count) tables (credentials sanitized):"
        foreach ($t in $model.Tables) { Write-Host ("  {0,-12} {1,6} rows" -f $t.Name, $rowsByTable[$t.Name].Count) }
        Write-Host "  $($paths.Schema)"
        Write-Host "  $($paths.Data)"
        Write-Host "  $($paths.Meta)"
    }
    return [pscustomobject]@{ Model = $model; Rows = $rowsByTable; Paths = $paths; SourceCredentialValues = $credentials }
}
