---
title: SQLite Database Guide — Iteration 3
---

|                  |                                                                 |
|------------------|-----------------------------------------------------------------|
| **Iteration**    | 3 — SQLite baked into a custom Docker image, independently verified, credentials sanitized |
| **File**         | /data/masterantique.sqlite (inside the image `masterantique-sqlite:iteration3`) |
| **Size**         | 100.0 KB (102,400 bytes) |
| **SQLite version** | sqlite3 3.45.3 on Alpine Linux v3.20 (same base image and SQLite package as iteration 2) |
| **Tables**       | 8 (the EF `__MigrationHistory` table was deliberately not migrated) |
| **Built by**     | `dbmigrate3.sh build`, native Linux tooling (bash + Python + docker), no PowerShell |

# 1. What this database is

This is the MasterAntiqueRepair repair-shop database, carrying the same schema and data lineage as iterations 1/2, with two changes made deliberately in this iteration: it is **baked into a Docker image at build time** (`docker build` fails if the schema/data don't load cleanly or `PRAGMA integrity_check` isn't `ok`, so a working image is a working database by construction), and every account's **login credentials have been sanitized** — see section 7.

Verification for this build does not compare against iteration 1 or iteration 2's stored results. Instead, two databases are built independently in every verification run — this image, and a throwaway local control database built directly with the `sqlite3` CLI — and cross-checked against each other. Section 3 explains how to work with the database; section 9 explains how to distribute the image.

# 2. Version and file format

- SQLite 3.45.3 on Linux (Alpine 3.20), the same version iteration 2 used — the database file format is unchanged.
- Java: the xerial `sqlite-jdbc` driver (`jdbc:sqlite:<path>`) reads it directly, the likely route for the Phase 2 Spring Boot application.
- Built entirely with native Linux tooling (bash, Python, the `sqlite3` and `docker` CLIs) — no PowerShell, no Windows, no Docker Desktop. Ran on a plain Linux Docker Engine install (29.7.2), not a WSL2-backed Docker Desktop as iterations 1/2 did.

# 3. Accessing the database

The database is the file `/data/masterantique.sqlite` inside any container started from the image `masterantique-sqlite:iteration3`. This guide's example container is `mar-sqlite-iter3`.

## 3.1 Is the container up?
```
docker ps --filter name=mar-sqlite-iter3
docker start mar-sqlite-iter3
docker exec mar-sqlite-iter3 ls -l /data/masterantique.sqlite
docker exec mar-sqlite-iter3 sqlite3 -version
```

## 3.2 Interactive session
```
docker exec -it mar-sqlite-iter3 sh
sqlite3 /data/masterantique.sqlite
sqlite> PRAGMA foreign_keys = ON;
sqlite> .headers on
sqlite> .mode column
sqlite> .tables
sqlite> SELECT COUNT(*) FROM Users;
sqlite> .quit
exit
```
`PRAGMA foreign_keys = ON` must be issued on every connection; SQLite does not enforce relationships otherwise.

## 3.3 One query, no interactive session
```
docker exec mar-sqlite-iter3 sqlite3 -header -column /data/masterantique.sqlite "SELECT COUNT(*) FROM Users;"
```

## 3.4 A fresh container from the same image
Because the data is baked into the image (not the container), starting a brand new container from the same tag gives byte-identical data — no rebuild, no re-import:
```
docker run -d --name mar-sqlite-iter3-copy masterantique-sqlite:iteration3
docker exec mar-sqlite-iter3-copy sqlite3 /data/masterantique.sqlite "SELECT COUNT(*) FROM Users;"
docker rm -f mar-sqlite-iter3-copy
```
This is the practical difference from iteration 2: there, a fresh container starts empty and has to be loaded; here, a fresh container from the tag is already populated.

## 3.5 Health checks
```
docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite "PRAGMA integrity_check;"   # must print: ok
docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite "PRAGMA foreign_key_check;" # must print nothing
```

## 3.6 Lifecycle
| Action | Effect |
|---|---|
| `docker stop`/`start mar-sqlite-iter3` | Database kept — it's baked into the image, not the container's writable layer. |
| `docker rm -f mar-sqlite-iter3` | Container removed; the **image** (and its baked-in data) is untouched — `docker run` from the tag again recreates an identical container. |
| `docker rmi masterantique-sqlite:iteration3` | The image itself, and the baked-in data, are gone. Rebuild from `tools/dbmigrate/iteration3/` to recreate it. |

This is the key difference from iteration 2, where `docker rm -f mar-sqlite` deleted the *only* copy of the data.

# 4. Schema

Tables and rows in this build:

| Table | Rows |
|---|---|
| AuditLogs | 78 |
| Comments | 26 |
| Roles | 3 |
| Tickets | 24 |
| UserClaims | 0 |
| UserLogins | 0 |
| UserRoles | 12 |
| Users | 12 |

`Users` gained one column relative to iterations 1/2: **`MustResetPassword INTEGER NOT NULL DEFAULT 0`**, set to `1` on every migrated row (see section 7).

## Relationships (foreign keys)
| Table | Column | References | On delete |
|---|---|---|---|
| AuditLogs | UserId | Users.Id | CASCADE |
| Comments | TicketId | Tickets.Id | CASCADE |
| Comments | UserId | Users.Id | CASCADE |
| Tickets | Customer_Id | Users.Id | NO ACTION |
| Tickets | User_Id | Users.Id | NO ACTION |
| UserClaims | UserId | Users.Id | CASCADE |
| UserLogins | UserId | Users.Id | CASCADE |
| UserRoles | RoleId | Roles.Id | CASCADE |
| UserRoles | UserId | Users.Id | CASCADE |

## Indexes
`IX_Users_Name_Active` is the important one: a unique index on `Users.Name` that only covers rows where `DeletedAt IS NULL`. A soft-deleted account keeps its row but frees its username for reuse — verified working in this build's behaviour tests (§7 of `MigrationVerificationReport3.docx`).

# 5. Using it: what the values mean

- `Users` is one table for all account types (table-per-hierarchy); `Discriminator` holds `Customer`, `Employee` or `Manager`. `DeletedAt IS NULL` means active.
- `Roles`/`UserRoles` hold role assignments (Customer = 1, Employee = 2, Manager = 3).
- `Tickets.Customer_Id` is the submitter; `Tickets.User_Id` is the assigned employee, `NULL` until assigned.
- Comments are add-only in the application.
- Dates are ISO-8601 text (`yyyy-MM-dd HH:mm:ss.fffffff`); yes/no columns are `INTEGER` 0/1 protected by `CHECK` constraints.

## Ticket state (Tickets.State)
| Value | Meaning |
|---|---|
| 0 | SUBMITTED |
| 1 | INPROGRESS |
| 2 | COMPLETED |

## Audit action (AuditLogs.Action)
| Value | Meaning |
|---|---|
| 0 | CreateUser |
| 1 | Login |
| 2 | CreateTicket |
| 3 | AssignTicket |
| 4 | CompleteTicket |
| 5 | AddComment |
| 6 | EditComment |
| 7 | DeleteComment |
| 8 | RequestPasswordReset |
| 9 | ResetPassword |
| 10 | EditUser |
| 11 | DeleteUser |

The audit log stores ids and timestamps only, never comment text or ticket descriptions. This log format is what Phase 2 must preserve or improve on.

# 6. Example queries

Run against this build; results are identical to iterations 1 and 2 for every column except the credential columns (see section 7).

```sql
SELECT CASE State WHEN 0 THEN 'SUBMITTED' WHEN 1 THEN 'INPROGRESS' WHEN 2 THEN 'COMPLETED' END, COUNT(*)
FROM Tickets GROUP BY State ORDER BY State;
```
| State | Tickets |
|---|---|
| SUBMITTED | 8 |
| INPROGRESS | 8 |
| COMPLETED | 8 |

```sql
SELECT Discriminator, COUNT(*), SUM(DeletedAt IS NULL), SUM(DeletedAt IS NOT NULL)
FROM Users GROUP BY Discriminator ORDER BY Discriminator;
```
| Type | Accounts | Active | Soft-deleted |
|---|---|---|---|
| Customer | 8 | 8 | 0 |
| Employee | 3 | 3 | 0 |
| Manager | 1 | 1 | 0 |

# 7. Credentials — sanitized, by design

Unlike iterations 1/2, **this database contains no usable credential material at all.** Every `Users` row has `PasswordHash = NULL`, `SecurityStamp = NULL`, and the new column `MustResetPassword = 1`:
```
docker exec mar-sqlite-iter3 sqlite3 /data/masterantique.sqlite \
  "SELECT Id, Name, PasswordHash, SecurityStamp, MustResetPassword FROM Users LIMIT 3;"
1|manager|||1
2|employee1|||1
3|employee2|||1
```

**Why:** this project's use case is a one-time legacy→modern bootstrap. Forcing every migrated account through a password reset on next login is an acceptable trade-off for a cutover, so there is no need to carry a *usable* legacy password hash into the new system at all — doing so would mean the new system has to understand the legacy PBKDF2 hash format, and it would mean a real secret has to be protected in every downstream artifact (this image, any backup, any registry it's pushed to) indefinitely. Instead, `tools/dbmigrate/iteration3/sanitize.py` invalidates credentials as part of the migration itself: the real hash never leaves the transient, gitignored `02-data.sql`, and every other column is preserved unchanged (verified — see `MigrationVerificationReport3.docx` §7's sanitization checks).

Every other column (`Name`, `CreatedAt`, `Discriminator`, `DeletedAt`, `Email`, and the rest) is preserved exactly as exported. Only `PasswordHash` and `SecurityStamp` are touched.

# 8. Regenerating the database and this guide

From `tools/dbmigrate/iteration3/` on a Linux host with Docker (and a copy of the raw `02-data.sql` from `tools/dbmigrate/iteration2/02-data.sql` — it's gitignored here and regenerated/copied locally, never committed):
```
./dbmigrate3.sh all --recreate
```
This sanitizes the raw data (`sanitize.py`), rebuilds the image, starts a fresh container, verifies it by building an independent local control database and cross-checking the two (no dependency on iteration 1/2's stored results, no live SQL Server connection), runs the tooling self-test, and writes `verification-results.json`/`selftest-results.json`. To rebuild the verification report from those results:
```
python3 report.py
```
To rebuild this guide (a static document — its numbers don't change unless the schema/data do):
```
pandoc guide.md -o ../../../docs/dbmigrate/iteration3/SQLiteDatabaseGuide3.docx
```

Exit codes: 0 success, 1 verification/selftest differences, 2 configuration/tool error, 3 refused (container already exists, no `--recreate`).

# 9. Distributing the image

This is the point of iteration 3: the database travels as part of the image, not as a separate file someone has to load — and because credentials are sanitized (section 7), the image can be distributed without carrying any real secret.

## 9.1 Save and load the image as a file
```
docker save masterantique-sqlite:iteration3 -o masterantique-sqlite-iteration3.tar
docker load -i masterantique-sqlite-iteration3.tar
```
The `.tar` is a complete, self-contained copy of the image — including the baked-in database — that can be moved to another machine with no network access and no rebuild.

## 9.2 Push to a registry
```
docker tag masterantique-sqlite:iteration3 <registry>/<namespace>/masterantique-sqlite:iteration3
docker push <registry>/<namespace>/masterantique-sqlite:iteration3
```
Safe to push to a private or public registry as far as this database's own contents are concerned — no real credential material is baked in. (Iterations 1/2's raw exported files still contain real hashes and should never be pushed anywhere; that's specific to those files, not this image.)

## 9.3 What is preserved, and what is not
| | Preserved | Not preserved |
|---|---|---|
| Baking data into the image | Portability (one artifact, no separate load step), reproducibility (`docker build` is the whole story) | An update path — changing the data means rebuilding the image, not patching a running container |
| Sanitizing credentials | Safe to distribute; no secret to protect in this artifact | The legacy password itself — every migrated account must reset their password on next login |
| Image size | — | Grows with the data; this build is 19.5 MB (mostly Alpine + `sqlite-tools`; the database itself is only 100 KB) |

## 9.4 Verifying a distributed copy
After `docker load` on another machine, confirm it's the expected database before trusting it:
```
docker run -d --name mar-sqlite-check masterantique-sqlite:iteration3
docker exec mar-sqlite-check sqlite3 /data/masterantique.sqlite "PRAGMA integrity_check;"
docker exec mar-sqlite-check sqlite3 /data/masterantique.sqlite \
  "SELECT COUNT(*) FROM Users WHERE PasswordHash IS NOT NULL OR SecurityStamp IS NOT NULL OR MustResetPassword != 1;"
```
The first must print `ok`; the second must print `0` — confirming both structural integrity and that no credential material has been reintroduced. For a full check, copy `verify.py` alongside the image and run it against the running container.
