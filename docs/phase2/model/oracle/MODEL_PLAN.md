# Plan: Phase 2 model layer on Oracle - a Spring Boot backend connected to the migrated Oracle database

**Status: PLANNED, NOT EXECUTED.** No `backend/oracle/` exists yet. This is the plan for building one, written so a person or a new Claude session with no memory of earlier conversations can carry it out. It is the Oracle counterpart of the executed PostgreSQL plan, [../postgresql/MODEL_PLAN.md](../postgresql/MODEL_PLAN.md), and follows it step for step; only the database-specific parts differ. Every one of those parts is already tested: they come from the Oracle database guide's sample project, which was built and run against a copy of the migrated Oracle database on 2026-09-24.

**Phase 2 stays on PostgreSQL** (user decision, 2026-09-23). The Oracle migration is a proof of concept that shows the same migration reasoned through for the Oracle the exercise brief names (`docs/phase1/dbmigrate/DATA_MIGRATION.md` §10); this backend would complete that proof for the model layer. Build it only when the user asks.

| What | Where |
|---|---|
| This plan | `claude_modernization/docs/phase2/model/oracle/MODEL_PLAN.md` |
| The code (to be created) | `~/dev/claude_work/master-antique-repair-claude/backend/oracle/`, beside `backend/postgresql/` |
| The database it connects to | import-oracle's `mar-oracle` container: [docs/phase1/dbmigrate/import-oracle/README.md](../../../phase1/dbmigrate/import-oracle/README.md) |
| How to reach that database (logins, network routes, the tested Spring Boot project) | [../../../phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html](../../../phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html) |

## 1. Goal and scope

The same demonstration as the PostgreSQL backend, on Oracle AI Database 26ai Free: a Spring Boot backend connects to the database produced by the data migration, reads it through JPA with a mapping the database itself confirms (`ddl-auto=validate`), and carries the forced password change every migrated user meets on first login. Same classes, same behaviour, same 6 unit tests.

**Deliberately out of scope**, as for PostgreSQL: a controller, a web layer, Spring Security and the front end. Those components are designed once, on PostgreSQL; an Oracle variant would follow only if the Oracle path is taken further.

## 2. Run the demonstration (once built)

Prerequisites: Java 21, Docker Engine, the `mar-oracle` container from import-oracle (`tools/phase1/dbmigrate/import-oracle/ingest.sh load` if it does not exist), and a clone of `master-antique-repair-claude`.

1. **Create the application logins** (once; the guide, section 3). `mar_app` and `mar_readonly` with passwords you choose, as Oracle users with schema privileges on `masterantique`:
   ```
   cd ~/dev/claude_work/claude_modernization
   read -rsp 'New password for mar_app: ' APP_PW; echo
   read -rsp 'New password for mar_readonly: ' RO_PW; echo
   { printf 'DEFINE app_pw = "%s"\nDEFINE ro_pw = "%s"\n' "$APP_PW" "$RO_PW"; cat tools/phase1/dbmigrate/import-oracle/guide/mar-roles.sql; } |
     docker exec -i mar-oracle sqlplus -S / as sysdba
   unset APP_PW RO_PW
   ```
2. **Open a localhost route** (once; the guide, section 4, route C). The database container publishes no port by design; a small proxy opens `127.0.0.1:1522` only:
   ```
   docker network create mar-net
   docker network connect mar-net mar-oracle
   docker run -d --name mar-oracle-proxy --network mar-net -p 127.0.0.1:1522:1521 \
     alpine/socat tcp-listen:1521,fork,reuseaddr tcp-connect:mar-oracle:1521
   ```
   (If `mar-net` already exists for the PostgreSQL route, skip `network create`; one network can hold both databases.)
3. **Run the backend**:
   ```
   cd ~/dev/claude_work/master-antique-repair-claude/backend/oracle
   read -rsp 'mar_app password: ' MAR_DB_PASSWORD; echo; export MAR_DB_PASSWORD
   ./gradlew bootRun
   ```
   Expected (from `DatabaseCheck`; the connection line is the one the guide's project printed):
   ```
   Connected: MAR_APP @ FREEPDB1, schema MASTERANTIQUE, Oracle 23.26.3.0.0
   users=12 tickets=24 comments=26 audit_logs=78
   customers=8 employees=3 managers=1, must reset password=12
   tickets SUBMITTED=8 INPROGRESS=8 COMPLETED=8
   ```
4. **Run the first-login demonstration** (the `demo` profile). It really changes the stored password of the user you name: use a test copy, or rebuild afterwards with `ingest.sh load --recreate` (which also removes the logins and network links from steps 1 and 2):
   ```
   ./gradlew bootJar
   java -jar build/libs/backend-oracle-0.0.1-SNAPSHOT.jar --spring.profiles.active=demo \
     --demo.username=Customer1 --demo.password=anything \
     --demo.one-time-code=DEMO-1234 --demo.new-password=Walnut-Armoire-1887
   ```
   Expected: the same four steps as on PostgreSQL (`MUST_CHANGE_PASSWORD`, changed, `OK`, `INVALID`).
5. **Unit tests** (no database needed): `./gradlew test` (6 tests).

To take the route down again: `docker rm -f mar-oracle-proxy; docker network disconnect mar-net mar-oracle`, and `docker network rm mar-net` if nothing else uses it.

## 3. Decisions

Carried over from the PostgreSQL backend (made with the user on 2026-09-23): Gradle with the Kotlin DSL and the Gradle 9.4.1 wrapper; Spring Boot 4.1.1 on Java 21; package `com.masterantique.backend`; password changes refused outside the demo (`RejectingIdentityCheck`). Proposed for Oracle, to confirm with the user before building:

| Decision | Proposal | Why |
|---|---|---|
| Whether to build it | Only on request | Phase 2 is PostgreSQL; this completes the Oracle proof of concept for the model layer, it is not the application |
| Where the code goes | `backend/oracle/`, a separate Gradle project beside `backend/postgresql/` | The repository was already laid out for it (`backend/postgresql/`); the two stay independent and can be compared file by file |
| Shared code | **Copied, not shared** (no common module yet) | The two differ in only a handful of lines (section 4); a shared module would decide the multi-database design by accident. Revisit if the Oracle path goes further than the model |
| Project name / jar | `rootProject.name = "backend-oracle"` → `backend-oracle-0.0.1-SNAPSHOT.jar` | Tells the two jars apart |

## 4. What to build

All paths under `master-antique-repair-claude/backend/oracle/`. Start from a copy of `backend/postgresql/`; the table lists every difference. Each Oracle-specific item is proven in the guide's project (`claude_modernization/tools/phase1/dbmigrate/import-oracle/guide/mar-db-client/`, see its `README.md`).

| File | Change from `backend/postgresql/` |
|---|---|
| `settings.gradle.kts` | `rootProject.name = "backend-oracle"` |
| `build.gradle.kts` | `runtimeOnly("com.oracle.database.jdbc:ojdbc11")` instead of `org.postgresql:postgresql` (the Boot 4.1.1 BOM manages it: 23.26.3.0.0, the same release as the database) |
| `src/main/resources/application.properties` | URL `jdbc:oracle:thin:@//${MAR_DB_HOST:localhost}:${MAR_DB_PORT:1522}/${MAR_DB_SERVICE:FREEPDB1}` (a service, not a database); add `spring.datasource.hikari.connection-init-sql=ALTER SESSION SET CURRENT_SCHEMA = MASTERANTIQUE` (the login does not own the tables; enough for Hibernate's validation too, no `hibernate.default_schema`); add `spring.jpa.properties.hibernate.jdbc.fetch_size=100` (the driver's default of 10 makes Hibernate warn) |
| `model/AppUser.java` | `@Lob` on `password_hash`, `security_stamp`, `phone_number` (they are `CLOB`; without it validation fails), instead of `columnDefinition = "text"`. `BOOLEAN`, `NUMBER(10)`, `TIMESTAMP(3)` and identity columns map unchanged |
| `repo/AppUserRepository.java` | `findActiveByName`: `(case when u.deletedAt is null then lower(u.name) end) = lower(:name)`, repeating the function-based index `ix_users_name_active ON users (CASE WHEN deleted_at IS NULL THEN LOWER(name) END)`. Oracle uses the index only for its exact expression (checked with `EXPLAIN PLAN`: index unique scan, versus a full scan for the PostgreSQL form) |
| `DatabaseCheck.java` | The connection query in Oracle SQL: `select user \|\| ' @ ' \|\| sys_context('USERENV', 'CON_NAME') \|\| ', schema ' \|\| sys_context('USERENV', 'CURRENT_SCHEMA') \|\| ', Oracle ' \|\| (select version_full from product_component_version where rownum = 1) from dual` |
| `README.md` | The Oracle variant: prerequisites, environment variables (`MAR_DB_SERVICE` instead of `MAR_DB_NAME`; port 1522), and a pointer to this plan |
| Everything else | Unchanged: `LoginService`, `LoginResult`, `IdentityCheck`, `RejectingIdentityCheck`, the `demo` classes, `LoginServiceTest` (it mocks the repository, so it is database-independent), the wrapper, `.gitignore` |

## 5. How to build it

1. `cp -r backend/postgresql backend/oracle` in `master-antique-repair-claude`, then remove `backend/oracle/build/` and `backend/oracle/.gradle/` if present.
2. Apply every change in section 4.
3. `./gradlew test` (6 of 6), then verify as in section 6.
4. Update the repository's `README.md` and `CLAUDE.md` (the backends now come in two variants) and this plan's status and sections 6-7 with what actually happened.

## 6. How to verify it

- `./gradlew build` compiles; `./gradlew test`: 6 of 6.
- Against a **temporary copy** of the database, never `mar-oracle`: `ingest.sh load --config` with container `mar-oracle-guide` (the recipe is in `tools/phase1/dbmigrate/import-oracle/guide/README.md`), logins from `mar-roles.sql` with throwaway passwords, an `alpine/socat` proxy on another localhost port (the guide used 1523):
  - normal mode: connected as `MAR_APP`, schema validation passed, the counts in section 2;
  - demo mode: `Customer1` goes `MUST_CHANGE_PASSWORD` → changed → `OK`, wrong password `INVALID`, a wrong one-time code refused;
  - then remove the temporary container, proxy and network.
- The delivered `mar-oracle` untouched: `ingest.sh verify` still passes 86 of 86 checks.

## 7. For the user: committing

Git is read-only for Claude in this project; the user commits. After the build, `git status` in `master-antique-repair-claude` would show the new `backend/oracle/` and the edited README and CLAUDE.md. Include `backend/oracle/gradle/wrapper/gradle-wrapper.jar`; nothing under `build/` or `.gradle/`.

## 8. Open items

- Everything in the PostgreSQL plan's section 8 (controller, security, a real `IdentityCheck`, audit logging, view, time zones) applies here too; none of it is planned for Oracle separately.
- **Text length in bytes:** the Oracle database has `MAX_STRING_SIZE = STANDARD`, so a `VARCHAR2(2000 CHAR)` value is also limited to 4,000 bytes (about 1,333 three-byte characters). Server-side validation for comments and descriptions would have to check bytes, not only characters, on Oracle.
- **`BOOLEAN` conversions:** Oracle silently converts numbers and words such as `'yes'` to `BOOLEAN`; through JPA this cannot happen (Java `boolean`), but hand-written SQL should use `TRUE`/`FALSE`.
