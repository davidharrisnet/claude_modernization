# verify: prove the target database holds the same schema objects and data as the source.
# Read-only on the source; the target is only queried (behaviour tests use a temp copy).

function Get-CellText($Canonical, [string]$Kind) {
    if ($null -eq $Canonical) { return '~' }
    $cls = Get-ExpectedStorageClass $Kind
    # SQLite's hex(blob) is already the canonical hex; everything else is hex of the UTF-8 text.
    if ($Kind -eq 'binary') { return "${cls}:$Canonical" }
    return "${cls}:$(ConvertTo-HexUtf8 $Canonical)"
}

function ConvertFrom-CellText([string]$Cell, [string]$Kind) {
    if ($Cell -eq '~') { return '<NULL>' }
    $hex = $Cell.Substring(2)
    if ($Kind -eq 'binary') { return "0x$hex" }
    return (ConvertFrom-HexUtf8 $hex)
}

function Get-RowsHash($Lines) {
    $arr = [string[]]@($Lines)
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return Get-Sha256Hex ($script:Utf8NoBom.GetBytes(($arr -join "`n")))
}

function Compare-TableRows($Table, $SourceRows, $TargetLines) {
    $cols = $Table.Columns
    $pkIdx = @($Table.PrimaryKey | ForEach-Object { $n = $_; for ($i = 0; $i -lt $cols.Count; $i++) { if ($cols[$i].Name -ceq $n) { $i } } })

    $srcLines = New-Object System.Collections.ArrayList
    $srcByKey = @{}
    foreach ($row in $SourceRows) {
        $cells = for ($i = 0; $i -lt $cols.Count; $i++) { Get-CellText $row[$i] $cols[$i].Kind }
        $line = $cells -join '|'
        [void]$srcLines.Add($line)
        $key = if ($pkIdx.Count -gt 0) { ($pkIdx | ForEach-Object { $cells[$_] }) -join '|' } else { $line }
        $srcByKey[$key] = $cells
    }
    $tgtByKey = @{}
    $malformed = 0
    foreach ($line in $TargetLines) {
        $cells = $line -split '\|'
        if ($cells.Count -ne $cols.Count) { $malformed++; continue }
        $key = if ($pkIdx.Count -gt 0) { ($pkIdx | ForEach-Object { $cells[$_] }) -join '|' } else { $line }
        $tgtByKey[$key] = $cells
    }

    $mismatches = New-Object System.Collections.ArrayList
    $badSourceKeys = @{}
    $total = 0
    $describeKey = {
        param($cells)
        if ($pkIdx.Count -eq 0) { return '(all columns)' }
        (($pkIdx | ForEach-Object { "$($cols[$_].Name)=$(ConvertFrom-CellText $cells[$_] $cols[$_].Kind)" }) -join ', ')
    }
    foreach ($key in ($srcByKey.Keys | Sort-Object { $_ } -CaseSensitive)) {
        $s = $srcByKey[$key]
        if (-not $tgtByKey.ContainsKey($key)) {
            $total++; $badSourceKeys[$key] = $true
            if ($mismatches.Count -lt 20) { [void]$mismatches.Add([pscustomobject]@{ Table = $Table.Name; Key = (& $describeKey $s); Column = '(row)'; Source = 'present'; Target = 'MISSING' }) }
            continue
        }
        $t = $tgtByKey[$key]
        for ($i = 0; $i -lt $cols.Count; $i++) {
            if ($s[$i] -cne $t[$i]) {
                $total++; $badSourceKeys[$key] = $true
                if ($mismatches.Count -lt 20) {
                    $redact = $script:RedactedColumns -contains $cols[$i].Name
                    $sv = if ($redact) { '<redacted>' } else { ConvertFrom-CellText $s[$i] $cols[$i].Kind }
                    $tv = if ($redact) { '<redacted>' } else { ConvertFrom-CellText $t[$i] $cols[$i].Kind }
                    [void]$mismatches.Add([pscustomobject]@{ Table = $Table.Name; Key = (& $describeKey $s); Column = $cols[$i].Name; Source = $sv; Target = $tv })
                }
            }
        }
    }
    foreach ($key in $tgtByKey.Keys) {
        if (-not $srcByKey.ContainsKey($key)) {
            $total++
            if ($mismatches.Count -lt 20) { [void]$mismatches.Add([pscustomobject]@{ Table = $Table.Name; Key = (& $describeKey $tgtByKey[$key]); Column = '(row)'; Source = 'ABSENT'; Target = 'unexpected row' }) }
        }
    }
    $total += $malformed
    if ($malformed -gt 0 -and $mismatches.Count -lt 20) { [void]$mismatches.Add([pscustomobject]@{ Table = $Table.Name; Key = '-'; Column = '(row)'; Source = '-'; Target = "$malformed malformed output line(s)" }) }

    return [pscustomobject]@{
        SourceHash    = (Get-RowsHash $srcLines)
        TargetHash    = (Get-RowsHash $TargetLines)
        MismatchCount = $total
        RowsIdentical = ($SourceRows.Count - $badSourceKeys.Count)
        Mismatches    = @($mismatches)
    }
}

function Format-SourceValue($V) {
    if ($V -is [System.DBNull]) { return '' }
    if ($V -is [datetime]) { return $V.ToString('yyyy-MM-dd HH:mm:ss.fffffff', $script:Inv) }
    if ($V -is [bool]) { if ($V) { return '1' } else { return '0' } }
    return [string]::Format($script:Inv, '{0}', $V)
}

# Business-level summaries. Double-quoted identifiers work unchanged on SQL Server and SQLite.
function Get-DomainQueries {
    return @(
        @{ Name = 'Users by type'; Sql = 'SELECT "Discriminator", COUNT(*) FROM "Users" GROUP BY "Discriminator"' }
        @{ Name = 'Users active vs soft-deleted'; Sql = 'SELECT s, COUNT(*) FROM (SELECT CASE WHEN "DeletedAt" IS NULL THEN ''active'' ELSE ''soft-deleted'' END AS s FROM "Users") x GROUP BY s' }
        @{ Name = 'Users per role'; Sql = 'SELECT r."Name", COUNT(*) FROM "UserRoles" ur JOIN "Roles" r ON r."Id" = ur."RoleId" GROUP BY r."Name"' }
        @{ Name = 'Tickets by state'; Sql = 'SELECT "State", COUNT(*) FROM "Tickets" GROUP BY "State"' }
        @{ Name = 'Tickets assigned vs unassigned'; Sql = 'SELECT s, COUNT(*) FROM (SELECT CASE WHEN "User_Id" IS NULL THEN ''unassigned'' ELSE ''assigned'' END AS s FROM "Tickets") x GROUP BY s' }
        @{ Name = 'Audit events by action'; Sql = 'SELECT "Action", COUNT(*) FROM "AuditLogs" GROUP BY "Action"' }
        @{ Name = 'Comments per ticket (distribution)'; Sql = 'SELECT n, COUNT(*) FROM (SELECT COUNT(*) AS n FROM "Comments" GROUP BY "TicketId") x GROUP BY n' }
        @{ Name = 'Comment and commented-ticket totals'; Sql = 'SELECT (SELECT COUNT(*) FROM "Comments"), (SELECT COUNT(DISTINCT "TicketId") FROM "Comments")' }
        @{ Name = 'Ticket date ranges'; Sql = 'SELECT MIN("SubmittedDate"), MAX("SubmittedDate"), MIN("AssignedDate"), MAX("AssignedDate"), MIN("CompletedDate"), MAX("CompletedDate") FROM "Tickets"' }
        @{ Name = 'Account and audit date ranges'; Sql = 'SELECT (SELECT MIN("CreatedAt") FROM "Users"), (SELECT MAX("CreatedAt") FROM "Users"), (SELECT MIN("Timestamp") FROM "AuditLogs"), (SELECT MAX("Timestamp") FROM "AuditLogs")' }
    )
}

function Invoke-SourceRowsAsText($Conn, [string]$Sql) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Sql
    $reader = $cmd.ExecuteReader()
    $rows = New-Object System.Collections.ArrayList
    try {
        while ($reader.Read()) {
            $vals = for ($i = 0; $i -lt $reader.FieldCount; $i++) { Format-SourceValue $reader.GetValue($i) }
            [void]$rows.Add(($vals -join '|'))
        }
    } finally { $reader.Close() }
    return , $rows
}

function Say([string]$Message, [string]$ForegroundColor) {
    if ($script:VerifyQuiet) { return }
    if ($ForegroundColor) { Write-Host $Message -ForegroundColor $ForegroundColor } else { Write-Host $Message }
}

function Invoke-Verify($Config, [string]$Target, [string]$DbOverride, [string]$ResultsPath, [bool]$Quiet) {
    $script:VerifyQuiet = $Quiet
    $settings = Get-TargetSettings $Config $Target
    $dialect = Get-Dialect $settings.dialect $settings
    $paths = Get-TargetPaths $Config $Target
    $dbFile = & $dialect.TargetId $settings $DbOverride
    if (-not (& $dialect.Exists $settings $dbFile)) { throw (New-MigrationError "Target database not found: $dbFile - run 'import' first." 2) }
    $schemaText = if (Test-Path $paths.Schema) { [System.IO.File]::ReadAllText($paths.Schema, $script:Utf8NoBom) } else { $null }
    $dataText = if (Test-Path $paths.Data) { [System.IO.File]::ReadAllText($paths.Data, $script:Utf8NoBom) } else { $null }

    $conn = Open-SourceConnection $Config.source
    try {
        $model = Get-SourceModel $conn
        $sourceVersion = (Invoke-SourceQuery $conn 'SELECT @@VERSION AS v')[0].v
        $sourceVersion = (($sourceVersion -split "`n")[0]).Trim()

        # 1 + 2: row counts and row-by-row content.
        Say "Comparing data ($($model.Tables.Count) tables) ..."
        $tables = New-Object System.Collections.ArrayList
        foreach ($t in $model.Tables) {
            $srcRows = Read-SourceRows $conn $t
            # Compare against the same sanitized shape Export produced, not the raw source: this both
            # proves the transform (target Users rows must have NULL/NULL/1 to match) and still catches
            # any real drift in every other column, using the same row-by-row comparison as every other
            # table (docs/DATA_MIGRATION.md §5.2). $t is the entry inside $model.Tables, so the added
            # MustResetPassword column is visible to the schema checks run after this loop too.
            if ($settings.sanitizeCredentials) { Protect-SensitiveData $t $srcRows }
            $tgtLines = & $dialect.ReadRows $settings $dbFile $t
            $cmp = Compare-TableRows $t $srcRows $tgtLines
            [void]$tables.Add([pscustomobject]@{
                Name          = $t.Name
                Columns       = $t.Columns.Count
                SourceRows    = $srcRows.Count
                TargetRows    = $tgtLines.Count
                CountPassed   = ($srcRows.Count -eq $tgtLines.Count)
                ContentPassed = ($cmp.MismatchCount -eq 0 -and $cmp.SourceHash -eq $cmp.TargetHash)
                SourceHash    = $cmp.SourceHash
                TargetHash    = $cmp.TargetHash
                MismatchCount = $cmp.MismatchCount
                RowsIdentical = $cmp.RowsIdentical
                Mismatches    = $cmp.Mismatches
            })
        }

        # 4: domain-level summaries, one SQL text on both engines.
        Say 'Comparing business-level summaries ...'
        $domain = New-Object System.Collections.ArrayList
        foreach ($q in (Get-DomainQueries)) {
            $src = @(Invoke-SourceRowsAsText $conn $q.Sql | ForEach-Object { $_ })
            $tgt = @(& $dialect.Query $settings $dbFile $q.Sql | ForEach-Object { $_ })
            $srcSorted = [string[]]@($src); [Array]::Sort($srcSorted, [StringComparer]::Ordinal)
            $tgtSorted = [string[]]@($tgt); [Array]::Sort($tgtSorted, [StringComparer]::Ordinal)
            [void]$domain.Add([pscustomobject]@{
                Name = $q.Name; Sql = $q.Sql
                SourceRows = $srcSorted; TargetRows = $tgtSorted
                Passed = (($srcSorted -join "`n") -ceq ($tgtSorted -join "`n"))
            })
        }
    } finally { $conn.Close() }

    # 3 + 5 + 6: schema objects, integrity, behaviour.
    Say 'Checking schema objects and integrity ...'
    $checks = New-Object System.Collections.ArrayList
    foreach ($c in (& $dialect.SchemaChecks $settings $dbFile $model)) { [void]$checks.Add($c) }
    Say 'Running behaviour tests on a temporary copy ...'
    foreach ($c in (& $dialect.Behaviour $settings $dbFile $model $schemaText $dataText)) { [void]$checks.Add($c) }
    if ($settings.sanitizeCredentials) {
        Say 'Checking credential sanitization ...'
        $bad = [int]([string[]]@(& $dialect.Query $settings $dbFile 'SELECT COUNT(*) FROM "Users" WHERE "PasswordHash" IS NOT NULL OR "SecurityStamp" IS NOT NULL OR "MustResetPassword" <> 1;'))[0]
        [void]$checks.Add((New-Check 'Sanitization' 'Every Users row has PasswordHash/SecurityStamp NULL and MustResetPassword = 1' ($bad -eq 0) "$bad row(s) not sanitized"))
    }

    $countChecks = $tables.Count
    $allPass = ($tables | Where-Object { -not $_.CountPassed -or -not $_.ContentPassed }).Count -eq 0 -and
        ($domain | Where-Object { -not $_.Passed }).Count -eq 0 -and
        ($checks | Where-Object { -not $_.Passed }).Count -eq 0
    $checkTotal = ($tables.Count * 2) + $domain.Count + $checks.Count
    $checkPassed = (@($tables | Where-Object { $_.CountPassed }).Count) + (@($tables | Where-Object { $_.ContentPassed }).Count) + (@($domain | Where-Object { $_.Passed }).Count) + (@($checks | Where-Object { $_.Passed }).Count)
    $rowsSource = ($tables | Measure-Object -Property SourceRows -Sum).Sum
    $rowsIdentical = ($tables | Measure-Object -Property RowsIdentical -Sum).Sum
    if ($null -eq $rowsIdentical) { $rowsIdentical = 0 }

    $schemaHash = if (Test-Path $paths.Schema) { Get-FileSha256 $paths.Schema } else { $null }
    $dataHash = if (Test-Path $paths.Data) { Get-FileSha256 $paths.Data } else { $null }
    $results = [ordered]@{
        Passed  = $allPass
        Meta    = [ordered]@{
            Target = $Target; Dialect = $settings.dialect
            SourceServer = $Config.source.server; SourceDatabase = $Config.source.database; SourceVersion = $sourceVersion
            TargetName = $dialect.DisplayName; TargetClient = (& $dialect.Version $settings); TargetLocation = $dbFile; TargetFingerprint = (& $dialect.Fingerprint $settings $dbFile)
            SanitizeCredentials = [bool]$settings.sanitizeCredentials
            KnownDifferences = @($dialect.KnownDifferences)
            ExportSchemaSha256 = $schemaHash; ExportDataSha256 = $dataHash
            GitCommit = (Get-GitCommit)
            Iteration = $(if ($settings.iteration) { [int]$settings.iteration } else { $null }); IterationTitle = $(if ($settings.iterationTitle) { [string]$settings.iterationTitle } else { $null })
            RunTimeUtc = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss', $script:Inv)
        }
        Summary = [ordered]@{ ChecksTotal = $checkTotal; ChecksPassed = $checkPassed; RowsSource = $rowsSource; RowsVerifiedIdentical = $rowsIdentical; Tables = $tables.Count }
        Tables  = @($tables)
        Checks  = @($checks)
        Domain  = @($domain)
    }
    $resultsFile = if ($ResultsPath) { Resolve-RepoPath $ResultsPath } else { $paths.Results }
    Write-TextFile $resultsFile ((ConvertTo-Json $results -Depth 8) + "`n")

    # console summary
    Say ''
    Say ('{0,-14} {1,8} {2,8}  {3,-6} {4,-8} {5}' -f 'Table', 'Source', 'Target', 'Count', 'Content', 'SHA-256 (rows)')
    foreach ($t in $tables) {
        $cp = if ($t.CountPassed) { 'PASS' } else { 'FAIL' }
        $ct = if ($t.ContentPassed) { 'PASS' } else { 'FAIL' }
        Say ('{0,-14} {1,8} {2,8}  {3,-6} {4,-8} {5}' -f $t.Name, $t.SourceRows, $t.TargetRows, $cp, $ct, $t.SourceHash.Substring(0, 16))
        foreach ($m in $t.Mismatches) { Say "    MISMATCH $($m.Table) [$($m.Key)] $($m.Column): source=$($m.Source) target=$($m.Target)" -ForegroundColor Red }
    }
    foreach ($d in $domain) { Say ('{0,-6} {1}' -f $(if ($d.Passed) { 'PASS' } else { 'FAIL' }), "Summary: $($d.Name)") }
    foreach ($c in $checks) {
        Say ('{0,-6} {1}: {2}{3}' -f $(if ($c.Passed) { 'PASS' } else { 'FAIL' }), $c.Category, $c.Name, $(if (-not $c.Passed -and $c.Detail) { " -> $($c.Detail)" } else { '' }))
    }
    Say ''
    $verdict = if ($allPass) { 'PASSED' } else { 'FAILED' }
    Say "VERIFICATION $verdict - $checkPassed of $checkTotal checks passed; $rowsIdentical of $rowsSource source rows verified identical." -ForegroundColor $(if ($allPass) { 'Green' } else { 'Red' })
    Say "Results: $resultsFile"
    return [pscustomobject]$results
}
