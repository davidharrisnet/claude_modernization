# selftest: proves the tooling itself is trustworthy.
#   1. Determinism    - a second export is byte-identical to the first.
#   2. Independent    - a database imported from the second export has no differences from the first,
#                       judged by the target engine's own tooling (sqldiff for SQLite, CHECKSUM TABLE for MySQL).
#   3. Negative test  - a deliberately damaged copy of the database is detected by verify, and the
#                       exact table / primary key / column is named.
# Writes selftest-results.json next to the other outputs. Returns an object with .Passed.

function Invoke-SelfTest($Config, [string]$Target) {
    $settings = Get-TargetSettings $Config $Target
    $dialect = Get-Dialect $settings.dialect $settings
    $paths = Get-TargetPaths $Config $Target
    $id = & $dialect.TargetId $settings $null
    foreach ($f in @($paths.Schema, $paths.Data)) {
        if (-not (Test-Path $f)) { throw (New-MigrationError "Missing $f - run 'export' and 'import' first." 2) }
    }
    if (-not (& $dialect.Exists $settings $id)) { throw (New-MigrationError "Target database not found: $id - run 'import' first." 2) }
    $schemaText = [System.IO.File]::ReadAllText($paths.Schema, $script:Utf8NoBom)
    $dataText = [System.IO.File]::ReadAllText($paths.Data, $script:Utf8NoBom)

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("mar-selftest-" + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path $work)
    $tests = New-Object System.Collections.ArrayList
    $scratch = New-Object System.Collections.ArrayList
    try {
        # 1. determinism
        Write-Host 'Self-test 1/3: exporting a second time ...'
        $exp = Invoke-Export $Config $Target $work $true
        $schemaB = Get-FileSha256 (Join-Path $work '01-schema.sql'); $dataB = Get-FileSha256 (Join-Path $work '02-data.sql')
        $schemaA = Get-FileSha256 $paths.Schema; $dataA = Get-FileSha256 $paths.Data
        [void]$tests.Add((New-Check 'Determinism' 'Schema export is byte-identical across runs' ($schemaA -eq $schemaB) "sha256 $schemaA vs $schemaB"))
        [void]$tests.Add((New-Check 'Determinism' 'Data export is byte-identical across runs' ($dataA -eq $dataB) "sha256 $dataA vs $dataB"))

        # 2. an independently imported copy must equal the delivered database
        Write-Host "Self-test 2/3: importing the second export and comparing with the target's own tooling ..."
        $second = & $dialect.NewScratchId $settings 'second'
        [void]$scratch.Add($second)
        [void](& $dialect.Import $settings $second ([IO.File]::ReadAllText((Join-Path $work '01-schema.sql'), $script:Utf8NoBom)) ([IO.File]::ReadAllText((Join-Path $work '02-data.sql'), $script:Utf8NoBom)) $true)
        [void]$tests.Add((& $dialect.Diff $settings $id $second $exp.Model))

        # 3. negative test: damage a copy, verify must fail and name the damage
        Write-Host 'Self-test 3/3: damaging a copy and confirming verify detects it ...'
        $damaged = & $dialect.NewScratchId $settings 'damaged'
        [void]$scratch.Add($damaged)
        & $dialect.Clone $settings $id $damaged $schemaText $dataText
        $victim = (& $dialect.Query $settings $damaged 'SELECT "Id" FROM "Comments" ORDER BY "Id" LIMIT 1;' | Select-Object -First 1)
        $gone = (& $dialect.Query $settings $damaged 'SELECT "Id" FROM "Tickets" ORDER BY "Id" DESC LIMIT 1;' | Select-Object -First 1)
        $r = & $dialect.Run $settings $damaged (& $dialect.DamageSql $victim $gone)
        if ($r.ExitCode -ne 0) { throw (New-MigrationError "Could not damage the test copy: $($r.Stderr)" 2) }
        $neg = Invoke-Verify $Config $Target $damaged (Join-Path $work 'negative-results.json') $true
        $commentHit = @($neg.Tables | Where-Object { $_.Name -eq 'Comments' } | ForEach-Object { $_.Mismatches } | Where-Object { $_.Column -eq 'Text' -and $_.Key -eq "Id=$victim" })
        $ticketHit = @($neg.Tables | Where-Object { $_.Name -eq 'Tickets' } | ForEach-Object { $_.Mismatches } | Where-Object { $_.Column -eq '(row)' -and $_.Target -eq 'MISSING' -and $_.Key -eq "Id=$gone" })
        [void]$tests.Add((New-Check 'Negative' 'Damaged copy is reported as FAILED' (-not $neg.Passed) "verify result Passed=$($neg.Passed)"))
        [void]$tests.Add((New-Check 'Negative' 'Altered comment is pinpointed (Comments, Id, Text)' ($commentHit.Count -eq 1) "Comments Id=$victim column Text"))
        [void]$tests.Add((New-Check 'Negative' 'Deleted ticket is pinpointed (Tickets, Id)' ($ticketHit.Count -eq 1) "Tickets Id=$gone"))
    } finally {
        foreach ($s in $scratch) { & $dialect.Remove $settings $s }
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $passed = (@($tests | Where-Object { -not $_.Passed })).Count -eq 0
    $out = [ordered]@{ Passed = $passed; Tests = @($tests) }
    Write-TextFile (Join-Path $paths.Dir 'selftest-results.json') ((ConvertTo-Json $out -Depth 5) + "`n")
    foreach ($t in $tests) { Write-Host ('{0,-6} {1}: {2}' -f $(if ($t.Passed) { 'PASS' } else { 'FAIL' }), $t.Category, $t.Name) }
    Write-Host ''
    Write-Host "SELF-TEST $(if ($passed) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($passed) { 'Green' } else { 'Red' })
    return [pscustomobject]$out
}
