#!/usr/bin/env python3
"""sanitize: the one-time bootstrap credential policy for this migration.

Legacy accounts are moving to a new system. Forcing every migrated account
through a password reset on next login is acceptable for this cutover, so
there is no need to carry a *usable* password hash into the target at all.
This script reads the raw exported data (real PBKDF2 hashes, transient input
only — never committed, see ../../../.gitignore-equivalent for this dir) and
writes 02-data-sanitized.sql: every Users row keeps every column except
PasswordHash and SecurityStamp, which are set to NULL, with MustResetPassword
set to 1 (see the matching column added to 01-schema.sql). That sanitized
file — never the raw one — is what gets baked into the Docker image and
committed to git.

Usage: sanitize.py [--raw 02-data.sql] [--out 02-data-sanitized.sql]
"""
import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Matches the whole "INSERT INTO "Users" (...) VALUES\n(...),\n(...),\n...;" statement.
USERS_INSERT_RE = re.compile(
    r'INSERT INTO "Users" \(([^)]*)\) VALUES\n(.*?);\n', re.DOTALL)
# Splits the VALUES clause into individual "(...)" row tuples, respecting quoted strings.
ROW_RE = re.compile(r"\(((?:[^()']|'(?:[^']|'')*')*)\)")


def split_columns(row_text):
    """Split one row's column values on top-level commas (ignoring commas inside quotes)."""
    cols, depth, cur, in_str = [], 0, "", False
    i = 0
    while i < len(row_text):
        c = row_text[i]
        if in_str:
            if c == "'" and row_text[i:i + 2] == "''":
                cur += "''"
                i += 2
                continue
            cur += c
            if c == "'":
                in_str = False
            i += 1
            continue
        if c == "'":
            in_str = True
            cur += c
        elif c == ",":
            cols.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    cols.append(cur)
    return [c.strip() for c in cols]


def sanitize_users_insert(match, col_names):
    cols = [c.strip().strip('"') for c in col_names.split(",")]
    pw_idx = cols.index("PasswordHash")
    stamp_idx = cols.index("SecurityStamp")

    body = match.group(2)
    rows = ROW_RE.findall(body)
    out_rows = []
    redacted = 0
    for row_text in rows:
        values = split_columns(row_text)
        if values[pw_idx].strip().upper() != "NULL":
            redacted += 1
        values[pw_idx] = "NULL"
        values[stamp_idx] = "NULL"
        out_rows.append("(" + ", ".join(values) + ")")

    new_cols = col_names.rstrip() + ', "MustResetPassword"'
    new_rows = [r[:-1] + ", 1)" for r in out_rows]
    stmt = f'INSERT INTO "Users" ({new_cols}) VALUES\n' + ",\n".join(new_rows) + ";\n"
    return stmt, redacted, len(rows)


def sanitize(raw_text):
    m = USERS_INSERT_RE.search(raw_text)
    if not m:
        raise RuntimeError("No Users INSERT statement found in the input data file.")
    stmt, redacted, total = sanitize_users_insert(m, m.group(1))
    out_text = raw_text[:m.start()] + stmt + raw_text[m.end():]
    return out_text, redacted, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(HERE / "02-data.sql"))
    ap.add_argument("--out", default=str(HERE / "02-data-sanitized.sql"))
    args = ap.parse_args()

    raw_path = Path(args.raw)
    if not raw_path.exists():
        print(f"ERROR: {raw_path} not found. Copy it from "
              f"tools/phase1/dbmigrate/iteration2/02-data.sql first (it is gitignored, "
              f"transient input only).", file=sys.stderr)
        return 2

    raw_text = raw_path.read_text()
    out_text, redacted, total = sanitize(raw_text)
    Path(args.out).write_text(out_text)
    print(f"Sanitized {redacted} of {total} Users rows "
          f"(PasswordHash/SecurityStamp -> NULL, MustResetPassword -> 1)")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
