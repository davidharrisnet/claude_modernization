#!/usr/bin/env bash
# Iteration 5: load iteration 4's PostgreSQL export into a PostgreSQL Docker container and verify it against
# source-metadata.json. bash + Docker only: psql runs inside the container; no host psql, Python, Java or jq.
# Plan: ../../../docs/dbmigrate/iteration5/ITERATION5_PLAN.md
#
# Usage: ingest.sh <load|verify|selftest|report|all> [--recreate] [--config <path>] [--db <name>] [--out <path>]
# Exit codes: 0 ok | 1 verification or self-test differences | 2 configuration, tool or Docker error | 3 refused
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
REPORT_DIR="$REPO_ROOT/docs/dbmigrate/iteration5"
REPORT_FILE="$REPORT_DIR/MigrationVerificationReport5.html"
RESULTS_FILE="$HERE/verification-results.json"
SELFTEST_FILE="$HERE/selftest-results.json"

usage() {
  cat <<'EOF'
Usage: ingest.sh <command> [options]

Commands:
  load      start the PostgreSQL container and load 01-schema.sql and 02-data-sanitized.sql into it
  verify    check the loaded database against source-metadata.json; writes verification-results.json
  selftest  prove the tooling on a separate, temporary container (the delivered database is never touched)
  report    build docs/dbmigrate/iteration5/MigrationVerificationReport5.html from the results JSON
  all       load, verify, selftest, report

Options:
  --recreate       (load, all) delete the existing container and its database first
  --config <path>  settings file (default: ingest.conf next to this script, if present; else built-in defaults)
  --db <name>      (verify) database to verify, default PG_DATABASE
  --out <path>     (verify) where to write the results JSON, default verification-results.json

Exit codes: 0 ok | 1 verification or self-test differences | 2 configuration, tool or Docker error | 3 refused
EOF
}

die() { local code="$1"; shift; echo "ERROR: $*" >&2; exit "$code"; }
info() { echo "== $*"; }

# ---------------------------------------------------------------- arguments and settings
CMD="${1:-}"
[ -n "$CMD" ] && shift
RECREATE=0
CONFIG=""
VERIFY_DB=""
VERIFY_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recreate) RECREATE=1 ;;
    --config) [ $# -ge 2 ] || die 2 "--config needs a path"; CONFIG="$2"; shift ;;
    --db) [ $# -ge 2 ] || die 2 "--db needs a name"; VERIFY_DB="$2"; shift ;;
    --out) [ $# -ge 2 ] || die 2 "--out needs a path"; VERIFY_OUT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 2 "unknown option: $1" ;;
  esac
  shift
done

CONTAINER=mar-postgres
PG_IMAGE=postgres:16.1
PG_DATABASE=masterantique
PG_USER=masterantique
PG_SCHEMA=public
INPUT_DIR=input
if [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || die 2 "config file not found: $CONFIG"
  # shellcheck disable=SC1090
  . "$CONFIG"
elif [ -f "$HERE/ingest.conf" ]; then
  # shellcheck disable=SC1091
  . "$HERE/ingest.conf"
fi
case "$INPUT_DIR" in /*) ;; *) INPUT_DIR="$HERE/$INPUT_DIR" ;; esac
SCHEMA_SQL="$INPUT_DIR/01-schema.sql"
DATA_SQL="$INPUT_DIR/02-data-sanitized.sql"
META_JSON="$INPUT_DIR/source-metadata.json"
for v in CONTAINER PG_IMAGE PG_DATABASE PG_USER PG_SCHEMA; do
  [[ "${!v}" =~ ^[A-Za-z0-9_.:/-]+$ ]] || die 2 "setting $v has an unexpected value: '${!v}'"
done

# ---------------------------------------------------------------- helpers
require_docker() {
  command -v docker >/dev/null 2>&1 || die 2 "docker is not installed or not on PATH"
  docker info >/dev/null 2>&1 || die 2 "Docker is not running or not reachable (docker info failed)"
}

container_exists() { docker container inspect "$CONTAINER" >/dev/null 2>&1; }
container_running() { [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; }

# psql inside the container, over the local socket (no password needed there). Extra arguments are passed to psql.
psql_in() {
  local db="$1"; shift
  docker exec -i -e PGOPTIONS="-c search_path=$PG_SCHEMA" "$CONTAINER" \
    psql -X -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$db" "$@"
}

# Expected SHA-256 recorded in the metadata for a key (schemaSha256 / dataSha256), read with grep so no jq is needed.
meta_sha() {
  grep -o "\"$1\": *\"[0-9a-f]\{64\}\"" "$META_JSON" | head -n 1 | grep -o '[0-9a-f]\{64\}'
}

file_sha() { sha256sum "$1" | cut -d' ' -f1; }

require_inputs() {
  local f
  for f in "$SCHEMA_SQL" "$DATA_SQL" "$META_JSON"; do
    [ -f "$f" ] || die 2 "input file missing: $f"
  done
}

# Transfer integrity: the two SQL files must be exactly the ones the metadata was recorded for.
check_integrity() {
  local key file expected actual
  for pair in "schemaSha256:$SCHEMA_SQL" "dataSha256:$DATA_SQL"; do
    key="${pair%%:*}"; file="${pair#*:}"
    expected="$(meta_sha "$key")"
    [ -n "$expected" ] || die 2 "source-metadata.json has no $key"
    actual="$(file_sha "$file")"
    if [ "$actual" != "$expected" ]; then
      die 2 "transfer integrity check failed: $(basename "$file") has SHA-256 $actual, the metadata expects $expected"
    fi
    echo "   integrity ok: $(basename "$file") $actual"
  done
}

tool_commit() { git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo unknown; }

# ---------------------------------------------------------------- load
wait_ready() {
  local i ok=0
  for i in $(seq 1 120); do
    if ! container_running; then
      docker logs --tail 30 "$CONTAINER" >&2 2>&1
      die 2 "container $CONTAINER stopped during start-up (log above)"
    fi
    # The official image starts a temporary server for first-time initialisation, then restarts. Only after the
    # "init process complete" line is the real server the one answering.
    if docker logs "$CONTAINER" 2>&1 | grep -q 'PostgreSQL init process complete' &&
       psql_in "$PG_DATABASE" -Atqc 'select 1' >/dev/null 2>&1; then
      ok=$((ok + 1))
      [ "$ok" -ge 2 ] && return 0
    else
      ok=0
    fi
    sleep 1
  done
  die 2 "PostgreSQL in $CONTAINER did not become ready within 120 seconds"
}

cmd_load() {
  require_docker
  require_inputs
  info "Checking the input files against the metadata (transfer integrity)"
  check_integrity

  if container_exists; then
    if [ "$RECREATE" -ne 1 ]; then
      echo "REFUSED: container $CONTAINER already exists (with its database). Use --recreate to delete it and load again." >&2
      exit 3
    fi
    info "Deleting the existing container $CONTAINER and its storage (--recreate)"
    docker rm -f -v "$CONTAINER" >/dev/null || die 2 "could not remove container $CONTAINER"
  fi

  if ! docker image inspect "$PG_IMAGE" >/dev/null 2>&1; then
    info "Pulling $PG_IMAGE"
    docker pull "$PG_IMAGE" || die 2 "could not pull image $PG_IMAGE"
  fi

  info "Starting container $CONTAINER from $PG_IMAGE (no published port)"
  # The password is random, handed over as a file (so it is not in the container's environment or `docker inspect`),
  # deleted once the server is up, and never printed or stored.
  local tmp; tmp="$(mktemp -d)"; chmod 700 "$tmp"
  head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > "$tmp/pw"
  chmod 644 "$tmp/pw"
  docker create --name "$CONTAINER" \
    -e POSTGRES_DB="$PG_DATABASE" -e POSTGRES_USER="$PG_USER" -e POSTGRES_PASSWORD_FILE=/tmp/.pgpw \
    "$PG_IMAGE" >/dev/null || { rm -rf "$tmp"; die 2 "could not create container $CONTAINER"; }
  docker cp -q "$tmp/pw" "$CONTAINER:/tmp/.pgpw" >/dev/null || { rm -rf "$tmp"; die 2 "could not copy the password file"; }
  rm -rf "$tmp"
  docker start "$CONTAINER" >/dev/null || die 2 "could not start container $CONTAINER"
  wait_ready
  docker exec "$CONTAINER" rm -f /tmp/.pgpw

  local ver enc
  ver="$(psql_in "$PG_DATABASE" -Atqc 'show server_version_num')" || die 2 "could not read the server version"
  enc="$(psql_in "$PG_DATABASE" -Atqc 'show server_encoding')" || die 2 "could not read the server encoding"
  [ "$ver" -ge 150000 ] || die 2 "PostgreSQL server version $ver is older than 15"
  [ "$enc" = "UTF8" ] || die 2 "server encoding is $enc, not UTF8"
  info "Server ready: version_num $ver, encoding $enc"

  if [ "$PG_SCHEMA" != "public" ]; then
    psql_in "$PG_DATABASE" -qc "CREATE SCHEMA IF NOT EXISTS \"$PG_SCHEMA\"" || die 2 "could not create schema $PG_SCHEMA"
  fi

  info "Copying the input files into the container"
  docker cp -q "$SCHEMA_SQL" "$CONTAINER:/tmp/01-schema.sql" &&
    docker cp -q "$DATA_SQL" "$CONTAINER:/tmp/02-data-sanitized.sql" &&
    docker cp -q "$META_JSON" "$CONTAINER:/tmp/source-metadata.json" || die 2 "could not copy the input files into $CONTAINER"

  info "Loading 01-schema.sql, then 02-data-sanitized.sql (stops at the first error)"
  if ! psql_in "$PG_DATABASE" -q -f /tmp/01-schema.sql -f /tmp/02-data-sanitized.sql >/dev/null; then
    die 2 "the load failed (psql error above); the container is left for inspection, reload with --recreate"
  fi

  info "Rows loaded"
  psql_in "$PG_DATABASE" -Atq -F ' ' -c "
    select c.relname, (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %I', c.relname), false, true, '')))[1]::text
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
    where s.nspname = current_schema() and c.relkind = 'r' order by c.oid" |
    awk '{ t += $2; printf "   %-14s %5d\n", $1, $2 } END { printf "   %-14s %5d\n", "total", t }'
  echo "LOAD COMPLETE: database $PG_DATABASE in container $CONTAINER"
}

# ---------------------------------------------------------------- verify
cmd_verify() {
  local db="${VERIFY_DB:-$PG_DATABASE}" out="${VERIFY_OUT:-$RESULTS_FILE}"
  require_docker
  require_inputs
  container_running || die 2 "container $CONTAINER is not running; run 'ingest.sh load' first"
  [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || die 2 "unexpected database name: $db"

  docker cp -q "$META_JSON" "$CONTAINER:/tmp/source-metadata.json" &&
    docker cp -q "$HERE/verify.sql" "$CONTAINER:/tmp/verify.sql" || die 2 "could not copy verify.sql and the metadata into $CONTAINER"
  # psql cannot overwrite a file in /tmp that another user owns (the kernel's protected_regular rule), so start clean.
  docker exec "$CONTAINER" rm -f /tmp/verification-results.json

  local lines rc
  lines="$(psql_in "$db" -q -A -t \
    -v schema_sha="$(file_sha "$SCHEMA_SQL")" -v data_sha="$(file_sha "$DATA_SQL")" \
    -v run_time="$(date -u '+%Y-%m-%d %H:%M:%S')" -v tool_commit="$(tool_commit)" \
    -v image="$PG_IMAGE" -v container="$CONTAINER" -v outfile=/tmp/verification-results.json \
    -f /tmp/verify.sql)"
  rc=$?
  [ "$rc" -eq 0 ] || die 2 "verify.sql failed to run (psql exit $rc)"
  docker cp -q "$CONTAINER:/tmp/verification-results.json" "$out" || die 2 "could not copy the results out of $CONTAINER"

  local summary fails
  summary="$(printf '%s\n' "$lines" | grep '^SUMMARY')"
  printf '%s\n' "$lines" | grep -v '^SUMMARY' | awk -F'\t' '{ printf "%-4s  %-13s %s -- %s\n", $1, $2, $3, $4 }'
  fails="$(printf '%s\n' "$lines" | grep -c '^FAIL')"
  IFS=$'\t' read -r _ passed total rows_ok rows_total <<<"$summary"
  echo "Results written to $out"
  if [ "$fails" -eq 0 ]; then
    echo "VERIFICATION PASSED - $passed of $total checks; $rows_ok of $rows_total rows verified identical (database $db)"
    return 0
  fi
  echo "VERIFICATION FAILED - $fails of $total checks failed; $rows_ok of $rows_total rows verified identical (database $db)"
  return 1
}

# ---------------------------------------------------------------- selftest
json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

cmd_selftest() {
  require_docker
  require_inputs
  container_running || die 2 "container $CONTAINER is not running; run 'ingest.sh load' first (the self-test compares against it)"

  local self="$HERE/ingest.sh" st_container="${CONTAINER}-selftest" work
  work="$(mktemp -d)"
  # A settings file for the temporary self-test container; everything else as configured.
  cat >"$work/selftest.conf" <<EOF
CONTAINER=$st_container
PG_IMAGE=$PG_IMAGE
PG_DATABASE=$PG_DATABASE
PG_USER=$PG_USER
PG_SCHEMA=$PG_SCHEMA
INPUT_DIR=$INPUT_DIR
EOF
  local names=() statuses=() details=()
  record() {
    names+=("$1"); statuses+=("$2"); details+=("$3")
    printf '%-4s  %s -- %s\n' "$2" "$1" "$3"
  }
  st() { "$self" "$@" --config "$work/selftest.conf"; }
  checklines() { grep -E '^(PASS|FAIL)  ' "$1"; }

  info "Self-test 1: two loads from scratch give identical verification results (container $st_container)"
  local rc1 rc2 rcm
  st load --recreate >"$work/load1.txt" 2>&1 && st verify --out "$work/a.json" >"$work/a.txt" 2>&1; rc1=$?
  st load --recreate >"$work/load2.txt" 2>&1 && st verify --out "$work/b.json" >"$work/b.txt" 2>&1; rc2=$?
  sed "s|^CONTAINER=.*|CONTAINER=$CONTAINER|" "$work/selftest.conf" >"$work/main.conf"
  "$self" verify --config "$work/main.conf" --out "$work/main.json" >"$work/main.txt" 2>&1; rcm=$?
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] &&
     diff <(checklines "$work/a.txt") <(checklines "$work/b.txt") >/dev/null &&
     diff <(grep -v '"runTimeUtc"' "$work/a.json") <(grep -v '"runTimeUtc"' "$work/b.json") >/dev/null; then
    record "Repeatable load" PASS "two fresh loads both pass verification; check output and results JSON identical (apart from the run time)"
  else
    record "Repeatable load" FAIL "load/verify exit codes $rc1 and $rc2, or the two results differ (see $work)"
  fi
  if [ "$rcm" -eq 0 ] && diff <(checklines "$work/a.txt") <(checklines "$work/main.txt") >/dev/null; then
    record "Delivered database matches a fresh load" PASS "$CONTAINER gives the same check results as the fresh self-test load"
  else
    record "Delivered database matches a fresh load" FAIL "verify of $CONTAINER exit $rcm, or its results differ from the fresh load"
  fi

  info "Self-test 2: a damaged copy of the database is caught and the damaged tables are named"
  local dmg="ingest_selftest_damaged" rcd
  CONTAINER="$st_container" psql_in "$PG_DATABASE" -q \
    -c "CREATE DATABASE $dmg TEMPLATE $PG_DATABASE" >/dev/null 2>&1
  CONTAINER="$st_container" psql_in "$dmg" -q \
    -c "UPDATE comments SET text = text || '.' WHERE id = (SELECT min(id) FROM comments)" \
    -c "DELETE FROM tickets WHERE id = (SELECT max(id) FROM tickets)" \
    -c "DROP INDEX ix_users_name_active" >/dev/null 2>&1
  st verify --db "$dmg" --out "$work/damaged.json" >"$work/damaged.txt" 2>&1; rcd=$?
  CONTAINER="$st_container" psql_in "$PG_DATABASE" -q -c "DROP DATABASE IF EXISTS $dmg" >/dev/null 2>&1
  if [ "$rcd" -eq 1 ] &&
     grep -q '^FAIL  hashes .*tickets' "$work/damaged.txt" &&
     grep -q '^FAIL  hashes .*comments' "$work/damaged.txt" &&
     grep -q '^FAIL  counts .*tickets' "$work/damaged.txt" &&
     grep -q '^FAIL  schema .*users indexes' "$work/damaged.txt" &&
     grep -q '^FAIL  rules .*differing only by case' "$work/damaged.txt" &&
     ! grep -q '^FAIL  hashes .*\(roles\|users\|audit_logs\|user_roles\)' "$work/damaged.txt"; then
    record "Damaged copy detected" PASS "one comment edited, one ticket deleted, the username index dropped: verify exits 1 and names tickets (count, hash), comments (hash), the users index and the case rule; untouched tables still pass"
  else
    record "Damaged copy detected" FAIL "verify exit $rcd, or the damaged tables were not named (see $work/damaged.txt)"
  fi

  info "Self-test 3: a changed table hash in the metadata is caught and the table is named"
  mkdir -p "$work/tampered"
  cp "$SCHEMA_SQL" "$DATA_SQL" "$work/tampered/"
  # Replace the first rowSha256 (the first table in load order, roles) with zeros.
  sed '0,/"rowSha256": *"[0-9a-f]\{64\}"/s//"rowSha256":  "0000000000000000000000000000000000000000000000000000000000000000"/' \
    "$META_JSON" >"$work/tampered/source-metadata.json"
  sed "s|^INPUT_DIR=.*|INPUT_DIR=$work/tampered|" "$work/selftest.conf" >"$work/tampered.conf"
  local rct
  "$self" verify --config "$work/tampered.conf" --out "$work/tampered.json" >"$work/tampered.txt" 2>&1; rct=$?
  if [ "$rct" -eq 1 ] && grep -q '^FAIL  hashes .*roles' "$work/tampered.txt" &&
     [ "$(grep -c '^FAIL' "$work/tampered.txt")" -eq 1 ]; then
    record "Tampered metadata hash detected" PASS "roles hash zeroed in a copy of the metadata: verify exits 1 with exactly one failure, naming roles"
  else
    record "Tampered metadata hash detected" FAIL "verify exit $rct, or the failure did not name roles alone (see $work/tampered.txt)"
  fi

  info "Self-test 4: a changed byte in the data file is refused before anything is loaded"
  mkdir -p "$work/corrupt"
  cp "$SCHEMA_SQL" "$META_JSON" "$work/corrupt/"
  sed '0,/Customer/s//Customes/' "$DATA_SQL" >"$work/corrupt/02-data-sanitized.sql"
  sed -e "s|^INPUT_DIR=.*|INPUT_DIR=$work/corrupt|" -e "s|^CONTAINER=.*|CONTAINER=${CONTAINER}-selftest-unused|" \
    "$work/selftest.conf" >"$work/corrupt.conf"
  local rcc
  "$self" load --config "$work/corrupt.conf" >"$work/corrupt.txt" 2>&1; rcc=$?
  if [ "$rcc" -eq 2 ] && grep -q 'transfer integrity check failed' "$work/corrupt.txt" &&
     ! docker container inspect "${CONTAINER}-selftest-unused" >/dev/null 2>&1; then
    record "Corrupted input refused" PASS "one byte changed in 02-data-sanitized.sql: load exits 2 on the integrity check and creates no container"
  else
    record "Corrupted input refused" FAIL "load exit $rcc, or no integrity message, or a container was created (see $work/corrupt.txt)"
  fi

  info "Self-test 5: loading over an existing database without --recreate is refused"
  local rcr
  st load >"$work/refused.txt" 2>&1; rcr=$?
  if [ "$rcr" -eq 3 ]; then
    record "Existing database protected" PASS "load without --recreate on an existing container exits 3 and changes nothing"
  else
    record "Existing database protected" FAIL "load exit $rcr, expected 3"
  fi

  info "Self-test 6: Docker unavailable is reported clearly"
  local rcx
  DOCKER_HOST=unix:///nonexistent/docker.sock "$self" verify --config "$work/selftest.conf" >"$work/nodocker.txt" 2>&1; rcx=$?
  if [ "$rcx" -eq 2 ] && grep -q 'Docker is not running' "$work/nodocker.txt"; then
    record "Docker unavailable reported" PASS "with Docker unreachable, the tool exits 2 with a clear message"
  else
    record "Docker unavailable reported" FAIL "exit $rcx, expected 2 with a clear message"
  fi

  docker rm -f -v "$st_container" >/dev/null 2>&1

  local i n="${#names[@]}" passed=0 status
  for ((i = 0; i < n; i++)); do [ "${statuses[$i]}" = PASS ] && passed=$((passed + 1)); done
  status=FAIL; [ "$passed" -eq "$n" ] && status=PASS
  {
    printf '{\n  "iteration": 5,\n  "status": "%s",\n  "passed": %d,\n  "total": %d,\n  "tests": [\n' "$status" "$passed" "$n"
    for ((i = 0; i < n; i++)); do
      printf '    { "name": %s, "status": "%s", "detail": %s }%s\n' \
        "$(json_str "${names[$i]}")" "${statuses[$i]}" "$(json_str "${details[$i]}")" "$([ $i -lt $((n - 1)) ] && echo ,)"
    done
    printf '  ]\n}\n'
  } >"$SELFTEST_FILE"
  echo "Results written to $SELFTEST_FILE"
  if [ "$status" = PASS ]; then
    rm -rf "$work"
    echo "SELFTEST PASSED - $passed of $n"
    return 0
  fi
  echo "SELFTEST FAILED - $passed of $n passed (working files kept in $work)"
  return 1
}

# ---------------------------------------------------------------- report
cmd_report() {
  require_docker
  [ -f "$RESULTS_FILE" ] || die 2 "no $RESULTS_FILE; run 'ingest.sh verify' first"
  container_running || die 2 "container $CONTAINER is not running (the report is rendered by psql inside it)"
  mkdir -p "$REPORT_DIR"
  # Own file names, so the report never leaves behind a file that verify must later overwrite.
  docker exec "$CONTAINER" rm -f /tmp/report-results.json /tmp/report-selftest.json /tmp/report.html
  docker cp -q "$RESULTS_FILE" "$CONTAINER:/tmp/report-results.json" &&
    docker cp -q "$HERE/report.sql" "$CONTAINER:/tmp/report.sql" || die 2 "could not copy the report inputs into $CONTAINER"
  if [ -f "$SELFTEST_FILE" ]; then
    docker cp -q "$SELFTEST_FILE" "$CONTAINER:/tmp/report-selftest.json" || die 2 "could not copy the self-test results"
  else
    printf 'null\n' | docker exec -i "$CONTAINER" sh -c 'cat > /tmp/report-selftest.json'
  fi
  # Rendered in the default 'postgres' database: the report reads only the two JSON files, never the migrated data.
  psql_in postgres -q -A -t -f /tmp/report.sql >/dev/null || die 2 "report.sql failed"
  docker cp -q "$CONTAINER:/tmp/report.html" "$REPORT_FILE" || die 2 "could not copy the report out of $CONTAINER"
  echo "REPORT WRITTEN: $REPORT_FILE"
}

# ---------------------------------------------------------------- main
case "$CMD" in
  load) cmd_load ;;
  verify) cmd_verify ;;
  selftest) cmd_selftest ;;
  report) cmd_report ;;
  all)
    cmd_load
    v=0; s=0
    cmd_verify || v=$?
    ( cmd_selftest ) || s=$?
    cmd_report
    if [ "$v" -ge 2 ] || [ "$s" -ge 2 ]; then exit 2; fi
    if [ "$v" -ne 0 ] || [ "$s" -ne 0 ]; then exit 1; fi
    exit 0
    ;;
  ""|-h|--help|help) usage; [ -n "$CMD" ] || exit 2 ;;
  *) usage >&2; die 2 "unknown command: $CMD" ;;
esac
