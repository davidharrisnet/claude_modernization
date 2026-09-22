# export: SQL Server -> <outputDir>/<outputSubdir or target>/01-schema.sql + 02-data.sql

function Get-TargetPaths($Config, [string]$Target) {
    $t = Get-TargetSettings $Config $Target
    $subdir = if ($t.outputSubdir) { [string]$t.outputSubdir } else { $Target }
    $outDir = Join-Path (Resolve-RepoPath $Config.outputDir) $subdir
    # Optional reportDir puts the .docx elsewhere (e.g. under docs/); default is the target's output folder.
    $reportDir = if ($t.reportDir) { Resolve-RepoPath ([string]$t.reportDir) } else { $outDir }
    # Each numbered iteration writes MigrationVerificationReport{N}.docx; a target that is not a numbered
    # iteration (e.g. the MySQL extra) writes MigrationVerificationReport-<target>.docx.
    $reportName = if ($t.iteration) { "MigrationVerificationReport$($t.iteration).docx" } else { "MigrationVerificationReport-$Target.docx" }
    $guideName = if ($t.guideFile) { [string]$t.guideFile } else { "DatabaseGuide-$Target.docx" }
    # Sanitized output is named like iteration 3's 02-data-sanitized.sql, so the filename itself
    # says whether it's safe to move/commit rather than relying on a reader already knowing.
    $dataName = if ($t.sanitizeCredentials) { '02-data-sanitized.sql' } else { '02-data.sql' }
    return [pscustomobject]@{
        Dir     = $outDir
        Guide   = Join-Path $reportDir $guideName
        Schema  = Join-Path $outDir '01-schema.sql'
        Data    = Join-Path $outDir $dataName
        Log     = Join-Path $outDir 'import-log.txt'
        Results = Join-Path $outDir 'verification-results.json'
        Report  = Join-Path $reportDir $reportName
    }
}

function Invoke-Export($Config, [string]$Target, [string]$OutDir, [bool]$Quiet) {
    $settings = Get-TargetSettings $Config $Target
    $dialect = Get-Dialect $settings.dialect $settings
    $paths = Get-TargetPaths $Config $Target
    if ($OutDir) {
        $d = Resolve-RepoPath $OutDir
        $paths.Dir = $d; $paths.Schema = Join-Path $d '01-schema.sql'; $paths.Data = Join-Path $d '02-data.sql'
    }
    $conn = Open-SourceConnection $Config.source
    try {
        $model = Get-SourceModel $conn
        $rowsByTable = @{}
        foreach ($t in $model.Tables) { $rowsByTable[$t.Name] = Read-SourceRows $conn $t }
    } finally { $conn.Close() }

    # Sanitize in memory, before anything is rendered to SQL text - a raw, unsanitized 02-data.sql
    # never exists as a file at all, not even transiently (docs/DATA_MIGRATION.md §5.2).
    if ($settings.sanitizeCredentials) {
        foreach ($t in $model.Tables) { Protect-SensitiveData $t $rowsByTable[$t.Name] }
    }

    $schema = & $dialect.RenderSchema $model $Config.source.database
    $data = & $dialect.RenderData $model $rowsByTable
    Write-TextFile $paths.Schema $schema
    Write-TextFile $paths.Data $data

    if (-not $Quiet) {
        Write-Host "Exported $($model.Tables.Count) tables:"
        foreach ($t in $model.Tables) { Write-Host ("  {0,-12} {1,6} rows" -f $t.Name, $rowsByTable[$t.Name].Count) }
        Write-Host "  $($paths.Schema)"
        Write-Host "  $($paths.Data)"
    }
    return [pscustomobject]@{ Model = $model; Rows = $rowsByTable; Paths = $paths }
}
