# Sources of the Oracle database guide

`docs/phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html` is generated from this folder. **Every code block in the guide
is copied from a file here that was run against the database**, so the page cannot drift from what was tested. To
change the guide: change the file here, test it again, rebuild the page. Self-contained: it needs nothing from the PostgreSQL tools.

| File | What it is |
|---|---|
| `guide.tpl.html` | The page: text, layout, styles, and markers where code goes |
| `build-guide.py` | Builds the page from the template (Python 3, standard library only; the one host tool besides bash and Docker) |
| `mar-roles.sql` | Creates the `mar_app` and `mar_readonly` logins with schema privileges on `masterantique`; passwords arrive as SQL*Plus substitution variables on standard input |
| `queries.sql` | The sample queries shown in the guide (SQL*Plus, run as SYS) |
| `mar-db-client/` | The sample Spring Boot 4.1.1 project for Oracle: entities, repositories, connection check, first-login password change; `build.gradle` (Gradle, Groovy DSL), `pom.xml` (Maven), `JdbcSmokeTest.java` (plain JDBC, no Spring), Gradle wrapper |
| `kts/` | The same build in the Gradle Kotlin DSL (`build.gradle.kts`, `settings.gradle.kts`). To build it, copy `mar-db-client/src`, `gradlew` and `gradle/` next to them |

Oracle-specific points, all found by running it: the driver is `com.oracle.database.jdbc:ojdbc11`
(BOM-managed, 23.26.3.0.0); the login does not own the tables, so `spring.datasource.hikari.connection-init-sql` switches
every connection to `MASTERANTIQUE` (enough for Hibernate's validation; no `hibernate.default_schema`);
`hibernate.jdbc.fetch_size=100` (the driver's default of 10 makes Hibernate warn); the three `CLOB` columns need `@Lob`;
the username lookup repeats the function-based index's expression (`CASE WHEN deleted_at IS NULL THEN LOWER(name) END`),
because Oracle uses the index only for that exact expression (checked with `EXPLAIN PLAN`: index unique scan versus full
scan for `LOWER(name) = ... AND deleted_at IS NULL`); `ConnectionCheck` uses `sys_context` and
`product_component_version`. `BOOLEAN`, `NUMBER(10)`, `TIMESTAMP(3)` and identity columns map without changes.

## Rebuild the page

```
python3 tools/phase1/dbmigrate/import-oracle/guide/build-guide.py
```

Template markers: `<!--CODE lang ... CODE-->` (copyable block), `<!--OUT[:label] ... OUT-->` (output, not copyable),
`<!--FILE path|label-->` (a file from this folder), `<!--SCHEMA-->` (table reference from
`../input/source-metadata.json`). The script stops if a marker is left unexpanded. The output is deterministic: rebuilding
without changes leaves `git status` clean. `--artifact <path>` also writes the unwrapped copy for publishing as an Artifact.

## Test again (never against the delivered database)

Everything in the guide was tested on a temporary copy, so the delivered `mar-oracle` is never changed:

```
cd ~/dev/claude_work/claude_modernization
sed -e 's/^CONTAINER=.*/CONTAINER=mar-oracle-guide/' \
    -e "s|^INPUT_DIR=.*|INPUT_DIR=$PWD/tools/phase1/dbmigrate/import-oracle/input|" \
    tools/phase1/dbmigrate/import-oracle/ingest.conf.example > /tmp/guide.conf
tools/phase1/dbmigrate/import-oracle/ingest.sh load --config /tmp/guide.conf

export APP_PW=Test_Pw_2026 RO_PW=Test_Ro_2026        # throwaway passwords for the copy
{ printf 'DEFINE app_pw = "%s"\nDEFINE ro_pw = "%s"\n' "$APP_PW" "$RO_PW"; cat tools/phase1/dbmigrate/import-oracle/guide/mar-roles.sql; } |
  docker exec -i mar-oracle-guide sqlplus -S / as sysdba

docker network create mar-net-guide
docker network connect mar-net-guide mar-oracle-guide
docker run -d --name mar-guide-proxy --network mar-net-guide -p 127.0.0.1:1523:1521 \
  alpine/socat tcp-listen:1521,fork,reuseaddr tcp-connect:mar-oracle-guide:1521

cd tools/phase1/dbmigrate/import-oracle/guide/mar-db-client
MAR_DB_PORT=1523 MAR_DB_PASSWORD=$APP_PW ./gradlew bootRun          # expect users=12 tickets=24 comments=26 audit_logs=78
MAR_DB_PORT=1523 MAR_DB_PASSWORD=$APP_PW mvn -q spring-boot:run      # the same with Maven
```

Then clean up: `docker rm -f mar-guide-proxy; docker rm -f -v mar-oracle-guide; docker network rm mar-net-guide`.
The first-login demo, the routes and the error messages in the troubleshooting table are exercised the same way; the
expected outputs are in the guide. Build output (`build/`, `.gradle/`, `target/`) is ignored by git.
