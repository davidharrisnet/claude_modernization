# selftest: proves the export tooling is trustworthy (tools/phase1/dbmigrate/iteration4/CLAUDE.md, "How selftest works"). Needs the live source (LocalDB) and a
# previous 'export'. Writes selftest-results.json next to the other outputs. Returns an object with .Passed.
#   1. Determinism        - a second export is byte-identical (SQL files, and the metadata apart from the run time).
#   2. No credentials     - no credential value read from the source appears in any output file.
#   3. Refuses unsanitized - the tool refuses to export with sanitizeCredentials off (exit 2).
#   4. Row counts         - the metadata's row counts equal a live COUNT(*) per source table; totals match the expectation.
#   5. Report determinism - the export report rebuilds byte-identically from the same metadata.

function Get-MetadataWithoutRunTime([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    # The whole 'run' section (run time, git commit) is the only non-deterministic part of the metadata.
    $text = [regex]::Replace($text, '"runTimeUtc":\s*"[^"]*"', '"runTimeUtc": ""')
    return [regex]::Replace($text, '"toolGitCommit":\s*"[^"]*"', '"toolGitCommit": ""')
}

function Invoke-SelfTest($Config, [string]$Target) {
    $settings = Get-TargetSettings $Config $Target
    $paths = Get-TargetPaths $Config $Target
    foreach ($f in @($paths.Schema, $paths.Data, $paths.Meta)) {
        if (-not (Test-Path $f)) { throw (New-MigrationError "Missing $f - run 'export' first." 2) }
    }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("mar-selftest4-" + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path $work)
    $tests = New-Object System.Collections.ArrayList
    try {
        # 1. determinism, and (2) credentials, both from a second export
        Write-Host 'Self-test 1/5: exporting a second time ...'
        $exp = Invoke-Export $Config $Target $work $true
        $b = @{ Schema = Join-Path $work '01-schema.sql'; Data = Join-Path $work '02-data-sanitized.sql'; Meta = Join-Path $work 'source-metadata.json' }
        $sA = Get-FileSha256 $paths.Schema; $sB = Get-FileSha256 $b.Schema
        $dA = Get-FileSha256 $paths.Data; $dB = Get-FileSha256 $b.Data
        [void]$tests.Add((New-Check 'Determinism' 'Schema export is byte-identical across runs' ($sA -eq $sB) "sha256 $sA vs $sB"))
        [void]$tests.Add((New-Check 'Determinism' 'Data export is byte-identical across runs' ($dA -eq $dB) "sha256 $dA vs $dB"))
        $mA = Get-MetadataWithoutRunTime $paths.Meta; $mB = Get-MetadataWithoutRunTime $b.Meta
        [void]$tests.Add((New-Check 'Determinism' 'Metadata is identical across runs (apart from the run time)' ($mA -ceq $mB) "$($mA.Length) vs $($mB.Length) characters"))

        Write-Host 'Self-test 2/5: scanning every output for credential values ...'
        $creds = @($exp.SourceCredentialValues)
        $leaks = 0
        foreach ($f in @($paths.Schema, $paths.Data, $paths.Meta, $b.Schema, $b.Data, $b.Meta)) {
            $text = [System.IO.File]::ReadAllText($f, $script:Utf8NoBom)
            foreach ($c in $creds) { if ($text.Contains($c)) { $leaks++ } }
        }
        [void]$tests.Add((New-Check 'Sanitization' "No credential value read from the source appears in any output file ($($creds.Count) values checked in 6 files)" (($leaks -eq 0) -and ($creds.Count -gt 0)) "$leaks occurrence(s)"))

        # 3. refuses unsanitized
        Write-Host 'Self-test 3/5: confirming the tool refuses to export unsanitized data ...'
        $bad = ($Config | ConvertTo-Json -Depth 10) | ConvertFrom-Json
        $bad.targets.$Target.sanitizeCredentials = $false
        $refused = $false; $code = $null
        try { [void](Invoke-Export $bad $Target $work $true) } catch { if ($_.Exception -is [MigrationException]) { $refused = $true; $code = $_.Exception.ExitCode } }
        [void]$tests.Add((New-Check 'Sanitization' 'Export refuses to run with sanitizeCredentials off (exit 2)' ($refused -and $code -eq 2) "refused=$refused exit=$code"))

        # 4. counts against the live source
        Write-Host 'Self-test 4/5: comparing row counts with the live source ...'
        $meta = Get-Content $paths.Meta -Raw -Encoding UTF8 | ConvertFrom-Json
        $conn = Open-SourceConnection $Config.source
        try {
            $allMatch = $true; $detail = @()
            foreach ($t in @($meta.tables)) {
                $n = [int](Invoke-SourceQuery $conn "SELECT COUNT(*) AS n FROM [dbo].[$($t.sourceName)]")[0].n
                if ($n -ne [int]$t.rowCount) { $allMatch = $false }
                $detail += "$($t.sourceName)=$n/$($t.rowCount)"
            }
        } finally { $conn.Close() }
        [void]$tests.Add((New-Check 'Counts' 'Row count of every table equals a live COUNT(*) of the source' $allMatch ($detail -join ', ')))
        $total = (@($meta.tables) | Measure-Object -Property rowCount -Sum).Sum
        [void]$tests.Add((New-Check 'Counts' 'Total rows equals the expectation recorded in the metadata' ($total -eq [int]$meta.expectations.totalRows) "$total rows"))
        [void]$tests.Add((New-Check 'Sanitization' 'Metadata expectations hold: users sanitized, no case-insensitive duplicate active usernames' ([bool]$meta.expectations.usersSanitized -and [bool]$meta.expectations.noDuplicateActiveUsernamesIgnoringCase) "usersSanitized=$($meta.expectations.usersSanitized)"))

        # 5. report determinism
        Write-Host 'Self-test 5/5: building the report twice from the same metadata ...'
        $r1 = Join-Path $work 'report1.docx'; $r2 = Join-Path $work 'report2.docx'
        [void](New-ExportReport $paths.Meta $r1); [void](New-ExportReport $paths.Meta $r2)
        $h1 = Get-FileSha256 $r1; $h2 = Get-FileSha256 $r2
        [void]$tests.Add((New-Check 'Determinism' 'The export report rebuilds byte-identically from the same metadata' ($h1 -eq $h2) "sha256 $h1 vs $h2"))
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $passed = (@($tests | Where-Object { -not $_.Passed })).Count -eq 0
    $out = [ordered]@{ Passed = $passed; Tests = @($tests) }
    Write-TextFile (Join-Path $paths.Dir 'selftest-results.json') ((($out | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n")
    foreach ($t in $tests) { Write-Host ('{0,-6} {1}: {2}' -f $(if ($t.Passed) { 'PASS' } else { 'FAIL' }), $t.Category, $t.Name) }
    Write-Host ''
    Write-Host "SELF-TEST $(if ($passed) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($passed) { 'Green' } else { 'Red' })
    return [pscustomobject]$out
}
