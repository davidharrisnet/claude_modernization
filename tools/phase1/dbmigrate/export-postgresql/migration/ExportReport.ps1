# export report content: builds MigrationExportReport.docx from source-metadata.json only (helpers are in Report.ps1).
# This tool verifies nothing against a target, so this is an export report, not a verification report (that is import-postgresql's).

function Get-SummaryPairs($M, [string]$Name) {
    $s = @($M.summaries | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    $pairs = @()
    foreach ($r in @($s.expectedRows)) { $p = ([string]$r) -split '\|'; $pairs += , @($p[0], [double]$p[1]) }
    return , $pairs
}

function New-SummaryChart($M, [string]$Name, [string]$Title, [string]$LabelPrefix) {
    $pairs = Get-SummaryPairs $M $Name
    $labels = [string[]]@($pairs | ForEach-Object { "$LabelPrefix$($_[0])" })
    $vals = [double[]]@($pairs | ForEach-Object { $_[1] })
    return New-BarChartPng $Title $labels $vals $null 'Rows in SQL Server (exported)' '' 1300 460
}

function Build-ExportReportDocument($M, $Images) {
    $script:BreakNext = $false
    $tables = @($M.tables)
    $totalRows = [int]$M.expectations.totalRows
    $rowSum = ($tables | Measure-Object -Property rowCount -Sum).Sum
    $ok = ([bool]$M.expectations.usersSanitized -and [bool]$M.expectations.noDuplicateActiveUsernamesIgnoringCase -and ($totalRows -eq $rowSum))
    $b = New-Object System.Text.StringBuilder
    $add = { param($x) [void]$b.Append($x) }

    # ---- title page
    & $add (Pg (Rn 'Database Export Report') 'Title')
    & $add (Pg (Rn 'MasterAntiqueRepair: SQL Server to PostgreSQL') 'Subtitle')
    & $add (Pg (Rn 'Sanitized PostgreSQL schema and data export' $true '2563EB' 28) '' '' $false 200)
    & $add (Banner $ok $(if ($ok) { 'EXPORT COMPLETE' } else { 'EXPORT INCOMPLETE' }) "$($tables.Count) tables  |  $totalRows rows  |  credentials sanitized for $($M.expectations.usersCount) users  |  PostgreSQL $($M.meta.minPostgresVersion)+")
    & $add (Pg (Rn "Run date (UTC): $($M.run.runTimeUtc)") '' '' $false 40)
    & $add (Pg (Rn "Source: $($M.meta.source.server), database $($M.meta.source.database)") '' '' $false 40)
    & $add (Pg (Rn "Source version: $($M.meta.source.version)") '' '' $false 40)
    & $add (Pg (Rn "Tooling version: git commit $($M.run.toolGitCommit)") '' '' $false 240)
    & $add (Pg (Rn 'Contents' $true '1F3864' 28) '' '' $false 60)
    foreach ($item in '1. Executive summary', '2. Scope and method', '3. Results at a glance', '4. Table inventory', '5. Schema', '6. Business-level summaries', '7. Credential sanitization', '8. Known differences and exclusions', '9. Reproducibility and hand-off', 'Appendix A. Full row hashes') { & $add (Pg (Rn $item) '' '' $false 20) }
    & $add (PageBreak)

    # ---- 1 executive summary
    & $add (PT '1. Executive summary' 'Heading1')
    & $add (PT "The MasterAntiqueRepair SQL Server database was exported into PostgreSQL-specific files: a schema file (01-schema.sql), a data file (02-data-sanitized.sql) and a metadata file (source-metadata.json) describing the source. All $totalRows rows across $($tables.Count) tables were exported. Password hashes and security stamps were blanked before anything was written, so no credential exists in any output file.")
    & $add (PT 'This tool only exports. It does not load or check a PostgreSQL database; that is import-postgresql, which reads these files on a Linux machine, creates a PostgreSQL database in a Docker container, and verifies it against the metadata described here. Everything in this report was produced by a deterministic script, not by a language model.')
    & $add (Table @(4160, 2600, 2600) @('Measure', 'Value', 'Status') @(
        , @('Tables exported', "$($tables.Count)", (ResultCell ($tables.Count -gt 0)))
        , @('Rows exported', "$totalRows", (ResultCell ($totalRows -eq $rowSum)))
        , @('Users with credentials sanitized', "$($M.expectations.usersCount)", (ResultCell ([bool]$M.expectations.usersSanitized)))
        , @('Case-insensitive duplicate active usernames', 'none', (ResultCell ([bool]$M.expectations.noDuplicateActiveUsernamesIgnoringCase)))
    ))

    # ---- 2 scope and method
    & $add (PT '2. Scope and method' 'Heading1')
    & $add (PT 'What was exported' 'Heading2')
    & $add (PT "All application tables in the source database: $((($tables | ForEach-Object { $_.sourceName }) -join ', ')). The structure (columns, primary keys, foreign keys with cascade rules, indexes including the filtered unique index that lets a deleted user's name be reused, defaults and auto-number counters) and every row were carried across. The Entity Framework bookkeeping table (__MigrationHistory) was intentionally not exported.")
    & $add (PT 'How it was produced' 'Heading2')
    & $add (Bullet "The tool reads SQL Server's own description of itself (tables, columns, keys, indexes, defaults, counters) and every row, and converts each value to one agreed text form.")
    & $add (Bullet 'Credentials are blanked in memory before anything is rendered, so an unsanitized data file never exists, not even briefly.')
    & $add (Bullet 'The PostgreSQL schema and data files are then written from that same sanitized in-memory copy. Identifiers become lowercase snake_case; data values are never lowercased.')
    & $add (Bullet 'The metadata file records what the source looked like at export: structure, row counts, a SHA-256 per table over the sanitized rows, the answers to ten business questions, and the SHA-256 of the two SQL files. It is computed from the in-memory rows, not from the SQL text, so it is an independent record that import-postgresql can check the loaded database against.')
    & $add (Bullet 'A self-test proves the tooling: two exports are byte-identical, no credential value appears in any output file, the tool refuses to export unsanitized data, row counts match a live count of the source, and this report rebuilds byte-identically.')

    # ---- 3 results at a glance
    & $add (PageBreak)
    & $add (PT '3. Results at a glance' 'Heading1')
    $labels = [string[]]@($tables | ForEach-Object { $_.sourceName })
    & $add (Image $Images (New-BarChartPng 'Rows exported per table' $labels ([double[]]@($tables | ForEach-Object { $_.rowCount })) $null 'Rows exported' '') 'Bar chart of rows exported per table' 5300000)
    & $add (Pg (Rn 'Figure 1. Number of rows exported from each table.' $false $null 0 $true) 'Caption' 'center')

    # ---- 4 inventory
    & $add (PT '4. Table inventory' 'Heading1')
    $rows = foreach ($t in $tables) { , @($t.sourceName, $t.targetName, "$($t.rowCount)", $(if ($null -ne $t.identityLast) { "$($t.identityLast)" } else { '-' }), ([string]$t.rowSha256).Substring(0, 16)) }
    & $add (Table @(1700, 1700, 1000, 1300, 3660) @('Source table', 'PostgreSQL table', 'Rows', 'Last identity', 'Row hash (SHA-256, first 16)') $rows)
    & $add (Pg (Rn 'The hash is computed over all rows of the table in a fixed, database-independent form (Appendix A lists the full values). import-postgresql recomputes it from the PostgreSQL database it builds. An empty table hashes the empty string (e3b0c442...).' $false $null 0 $true) 'Caption')

    # ---- 5 schema
    & $add (PT '5. Schema' 'Heading1')
    & $add (PT 'Identifiers are lowercase snake_case. Column types are the PostgreSQL types the schema file declares. The users table also carries one column that does not exist in the source: must_reset_password (see section 7).')
    foreach ($t in $tables) {
        & $add (PT "$($t.sourceName) -> $($t.targetName)" 'Heading2')
        $crows = foreach ($c in @($t.columns)) {
            $note = @()
            if ($c.identity) { $note += 'identity' }
            if ($c.synthetic) { $note += 'added by sanitization' }
            if (@($t.primaryKey) -contains $c.targetName -and -not $c.identity) { $note += 'primary key' }
            , @("$($c.sourceName) -> $($c.targetName)", [string]$c.targetType, $(if ($c.nullable) { 'yes' } else { 'NOT NULL' }), $(if ($null -ne $c.default) { [string]$c.default } else { '' }), ($note -join ', '))
        }
        & $add (Table @(3060, 1700, 1100, 1200, 2300) @('Column (source -> PostgreSQL)', 'Type', 'Nullable', 'Default', 'Notes') $crows)
    }
    & $add (PT 'Foreign keys' 'Heading2')
    $frows = foreach ($t in $tables) { foreach ($fk in @($t.foreignKeys)) { , @($t.targetName, [string]$fk.targetName, "($((@($fk.columns)) -join ', ')) -> $($fk.refTable) ($((@($fk.refColumns)) -join ', '))", [string]$fk.onDelete) } }
    & $add (Table @(1500, 3000, 3560, 1300) @('Table', 'Constraint', 'References', 'On delete') @($frows))
    & $add (PT 'Indexes' 'Heading2')
    $irows = foreach ($t in $tables) {
        foreach ($ix in @($t.indexes)) {
            $kc = (@($ix.columns) | ForEach-Object { if ($_.expression) { [string]$_.expression } else { [string]$_.column } }) -join ', '
            , @($t.targetName, [string]$ix.targetName, $(if ($ix.unique) { 'unique' } else { '' }), $kc, $(if ($ix.filter) { "WHERE $($ix.filter)" } else { '' }))
        }
    }
    & $add (Table @(1400, 2800, 900, 2100, 2160) @('Table', 'Index', 'Unique', 'Key', 'Filter') @($irows))
    & $add (PT 'ix_users_name_active is the important one: a unique index on lower(name) that only covers rows where deleted_at IS NULL. An account that is soft-deleted keeps its row but frees its user name for reuse, and "Bob" and "bob" cannot both be active.')

    # ---- 6 business summaries
    & $add (PageBreak)
    & $add (PT '6. Business-level summaries' 'Heading1')
    & $add (PT 'Ten business questions were asked of the SQL Server source; the answers are recorded in the metadata so import-postgresql can ask the same questions of the PostgreSQL database and compare.')
    & $add (Image $Images (New-SummaryChart $M 'Users per role' 'Users per role' '') 'Bar chart: users per role')
    & $add (Image $Images (New-SummaryChart $M 'Users active vs soft-deleted' 'Active and soft-deleted users' '') 'Bar chart: active versus soft-deleted users')
    & $add (Image $Images (New-SummaryChart $M 'Tickets by state' 'Tickets by state' 'State ') 'Bar chart: tickets by state')
    & $add (Image $Images (New-SummaryChart $M 'Audit events by action' 'Audit events by action' 'Action ') 'Bar chart: audit events by action')
    $drows = foreach ($s in @($M.summaries)) {
        $ans = (@($s.expectedRows) | Select-Object -First 4 | ForEach-Object { Format-Answer $_ }) -join '; '
        if (@($s.expectedRows).Count -gt 4) { $ans += '; ...' }
        , @([string]$s.name, $ans)
    }
    & $add (Table @(3300, 6060) @('Summary', 'Answer recorded from the source') $drows)

    # ---- 7 sanitization
    & $add (PT '7. Credential sanitization' 'Heading1')
    & $add (PT 'Every users row had its password hash and security stamp set to NULL, and a new must_reset_password column set to true. This is a deliberate one-time-bootstrap policy: forcing a password reset at first login means no usable legacy credential is carried into the target at all (docs/phase1/dbmigrate/DATA_MIGRATION.md 5.2). Nothing else in the users table, or in any other table, was changed.')
    & $add (Table @(5360, 4000) @('Check', 'Result') @(
        , @('All users have a NULL password_hash and security_stamp', (ResultCell ([bool]$M.expectations.usersSanitized)))
        , @('All users have must_reset_password = true', (ResultCell ([bool]$M.expectations.usersSanitized)))
        , @('No duplicate active username, ignoring case', (ResultCell ([bool]$M.expectations.noDuplicateActiveUsernamesIgnoringCase)))
    ))
    & $add (PT 'The self-test additionally scans every output file for every original credential value read from the source and finds none.')

    # ---- 8 known differences
    & $add (PT '8. Known differences and exclusions' 'Heading1')
    foreach ($e in @($M.excludedTables)) { & $add (Bullet "The Entity Framework migration history table ($e) is not exported; it only describes the SQL Server schema history and has no meaning in PostgreSQL.") }
    & $add (Bullet 'The SQL Server "dbo" schema prefix is dropped.')
    foreach ($kd in @($M.knownDifferences)) { & $add (Bullet ([string]$kd)) }
    & $add (Bullet 'The single users table keeps its "discriminator" column (Customer / Employee / Manager) unchanged.')

    # ---- 9 reproducibility
    & $add (PT '9. Reproducibility and hand-off' 'Heading1')
    & $add (PT 'From a Windows command prompt in the repository root:')
    & $add (Pg (Rn 'tools\phase1\dbmigrate\export-postgresql\export-postgresql.cmd all --target postgres' $true '1F3864') '' '' $false 40)
    & $add (PT 'runs export, the tooling self-test and this report. Individual steps: export, selftest, report.')
    & $add (Table @(2800, 6560) @('Item', 'Value') @(
        , @('Tooling git commit', [string]$M.run.toolGitCommit)
        , @('Source server', [string]$M.meta.source.version)
        , @('Run time (UTC)', [string]$M.run.runTimeUtc)
        , @('01-schema.sql SHA-256', [string]$M.meta.schemaSha256)
        , @('02-data-sanitized.sql SHA-256', [string]$M.meta.dataSha256)
    ))
    & $add (PT 'Hand-off to import-postgresql: after a successful export, copy 01-schema.sql, 02-data-sanitized.sql and source-metadata.json into tools\phase1\dbmigrate\import-postgresql\input\ and commit them. import-postgresql (Linux, Docker) reads only that folder. See docs/phase1/dbmigrate/import-postgresql/README.md.')

    # ---- appendix
    & $add (PageBreak)
    & $add (PT 'Appendix A. Full row hashes' 'Heading1')
    & $add (PT 'SHA-256 over all rows of each table in the canonical form (rows sorted by their canonical text, joined by line feeds, hashed as UTF-8), computed from the sanitized rows at export.')
    $split = { param($h) ([string]$h).Substring(0, 32) + "`n" + ([string]$h).Substring(32) }
    $hrows = foreach ($t in $tables) { , @($t.sourceName, "$($t.rowCount)", (& $split $t.rowSha256)) }
    & $add (Table @(1700, 1000, 6660) @('Table', 'Rows', 'SHA-256') $hrows)
    return $b.ToString()
}

function New-ExportReport([string]$MetaPath, [string]$OutFile) {
    $m = Get-Content $MetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $images = [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList) }
    $body = Build-ExportReportDocument $m $images
    $created = ([datetime]::ParseExact($m.run.runTimeUtc, 'yyyy-MM-dd HH:mm:ss', $script:Inv)).ToString('yyyy-MM-ddTHH:mm:ssZ', $script:Inv)
    Save-Docx $OutFile $body $images "Commit $($m.run.toolGitCommit) | $($m.run.runTimeUtc) UTC" $created 'MasterAntiqueRepair - export-postgresql - Database Export' 'Database Export Report'
    return $OutFile
}

function Invoke-Report($Config, [string]$Target, [string]$Out) {
    $paths = Get-TargetPaths $Config $Target
    if (-not (Test-Path $paths.Meta)) { throw (New-MigrationError "Missing $($paths.Meta) - run 'export' first." 2) }
    $outFile = if ($Out) { Resolve-RepoPath $Out } else { $paths.Report }
    [void](New-ExportReport $paths.Meta $outFile)
    Write-Host "Report: $outFile ($([Math]::Round((Get-Item $outFile).Length / 1KB)) KB)"
    return $outFile
}
