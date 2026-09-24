# Sources of the PostgreSQL database guide

`docs/dbmigrate/iteration5/PostgreSQLDatabaseGuide.html` is generated from this folder. **Every code block in the guide
is copied from a file here that was run against the database**, so the page cannot drift from what was tested. To
change the guide: change the file here, test it again, rebuild the page.

| File | What it is |
|---|---|
| `guide.tpl.html` | The page: text, layout, styles, and markers where code goes |
| `build-guide.py` | Builds the page from the template (Python 3, standard library only) |
| `mar-roles.sql` | Creates the `mar_app` and `mar_readonly` logins; passwords come from environment variables (`\getenv`) |
| `queries.sql` | The sample queries shown in the guide |
| `mar-db-client/` | The sample Spring Boot 4.1.1 project: entities, repositories, connection check, first-login password change; `build.gradle` (Gradle, Groovy DSL), `pom.xml` (Maven), `JdbcSmokeTest.java` (plain JDBC, no Spring), Gradle wrapper |
| `kts/` | The same build in the Gradle Kotlin DSL (`build.gradle.kts`, `settings.gradle.kts`). To build it, copy `mar-db-client/src`, `gradlew` and `gradle/` next to them |

The Phase 2 backend (`master-antique-repair-claude/backend/`) was built from `mar-db-client/`; see
`docs/phase2/model/MODEL_PLAN.md`.

## Rebuild the page

```
python3 tools/dbmigrate/iteration5/guide/build-guide.py
```

Template markers: `<!--CODE lang ... CODE-->` (copyable block), `<!--OUT[:label] ... OUT-->` (output, not copyable),
`<!--FILE path|label-->` (a file from this folder), `<!--SCHEMA-->` (table reference from
`../input/source-metadata.json`). The script stops if a marker is left unexpanded. The output is deterministic: rebuilding
without changes leaves `git status` clean.

To republish the shared page (https://claude.ai/artifact/Xhzati1QXvcqPcmt1aQkfD), build the unwrapped copy with
`--artifact <path>` and publish that file to the same URL.

## Test again (never against the delivered database)

Everything in the guide was tested on a temporary copy, so the delivered `mar-postgres` is never changed:

```
cd ~/dev/claude_work/claude_modernization
sed -e 's/^CONTAINER=.*/CONTAINER=mar-postgres-guide/' \
    -e "s|^INPUT_DIR=.*|INPUT_DIR=$PWD/tools/dbmigrate/iteration5/input|" \
    tools/dbmigrate/iteration5/ingest.conf.example > /tmp/guide.conf
tools/dbmigrate/iteration5/ingest.sh load --config /tmp/guide.conf

export APP_PW=Test_Pw_2026 RO_PW=Test_Ro_2026        # throwaway passwords for the copy
docker exec -i -e APP_PW -e RO_PW mar-postgres-guide psql -X -q -U masterantique -d masterantique \
  < tools/dbmigrate/iteration5/guide/mar-roles.sql

docker network create mar-net-guide
docker network connect mar-net-guide mar-postgres-guide
docker run -d --name mar-guide-proxy --network mar-net-guide -p 127.0.0.1:5434:5432 \
  alpine/socat tcp-listen:5432,fork,reuseaddr tcp-connect:mar-postgres-guide:5432

cd tools/dbmigrate/iteration5/guide/mar-db-client
MAR_DB_PORT=5434 MAR_DB_PASSWORD=$APP_PW ./gradlew bootRun          # expect users=12 tickets=24 comments=26 audit_logs=78
MAR_DB_PORT=5434 MAR_DB_PASSWORD=$APP_PW mvn -q spring-boot:run      # the same with Maven
```

Then clean up: `docker rm -f mar-guide-proxy; docker rm -f -v mar-postgres-guide; docker network rm mar-net-guide`.
The first-login demo and the other commands are exercised the same way; the expected outputs are in the guide.
Build output (`build/`, `.gradle/`, `target/`) is ignored by git.
