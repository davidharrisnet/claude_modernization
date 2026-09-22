# guide: builds a Word document (.docx) that describes the migrated SQLite database, its version and how to
# access and use it. Everything about the schema is read from the delivered database file, so the guide cannot
# drift from it. Reuses the OpenXML helpers in Report.ps1 (Rn, Pg, PT, Bullet, Table, Save-Docx).
# The guide never contains password hashes, security stamps or passwords.

# Credential columns are listed in the schema like any other column but are flagged, and never queried.
$script:GuideCredentialColumns = @('PasswordHash', 'SecurityStamp')

# One monospace paragraph per line (Code style is defined in Get-StylesXml).
function Code([string]$Text) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($line in ($Text -split "`r?`n")) { [void]$sb.Append((Pg (Rn $line) 'Code')) }
    return $sb.ToString()
}

function H1([string]$Text) { return (Pg (Rn $Text) 'Heading1') }
function H2([string]$Text) { return (Pg (Rn $Text) 'Heading2') }

# Runs a query through the dialect and returns rows split into cells.
function Get-GuideRows($Settings, [string]$Db, [string]$Sql) {
    $rows = New-Object System.Collections.ArrayList
    foreach ($r in (Sqlite-Query $Settings $Db $Sql)) { [void]$rows.Add(([string]$r -split '\|')) }
    return , $rows
}

function Build-GuideDocument($Settings, [string]$Db, [string]$DisplayPath, $Results) {
    $script:BreakNext = $false
    $b = New-Object System.Text.StringBuilder
    $add = { param($x) [void]$b.Append($x) }

    $version = (Sqlite-Query $Settings $Db 'SELECT sqlite_version();')[0]
    $sizeKb = [Math]::Round((Get-Item $Db).Length / 1KB)
    $tables = [string[]](Sqlite-Query $Settings $Db "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
    $ran = if ($Results) { "$($Results.Meta.RunTimeUtc) UTC" } else { 'n/a' }

    & $add (Pg (Rn 'MasterAntiqueRepair' $true '1F3864' 64) 'Title')
    & $add (Pg (Rn 'SQLite Database Guide') 'Subtitle')
    & $add (Table @(2400, 6960) @('Item', 'Value') @(@('Iteration', '1 - SQL Server LocalDB to SQLite on Windows'), @('File', $DisplayPath), @('Size', "$sizeKb KB"), @('SQLite version', "$version (64-bit command-line build used for the migration)"), @('Tables', "$($tables.Count) (eight application tables; the EF __MigrationHistory table was deliberately not migrated)"), @('Created by', "dbmigrate export/import run on $ran")))

    # ---------------------------------------------------------------- 1
    & $add (H1 '1. What this database is')
    & $add (PT 'This is a SQLite copy of the MasterAntiqueRepair repair-shop database. The source is the SQL Server LocalDB database of the legacy ASP.NET Web Forms application. The structure, keys, relationships, indexes, defaults and every row were exported by a deterministic script and rebuilt in SQLite. The verification report (MigrationVerificationReport1.docx, in the same folder as this guide) proves the copy is identical: every row and value matched, and the structure and business rules were checked.')
    & $add (PT 'It is a single file with no server to run. It is the baseline data set for Phase 2 of the modernization: the reference database that the Spring Boot / Angular application is compared against.')

    # ---------------------------------------------------------------- 2
    & $add (H1 '2. Version and file format')
    & $add (Bullet "SQLite $version. The database file format is stable across SQLite 3.x and is identical on Windows and Linux, so this file opens with any modern SQLite build.")
    & $add (Bullet 'Java: the xerial sqlite-jdbc driver (JDBC URL jdbc:sqlite:<path>) reads it directly, which is the likely route for the Phase 2 Spring Boot application.')
    & $add (Bullet 'Iteration 2 builds the same database in a Docker Linux container with a different SQLite version. The file format is the same; only the tool version differs.')

    # ---------------------------------------------------------------- 3
    & $add (H1 '3. Accessing the database')
    & $add (H2 'Command line')
    & $add (PT 'Open a copy of the file rather than the delivered file, so experiments cannot change it:')
    & $add (Code "copy $($DisplayPath.Replace('/', '\')) work.sqlite`nsqlite3 work.sqlite`nsqlite> .headers on`nsqlite> .mode column`nsqlite> .tables`nsqlite> .schema Tickets`nsqlite> PRAGMA foreign_keys = ON;")
    & $add (H2 'Graphical tools')
    & $add (PT 'Any SQLite browser (for example DB Browser for SQLite) can open the file. Open it read-only unless you are working on a copy.')
    & $add (H2 'From Java (JDBC)')
    & $add (Code "String url = ""jdbc:sqlite:C:/path/to/masterantique.sqlite"";`ntry (Connection c = DriverManager.getConnection(url);`n     Statement s = c.createStatement()) {`n    s.execute(""PRAGMA foreign_keys = ON"");   // per connection`n    ResultSet rs = s.executeQuery(""SELECT COUNT(*) FROM Users"");`n}")
    & $add (PT 'SQLite does not enforce foreign keys unless PRAGMA foreign_keys = ON is issued on every connection. The schema declares the relationships and delete rules; the pragma makes SQLite apply them.')

    # ---------------------------------------------------------------- 4
    & $add (H1 '4. Schema')
    $counts = @{}
    foreach ($t in $tables) { $counts[$t] = (Sqlite-Query $Settings $Db "SELECT COUNT(*) FROM ""$t"";")[0] }
    $sumRows = @($tables | ForEach-Object { , @($_, [string]$counts[$_]) })
    & $add (PT 'Tables and the number of rows they hold in this run:')
    & $add (Table @(6000, 3360) @('Table', 'Rows') $sumRows)

    foreach ($t in $tables) {
        & $add (H2 $t)
        $colRows = New-Object System.Collections.ArrayList
        foreach ($c in (Get-GuideRows $Settings $Db "SELECT p.name, p.type, p.""notnull"", COALESCE(p.dflt_value, ''), p.pk FROM pragma_table_info('$t') p ORDER BY p.cid;")) {
            $note = ''
            if ($c[4] -ne '0') { $note = 'Primary key' }
            if ($script:GuideCredentialColumns -contains $c[0]) { $note = 'Identity credential field (values are not shown in this guide)' }
            [void]$colRows.Add(@($c[0], $c[1], $(if ($c[2] -eq '1') { 'Yes' } else { 'No' }), $c[3], $note))
        }
        & $add (Table @(2100, 1500, 1000, 1760, 3000) @('Column', 'Type', 'Required', 'Default', 'Notes') $colRows)
    }

    & $add (H2 'Relationships (foreign keys)')
    $fkRows = New-Object System.Collections.ArrayList
    foreach ($f in (Get-GuideRows $Settings $Db "SELECT m.name, f.""from"", f.""table"", f.""to"", f.on_delete FROM sqlite_master m, pragma_foreign_key_list(m.name) f WHERE m.type = 'table' ORDER BY m.name, f.""from"";")) {
        [void]$fkRows.Add(@($f[0], $f[1], "$($f[2]).$($f[3])", $f[4]))
    }
    & $add (Table @(2100, 2200, 2800, 2260) @('Table', 'Column', 'References', 'On delete') $fkRows)

    & $add (H2 'Indexes')
    $ixRows = New-Object System.Collections.ArrayList
    foreach ($i in (Get-GuideRows $Settings $Db "SELECT m.name, i.name, CASE i.""unique"" WHEN 1 THEN 'Unique' ELSE '' END, CASE i.partial WHEN 1 THEN 'Partial' ELSE '' END FROM sqlite_master m, pragma_index_list(m.name) i WHERE m.type = 'table' AND i.origin = 'c' ORDER BY m.name, i.name;")) {
        [void]$ixRows.Add(@($i[0], $i[1], $i[2], $i[3]))
    }
    & $add (Table @(2100, 3600, 1600, 2060) @('Table', 'Index', 'Unique', 'Partial') $ixRows)
    & $add (PT 'IX_Users_Name_Active is the important one: it is a unique index on Users.Name that only covers rows where DeletedAt IS NULL. An account that has been soft-deleted (DeletedAt set) keeps its row but frees its user name for reuse.')

    # ---------------------------------------------------------------- 5
    & $add (H1 '5. Using it: what the values mean')
    & $add (Bullet 'Users is one table for all account types (table-per-hierarchy). Discriminator holds Customer, Employee or Manager. Name is the login (the ASP.NET Identity UserName). Soft delete: DeletedAt IS NULL means the account is active.')
    & $add (Bullet 'Roles and UserRoles hold the role assignments (Customer = 1, Employee = 2, Manager = 3 in this database). UserClaims and UserLogins are Identity tables and are empty.')
    & $add (Bullet 'Tickets.Customer_Id is the submitter. Tickets.User_Id is the assigned employee and is NULL until an employee takes the ticket.')
    & $add (Bullet 'Comments are add-only in the application; nothing ever edits or deletes them.')
    & $add (Bullet 'Dates (DATETIME columns) are ISO-8601 text in the form yyyy-MM-dd HH:mm:ss.fffffff. They sort correctly as text; use SQLite date functions such as date() and strftime() to work with them.')
    & $add (Bullet 'Yes/no columns are INTEGER 0 or 1, protected by CHECK constraints.')
    & $add (Bullet 'VARCHAR(n) lengths are documentation only; SQLite does not enforce them. The application limits comment and description text to 2000 characters.')
    & $add (Bullet 'Text comparison is case-sensitive in SQLite but was case-insensitive in SQL Server. Rows inserted directly into SQLite are not protected against user names that differ only by case.')
    & $add (Bullet 'Integer-coded columns are enums in the legacy application. The tables below give the meaning of each value.')
    & $add (H2 'Ticket state (Tickets.State)')
    & $add (Table @(1500, 4000) @('Value', 'Meaning') @(@('0', 'SUBMITTED'), @('1', 'INPROGRESS'), @('2', 'COMPLETED')))
    & $add (H2 'Audit action (AuditLogs.Action)')
    $actions = 'CreateUser', 'Login', 'CreateTicket', 'AssignTicket', 'CompleteTicket', 'AddComment', 'EditComment', 'DeleteComment', 'RequestPasswordReset', 'ResetPassword', 'EditUser', 'DeleteUser'
    $actRows = @(for ($i = 0; $i -lt $actions.Count; $i++) { , @([string]$i, $actions[$i]) })
    & $add (Table @(1500, 4000) @('Value', 'Meaning') $actRows)
    & $add (PT 'EditComment and DeleteComment remain defined so that historical audit rows still make sense; the application no longer writes them.')
    & $add (H2 'Audit entity type (AuditLogs.EntityType)')
    & $add (Table @(1500, 4000) @('Value', 'Meaning') @(@('0', 'User'), @('1', 'Ticket'), @('2', 'Comment')))
    & $add (PT 'The audit log stores ids and timestamps only, never comment text or ticket descriptions. AuditLogs.EntityId is the id of the row in the table named by EntityType. This log format is what Phase 2 must preserve or improve on.')

    # ---------------------------------------------------------------- 6
    & $add (H1 '6. Example queries')
    & $add (PT 'Each query below was run against this database when the guide was generated; the results shown are the actual output.')
    $examples = @(
        @{ Title = 'Tickets by state'; Header = @('State', 'Tickets'); Widths = @(4680, 4680)
           Sql = "SELECT CASE State WHEN 0 THEN 'SUBMITTED' WHEN 1 THEN 'INPROGRESS' WHEN 2 THEN 'COMPLETED' END, COUNT(*)`nFROM Tickets GROUP BY State ORDER BY State;" },
        @{ Title = 'Active versus soft-deleted accounts by type'; Header = @('Type', 'Accounts', 'Active', 'Soft-deleted'); Widths = @(3360, 2000, 2000, 2000)
           Sql = "SELECT Discriminator, COUNT(*), SUM(DeletedAt IS NULL), SUM(DeletedAt IS NOT NULL)`nFROM Users GROUP BY Discriminator ORDER BY Discriminator;" },
        @{ Title = 'First five tickets with submitter and assignee'; Header = @('Ticket', 'Customer', 'Assigned to'); Widths = @(1500, 3930, 3930)
           Sql = "SELECT t.Id, c.Name, COALESCE(e.Name, '(unassigned)')`nFROM Tickets t`nJOIN Users c ON c.Id = t.Customer_Id`nLEFT JOIN Users e ON e.Id = t.User_Id`nORDER BY t.Id LIMIT 5;" },
        @{ Title = 'Audit events by action'; Header = @('Action', 'Events'); Widths = @(4680, 4680)
           Sql = "SELECT CASE Action WHEN 0 THEN 'CreateUser' WHEN 1 THEN 'Login' WHEN 2 THEN 'CreateTicket' WHEN 3 THEN 'AssignTicket' WHEN 4 THEN 'CompleteTicket' WHEN 5 THEN 'AddComment' ELSE 'Other' END, COUNT(*)`nFROM AuditLogs GROUP BY Action ORDER BY Action;" }
    )
    foreach ($ex in $examples) {
        & $add (H2 $ex.Title)
        & $add (Code $ex.Sql)
        $out = New-Object System.Collections.ArrayList
        foreach ($r in (Get-GuideRows $Settings $Db $ex.Sql)) { [void]$out.Add($r) }
        & $add (Table $ex.Widths $ex.Header $out)
    }

    # ---------------------------------------------------------------- 7
    & $add (H1 '7. Credentials')
    if ($Settings.sanitizeCredentials) {
        & $add (PT 'The Users table contains the Identity credential columns PasswordHash and SecurityStamp. As part of this migration''s one-time-bootstrap policy, every row has these set to NULL, and a new MustResetPassword column set to 1: no usable legacy credential was carried into this database, and every migrated account must reset its password on first login. This guide does not show credential values and none of its queries read them.')
    } else {
        & $add (PT 'The Users table contains the Identity credential columns PasswordHash and SecurityStamp, copied unchanged from the source so the copy is complete. This guide does not show their values and none of its queries read them. Treat the database file as sensitive and do not share or commit it.')
    }

    # ---------------------------------------------------------------- 8
    & $add (H1 '8. Regenerating the database and this guide')
    & $add (Code 'tools\dbmigrate\dbmigrate.cmd all --target sqlite')
    & $add (PT 'This exports from the SQL Server LocalDB source (the instance must be available), rebuilds the SQLite file, verifies it, runs the tooling self-test and writes the verification report. To rebuild only this guide from the existing database file:')
    & $add (Code 'tools\dbmigrate\dbmigrate.cmd guide --target sqlite')
    & $add (PT 'Exit codes: 0 success, 1 verification differences, 2 configuration or tool error, 3 refused because the target already exists.')

    return $b.ToString()
}

function Invoke-Guide($Config, [string]$Target, [string]$Out) {
    $settings = Get-TargetSettings $Config $Target
    if ($settings.dialect -ne 'sqlite') { throw (New-MigrationError "The guide is only implemented for the sqlite dialect (target '$Target' uses '$($settings.dialect)')." 2) }
    $dialect = Get-Dialect $settings.dialect $settings   # loads the dialect so Sqlite-Query is available
    $paths = Get-TargetPaths $Config $Target
    $db = Resolve-RepoPath ([string]$settings.file)
    if (-not (Test-Path $db)) { throw (New-MigrationError "Database file not found: $db - run 'import' first." 2) }
    $results = if (Test-Path $paths.Results) { Get-Content $paths.Results -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $outFile = if ($Out) { Resolve-RepoPath $Out } else { $paths.Guide }

    $images = [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList) }
    $body = Build-GuideDocument $settings $db ([string]$settings.file) $results
    $created = if ($results) { ([datetime]::ParseExact($results.Meta.RunTimeUtc, 'yyyy-MM-dd HH:mm:ss', $script:Inv)).ToString('yyyy-MM-ddTHH:mm:ssZ', $script:Inv) } else { '2000-01-01T00:00:00Z' }
    $iter = if ($settings.iteration) { "Iteration $($settings.iteration) - " } else { '' }
    Save-Docx $outFile $body $images "$iter$($settings.iterationTitle)" $created 'MasterAntiqueRepair - SQLite Database Guide' 'SQLite Database Guide'
    Write-Host "Guide: $outFile ($([Math]::Round((Get-Item $outFile).Length / 1KB)) KB)"
    return $outFile
}
