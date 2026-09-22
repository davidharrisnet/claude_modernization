#!/usr/bin/env bash
# Iteration 3 wrapper: dbmigrate3.sh <build|verify|selftest|all> [--recreate]
# Native Linux tooling (bash/python3/sqlite3/docker), no PowerShell. See ../../../docs/dbmigrate/iteration3/.
# Exit codes: 0 ok, 1 verify/selftest differences, 2 config/tool error, 3 refused.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
Usage: dbmigrate3.sh <command> [options]

Commands:
  build     docker build the image with 01-schema.sql/02-data.sql baked in, start the container
  verify    check the built database against iteration 2's verified results + the iteration 1 reference file
  selftest  prove the tooling: repeatable build, an independent scratch copy, a damaged copy must be caught
  all       build, verify, selftest

Options:
  --recreate   (build only) replace an existing container/image

Exit codes: 0 ok | 1 verify/selftest differences | 2 config/tool error | 3 refused
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
  build) ./build.sh "$@" ;;
  verify) ./verify.sh ;;
  selftest) ./selftest.sh ;;
  all)
    ./build.sh "$@"
    v=0; s=0
    ./verify.sh || v=$?
    ./selftest.sh || s=$?
    if [ "$v" -ge 2 ] || [ "$s" -ge 2 ]; then exit 2; fi
    if [ "$v" -ne 0 ] || [ "$s" -ne 0 ]; then exit 1; fi
    exit 0
    ;;
  ""|help|--help|-h) usage; exit 0 ;;
  *) echo "ERROR: unknown command '$cmd'. Run 'dbmigrate3.sh --help'." >&2; exit 2 ;;
esac
