# Plan: Phase 2 controller layer on Oracle - a REST API with Swagger UI over the migrated Oracle database

**Status: PLANNED (2026-09-30), not yet executed.** Written on Windows, to be run on the Linux machine by a person or a
new Claude session with no memory of the planning conversation. It runs when the user says **`Run import-controller`**
or `/import-controller` (section 6). Target home of this plan: `claude_modernization/docs/phase2/controller/oracle/CLAUDE.md`.

## Context

`model/oracle/` (Spring Boot 4.1.1, Java 21) maps five of the eight migrated Oracle tables with JPA and has
`LoginService`, but no web layer. This plan adds a REST API, browsable through a Swagger page, on the migrated Oracle
database `mar-oracle`. The API offers **only the actions in the controller contract**
`docs/phase2/controller/CONTROLLER.md` (29 numbered actions, written by `/export-controller` from the legacy pages),
not CRUD on every table. Planning happened on Windows, where Oracle cannot run; everything below is executed on Linux.

**The contract governs.** Build only once `CONTROLLER.md` says `Status: approved`. Section 3's endpoint table is keyed
by the contract's action numbers; if the contract is regenerated and its numbers or actions change, re-check the table
before building. Where this plan and the contract disagree, the contract wins.

| What | Where (Linux) |
|---|---|
| This plan | `~/dev/claude_work/claude_modernization/docs/phase2/controller/oracle/CLAUDE.md` |
| The contract | `~/dev/claude_work/claude_modernization/docs/phase2/controller/CONTROLLER.md` |
| The code | `model/oracle/` in the Phase 2 repository (`master-antique-repair-modern`, formerly `-claude`; use the clone's actual path, called `$APP` below) |
| Database tool | `~/dev/claude_work/claude_modernization/tools/phase2/dbmigrate/import-oracle/ingest.sh` (`$MOD/...`) |

## 1. Decisions

1. **One database: `mar-oracle`**, as built and verified by `/import-oracle`; no copy. The run starts only on a fresh
   `mar-oracle` (verify 86 of 86, so the smoke test's fixed counts hold) and its smoke test writes to it, so afterwards
   verify fails (counts, hashes, identity sequences) until `/import-oracle all --recreate` restores it. Route: the
   delivered database's own network `mar-net` and proxy `mar-oracle-proxy` on `127.0.0.1:1522` (created if missing,
   as in the database guide).
2. **Code lives in `model/oracle/`** (one self-contained Oracle project; its rules 1-6 still hold, especially
   `ddl-auto=validate`: fix entities, never the schema).
3. **Security actions are out of scope** (the security component, `docs/phase2/security/`): contract actions 1-5
   (sign-up, reset request, login, reset-link check, reset), the password fields of 16, 17, 20 and 21, and log off get
   no endpoint here. New users get no password and `must_reset_password = true`; users never expose or accept
   `password_hash` / `security_stamp`.
4. **Acting user stand-in.** With no Spring Security yet, the server binds to `127.0.0.1` only and every request names
   its user in the header `X-Acting-User-Id` (an active user, else 400). The user's role comes from `user_roles` ->
   `roles.name`, as in the legacy app (`RepairAuthHelper.RequireRole` checks the role, not the discriminator); an action
   called by the wrong role is 403. Documented in Swagger as a stand-in until authentication exists.
5. **Audit rows are written only by the services**, in the legacy format (codes in section 2), never through the API;
   `audit_logs` is read-only (action 14).
6. **Explicit responses where the legacy app silently did nothing** (contract rule "Silent no-ops"): unknown or not-mine
   ticket, comment target or user -> 404; take an already-assigned ticket -> 409; comment on a ticket that is not
   COMPLETED -> 409; validation -> 400 (ProblemDetail).
7. **Two small, flagged improvements over the legacy behaviour** (section 8): completing an already-COMPLETED ticket ->
   409 (legacy re-completes and moves the date), and an invalid completion comment -> 400 with nothing changed (legacy
   crashes the page after the state change).

## 2. The schema (from `import-oracle/input/01-schema.sql`)

| Table | Key | Entity today | Used by the API |
|---|---|---|---|
| `roles` | identity `id` | none -> `Role` | role names for the acting user's role and new users' role (16, 20) |
| `users` | identity `id` | `AppUser` | TPH `discriminator` Customer/Employee/Manager; CLOBs `password_hash`, `security_stamp`, `phone_number` |
| `tickets` | identity `id` | `Ticket` | `state` ordinal 0/1/2; `user_id` = assignee, `customer_id` |
| `comments` | identity `id` | `Comment` | `text VARCHAR2(2000 CHAR)`; add-only |
| `audit_logs` | identity `id` | `AuditLog` | `action`, `entity_type` numeric codes; read-only through the API |
| `user_roles` | (`user_id`, `role_id`) | none -> `UserRole` | composite key, `@IdClass(UserRoleId)`; one row per user |
| `user_claims` | identity `id` | none | no page uses it (0 rows); no entity, no endpoint |
| `user_logins` | composite | none | no page uses it (0 rows); no entity, no endpoint |

**Legacy audit codes** (`MasterAntiqueRepairData/App_Code/AuditLog.cs`; ordinals, never reorder): `ActionType`
CreateUser 0, Login 1, CreateTicket 2, AssignTicket 3, CompleteTicket 4, AddComment 5, EditComment 6, DeleteComment 7,
RequestPasswordReset 8, ResetPassword 9, EditUser 10, DeleteUser 11; `EntityKind` User 0, Ticket 1, Comment 2. Add
them as Java enums `AuditAction` and `AuditEntityKind` (ordinal-mapped) and switch `AuditLog` to them; rows hold ids and
timestamps only, never comment text or descriptions. This API writes 2, 3, 4, 5, 0, 10 and 11.

## 3. Code changes in `$APP/model/oracle/`

**Build (`build.gradle.kts`)**: add `spring-boot-starter-webmvc` (Boot 4 name; `spring-boot-starter-web` if the
BOM still prefers it), `spring-boot-starter-validation`, `org.springdoc:springdoc-openapi-starter-webmvc-ui` in the
3.x line (the Boot 4 line; confirm the latest 3.x on Maven Central and pin it), and for tests
`spring-boot-starter-webmvc-test` if `@WebMvcTest` is used. Boot 4 uses Jackson 3 (`tools.jackson`) - keep DTOs as
plain records so this does not matter.

**`application.properties`**: `server.address=127.0.0.1`, `server.port=${MAR_API_PORT:8080}`,
`springdoc.swagger-ui.path=/swagger-ui.html`, `springdoc.api-docs.path=/v3/api-docs`,
`spring.mvc.problemdetails.enabled=true`. The DB defaults stay; the run sets `MAR_DB_PORT=1522`.

**Packages** (layering: controller -> service -> repository; no logic in controllers):
```
model/      + Role, UserRole (+UserRoleId), AuditAction, AuditEntityKind;
              AppUser gains rename() + softDelete(); Ticket gains take()/complete() + a create factory with the
              description rules; Comment gains a create factory with the text rules (entities keep their exact
              @Column names/lengths)
repo/       + RoleRepository, UserRoleRepository; queries for the orderings and filters below;
              AppUserRepository.existsActiveByName using the same CASE expression as findActiveByName
api/dto/    request/response records per action, Bean Validation (@NotBlank, @Size in CHARACTERS matching the
              column); no password or security-stamp fields anywhere
service/    TicketService (6, 8-12, 24, 26), CommentService (7, 13), AccountService (15-23, 27, 28),
              AuditLogService (14), MetricsService (25), SearchService (29), AuditWriter (package-private),
              ActingUser (resolves X-Acting-User-Id to an active user and its role, else 400; wrong role 403)
api/        one @RestController per area + ApiExceptionHandler (@RestControllerAdvice -> ProblemDetail: not found 404,
              validation 400, wrong role 403, conflict 409, DataIntegrityViolationException 409 for a duplicate
              username) + OpenApiConfig (title, the X-Acting-User-Id header)
```
Every service method `@Transactional`; `open-in-view` stays off, so services map entities to DTOs before returning.
Each controller method's OpenAPI summary starts with its action number ("Action 11: take a ticket").

**Endpoints** (JSON; `X-Acting-User-Id` on every request). Every contract action except the security ones has one:

| Action | Role | Endpoint | Rules (see the contract for the full text) |
|---|---|---|---|
| 6 | Customer | `GET /api/customers/me/tickets` | newest first (id desc), comments split employee/customer, oldest first |
| 7, 13 | Customer, Employee | `POST /api/tickets/{id}/comments {text}` | customer: own ticket; employee: assigned to me; COMPLETED only (409); text rules (400); audit AddComment |
| 8 | Customer | `POST /api/tickets {description}` | SUBMITTED, submitted date now; description rules; audit CreateTicket |
| 9, 24 | Employee, Manager | `GET /api/tickets/unassigned` | no assignee, by id; the customer is included only for a Manager (24) |
| 10 | Employee | `GET /api/employees/me/tickets` | assigned to me, by id, with state and split comments |
| 11 | Employee | `POST /api/tickets/{id}/take` | unassigned only (409 otherwise); INPROGRESS, assigned date now; audit AssignTicket |
| 12 | Employee | `POST /api/tickets/{id}/complete {comment?}` | assigned to me (404 otherwise); COMPLETED, completed date now; a non-blank comment added with the text rules; audit CompleteTicket only; already COMPLETED 409 |
| 14 | Manager | `GET /api/audit-logs?entityId=&page=&size=` | newest first; `size` 10 or 20; each row: timestamp, actor username, action and entity names and codes, entity id, the ticket id to open |
| 15, 19 | Manager | `GET /api/employees`, `GET /api/customers` | active only, by username (id, username) |
| 27, 28 (pickers) | Manager | `GET /api/customers?includeDeleted=true`, `GET /api/employees?includeDeleted=true` | all, by id, with a deleted flag |
| 16, 20 | Manager | `POST /api/employees {username}`, `POST /api/customers {username}` | username required, unique among active users (409); no password, must reset; role row `Employee` / `Customer`; audit CreateUser |
| 17, 21 | Manager | `PUT /api/employees/{id} {username}`, `PUT /api/customers/{id} {username}` | rename only (password: security component); 404 if not that kind; audit EditUser |
| 18, 22 | Manager | `DELETE /api/employees/{id}`, `DELETE /api/customers/{id}` | soft delete, username freed; audit DeleteUser |
| 23, 28 | Manager | `GET /api/employees/{id}` | username, created, deleted flag, tickets assigned (by id); deleted ones included |
| 25 | Manager | `GET /api/metrics` | the contract's 7-day summary; `hasData: false` when nothing is completed |
| 26 | Manager | `GET /api/tickets`, `GET /api/tickets/{id}` | picker: all tickets by id (id, description); detail: state, customer, assignee, the three dates, split comments |
| 27 | Manager | `GET /api/customers/{id}` | username, created, deleted flag, tickets (newest first) |
| 29 | Manager | `GET /api/search?text=` | trimmed, required (400); comments and ticket descriptions containing it, newest first |

**No endpoints** for: the security actions (decision 3); roles, user roles, user claims or user logins; writing audit
rows; ticket edit, delete, reassignment or reopening; comment edit or delete (removed in the legacy app).

Text limits: Oracle `MAX_STRING_SIZE = STANDARD` caps a value at 4,000 bytes; validate `description`/`text` at 2,000
characters after trimming, reject control characters other than CR, LF and TAB, and also reject over 4,000 UTF-8 bytes
(service check, 400).

**Tests** (unit, Mockito, no database; alongside the 6 `LoginServiceTest` tests): one test class per service, each test
named with its action number: workflow transitions and their 409s, comment rules (own/assigned ticket, COMPLETED only),
role checks (403), soft delete and username reuse, duplicate active username 409, audit rows written with the right codes
and actor and never with text, password fields never mapped. Optionally one `@WebMvcTest` for `ApiExceptionHandler`.

**Docs**: `model/oracle/README.md` and `model/oracle/CLAUDE.md` (layout, settings, a "Run import-controller" section
copied from section 6 here); Phase 2 repo root `README.md`/`CLAUDE.md` (the controller exists for Oracle). Fix stale
`master-antique-repair-claude` paths only where these files are touched anyway.

## 4. Reuse

- `ingest.sh verify` to confirm `mar-oracle` is fresh before the smoke test (`/import-oracle all --recreate` rebuilds it).
- `model/oracle/db/mar-roles.sql` for the `mar_app` / `mar_readonly` logins (schema privileges already cover all
  eight tables, including INSERT/UPDATE/DELETE).
- `AppUserRepository.findActiveByName` and its CASE-expression pattern (index-friendly) for duplicate checks.
- `LoginService` unchanged; `DatabaseCheck` still logs counts at start-up (keeps proving `validate`).
- The alpine/socat proxy `mar-oracle-proxy` from the database guide ("Using the delivered database" in
  `model/oracle/CLAUDE.md`).

## 5. Security and data rules

No password in any file, command line or output (generated in the shell, used, unset). `mar-oracle` is written only by
the smoke test, through the API as `mar_app`; never by hand, and never its schema.
The API listens on 127.0.0.1 only and trusts the `X-Acting-User-Id` header: a local demonstration, not deployable.
Responses and logs never carry password hashes, security stamps, or (in audit rows) comment/description text. Git
stays read-only for Claude; the user commits.

## 6. `Run import-controller` (Linux)

Stop at the first failure and report; `mar-oracle` and its proxy stay up afterwards.
1. **Prerequisites**: `java -version` 21, `docker info`, `$MOD/tools/phase2/dbmigrate/import-oracle/ingest.sh` exists,
   `mar-oracle` is running, and `CONTROLLER.md` says `Status: approved`.
2. **Build and unit tests**: `cd $APP/model/oracle && ./gradlew build && ./gradlew test --rerun` -> BUILD SUCCESSFUL,
   `LoginServiceTest` 6 + the new service tests, 0 failures.
3. **Fresh database**: `$MOD/tools/phase2/dbmigrate/import-oracle/ingest.sh verify --out "$(mktemp)"` ->
   `VERIFICATION PASSED - 86 of 86`. If it fails (usually an earlier smoke test's rows), stop and ask the person to run
   `/import-oracle all --recreate`; never recreate it without asking.
4. **Route**: create `mar-net` (skip if exists), connect `mar-oracle` (skip if connected), run `mar-oracle-proxy`
   (`-p 127.0.0.1:1522:1521`, alpine/socat; skip if running).
5. **In one shell**: generate `APP_PW`/`RO_PW`, pipe them with `db/mar-roles.sql` into
   `docker exec -i mar-oracle sqlplus -S / as sysdba` (expect 2 x "User created"; if the logins already exist, set the
   new passwords with `ALTER USER ... IDENTIFIED BY` the same way); `export MAR_DB_PORT=1522 MAR_DB_PASSWORD=$APP_PW`; start `java -jar build/libs/model-oracle-0.0.1-SNAPSHOT.jar` in the background, wait for
   `curl -sf 127.0.0.1:8080/v3/api-docs`; look up one active Manager, Employee and Customer id (`GET /api/employees`,
   `GET /api/customers` as the Manager; the Manager's id from the database); then the smoke test with `curl`:
   - `GET /swagger-ui.html` 200 (after redirect); `/v3/api-docs` has no path for roles, user roles, claims, logins,
     comment edit/delete or ticket delete;
   - Manager reads: `/api/tickets` 24, `/api/customers?includeDeleted=true` 8, `/api/employees?includeDeleted=true` 3,
     `/api/audit-logs` total 79, `/api/metrics` 200, `/api/search?text=a` 200, blank search 400;
   - role check: the Customer calling `/api/metrics` 403;
   - accounts (Manager): add a customer (no password fields in the JSON, must reset), rename it, soft delete it, add
     the same name again (allowed), add a duplicate active name 409;
   - workflow: Customer submits a ticket -> SUBMITTED; Customer comments on it -> 409 (not completed); Employee sees it
     in `/api/tickets/unassigned`, takes it -> INPROGRESS, takes again -> 409; completes it with a comment ->
     COMPLETED, completes again -> 409; Customer comments -> 201; Employee comments -> 201;
   - `/api/audit-logs` now 79 + the rows the smoke test wrote (CreateUser, EditUser, DeleteUser, CreateTicket,
     AssignTicket, CompleteTicket, AddComment), with those codes and no text;
   - invalid input: blank description 400, 2,001-character description 400, each with a ProblemDetail body.
   Stop the app (`kill`), `unset APP_PW RO_PW MAR_DB_PASSWORD`.
6. **Report** the numbers; say that `mar-oracle` now holds the smoke test's rows (verify will fail until
   `/import-oracle all --recreate`), and tell the person how to use Swagger themselves: set their own `mar_app`
   password (`read -rsp` + `ALTER USER mar_app IDENTIFIED BY ...` through `docker exec -i mar-oracle sqlplus / as
   sysdba`), export `MAR_DB_PORT=1522` and `MAR_DB_PASSWORD`, `./gradlew bootRun`, open
   `http://127.0.0.1:8080/swagger-ui.html`. The proxy stays; remove it with `docker rm -f mar-oracle-proxy`.

## 7. Verification (definition of done)

- Build green; all unit tests pass; Hibernate `validate` passes with the new `Role` and `UserRole` entities.
- Swagger UI loads and documents one endpoint per non-security contract action, the `X-Acting-User-Id` header and the
  error format; every summary names its action number.
- `mar-oracle` verified 86 of 86 before the smoke test; every smoke-test step in 6.5 returns the expected status and
  counts; audit rows written match the legacy codes.

## 8. Known gaps to note (parity and risk)

- No authentication: the acting-user header is trust-the-caller, local only. Actions 1-5, passwords and log off wait
  for the security component; so do the Login, RequestPasswordReset and ResetPassword audit rows.
- Deliberate differences from the legacy app: explicit 404/409 instead of silent no-ops; completing a COMPLETED ticket
  is refused; an invalid completion comment is refused before anything changes; account creation sets no password.
- The per-IP rate limits (`IpThrottle`) belong with login/sign-up in the security component.
- Time zone of `TIMESTAMP(3)` values is unknown (legacy); new rows use the server's local time like Phase 1 -
  confirm, or switch both to UTC.
