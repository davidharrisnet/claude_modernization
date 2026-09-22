#!/usr/bin/env bash
# selftest: proves the tooling itself is trustworthy. Exit codes: 0 ok, 1 a test failed, 2 error.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec python3 selftest.py
