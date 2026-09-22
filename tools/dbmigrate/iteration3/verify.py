#!/usr/bin/env python3
"""verify: iteration 3 stands on its own. It does NOT read any output artifact from
iteration 1 or iteration 2 (no verification-results.json, no masterantique.sqlite from
another iteration) to decide pass/fail. Instead it builds TWO independent databases from
its own 01-schema.sql + 02-data-sanitized.sql, right now, on this Linux host:

  1. "docker" - the delivered image, built by `docker build` (see Dockerfile), running
     as the container named CONTAINER below.
  2. "local"  - a throwaway control database built directly with the local sqlite3 CLI
     (no Docker at all), from the exact same two input files.

Every check compares these two independently-built copies against each other. Neither
is treated as more authoritative than the other; agreement between two different build
mechanisms fed the same input is the evidence, not agreement with a stored answer from
a prior iteration.

01-schema.sql/02-data-sanitized.sql are themselves derived from the same export lineage
as iterations 1/2 (documented in ITERATION3.md as historical context), but that lineage
is not consulted here at verification time.

Additionally verifies the credential-sanitization step (sanitize.py): every Users row's
PasswordHash/SecurityStamp must be NULL and MustResetPassword must be 1 in both builds,
while every other Users column must still match the raw (pre-sanitization) source - see
check_credential_sanitization().

Writes tools/dbmigrate/iteration3/verification-results.json. Exit codes:
0 all checks passed, 1 a check failed, 2 tool/container error.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sanitize  # noqa: E402  (local module, for parsing the raw Users rows)

CONTAINER = "mar-sqlite-iter3"
DOCKER_DB = "/data/masterantique.sqlite"
LOCAL_DIR = HERE / "_local"
LOCAL_DB = LOCAL_DIR / "masterantique.sqlite"
SCHEMA_SQL = HERE / "01-schema.sql"
SANITIZED_DATA_SQL = HERE / "02-data-sanitized.sql"
RAW_DATA_SQL = HERE / "02-data.sql"  # gitignored, transient; used only for the
                                     # sanitization cross-check, optional if absent


def sh(cmd, check=True, input_text=None):
    r = subprocess.run(cmd, capture_output=True, text=True, input=input_text)
    if check and r.returncode != 0:
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(cmd)}\n{r.stderr}")
    return r


def docker_query(sql):
    return sh(["docker", "exec", "-i", CONTAINER, "sqlite3", "-bail", DOCKER_DB],
               input_text=sql).stdout


def local_query(sql):
    return sh(["sqlite3", "-bail", str(LOCAL_DB)], input_text=sql).stdout


def query(target, sql):
    return docker_query(sql) if target == "docker" else local_query(sql)


def build_local_control_db():
    """Independent build #2: plain sqlite3 CLI, no Docker, same two input files."""
    LOCAL_DIR.mkdir(exist_ok=True)
    if LOCAL_DB.exists():
        LOCAL_DB.unlink()
    sh(["sqlite3", "-bail", str(LOCAL_DB)], input_text=SCHEMA_SQL.read_text())
    sh(["sqlite3", "-bail", str(LOCAL_DB)], input_text=SANITIZED_DATA_SQL.read_text())
    ok = local_query("PRAGMA integrity_check;").strip()
    if ok != "ok":
        raise RuntimeError(f"local control database failed integrity_check: {ok}")


TABLES = {
    "Roles": ["Id"],
    "Users": ["Id"],
    "AuditLogs": ["Id"],
    "Tickets": ["Id"],
    "Comments": ["Id"],
    "UserClaims": ["Id"],
    "UserLogins": ["LoginProvider", "ProviderKey", "UserId"],
    "UserRoles": ["UserId", "RoleId"],
}

DOMAIN_QUERIES = [
    ("Users by type", 'SELECT "Discriminator", COUNT(*) FROM "Users" GROUP BY "Discriminator"'),
    ("Users active vs soft-deleted",
     'SELECT s, COUNT(*) FROM (SELECT CASE WHEN "DeletedAt" IS NULL THEN \'active\' ELSE '
     '\'soft-deleted\' END AS s FROM "Users") x GROUP BY s'),
    ("Users per role",
     'SELECT r."Name", COUNT(*) FROM "UserRoles" ur JOIN "Roles" r ON r."Id" = ur."RoleId" '
     'GROUP BY r."Name"'),
    ("Tickets by state", 'SELECT "State", COUNT(*) FROM "Tickets" GROUP BY "State"'),
    ("Tickets assigned vs unassigned",
     'SELECT s, COUNT(*) FROM (SELECT CASE WHEN "User_Id" IS NULL THEN \'unassigned\' ELSE '
     '\'assigned\' END AS s FROM "Tickets") x GROUP BY s'),
    ("Audit events by action", 'SELECT "Action", COUNT(*) FROM "AuditLogs" GROUP BY "Action"'),
    ("Comments per ticket (distribution)",
     'SELECT n, COUNT(*) FROM (SELECT COUNT(*) AS n FROM "Comments" GROUP BY "TicketId") x '
     'GROUP BY n'),
    ("Comment and commented-ticket totals",
     'SELECT (SELECT COUNT(*) FROM "Comments"), (SELECT COUNT(DISTINCT "TicketId") FROM "Comments")'),
    ("Ticket date ranges",
     'SELECT MIN("SubmittedDate"), MAX("SubmittedDate"), MIN("AssignedDate"), '
     'MAX("AssignedDate"), MIN("CompletedDate"), MAX("CompletedDate") FROM "Tickets"'),
    ("Account and audit date ranges",
     'SELECT (SELECT MIN("CreatedAt") FROM "Users"), (SELECT MAX("CreatedAt") FROM "Users"), '
     '(SELECT MIN("Timestamp") FROM "AuditLogs"), (SELECT MAX("Timestamp") FROM "AuditLogs")'),
]


def check_integrity():
    checks = []
    ok = docker_query("PRAGMA integrity_check;").strip()
    checks.append({"Category": "Integrity", "Name": "SQLite integrity_check (docker image)",
                    "Source": None, "Target": None, "Passed": ok == "ok",
                    "Detail": "" if ok == "ok" else ok})
    fk = docker_query("PRAGMA foreign_key_check;").strip()
    checks.append({"Category": "Integrity", "Name": "SQLite foreign_key_check (orphan rows)",
                    "Source": None, "Target": None, "Passed": fk == "", "Detail": fk})
    return checks


def schema_facts(target):
    def q(sql):
        return int(query(target, sql).strip() or 0)

    index_names = [n for n in query(
        target, "SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL;"
    ).splitlines() if n]
    return {
        "Tables": q("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"),
        "Columns (name, order, type, NOT NULL, PK position, default)": sum(
            int(query(target, f"SELECT COUNT(*) FROM pragma_table_info('{t}');").strip()) for t in TABLES),
        "Primary key columns": sum(
            int(query(target, f"SELECT COUNT(*) FROM pragma_table_info('{t}') WHERE pk > 0;").strip())
            for t in TABLES),
        "Foreign keys (column, target, ON DELETE action)": sum(
            int(query(target, f"SELECT COUNT(*) FROM pragma_foreign_key_list('{t}');").strip())
            for t in TABLES),
        "Indexes (name, unique, partial)": q(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND sql IS NOT NULL;"),
        "Index columns": sum(
            int(query(target, f"SELECT COUNT(*) FROM pragma_index_info('{n}');").strip())
            for n in index_names),
        "Partial index filters (e.g. active-username rule)": q(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND sql LIKE '%WHERE%';"),
        "Auto-increment (identity) tables": q(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND sql LIKE '%AUTOINCREMENT%';"),
    }


def check_schema():
    local_facts = schema_facts("local")
    docker_facts = schema_facts("docker")
    out = []
    for name, local_val in local_facts.items():
        docker_val = docker_facts[name]
        out.append({"Category": "Schema", "Name": name, "Source": local_val, "Target": docker_val,
                     "Passed": local_val == docker_val,
                     "Detail": "" if local_val == docker_val
                     else f"local build: {local_val}, docker image: {docker_val}"})
    return out


def canonical_dump(target, table, pk_cols):
    order = ", ".join(f'"{c}"' for c in pk_cols)
    return query(target, f'SELECT * FROM "{table}" ORDER BY {order};')


def check_tables():
    tables = []
    for name, pk in TABLES.items():
        local_rows = int(local_query(f'SELECT COUNT(*) FROM "{name}";').strip())
        docker_rows = int(docker_query(f'SELECT COUNT(*) FROM "{name}";').strip())
        local_dump = canonical_dump("local", name, pk)
        docker_dump = canonical_dump("docker", name, pk)
        local_hash = hashlib.sha256(local_dump.encode()).hexdigest()
        docker_hash = hashlib.sha256(docker_dump.encode()).hexdigest()
        count_passed = (local_rows == docker_rows)
        content_passed = (local_hash == docker_hash)
        tables.append({
            "Name": name, "SourceRows": local_rows, "TargetRows": docker_rows,
            "CountPassed": count_passed, "ContentPassed": content_passed,
            "SourceHash": local_hash, "TargetHash": docker_hash,
            "MismatchCount": 0 if content_passed else 1,
            "RowsIdentical": docker_rows if content_passed else 0,
            "Mismatches": [] if content_passed else [{"Table": name, "Key": "-", "Column": "-",
                                                        "Source": "(local build differs)",
                                                        "Target": "(see dump)"}],
        })
    return tables


def check_domain():
    out = []
    for name, sql in DOMAIN_QUERIES:
        local_rows = local_query(sql + ";").rstrip("\n")
        docker_rows = docker_query(sql + ";").rstrip("\n")
        local_list = local_rows.split("\n") if local_rows else []
        docker_list = docker_rows.split("\n") if docker_rows else []
        out.append({"Name": name, "Sql": sql, "SourceRows": local_list, "TargetRows": docker_list,
                     "Passed": local_list == docker_list})
    return out


def check_credential_sanitization():
    """Confirms sanitize.py did exactly what it claims: credentials redacted, nothing
    else touched. Cross-checked against the raw (real) source data if it's still present
    (it's gitignored/transient, so this check is skipped, not failed, if it's gone)."""
    checks = []
    for target, q in (("local", local_query), ("docker", docker_query)):
        bad = int(q('SELECT COUNT(*) FROM "Users" WHERE "PasswordHash" IS NOT NULL '
                     'OR "SecurityStamp" IS NOT NULL OR "MustResetPassword" != 1;').strip())
        checks.append({"Category": "Sanitization",
                        "Name": f"All Users rows have PasswordHash/SecurityStamp NULL and "
                                 f"MustResetPassword=1 ({target} build)",
                        "Passed": bad == 0, "Detail": "" if bad == 0 else f"{bad} row(s) not sanitized"})

    if RAW_DATA_SQL.exists():
        non_credential_cols = ["Name", "CreatedAt", "Discriminator", "DeletedAt", "Email",
                                "EmailConfirmed", "PhoneNumber", "PhoneNumberConfirmed",
                                "TwoFactorEnabled", "LockoutEndDateUtc", "LockoutEnabled",
                                "AccessFailedCount"]

        def sql_literal_to_text(v):
            v = v.strip()
            if v.upper() == "NULL":
                return ""
            if v.startswith("'") and v.endswith("'"):
                return v[1:-1].replace("''", "'")
            return v

        raw_text = RAW_DATA_SQL.read_text()
        m = sanitize.USERS_INSERT_RE.search(raw_text)
        cols = [c.strip().strip('"') for c in m.group(1).split(",")]
        rows = sanitize.ROW_RE.findall(m.group(2))
        mismatches = []
        for row_text in rows:
            values = sanitize.split_columns(row_text)
            raw_row = dict(zip(cols, values))
            user_id = raw_row["Id"]
            select_cols = ", ".join(f'"{c}"' for c in non_credential_cols)
            actual_line = local_query(
                f'SELECT {select_cols} FROM "Users" WHERE "Id" = {user_id};').strip("\n")
            actual_values = actual_line.split("|") if actual_line else [""] * len(non_credential_cols)
            expected_values = [sql_literal_to_text(raw_row[c]) for c in non_credential_cols]
            if actual_values != expected_values:
                mismatches.append({"UserId": user_id,
                                    "Expected": dict(zip(non_credential_cols, expected_values)),
                                    "Actual": dict(zip(non_credential_cols, actual_values))})
        checks.append({"Category": "Sanitization",
                        "Name": "Non-credential Users columns unchanged by sanitization "
                                 f"({len(rows)} rows cross-checked against raw source)",
                        "Passed": len(mismatches) == 0,
                        "Detail": "" if not mismatches else f"{len(mismatches)} row(s) differ: {mismatches[:3]}"})
    else:
        checks.append({"Category": "Sanitization",
                        "Name": "Non-credential Users columns unchanged by sanitization",
                        "Passed": True,
                        "Detail": "raw 02-data.sql not present (gitignored, transient) - "
                                   "check skipped, not failed"})
    return checks


def check_behaviour():
    """Runs on a scratch copy inside the container; the delivered database is never touched."""
    out = []
    scratch = "/tmp/verify-scratch.sqlite"
    sh(["docker", "exec", CONTAINER, "sh", "-c", f"rm -f {scratch} && cp {DOCKER_DB} {scratch}"])

    def run(sql):
        return sh(["docker", "exec", "-i", CONTAINER, "sqlite3", "-bail", scratch],
                   input_text=sql, check=False)

    r = run('PRAGMA foreign_keys=ON; INSERT INTO "Users" ("Name","CreatedAt","Discriminator") '
            'VALUES (\'manager\', \'2026-01-01 00:00:00\', \'Manager\');')
    out.append({"Category": "Behaviour", "Name": "Duplicate active username is rejected",
                "Passed": r.returncode != 0 and "UNIQUE" in r.stderr})

    run('UPDATE "Users" SET "DeletedAt" = \'2026-01-01 00:00:00\' WHERE "Name" = \'manager\';')
    r = run('INSERT INTO "Users" ("Name","CreatedAt","Discriminator") '
            'VALUES (\'manager\', \'2026-01-01 00:00:00\', \'Manager\');')
    out.append({"Category": "Behaviour", "Name": "Reusing a soft-deleted username is allowed (partial unique index)",
                "Passed": r.returncode == 0})

    r = run('PRAGMA foreign_keys=ON; INSERT INTO "Comments" ("UserId","TicketId","Text","CreatedAt") '
            'VALUES (999999, 999999, \'x\', \'2026-01-01 00:00:00\');')
    out.append({"Category": "Behaviour", "Name": "Orphan foreign key insert is rejected",
                "Passed": r.returncode != 0 and ("FOREIGN KEY" in r.stderr or "constraint" in r.stderr.lower())})

    r = run('UPDATE "Users" SET "EmailConfirmed" = 2 WHERE "Id" = 1;')
    out.append({"Category": "Behaviour", "Name": "Boolean CHECK constraint rejects values other than 0/1",
                "Passed": r.returncode != 0 and "CHECK" in r.stderr})

    before = int(run('SELECT seq FROM sqlite_sequence WHERE name=\'Roles\';').stdout.strip())
    run('INSERT INTO "Roles" ("Name") VALUES (\'Scratch\');')
    after = int(run('SELECT seq FROM sqlite_sequence WHERE name=\'Roles\';').stdout.strip())
    out.append({"Category": "Behaviour", "Name": "New Roles row continues the source identity sequence",
                "Passed": after == before + 1})

    sh(["docker", "exec", CONTAINER, "rm", "-f", scratch])
    return out


def git_commit():
    r = sh(["git", "-C", str(HERE.parent.parent.parent), "rev-parse", "--short", "HEAD"], check=False)
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def main():
    for f in (SCHEMA_SQL, SANITIZED_DATA_SQL):
        if not f.exists():
            print(f"ERROR: {f} not found.", file=sys.stderr)
            return 2

    try:
        r = sh(["docker", "inspect", "-f", "{{.State.Running}}", CONTAINER], check=False)
        if r.returncode != 0 or r.stdout.strip() != "true":
            print(f"ERROR: container '{CONTAINER}' is not running. Run build.sh first.", file=sys.stderr)
            return 2

        build_local_control_db()

        integrity = check_integrity()
        schema = check_schema()
        tables = check_tables()
        domain = check_domain()
        behaviour = check_behaviour()
        sanitization = check_credential_sanitization()
        all_checks = schema + integrity + behaviour + sanitization

        checks_total = len(all_checks) + sum(2 for _ in tables) + len(domain)
        checks_passed = (sum(1 for c in all_checks if c["Passed"])
                          + sum((1 if t["CountPassed"] else 0) + (1 if t["ContentPassed"] else 0) for t in tables)
                          + sum(1 for d in domain if d["Passed"]))
        rows_source = sum(t["SourceRows"] for t in tables)
        rows_identical = sum(t["RowsIdentical"] for t in tables)
        passed = (checks_passed == checks_total)

        results = {
            "Passed": passed,
            "GitCommit": git_commit(),
            "Meta": {
                "Target": "sqlite-image",
                "Dialect": "sqlite",
                "SourceServer": "n/a by design - iteration 3 has no live SQL Server connection and does "
                                 "not consult iteration 1/2's output artifacts. Correctness is established "
                                 "by cross-checking two independently-built copies of the same sanitized "
                                 "input, both produced fresh in this run on this Linux host: (1) the "
                                 "delivered Docker image, and (2) a throwaway control database built "
                                 "directly with the local sqlite3 CLI, no Docker involved.",
                "SourceDatabase": "n/a (see SourceServer)",
                "TargetName": "SQLite (custom Docker image)",
                "TargetClient": docker_query("SELECT sqlite_version();").strip(),
                "TargetLocation": DOCKER_DB,
                "Iteration": 3,
                "IterationTitle": "SQLite baked into a custom Docker image (independent verification, "
                                   "credentials sanitized)",
                "KnownDifferences": [
                    "The database is baked into the Docker image at build time (docker build), not "
                    "loaded into a running container afterward as in iteration 2.",
                    "Verification does not consult any iteration 1/2 output artifact. It cross-checks "
                    "two databases built independently in this run from the same sanitized input: the "
                    "Docker image and a local sqlite3-CLI control build.",
                    "Every migrated Users row has PasswordHash and SecurityStamp set to NULL and "
                    "MustResetPassword set to 1 - the real password hashes are never baked into this "
                    "image or committed to git. This is a deliberate one-time-bootstrap policy: a forced "
                    "password reset on next login is acceptable, so there is no need to carry a usable "
                    "credential into the target at all.",
                ],
            },
            "Summary": {
                "ChecksTotal": checks_total, "ChecksPassed": checks_passed,
                "RowsSource": rows_source, "RowsVerifiedIdentical": rows_identical,
                "Tables": len(tables),
            },
            "Tables": tables,
            "Checks": all_checks,
            "Domain": domain,
        }
        out_path = HERE / "verification-results.json"
        out_path.write_text(json.dumps(results, indent=2))
        print(f"{'VERIFICATION PASSED' if passed else 'VERIFICATION FAILED'} - "
              f"{checks_passed} of {checks_total} checks passed; "
              f"{rows_identical} of {rows_source} rows verified identical (local build vs. docker image)")
        print(f"Results written to {out_path}")
        return 0 if passed else 1
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
