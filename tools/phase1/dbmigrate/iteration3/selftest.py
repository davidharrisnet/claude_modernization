#!/usr/bin/env python3
"""selftest: proves the iteration 3 tooling itself is trustworthy, same 3-part shape as
iterations 1/2's SelfTest.ps1:
  1. Determinism - building the image a second time (fresh tag) yields an identical dump.
  2. Independent  - a scratch copy loaded separately inside the container matches the
                     delivered database by dump diff.
  3. Negative test - a deliberately damaged copy is caught, naming the table and row.
Writes tools/phase1/dbmigrate/iteration3/selftest-results.json. Exit: 0 all passed, 1 a test failed, 2 error.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTAINER = "mar-sqlite-iter3"
DB = "/data/masterantique.sqlite"
TEMP_TAG = "masterantique-sqlite:iteration3-selftest"
TEMP_CONTAINER = "mar-sqlite-iter3-selftest"


def sh(cmd, check=True, input_text=None):
    r = subprocess.run(cmd, capture_output=True, text=True, input=input_text)
    if check and r.returncode != 0:
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(cmd)}\n{r.stderr}")
    return r


def dump(container, db=DB):
    return sh(["docker", "exec", container, "sqlite3", db, ".dump"]).stdout


def main():
    tests = []
    try:
        # 1. determinism: build again under a throwaway tag/container
        sh(["docker", "rm", "-f", TEMP_CONTAINER], check=False)
        sh(["docker", "rmi", "-f", TEMP_TAG], check=False)
        sh(["docker", "build", "-t", TEMP_TAG, str(HERE)])
        sh(["docker", "run", "-d", "--name", TEMP_CONTAINER, TEMP_TAG])
        try:
            dump_a = dump(CONTAINER)
            dump_b = dump(TEMP_CONTAINER)
            tests.append({"Category": "Determinism", "Name": "Second build is byte-identical to the first",
                           "Passed": dump_a == dump_b})
        finally:
            sh(["docker", "rm", "-f", TEMP_CONTAINER], check=False)
            sh(["docker", "rmi", "-f", TEMP_TAG], check=False)

        # 2. independent: a scratch copy inside the container matches the delivered database
        scratch = "/tmp/selftest-scratch.sqlite"
        sh(["docker", "exec", CONTAINER, "cp", DB, scratch])
        dump_scratch = dump(CONTAINER, scratch)
        dump_live = dump(CONTAINER, DB)
        tests.append({"Category": "Independent", "Name": "Scratch copy matches the delivered database (dump diff)",
                       "Passed": dump_scratch == dump_live})
        sh(["docker", "exec", CONTAINER, "rm", "-f", scratch])

        # 3. negative test: damage a copy, confirm the difference is caught and named
        damaged = "/tmp/selftest-damaged.sqlite"
        sh(["docker", "exec", CONTAINER, "cp", DB, damaged])
        sh(["docker", "exec", "-i", CONTAINER, "sqlite3", damaged],
           input_text='UPDATE "Comments" SET "Text" = \'DAMAGED\' WHERE "Id" = 1;'
                      'DELETE FROM "Tickets" WHERE "Id" = 1;')
        dump_damaged = dump(CONTAINER, damaged)
        caught = dump_damaged != dump_live and "DAMAGED" in dump_damaged
        tests.append({"Category": "Negative test",
                       "Name": "A damaged copy (Comments.Id=1 text changed, Tickets.Id=1 deleted) is detected",
                       "Passed": caught,
                       "Detail": "dump differs and contains the injected 'DAMAGED' marker" if caught else "not detected"})
        sh(["docker", "exec", CONTAINER, "rm", "-f", damaged])

        passed = all(t["Passed"] for t in tests)
        results = {"Passed": passed, "Tests": tests}
        (HERE / "selftest-results.json").write_text(json.dumps(results, indent=2))
        print(f"{'SELF-TEST PASSED' if passed else 'SELF-TEST FAILED'} - "
              f"{sum(1 for t in tests if t['Passed'])} of {len(tests)} passed")
        return 0 if passed else 1
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
