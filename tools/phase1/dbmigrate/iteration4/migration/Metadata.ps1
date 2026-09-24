# metadata: builds source-metadata.json, the data about the SQL Server source recorded at export (tools/phase1/dbmigrate/iteration4/CLAUDE.md, "Contracts").
# It is computed from the catalog and the SAME in-memory rows the SQL is rendered from (after credential sanitization), by a code
# path independent of the SQL rendering. It contains no credentials, no personal data, no raw comment text and no SQL text meant
# to be executed. Deterministic except the separate 'run' section (run time).

# Business summaries, as SQL Server text (documentation) - the identifiers are the SOURCE names.
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

# Summary answer cell text: NULL -> empty string, datetime -> 'yyyy-MM-dd HH:mm:ss.fff', bit -> 1/0, else invariant text.
function Format-SummaryValue($V) {
    if ($V -is [System.DBNull] -or $null -eq $V) { return '' }
    if ($V -is [datetime]) { return $V.ToString('yyyy-MM-dd HH:mm:ss.fff', $script:Inv) }
    if ($V -is [bool]) { if ($V) { return '1' } else { return '0' } }
    return [string]::Format($script:Inv, '{0}', $V)
}

function Get-SourceSummaries($Conn) {
    $out = New-Object System.Collections.ArrayList
    foreach ($q in (Get-DomainQueries)) {
        $cmd = $Conn.CreateCommand()
        $cmd.CommandText = $q.Sql
        $reader = $cmd.ExecuteReader()
        $lines = New-Object System.Collections.ArrayList
        try {
            while ($reader.Read()) {
                $vals = for ($i = 0; $i -lt $reader.FieldCount; $i++) { Format-SummaryValue $reader.GetValue($i) }
                [void]$lines.Add(($vals -join '|'))
            }
        } finally { $reader.Close() }
        $arr = [string[]]@($lines)
        [Array]::Sort($arr, [StringComparer]::Ordinal)
        [void]$out.Add([ordered]@{ name = $q.Name; sourceSql = $q.Sql; expectedRows = [string[]]$arr })
    }
    return , $out
}

# Canonical cell: NULL '~'; integer 'i:<decimal>'; boolean 'b:1|0'; timestamp 't:yyyy-MM-dd HH:mm:ss.fff';
# string 's:<lowercase hex of UTF-8>'; binary 'x:<lowercase hex>'; guid 'g:<lowercase text>'.
function Get-CanonicalCell($Value, [string]$Kind) {
    if ($null -eq $Value) { return '~' }
    switch ($Kind) {
        'int' { return "i:$Value" }
        'bit' { return "b:$Value" }
        'datetime' { return 't:' + (ConvertTo-Ts3 $Value) }
        'string' { return 's:' + (ConvertTo-HexUtf8 $Value).ToLowerInvariant() }
        'binary' { return 'x:' + ([string]$Value).ToLowerInvariant() }
        'guid' { return 'g:' + ([string]$Value).ToLowerInvariant() }
    }
    throw (New-MigrationError "No canonical cell form for kind '$Kind'." 2)
}

# SHA-256 over all rows of a table in the canonical form: rows sorted ascending by their canonical text (ordinal), joined by LF,
# hashed as UTF-8. An empty table hashes the empty string.
function Get-TableRowSha256($Table, $Rows) {
    $lines = New-Object System.Collections.ArrayList
    foreach ($row in $Rows) {
        $cells = for ($i = 0; $i -lt $Table.Columns.Count; $i++) { Get-CanonicalCell $row[$i] $Table.Columns[$i].Kind }
        [void]$lines.Add(($cells -join '|'))
    }
    $arr = [string[]]@($lines)
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return Get-Sha256Hex ($script:Utf8NoBom.GetBytes(($arr -join "`n")))
}

function New-SourceMetadata($Config, $Settings, $Model, $RowsByTable, [string]$SchemaText, [string]$DataText, $Summaries, [string]$SourceVersion, [string]$RunTimeUtc) {
    $ci = Pg-CaseInsensitiveSet $Settings
    $tables = New-Object System.Collections.ArrayList
    $totalRows = 0
    foreach ($t in $Model.Tables) {
        $rows = $RowsByTable[$t.Name]
        $totalRows += $rows.Count
        $cols = New-Object System.Collections.ArrayList
        foreach ($c in $t.Columns) {
            $info = Pg-InfoType $c
            [void]$cols.Add([ordered]@{
                sourceName = $c.Name; sourceType = $c.TypeName; kind = $c.Kind
                targetName = (Pg-Column $t.Name $c.Name); targetType = (Pg-ColumnType $c); dataType = $info.DataType; maxLength = $info.MaxLength
                nullable = [bool]$c.Nullable; default = (Pg-DefaultText $c); identity = [bool]$c.IsIdentity
                synthetic = ($c.Name -ceq 'MustResetPassword')
            })
        }
        $fks = New-Object System.Collections.ArrayList
        foreach ($fk in ($t.ForeignKeys | Sort-Object { Pg-FkName $_ })) {
            [void]$fks.Add([ordered]@{
                targetName = (Pg-FkName $fk); sourceName = $fk.Name
                columns = [string[]]@($fk.Columns | ForEach-Object { Pg-Column $fk.Table $_ })
                refTable = (Pg-Table $fk.RefTable); refColumns = [string[]]@($fk.RefColumns | ForEach-Object { Pg-Column $fk.RefTable $_ })
                onDelete = [string]$fk.OnDelete
            })
        }
        $ixs = New-Object System.Collections.ArrayList
        foreach ($ix in ($t.Indexes | Sort-Object { Pg-IndexName $_.TargetName })) {
            $ixCols = New-Object System.Collections.ArrayList
            foreach ($ic in $ix.Columns) {
                $isLower = ($ix.Unique -and $ci.ContainsKey("$($ix.Table)|$($ic.Name)"))
                [void]$ixCols.Add([ordered]@{ column = (Pg-Column $ix.Table $ic.Name); expression = $(if ($isLower) { 'lower(' + (Pg-Column $ix.Table $ic.Name) + ')' } else { $null }); descending = [bool]$ic.Descending })
            }
            [void]$ixs.Add([ordered]@{
                targetName = (Pg-IndexName $ix.TargetName); sourceName = $ix.Name; unique = [bool]$ix.Unique
                columns = [object[]]@($ixCols)
                filter = $(if ($ix.Filter) { Pg-TranslateFilter $ix.Table $ix.Filter } else { $null })
            })
        }
        [void]$tables.Add([ordered]@{
            sourceName = $t.Name; targetName = (Pg-Table $t.Name)
            rowCount = $rows.Count
            identityLast = $(if ($t.Identity -and $null -ne $t.IdentityLast) { [int64]$t.IdentityLast } else { $null })
            rowSha256 = (Get-TableRowSha256 $t $rows)
            columns = [object[]]@($cols)
            primaryKey = [string[]]@($t.PrimaryKey | ForEach-Object { Pg-Column $t.Name $_ })
            foreignKeys = [object[]]@($fks)
            indexes = [object[]]@($ixs)
        })
    }

    # Expectations, computed from the sanitized in-memory rows.
    $users = $Model.Tables | Where-Object { $_.Name -ceq 'Users' } | Select-Object -First 1
    $pw = -1; $st = -1; $mr = -1
    for ($i = 0; $i -lt $users.Columns.Count; $i++) {
        if ($users.Columns[$i].Name -ceq 'PasswordHash') { $pw = $i }
        if ($users.Columns[$i].Name -ceq 'SecurityStamp') { $st = $i }
        if ($users.Columns[$i].Name -ceq 'MustResetPassword') { $mr = $i }
    }
    $urows = $RowsByTable['Users']
    $sanitized = ($mr -ge 0)
    foreach ($r in $urows) { if ($null -ne $r[$pw] -or $null -ne $r[$st] -or $r[$mr] -ne '1') { $sanitized = $false } }
    $activeNames = @{}
    $dupActive = $false
    $nameIdx = 0; $delIdx = 0
    for ($i = 0; $i -lt $users.Columns.Count; $i++) { if ($users.Columns[$i].Name -ceq 'Name') { $nameIdx = $i }; if ($users.Columns[$i].Name -ceq 'DeletedAt') { $delIdx = $i } }
    foreach ($r in $urows) {
        if ($null -eq $r[$delIdx]) {
            $k = ([string]$r[$nameIdx]).ToLowerInvariant()
            if ($activeNames.ContainsKey($k)) { $dupActive = $true }
            $activeNames[$k] = $true
        }
    }

    $map = Pg-Map
    $renameTables = [ordered]@{}
    foreach ($t in $Model.Tables) {
        $colMap = [ordered]@{}
        foreach ($c in $t.Columns) { $colMap[$c.Name] = (Pg-Column $t.Name $c.Name) }
        $renameTables[$t.Name] = [ordered]@{ table = (Pg-Table $t.Name); columns = $colMap }
    }

    $doc = [ordered]@{
        schemaVersion = 1
        meta = [ordered]@{
            iteration = 4
            description = 'Data about the SQL Server source, recorded at export. Sanitized: credential columns are NULL and hash as NULL. Contains no credentials and no raw comment text.'
            source = [ordered]@{ server = [string]$Config.source.server; database = [string]$Config.source.database; version = $SourceVersion }

            minPostgresVersion = 15
            schemaFile = '01-schema.sql'; schemaSha256 = (Get-Sha256Hex ($script:Utf8NoBom.GetBytes($SchemaText)))
            dataFile = '02-data-sanitized.sql'; dataSha256 = (Get-Sha256Hex ($script:Utf8NoBom.GetBytes($DataText)))
            sanitizeCredentials = [bool]$Settings.sanitizeCredentials
        }
        canonicalForm = [ordered]@{
            description = 'Per table: rows sorted ascending by their canonical text (ordinal/byte order), joined by LF, hashed as UTF-8 with SHA-256 (lowercase hex). An empty table hashes the empty string. Cells are joined by | in column order (see tables[].columns).'
            cells = [ordered]@{ null = '~'; integer = 'i:<decimal>'; boolean = 'b:1 or b:0'; timestamp = 't:yyyy-MM-dd HH:mm:ss.fff'; string = 's:<lowercase hex of the UTF-8 bytes>'; binary = 'x:<lowercase hex>'; guid = 'g:<lowercase text>' }
            summaryValues = 'expectedRows are sorted ordinally; cells joined by |; NULL is the empty string; timestamps yyyy-MM-dd HH:mm:ss.fff; booleans 1/0.'
        }
        tables = [object[]]@($tables)
        summaries = [object[]]@($Summaries)
        expectations = [ordered]@{
            totalRows = $totalRows
            usersSanitized = $sanitized
            usersCount = $urows.Count
            noDuplicateActiveUsernamesIgnoringCase = (-not $dupActive)
        }
        renameMap = $renameTables
        excludedTables = [string[]]@('__MigrationHistory')
        knownDifferences = [string[]]@(Pg-KnownDifferences)
        run = [ordered]@{ runTimeUtc = $RunTimeUtc; toolGitCommit = (Get-GitCommit) }
    }
    return (($doc | ConvertTo-Json -Depth 12) -replace "`r`n", "`n") + "`n"
}
