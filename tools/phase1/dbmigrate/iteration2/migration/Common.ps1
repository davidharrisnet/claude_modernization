# Shared helpers for the database migration tooling (dot-sourced by DbMigrate.ps1).
# Deterministic by design: sorted metadata, invariant culture, UTF-8 without BOM, no clock
# values in anything that is exported.

$script:MigrationRoot = $PSScriptRoot
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Columns whose values are compared but never printed (credential-equivalent data).
$script:RedactedColumns = @('PasswordHash', 'SecurityStamp')

Add-Type -TypeDefinition @"
using System;
public class MigrationException : Exception {
    public int ExitCode;
    public MigrationException(string message, int exitCode) : base(message) { ExitCode = exitCode; }
}
"@

function New-MigrationError([string]$Message, [int]$ExitCode) {
    return (New-Object MigrationException($Message, $ExitCode))
}

function Resolve-RepoPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $Path))
}

function Get-MigrationConfig([string]$Path) {
    if (-not $Path) { $Path = Join-Path $script:MigrationRoot 'migration.config.json' }
    $Path = Resolve-RepoPath $Path
    if (-not (Test-Path $Path)) { throw (New-MigrationError "Config file not found: $Path" 2) }
    return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# ---------------------------------------------------------------- source (SQL Server)

function Open-SourceConnection($Source) {
    if ($Source.server -match '^\(localdb\)\\(.+)$') {
        # Same cold-start guard as Scripts\Reset-Database.ps1.
        & SqlLocalDB.exe start $Matches[1] | Out-Null
    }
    $cs = "Data Source=$($Source.server);Initial Catalog=$($Source.database);Integrated Security=SSPI;Connect Timeout=60"
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    try { $conn.Open() } catch { throw (New-MigrationError "Cannot connect to source '$($Source.server)' / '$($Source.database)': $($_.Exception.Message)" 2) }
    return $conn
}

function Invoke-SourceQuery($Conn, [string]$Sql) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 120
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    return , @($dt.Rows)
}

function Get-TypeKind([string]$TypeName) {
    switch ($TypeName) {
        { $_ -in 'int', 'bigint', 'smallint', 'tinyint' } { return 'int' }
        'bit' { return 'bit' }
        { $_ -in 'nvarchar', 'varchar', 'nchar', 'char', 'ntext', 'text' } { return 'string' }
        { $_ -in 'datetime', 'datetime2', 'smalldatetime' } { return 'datetime' }
        { $_ -in 'varbinary', 'binary', 'image' } { return 'binary' }
        'uniqueidentifier' { return 'guid' }
        default { throw (New-MigrationError "Unsupported SQL Server type '$TypeName' - add an explicit mapping before exporting." 2) }
    }
}

function Get-SourceModel($Conn) {
    $tableRows = Invoke-SourceQuery $Conn @"
SELECT t.object_id, t.name FROM sys.tables t
WHERE t.is_ms_shipped = 0 AND SCHEMA_NAME(t.schema_id) = 'dbo' AND t.name <> '__MigrationHistory'
ORDER BY t.name
"@
    $colRows = Invoke-SourceQuery $Conn @"
SELECT c.object_id, c.column_id, c.name, ty.name AS type_name, c.max_length, c.is_nullable, c.is_identity,
       c.collation_name, CAST(ic.last_value AS bigint) AS last_value
FROM sys.columns c
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
ORDER BY c.object_id, c.column_id
"@
    $pkRows = Invoke-SourceQuery $Conn @"
SELECT i.object_id, ic.key_ordinal, col.name
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
WHERE i.is_primary_key = 1
ORDER BY i.object_id, ic.key_ordinal
"@
    $ixRows = Invoke-SourceQuery $Conn @"
SELECT i.object_id, i.name, i.is_unique, i.filter_definition, ic.key_ordinal, ic.is_descending_key, col.name AS col_name
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
WHERE i.is_primary_key = 0 AND i.is_hypothetical = 0 AND i.type > 0 AND i.name IS NOT NULL
ORDER BY i.object_id, i.name, ic.key_ordinal
"@
    $fkRows = Invoke-SourceQuery $Conn @"
SELECT fk.name, fk.parent_object_id, fk.referenced_object_id, fk.delete_referential_action_desc AS on_delete,
       fkc.constraint_column_id, pc.name AS parent_col, rc.name AS ref_col
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
ORDER BY fk.name, fkc.constraint_column_id
"@
    $defaults = Invoke-SourceQuery $Conn "SELECT parent_object_id AS object_id, parent_column_id AS column_id, COL_NAME(parent_object_id, parent_column_id) AS col_name, definition FROM sys.default_constraints"

    $byId = @{}
    $tables = New-Object System.Collections.ArrayList
    foreach ($t in $tableRows) {
        $tbl = [pscustomobject]@{ Name = [string]$t.name; ObjectId = [int]$t.object_id; Columns = (New-Object System.Collections.ArrayList); PrimaryKey = (New-Object System.Collections.ArrayList); Indexes = (New-Object System.Collections.ArrayList); ForeignKeys = (New-Object System.Collections.ArrayList); Identity = $null; IdentityLast = $null }
        $byId[$tbl.ObjectId] = $tbl
        [void]$tables.Add($tbl)
    }
    foreach ($c in $colRows) {
        $tbl = $byId[[int]$c.object_id]
        if (-not $tbl) { continue }
        $typeName = [string]$c.type_name
        $len = [int]$c.max_length
        if (($typeName -eq 'nvarchar' -or $typeName -eq 'nchar') -and $len -gt 0) { $len = [int]($len / 2) }
        $collation = $null
        if ($c.collation_name -isnot [System.DBNull]) { $collation = [string]$c.collation_name }
        $col = [pscustomobject]@{ Name = [string]$c.name; TypeName = $typeName; Kind = (Get-TypeKind $typeName); Length = $len; Nullable = [bool]$c.is_nullable; IsIdentity = [bool]$c.is_identity; Default = $null; Collation = $collation }
        [void]$tbl.Columns.Add($col)
        if ($col.IsIdentity) {
            $tbl.Identity = $col.Name
            if ($c.last_value -isnot [System.DBNull]) { $tbl.IdentityLast = [int64]$c.last_value }
        }
    }
    foreach ($p in $pkRows) {
        $tbl = $byId[[int]$p.object_id]
        if ($tbl) { [void]$tbl.PrimaryKey.Add([string]$p.name) }
    }
    $ixByKey = @{}
    foreach ($r in $ixRows) {
        $tbl = $byId[[int]$r.object_id]
        if (-not $tbl) { continue }
        $key = "$($r.object_id)|$($r.name)"
        if (-not $ixByKey.ContainsKey($key)) {
            $filter = $null
            if ($r.filter_definition -isnot [System.DBNull]) { $filter = [string]$r.filter_definition }
            $ix = [pscustomobject]@{ Name = [string]$r.name; Table = $tbl.Name; Unique = [bool]$r.is_unique; Filter = $filter; Columns = (New-Object System.Collections.ArrayList); TargetName = $null }
            $ixByKey[$key] = $ix
            [void]$tbl.Indexes.Add($ix)
        }
        [void]$ixByKey[$key].Columns.Add([pscustomobject]@{ Name = [string]$r.col_name; Descending = [bool]$r.is_descending_key })
    }
    $fkByKey = @{}
    foreach ($r in $fkRows) {
        $parent = $byId[[int]$r.parent_object_id]
        $ref = $byId[[int]$r.referenced_object_id]
        if (-not $parent -or -not $ref) { continue }
        $key = "$($r.parent_object_id)|$($r.name)"
        if (-not $fkByKey.ContainsKey($key)) {
            $fk = [pscustomobject]@{ Name = [string]$r.name; Table = $parent.Name; RefTable = $ref.Name; OnDelete = ([string]$r.on_delete).Replace('_', ' '); Columns = (New-Object System.Collections.ArrayList); RefColumns = (New-Object System.Collections.ArrayList) }
            $fkByKey[$key] = $fk
            [void]$parent.ForeignKeys.Add($fk)
        }
        [void]$fkByKey[$key].Columns.Add([string]$r.parent_col)
        [void]$fkByKey[$key].RefColumns.Add([string]$r.ref_col)
    }
    foreach ($d in $defaults) {
        $tbl = $byId[[int]$d.object_id]
        if (-not $tbl) { continue }
        $col = $tbl.Columns | Where-Object { $_.Name -ceq [string]$d.col_name } | Select-Object -First 1
        # Only plain integer / string literal defaults are understood: ((0)), (N'x'), ('x').
        $def = [string]$d.definition
        while ($def.StartsWith('(') -and $def.EndsWith(')')) { $def = $def.Substring(1, $def.Length - 2) }
        if ($def -match '^-?\d+$') { $col.Default = $def }
        elseif ($def -match "^N?'((?:[^']|'')*)'$") { $col.Default = "'" + $Matches[1] + "'" }
        else { throw (New-MigrationError "Unsupported column default on $($tbl.Name).$($col.Name): $($d.definition)" 2) }
    }

    # Index names are schema-global in SQLite/PostgreSQL but only table-scoped in SQL Server
    # (EF names half its indexes 'IX_UserId'). Keep the original name when it is unique across
    # the whole database, otherwise prefix it with the table name.
    $all = @()
    foreach ($t in $tables) { foreach ($ix in $t.Indexes) { $all += $ix } }
    $counts = @{}
    foreach ($ix in $all) { $counts[$ix.Name] = 1 + [int]$counts[$ix.Name] }
    foreach ($ix in $all) {
        if ($counts[$ix.Name] -gt 1) { $ix.TargetName = "$($ix.Table)_$($ix.Name)" } else { $ix.TargetName = $ix.Name }
    }

    $sorted = Sort-TablesByDependency $tables
    return [pscustomobject]@{ Tables = $sorted }
}

# Kahn's algorithm, always taking the alphabetically-smallest ready table so output is stable.
function Sort-TablesByDependency($Tables) {
    $remaining = New-Object System.Collections.ArrayList
    $names = @($Tables | ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    foreach ($n in $names) { [void]$remaining.Add(($Tables | Where-Object { $_.Name -ceq $n } | Select-Object -First 1)) }
    $done = @{}
    $result = New-Object System.Collections.ArrayList
    while ($remaining.Count -gt 0) {
        $picked = $null
        foreach ($t in $remaining) {
            $ready = $true
            foreach ($fk in $t.ForeignKeys) {
                if ($fk.RefTable -ne $t.Name -and -not $done.ContainsKey($fk.RefTable)) { $ready = $false; break }
            }
            if ($ready) { $picked = $t; break }
        }
        if (-not $picked) { throw (New-MigrationError "Circular foreign key dependency among: $(($remaining | ForEach-Object { $_.Name }) -join ', ')" 2) }
        [void]$result.Add($picked)
        $done[$picked.Name] = $true
        $remaining.Remove($picked)
    }
    return , @($result)
}

# ---------------------------------------------------------------- canonical value form

# One text form per value that both engines can be reduced to. NULL stays $null.
function ConvertTo-Canonical($Value, [string]$Kind) {
    if ($Value -is [System.DBNull] -or $null -eq $Value) { return $null }
    switch ($Kind) {
        'int' { return ([System.Convert]::ToInt64($Value)).ToString($script:Inv) }
        'bit' { if ([bool]$Value) { return '1' } else { return '0' } }
        'datetime' { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss.fffffff', $script:Inv) }
        'binary' { return ([System.BitConverter]::ToString([byte[]]$Value)).Replace('-', '') }
        'guid' { return ([guid]$Value).ToString('D').ToLowerInvariant() }
        'string' { return [string]$Value }
    }
    throw (New-MigrationError "No canonical form for kind '$Kind'" 2)
}

# SQLite storage class letter (from typeof()) a canonical value must end up in.
function Get-ExpectedStorageClass([string]$Kind) {
    switch ($Kind) {
        { $_ -in 'int', 'bit' } { return 'i' }
        'binary' { return 'b' }
        default { return 't' }
    }
}

function ConvertTo-HexUtf8([string]$Text) {
    if ($Text.Length -eq 0) { return '' }
    $bytes = $script:Utf8NoBom.GetBytes($Text)
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '')
}

function ConvertFrom-HexUtf8([string]$Hex) {
    if ($Hex.Length -eq 0) { return '' }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [System.Convert]::ToByte($Hex.Substring(2 * $i, 2), 16) }
    return $script:Utf8NoBom.GetString($bytes)
}

# ---------------------------------------------------------------- credential sanitization (opt-in per target)

# One-time-bootstrap credential policy (docs/phase1/dbmigrate/DATA_MIGRATION.md §5.2): mutates $Table and $Rows in place,
# in memory, before RenderSchema/RenderData (export) or a source-vs-target comparison (verify) ever sees
# them - so a raw PasswordHash/SecurityStamp value never reaches disk. $Rows is the ArrayList of canonical
# row arrays for $Table (as returned by Read-SourceRows). No-op for any table but Users, so callers can
# invoke it unconditionally per table without checking the name themselves.
function Protect-SensitiveData($Table, $Rows) {
    if ($Table.Name -cne 'Users') { return }
    $pwIdx = -1; $stampIdx = -1
    for ($i = 0; $i -lt $Table.Columns.Count; $i++) {
        if ($Table.Columns[$i].Name -ceq 'PasswordHash') { $pwIdx = $i }
        if ($Table.Columns[$i].Name -ceq 'SecurityStamp') { $stampIdx = $i }
    }
    if ($pwIdx -lt 0 -or $stampIdx -lt 0) { throw (New-MigrationError "Protect-SensitiveData: Users table is missing PasswordHash/SecurityStamp." 2) }
    [void]$Table.Columns.Add([pscustomobject]@{ Name = 'MustResetPassword'; TypeName = 'bit'; Kind = 'bit'; Length = 0; Nullable = $false; IsIdentity = $false; Default = '0'; Collation = $null })
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $old = $Rows[$r]
        $new = New-Object 'object[]' ($old.Length + 1)
        [Array]::Copy($old, $new, $old.Length)
        $new[$pwIdx] = $null
        $new[$stampIdx] = $null
        $new[$new.Length - 1] = '1'
        $Rows[$r] = $new
    }
}

# Reads a whole table from the source as canonical rows (string[] per row, $null = NULL).
function Read-SourceRows($Conn, $Table) {
    $cols = ($Table.Columns | ForEach-Object { "[$($_.Name)]" }) -join ', '
    $order = if ($Table.PrimaryKey.Count -gt 0) { ($Table.PrimaryKey | ForEach-Object { "[$_]" }) -join ', ' } else { $cols }
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = "SELECT $cols FROM [dbo].[$($Table.Name)] ORDER BY $order"
    $cmd.CommandTimeout = 300
    $reader = $cmd.ExecuteReader()
    $rows = New-Object System.Collections.ArrayList
    try {
        while ($reader.Read()) {
            $fields = New-Object 'object[]' $Table.Columns.Count
            for ($i = 0; $i -lt $Table.Columns.Count; $i++) {
                $fields[$i] = ConvertTo-Canonical $reader.GetValue($i) $Table.Columns[$i].Kind
            }
            [void]$rows.Add($fields)
        }
    } finally { $reader.Close() }
    return , $rows
}

# ---------------------------------------------------------------- external clients

function Invoke-ClientProcess([string]$Exe, [string[]]$ArgList, [string]$StdinText) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($ArgList | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if ($StdinText) {
        $bytes = $script:Utf8NoBom.GetBytes($StdinText)
        try {
            $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
            $p.StandardInput.BaseStream.Flush()
        } catch [System.IO.IOException] { } # client exited early (e.g. -bail); its exit code/stderr tell the story
    }
    try { $p.StandardInput.Close() } catch { }
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $outTask.Result; Stderr = $errTask.Result }
}

function Write-TextFile([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-FileSha256([string]$Path) {
    return Get-Sha256Hex ([System.IO.File]::ReadAllBytes($Path))
}

# ---------------------------------------------------------------- Docker runner (for targets that live in a container)

function Get-DockerExe {
    $c = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $c) { throw (New-MigrationError "docker was not found on PATH. Install/start Docker Desktop, or change the target's runner mode." 2) }
    return $c.Source
}

function Invoke-Docker([string[]]$ArgList, [string]$StdinText) {
    return Invoke-ClientProcess (Get-DockerExe) $ArgList $StdinText
}

function Assert-DockerRunning {
    $r = Invoke-Docker @('info', '--format', '{{.ServerVersion}}') ''
    if ($r.ExitCode -ne 0) { throw (New-MigrationError "The Docker daemon is not running. Start Docker Desktop, wait until it says running, and retry.`n$($r.Stderr.Trim())" 2) }
}

# Makes sure a named container exists and is running. $RunArgs are appended to `docker run -d --name <name>`
# (environment, image, and the image's own arguments). Returns $true when it had to create the container.
function Confirm-DockerContainer([string]$Name, [string[]]$RunArgs, [bool]$AutoCreate) {
    Assert-DockerRunning
    $r = Invoke-Docker @('inspect', '-f', '{{.State.Running}}', $Name) ''
    if ($r.ExitCode -ne 0) {
        if (-not $AutoCreate) { throw (New-MigrationError "Docker container '$Name' does not exist and autoStart is off." 2) }
        Write-Host "Creating Docker container '$Name' (the first run downloads the image, which can take a few minutes) ..."
        $create = Invoke-Docker (@('run', '-d', '--name', $Name) + $RunArgs) ''
        if ($create.ExitCode -ne 0) { throw (New-MigrationError "docker run failed: $($create.Stderr.Trim())" 2) }
        return $true
    }
    if ($r.Stdout.Trim() -ne 'true') {
        Write-Host "Starting Docker container '$Name' ..."
        $start = Invoke-Docker @('start', $Name) ''
        if ($start.ExitCode -ne 0) { throw (New-MigrationError "docker start failed: $($start.Stderr.Trim())" 2) }
    }
    return $false
}

# ---------------------------------------------------------------- dialect / target loading

function Get-Dialect([string]$Name, $Settings) {
    $file = Join-Path $script:MigrationRoot "dialects\$Name.ps1"
    if (-not (Test-Path $file)) {
        $known = (Get-ChildItem (Join-Path $script:MigrationRoot 'dialects') -Filter *.ps1 | ForEach-Object { $_.BaseName }) -join ', '
        throw (New-MigrationError "No dialect '$Name'. Implemented dialects: $known" 2)
    }
    . $file
    return (New-Dialect $Settings)
}

function Get-TargetSettings($Config, [string]$Target) {
    $t = $Config.targets.$Target
    if (-not $t) { throw (New-MigrationError "Target '$Target' is not defined in the config file." 2) }
    return $t
}

# ---------------------------------------------------------------- check helpers

# Compares two string collections as sets; the result carries counts and (capped) differences.
function New-SetCheck([string]$Category, [string]$Name, $Expected, $Actual) {
    $exp = @{}; foreach ($e in $Expected) { $exp[[string]$e] = $true }
    $act = @{}; foreach ($a in $Actual) { $act[[string]$a] = $true }
    $missing = @($exp.Keys | Where-Object { -not $act.ContainsKey($_) } | Sort-Object)
    $extra = @($act.Keys | Where-Object { -not $exp.ContainsKey($_) } | Sort-Object)
    $detail = @()
    foreach ($m in ($missing | Select-Object -First 10)) { $detail += "missing in target: $m" }
    foreach ($x in ($extra | Select-Object -First 10)) { $detail += "unexpected in target: $x" }
    return [pscustomobject]@{
        Category = $Category; Name = $Name
        Source = $exp.Count; Target = $act.Count
        Passed = (($missing.Count + $extra.Count) -eq 0)
        Detail = ($detail -join '; ')
    }
}

function New-Check([string]$Category, [string]$Name, [bool]$Passed, [string]$Detail) {
    return [pscustomobject]@{ Category = $Category; Name = $Name; Source = $null; Target = $null; Passed = $Passed; Detail = $Detail }
}

function Get-GitCommit {
    try {
        $h = & git -C $script:RepoRoot rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $h) { return "$h".Trim() }
    } catch { }
    return 'unknown'
}
