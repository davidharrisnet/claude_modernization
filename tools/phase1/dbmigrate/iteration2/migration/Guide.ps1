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

# $Db is what sqlite3 opens: a Windows path for the local target, or a path inside the container for a docker target.
# For a docker target the guide describes only the database in the container; $HostFile is not used.
function Build-GuideDocument($Settings, [string]$Db, [string]$DisplayPath, $Results, [string]$Target, [string]$HostFile, $ExportPaths = $null) {
    $script:BreakNext = $false
    $b = New-Object System.Text.StringBuilder
    $add = { param($x) [void]$b.Append($x) }
    $docker = [bool](Sqlite-IsDocker $Settings)
    $iterNo = if ($Settings.iteration) { [string]$Settings.iteration } else { '' }
    $container = if ($docker) { [string]$Settings.runner.container } else { '' }

    $version = (Sqlite-Query $Settings $Db 'SELECT sqlite_version();')[0]
    $sizeKb = if ($docker) { [Math]::Round([double](Sqlite-Docker $Settings @('stat', '-c', '%s', $Db) '').Stdout.Trim() / 1KB) } else { [Math]::Round((Get-Item $HostFile).Length / 1KB) }
    $versionCell = if ($docker) { Sqlite-VersionText $Settings } else { "$version (64-bit command-line build used for the migration)" }
    $fileCell = if ($docker) { "$Db (inside the Linux container $container)" } else { $DisplayPath }
    $tables = [string[]](Sqlite-Query $Settings $Db "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
    $ran = if ($Results) { "$($Results.Meta.RunTimeUtc) UTC" } else { 'n/a' }

    & $add (Pg (Rn 'MasterAntiqueRepair' $true '1F3864' 64) 'Title')
    & $add (Pg (Rn 'SQLite Database Guide') 'Subtitle')
    & $add (Table @(2400, 6960) @('Item', 'Value') @(@('Iteration', "$iterNo - SQL Server LocalDB to $($Settings.iterationTitle)"), @('File', $fileCell), @('Size', "$sizeKb KB"), @('SQLite version', $versionCell), @('Tables', "$($tables.Count) (eight application tables; the EF __MigrationHistory table was deliberately not migrated)"), @('Created by', "dbmigrate export/import run on $ran")))

    # ---------------------------------------------------------------- 1
    & $add (H1 '1. What this database is')
    & $add (PT 'This is a SQLite copy of the MasterAntiqueRepair repair-shop database. The source is the SQL Server LocalDB database of the legacy ASP.NET Web Forms application. The structure, keys, relationships, indexes, defaults and every row were exported by a deterministic script and rebuilt in SQLite. The verification report (' + "MigrationVerificationReport$iterNo.docx" + ', in the same folder as this guide) proves the copy is identical: every row and value matched, and the structure and business rules were checked.')
    if ($docker) {
        & $add (PT ('It is a single file, ' + $Db + ', in the Linux file system of the Docker container ' + $container + '. It was never copied to Windows, and there is no database server to run. It is the Linux database for Phase 2 of the modernization: the Windows SQL Server data exported to SQLite for a Linux host. Section 3 explains how to work with it in the container; section 9 explains how the exported schema and data are loaded into a SQLite on Linux.'))
    } else {
        & $add (PT 'It is a single file with no server to run. It is the baseline data set for Phase 2 of the modernization: the reference database that the Spring Boot / Angular application is compared against.')
    }

    # ---------------------------------------------------------------- 2
    & $add (H1 '2. Version and file format')
    if ($docker) { & $add (Bullet "SQLite $version on Linux. The database file format is stable across SQLite 3.x, so the file opens with any modern SQLite build.") }
    else { & $add (Bullet "SQLite $version. The database file format is stable across SQLite 3.x and is identical on Windows and Linux, so this file opens with any modern SQLite build.") }
    & $add (Bullet 'Java: the xerial sqlite-jdbc driver (JDBC URL jdbc:sqlite:<path>) reads it directly, which is the likely route for the Phase 2 Spring Boot application.')
    if ($docker) {
        & $add (Bullet "This database was created and checked by the Linux build of SQLite running in a Dockerized Linux container ($container). Iteration 1 builds the same database with the Windows SQLite build, which is a different version. The file format is the same; only the tool version differs.")
    } else {
        & $add (Bullet 'Iteration 2 builds the same database in a Docker Linux container with a different SQLite version. The file format is the same; only the tool version differs.')
    }

    # ---------------------------------------------------------------- 3
    & $add (H1 '3. Accessing the database')
    if ($docker) {
        & $add (PT "The database is the single file $Db inside the Linux container $container. It exists nowhere on Windows: there is no copy, no bind mount and no published port. Every command below is typed at a Windows Command Prompt or PowerShell window and runs inside the container with docker exec, or is typed in a shell already inside the container. The container name and database path are already filled in.")
        & $add (H2 '3.1 Before you start: is the container up?')
        & $add (Code "docker ps --filter name=$container`ndocker start $container`ndocker exec $container ls -l $Db`ndocker exec $container sqlite3 -version")
        & $add (Bullet 'docker ps lists the container if it is running. If the list is empty, docker start brings it back (Docker Desktop must be running first).')
        & $add (Bullet 'ls -l proves the database file is present and shows its size. sqlite3 -version shows the Linux SQLite build that opens it.')
        & $add (H2 '3.2 Interactive session')
        & $add (Code "docker exec -it $container sh`nsqlite3 $Db`nsqlite> PRAGMA foreign_keys = ON;`nsqlite> .headers on`nsqlite> .mode column`nsqlite> .tables`nsqlite> .schema Tickets`nsqlite> .indexes Users`nsqlite> SELECT COUNT(*) FROM Users;`nsqlite> .quit`nexit")
        & $add (PT 'PRAGMA foreign_keys = ON must be issued in every session and by every application connection; SQLite does not enforce the declared relationships and delete rules otherwise. .quit leaves sqlite3; exit leaves the container shell.')
        & $add (H2 '3.3 Read-only access (the safe way to look around)')
        & $add (Code "docker exec -it $container sqlite3 -readonly $Db")
        & $add (PT 'A read-only connection cannot change the data. Use a writable connection only when you intend to change something.')
        & $add (H2 '3.4 One query from Windows, no interactive session')
        & $add (Code "docker exec $container sqlite3 -header -column $Db ""SELECT COUNT(*) FROM Users;""")
        & $add (Bullet 'Command Prompt and PowerShell: put the SQL in double quotes and use single quotes for text values inside it, for example "SELECT Name FROM Users WHERE Discriminator = ''Manager'';" with ordinary single quotes around Manager. For anything longer, put the SQL in a file and use 3.5.')
        & $add (Bullet 'Git Bash rewrites arguments that start with a slash (it turns /data/... into a Windows path). Prefix the command with MSYS_NO_PATHCONV=1, or use Command Prompt or PowerShell instead.')
        & $add (H2 '3.5 Run a SQL script that lives on Windows')
        & $add (PT 'Pipe the script into sqlite3 through standard input. The script is read on Windows and executed inside the container; nothing is copied into the container and the database file never leaves it.')
        & $add (Code "type report.sql | docker exec -i $container sqlite3 -header -column $Db`nGet-Content report.sql | docker exec -i $container sqlite3 -header -column $Db")
        & $add (PT 'The first line is for Command Prompt, the second for PowerShell. Add -readonly before the database path for a script that only reads.')
        & $add (H2 '3.6 Take query results out (not the database)')
        & $add (Code "docker exec $container sqlite3 -header -csv $Db ""SELECT Id, Name FROM Users;"" > users.csv")
        & $add (PT 'Only the text output of the query is written to the Windows file. The database itself stays in the container.')
        & $add (H2 '3.7 Experiment on a scratch copy inside the container')
        & $add (Code "docker exec $container cp $Db /tmp/work.sqlite`ndocker exec -it $container sqlite3 /tmp/work.sqlite`ndocker exec $container rm -f /tmp/work.sqlite")
        & $add (PT "Change the scratch copy freely, then delete it. To return the real database to its migrated state, rebuild it from the exported files (this deletes the database in the container and recreates it): tools\phase1\dbmigrate\iteration2\dbmigrate.cmd import --target $Target --recreate")
        & $add (H2 '3.8 Health checks and comparison tools inside the container')
        & $add (Code "docker exec $container sqlite3 $Db ""PRAGMA integrity_check;""`ndocker exec $container sqlite3 $Db ""PRAGMA foreign_key_check;""`ndocker exec $container sqldiff /tmp/work.sqlite $Db`ndocker exec $container sqlite3 $Db "".backup /tmp/backup.sqlite""")
        & $add (Bullet 'integrity_check must print ok; foreign_key_check must print nothing (no orphaned rows).')
        & $add (Bullet 'sqldiff (run it while a scratch copy from 3.7 exists) prints the SQL that would turn one database into the other; no output means the two are identical.')
        & $add (Bullet '.backup makes a consistent copy inside the container. It stays in the container, like the database.')
        & $add (H2 '3.9 Where the database lives and how long it lasts')
        & $add (Table @(3300, 6060) @('Action', 'Effect on the database') @(
            @("docker stop $container", 'Database is kept. docker start brings it back unchanged.'),
            @('Restarting Docker Desktop or Windows', 'Database is kept (it lives in the container''s writable layer).'),
            @("docker rm -f $container", 'Database is deleted with the container. Rebuild it by running the pipeline again.')))
        & $add (PT "The container was created from the stock alpine:3.20 image; SQLite was installed into it with apk add sqlite sqlite-tools. There is no custom image and no volume, so the container is the only home of the database. To rebuild everything: tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target $Target --recreate")
        & $add (H2 '3.10 From an application running on Linux')
        & $add (Code "String url = ""jdbc:sqlite:$Db"";`ntry (Connection c = DriverManager.getConnection(url);`n     Statement s = c.createStatement()) {`n    s.execute(""PRAGMA foreign_keys = ON"");   // per connection`n    ResultSet rs = s.executeQuery(""SELECT COUNT(*) FROM Users"");`n}")
        & $add (Bullet "The path is a Linux path, so the application must run where that path exists: inside this container, or in another container that shares its /data directory (for example started with --volumes-from $container).")
        & $add (Bullet 'An application running directly on Windows cannot open the database, because there is no Windows copy. Run the application in Linux, or read the data through docker exec as shown above.')
        & $add (PT 'For a Linux deployment of the Phase 2 application, build the database on the Linux host from the exported files, as described in section 9.')
        & $add (H2 '3.11 Troubleshooting')
        & $add (Table @(3300, 6060) @('Symptom', 'Cause and fix') @(
            @('Error: No such container', "The container was removed. Run the pipeline again to recreate it and the database: tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target $Target"),
            @('Cannot connect to the Docker daemon', 'Docker Desktop is not running. Start it and wait until it reports running.'),
            @('unable to open database file', 'Wrong path, or the container was recreated. Check the path with docker exec ... ls -l. In Git Bash, set MSYS_NO_PATHCONV=1.'),
            @('database is locked', 'Another session has the file open for writing. Close it (.quit) and retry, or connect with -readonly.'),
            @('sqlite3: not found', "The container has no SQLite. Run: docker exec $container apk add sqlite sqlite-tools"),
            @('A delete does not cascade, or an orphan row is accepted', 'PRAGMA foreign_keys = ON was not issued on that connection.'),
            @('Accented or emoji text looks wrong in the console', 'The data is correct (stored as UTF-8). Use a UTF-8 console, or write the output to a file with -csv.')))
    } else {
        & $add (H2 'Command line')
        & $add (PT 'Open a copy of the file rather than the delivered file, so experiments cannot change it:')
        & $add (Code "copy $($DisplayPath.Replace('/', '\')) work.sqlite`nsqlite3 work.sqlite`nsqlite> .headers on`nsqlite> .mode column`nsqlite> .tables`nsqlite> .schema Tickets`nsqlite> PRAGMA foreign_keys = ON;")
        & $add (H2 'Graphical tools')
        & $add (PT 'Any SQLite browser (for example DB Browser for SQLite) can open the file. Open it read-only unless you are working on a copy.')
        & $add (H2 'From Java (JDBC)')
        & $add (Code "String url = ""jdbc:sqlite:C:/path/to/masterantique.sqlite"";`ntry (Connection c = DriverManager.getConnection(url);`n     Statement s = c.createStatement()) {`n    s.execute(""PRAGMA foreign_keys = ON"");   // per connection`n    ResultSet rs = s.executeQuery(""SELECT COUNT(*) FROM Users"");`n}")
        & $add (PT 'SQLite does not enforce foreign keys unless PRAGMA foreign_keys = ON is issued on every connection. The schema declares the relationships and delete rules; the pragma makes SQLite apply them.')
    }
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
    & $add (Code "tools\phase1\dbmigrate\iteration2\dbmigrate.cmd all --target $Target --recreate")
    $dockerNote = if ($docker) { ' Docker Desktop must be running; the database is created inside the container ' + $container + ' and is not copied to Windows. --recreate replaces the database already in the container; leave it out on a first run.' } else { '' }
    & $add (PT ('This exports from the SQL Server LocalDB source (the instance must be available), rebuilds the SQLite file, verifies it, runs the tooling self-test and writes the verification report.' + $dockerNote + ' To rebuild only this guide from the existing database file:'))
    & $add (Code "tools\phase1\dbmigrate\iteration2\dbmigrate.cmd guide --target $Target")
    & $add (PT 'Exit codes: 0 success, 1 verification differences, 2 configuration or tool error, 3 refused because the target already exists.')

    if ($docker) {
        # ------------------------------------------------------------ 9
        & $add (H1 '9. Moving to Linux: loading the exported schema and data into a Linux SQLite')
        & $add (PT 'The wider goal is to move the ASP.NET application to Linux. The database is the first piece. This section shows how a Linux process takes over from the export, so the same steps work in the container used here or on any Linux host.')
        & $add (H2 '9.1 Where Windows stops and Linux takes over')
        & $add (Bullet 'Windows only: the export. The source is SQL Server LocalDB, which exists only on Windows, and the export tooling is Windows PowerShell.')
        $dataFile = if ($Settings.sanitizeCredentials) { '02-data-sanitized.sql' } else { '02-data.sql' }
        & $add (Bullet "Portable: the two files the export writes, 01-schema.sql and $dataFile. They are plain SQLite SQL text (UTF-8 without BOM, LF line ends). They are the only things that cross from Windows to Linux.")
        & $add (Bullet 'Linux: everything after that. A Linux process needs nothing but the sqlite3 command-line tool to build the database from those two files and to check that it is sound.')
        & $add (H2 '9.2 What to carry over')
        $exRows = New-Object System.Collections.ArrayList
        foreach ($f in @(@('01-schema.sql', 'Schema', 'ExportSchemaSha256'), @($dataFile, 'Data', 'ExportDataSha256'))) {
            $sz = 'n/a'; $sha = 'n/a'
            if ($ExportPaths -and (Test-Path $ExportPaths.($f[1]))) { $sz = "$((Get-Item $ExportPaths.($f[1])).Length) bytes" }
            if ($Results -and $Results.Meta.($f[2])) { $sha = [string]$Results.Meta.($f[2]) }
            [void]$exRows.Add(@($f[0], $sz, $sha))
        }
        & $add (Table @(2000, 1700, 5660) @('File', 'Size', 'SHA-256 (from this run)') $exRows)
        if ($Settings.sanitizeCredentials) {
            & $add (PT "Both files are in tools\phase1\dbmigrate\iteration2 on the Windows machine. $dataFile has already had PasswordHash/SecurityStamp set to NULL for every Users row (section 7), so it carries no credential material. Whether any other column should be treated as sensitive has not been evaluated for this database and is a separate decision.")
        } else {
            & $add (PT "Both files are in tools\phase1\dbmigrate\iteration2 on the Windows machine. $dataFile contains the password hashes from the Identity tables, so treat it as sensitive: do not commit it or share it.")
        }
        & $add (H2 '9.3 Getting the files to Linux')
        & $add (Code "rem Into the running container, without touching the database:`ndocker cp tools\phase1\dbmigrate\iteration2\01-schema.sql ${container}:/tmp/01-schema.sql`ndocker cp tools\phase1\dbmigrate\iteration2\$dataFile ${container}:/tmp/$dataFile`n`n# To a separate Linux host:`nscp 01-schema.sql $dataFile user@linuxhost:/tmp/")
        & $add (PT 'Or skip the copy entirely and pipe each file into sqlite3 from Windows, as the migration tool does (9.4, option A).')
        & $add (PT 'Confirm the transfer on Linux against the SHA-256 values in 9.2:')
        & $add (Code "docker exec $container sha256sum /tmp/01-schema.sql /tmp/$dataFile`nsha256sum /tmp/01-schema.sql /tmp/$dataFile")
        & $add (PT 'The first line is for the container, the second for a plain Linux host.')
        & $add (H2 '9.4 Build the database on Linux')
        & $add (PT 'Install SQLite if it is missing: apk add sqlite sqlite-tools (Alpine), or apt-get install sqlite3 (Debian, Ubuntu). Load the schema first, then the data. The schema creates the tables in dependency order with the foreign keys inline; the data script switches foreign key checks off while it loads, sets the auto-number counters, switches them back on and runs a foreign key check. -bail stops at the first error.')
        & $add (PT 'Option A: from Windows, into the container, piping the files (the tool''s own method):')
        & $add (Code "docker exec $container sh -c ""test ! -e $Db""`ntype tools\phase1\dbmigrate\iteration2\01-schema.sql | docker exec -i $container sqlite3 -bail $Db`ntype tools\phase1\dbmigrate\iteration2\$dataFile | docker exec -i $container sqlite3 -bail $Db")
        & $add (PT 'Option B: files already in the container:')
        & $add (Code "docker exec $container sh -c ""sqlite3 -bail $Db < /tmp/01-schema.sql && sqlite3 -bail $Db < /tmp/$dataFile""")
        & $add (PT 'Option C: on a plain Linux host (any path works; /data/masterantique.sqlite is used here to match this guide):')
        & $add (Code "mkdir -p /data`ntest ! -e /data/masterantique.sqlite`nsqlite3 -bail /data/masterantique.sqlite < /tmp/01-schema.sql`nsqlite3 -bail /data/masterantique.sqlite < /tmp/$dataFile")
        & $add (PT 'The test ! -e line makes the sequence stop if a database already exists, so an existing database is never overwritten by accident. To rebuild deliberately, delete the old file first (rm -f) and run the steps again.')
        & $add (H2 '9.5 Check the result on Linux, without SQL Server')
        & $add (Code "sqlite3 /data/masterantique.sqlite ""PRAGMA integrity_check;""      # must print: ok`nsqlite3 /data/masterantique.sqlite ""PRAGMA foreign_key_check;""   # must print nothing`nsqlite3 /data/masterantique.sqlite "".tables""`nsqlite3 /data/masterantique.sqlite ""SELECT COUNT(*) FROM Users;""")
        & $add (PT 'Inside the container, put docker exec (name of the container) in front of each command. Then compare the row count of every table with the numbers from this run:')
        & $add (Table @(6000, 3360) @('Table', 'Expected rows') $sumRows)
        & $add (PT 'The rule that a soft-deleted user name can be reused can be tested on a scratch copy (never on the real database):')
        & $add (Code "cp /data/masterantique.sqlite /tmp/rule-test.sqlite`nsqlite3 /tmp/rule-test.sqlite ""PRAGMA foreign_keys = ON; SELECT Name FROM Users WHERE DeletedAt IS NULL LIMIT 1;""`nrm -f /tmp/rule-test.sqlite")
        & $add (PT 'Inserting a second active user with that name in the copy must fail with UNIQUE constraint failed; after setting DeletedAt on the first, the insert must succeed.')
        & $add (H2 '9.6 What can and cannot be proven on Linux')
        & $add (Bullet 'On Linux you can prove that the database is sound (integrity and foreign key checks), that it has the expected tables and row counts, and that the rules work.')
        & $add (Bullet 'The complete proof, that every row and value equals the SQL Server source, compares against the source and therefore runs on Windows. It is what the verification report (MigrationVerificationReport2.docx) records.')
        & $add (Bullet 'A future step could remove the Windows dependency after the export: the export would also write a manifest (row counts, a SHA-256 per table, the schema description), and a Linux script using sqlite3 and sha256sum would recompute the same values and compare them. That is not part of this iteration.')
    }

    return $b.ToString()
}

function Invoke-Guide($Config, [string]$Target, [string]$Out) {
    $settings = Get-TargetSettings $Config $Target
    if ($settings.dialect -ne 'sqlite') { throw (New-MigrationError "The guide is only implemented for the sqlite dialect (target '$Target' uses '$($settings.dialect)')." 2) }
    $dialect = Get-Dialect $settings.dialect $settings   # loads the dialect so Sqlite-Query is available
    $paths = Get-TargetPaths $Config $Target
    $docker = [bool](Sqlite-IsDocker $settings)
    if ($docker) {
        # The database lives inside the container; the guide describes only that database.
        $db = [string]$settings.file
        $hostFile = $null
        if (-not (Sqlite-FileExists $settings $db)) { throw (New-MigrationError "Database file not found in the container: $db - run 'import' first." 2) }
        $display = $db
    } else {
        $db = Resolve-RepoPath ([string]$settings.file)
        $hostFile = $db
        $display = [string]$settings.file
    }
    if (-not $docker -and -not (Test-Path $hostFile)) { throw (New-MigrationError "Database file not found: $hostFile - run 'import' first." 2) }
    $results = if (Test-Path $paths.Results) { Get-Content $paths.Results -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $outFile = if ($Out) { Resolve-RepoPath $Out } else { $paths.Guide }

    $images = [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList) }
    $body = Build-GuideDocument $settings $db $display $results $Target $hostFile $paths
    $created = if ($results) { ([datetime]::ParseExact($results.Meta.RunTimeUtc, 'yyyy-MM-dd HH:mm:ss', $script:Inv)).ToString('yyyy-MM-ddTHH:mm:ssZ', $script:Inv) } else { '2000-01-01T00:00:00Z' }
    $iter = if ($settings.iteration) { "Iteration $($settings.iteration) - " } else { '' }
    Save-Docx $outFile $body $images "$iter$($settings.iterationTitle)" $created 'MasterAntiqueRepair - SQLite Database Guide' 'SQLite Database Guide'
    Write-Host "Guide: $outFile ($([Math]::Round((Get-Item $outFile).Length / 1KB)) KB)"
    return $outFile
}
