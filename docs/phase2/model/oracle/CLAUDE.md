# Plan: Phase 2 model layer on Oracle - a Spring Boot model connected to the migrated Oracle database

**Status: EXECUTED (2026-09-24).** This is the plan as it was carried out, written so the work can be repeated, or rebuilt from scratch, by a person or a new Claude session with no memory of the original conversation. It runs when the user says **`Run model-oracle`** (section 2), or asks to rebuild the Oracle model (section 5). Result: the model builds, its 6 unit tests pass, and it connects to the migrated Oracle database, validates every entity against the live schema, and demonstrates the first-login password change.

**Self-contained by design.** Everything here comes from the Oracle side: the import-oracle database and the Oracle database guide's tested sample project. Nothing reads from, copies or needs any PostgreSQL folder (`model/postgresql/`, `tools/phase1/dbmigrate/*-postgresql/`, `docs/phase2/model/postgresql/`); deleting all of them leaves this plan and `model/oracle/` working (checked: `model/oracle/` was built and run from a copy with no other folder beside it). Phase 2 as a whole runs on PostgreSQL; this model is the Oracle proof of concept for the model layer.

| What | Where |
|---|---|
| This plan | `claude_modernization/docs/phase2/model/oracle/CLAUDE.md` |
| The code | `~/dev/claude_work/master-antique-repair-claude/model/oracle/` (origin `github.com/davidharrisnet/master-antique-repair-claude`, branch `main`); its `README.md` is for people |
| The database it connects to | import-oracle's `mar-oracle` container: [docs/phase1/dbmigrate/import-oracle/README.md](../../../phase1/dbmigrate/import-oracle/README.md) (built with `Run import-oracle`) |
| How to reach that database (logins, network routes), and the tested source of this code | [OracleDatabaseGuide.html](../../../phase1/dbmigrate/import-oracle/OracleDatabaseGuide.html); its sources in `tools/phase1/dbmigrate/import-oracle/guide/` |

## 1. Goal and scope

**The goal is a demonstration**: show that a Spring Boot model can connect to the Oracle database produced by the data migration, read it through JPA with a mapping the database itself confirms (`ddl-auto=validate`), and carry the one business rule every migrated user meets first, the forced password change on first login.

**Deliberately out of scope:** a controller, a web layer, Spring Security and the front end. They belong to the other Phase 2 components (`docs/phase2/controller/`, `security/`, `view/`) and need their own design.

## 2. Run the demonstration (`Run model-oracle`)

**The operating instructions now live with the code:** `master-antique-repair-claude/model/oracle/CLAUDE.md` (read automatically by a Claude session opened in that repository; its section "Run model-oracle" runs the whole demonstration on a temporary copy, with `model/oracle/db/mar-roles.sql`). The steps below are the same demonstration done by hand against the delivered `mar-oracle`.

Prerequisites: Java 21, Docker Engine, the `mar-oracle` container (if `docker ps -a` does not show it, run `Run import-oracle` in `claude_modernization` first: `tools/phase1/dbmigrate/import-oracle/ingest.sh load`), and a clone of `master-antique-repair-claude`.

1. **Create the application logins** (once; the guide, section 3). This makes `mar_app` (read/write) and `mar_readonly` with passwords you choose, as Oracle users with schema privileges on `masterantique`; the passwords reach SQL*Plus on standard input and are never written anywhere:
   ```
   cd ~/dev/claude_work/claude_modernization
   read -rsp 'New password for mar_app: ' APP_PW; echo
   read -rsp 'New password for mar_readonly: ' RO_PW; echo
   { printf 'DEFINE app_pw = "%s"\nDEFINE ro_pw = "%s"\n' "$APP_PW" "$RO_PW"; cat tools/phase1/dbmigrate/import-oracle/guide/mar-roles.sql; } |
     docker exec -i mar-oracle sqlplus -S / as sysdba
   unset APP_PW RO_PW
   ```
   Running it twice stops with `ORA-01920` (the logins exist); change a password with the guide's `ALTER USER` block instead.
2. **Open a localhost route** (once; the guide, section 4, route C). The database container publishes no port by design; a small proxy opens `127.0.0.1:1522` only:
   ```
   docker network create mar-net                  # skip if it exists
   docker network connect mar-net mar-oracle
   docker run -d --name mar-oracle-proxy --network mar-net -p 127.0.0.1:1522:1521 \
     alpine/socat tcp-listen:1521,fork,reuseaddr tcp-connect:mar-oracle:1521
   ```
3. **Run the model** (normal mode: connect and report):
   ```
   cd ~/dev/claude_work/master-antique-repair-claude/model/oracle
   read -rsp 'mar_app password: ' MAR_DB_PASSWORD; echo; export MAR_DB_PASSWORD
   ./gradlew bootRun
   ```
   Expected (from `DatabaseCheck`, among the start-up log lines):
   ```
   Connected: MAR_APP @ FREEPDB1, schema MASTERANTIQUE, Oracle 23.26.3.0.0
   users=12 tickets=24 comments=26 audit_logs=78
   customers=8 employees=3 managers=1, must reset password=12
   tickets SUBMITTED=8 INPROGRESS=8 COMPLETED=8
   ```
   Getting this far also proves the mapping: Hibernate runs with `ddl-auto=validate` and refuses to start if any entity disagrees with the live schema.
4. **Run the first-login demonstration** (the `demo` profile). **It really changes the stored password of the user you name**, so run it against a test copy of the database (section 6), or rebuild afterwards with `ingest.sh load --recreate` (which also removes the logins and network links from steps 1 and 2):
   ```
   ./gradlew bootJar
   java -jar build/libs/model-oracle-0.0.1-SNAPSHOT.jar --spring.profiles.active=demo \
     --demo.username=Customer1 --demo.password=anything \
     --demo.one-time-code=DEMO-1234 --demo.new-password=Walnut-Armoire-1887
   ```
   Expected:
   ```
   1. Sign in as 'Customer1' -> MUST_CHANGE_PASSWORD
      You must change your password before you continue.
   ... DemoIdentityCheck : DEMO identity check used for 'customer1': replace DemoIdentityCheck before production
   ... LoginService      : Password changed for user id 5 (Customer); must_reset_password cleared
   2. Password changed.
   3. Sign in again with the new password -> OK
   4. Sign in with a wrong password      -> INVALID
   ```
   Without the `--demo.*` values it asks for each one at the console, hiding passwords. A wrong one-time code gives `2. Not changed: The one-time code is not valid.`
5. **Unit tests** (no database needed): `./gradlew test` (6 tests).

To take the route down again: `docker rm -f mar-oracle-proxy; docker network disconnect mar-net mar-oracle`, and `docker network rm mar-net` if nothing else uses it.

## 3. Decisions

| Decision | Choice | Why |
|---|---|---|
| Where the code goes | `model/oracle/` of `master-antique-repair-claude`, a Gradle project of its own | One folder per database; it must build and run with every other folder removed (user, 2026-09-24) |
| Source of the code | The Oracle database guide's sample project (`tools/phase1/dbmigrate/import-oracle/guide/mar-db-client/`), package renamed | Every Oracle-specific line in it was run against a copy of the migrated database; nothing is taken from any PostgreSQL folder |
| Build tool | Gradle with the Kotlin DSL (`build.gradle.kts`), Gradle 9.4.1 wrapper | Type-checked, Gradle's default for new builds; the wrapper means nobody installs Gradle |
| Spring Boot version | 4.1.1 on Java 21 | The project's chosen stack for Phase 2 |
| Package / artifact | `com.masterantique`; project `model-oracle` → `model-oracle-0.0.1-SNAPSHOT.jar` | |
| Password changes outside the demo | Refused (`RejectingIdentityCheck`) | Migrated users have no password, so identity must be proven another way before a first password is set; until a real check exists, no account can be taken over by someone who only knows a username |
| Demo code | Only under the `demo` profile, in package `demo` | It changes real data and accepts a fixed code |

## 4. What was built

All paths are under `master-antique-repair-claude/model/oracle/`; the Java sources under `src/main/java/com/masterantique/`.

| File | Purpose |
|---|---|
| `settings.gradle.kts`, `build.gradle.kts` | `rootProject.name = "model-oracle"`. Spring Boot 4.1.1 plugin, `io.spring.dependency-management` 1.1.7, Java 21 toolchain. Dependencies: `spring-boot-starter-data-jpa` (Hibernate 7.4.5, Spring Data JPA 4.1.1, JDBC, HikariCP 7.0.2), `spring-security-crypto` (password hashing only), `com.oracle.database.jdbc:ojdbc11` (runtime; 23.26.3.0.0 from the Boot BOM, the same release as the database), `spring-boot-starter-test` and `junit-platform-launcher` (tests); `useJUnitPlatform()` |
| `gradlew`, `gradlew.bat`, `gradle/wrapper/*` | Gradle 9.4.1 wrapper (copied from the guide's sample project; `gradle wrapper --gradle-version 9.4.1` recreates it) |
| `src/main/resources/application.properties` | Connection from environment variables only: `jdbc:oracle:thin:@//${MAR_DB_HOST:localhost}:${MAR_DB_PORT:1522}/${MAR_DB_SERVICE:FREEPDB1}` (a service, not a database), user `${MAR_DB_USER:mar_app}`, password `${MAR_DB_PASSWORD}` (never in a file). HikariCP pool `mar-pool` (5 connections, 10 s timeout) with `connection-init-sql=ALTER SESSION SET CURRENT_SCHEMA = MASTERANTIQUE` (the login does not own the tables; enough for Hibernate's validation too, no `hibernate.default_schema`). `ddl-auto=validate`, `open-in-view=false`, `hibernate.jdbc.fetch_size=100` (the driver's default of 10 makes Hibernate warn), `spring.sql.init.mode=never` |
| `src/main/resources/application-demo.properties` | Quiet console output for the demo profile (no banner, `warn` root logging, `info` for `com.masterantique`) |
| `ModelApplication.java` | Entry point (`@SpringBootApplication`) |
| `DatabaseCheck.java` | `@Profile("!demo")` `CommandLineRunner`: logs the connection through `JdbcTemplate` (`select user \|\| ' @ ' \|\| sys_context('USERENV', 'CON_NAME') \|\| ', schema ' \|\| sys_context('USERENV', 'CURRENT_SCHEMA') \|\| ', Oracle ' \|\| (select version_full from product_component_version where rownum = 1) from dual`) and the counts through the repositories |
| `model/AppUser.java` | Table `users`: one entity for customers, employees and managers (`discriminator` is a plain column). Every column named explicitly; `GenerationType.IDENTITY`; `@Lob` on the `CLOB` columns `password_hash`, `security_stamp`, `phone_number` (without it Hibernate expects `VARCHAR2` and validation fails); `boolean` for the `BOOLEAN` columns; `LocalDateTime` for `TIMESTAMP(3)`; `setNewPassword(hash, stamp)` clears `must_reset_password` and the failed-attempt count |
| `model/Ticket.java`, `model/TicketState.java` | Table `tickets`; `state` (`NUMBER(10)`) is the enum's ordinal 0/1/2 = `SUBMITTED`, `INPROGRESS`, `COMPLETED`; `assignee` (`user_id`) and `customer` (`customer_id`) are lazy `@ManyToOne` |
| `model/Comment.java`, `model/AuditLog.java` | Tables `comments` and `audit_logs` (the audit trail stores ids and timestamps only) |
| `repo/AppUserRepository.java` | `findActiveByName`: `(case when u.deletedAt is null then lower(u.name) end) = lower(:name)`, the exact expression of the function-based unique index `ix_users_name_active`. Oracle uses the index only for its own expression (checked with `EXPLAIN PLAN`: index unique scan, versus a full table scan for `lower(name) = ... and deleted_at is null`); it ignores case and soft-deleted users, whose expression is NULL. Also counts by type and by `must_reset_password` |
| `repo/TicketRepository.java`, `CommentRepository.java`, `AuditLogRepository.java` | Spring Data repositories (`countByState` on tickets) |
| `login/LoginResult.java` | `OK`, `MUST_CHANGE_PASSWORD`, `INVALID` (same answer for an unknown user and a wrong password) |
| `login/LoginService.java` | `login(username, password)` (a dummy bcrypt compare for unknown users evens out timing); `changePassword(username, oneTimeCode, new, confirm)`: identity check, policy (`checkPolicy`: 12+ characters, confirmation matches, must not contain the username), bcrypt hash via Spring Security's delegating encoder (`{bcrypt}...`), new UUID security stamp; errors are `IllegalArgumentException` with user-facing messages; logs the event, never the password |
| `login/IdentityCheck.java` | The seam where a real identity proof goes |
| `login/RejectingIdentityCheck.java` | Default (`@Profile("!demo")`): refuses every password change |
| `demo/DemoIdentityCheck.java` | `@Profile("demo")`: accepts one fixed code, `demo.issued-code` (default `DEMO-1234`); logs a warning on every use |
| `demo/FirstLoginDemo.java` | `@Profile("demo")` `CommandLineRunner`: console walk-through of a first login, driven by `demo.username`, `demo.password`, `demo.one-time-code`, `demo.new-password` (asks for missing ones) |
| `src/test/java/.../login/LoginServiceTest.java` | 6 unit tests with Mockito (repository and entity mocked, no database, no Spring context): a migrated user must change the password; an unknown user is `INVALID`; a user with their own password signs in only with it; the default identity check refuses every change and nothing is stored; the password policy (length, confirmation, username); a successful change stores a `{bcrypt}` hash that never contains the password and matches it, and a new UUID stamp |
| `README.md` | For people: what it is, the database and the two set-up steps, the environment variables, build/test/run, layout, the first-login design, limits |

The repository's root `.gitignore` already keeps `gradle-wrapper.jar` and ignores `build/`, `.gradle/` and `.env` files.

## 5. How to rebuild it from scratch

Sources: `claude_modernization/tools/phase1/dbmigrate/import-oracle/guide/mar-db-client/` (call it `SRC`; its Java package is `com.masterantique.dbclient`).

1. In `master-antique-repair-claude`, create `model/oracle/` with `settings.gradle.kts`, `build.gradle.kts`, both properties files, `ModelApplication.java` and `README.md` as described in section 4. Copy `gradlew`, `gradlew.bat` and `gradle/wrapper/` from `SRC`.
2. Copy from `SRC/src/main/java/com/masterantique/dbclient/` into `model/oracle/src/main/java/com/masterantique/`, changing `com.masterantique.dbclient` to `com.masterantique`: `model/*`, `repo/*`, `login/LoginResult`, `login/IdentityCheck`, `login/LoginService`. Do not copy `ConnectionCheck` or `MarDbClientApplication` (replaced by `DatabaseCheck` and `ModelApplication`), nor `JdbcSmokeTest.java`, `build.gradle`, `pom.xml` or the sample's `application.properties`.
3. Put `DemoIdentityCheck` and `FirstLoginDemo` in package `demo`: add `@Profile("demo")` to `DemoIdentityCheck` and imports of `login.IdentityCheck`; in `FirstLoginDemo` import `login.LoginResult` and `login.LoginService` and rename its profile from `first-login-demo` to `demo`.
4. Add `RejectingIdentityCheck`, `DatabaseCheck` and `LoginServiceTest` (section 4).
5. `./gradlew build` (6 of 6 tests), then verify as in section 6.

## 6. How it was verified (2026-09-24)

- `./gradlew build`: compiles; `./gradlew test`: **6 of 6 passed**.
- **Independence:** a copy of `model/oracle/` alone (no other folder beside it) was built, tested (6 of 6) and run against the database; nothing in it names PostgreSQL.
- Against a **temporary copy** of the database, never `mar-oracle`: `tools/phase1/dbmigrate/import-oracle/ingest.sh load --config` with container `mar-oracle-guide` (settings: `ingest.conf.example` with `CONTAINER=mar-oracle-guide`), the logins from `mar-roles.sql` with throwaway passwords, a network `mar-net-guide` and an `alpine/socat` proxy on `127.0.0.1:1523` (`MAR_DB_PORT=1523`):
  - normal mode (`java -jar` and `./gradlew bootRun`): connected as `MAR_APP` to `FREEPDB1`, schema `MASTERANTIQUE`, Oracle 23.26.3.0.0; schema validation passed; the counts in section 2;
  - demo mode: `Customer1` (typed in capitals) went `MUST_CHANGE_PASSWORD` → changed → `OK`, wrong password `INVALID`; a wrong one-time code was refused; a later sign-in with the new password was `OK`.
  The temporary container, proxy and network were removed afterwards.
- The delivered `mar-oracle` was never touched: `ingest.sh verify` passes 86 of 86 checks.

## 7. For the user: committing

Git is read-only for Claude in this project; the user commits. In `master-antique-repair-claude`, `git status` shows the new `model/oracle/`. Make sure `model/oracle/gradle/wrapper/gradle-wrapper.jar` is included (it is a `.jar`, which the `.gitignore` otherwise excludes, and the `!**/gradle/wrapper/gradle-wrapper.jar` rule keeps it). Nothing under `model/oracle/build/` or `model/oracle/.gradle/` should be committed.

## 8. Open items

- **Controller, security, view:** designed once for Phase 2 (`docs/phase2/controller/`, `security/`, `view/`); an Oracle variant only if the Oracle path is taken further.
- **A real `IdentityCheck`**: a single-use, expiring code issued by a manager, or an email reset link (every migrated `email` is NULL, so addresses must be collected first).
- **Audit logging**: record workflow and password changes in the legacy `audit_logs` format (ids and timestamps, never comment text or passwords).
- **Text length in bytes:** the database has `MAX_STRING_SIZE = STANDARD`, so a `VARCHAR2(2000 CHAR)` value is also limited to 4,000 bytes (about 1,333 three-byte characters); server-side validation must check bytes, not only characters.
- **`BOOLEAN` conversions:** Oracle silently converts numbers and words such as `'yes'`; through JPA this cannot happen (Java `boolean`), but hand-written SQL should use `TRUE`/`FALSE`.
- **Time zones**: `TIMESTAMP(3)` columns are read as `LocalDateTime` with no conversion; whether the legacy system stored UTC or local time is unknown.
- **Sequences after use:** once the application inserts rows, import-oracle's identity check (`LAST_NUMBER`) no longer matches; rebuild with `ingest.sh load --recreate` for a clean verification.
