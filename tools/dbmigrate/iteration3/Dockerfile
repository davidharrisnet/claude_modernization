# MasterAntiqueRepair SQLite, baked in at build time.
# Unlike iteration 2 (stock alpine:3.20, data loaded via `docker exec` after the
# container is already running), this image carries the finished, populated
# database as part of the image itself: `docker build` fails if the schema/data
# SQL doesn't load cleanly or PRAGMA integrity_check isn't 'ok'.
#
# Only the *sanitized* data file is ever built into this image (see sanitize.py):
# every Users row has PasswordHash/SecurityStamp set to NULL and MustResetPassword
# set to 1. No real credential material is ever baked into this artifact.
FROM alpine:3.20
RUN apk add --no-cache sqlite sqlite-tools
COPY 01-schema.sql 02-data-sanitized.sql /tmp/
RUN mkdir -p /data \
 && sqlite3 -bail /data/masterantique.sqlite < /tmp/01-schema.sql \
 && sqlite3 -bail /data/masterantique.sqlite < /tmp/02-data-sanitized.sql \
 && test "$(sqlite3 /data/masterantique.sqlite 'PRAGMA integrity_check;')" = "ok" \
 && rm -f /tmp/01-schema.sql /tmp/02-data-sanitized.sql
CMD ["tail", "-f", "/dev/null"]
