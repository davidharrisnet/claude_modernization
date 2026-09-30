# Plan: Phase 2 controller layer on Oracle - a REST API with Swagger UI over the migrated Oracle database

**Status: PLANNED (2026-09-29), not yet executed.** Written on Windows, to be run on the Linux machine by a person or a
new Claude session with no memory of the planning conversation. It runs when the user says **`Run controller-oracle`**
(section 6). Target home of this plan: `claude_modernization/docs/phase2/controller/oracle/CLAUDE.md`.

## Context

`model/oracle/` (Spring Boot 4.1.1, Java 21) maps five of the eight migrated Oracle tables with JPA and has
`LoginService`, but no web layer. The user wants the Spring Boot ORM bootstrapped against a copy of the migrated Oracle
database and a REST API, browsable through a Swagger page, with CRUD on every table. This is the Oracle proof of
concept of the Phase 2 controller layer; Phase 2 itself stays on PostgreSQL (a later `controller-postgresql` repeats
it). Planning happened on Windows, where Oracle cannot run; everything below is executed on Linux.

**Self-contained, like `model/oracle`:** nothing reads from or depends on any PostgreSQL folder.

| What | Where (Linux) |
|---|---|
| This plan | `~/dev/claude_work/claude_modernization/docs/phase2/controller/oracle/CLAUDE.md` |
| The code | `model/oracle/` in the Phase 2 repository (`master-antique-repair-modern`, formerly `-claude`; use the clone's actual path, called `$APP` below) |
| Database tool | `~/dev/claude_work/claude_modernization/tools/phase1/dbmigrate/import-oracle/ingest.sh` (`$MOD/...`) |

## 1. Decisions (agreed in planning, 2026-09-29)

1. **Own database copy `mar-oracle-controller`**, long-lived, loaded by import-oracle's `ingest.sh load --recreate
   --config /tmp/mar-oracle-controller.conf`. `mar-oracle` stays read-only (verified untouched at the end);
   `mar-oracle-demo` stays `Run model-oracle`'s temporary copy. Route: network `mar-net-controller`, proxy
   `mar-oracle-controller-proxy` on `127.0.0.1:1524`.
2. **Code lives in `model/oracle/`** (one self-contained Oracle project; its rules 1-6 still hold, especially
   `ddl-auto=validate`: fix entities, never the schema).
3. **`audit_logs` is read-only through the API** (GET only). Rows are written by the services when a workflow or
   data change happens, in the legacy format (below). Full CRUD on audit rows would defeat the audit trail.
4. **`DELETE /users/{id}` is a soft delete** (sets `deleted_at`, frees the username through `ix_users_name_active`).
   A hard delete would cascade away the user's `audit_logs`, `comments`, `user_claims`, `user_logins`, `user_roles`
   (all `ON DELETE CASCADE`).
5. **Tickets follow the legacy workflow** `SUBMITTED -> INPROGRESS -> COMPLETED`; state changes only through
   workflow endpoints, each writing an audit row.
6. **Users never expose or accept `password_hash` / `security_stamp`.** New users get no password and
   `must_reset_password = true`; passwords change only through `LoginService`.
7. **No Spring Security yet** (its own component, `docs/phase2/security/`): the server binds to `127.0.0.1` only.
   The acting user for audit rows comes from a request header `X-Acting-User-Id` (required on writes, must be an
   active user) - an explicit stand-in until authentication exists, documented as such in Swagger.

## 2. The schema (from `import-oracle/input/01-schema.sql`)

| Table | Key | Entity today | Notes |
|---|---|---|---|
| `roles` | identity `id` | none -> `Role` | `name VARCHAR2(256 CHAR)`, unique `ix_roles_name` |
| `users` | identity `id` | `AppUser` | TPH `discriminator` Customer/Employee/Manager; CLOBs `password_hash`, `security_stamp`, `phone_number` |
| `tickets` | identity `id` | `Ticket` | `state` ordinal 0/1/2; `user_id` = assignee, `customer_id` |
| `comments` | identity `id` | `Comment` | `text VARCHAR2(2000 CHAR)`, cascade from tickets and users |
| `audit_logs` | identity `id` | `AuditLog` | `action`, `entity_type` numeric codes |
| `user_claims` | identity `id` | none -> `UserClaim` | `claim_type`, `claim_value` are CLOB (`@Lob`) |
| `user_roles` | (`user_id`, `role_id`) | none -> `UserRole` | composite key, `@IdClass(UserRoleId)` |
| `user_logins` | (`login_provider`, `provider_key`, `user_id`) | none -> `UserLogin` | composite key, `@IdClass(UserLoginId)`, `VARCHAR2(128 CHAR)` |

**Legacy audit codes** (`master-antique-repair/.../MasterAntiqueRepairData/App_Code/AuditLog.cs`; ordinals, never
reorder): `ActionType` CreateUser 0, Login 1, CreateTicket 2, AssignTicket 3, CompleteTicket 4, AddComment 5,
EditComment 6, DeleteComment 7, RequestPasswordReset 8, ResetPassword 9, EditUser 10, DeleteUser 11; `EntityKind`
User 0, Ticket 1, Comment 2. The migrated data uses 0,1 (User) 2,3,4 (Ticket) 5 (Comment). Add them as Java enums
`AuditAction` and `AuditEntityKind` (ordinal-mapped) and switch `AuditLog` to them; rows hold ids and timestamps
only, never comment text or descriptions.

## 3. Code changes in `$APP/model/oracle/`

**Build (`build.gradle.kts`)**: add `spring-boot-starter-webmvc` (Boot 4 name; `spring-boot-starter-web` if the
BOM still prefers it), `spring-boot-starter-validation`, `org.springdoc:springdoc-openapi-starter-webmvc-ui` in the
3.x line (the Boot 4 line; confirm the latest 3.x on Maven Central and pin it), and for tests
`spring-boot-starter-webmvc-test` if `@WebMvcTest` is used. Boot 4 uses Jackson 3 (`tools.jackson`) - keep DTOs as
plain records so this does not matter.

**`application.properties`**: `server.address=127.0.0.1`, `server.port=${MAR_API_PORT:8080}`,
`springdoc.swagger-ui.path=/swagger-ui.html`, `springdoc.api-docs.path=/v3/api-docs`,
`spring.mvc.problemdetails.enabled=true`. The DB defaults stay; the run sets `MAR_DB_PORT=1524`.

**Packages** (layering: controller -> service -> repository; no logic in controllers):
```
model/      + Role, UserRole (+UserRoleId), UserClaim, UserLogin (+UserLoginId), AuditAction, AuditEntityKind;
              AppUser gains setters for editable fields + softDelete(); Ticket gains assign()/complete()/create
              factory; Comment gains edit()/create factory (entities keep their exact @Column names/lengths)
repo/       + RoleRepository, UserRoleRepository, UserClaimRepository, UserLoginRepository;
              AppUserRepository.existsActiveByName using the same CASE expression as findActiveByName
api/dto/    request/response records per resource, Bean Validation (@NotBlank, @Size in CHARACTERS matching the
              column, @Email, @Pattern for discriminator); UserResponse has no password fields
service/    RoleService, UserService, TicketService, CommentService, UserClaimService, UserRoleService,
              UserLoginService, AuditLogService (read) + AuditWriter (package-private use by services),
              ActingUser (resolves X-Acting-User-Id to an active AppUser or 400)
api/        one @RestController per resource + ApiExceptionHandler (@RestControllerAdvice -> ProblemDetail:
              NotFound 404, IllegalArgumentException/validation 400, IllegalStateException 409,
              DataIntegrityViolationException 409 e.g. duplicate username/role) + OpenApiConfig (title, header doc)
```
Every service method `@Transactional`; `open-in-view` stays off, so services map entities to DTOs before returning.

**Endpoints** (all JSON; lists take `page`, `size` (max 100), `sort`; `X-Acting-User-Id` on every write):

| Resource | Endpoints | Rules |
|---|---|---|
| Roles | `GET/POST /api/roles`, `GET/PUT/DELETE /api/roles/{id}` | 409 on duplicate name; DELETE cascades `user_roles` (say so in Swagger) |
| Users | `GET /api/users?discriminator=&includeDeleted=false`, `POST`, `GET/PUT/DELETE /api/users/{id}` | POST: name, discriminator, email, phone -> no password, must reset, audit CreateUser; PUT: audit EditUser; DELETE = soft delete, audit DeleteUser; 409 on active duplicate name |
| Tickets | `GET /api/tickets?state=&customerId=&assigneeId=`, `POST`, `GET/PUT /api/tickets/{id}`, `POST /api/tickets/{id}/assign {employeeId}`, `POST /api/tickets/{id}/complete` | POST: customer must be an active Customer, state SUBMITTED, submitted_date now, audit CreateTicket; PUT edits description only; assign: SUBMITTED only, assignee an active Employee or Manager, audit AssignTicket; complete: INPROGRESS only, audit CompleteTicket; wrong state 409. **No DELETE** (legacy has none and no audit code; flagged as a parity note) |
| Comments | `GET /api/comments?ticketId=`, `POST`, `GET/PUT/DELETE /api/comments/{id}` | audit AddComment / EditComment / DeleteComment; hard delete (legacy behaviour) |
| User claims | `GET /api/user-claims?userId=`, `POST`, `GET/PUT/DELETE /api/user-claims/{id}` | CLOB fields, size-limited in the DTO |
| User roles | `GET /api/user-roles?userId=&roleId=`, `POST {userId, roleId}`, `DELETE /api/user-roles/{userId}/{roleId}` | no PUT (the row is its key); 409 on duplicate |
| User logins | `GET /api/user-logins?userId=`, `POST`, `DELETE /api/user-logins/{userId}/{loginProvider}/{providerKey}` | no PUT (the row is its key); 409 on duplicate |
| Audit logs | `GET /api/audit-logs?userId=&entityType=&entityId=`, `GET /api/audit-logs/{id}` | read-only; responses show action/entity names and codes |

Text limits: Oracle `MAX_STRING_SIZE = STANDARD` caps a value at 4,000 bytes; validate `description`/`text` at
2,000 characters and also reject over 4,000 UTF-8 bytes (service check, 400).

**Tests** (unit, Mockito, no database; alongside the 6 `LoginServiceTest` tests): one test class per service
covering the rules above (workflow transitions and wrong-state 409s, soft delete, duplicate names, audit rows
written with the right codes and never with text, password fields never mapped). Optionally one `@WebMvcTest` for
`ApiExceptionHandler` status mapping.

**Docs**: `model/oracle/README.md` and `model/oracle/CLAUDE.md` (layout, settings, a "Run controller-oracle"
section copied from section 6 here); `claude_modernization/CLAUDE.md` (add the `Run controller-oracle` prompt);
Phase 2 repo root `README.md`/`CLAUDE.md` (the controller exists for Oracle). Fix stale
`master-antique-repair-claude` paths only where these files are touched anyway.

## 4. Reuse

- `ingest.sh load --recreate --config` and `ingest.conf.example` (as `Run model-oracle` step 3) to build the copy.
- `model/oracle/db/mar-roles.sql` for the `mar_app` / `mar_readonly` logins (schema privileges already cover all
  eight tables, including INSERT/UPDATE/DELETE).
- `AppUserRepository.findActiveByName` and its CASE-expression pattern (index-friendly) for duplicate checks.
- `LoginService` unchanged; `DatabaseCheck` still logs counts at start-up (keeps proving `validate`).
- The alpine/socat proxy pattern from `Run model-oracle` step 4.

## 5. Security and data rules

No password in any file, command line or output (generated in the shell, used, unset). `mar-oracle` is never written.
The API listens on 127.0.0.1 only and has no authentication: a local demonstration, not deployable. Responses and
logs never carry password hashes, security stamps, or (in audit rows) comment/description text. Git stays read-only
for Claude; the user commits.

## 6. `Run controller-oracle` (Linux)

Stop at the first failure and report; the database copy and proxy are meant to stay up afterwards.
1. **Prerequisites**: `java -version` 21, `docker info`, `$MOD/tools/phase1/dbmigrate/import-oracle/ingest.sh` exists.
2. **Build and unit tests**: `cd $APP/model/oracle && ./gradlew build && ./gradlew test --rerun` -> BUILD SUCCESSFUL,
   `LoginServiceTest` 6 + the new service tests, 0 failures.
3. **Fresh copy**: write `/tmp/mar-oracle-controller.conf` (CONTAINER=mar-oracle-controller, INPUT_DIR=import-oracle
   input) with `sed` from `ingest.conf.example`, then `ingest.sh load --recreate --config` it -> LOAD COMPLETE, 156 rows.
4. **Route**: create `mar-net-controller` (skip if exists), connect the container, run `mar-oracle-controller-proxy`
   (`-p 127.0.0.1:1524:1521`, alpine/socat).
5. **In one shell**: generate `APP_PW`/`RO_PW`, pipe them with `db/mar-roles.sql` into
   `docker exec -i mar-oracle-controller sqlplus -S / as sysdba` (expect 2 x "User created"); `export MAR_DB_PORT=1524
   MAR_DB_PASSWORD=$APP_PW`; start `java -jar build/libs/model-oracle-0.0.1-SNAPSHOT.jar` in the background, wait for
   `curl -sf 127.0.0.1:8080/v3/api-docs`; then the smoke test with `curl` (acting user: the Manager's id):
   - `GET /swagger-ui.html` 200 (after redirect) and `/v3/api-docs` lists 8 resource tags;
   - GET list on each resource: users 12, tickets 24, comments 26, audit-logs 79, roles 3, user-roles 12, claims 0, logins 0;
   - roles: create, read, rename, delete; users: create (must reset, no password fields in JSON), edit, soft delete,
     then re-create the same name (allowed), duplicate active name 409;
   - tickets: create for a Customer -> SUBMITTED, assign to an Employee -> INPROGRESS, complete -> COMPLETED,
     complete again 409, PUT description; comments: add, edit, delete; claims, user-roles, logins: create, read, delete;
   - audit-logs now 79 + the rows the smoke test wrote, with the expected action codes and no text;
   - invalid input (blank name, 2,001-character description) 400 with a ProblemDetail body.
   Stop the app (`kill`), `unset APP_PW RO_PW MAR_DB_PASSWORD`.
6. **Prove the delivered database untouched** (if `mar-oracle` exists):
   `$MOD/tools/phase1/dbmigrate/import-oracle/ingest.sh verify --out "$(mktemp)"` -> `VERIFICATION PASSED - 86 of 86`.
7. **Report** the numbers, and tell the person how to use Swagger themselves: set their own `mar_app` password
   (`read -rsp` + `ALTER USER mar_app IDENTIFIED BY ...` through `docker exec -i ... sqlplus / as sysdba`), export
   `MAR_DB_PORT=1524` and `MAR_DB_PASSWORD`, `./gradlew bootRun`, open `http://127.0.0.1:8080/swagger-ui.html`.
   Remove everything with `docker rm -f mar-oracle-controller-proxy; docker rm -f -v mar-oracle-controller;
   docker network rm mar-net-controller; rm -f /tmp/mar-oracle-controller.conf`.

## 7. Verification (definition of done)

- Build green; all unit tests pass; Hibernate `validate` passes with the four new entities.
- Swagger UI loads and documents all eight resources, the `X-Acting-User-Id` header and the error format.
- Every smoke-test step in 6.5 returns the expected status and counts; audit rows written match the legacy codes.
- `mar-oracle` verification still 86 of 86.

## 8. Known gaps to note (parity and risk)

- No authentication/authorization: the acting-user header is trust-the-caller, local only.
- No ticket DELETE (none in Phase 1). Roles DELETE cascades role assignments.
- `Login`, `RequestPasswordReset`, `ResetPassword` audit codes are not yet written by `LoginService` (security component).
- Time zone of `TIMESTAMP(3)` values is unknown (legacy); new rows use the server's local time like Phase 1 -
  confirm, or switch both to UTC in the security/controller PostgreSQL work.
