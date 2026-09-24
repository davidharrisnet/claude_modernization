#!/usr/bin/env bash
# import-oracle: load the Oracle export from export-oracle into an Oracle AI Database 26ai Free Docker container and verify it
# against source-metadata.json. bash + Docker only: sqlplus runs inside the container; no host Oracle client, Python, Java or jq.
# Instructions: CLAUDE.md in this folder. Description: ../../../../docs/phase1/dbmigrate/import-oracle/README.md
#
# Usage: ingest.sh <load|verify|selftest|report|all> [--recreate] [--config <path>] [--schema <name>] [--out <path>]
# Exit codes: 0 ok | 1 verification or self-test differences | 2 configuration, tool or Docker error | 3 refused
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
REPORT_DIR="$REPO_ROOT/docs/phase1/dbmigrate/import-oracle"
REPORT_FILE="$REPORT_DIR/MigrationVerificationReport.html"
RESULTS_FILE="$HERE/verification-results.json"
SELFTEST_FILE="$HERE/selftest-results.json"

usage() {
  cat <<'EOF'
Usage: ingest.sh <command> [options]

Commands:
  load      start the Oracle container and load 01-schema.sql and 02-data-sanitized.sql into it
  verify    check the loaded schema against source-metadata.json; writes verification-results.json
  selftest  prove the tooling on a separate, temporary container (the delivered database is never touched)
  report    build docs/phase1/dbmigrate/import-oracle/MigrationVerificationReport.html from the results JSON
  all       load, verify, selftest, report

Options:
  --recreate        (load, all) delete the existing container and its database first
  --config <path>   settings file (default: ingest.conf next to this script, if present; else built-in defaults)
  --schema <name>   (verify) schema to verify, default ORA_USER
  --out <path>      (verify) where to write the results JSON, default verification-results.json

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
VERIFY_SCHEMA=""
VERIFY_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recreate) RECREATE=1 ;;
    --config) [ $# -ge 2 ] || die 2 "--config needs a path"; CONFIG="$2"; shift ;;
    --schema) [ $# -ge 2 ] || die 2 "--schema needs a name"; VERIFY_SCHEMA="$2"; shift ;;
    --out) [ $# -ge 2 ] || die 2 "--out needs a path"; VERIFY_OUT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 2 "unknown option: $1" ;;
  esac
  shift
done

CONTAINER=mar-oracle
ORA_IMAGE=gvenzl/oracle-free:23.26.3-faststart
ORA_PDB=FREEPDB1
ORA_USER=masterantique
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
for v in CONTAINER ORA_IMAGE ORA_PDB ORA_USER; do
  [[ "${!v}" =~ ^[A-Za-z0-9_.:/-]+$ ]] || die 2 "setting $v has an unexpected value: '${!v}'"
done
# The pluggable database and the schema go into SQL text: plain identifiers only.
for v in ORA_PDB ORA_USER; do
  [[ "${!v}" =~ ^[A-Za-z][A-Za-z0-9_]{0,29}$ ]] || die 2 "setting $v must be a plain identifier: '${!v}'"
done

# ---------------------------------------------------------------- helpers
require_docker() {
  command -v docker >/dev/null 2>&1 || die 2 "docker is not installed or not on PATH"
  docker info >/dev/null 2>&1 || die 2 "Docker is not running or not reachable (docker info failed)"
}

container_exists() { docker container inspect "$CONTAINER" >/dev/null 2>&1; }
container_running() { [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; }

# sqlplus inside the container as SYS through operating-system authentication (the oracle user is in the dba group), so no
# password is needed or known. The script comes on stdin. -L: never prompt for a login if that fails.
sql_in() {
  docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$CONTAINER" sqlplus -S -L / as sysdba
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

# A random password that is used once and never stored or printed.
random_pw() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 30; }

# ---------------------------------------------------------------- load
wait_ready() {
  local i ok=0
  for i in $(seq 1 300); do
    if ! container_running; then
      docker logs --tail 30 "$CONTAINER" >&2 2>&1
      die 2 "container $CONTAINER stopped during start-up (log above)"
    fi
    # The entrypoint prints this line once the database is open and the SYS/SYSTEM passwords are set; a query must then
    # succeed twice in a row in the pluggable database, not just once.
    if docker logs "$CONTAINER" 2>&1 | grep -q 'DATABASE IS READY TO USE!' &&
       printf 'WHENEVER SQLERROR EXIT FAILURE\nALTER SESSION SET CONTAINER = %s;\nSELECT 1 FROM dual;\nEXIT\n' "$ORA_PDB" |
         sql_in >/dev/null 2>&1; then
      ok=$((ok + 1))
      [ "$ok" -ge 2 ] && return 0
    else
      ok=0
    fi
    sleep 1
  done
  die 2 "Oracle in $CONTAINER did not become ready within 300 seconds"
}

# Create a schema-only account (NO AUTHENTICATION: nobody can log in as it) and run the two scripts in it as SYS with
# CURRENT_SCHEMA set, so unqualified CREATE TABLE / CREATE INDEX / INSERT land in that schema. Used by load and by the self-test.
load_schema() {
  local schema="$1" out rc
  out="$(sql_in 2>&1 <<EOF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
ALTER SESSION SET CONTAINER = $ORA_PDB;
CREATE USER $schema NO AUTHENTICATION DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
ALTER SESSION SET CURRENT_SCHEMA = $schema;
@/tmp/marload/01-schema.sql
@/tmp/marload/02-data-sanitized.sql
EXIT SUCCESS
EOF
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" | grep -v -E '^(Table|Index|Session|User) (created|altered)\.$|^[0-9]+ rows? created\.$|^Commit complete\.$|^$' | tail -n 25 >&2
    return 2
  fi
}

copy_load_inputs() {
  docker exec "$CONTAINER" mkdir -p /tmp/marload &&
    docker cp -q "$SCHEMA_SQL" "$CONTAINER:/tmp/marload/01-schema.sql" &&
    docker cp -q "$DATA_SQL" "$CONTAINER:/tmp/marload/02-data-sanitized.sql"
}

row_counts() {
  local schema="$1"
  sql_in <<EOF | awk -F'\t' 'NF == 2 { t += $2; printf "   %-14s %5d\n", $1, $2 } END { printf "   %-14s %5d\n", "total", t }'
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 200 TAB OFF
ALTER SESSION SET CONTAINER = $ORA_PDB;
SET SERVEROUTPUT ON
DECLARE n NUMBER;
BEGIN
  FOR t IN (SELECT o.object_name FROM dba_objects o WHERE o.owner = UPPER('$schema') AND o.object_type = 'TABLE' ORDER BY o.object_id) LOOP
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || DBMS_ASSERT.ENQUOTE_NAME(UPPER('$schema'), FALSE) || '.'
      || DBMS_ASSERT.ENQUOTE_NAME(t.object_name, FALSE) INTO n;
    DBMS_OUTPUT.PUT_LINE(LOWER(t.object_name) || CHR(9) || n);
  END LOOP;
END;
/
EXIT
EOF
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

  if ! docker image inspect "$ORA_IMAGE" >/dev/null 2>&1; then
    info "Pulling $ORA_IMAGE (about 1.7 GB to download)"
    docker pull "$ORA_IMAGE" || die 2 "could not pull image $ORA_IMAGE"
  fi

  info "Starting container $CONTAINER from $ORA_IMAGE (no published port)"
  # The image insists on a SYS/SYSTEM password at first start. It gets a random one as a file (ORACLE_PASSWORD_FILE, so it is
  # not in the container's environment or `docker inspect`), the file is deleted once the database is up, and then every
  # password account is given a new random password that nobody keeps: the tool itself logs in by OS authentication only.
  local tmp; tmp="$(mktemp -d)"; chmod 700 "$tmp"
  random_pw > "$tmp/pw"
  chmod 644 "$tmp/pw"
  docker create --name "$CONTAINER" -e ORACLE_PASSWORD_FILE=/tmp/.orapw "$ORA_IMAGE" >/dev/null ||
    { rm -rf "$tmp"; die 2 "could not create container $CONTAINER"; }
  docker cp -q "$tmp/pw" "$CONTAINER:/tmp/.orapw" >/dev/null || { rm -rf "$tmp"; die 2 "could not copy the password file"; }
  rm -rf "$tmp"
  docker start "$CONTAINER" >/dev/null || die 2 "could not start container $CONTAINER"
  wait_ready
  # docker cp gives the file the host user's uid, which the oracle user cannot delete from the sticky /tmp: remove it as root.
  docker exec -u root "$CONTAINER" rm -f /tmp/.orapw

  # New random passwords go through stdin (never a command line), are used once and forgotten. PDBADMIN, the pluggable
  # database's administrator, keeps the password the image was built with unless changed here; it is also locked.
  { printf 'WHENEVER SQLERROR EXIT FAILURE\n'
    printf 'ALTER USER SYS IDENTIFIED BY "%s";\n' "$(random_pw)"
    printf 'ALTER USER SYSTEM IDENTIFIED BY "%s";\n' "$(random_pw)"
    printf 'ALTER SESSION SET CONTAINER = %s;\n' "$ORA_PDB"
    printf 'ALTER USER PDBADMIN IDENTIFIED BY "%s" ACCOUNT LOCK;\n' "$(random_pw)"
    printf 'EXIT\n'
  } | sql_in >/dev/null 2>&1 || die 2 "could not replace the start-up passwords in $CONTAINER"

  local env ver maj cs
  env="$(sql_in 2>&1 <<EOF
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 200
ALTER SESSION SET CONTAINER = $ORA_PDB;
SELECT 'VERSION ' || version_full FROM v\$instance;
SELECT 'CHARSET ' || value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';
SELECT 'MAXSTR ' || UPPER(value) FROM v\$parameter WHERE name = 'max_string_size';
EXIT
EOF
)" || die 2 "could not read the server version and character set: $env"
  ver="$(printf '%s\n' "$env" | awk '$1 == "VERSION" { print $2 }')"
  cs="$(printf '%s\n' "$env" | awk '$1 == "CHARSET" { print $2 }')"
  maj="${ver%%.*}"
  [[ "$maj" =~ ^[0-9]+$ ]] && [ "$maj" -ge 23 ] || die 2 "Oracle server version '$ver' is older than 23 (BOOLEAN and multi-row INSERT need 23ai or later)"
  [ "$cs" = "AL32UTF8" ] || die 2 "database character set is $cs, not AL32UTF8"
  info "Server ready: version $ver, character set $cs, MAX_STRING_SIZE $(printf '%s\n' "$env" | awk '$1 == "MAXSTR" { print $2 }')"

  info "Copying the input files into the container"
  copy_load_inputs || die 2 "could not copy the input files into $CONTAINER"

  info "Creating schema $ORA_USER (no password: nobody can log in as it), loading 01-schema.sql, then 02-data-sanitized.sql"
  load_schema "$ORA_USER" ||
    die 2 "the load failed (sqlplus error above); DDL cannot be rolled back, so the container is left for inspection: reload with --recreate"

  info "Rows loaded"
  row_counts "$ORA_USER" || die 2 "could not count the loaded rows"
  echo "LOAD COMPLETE: schema $ORA_USER in pluggable database $ORA_PDB, container $CONTAINER"
}

# ---------------------------------------------------------------- verify
cmd_verify() {
  local schema="${VERIFY_SCHEMA:-$ORA_USER}" out="${VERIFY_OUT:-$RESULTS_FILE}"
  require_docker
  require_inputs
  container_running || die 2 "container $CONTAINER is not running; run 'ingest.sh load' first"
  [[ "$schema" =~ ^[A-Za-z][A-Za-z0-9_]{0,29}$ ]] || die 2 "unexpected schema name: $schema"

  local schema_sha data_sha run_time commit
  schema_sha="$(file_sha "$SCHEMA_SQL")"; data_sha="$(file_sha "$DATA_SQL")"
  run_time="$(date -u '+%Y-%m-%d %H:%M:%S')"; commit="$(tool_commit)"
  [[ "$commit" =~ ^[0-9a-z]+$ ]] || commit=unknown

  # The directory object used to read the metadata points at this folder; it is dropped at the end of verify.sql, and the
  # folder's contents are removed here before and after.
  docker exec "$CONTAINER" sh -c 'rm -rf /tmp/marverify && mkdir -p /tmp/marverify' &&
    docker cp -q "$META_JSON" "$CONTAINER:/tmp/marverify/source-metadata.json" &&
    docker cp -q "$HERE/verify.sql" "$CONTAINER:/tmp/marverify/verify.sql" ||
    die 2 "could not copy verify.sql and the metadata into $CONTAINER"

  local output rc
  output="$(sql_in 2>&1 <<EOF
DEFINE v_pdb = "$ORA_PDB"
DEFINE v_schema = "$schema"
DEFINE v_dir = "/tmp/marverify"
DEFINE v_schema_sha = "$schema_sha"
DEFINE v_data_sha = "$data_sha"
DEFINE v_run_time = "$run_time"
DEFINE v_tool_commit = "$commit"
DEFINE v_image = "$ORA_IMAGE"
DEFINE v_container = "$CONTAINER"
@/tmp/marverify/verify.sql
EOF
)"
  rc=$?
  docker exec -u root "$CONTAINER" rm -rf /tmp/marverify
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$output" | grep -q '^JSON-END$'; then
    printf '%s\n' "$output" | tail -n 25 >&2
    die 2 "verify.sql failed to run (sqlplus exit $rc)"
  fi
  printf '%s\n' "$output" | sed -n '/^JSON-BEGIN$/,/^JSON-END$/p' | sed '1d;$d' >"$out" || die 2 "could not write $out"

  local lines summary fails passed total rows_ok rows_total
  lines="$(printf '%s\n' "$output" | grep -E $'^(PASS|FAIL)\t')"
  summary="$(printf '%s\n' "$output" | grep $'^SUMMARY\t')"
  printf '%s\n' "$lines" | awk -F'\t' '{ printf "%-4s  %-13s %s -- %s\n", $1, $2, $3, $4 }'
  fails="$(printf '%s\n' "$lines" | grep -c '^FAIL')"
  IFS=$'\t' read -r _ passed total rows_ok rows_total <<<"$summary"
  echo "Results written to $out"
  if [ "$fails" -eq 0 ]; then
    echo "VERIFICATION PASSED - $passed of $total checks; $rows_ok of $rows_total rows verified identical (schema $schema)"
    return 0
  fi
  echo "VERIFICATION FAILED - $fails of $total checks failed; $rows_ok of $rows_total rows verified identical (schema $schema)"
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
ORA_IMAGE=$ORA_IMAGE
ORA_PDB=$ORA_PDB
ORA_USER=$ORA_USER
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

  info "Self-test 2: a damaged copy of the schema is caught and the damaged tables are named"
  # The copy is a second schema loaded from the same files in the self-test container, then damaged.
  local dmg="ingest_selftest_damaged" rcd
  ( CONTAINER="$st_container"; load_schema "$dmg" ) >"$work/damaged-load.txt" 2>&1
  CONTAINER="$st_container" sql_in >"$work/damage.txt" 2>&1 <<EOF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
ALTER SESSION SET CONTAINER = $ORA_PDB;
ALTER SESSION SET CURRENT_SCHEMA = $dmg;
UPDATE comments SET text = text || '.' WHERE id = (SELECT MIN(id) FROM comments);
DELETE FROM tickets WHERE id = (SELECT MAX(id) FROM tickets);
COMMIT;
DROP INDEX ix_users_name_active;
EXIT
EOF
  st verify --schema "$dmg" --out "$work/damaged.json" >"$work/damaged.txt" 2>&1; rcd=$?
  printf 'ALTER SESSION SET CONTAINER = %s;\nDROP USER %s CASCADE;\nEXIT\n' "$ORA_PDB" "$dmg" |
    CONTAINER="$st_container" sql_in >/dev/null 2>&1
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
    printf '{\n  "tool": "import-oracle",\n  "status": "%s",\n  "passed": %d,\n  "total": %d,\n  "tests": [\n' "$status" "$passed" "$n"
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
  container_running || die 2 "container $CONTAINER is not running (the report is rendered by PL/SQL inside it)"
  mkdir -p "$REPORT_DIR"
  docker exec "$CONTAINER" sh -c 'rm -rf /tmp/marreport && mkdir -p /tmp/marreport' &&
    docker cp -q "$RESULTS_FILE" "$CONTAINER:/tmp/marreport/report-results.json" &&
    docker cp -q "$HERE/report.sql" "$CONTAINER:/tmp/marreport/report.sql" || die 2 "could not copy the report inputs into $CONTAINER"
  if [ -f "$SELFTEST_FILE" ]; then
    docker cp -q "$SELFTEST_FILE" "$CONTAINER:/tmp/marreport/report-selftest.json" || die 2 "could not copy the self-test results"
  else
    printf 'null\n' | docker exec -i "$CONTAINER" sh -c 'cat > /tmp/marreport/report-selftest.json'
  fi
  # PL/SQL is only the template engine: the report reads the two JSON files, never the migrated data.
  local output rc
  output="$(printf '@/tmp/marreport/report.sql\n' | sql_in 2>&1)"
  rc=$?
  docker exec -u root "$CONTAINER" rm -rf /tmp/marreport
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$output" | grep -q '^HTML-END$'; then
    printf '%s\n' "$output" | tail -n 25 >&2
    die 2 "report.sql failed (sqlplus exit $rc)"
  fi
  printf '%s\n' "$output" | sed -n '/^HTML-BEGIN$/,/^HTML-END$/p' | sed '1d;$d' >"$REPORT_FILE" || die 2 "could not write $REPORT_FILE"
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
