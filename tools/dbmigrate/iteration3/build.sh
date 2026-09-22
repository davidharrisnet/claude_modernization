#!/usr/bin/env bash
# build: docker build the image with the schema/data baked in, then start an idle container from it.
# Usage: build.sh [--recreate]
# Exit codes: 0 ok, 2 error, 3 refused (container/image already exists, no --recreate)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="masterantique-sqlite:iteration3"
CONTAINER="mar-sqlite-iter3"
RECREATE=0
for a in "$@"; do
  case "$a" in
    --recreate) RECREATE=1 ;;
    *) echo "ERROR: unknown option '$a'" >&2; exit 2 ;;
  esac
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: the Docker daemon is not running." >&2
  exit 2
fi

if [ ! -f 02-data.sql ]; then
  echo "ERROR: 02-data.sql not found (gitignored, transient input — copy it from tools/dbmigrate/iteration2/02-data.sql first)." >&2
  exit 2
fi
if [ "$RECREATE" -eq 1 ] || [ ! -f 02-data-sanitized.sql ]; then
  python3 sanitize.py
fi

EXISTS=0
if docker inspect "$CONTAINER" >/dev/null 2>&1; then EXISTS=1; fi

if [ "$EXISTS" -eq 1 ] && [ "$RECREATE" -eq 0 ]; then
  echo "ERROR: container '$CONTAINER' already exists (use --recreate to replace it)." >&2
  exit 3
fi

if [ "$EXISTS" -eq 1 ]; then
  echo "Removing existing container '$CONTAINER' and image '$IMAGE' ..."
  docker rm -f "$CONTAINER" >/dev/null
  docker rmi -f "$IMAGE" >/dev/null 2>&1 || true
fi

echo "Building image '$IMAGE' from 01-schema.sql + 02-data-sanitized.sql (credentials redacted) ..."
docker build -t "$IMAGE" .

echo "Starting container '$CONTAINER' ..."
docker run -d --name "$CONTAINER" "$IMAGE" >/dev/null

echo "Built and started. Database baked in at /data/masterantique.sqlite inside '$CONTAINER'."
docker images "$IMAGE" --format 'Image size: {{.Size}}'
