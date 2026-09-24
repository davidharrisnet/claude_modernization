# import: run the exported SQL into the target database

function Invoke-Import($Config, [string]$Target, [bool]$Recreate) {
    $settings = Get-TargetSettings $Config $Target
    $dialect = Get-Dialect $settings.dialect $settings
    $paths = Get-TargetPaths $Config $Target
    foreach ($f in @($paths.Schema, $paths.Data)) {
        if (-not (Test-Path $f)) { throw (New-MigrationError "Missing $f - run 'export' first." 2) }
    }
    $id = & $dialect.TargetId $settings $null
    $schema = [System.IO.File]::ReadAllText($paths.Schema, $script:Utf8NoBom)
    $data = [System.IO.File]::ReadAllText($paths.Data, $script:Utf8NoBom)
    $log = & $dialect.Import $settings $id $schema $data $Recreate
    $lines = @("client: $(& $dialect.Version $settings)", "target: $id") + @($log)
    Write-TextFile $paths.Log (($lines -join "`n") + "`n")
    Write-Host "Imported into $($dialect.DisplayName) target $id"
    foreach ($l in $log) { Write-Host "  $l" }
    return $id
}