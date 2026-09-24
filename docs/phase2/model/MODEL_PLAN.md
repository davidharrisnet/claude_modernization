# Plan: Phase 2 model layer - a Spring Boot backend connected to the migrated PostgreSQL database

**Status: EXECUTED (2026-09-23).** This is the plan as it was carried out, written so the work can be repeated, or rebuilt from scratch, by a person or a new Claude session with no memory of the original conversation. Result: the backend builds, its 6 unit tests pass, and it connects to the migrated database, validates every entity against the live schema, and demonstrates the first-login password change.

The code lives in a different repository from this document:

| What | Where |
|---|---|
| This plan | `claude_modernization/docs/phase2/model/MODEL_PLAN.md` |
| The code | `~/dev/claude_work/master-antique-repair-claude/backend/` (origin `github.com/davidharrisnet/master-antique-repair-claude`, branch `main`) |
| The database it connects to | Iteration 5's `mar-postgres` container: [../../dbmigrate/iteration5/ITERATION5_PLAN.md](../../phase1/dbmigrate/iteration5/ITERATION5_PLAN.md) |
| How to reach that database (logins, network routes) | [../../dbmigrate/iteration5/PostgreSQLDatabaseGuide.html](../../phase1/dbmigrate/iteration5/PostgreSQLDatabaseGuide.html) |

## 1. Goal and scope

Phase 2 rebuilds the legacy ASP.NET Web Forms repair-shop application as Spring Boot plus Angular. Its documentation is organised by architectural component, one folder each under `docs/phase2/`:

| Folder | Component | State |
|---|---|---|
| `model/` (this plan) | Entities mapped to the migrated tables, repositories, business rules such as sign-in | **Done** (first version) |
| `controller/` | REST endpoints | Not started |
| `view/` | The Angular app | Not started |
| `security/` | Spring Security, authentication, sessions or tokens | Not started |

**The goal of this step is a demonstration**: show that a Spring Boot backend can connect to the PostgreSQL database produced by the data migration, read it through JPA with a mapping the database itself confirms, and carry the one business rule every migrated user meets first, the forced password change on first login.

**Deliberately out of scope:** a controller, a web layer, Spring Security and the front end. They belong to the other components and need their own design (sessions or tokens, error format, how Angular calls the API); bolting them onto a connection demonstration would decide those questions by accident.

In the code repository the Spring Boot project is `backend/`: it will eventually hold model, controller and security together; only the view will live beside it in `frontend/`.

## 2. Run the demonstration

Prerequisites: Java 21, Docker Engine, the `mar-postgres` container from iteration 5 (`tools/phase1/dbmigrate/iteration5/ingest.sh load` if it does not exist), and a clone of `master-antique-repair-claude`.

1. **Create the application login** (once; the guide, section 3). This makes `mar_app` with a password you choose:
   ```
   cd ~/dev/claude_work/claude_modernization
   # save the mar-roles.sql shown in the guide, section 3, then:
   read -rsp 'New password for mar_app: ' APP_PW; echo
   read -rsp 'New password for mar_readonly: ' RO_PW; echo
   export APP_PW RO_PW
   docker exec -i -e APP_PW -e RO_PW mar-postgres psql -X -q -U masterantique -d masterantique < mar-roles.sql
   unset APP_PW RO_PW
   ```
   (`mar-roles.sql` is also kept at `tools/phase1/dbmigrate/iteration5/guide/mar-roles.sql`.)
2. **Open a localhost route** (once; the guide, section 4, route C). The database container publishes no port by design; a small proxy opens `127.0.0.1:5433` only:
   ```
   docker network create mar-net
   docker network connect mar-net mar-postgres
   docker run -d --name mar-postgres-proxy --network mar-net -p 127.0.0.1:5433:5432 \
     alpine/socat tcp-listen:5432,fork,reuseaddr tcp-connect:mar-postgres:5432
   ```
3. **Run the backend** (normal mode: connect and report):
   ```
   cd ~/dev/claude_work/master-antique-repair-claude/backend
   read -rsp 'mar_app password: ' MAR_DB_PASSWORD; echo; export MAR_DB_PASSWORD
   ./gradlew bootRun
   ```
   Expected (from `DatabaseCheck`, among the start-up log lines):
   ```
   Connected: mar_app @ masterantique, PostgreSQL 16.1 (Debian 16.1-1.pgdg120+1)
   users=12 tickets=24 comments=26 audit_logs=78
   customers=8 employees=3 managers=1, must reset password=12
   tickets SUBMITTED=8 INPROGRESS=8 COMPLETED=8
   ```
   Getting this far also proves the mapping: Hibernate runs with `ddl-auto=validate` and refuses to start if any entity disagrees with the live schema.
4. **Run the first-login demonstration** (the `demo` profile). **It really changes the stored password of the user you name**, so run it against a test copy of the database, or rebuild afterwards with `ingest.sh load --recreate` (which also removes the logins and network links from steps 1 and 2):
   ```
   ./gradlew bootJar
   java -jar build/libs/backend-0.0.1-SNAPSHOT.jar --spring.profiles.active=demo \
     --demo.username=Customer1 --demo.password=anything \
     --demo.one-time-code=DEMO-1234 --demo.new-password=Walnut-Armoire-1887
   ```
   Expected:
   ```
   1. Sign in as 'Customer1' -> MUST_CHANGE_PASSWORD
      You must change your password before you continue.
   ... LoginService : Password changed for user id 5 (Customer); must_reset_password cleared
   2. Password changed.
   3. Sign in again with the new password -> OK
   4. Sign in with a wrong password      -> INVALID
   ```
   Without the `--demo.*` values it asks for each one at the console, hiding passwords. A wrong one-time code gives `2. Not changed: The one-time code is not valid.`
5. **Unit tests** (no database needed): `./gradlew test` (6 tests).

To take the route down again: `docker rm -f mar-postgres-proxy; docker network disconnect mar-net mar-postgres; docker network rm mar-net`.

## 3. Decisions (made with the user)

| Decision | Choice | Why |
|---|---|---|
| Where the code goes | A real backend in `backend/` of `master-antique-repair-claude` (not a standalone sample, not the repository root) | It is the start of the Phase 2 service; `frontend/` will sit beside it. |
| Build tool | **Gradle with the Kotlin DSL** (`build.gradle.kts`), Gradle 9.4.1 wrapper | Chosen after comparing Maven, Gradle Groovy and Gradle Kotlin; all three were built and run first. The Kotlin DSL is type-checked in the editor and is Gradle's default for new builds. The wrapper means nobody installs Gradle. |
| Spring Boot version | **4.1.1** on Java 21 | Confirmed with the user; this settles, for this code, the README's Spring Boot 3 vs 4 discrepancy noted in `CLAUDE.md`. |
| Package | `com.masterantique.backend` | |
| Documentation layout | `docs/phase2/<component>/`, this plan in `model/` | Organised by architectural component (model, controller, view, security). |
| Password changes outside the demo | Refused (`RejectingIdentityCheck`) | Migrated users have no password, so identity must be proven another way before a first password is set. Until a real check exists, no account can be taken over by someone who only knows a username. |

## 4. What was built

All paths are under `master-antique-repair-claude/`.

| File | Purpose |
|---|---|
| `backend/settings.gradle.kts`, `backend/build.gradle.kts` | Spring Boot 4.1.1 plugin, `io.spring.dependency-management` 1.1.7, Java 21 toolchain. Dependencies: `spring-boot-starter-data-jpa` (Hibernate, Spring Data JPA, JDBC, HikariCP), `spring-security-crypto` (password hashing only), `postgresql` (runtime), `spring-boot-starter-test` and `junit-platform-launcher` (tests). Versions come from the Boot BOM: Hibernate 7.4.5, HikariCP 7.0.2, PostgreSQL JDBC 42.7.11. |
| `backend/gradlew`, `gradlew.bat`, `gradle/wrapper/*` | Gradle 9.4.1 wrapper (created with `gradle wrapper --gradle-version 9.4.1`). |
| `src/main/resources/application.properties` | Connection from environment variables only: `jdbc:postgresql://${MAR_DB_HOST:localhost}:${MAR_DB_PORT:5433}/${MAR_DB_NAME:masterantique}`, user `${MAR_DB_USER:mar_app}`, password `${MAR_DB_PASSWORD}` (never in a file). HikariCP pool `mar-pool` (5 connections, 10 s timeout). `spring.jpa.hibernate.ddl-auto=validate`, `open-in-view=false`, `spring.sql.init.mode=never`. |
| `src/main/resources/application-demo.properties` | Quiet console output for the demo profile. |
| `BackendApplication.java` | Entry point. |
| `DatabaseCheck.java` | Start-up runner (not in the demo profile): logs the connection through `JdbcTemplate` and the counts through the repositories. |
| `model/AppUser.java` | Table `users`. One entity for customers, employees and managers (the legacy table-per-hierarchy `discriminator` is a plain column). Every column named explicitly; `GenerationType.IDENTITY`; `LocalDateTime` for `TIMESTAMP`; `setNewPassword(hash, stamp)` clears `must_reset_password`. |
| `model/Ticket.java`, `model/TicketState.java` | Table `tickets`; `state` is the enum's ordinal 0/1/2 = `SUBMITTED`, `INPROGRESS`, `COMPLETED`; `assignee` (`user_id`) and `customer` (`customer_id`) are lazy `@ManyToOne`. |
| `model/Comment.java`, `model/AuditLog.java` | Tables `comments` and `audit_logs` (the audit trail stores ids and timestamps only). |
| `repo/AppUserRepository.java` | `findActiveByName`: `lower(u.name) = lower(:name) and u.deletedAt is null`, matching the index `ix_users_name_active ON users (lower(name)) WHERE deleted_at IS NULL`; counts by type and by `must_reset_password`. |
| `repo/TicketRepository.java`, `CommentRepository.java`, `AuditLogRepository.java` | Spring Data repositories (`countByState` on tickets). |
| `login/LoginResult.java` | `OK`, `MUST_CHANGE_PASSWORD`, `INVALID` (same answer for an unknown user and a wrong password). |
| `login/LoginService.java` | `login(username, password)`; `changePassword(username, oneTimeCode, new, confirm)`: identity check, policy (12+ characters, confirmation matches, must not contain the username), bcrypt hash via Spring Security's delegating encoder (`{bcrypt}...`), new security stamp, flag cleared, failed-attempt count reset; logs the event, never the password. |
| `login/IdentityCheck.java` | The seam where a real identity proof goes. |
| `login/RejectingIdentityCheck.java` | Default (`@Profile("!demo")`): refuses every password change. |
| `demo/DemoIdentityCheck.java` | `@Profile("demo")`: accepts one fixed code, `demo.issued-code` (default `DEMO-1234`); logs a warning on every use. |
| `demo/FirstLoginDemo.java` | `@Profile("demo")`: console walk-through of a first login. |
| `src/test/java/.../login/LoginServiceTest.java` | 6 unit tests with Mockito (repository and entity mocked, no database): migrated user must change password; unknown user is `INVALID`; a user with their own password signs in only with it; the default identity check refuses every change; the password policy; a successful change stores a bcrypt hash that never contains the password, and a new UUID stamp. |
| `.gitignore` | The original ignored every `*.jar`, which would have dropped the Gradle wrapper jar. Added `!**/gradle/wrapper/gradle-wrapper.jar`, `.gradle/`, `build/`, IDE folders, `.env`. |
| `README.md` | What exists, layout, the environment variables, build/test/run, the first-login design, next steps. |

**Where the code came from:** the entities, repositories, `LoginService` and demo classes are the tested sample project from the PostgreSQL database guide (`tools/phase1/dbmigrate/iteration5/guide/mar-db-client/`, package `com.masterantique.dbclient`), copied with the package renamed. New for the backend: `RejectingIdentityCheck`, the `demo` profile on the demo classes, `DatabaseCheck` (replacing the sample's console `ConnectionCheck`), the test suite, and the build and ignore files.

## 5. How to rebuild it from scratch

1. In `master-antique-repair-claude`, create `backend/` with `settings.gradle.kts` and `build.gradle.kts` as described in section 4.
2. Copy the sources from `claude_modernization/tools/phase1/dbmigrate/iteration5/guide/mar-db-client/src/main/java/com/masterantique/dbclient/` into `backend/src/main/java/com/masterantique/backend/`, changing `com.masterantique.dbclient` to `com.masterantique.backend`: `model/*`, `repo/*`, `login/LoginResult`, `login/IdentityCheck`, `login/LoginService`. Put `DemoIdentityCheck` and `FirstLoginDemo` in `demo/`, annotate both `@Profile("demo")`, and rename the `FirstLoginDemo` profile from `first-login-demo` to `demo`.
3. Add `RejectingIdentityCheck`, `BackendApplication`, `DatabaseCheck`, the two properties files and `LoginServiceTest` (section 4).
4. `gradle wrapper --gradle-version 9.4.1` inside `backend/`; fix `.gitignore`; write the README.
5. Verify as in section 6.

## 6. How it was verified (2026-09-23)

- `./gradlew build`: compiles; `./gradlew test`: **6 of 6 passed**.
- Against a **temporary copy** of the database (`ingest.sh load --config` with container `mar-postgres-guide`), with the logins created from `mar-roles.sql` and an `alpine/socat` proxy on `127.0.0.1:5434`:
  - normal mode: connected as `mar_app`, schema validation passed, the counts above;
  - demo mode: `Customer1` (typed in capitals) went `MUST_CHANGE_PASSWORD` → changed → `OK`, wrong password `INVALID`; a wrong one-time code was refused;
  - `./gradlew bootRun` connected the same way.
  The temporary container, proxy and network were removed afterwards.
- `git check-ignore` confirmed the wrapper jar is kept and `build/`, `.gradle/` are ignored.
- The delivered `mar-postgres` was never touched: `ingest.sh verify` still passes 80 of 80 checks.

## 7. For the user: committing

Git is read-only for Claude in this project; the user commits. In `master-antique-repair-claude`, `git status` shows the changed `.gitignore` and `README.md` and the new `backend/`. Make sure `backend/gradle/wrapper/gradle-wrapper.jar` is included (it is a `.jar`, which the `.gitignore` otherwise excludes). Nothing under `backend/build/` or `backend/.gradle/` should be committed.

## 8. Open items and next components

- **Controller** (`docs/phase2/controller/`): REST endpoints with server-side validation, for example sign-in and change-password, then tickets and comments.
- **Security** (`docs/phase2/security/`): Spring Security around `LoginService`; sessions or tokens; the forced change becomes a redirect until `must_reset_password` is false; lockout on repeated failures (`access_failed_count`, `lockout_end_date_utc` already exist); rate limiting.
- **A real `IdentityCheck`**: a single-use, expiring code issued by a manager, or an email reset link (every migrated `email` is NULL, so addresses must be collected first).
- **Audit logging**: record workflow changes and password changes in the legacy `audit_logs` format (ids and timestamps, never comment text or passwords); the numeric action codes need mapping from the legacy application.
- **View** (`docs/phase2/view/`): the Angular app in `frontend/`.
- **Database target**: settled on 2026-09-23 — **PostgreSQL only; Oracle (named in the exercise brief) is not pursued.** This model runs on the database the migration produced, so no further data migration is planned.
- **Time zones**: `TIMESTAMP` columns are read as `LocalDateTime` with no conversion; whether the legacy system stored UTC or local time is still unknown.
