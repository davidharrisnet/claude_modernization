#!/usr/bin/env bash
# verify: run verify.py against the running container. Exit codes: 0 ok, 1 differences, 2 error.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec python3 verify.py
