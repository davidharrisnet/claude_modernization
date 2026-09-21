# MySQL 8.x dialect. The server runs in a Docker container (runner.mode = docker); the mysql client
# is executed with `docker exec -i`, SQL piped in as UTF-8 on stdin. Dot-sourced by Get-Dialect;
# helpers are global: so the scriptblocks returned from New-Dialect can find them later.

function global:Mysql-Quote([string]$Name) {
    if ($Name.Length -gt 64) { throw (New-MigrationError "Identifier '$Name' is longer than MySQL's 64-character limit." 2) }
    return '`' + $Name.Replace('`', '``') + '`'
}

$global:MysqlDefaultCollation = 'utf8mb4_0900_as_ci'

# SQL Server collation -> MySQL collation. CI_AS (the SQL Server default) becomes the accent-sensitive,
# case-insensitive utf8mb4_0900_as_ci. Anything else is refused rather than guessed.
function global:Mysql-Collation($Col) {
    $c = $Col.Collation
    if (-not $c) { return $global:MysqlDefaultCollation }
    if ($c -match '_CI_AS') { return 'utf8mb4_0900_as_ci' }
    if ($c -match '_CS_AS') { return 'utf8mb4_0900_as_cs' }
    throw (New-MigrationError "No MySQL collation mapping for SQL Server collation '$c' (column $($Col.Name))." 2)
}

# Returns @{ Ddl; Info } - the CREATE TABLE spelling and what information_schema.column_type reports back.
function global:Mysql-Type($Col) {
    switch ($Col.Kind) {
        'int' {
            switch ($Col.TypeName) {
                'bigint' { return @{ Ddl = 'BIGINT'; Info = 'bigint' } }
                'smallint' { return @{ Ddl = 'SMALLINT'; Info = 'smallint' } }
                'tinyint' { return @{ Ddl = 'TINYINT UNSIGNED'; Info = 'tinyint unsigned' } }
                default { return @{ Ddl = 'INT'; Info = 'int' } }
            }
        }
        'bit' { return @{ Ddl = 'TINYINT(1)'; Info = 'tinyint(1)' } }
        'datetime' { return @{ Ddl = 'DATETIME(6)'; Info = 'datetime(6)' } }
        'binary' { return @{ Ddl = 'LONGBLOB'; Info = 'longblob' } }
        'guid' { return @{ Ddl = 'CHAR(36)'; Info = 'char(36)' } }
        'string' {
            if ($Col.Length -lt 0 -or $Col.TypeName -in 'ntext', 'text') { return @{ Ddl = 'LONGTEXT'; Info = 'longtext' } }
            return @{ Ddl = "VARCHAR($($Col.Length))"; Info = "varchar($($Col.Length))" }
        }
    }
    throw (New-MigrationError "No MySQL type for kind '$($Col.Kind)'" 2)
}

# [col] IS [NOT] NULL (AND-ed) only; anything else is an error so a rule is never silently dropped.
function global:Mysql-FilterPredicates([string]$Filter) {
    $preds = New-Object System.Collections.ArrayList
    foreach ($p in ($Filter.Trim() -split '\s+AND\s+', 0, 'IgnoreCase')) {
        $q = $p.Trim()
        while ($q.StartsWith('(') -and $q.EndsWith(')')) { $q = $q.Substring(1, $q.Length - 2).Trim() }
        if ($q -notmatch '^\[(\w+)\]\s+IS\s+(NOT\s+)?NULL$') {
            throw (New-MigrationError "Cannot translate index filter '$Filter' to MySQL - extend Mysql-FilterPredicates." 2)
        }
        [void]$preds.Add([pscustomobject]@{ Column = $Matches[1]; Negated = [bool]$Matches[2] })
    }
    return , $preds
}

function global:Mysql-FilterSql($Preds) {
    return (($Preds | ForEach-Object { "$(Mysql-Quote $_.Column) IS $(if ($_.Negated) { 'NOT ' })NULL" }) -join ' AND ')
}

function global:Mysql-RenderSchema($Model, [string]$SourceName) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("-- MasterAntiqueRepair schema for MySQL 8 (generated from SQL Server catalog '$SourceName')`n")
    [void]$sb.Append("SET NAMES utf8mb4;`n`n")
    foreach ($t in $Model.Tables) {
        $defs = New-Object System.Collections.ArrayList
        foreach ($c in $t.Columns) {
            $type = Mysql-Type $c
            $d = "$(Mysql-Quote $c.Name) $($type.Ddl)"
            if ($c.Kind -eq 'string' -or $c.Kind -eq 'guid') { $d += " CHARACTER SET utf8mb4 COLLATE $(Mysql-Collation $c)" }
            $d += $(if ($c.Nullable) { ' NULL' } else { ' NOT NULL' })
            if ($null -ne $c.Default) { $d += " DEFAULT $($c.Default)" }
            if ($c.IsIdentity) {
                if ($t.PrimaryKey.Count -ne 1 -or $t.PrimaryKey[0] -ne $c.Name -or $c.Kind -ne 'int') {
                    throw (New-MigrationError "Identity column $($t.Name).$($c.Name) is not a single-column integer primary key - not supported." 2)
                }
                $d += ' AUTO_INCREMENT'
            }
            if ($c.Kind -eq 'bit') { $d += " CHECK ($(Mysql-Quote $c.Name) IN (0, 1))" }
            [void]$defs.Add($d)
        }
        if ($t.PrimaryKey.Count -gt 0) { [void]$defs.Add("PRIMARY KEY ($(($t.PrimaryKey | ForEach-Object { Mysql-Quote $_ }) -join ', '))") }
        # Indexes go in the table body ahead of the foreign keys so MySQL uses them for the FKs instead of
        # silently creating (and later dropping) implicit ones.
        foreach ($ix in ($t.Indexes | Sort-Object { $_.TargetName })) {
            $name = Mysql-Quote $ix.TargetName
            if ($ix.Filter) {
                if (-not $ix.Unique) { throw (New-MigrationError "Filtered non-unique index '$($ix.Name)' is not supported for MySQL." 2) }
                # MySQL has no partial indexes. A functional unique index over IF(filter, column, NULL)
                # gives the same rule: rows outside the filter yield NULLs, which never collide.
                $cond = Mysql-FilterSql (Mysql-FilterPredicates $ix.Filter)
                $parts = ($ix.Columns | ForEach-Object { "(IF($cond, $(Mysql-Quote $_.Name), NULL))" }) -join ', '
                [void]$defs.Add("UNIQUE KEY $name ($parts)")
            } else {
                $cols = ($ix.Columns | ForEach-Object { if ($_.Descending) { "$(Mysql-Quote $_.Name) DESC" } else { Mysql-Quote $_.Name } }) -join ', '
                [void]$defs.Add($(if ($ix.Unique) { "UNIQUE KEY $name ($cols)" } else { "KEY $name ($cols)" }))
            }
        }
        foreach ($fk in ($t.ForeignKeys | Sort-Object { $_.Name })) {
            [void]$defs.Add("CONSTRAINT $(Mysql-Quote $fk.Name) FOREIGN KEY ($(($fk.Columns | ForEach-Object { Mysql-Quote $_ }) -join ', ')) REFERENCES $(Mysql-Quote $fk.RefTable) ($(($fk.RefColumns | ForEach-Object { Mysql-Quote $_ }) -join ', ')) ON DELETE $($fk.OnDelete)")
        }
        [void]$sb.Append("CREATE TABLE $(Mysql-Quote $t.Name) (`n    $($defs -join ",`n    ")`n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=$($global:MysqlDefaultCollation);`n`n")
    }
    return $sb.ToString()
}

function global:Mysql-Literal($Canonical, $Col) {
    if ($null -eq $Canonical) { return 'NULL' }
    switch ($Col.Kind) {
        { $_ -in 'int', 'bit' } { return $Canonical }
        'binary' { return "X'$Canonical'" }
        'datetime' {
            # canonical has 7 fractional digits; DATETIME(6) keeps 6, so the 7th must be a zero
            if (-not $Canonical.EndsWith('0')) { throw (New-MigrationError "Column $($Col.Name) holds sub-microsecond precision ($Canonical) that DATETIME(6) cannot store." 2) }
            return "'" + $Canonical.Substring(0, $Canonical.Length - 1) + "'"
        }
        default {
            # Backslashes (an escape character unless NO_BACKSLASH_ESCAPES is set) and control characters
            # are sent as hex so the result never depends on sql_mode or on how the pipe treats line endings.
            if ($Canonical -notmatch '[\x00-\x08\x0B-\x1F\x7F\\]') { return "'" + $Canonical.Replace("'", "''") + "'" }
            return "CONVERT(X'$(ConvertTo-HexUtf8 $Canonical)' USING utf8mb4)"
        }
    }
}

function global:Mysql-RenderData($Model, $RowsByTable) {
    $batch = 100
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("-- MasterAntiqueRepair data for MySQL 8`n")
    [void]$sb.Append("SET NAMES utf8mb4;`nSET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_AUTO_VALUE_ON_ZERO');`nSTART TRANSACTION;`n")
    foreach ($t in $Model.Tables) {
        $rows = $RowsByTable[$t.Name]
        if ($rows.Count -gt 0) {
            $colList = ($t.Columns | ForEach-Object { Mysql-Quote $_.Name }) -join ', '
            for ($start = 0; $start -lt $rows.Count; $start += $batch) {
                $end = [Math]::Min($start + $batch, $rows.Count)
                $lines = for ($r = $start; $r -lt $end; $r++) {
                    $vals = for ($i = 0; $i -lt $t.Columns.Count; $i++) { Mysql-Literal $rows[$r][$i] $t.Columns[$i] }
                    "(" + ($vals -join ', ') + ")"
                }
                [void]$sb.Append("INSERT INTO $(Mysql-Quote $t.Name) ($colList) VALUES`n$($lines -join ",`n");`n")
            }
        }
    }
    [void]$sb.Append("COMMIT;`n")
    foreach ($t in $Model.Tables) {
        if ($t.Identity) {
            $next = if ($null -ne $t.IdentityLast) { $t.IdentityLast + 1 } else { 1 }
            [void]$sb.Append("ALTER TABLE $(Mysql-Quote $t.Name) AUTO_INCREMENT = $next;`n")
        }
    }
    return $sb.ToString()
}

# ---- client access (mysql inside a Docker container)

function global:Mysql-Password($Settings) {
    $name = if ($Settings.passwordEnv) { [string]$Settings.passwordEnv } else { 'MAR_MYSQL_PASSWORD' }
    $v = [Environment]::GetEnvironmentVariable($name)
    if ($v) { return $v }
    return 'MarTest#2026'   # throwaway local test container only; set the env var to use your own
}

function global:Mysql-DbName([string]$Name) {
    if ($Name -notmatch '^[A-Za-z0-9_]{1,64}$') { throw (New-MigrationError "Invalid MySQL database name '$Name' (letters, digits and underscore only)." 2) }
    return $Name
}

function global:Mysql-EnsureServer($Settings) {
    $name = [string]$Settings.runner.container
    if (-not $name) { throw (New-MigrationError "Target has no runner.container configured." 2) }
    if ($global:MarMysqlReady -and $global:MarMysqlReady[$name]) { return }
    if ($Settings.runner.mode -ne 'docker') { throw (New-MigrationError "The mysql dialect currently supports runner.mode 'docker' only." 2) }
    $image = if ($Settings.runner.image) { [string]$Settings.runner.image } else { 'mysql:8.4' }
    $pw = Mysql-Password $Settings
    $auto = if ($null -ne $Settings.runner.autoStart) { [bool]$Settings.runner.autoStart } else { $true }
    [void](Confirm-DockerContainer $name @('-e', "MYSQL_ROOT_PASSWORD=$pw", $image, '--character-set-server=utf8mb4', '--collation-server=utf8mb4_0900_as_ci') $auto)
    Write-Host "Waiting for MySQL in container '$name' ..."
    $last = $null
    for ($i = 0; $i -lt 120; $i++) {
        # TCP on 127.0.0.1 only answers once the *final* server is up (the image's temporary init server has networking off)
        $last = Invoke-Docker @('exec', '-e', "MYSQL_PWD=$pw", $name, 'mysql', "--user=$($Settings.user)", '--protocol=TCP', '-h', '127.0.0.1', '--batch', '--skip-column-names', '-e', 'SELECT 1') ''
        if ($last.ExitCode -eq 0 -and $last.Stdout.Trim() -eq '1') { break }
        Start-Sleep -Seconds 2
        $last = $null
    }
    if (-not $last) { throw (New-MigrationError "MySQL in container '$name' did not become ready within 4 minutes (check: docker logs $name; a wrong password from an earlier container also shows up here)." 2) }
    if (-not $global:MarMysqlReady) { $global:MarMysqlReady = @{} }
    $global:MarMysqlReady[$name] = $true
}

function global:Mysql-Run($Settings, [string]$Db, [string]$Sql) {
    Mysql-EnsureServer $Settings
    $user = if ($Settings.user) { [string]$Settings.user } else { 'root' }
    $a = @('exec', '-i', '-e', "MYSQL_PWD=$(Mysql-Password $Settings)", [string]$Settings.runner.container, 'mysql', "--user=$user", '--default-character-set=utf8mb4', '--batch', '--skip-column-names')
    if ($Db) { $a += "--database=$(Mysql-DbName $Db)" }
    return Invoke-Docker $a $Sql
}

# Runs a query and returns one string per row. Unless -Raw: columns joined with '|', NULL shown as empty and
# DATETIME(6) values widened to the 7 fractional digits the SQL Server side uses, so both engines print alike.
function global:Mysql-Query($Settings, [string]$Db, [string]$Sql, [switch]$Raw) {
    $prefix = "SET SESSION sql_mode = CONCAT(@@sql_mode, ',ANSI_QUOTES'); SET SESSION information_schema_stats_expiry = 0;`n"
    $r = Mysql-Run $Settings $Db ($prefix + $Sql)
    if ($r.ExitCode -ne 0) { throw (New-MigrationError "mysql query failed: $($r.Stderr.Trim())`n$Sql" 2) }
    $rows = New-Object System.Collections.ArrayList
    foreach ($l in ($r.Stdout -split "`r?`n")) {
        if ($l.Length -eq 0) { continue }
        if ($Raw) { [void]$rows.Add($l); continue }
        $cells = foreach ($c in ($l -split "`t")) { if ($c -ceq 'NULL') { '' } else { [regex]::Replace($c, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6})(?!\d)', '${1}0') } }
        [void]$rows.Add(($cells -join '|'))
    }
    return , $rows
}

function global:Mysql-Version($Settings) {
    $v = (Mysql-Query $Settings $null 'SELECT VERSION();' -Raw)[0]
    $img = if ($Settings.runner.image) { [string]$Settings.runner.image } else { 'mysql:8.4' }
    return "MySQL $v (Docker image $img)"
}

function global:Mysql-Exists($Settings, [string]$Db) {
    $n = (Mysql-Query $Settings $null "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$(Mysql-DbName $Db)';" -Raw)[0]
    return ([int]$n -gt 0)
}

function global:Mysql-Orphans($Settings, [string]$Db, $Model) {
    $total = 0
    $details = New-Object System.Collections.ArrayList
    foreach ($t in $Model.Tables) {
        foreach ($fk in $t.ForeignKeys) {
            $on = for ($i = 0; $i -lt $fk.Columns.Count; $i++) { "c.$(Mysql-Quote $fk.Columns[$i]) = p.$(Mysql-Quote $fk.RefColumns[$i])" }
            $notNull = ($fk.Columns | ForEach-Object { "c.$(Mysql-Quote $_) IS NOT NULL" }) -join ' AND '
            $sql = "SELECT COUNT(*) FROM $(Mysql-Quote $t.Name) c LEFT JOIN $(Mysql-Quote $fk.RefTable) p ON $($on -join ' AND ') WHERE p.$(Mysql-Quote $fk.RefColumns[0]) IS NULL AND $notNull;"
            $n = [int](Mysql-Query $Settings $Db $sql -Raw)[0]
            if ($n -gt 0) { $total += $n; [void]$details.Add("$($t.Name).$($fk.Columns -join ',') -> $($fk.RefTable): $n orphan row(s)") }
        }
    }
    return [pscustomobject]@{ Count = $total; Detail = ($details -join '; ') }
}

function global:Mysql-Import($Settings, [string]$Db, [string]$SchemaText, [string]$DataText, [switch]$Recreate) {
    $Db = Mysql-DbName $Db
    if ((Mysql-Exists $Settings $Db) -and -not $Recreate) { throw (New-MigrationError "Target database '$Db' already exists (use --recreate to replace it)." 3) }
    $log = New-Object System.Collections.ArrayList
    $steps = @(
        @('create database', $null, "DROP DATABASE IF EXISTS $(Mysql-Quote $Db);`nCREATE DATABASE $(Mysql-Quote $Db) CHARACTER SET utf8mb4 COLLATE $($global:MysqlDefaultCollation);`n"),
        @('schema', $Db, $SchemaText),
        @('data', $Db, $DataText)
    )
    foreach ($s in $steps) {
        $r = Mysql-Run $Settings $s[1] $s[2]
        if ($r.ExitCode -ne 0) { throw (New-MigrationError "mysql failed during $($s[0]) (exit $($r.ExitCode)): $($r.Stderr.Trim())" 2) }
        [void]$log.Add("$($s[0]): ok")
    }
    $tables = (Mysql-Query $Settings $Db "SELECT table_name FROM information_schema.tables WHERE table_schema = '$Db' AND table_type = 'BASE TABLE' ORDER BY table_name;" -Raw)
    $list = ($tables | ForEach-Object { Mysql-Quote $_ }) -join ', '
    $check = Mysql-Query $Settings $Db "CHECK TABLE $list;" -Raw
    $bad = @($check | Where-Object { $_ -notmatch "`tstatus`tOK$" })
    if ($bad.Count -gt 0) { throw (New-MigrationError "CHECK TABLE reported problems: $($bad -join '; ')" 2) }
    [void]$log.Add("CHECK TABLE: ok ($($tables.Count) tables)")
    return $log
}

# One line per row, each cell 'i:HEX' / 't:HEX' / 'b:HEX' or '~' for NULL, joined by '|' (same shape as the SQLite dialect).
function global:Mysql-ReadRows($Settings, [string]$Db, $Table) {
    $exprs = foreach ($c in $Table.Columns) {
        $q = Mysql-Quote $c.Name
        $inner = switch ($c.Kind) {
            { $_ -in 'int', 'bit' } { "CONCAT('i:', HEX(CAST($q AS CHAR)))" }
            'datetime' { "CONCAT('t:', HEX(CONCAT(DATE_FORMAT($q, '%Y-%m-%d %H:%i:%s.%f'), '0')))" }
            'binary' { "CONCAT('b:', HEX($q))" }
            default { "CONCAT('t:', HEX($q))" }
        }
        "CASE WHEN $q IS NULL THEN '~' ELSE $inner END"
    }
    return Mysql-Query $Settings $Db "SELECT CONCAT_WS('|', $($exprs -join ', ')) FROM $(Mysql-Quote $Table.Name);" -Raw
}

function global:Mysql-SchemaChecks($Settings, [string]$Db, $Model) {
    $checks = New-Object System.Collections.ArrayList
    $d = $Db.Replace("'", "''")
    $Q = { param($sql) [object[]](Mysql-Query $Settings $Db $sql) }

    [void]$checks.Add((New-SetCheck 'Schema' 'Tables' @($Model.Tables | ForEach-Object { $_.Name }) (& $Q "SELECT table_name FROM information_schema.tables WHERE table_schema = '$d' AND table_type = 'BASE TABLE';")))

    $expCols = foreach ($t in $Model.Tables) {
        for ($i = 0; $i -lt $t.Columns.Count; $i++) {
            $c = $t.Columns[$i]
            $nn = if ($c.Nullable) { 0 } else { 1 }
            $def = '~'
            if ($null -ne $c.Default) { $def = $c.Default; if ($def.StartsWith("'")) { $def = $def.Substring(1, $def.Length - 2).Replace("''", "'") } }
            $auto = if ($c.IsIdentity) { 1 } else { 0 }
            $coll = if ($c.Kind -eq 'string' -or $c.Kind -eq 'guid') { Mysql-Collation $c } else { '~' }
            "$($t.Name)|$i|$($c.Name)|$((Mysql-Type $c).Info)|$nn|$def|$auto|$coll"
        }
    }
    $actCols = & $Q "SELECT CONCAT(table_name, '|', ordinal_position - 1, '|', column_name, '|', column_type, '|', IF(is_nullable = 'NO', 1, 0), '|', IFNULL(column_default, '~'), '|', IF(extra LIKE '%auto_increment%', 1, 0), '|', IFNULL(collation_name, '~')) FROM information_schema.columns WHERE table_schema = '$d';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Columns (name, order, type, NOT NULL, default, auto-increment, collation)' $expCols $actCols))

    $expPk = foreach ($t in $Model.Tables) { for ($i = 0; $i -lt $t.PrimaryKey.Count; $i++) { "$($t.Name)|$($i + 1)|$($t.PrimaryKey[$i])" } }
    $actPk = & $Q "SELECT CONCAT(table_name, '|', seq_in_index, '|', column_name) FROM information_schema.statistics WHERE table_schema = '$d' AND index_name = 'PRIMARY';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Primary key columns' $expPk $actPk))

    $expFk = foreach ($t in $Model.Tables) { foreach ($fk in $t.ForeignKeys) { for ($i = 0; $i -lt $fk.Columns.Count; $i++) { "$($t.Name)|$($fk.Columns[$i])|$($fk.RefTable)|$($fk.RefColumns[$i])|$($fk.OnDelete)" } } }
    $actFk = & $Q "SELECT CONCAT(k.table_name, '|', k.column_name, '|', k.referenced_table_name, '|', k.referenced_column_name, '|', r.delete_rule) FROM information_schema.key_column_usage k JOIN information_schema.referential_constraints r ON r.constraint_schema = k.constraint_schema AND r.constraint_name = k.constraint_name AND r.table_name = k.table_name WHERE k.table_schema = '$d' AND k.referenced_table_name IS NOT NULL;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Foreign keys (column, target, ON DELETE action)' $expFk $actFk))

    $expIx = foreach ($t in $Model.Tables) { foreach ($ix in $t.Indexes) { "$($t.Name)|$($ix.TargetName)|$(if ($ix.Unique) { 1 } else { 0 })|$(if ($ix.Filter) { 1 } else { 0 })" } }
    $actIx = & $Q "SELECT CONCAT(table_name, '|', index_name, '|', IF(MIN(non_unique) = 0, 1, 0), '|', IF(MAX(expression IS NOT NULL) = 1, 1, 0)) FROM information_schema.statistics WHERE table_schema = '$d' AND index_name <> 'PRIMARY' GROUP BY table_name, index_name;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Indexes (name, unique, filtered)' $expIx $actIx))

    $expIxc = foreach ($t in $Model.Tables) { foreach ($ix in $t.Indexes) { for ($i = 0; $i -lt $ix.Columns.Count; $i++) { "$($ix.TargetName)|$i|$(if ($ix.Filter) { '<expr>' } else { $ix.Columns[$i].Name })" } } }
    $actIxc = & $Q "SELECT CONCAT(index_name, '|', seq_in_index - 1, '|', IFNULL(column_name, '<expr>')) FROM information_schema.statistics WHERE table_schema = '$d' AND index_name <> 'PRIMARY';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Index columns' $expIxc $actIxc))

    # Filtered indexes: MySQL normalises the expression text, so check it mentions every key column and the IS NULL tests.
    $actExpr = & $Q "SELECT CONCAT(index_name, '|', LOWER(expression)) FROM information_schema.statistics WHERE table_schema = '$d' AND expression IS NOT NULL;"
    $filtered = @($Model.Tables | ForEach-Object { $_.Indexes } | ForEach-Object { $_ } | Where-Object { $_.Filter })
    $ok = 0; $notes = @()
    foreach ($ix in $filtered) {
        $preds = Mysql-FilterPredicates $ix.Filter
        $rows = @($actExpr | Where-Object { $_.StartsWith("$($ix.TargetName)|") } | ForEach-Object { $_.Substring($ix.TargetName.Length + 1) })
        $need = @($ix.Columns | ForEach-Object { $_.Name.ToLowerInvariant() }) + @($preds | ForEach-Object { $_.Column.ToLowerInvariant() })
        $good = ($rows.Count -ge 1)
        foreach ($e in $rows) { foreach ($n in $need) { if (-not $e.Contains($n)) { $good = $false } }; if (-not $e.Contains(' is ')) { $good = $false } }
        if ($good) { $ok++ } else { $notes += "$($ix.TargetName): $($rows -join ' ; ')" }
    }
    [void]$checks.Add([pscustomobject]@{ Category = 'Schema'; Name = 'Filtered index rules (emulated with functional indexes, e.g. active-username rule)'; Source = $filtered.Count; Target = $ok; Passed = ($ok -eq $filtered.Count); Detail = ($notes -join '; ') })

    $expAuto = @($Model.Tables | Where-Object { $_.Identity } | ForEach-Object { $_.Name })
    [void]$checks.Add((New-SetCheck 'Schema' 'Auto-increment (identity) tables' $expAuto (& $Q "SELECT table_name FROM information_schema.columns WHERE table_schema = '$d' AND extra LIKE '%auto_increment%';")))

    $expNext = foreach ($t in ($Model.Tables | Where-Object { $_.Identity })) { "$($t.Name)|$(if ($null -ne $t.IdentityLast) { $t.IdentityLast + 1 } else { 1 })" }
    $actNext = & $Q "SELECT CONCAT(table_name, '|', auto_increment) FROM information_schema.tables WHERE table_schema = '$d' AND auto_increment IS NOT NULL;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Auto-increment counters (continue from source values)' $expNext $actNext))

    $list = (@($Model.Tables | ForEach-Object { Mysql-Quote $_.Name })) -join ', '
    $chk = @(& $Q "CHECK TABLE $list;")
    $badChk = @($chk | Where-Object { $_ -notmatch '\|status\|OK$' })
    [void]$checks.Add((New-Check 'Integrity' 'MySQL CHECK TABLE on every table' ($badChk.Count -eq 0) "$($chk.Count) table(s) checked$(if ($badChk.Count) { ': ' + ($badChk -join '; ') })"))
    $orph = Mysql-Orphans $Settings $Db $Model
    [void]$checks.Add((New-Check 'Integrity' 'Foreign key orphan check (every child row has its parent)' ($orph.Count -eq 0) "$($orph.Count) orphan row(s) $($orph.Detail)"))
    return , $checks
}

# Runs rules against a scratch database rebuilt from the exported SQL, so the delivered database is never touched.
function global:Mysql-BehaviourTests($Settings, [string]$Db, $Model, [string]$SchemaText, [string]$DataText) {
    $checks = New-Object System.Collections.ArrayList
    if (-not $SchemaText -or -not $DataText) {
        [void]$checks.Add((New-Check 'Behaviour' 'Behaviour tests need the exported SQL files (run export first)' $false 'schema/data SQL not available'))
        return , $checks
    }
    $scratch = Mysql-DbName ("$Db`_behaviour")
    [void](Mysql-Import $Settings $scratch $SchemaText $DataText -Recreate)
    try {
        $ts = "'2000-01-01 00:00:00.000000'"
        $name = (Mysql-Query $Settings $scratch 'SELECT "Name" FROM "Users" WHERE "DeletedAt" IS NULL ORDER BY "Id" LIMIT 1;' -Raw)
        if ($name.Count -eq 1) {
            $n = $name[0].Replace("'", "''")
            $ins = "INSERT INTO ``Users`` (``Name``, ``CreatedAt``, ``Discriminator``) VALUES ('$n', $ts, 'Customer');`n"
            $r = Mysql-Run $Settings $scratch $ins
            [void]$checks.Add((New-Check 'Behaviour' 'Duplicate active username is rejected' ($r.ExitCode -ne 0 -and $r.Stderr -match 'Duplicate entry') ($r.Stderr.Trim())))
            $swapped = $n.ToUpperInvariant(); if ($swapped -ceq $n) { $swapped = $n.ToLowerInvariant() }
            if ($swapped -cne $n) {
                $r = Mysql-Run $Settings $scratch ($ins.Replace("'$n'", "'$swapped'"))
                [void]$checks.Add((New-Check 'Behaviour' 'Case-only duplicate of an active username is rejected (matches SQL Server''s case-insensitive collation)' ($r.ExitCode -ne 0 -and $r.Stderr -match 'Duplicate entry') ($r.Stderr.Trim())))
            }
            $r = Mysql-Run $Settings $scratch ("UPDATE ``Users`` SET ``DeletedAt`` = $ts WHERE ``Name`` = '$n';`n" + $ins)
            [void]$checks.Add((New-Check 'Behaviour' 'Reusing a soft-deleted username is allowed (filtered unique index)' ($r.ExitCode -eq 0) ($r.Stderr.Trim())))
        }
        $r = Mysql-Run $Settings $scratch "INSERT INTO ``Comments`` (``UserId``, ``TicketId``, ``Text``, ``CreatedAt``) VALUES (-1, -1, 'x', $ts);`n"
        [void]$checks.Add((New-Check 'Behaviour' 'Orphan foreign key insert is rejected' ($r.ExitCode -ne 0 -and $r.Stderr -match 'foreign key constraint fails') ($r.Stderr.Trim())))
        $r = Mysql-Run $Settings $scratch "INSERT INTO ``Users`` (``Name``, ``CreatedAt``, ``Discriminator``, ``EmailConfirmed``) VALUES ('zz_check_test', $ts, 'Customer', 2);`n"
        [void]$checks.Add((New-Check 'Behaviour' 'Boolean CHECK constraint rejects values other than 0/1' ($r.ExitCode -ne 0 -and $r.Stderr -match 'heck constraint') ($r.Stderr.Trim())))
        foreach ($t in ($Model.Tables | Where-Object { $_.Identity -and $_.Name -eq 'Roles' })) {
            $expected = if ($null -ne $t.IdentityLast) { $t.IdentityLast + 1 } else { 1 }
            $r = (Mysql-Query $Settings $scratch "INSERT INTO ``Roles`` (``Name``) VALUES ('zz_verify_test');`nSELECT LAST_INSERT_ID();" -Raw)
            [void]$checks.Add((New-Check 'Behaviour' 'New Roles row continues the source identity sequence' ("$($r[0])" -eq "$expected") "expected id $expected, got id $($r[0])"))
        }
        # cascade rule: deleting a ticket deletes its comments (only if the source defines that cascade)
        $cascade = @($Model.Tables | ForEach-Object { $_.ForeignKeys } | ForEach-Object { $_ } | Where-Object { $_.Table -eq 'Comments' -and $_.RefTable -eq 'Tickets' -and $_.OnDelete -eq 'CASCADE' })
        if ($cascade.Count -gt 0) {
            $tid = (Mysql-Query $Settings $scratch 'SELECT "TicketId" FROM "Comments" ORDER BY "TicketId" LIMIT 1;' -Raw)
            if ($tid.Count -eq 1) {
                $after = (Mysql-Query $Settings $scratch "DELETE FROM ``Tickets`` WHERE ``Id`` = $($tid[0]);`nSELECT COUNT(*) FROM ``Comments`` WHERE ``TicketId`` = $($tid[0]);" -Raw)
                [void]$checks.Add((New-Check 'Behaviour' 'Deleting a ticket cascades to its comments (ON DELETE CASCADE)' ("$($after[0])" -eq '0') "comments left for deleted ticket: $($after[0])"))
            }
        }
    } finally { Mysql-Run $Settings $null "DROP DATABASE IF EXISTS $(Mysql-Quote $scratch);" | Out-Null }
    return , $checks
}

# ---- self-test support

function global:Mysql-NewScratchId($Settings, [string]$Label) { return Mysql-DbName ("$($Settings.database)_$Label") }
function global:Mysql-Clone($Settings, [string]$Src, [string]$Dst, [string]$SchemaText, [string]$DataText) { [void](Mysql-Import $Settings $Dst $SchemaText $DataText -Recreate) }
function global:Mysql-Remove($Settings, [string]$Db) { [void](Mysql-Run $Settings $null "DROP DATABASE IF EXISTS $(Mysql-Quote (Mysql-DbName $Db));") }

# SQL that alters one comment and deletes one ticket without letting the cascade hide it.
function global:Mysql-DamageSql([string]$CommentId, [string]$TicketId) {
    return "SET FOREIGN_KEY_CHECKS = 0;`nUPDATE ``Comments`` SET ``Text`` = CONCAT(``Text``, ' (tampered)') WHERE ``Id`` = $CommentId;`nDELETE FROM ``Tickets`` WHERE ``Id`` = $TicketId;`n"
}

# Independent check: MySQL's own CHECKSUM TABLE, per table, for two databases built from the same export.
function global:Mysql-Diff($Settings, [string]$A, [string]$B, $Model) {
    $sum = {
        param($db)
        $list = ($Model.Tables | ForEach-Object { "$(Mysql-Quote $db).$(Mysql-Quote $_.Name)" }) -join ', '
        $rows = Mysql-Query $Settings $null "CHECKSUM TABLE $list;" -Raw
        foreach ($r in $rows) { $p = $r -split "`t"; "$($p[0].Substring($p[0].IndexOf('.') + 1))|$($p[1])" }
    }
    $sa = @(& $sum $A); $sb2 = @(& $sum $B)
    $c = New-SetCheck 'MySQL' 'Imported database equals an independently imported copy (CHECKSUM TABLE)' $sa $sb2
    if ($c.Passed) { $c.Detail = "CHECKSUM TABLE matched for $($sa.Count) tables" }
    return $c
}

function global:Mysql-KnownDifferences {
    return @(
        'MySQL has no partial (filtered) indexes. The rule that lets a deleted user''s name be reused is enforced with a functional unique index on IF(DeletedAt IS NULL, Name, NULL); it is verified by behaviour tests, not just by structure.',
        "Text columns are utf8mb4 with the accent-sensitive, case-insensitive collation utf8mb4_0900_as_ci, chosen to mirror the SQL Server collation (SQL_Latin1_General_CP1_CI_AS), so usernames that differ only by case still collide, as before.",
        'Dates are stored as DATETIME(6) (microseconds). SQL Server datetime values (millisecond precision) fit exactly.',
        'Yes/no columns are TINYINT(1) 0/1 with a CHECK constraint (enforced by MySQL 8.0.16 and later).',
        'On Linux, MySQL treats table names as case-sensitive; the migrated tables keep their exact CamelCase spelling, so the application must use the same case.',
        'Index names that were duplicated across tables in SQL Server (for example IX_UserId) are prefixed with the table name, the same rule used for every target.'
    )
}

function New-Dialect {
    return @{
        Name             = 'mysql'
        DisplayName      = 'MySQL'
        KnownDifferences = (Mysql-KnownDifferences)
        RenderSchema     = { param($m, $s) Mysql-RenderSchema $m $s }
        RenderData       = { param($m, $r) Mysql-RenderData $m $r }
        TargetId         = { param($st, $ov) if ($ov) { Mysql-DbName $ov } else { Mysql-DbName ([string]$st.database) } }
        Exists           = { param($st, $id) Mysql-Exists $st $id }
        Fingerprint      = { param($st, $id) $null }
        Import           = { param($st, $id, $sch, $dat, $rc) Mysql-Import $st $id $sch $dat -Recreate:$rc }
        ReadRows         = { param($st, $id, $t) Mysql-ReadRows $st $id $t }
        Query            = { param($st, $id, $sql) Mysql-Query $st $id $sql }
        Run              = { param($st, $id, $sql) Mysql-Run $st $id $sql }
        Version          = { param($st) Mysql-Version $st }
        SchemaChecks     = { param($st, $id, $m) Mysql-SchemaChecks $st $id $m }
        Behaviour        = { param($st, $id, $m, $sch, $dat) Mysql-BehaviourTests $st $id $m $sch $dat }
        NewScratchId     = { param($st, $label) Mysql-NewScratchId $st $label }
        Clone            = { param($st, $src, $dst, $sch, $dat) Mysql-Clone $st $src $dst $sch $dat }
        Remove           = { param($st, $id) Mysql-Remove $st $id }
        Diff             = { param($st, $a, $b, $m) Mysql-Diff $st $a $b $m }
        DamageSql        = { param($cid, $tid) Mysql-DamageSql $cid $tid }
    }
}
