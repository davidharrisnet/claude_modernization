# SQLite dialect. Dot-sourced by Get-Dialect; helper functions are global: so the scriptblocks
# returned from New-Dialect can still find them after Get-Dialect returns.

function global:Sqlite-Quote([string]$Name) { return '"' + $Name.Replace('"', '""') + '"' }

function global:Sqlite-ColumnType($Col) {
    switch ($Col.Kind) {
        'int' { return 'INTEGER' }
        'bit' { return 'INTEGER' }
        'datetime' { return 'DATETIME' }
        'binary' { return 'BLOB' }
        'guid' { return 'TEXT' }
        'string' {
            if ($Col.Length -lt 0 -or $Col.TypeName -in 'ntext', 'text') { return 'TEXT' }
            return "VARCHAR($($Col.Length))"
        }
    }
    throw (New-MigrationError "No SQLite type for kind '$($Col.Kind)'" 2)
}

# Translates a SQL Server filtered-index predicate. Only [col] IS [NOT] NULL (AND-ed) is
# understood; anything else is an error so a business rule is never silently dropped.
function global:Sqlite-TranslateFilter([string]$Filter) {
    $parts = New-Object System.Collections.ArrayList
    $text = $Filter.Trim()
    foreach ($p in ($text -split '\s+AND\s+', 0, 'IgnoreCase')) {
        $q = $p.Trim()
        while ($q.StartsWith('(') -and $q.EndsWith(')')) { $q = $q.Substring(1, $q.Length - 2).Trim() }
        if ($q -notmatch '^\[(\w+)\]\s+IS\s+(NOT\s+)?NULL$') {
            throw (New-MigrationError "Cannot translate index filter '$Filter' to SQLite - extend Sqlite-TranslateFilter." 2)
        }
        $neg = if ($Matches[2]) { 'NOT ' } else { '' }
        [void]$parts.Add("$(Sqlite-Quote $Matches[1]) IS ${neg}NULL")
    }
    return ($parts -join ' AND ')
}

function global:Sqlite-RenderSchema($Model, [string]$SourceName) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("-- MasterAntiqueRepair schema for SQLite (generated from SQL Server catalog '$SourceName')`n")
    [void]$sb.Append("PRAGMA foreign_keys = ON;`n`n")
    foreach ($t in $Model.Tables) {
        $defs = New-Object System.Collections.ArrayList
        foreach ($c in $t.Columns) {
            $d = "$(Sqlite-Quote $c.Name) $(Sqlite-ColumnType $c)"
            if ($c.IsIdentity) {
                if ($t.PrimaryKey.Count -ne 1 -or $t.PrimaryKey[0] -ne $c.Name -or $c.Kind -ne 'int') {
                    throw (New-MigrationError "Identity column $($t.Name).$($c.Name) is not a single-column integer primary key - not supported." 2)
                }
                $d += ' PRIMARY KEY AUTOINCREMENT'
            }
            if (-not $c.Nullable) { $d += ' NOT NULL' }
            if ($null -ne $c.Default) { $d += " DEFAULT $($c.Default)" }
            if ($c.Kind -eq 'bit') { $d += " CHECK ($(Sqlite-Quote $c.Name) IN (0, 1))" }
            [void]$defs.Add($d)
        }
        if (-not $t.Identity -and $t.PrimaryKey.Count -gt 0) {
            [void]$defs.Add("PRIMARY KEY ($(($t.PrimaryKey | ForEach-Object { Sqlite-Quote $_ }) -join ', '))")
        }
        foreach ($fk in ($t.ForeignKeys | Sort-Object { $_.Name })) {
            [void]$defs.Add("CONSTRAINT $(Sqlite-Quote $fk.Name) FOREIGN KEY ($(($fk.Columns | ForEach-Object { Sqlite-Quote $_ }) -join ', ')) REFERENCES $(Sqlite-Quote $fk.RefTable) ($(($fk.RefColumns | ForEach-Object { Sqlite-Quote $_ }) -join ', ')) ON DELETE $($fk.OnDelete)")
        }
        [void]$sb.Append("CREATE TABLE $(Sqlite-Quote $t.Name) (`n    $($defs -join ",`n    ")`n);`n`n")
    }
    foreach ($t in $Model.Tables) {
        foreach ($ix in ($t.Indexes | Sort-Object { $_.TargetName })) {
            $u = if ($ix.Unique) { 'UNIQUE ' } else { '' }
            $cols = ($ix.Columns | ForEach-Object { if ($_.Descending) { "$(Sqlite-Quote $_.Name) DESC" } else { Sqlite-Quote $_.Name } }) -join ', '
            $w = if ($ix.Filter) { " WHERE $(Sqlite-TranslateFilter $ix.Filter)" } else { '' }
            [void]$sb.Append("CREATE ${u}INDEX $(Sqlite-Quote $ix.TargetName) ON $(Sqlite-Quote $t.Name) ($cols)$w;`n")
        }
    }
    return $sb.ToString()
}

function global:Sqlite-Literal($Canonical, $Col) {
    if ($null -eq $Canonical) { return 'NULL' }
    switch ($Col.Kind) {
        { $_ -in 'int', 'bit' } { return $Canonical }
        'binary' { return "X'$Canonical'" }
        default {
            # The sqlite3 shell reads stdin in Windows text mode, which rewrites CRLF to LF and
            # treats Ctrl-Z as end of input. Control characters other than TAB and LF are
            # therefore emitted as char(n) expressions instead of raw bytes.
            if ($Canonical -notmatch '[\x00-\x08\x0B-\x1F\x7F]') { return "'" + $Canonical.Replace("'", "''") + "'" }
            $parts = New-Object System.Collections.ArrayList
            $run = New-Object System.Text.StringBuilder
            foreach ($ch in $Canonical.ToCharArray()) {
                $code = [int]$ch
                if (($code -le 8) -or ($code -ge 11 -and $code -le 31) -or $code -eq 127) {
                    if ($run.Length -gt 0) { [void]$parts.Add("'" + $run.ToString().Replace("'", "''") + "'"); [void]$run.Clear() }
                    [void]$parts.Add("char($code)")
                } else { [void]$run.Append($ch) }
            }
            if ($run.Length -gt 0) { [void]$parts.Add("'" + $run.ToString().Replace("'", "''") + "'") }
            return '(' + ($parts -join ' || ') + ')'
        }
    }
}

function global:Sqlite-RenderData($Model, $RowsByTable) {
    $batch = 100
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("-- MasterAntiqueRepair data for SQLite`n")
    [void]$sb.Append("PRAGMA foreign_keys = OFF;`nBEGIN TRANSACTION;`n")
    foreach ($t in $Model.Tables) {
        $rows = $RowsByTable[$t.Name]
        if ($rows.Count -gt 0) {
            $colList = ($t.Columns | ForEach-Object { Sqlite-Quote $_.Name }) -join ', '
            for ($start = 0; $start -lt $rows.Count; $start += $batch) {
                $end = [Math]::Min($start + $batch, $rows.Count)
                $lines = for ($r = $start; $r -lt $end; $r++) {
                    $vals = for ($i = 0; $i -lt $t.Columns.Count; $i++) { Sqlite-Literal $rows[$r][$i] $t.Columns[$i] }
                    "(" + ($vals -join ', ') + ")"
                }
                [void]$sb.Append("INSERT INTO $(Sqlite-Quote $t.Name) ($colList) VALUES`n$($lines -join ",`n");`n")
            }
        }
        if ($t.Identity -and $null -ne $t.IdentityLast) {
            [void]$sb.Append("DELETE FROM sqlite_sequence WHERE name = '$($t.Name.Replace("'", "''"))';`n")
            [void]$sb.Append("INSERT INTO sqlite_sequence (name, seq) VALUES ('$($t.Name.Replace("'", "''"))', $($t.IdentityLast));`n")
        }
    }
    [void]$sb.Append("COMMIT;`nPRAGMA foreign_keys = ON;`nPRAGMA foreign_key_check;`n")
    return $sb.ToString()
}

# ---- client access

function global:Sqlite-Exe($Settings) {
    if ($Settings.exe -and (Test-Path $Settings.exe)) { return $Settings.exe }
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw (New-MigrationError "sqlite3 not found (config 'exe' = '$($Settings.exe)', and nothing named sqlite3 on PATH)." 2)
}

# ---- runner: 'local' (sqlite3.exe on this machine) or 'docker' (sqlite3 inside a Linux container)

function global:Sqlite-IsDocker($Settings) { return ($Settings.runner -and $Settings.runner.mode -eq 'docker') }

# Creates/starts the Linux container that hosts the SQLite client and the database file, then waits for it.
# Alpine + `apk add sqlite sqlite-tools` gives sqlite3 and sqldiff; database files live under /data inside the container.
function global:Sqlite-EnsureContainer($Settings) {
    $name = [string]$Settings.runner.container
    if (-not $name) { throw (New-MigrationError "Target has no runner.container configured." 2) }
    if ($global:MarSqliteReady -and $global:MarSqliteReady[$name]) { return }
    $image = if ($Settings.runner.image) { [string]$Settings.runner.image } else { 'alpine:3.20' }
    $auto = if ($null -ne $Settings.runner.autoStart) { [bool]$Settings.runner.autoStart } else { $true }
    [void](Confirm-DockerContainer $name @($image, 'sh', '-c', 'apk add --no-cache sqlite sqlite-tools && mkdir -p /data && exec tail -f /dev/null') $auto)
    Write-Host "Waiting for sqlite3 in container '$name' ..."
    $ok = $false
    for ($i = 0; $i -lt 90; $i++) {
        $r = Invoke-Docker @('exec', $name, 'sh', '-c', 'command -v sqlite3 >/dev/null && command -v sqldiff >/dev/null && test -d /data') ''
        if ($r.ExitCode -eq 0) { $ok = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $ok) { throw (New-MigrationError "sqlite3/sqldiff did not become available in container '$name' within 3 minutes (needs internet for 'apk add'; check: docker logs $name)." 2) }
    if (-not $global:MarSqliteReady) { $global:MarSqliteReady = @{} }
    $global:MarSqliteReady[$name] = $true
}

# Runs a command inside the SQLite container (stdin is piped as UTF-8).
function global:Sqlite-Docker($Settings, [string[]]$Cmd, [string]$Stdin) {
    Sqlite-EnsureContainer $Settings
    return Invoke-Docker (@('exec', '-i', [string]$Settings.runner.container) + $Cmd) $Stdin
}

function global:Sqlite-Run($Settings, [string]$DbFile, [string]$Sql, [switch]$Quiet) {
    if (Sqlite-IsDocker $Settings) { return Sqlite-Docker $Settings @('sqlite3', '-bail', $DbFile) $Sql }
    $exe = Sqlite-Exe $Settings
    return Invoke-ClientProcess $exe @('-bail', $DbFile) $Sql
}

function global:Sqlite-Version($Settings) {
    if (Sqlite-IsDocker $Settings) {
        $r = Sqlite-Docker $Settings @('sqlite3', '-version') ''
        return ($r.Stdout.Trim() -split '\s+')[0]
    }
    $r = Invoke-ClientProcess (Sqlite-Exe $Settings) @('-version') ''
    return ($r.Stdout.Trim() -split '\s+')[0]
}

# Human-readable description recorded in the results and the report.
function global:Sqlite-VersionText($Settings) {
    $v = Sqlite-Version $Settings
    if (-not (Sqlite-IsDocker $Settings)) { return "sqlite3 $v" }
    $os = (Sqlite-Docker $Settings @('sh', '-c', '. /etc/os-release && echo "$PRETTY_NAME"') '').Stdout.Trim()
    $kernel = (Sqlite-Docker $Settings @('uname', '-r') '').Stdout.Trim()
    $image = if ($Settings.runner.image) { [string]$Settings.runner.image } else { 'alpine:3.20' }
    return "sqlite3 $v on $os, Linux kernel $kernel (container $($Settings.runner.container), image $image)"
}

# File operations on the database file, wherever it lives (host path or container path).
function global:Sqlite-FileExists($Settings, [string]$Path) {
    if (Sqlite-IsDocker $Settings) { return ((Sqlite-Docker $Settings @('test', '-f', $Path) '').ExitCode -eq 0) }
    return (Test-Path -LiteralPath $Path)
}
function global:Sqlite-FileRemove($Settings, [string]$Path) {
    if (Sqlite-IsDocker $Settings) { [void](Sqlite-Docker $Settings @('rm', '-f', $Path) ''); return }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}
function global:Sqlite-EnsureDir($Settings, [string]$FilePath) {
    if (Sqlite-IsDocker $Settings) {
        $dir = $FilePath.Substring(0, $FilePath.LastIndexOf('/'))
        if ($dir) { [void](Sqlite-Docker $Settings @('mkdir', '-p', $dir) '') }
        return
    }
    $dir = Split-Path -Parent $FilePath
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
}

# After import: a container-hosted database is also copied out to the host output folder so it can be inspected and handed over.
function global:Sqlite-Publish($Settings, [string]$DbFile, [string]$HostDir) {
    if (-not (Sqlite-IsDocker $Settings)) { return $null }
    if (-not (Test-Path $HostDir)) { [void](New-Item -ItemType Directory -Force -Path $HostDir) }
    $dest = Join-Path $HostDir ([System.IO.Path]::GetFileName($DbFile))
    if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force }
    $r = Invoke-Docker @('cp', "$($Settings.runner.container):$DbFile", $dest) ''
    if ($r.ExitCode -ne 0) { throw (New-MigrationError "docker cp failed: $($r.Stderr.Trim())" 2) }
    return "copied out of the container: $dest ($((Get-Item -LiteralPath $dest).Length) bytes, sha256 $(Get-FileSha256 $dest))"
}

function global:Sqlite-Import($Settings, [string]$DbFile, [string]$SchemaText, [string]$DataText, [switch]$Recreate) {
    if (Sqlite-FileExists $Settings $DbFile) {
        if (-not $Recreate) { throw (New-MigrationError "Target database already exists: $DbFile (use --recreate to replace it)." 3) }
        Sqlite-FileRemove $Settings $DbFile
    }
    Sqlite-EnsureDir $Settings $DbFile
    $log = New-Object System.Collections.ArrayList
    foreach ($step in @(@('schema', $SchemaText), @('data', $DataText))) {
        $r = Sqlite-Run $Settings $DbFile $step[1]
        if ($r.ExitCode -ne 0) { throw (New-MigrationError "sqlite3 failed loading $($step[0]) (exit $($r.ExitCode)): $($r.Stderr.Trim())" 2) }
        if ($step[0] -eq 'data' -and $r.Stdout.Trim().Length -gt 0) {
            throw (New-MigrationError "Foreign key violations after loading data:`n$($r.Stdout.Trim())" 2)
        }
        [void]$log.Add("$($step[0]): ok")
    }
    $r = Sqlite-Run $Settings $DbFile "PRAGMA integrity_check;`nPRAGMA foreign_key_check;`n"
    if ($r.ExitCode -ne 0 -or $r.Stdout.Trim() -ne 'ok') { throw (New-MigrationError "Post-load integrity/foreign key check failed: $($r.Stdout.Trim()) $($r.Stderr.Trim())" 2) }
    [void]$log.Add('integrity_check: ok; foreign_key_check: clean')
    return $log
}

# One line per row, each cell 'i:HEX' / 't:HEX' / 'b:HEX' or '~' for NULL, joined by '|'.
function global:Sqlite-ReadRows($Settings, [string]$DbFile, $Table) {
    $exprs = foreach ($c in $Table.Columns) {
        $q = Sqlite-Quote $c.Name
        "CASE WHEN $q IS NULL THEN '~' ELSE substr(typeof($q),1,1)||':'||hex($q) END"
    }
    $sql = "SELECT $($exprs -join "||'|'||") FROM $(Sqlite-Quote $Table.Name);"
    $r = Sqlite-Run $Settings $DbFile $sql
    if ($r.ExitCode -ne 0) { throw (New-MigrationError "sqlite3 query failed for $($Table.Name): $($r.Stderr.Trim())" 2) }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in ($r.Stdout -split "`r?`n")) { if ($l.Length -gt 0) { [void]$lines.Add($l) } }
    return , $lines
}

# Runs a query and returns each output row as a '|'-joined string.
function global:Sqlite-Query($Settings, [string]$DbFile, [string]$Sql) {
    # -list/-separator are CLI flags, not dot-commands piped over stdin: newer sqlite3 builds (seen:
    # 3.53.4) don't reliably parse '.mode list'/'.separator |' sent as part of the same stdin write
    # Sqlite-Run uses for the query itself, so set the output shape on the command line instead.
    if (Sqlite-IsDocker $Settings) {
        $r = Sqlite-Docker $Settings @('sqlite3', '-bail', '-list', '-separator', '|', $DbFile) $Sql
    } else {
        $exe = Sqlite-Exe $Settings
        $r = Invoke-ClientProcess $exe @('-bail', '-list', '-separator', '|', $DbFile) $Sql
    }
    if ($r.ExitCode -ne 0) { throw (New-MigrationError "sqlite3 query failed: $($r.Stderr.Trim())`n$Sql" 2) }
    $rows = New-Object System.Collections.ArrayList
    foreach ($l in ($r.Stdout -split "`r?`n")) { if ($l.Length -gt 0) { [void]$rows.Add($l) } }
    return , $rows
}

# ---- verification helpers (schema objects and behaviour)

function global:Sqlite-SchemaChecks($Settings, [string]$DbFile, $Model) {
    $checks = New-Object System.Collections.ArrayList
    $notInternal = "m.type = 'table' AND m.name NOT LIKE 'sqlite_%'"

    $expTables = @($Model.Tables | ForEach-Object { $_.Name })
    $actTables = Sqlite-Query $Settings $DbFile "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Tables' $expTables $actTables))

    $expCols = foreach ($t in $Model.Tables) {
        for ($i = 0; $i -lt $t.Columns.Count; $i++) {
            $c = $t.Columns[$i]
            $pk = $t.PrimaryKey.IndexOf($c.Name) + 1
            $nn = if ($c.Nullable) { 0 } else { 1 }
            $def = if ($null -ne $c.Default) { $c.Default } else { '~' }
            "$($t.Name)|$i|$($c.Name)|$(Sqlite-ColumnType $c)|$nn|$pk|$def"
        }
    }
    $actCols = Sqlite-Query $Settings $DbFile "SELECT m.name||'|'||p.cid||'|'||p.name||'|'||p.type||'|'||p.""notnull""||'|'||p.pk||'|'||COALESCE(p.dflt_value,'~') FROM sqlite_master m, pragma_table_info(m.name) p WHERE $notInternal;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Columns (name, order, type, NOT NULL, PK position, default)' $expCols $actCols))

    $expPk = foreach ($t in $Model.Tables) { foreach ($k in $t.PrimaryKey) { "$($t.Name)|$k" } }
    $actPk = Sqlite-Query $Settings $DbFile "SELECT m.name||'|'||p.name FROM sqlite_master m, pragma_table_info(m.name) p WHERE $notInternal AND p.pk > 0;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Primary key columns' $expPk $actPk))

    $expFk = foreach ($t in $Model.Tables) { foreach ($fk in $t.ForeignKeys) { for ($i = 0; $i -lt $fk.Columns.Count; $i++) { "$($t.Name)|$($fk.Columns[$i])|$($fk.RefTable)|$($fk.RefColumns[$i])|$($fk.OnDelete)" } } }
    $actFk = Sqlite-Query $Settings $DbFile "SELECT m.name||'|'||f.""from""||'|'||f.""table""||'|'||f.""to""||'|'||f.on_delete FROM sqlite_master m, pragma_foreign_key_list(m.name) f WHERE $notInternal;"
    [void]$checks.Add((New-SetCheck 'Schema' 'Foreign keys (column, target, ON DELETE action)' $expFk $actFk))

    $expIx = foreach ($t in $Model.Tables) { foreach ($ix in $t.Indexes) { "$($t.Name)|$($ix.TargetName)|$(if ($ix.Unique) { 1 } else { 0 })|$(if ($ix.Filter) { 1 } else { 0 })" } }
    $actIx = Sqlite-Query $Settings $DbFile "SELECT m.name||'|'||i.name||'|'||i.""unique""||'|'||i.partial FROM sqlite_master m, pragma_index_list(m.name) i WHERE $notInternal AND i.origin = 'c';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Indexes (name, unique, partial)' $expIx $actIx))

    $expIxc = foreach ($t in $Model.Tables) { foreach ($ix in $t.Indexes) { for ($i = 0; $i -lt $ix.Columns.Count; $i++) { "$($ix.TargetName)|$i|$($ix.Columns[$i].Name)" } } }
    $actIxc = Sqlite-Query $Settings $DbFile "SELECT i.name||'|'||x.seqno||'|'||x.name FROM sqlite_master m, pragma_index_list(m.name) i, pragma_index_info(i.name) x WHERE $notInternal AND i.origin = 'c';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Index columns' $expIxc $actIxc))

    $expFilter = foreach ($t in $Model.Tables) { foreach ($ix in $t.Indexes) { if ($ix.Filter) { "$($ix.TargetName)|$(Sqlite-TranslateFilter $ix.Filter)" } } }
    $actFilter = Sqlite-Query $Settings $DbFile "SELECT name||'|'||substr(sql, instr(sql, ' WHERE ') + 7) FROM sqlite_master WHERE type = 'index' AND sql LIKE '% WHERE %';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Partial index filters (e.g. active-username rule)' $expFilter $actFilter))

    $expAuto = @($Model.Tables | Where-Object { $_.Identity } | ForEach-Object { $_.Name })
    $actAuto = Sqlite-Query $Settings $DbFile "SELECT name FROM sqlite_master WHERE type = 'table' AND sql LIKE '%AUTOINCREMENT%';"
    [void]$checks.Add((New-SetCheck 'Schema' 'Auto-increment (identity) tables' $expAuto $actAuto))

    $integrity = [object[]](Sqlite-Query $Settings $DbFile 'PRAGMA integrity_check;')
    [void]$checks.Add((New-Check 'Integrity' 'SQLite integrity_check' ($integrity[0] -eq 'ok') ($integrity -join '; ')))
    $fkc = [object[]](Sqlite-Query $Settings $DbFile 'PRAGMA foreign_key_check;')
    [void]$checks.Add((New-Check 'Integrity' 'SQLite foreign_key_check (orphan rows)' ($fkc.Count -eq 0) "$($fkc.Count) violation(s)"))
    return , $checks
}

# Exercises rules on a throw-away copy of the database (the real target is never modified).
function global:Sqlite-BehaviourTests($Settings, [string]$DbFile, $Model) {
    $checks = New-Object System.Collections.ArrayList
    $copy = Sqlite-NewScratchId $Settings 'behaviour'
    Sqlite-Clone $Settings $DbFile $copy $null $null
    try {
        $fkOn = "PRAGMA foreign_keys = ON;`n"
        $ts = "'2000-01-01 00:00:00.0000000'"
        $name = [object[]](Sqlite-Query $Settings $copy 'SELECT "Name" FROM "Users" WHERE "DeletedAt" IS NULL ORDER BY "Id" LIMIT 1;')
        if ($name.Count -eq 1) {
            $n = $name[0].Replace("'", "''")
            $ins = "INSERT INTO ""Users"" (""Name"", ""CreatedAt"", ""Discriminator"") VALUES ('$n', $ts, 'Customer');`n"
            $r = Sqlite-Run $Settings $copy ($fkOn + $ins)
            [void]$checks.Add((New-Check 'Behaviour' 'Duplicate active username is rejected' ($r.ExitCode -ne 0 -and $r.Stderr -match 'UNIQUE constraint failed') ($r.Stderr.Trim())))
            $r = Sqlite-Run $Settings $copy ($fkOn + "UPDATE ""Users"" SET ""DeletedAt"" = $ts WHERE ""Name"" = '$n';`n" + $ins)
            [void]$checks.Add((New-Check 'Behaviour' 'Reusing a soft-deleted username is allowed (partial unique index)' ($r.ExitCode -eq 0) ($r.Stderr.Trim())))
        }
        $r = Sqlite-Run $Settings $copy ($fkOn + "INSERT INTO ""Comments"" (""UserId"", ""TicketId"", ""Text"", ""CreatedAt"") VALUES (-1, -1, 'x', $ts);`n")
        [void]$checks.Add((New-Check 'Behaviour' 'Orphan foreign key insert is rejected' ($r.ExitCode -ne 0 -and $r.Stderr -match 'FOREIGN KEY constraint failed') ($r.Stderr.Trim())))
        $r = Sqlite-Run $Settings $copy ($fkOn + "INSERT INTO ""Users"" (""Name"", ""CreatedAt"", ""Discriminator"", ""EmailConfirmed"") VALUES ('zz_check_test', $ts, 'Customer', 2);`n")
        [void]$checks.Add((New-Check 'Behaviour' 'Boolean CHECK constraint rejects values other than 0/1' ($r.ExitCode -ne 0 -and $r.Stderr -match 'CHECK constraint failed') ($r.Stderr.Trim())))

        foreach ($t in ($Model.Tables | Where-Object { $_.Identity -and $_.Name -eq 'Roles' })) {
            $expected = if ($null -ne $t.IdentityLast) { $t.IdentityLast + 1 } else { 1 }
            $r = [object[]](Sqlite-Query $Settings $copy "INSERT INTO ""Roles"" (""Name"") VALUES ('zz_verify_test');`nSELECT last_insert_rowid();")
            [void]$checks.Add((New-Check 'Behaviour' 'New Roles row continues the source identity sequence' ("$($r[0])" -eq "$expected") "expected id $expected, got id $($r[0])"))
        }
    } finally { Sqlite-Remove $Settings $copy }
    return , $checks
}

# ---- interface used by the generic pipeline (target ids are file paths for SQLite)

function global:Sqlite-NewScratchId($Settings, [string]$Label) {
    $leaf = "mar-$Label-" + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.sqlite'
    if (Sqlite-IsDocker $Settings) { return "/data/$leaf" }
    return (Join-Path ([System.IO.Path]::GetTempPath()) $leaf)
}
function global:Sqlite-Clone($Settings, [string]$Src, [string]$Dst, [string]$SchemaText, [string]$DataText) {
    if (Sqlite-IsDocker $Settings) {
        $r = Sqlite-Docker $Settings @('cp', $Src, $Dst) ''
        if ($r.ExitCode -ne 0) { throw (New-MigrationError "cp failed in container: $($r.Stderr.Trim())" 2) }
        return
    }
    Copy-Item -LiteralPath $Src -Destination $Dst
}
function global:Sqlite-Remove($Settings, [string]$Path) { Sqlite-FileRemove $Settings $Path }

function global:Sqlite-DamageSql([string]$CommentId, [string]$TicketId) {
    return "PRAGMA foreign_keys = OFF;`nUPDATE ""Comments"" SET ""Text"" = ""Text"" || ' (tampered)' WHERE ""Id"" = $CommentId;`nDELETE FROM ""Tickets"" WHERE ""Id"" = $TicketId;`n"
}

# Independent check with SQLite's own sqldiff tool.
function global:Sqlite-Diff($Settings, [string]$A, [string]$B, $Model) {
    if (Sqlite-IsDocker $Settings) {
        $r = Sqlite-Docker $Settings @('sqldiff', $A, $B) ''
    } else {
        $diffExe = $Settings.diffExe
        if (-not $diffExe -or -not (Test-Path $diffExe)) { return (New-Check 'sqldiff' 'Imported database equals an independently imported copy (sqldiff)' $false "sqldiff not found at '$diffExe'") }
        $r = Invoke-ClientProcess $diffExe @($A, $B) ''
    }
    $clean = ($r.ExitCode -eq 0 -and $r.Stdout.Trim().Length -eq 0 -and $r.Stderr.Trim().Length -eq 0)
    $detail = if ($clean) { 'sqldiff reported no differences' } else { "$($r.Stdout.Trim()) $($r.Stderr.Trim())".Trim() }
    return (New-Check 'sqldiff' 'Imported database equals an independently imported copy (sqldiff)' $clean $detail)
}

function global:Sqlite-KnownDifferences($Settings) {
    $list = @(
        'SQLite has no separate date type: dates are stored as ISO-8601 text (yyyy-MM-dd HH:mm:ss.fffffff) and compared as such. Yes/no columns are stored as integers 0/1 and protected by a CHECK constraint.',
        'SQLite does not enforce VARCHAR lengths; the declared lengths are kept for documentation.',
        'SQLite compares text case-sensitively, whereas the SQL Server database uses a case-insensitive collation. The migrated data already satisfies SQL Server''s rules, but new rows inserted directly into SQLite are not protected against case-only duplicates (for example usernames "Bob" and "bob").',
        'Index names that were duplicated across tables in SQL Server (for example IX_UserId) are prefixed with the table name, because index names are database-wide in SQLite.'
    )
    if (Sqlite-IsDocker $Settings) {
        $list += 'The database was created and checked by the Linux build of SQLite running in a Docker container (Alpine Linux); the native Windows target (iteration 1) used a different SQLite version. The SQLite file format is identical on both, so a file built on one platform opens on the other. The database file lives inside the container; a copy is taken out with docker cp after the import.'
    }
    return $list
}

function New-Dialect($Settings) {
    $docker = ($Settings -and (Sqlite-IsDocker $Settings))
    return @{
        Name             = 'sqlite'
        DisplayName      = $(if ($docker) { 'SQLite (Linux container)' } else { 'SQLite' })
        KnownDifferences = (Sqlite-KnownDifferences $Settings)
        RenderSchema     = { param($m, $s) Sqlite-RenderSchema $m $s }
        RenderData       = { param($m, $r) Sqlite-RenderData $m $r }
        TargetId         = { param($st, $ov)
            if (Sqlite-IsDocker $st) { if ($ov) { return $ov } else { return [string]$st.file } }
            if ($ov) { Resolve-RepoPath $ov } else { Resolve-RepoPath ([string]$st.file) } }
        Exists           = { param($st, $id) Sqlite-FileExists $st $id }
        Fingerprint      = { param($st, $id)
            if (Sqlite-IsDocker $st) { return (((Sqlite-Docker $st @('sha256sum', $id) '').Stdout.Trim() -split '\s+')[0]) }
            Get-FileSha256 $id }
        Import           = { param($st, $id, $sch, $dat, $rc) Sqlite-Import $st $id $sch $dat -Recreate:$rc }
        Publish          = { param($st, $id, $hostDir) Sqlite-Publish $st $id $hostDir }
        ReadRows         = { param($st, $id, $t) Sqlite-ReadRows $st $id $t }
        Query            = { param($st, $id, $sql) Sqlite-Query $st $id $sql }
        Run              = { param($st, $id, $sql) Sqlite-Run $st $id $sql }
        Version          = { param($st) Sqlite-VersionText $st }
        SchemaChecks     = { param($st, $id, $m) Sqlite-SchemaChecks $st $id $m }
        Behaviour        = { param($st, $id, $m, $sch, $dat) Sqlite-BehaviourTests $st $id $m }
        NewScratchId     = { param($st, $label) Sqlite-NewScratchId $st $label }
        Clone            = { param($st, $src, $dst, $sch, $dat) Sqlite-Clone $st $src $dst $sch $dat }
        Remove           = { param($st, $id) Sqlite-Remove $st $id }
        Diff             = { param($st, $a, $b, $m) Sqlite-Diff $st $a $b $m }
        DamageSql        = { param($cid, $tid) Sqlite-DamageSql $cid $tid }
    }
}