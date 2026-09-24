-- import-postgresql verification: checks the loaded PostgreSQL database against source-metadata.json.
-- Run by `ingest.sh verify` inside the container:
--   psql -X -q -A -t -v ON_ERROR_STOP=1 -v schema_sha=.. -v data_sha=.. -v run_time=.. -v tool_commit=..
--        -v image=.. -v container=.. -v outfile=.. -f /tmp/verify.sql
-- Prints one line per check (PASS|FAIL <TAB> category <TAB> name <TAB> detail), then a SUMMARY line, and writes every
-- check, count, hash and summary as JSON to :outfile (the report's source).
-- Nothing executable is read from the metadata: every query is built here, identifiers quoted with format('%I').
-- Read-only against the data: the rule tests run inside blocks that are always rolled back, with explicit ids so no
-- sequence moves (nextval is never rolled back).

\set meta `cat /tmp/source-metadata.json`
SET client_min_messages = warning;

CREATE TEMP TABLE meta AS SELECT :'meta'::jsonb AS j;
CREATE TEMP TABLE run_info AS SELECT
  :'schema_sha'::text AS schema_sha, :'data_sha'::text AS data_sha, :'run_time'::text AS run_time,
  :'tool_commit'::text AS tool_commit, :'image'::text AS image, :'container'::text AS container;

CREATE TEMP TABLE results (seq serial PRIMARY KEY, status text NOT NULL, category text NOT NULL, name text NOT NULL,
                           detail text NOT NULL);
CREATE TEMP TABLE table_results (ord int PRIMARY KEY, source_name text, target_name text, expected_rows bigint,
                                 actual_rows bigint, expected_sha text, actual_sha text);
CREATE TEMP TABLE summary_results (ord int PRIMARY KEY, name text, expected jsonb, actual jsonb);
CREATE TEMP TABLE seq_snapshot (seq_name text PRIMARY KEY, last_value bigint);

-- Record one check. A NULL outcome counts as a failure.
CREATE FUNCTION pg_temp.chk(ok boolean, cat text, nm text, det text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO results (status, category, name, detail)
  VALUES (CASE WHEN coalesce(ok, false) THEN 'PASS' ELSE 'FAIL' END, cat, nm, coalesce(det, ''));
$$;

-- Defaults as information_schema reports them ('false', '0', 'abc'::character varying) versus the metadata ('FALSE', '0').
CREATE FUNCTION pg_temp.norm_default(t text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(replace(regexp_replace(lower(t), '::[a-z_ ]+(\[\])?', '', 'g'), '''', ''), '');
$$;

-- Index keys and predicates: pg_get_indexdef gives lower(name::text) and (deleted_at IS NULL); the metadata has
-- lower(name) and deleted_at IS NULL. Compare without casts, parentheses, quotes, spaces or case.
CREATE FUNCTION pg_temp.norm_expr(t text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_replace(regexp_replace(lower(t), '::[a-z_ ]+(\[\])?', '', 'g'), '[\s()"]', '', 'g');
$$;

-- Human-readable difference between two JSON arrays (used only for the detail text; the check itself is equality).
CREATE FUNCTION pg_temp.jdiff(e jsonb, a jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(d, '; ' ORDER BY d COLLATE "C"), 'same items, different order')
  FROM (SELECT 'expected ' || x::text AS d FROM jsonb_array_elements(e) x WHERE NOT a @> jsonb_build_array(x)
        UNION ALL
        SELECT 'found ' || y::text FROM jsonb_array_elements(a) y WHERE NOT e @> jsonb_build_array(y)) s;
$$;

CREATE FUNCTION pg_temp.ts(v timestamp) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(to_char(v, 'YYYY-MM-DD HH24:MI:SS.MS'), '');
$$;

-- ------------------------------------------------------------------ 1. environment
DO $$
DECLARE m jsonb := (SELECT j FROM meta);
        minv int := coalesce((m -> 'meta' ->> 'minPostgresVersion')::int, 15);
BEGIN
  PERFORM pg_temp.chk(current_setting('server_version_num')::int >= minv * 10000, 'environment',
    'PostgreSQL server version is supported',
    format('server %s, minimum %s', current_setting('server_version'), minv));
  PERFORM pg_temp.chk(current_setting('server_encoding') = 'UTF8', 'environment', 'Server encoding is UTF8',
    current_setting('server_encoding'));
  PERFORM pg_temp.chk(m ->> 'schemaVersion' = '1', 'environment', 'Metadata format is version 1',
    'schemaVersion ' || coalesce(m ->> 'schemaVersion', 'missing'));
END $$;

-- ------------------------------------------------------------------ 2. transfer integrity
DO $$
DECLARE m jsonb := (SELECT j -> 'meta' FROM meta);
        r record;
BEGIN
  SELECT * INTO r FROM run_info;
  PERFORM pg_temp.chk(r.schema_sha = m ->> 'schemaSha256', 'integrity',
    format('%s matches the recorded SHA-256', m ->> 'schemaFile'),
    format('expected %s, found %s', left(m ->> 'schemaSha256', 16), left(r.schema_sha, 16)));
  PERFORM pg_temp.chk(r.data_sha = m ->> 'dataSha256', 'integrity',
    format('%s matches the recorded SHA-256', m ->> 'dataFile'),
    format('expected %s, found %s', left(m ->> 'dataSha256', 16), left(r.data_sha, 16)));
END $$;

-- ------------------------------------------------------------------ 3. row counts and canonical content hashes
-- Canonical form (defined by export-postgresql, independent of any database): per table, rows sorted by their own text in
-- byte order, joined by LF; cells joined by | in column order; NULL is ~; i:<int>, b:1|0, t:yyyy-MM-dd HH:mm:ss.fff,
-- s:<hex of UTF-8>, x:<hex>, g:<guid>; SHA-256 of the UTF-8 text; an empty table hashes the empty string.
DO $$
DECLARE m jsonb := (SELECT j FROM meta);
        t jsonb; c jsonb; cells text[]; q text; n bigint; h text; ord int := 0; tn text; col text;
BEGIN
  FOR t IN SELECT value FROM jsonb_array_elements(m -> 'tables') LOOP
    ord := ord + 1;
    tn := t ->> 'targetName';
    n := NULL; h := NULL;
    BEGIN
      cells := ARRAY[]::text[];
      FOR c IN SELECT value FROM jsonb_array_elements(t -> 'columns') LOOP
        col := c ->> 'targetName';
        cells := cells || CASE c ->> 'kind'
          WHEN 'int'      THEN format($f$coalesce('i:' || %I::text, '~')$f$, col)
          WHEN 'bit'      THEN format($f$coalesce('b:' || CASE WHEN %I THEN '1' WHEN NOT %I THEN '0' END, '~')$f$, col, col)
          WHEN 'datetime' THEN format($f$coalesce('t:' || to_char(%I, 'YYYY-MM-DD HH24:MI:SS.MS'), '~')$f$, col)
          WHEN 'string'   THEN format($f$coalesce('s:' || encode(convert_to(%I, 'UTF8'), 'hex'), '~')$f$, col)
          WHEN 'binary'   THEN format($f$coalesce('x:' || encode(%I, 'hex'), '~')$f$, col)
          WHEN 'guid'     THEN format($f$coalesce('g:' || lower(%I::text), '~')$f$, col)
        END;
        IF cells[array_length(cells, 1)] IS NULL THEN
          RAISE EXCEPTION 'column %.% has unknown kind %', tn, col, c ->> 'kind';
        END IF;
      END LOOP;
      q := format($q$SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(r, E'\n' ORDER BY r COLLATE "C"), ''),
                     'UTF8')), 'hex') FROM (SELECT concat_ws('|', %s) AS r FROM %I) x$q$,
                  array_to_string(cells, ', '), tn);
      EXECUTE q INTO n, h;
    EXCEPTION WHEN others THEN
      PERFORM pg_temp.chk(false, 'counts', format('Table %s row count', tn), 'could not read the table: ' || SQLERRM);
      PERFORM pg_temp.chk(false, 'hashes', format('Table %s content hash', tn), 'could not read the table: ' || SQLERRM);
      INSERT INTO table_results VALUES (ord, t ->> 'sourceName', tn, (t ->> 'rowCount')::bigint, NULL,
                                        t ->> 'rowSha256', NULL);
      CONTINUE;
    END;
    INSERT INTO table_results VALUES (ord, t ->> 'sourceName', tn, (t ->> 'rowCount')::bigint, n, t ->> 'rowSha256', h);
    PERFORM pg_temp.chk(n = (t ->> 'rowCount')::bigint, 'counts', format('Table %s row count', tn),
      format('expected %s, found %s', t ->> 'rowCount', n));
    PERFORM pg_temp.chk(h = t ->> 'rowSha256', 'hashes', format('Table %s content hash', tn),
      format('expected %s, found %s', left(t ->> 'rowSha256', 16), left(h, 16)));
  END LOOP;

  PERFORM pg_temp.chk((SELECT sum(actual_rows) FROM table_results) = (m -> 'expectations' ->> 'totalRows')::bigint,
    'counts', 'Total rows across all tables',
    format('expected %s, found %s', m -> 'expectations' ->> 'totalRows', (SELECT sum(actual_rows) FROM table_results)));
END $$;

-- ------------------------------------------------------------------ 4. schema
DO $$
DECLARE m jsonb := (SELECT j FROM meta);
        t jsonb; tn text; rel regclass; e jsonb; a jsonb; ep text[]; ap text[]; n int;
BEGIN
  -- The set of tables: nothing missing, nothing extra.
  SELECT coalesce(jsonb_agg(x ORDER BY x COLLATE "C"), '[]') INTO e
    FROM (SELECT value ->> 'targetName' AS x FROM jsonb_array_elements(m -> 'tables')) s;
  SELECT coalesce(jsonb_agg(table_name::text ORDER BY table_name::text COLLATE "C"), '[]') INTO a
    FROM information_schema.tables WHERE table_schema = current_schema() AND table_type = 'BASE TABLE';
  PERFORM pg_temp.chk(e = a, 'schema', 'The schema has exactly the expected tables',
    CASE WHEN e = a THEN format('%s tables', jsonb_array_length(a)) ELSE pg_temp.jdiff(e, a) END);

  FOR t IN SELECT value FROM jsonb_array_elements(m -> 'tables') LOOP
    tn := t ->> 'targetName';
    rel := to_regclass(format('%I', tn));
    IF rel IS NULL THEN
      PERFORM pg_temp.chk(false, 'schema', format('Table %s structure', tn), 'table missing');
      CONTINUE;
    END IF;

    -- Columns, in order: name, type, length, nullability, default, identity (GENERATED BY DEFAULT).
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'name', c ->> 'targetName', 'type', c ->> 'dataType', 'maxLength', c -> 'maxLength',
             'nullable', (c ->> 'nullable')::boolean, 'default', pg_temp.norm_default(c ->> 'default'),
             'identity', (c ->> 'identity')::boolean) ORDER BY o), '[]')
      INTO e FROM jsonb_array_elements(t -> 'columns') WITH ORDINALITY x(c, o);
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'name', column_name::text, 'type', data_type::text, 'maxLength', character_maximum_length::int,
             'nullable', is_nullable::text = 'YES', 'default', pg_temp.norm_default(column_default::text),
             'identity', is_identity::text = 'YES' AND identity_generation::text = 'BY DEFAULT') ORDER BY ordinal_position), '[]')
      INTO a FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = tn;
    PERFORM pg_temp.chk(e = a, 'schema', format('Table %s columns', tn),
      CASE WHEN e = a THEN format('%s columns: names, types, lengths, nullability, defaults, identity', jsonb_array_length(a))
           ELSE pg_temp.jdiff(e, a) END);

    -- Primary key, columns in order.
    ep := ARRAY(SELECT jsonb_array_elements_text(t -> 'primaryKey'));
    SELECT coalesce(array_agg(att.attname::text ORDER BY k.o), '{}') INTO ap
      FROM pg_constraint con CROSS JOIN LATERAL unnest(con.conkey) WITH ORDINALITY k(attnum, o)
      JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.attnum
      WHERE con.conrelid = rel AND con.contype = 'p';
    PERFORM pg_temp.chk(ep = ap, 'schema', format('Table %s primary key', tn),
      format('expected (%s), found (%s)', array_to_string(ep, ', '), array_to_string(ap, ', ')));

    -- Foreign keys: name, columns, referenced table and columns, delete action.
    SELECT coalesce(jsonb_agg(jsonb_build_object('name', f ->> 'targetName', 'columns', f -> 'columns',
             'refTable', f ->> 'refTable', 'refColumns', f -> 'refColumns', 'onDelete', f ->> 'onDelete')
             ORDER BY f ->> 'targetName' COLLATE "C"), '[]')
      INTO e FROM jsonb_array_elements(t -> 'foreignKeys') f;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'name', con.conname::text,
             'columns', (SELECT jsonb_agg(att.attname::text ORDER BY k.o) FROM unnest(con.conkey) WITH ORDINALITY k(n, o)
                         JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.n),
             'refTable', rc.relname::text,
             'refColumns', (SELECT jsonb_agg(att.attname::text ORDER BY k.o) FROM unnest(con.confkey) WITH ORDINALITY k(n, o)
                            JOIN pg_attribute att ON att.attrelid = con.confrelid AND att.attnum = k.n),
             'onDelete', CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'c' THEN 'CASCADE' WHEN 'r' THEN 'RESTRICT'
                                              WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END)
             ORDER BY con.conname::text COLLATE "C"), '[]')
      INTO a FROM pg_constraint con JOIN pg_class rc ON rc.oid = con.confrelid
      WHERE con.conrelid = rel AND con.contype = 'f';
    PERFORM pg_temp.chk(e = a, 'schema', format('Table %s foreign keys', tn),
      CASE WHEN e = a THEN format('%s foreign keys: names, columns, targets, delete actions', jsonb_array_length(a))
           ELSE pg_temp.jdiff(e, a) END);

    -- Indexes (other than the primary key): name, unique, key columns or expressions, direction, partial filter.
    SELECT coalesce(jsonb_agg(jsonb_build_object('name', i ->> 'targetName', 'unique', (i ->> 'unique')::boolean,
             'keys', (SELECT jsonb_agg(pg_temp.norm_expr(coalesce(k ->> 'expression', k ->> 'column')) ORDER BY o)
                      FROM jsonb_array_elements(i -> 'columns') WITH ORDINALITY z(k, o)),
             'descending', (SELECT jsonb_agg((k ->> 'descending')::boolean ORDER BY o)
                            FROM jsonb_array_elements(i -> 'columns') WITH ORDINALITY z(k, o)),
             'filter', pg_temp.norm_expr(i ->> 'filter'))
             ORDER BY i ->> 'targetName' COLLATE "C"), '[]')
      INTO e FROM jsonb_array_elements(t -> 'indexes') i;
    SELECT coalesce(jsonb_agg(jsonb_build_object('name', ic.relname::text, 'unique', ix.indisunique,
             'keys', (SELECT jsonb_agg(pg_temp.norm_expr(pg_get_indexdef(ix.indexrelid, k, true)) ORDER BY k)
                      FROM generate_series(1, ix.indnkeyatts) k),
             'descending', (SELECT jsonb_agg((ix.indoption[k - 1] & 1) = 1 ORDER BY k)
                            FROM generate_series(1, ix.indnkeyatts) k),
             'filter', pg_temp.norm_expr(pg_get_expr(ix.indpred, ix.indrelid, true)))
             ORDER BY ic.relname::text COLLATE "C"), '[]')
      INTO a FROM pg_index ix JOIN pg_class ic ON ic.oid = ix.indexrelid
      WHERE ix.indrelid = rel AND NOT ix.indisprimary;
    PERFORM pg_temp.chk(e = a, 'schema', format('Table %s indexes', tn),
      CASE WHEN e = a THEN format('%s indexes: names, uniqueness, keys and expressions, partial filters', jsonb_array_length(a))
           ELSE pg_temp.jdiff(e, a) END);
  END LOOP;

  SELECT count(*) INTO n FROM pg_index ix JOIN pg_class c ON c.oid = ix.indrelid
    JOIN pg_namespace s ON s.oid = c.relnamespace WHERE s.nspname = current_schema() AND NOT ix.indisvalid;
  PERFORM pg_temp.chk(n = 0, 'schema', 'No invalid indexes', format('%s invalid', n));
END $$;

-- ------------------------------------------------------------------ 5. business summaries
-- The PostgreSQL form of the ten summaries from export-postgresql (the metadata's sourceSql is SQL Server text,
-- recorded for documentation only and never executed). Output format: cells joined by |, NULL as the empty string,
-- timestamps yyyy-MM-dd HH:mm:ss.fff; compared as rows sorted in byte order.
CREATE TEMP TABLE summary_sql (name text PRIMARY KEY, q text NOT NULL);
INSERT INTO summary_sql VALUES
 ('Users by type',
  $q$SELECT coalesce(discriminator, '') || '|' || count(*) FROM users GROUP BY discriminator$q$),
 ('Users active vs soft-deleted',
  $q$SELECT s || '|' || count(*) FROM (SELECT CASE WHEN deleted_at IS NULL THEN 'active' ELSE 'soft-deleted' END AS s
     FROM users) x GROUP BY s$q$),
 ('Users per role',
  $q$SELECT coalesce(r.name, '') || '|' || count(*) FROM user_roles ur JOIN roles r ON r.id = ur.role_id GROUP BY r.name$q$),
 ('Tickets by state',
  $q$SELECT coalesce(state::text, '') || '|' || count(*) FROM tickets GROUP BY state$q$),
 ('Tickets assigned vs unassigned',
  $q$SELECT s || '|' || count(*) FROM (SELECT CASE WHEN user_id IS NULL THEN 'unassigned' ELSE 'assigned' END AS s
     FROM tickets) x GROUP BY s$q$),
 ('Audit events by action',
  $q$SELECT coalesce(action::text, '') || '|' || count(*) FROM audit_logs GROUP BY action$q$),
 ('Comments per ticket (distribution)',
  $q$SELECT n || '|' || count(*) FROM (SELECT count(*) AS n FROM comments GROUP BY ticket_id) x GROUP BY n$q$),
 ('Comment and commented-ticket totals',
  $q$SELECT (SELECT count(*) FROM comments) || '|' || (SELECT count(DISTINCT ticket_id) FROM comments)$q$),
 ('Ticket date ranges',
  $q$SELECT concat_ws('|', pg_temp.ts(min(submitted_date)), pg_temp.ts(max(submitted_date)), pg_temp.ts(min(assigned_date)),
     pg_temp.ts(max(assigned_date)), pg_temp.ts(min(completed_date)), pg_temp.ts(max(completed_date))) FROM tickets$q$),
 ('Account and audit date ranges',
  $q$SELECT concat_ws('|', pg_temp.ts((SELECT min(created_at) FROM users)), pg_temp.ts((SELECT max(created_at) FROM users)),
     pg_temp.ts((SELECT min(timestamp) FROM audit_logs)), pg_temp.ts((SELECT max(timestamp) FROM audit_logs)))$q$);

DO $$
DECLARE m jsonb := (SELECT j FROM meta);
        s jsonb; o int; q text; act jsonb; err text; exp jsonb;
BEGIN
  FOR s, o IN SELECT value, ordinality FROM jsonb_array_elements(m -> 'summaries') WITH ORDINALITY LOOP
    exp := s -> 'expectedRows';
    SELECT ss.q INTO q FROM summary_sql ss WHERE ss.name = s ->> 'name';
    act := NULL; err := NULL;
    IF q IS NULL THEN
      err := 'no PostgreSQL query is defined for this summary';
    ELSE
      BEGIN
        EXECUTE format('SELECT coalesce(jsonb_agg(r ORDER BY r COLLATE "C"), ''[]'') FROM (%s) x(r)', q) INTO act;
      EXCEPTION WHEN others THEN err := SQLERRM;
      END;
    END IF;
    INSERT INTO summary_results VALUES (o, s ->> 'name', exp, act);
    PERFORM pg_temp.chk(err IS NULL AND act = exp, 'summaries', s ->> 'name',
      CASE WHEN err IS NOT NULL THEN err
           WHEN act = exp THEN (SELECT string_agg(v, ', ') FROM jsonb_array_elements_text(act) v)
           ELSE format('expected %s, found %s', exp, act) END);
  END LOOP;
  FOR q IN SELECT ss.name FROM summary_sql ss
           WHERE ss.name NOT IN (SELECT value ->> 'name' FROM jsonb_array_elements(m -> 'summaries')) LOOP
    PERFORM pg_temp.chk(false, 'summaries', q, 'defined here but not recorded in the metadata');
  END LOOP;
END $$;

-- ------------------------------------------------------------------ 6. sanitization and expectations
DO $$
DECLARE x jsonb := (SELECT j -> 'expectations' FROM meta);
        m jsonb := (SELECT j -> 'meta' FROM meta);
        n bigint; bad bigint; dups bigint;
BEGIN
  PERFORM pg_temp.chk((m ->> 'sanitizeCredentials')::boolean, 'sanitization', 'The export was made with credentials sanitized',
    'sanitizeCredentials = ' || coalesce(m ->> 'sanitizeCredentials', 'missing'));
  BEGIN
    SELECT count(*), count(*) FILTER (WHERE password_hash IS NOT NULL OR security_stamp IS NOT NULL
                                       OR must_reset_password IS DISTINCT FROM true)
      INTO n, bad FROM users;
    PERFORM pg_temp.chk(n = (x ->> 'usersCount')::bigint, 'sanitization', 'User count',
      format('expected %s, found %s', x ->> 'usersCount', n));
    PERFORM pg_temp.chk(bad = 0 AND (x ->> 'usersSanitized')::boolean, 'sanitization',
      'Every user has no password hash or security stamp and must reset the password',
      format('%s of %s users not sanitized', bad, n));
    SELECT count(*) INTO dups FROM (SELECT lower(name) FROM users WHERE deleted_at IS NULL GROUP BY 1 HAVING count(*) > 1) d;
    PERFORM pg_temp.chk((dups = 0) = (x ->> 'noDuplicateActiveUsernamesIgnoringCase')::boolean, 'sanitization',
      'No two active usernames differ only by case', format('%s duplicates', dups));
  EXCEPTION WHEN others THEN
    PERFORM pg_temp.chk(false, 'sanitization', 'Users table readable for the sanitization checks', SQLERRM);
  END;
END $$;

-- ------------------------------------------------------------------ 7. rules
-- 7a. Identity sequences continue after the loaded ids. Checked first and without nextval, so nothing is consumed.
DO $$
DECLARE m jsonb := (SELECT j FROM meta);
        t jsonb; idcol text; seq text; lv bigint; expected bigint;
BEGIN
  FOR t IN SELECT value FROM jsonb_array_elements(m -> 'tables') LOOP
    SELECT c ->> 'targetName' INTO idcol FROM jsonb_array_elements(t -> 'columns') c
      WHERE (c ->> 'identity')::boolean LIMIT 1;
    CONTINUE WHEN idcol IS NULL;
    expected := (t ->> 'identityLast')::bigint;
    BEGIN
      seq := pg_get_serial_sequence(format('%I', t ->> 'targetName'), idcol);
      SELECT s.last_value INTO lv FROM pg_sequences s WHERE format('%I.%I', s.schemaname, s.sequencename) = seq;
      INSERT INTO seq_snapshot VALUES (seq, lv);
      PERFORM pg_temp.chk(seq IS NOT NULL AND lv IS NOT DISTINCT FROM expected, 'rules',
        format('New %s ids continue after the loaded ones', t ->> 'targetName'),
        format('sequence %s last value %s, expected %s', coalesce(seq, 'missing'),
               coalesce(lv::text, 'unused'), coalesce(expected::text, 'unused')));
    EXCEPTION WHEN others THEN
      PERFORM pg_temp.chk(false, 'rules', format('New %s ids continue after the loaded ones', t ->> 'targetName'), SQLERRM);
    END;
  END LOOP;
END $$;

-- 7b. Behaviour tests. Each runs in a block that ends by raising a private error, which rolls back everything the
-- block did; the outcome is kept in a variable. Test rows use explicit ids far above the data.
DO $$
DECLARE uid int; uname text; outcome text;
BEGIN
  SELECT id, name INTO uid, uname FROM users WHERE deleted_at IS NULL AND name <> upper(name) ORDER BY id LIMIT 1;

  -- A second active user whose name differs only by case is rejected.
  outcome := NULL;
  BEGIN
    INSERT INTO users (id, name, created_at, discriminator) VALUES (1000001, upper(uname), timestamp '2026-01-01', 'Customer');
    outcome := 'accepted';
    RAISE EXCEPTION USING ERRCODE = 'P0999', MESSAGE = 'roll back';
  EXCEPTION
    WHEN unique_violation THEN outcome := 'rejected (unique_violation)';
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN others THEN outcome := 'error: ' || SQLERRM;
  END;
  PERFORM pg_temp.chk(outcome = 'rejected (unique_violation)', 'rules',
    'A second active user differing only by case is rejected',
    format('inserting %L while %L is active: %s', upper(uname), uname, coalesce(outcome, 'no user to test with')));

  -- A soft-deleted username can be reused.
  outcome := NULL;
  BEGIN
    UPDATE users SET deleted_at = timestamp '2026-01-01' WHERE id = uid;
    INSERT INTO users (id, name, created_at, discriminator) VALUES (1000002, uname, timestamp '2026-01-01', 'Customer');
    outcome := 'accepted';
    RAISE EXCEPTION USING ERRCODE = 'P0999', MESSAGE = 'roll back';
  EXCEPTION
    WHEN unique_violation THEN outcome := 'rejected (unique_violation)';
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN others THEN outcome := 'error: ' || SQLERRM;
  END;
  PERFORM pg_temp.chk(outcome = 'accepted', 'rules', 'A soft-deleted username can be reused',
    format('%L soft-deleted, then inserted again: %s', uname, coalesce(outcome, 'no user to test with')));

  -- A comment pointing at a user and ticket that do not exist is rejected.
  outcome := NULL;
  BEGIN
    INSERT INTO comments (id, user_id, ticket_id, text, created_at)
      VALUES (1000003, 999999999, 999999999, 'orphan', timestamp '2026-01-01');
    outcome := 'accepted';
    RAISE EXCEPTION USING ERRCODE = 'P0999', MESSAGE = 'roll back';
  EXCEPTION
    WHEN foreign_key_violation THEN outcome := 'rejected (foreign_key_violation)';
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN others THEN outcome := 'error: ' || SQLERRM;
  END;
  PERFORM pg_temp.chk(outcome = 'rejected (foreign_key_violation)', 'rules',
    'A comment with a non-existent user and ticket is rejected', coalesce(outcome, ''));
END $$;

-- 7c. The rule tests left nothing behind: no test rows, and no sequence moved.
DO $$
DECLARE leftovers bigint; moved bigint;
BEGIN
  SELECT (SELECT count(*) FROM users WHERE id >= 1000000) + (SELECT count(*) FROM comments WHERE id >= 1000000)
    INTO leftovers;
  SELECT count(*) INTO moved FROM seq_snapshot sn
    WHERE sn.last_value IS DISTINCT FROM
          (SELECT s.last_value FROM pg_sequences s WHERE format('%I.%I', s.schemaname, s.sequencename) = sn.seq_name);
  PERFORM pg_temp.chk(leftovers = 0 AND moved = 0, 'rules', 'The rule tests left the database unchanged',
    format('%s test rows left, %s sequences moved', leftovers, moved));
EXCEPTION WHEN others THEN
  PERFORM pg_temp.chk(false, 'rules', 'The rule tests left the database unchanged', SQLERRM);
END $$;

-- ------------------------------------------------------------------ output
SELECT status || E'\t' || category || E'\t' || name || E'\t' || replace(detail, E'\t', ' ') FROM results ORDER BY seq;

SELECT 'SUMMARY' || E'\t' || count(*) FILTER (WHERE status = 'PASS') || E'\t' || count(*) || E'\t' ||
       (SELECT coalesce(sum(actual_rows) FILTER (WHERE actual_rows = expected_rows AND actual_sha = expected_sha), 0)
          FROM table_results) || E'\t' ||
       (SELECT coalesce(sum(expected_rows), 0) FROM table_results)
FROM results;

\o :outfile
SELECT jsonb_pretty(jsonb_build_object(
  'schemaVersion', 1,
  'tool', 'import-postgresql',
  'status', CASE WHEN (SELECT count(*) FROM results WHERE status = 'FAIL') = 0 THEN 'PASS' ELSE 'FAIL' END,
  'checksPassed', (SELECT count(*) FROM results WHERE status = 'PASS'),
  'checksTotal', (SELECT count(*) FROM results),
  'rowsVerified', (SELECT coalesce(sum(actual_rows) FILTER (WHERE actual_rows = expected_rows AND actual_sha = expected_sha), 0)
                   FROM table_results),
  'rowsTotal', (SELECT coalesce(sum(expected_rows), 0) FROM table_results),
  'database', current_database(),
  'environment', jsonb_build_object('serverVersion', current_setting('server_version'),
                                    'serverEncoding', current_setting('server_encoding'),
                                    'image', ri.image, 'container', ri.container, 'schema', current_schema()),
  'run', jsonb_build_object('runTimeUtc', ri.run_time, 'toolGitCommit', ri.tool_commit),
  'source', mt.j -> 'meta' -> 'source',
  'sourceExport', mt.j -> 'run',
  'inputs', jsonb_build_array(
      jsonb_build_object('file', mt.j -> 'meta' ->> 'schemaFile', 'expectedSha256', mt.j -> 'meta' ->> 'schemaSha256',
                         'actualSha256', ri.schema_sha),
      jsonb_build_object('file', mt.j -> 'meta' ->> 'dataFile', 'expectedSha256', mt.j -> 'meta' ->> 'dataSha256',
                         'actualSha256', ri.data_sha)),
  'tables', (SELECT coalesce(jsonb_agg(jsonb_build_object('sourceName', source_name, 'targetName', target_name,
                'expectedRows', expected_rows, 'actualRows', actual_rows, 'expectedSha256', expected_sha,
                'actualSha256', actual_sha) ORDER BY ord), '[]') FROM table_results),
  'summaries', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', name, 'expectedRows', expected, 'actualRows', actual)
                ORDER BY ord), '[]') FROM summary_results),
  'checks', (SELECT jsonb_agg(jsonb_build_object('seq', seq, 'status', status, 'category', category, 'name', name,
                'detail', detail) ORDER BY seq) FROM results),
  'schemaModel', (SELECT jsonb_agg(jsonb_build_object('sourceName', t ->> 'sourceName', 'targetName', t ->> 'targetName',
                'columns', t -> 'columns', 'primaryKey', t -> 'primaryKey', 'foreignKeys', t -> 'foreignKeys',
                'indexes', t -> 'indexes') ORDER BY o) FROM jsonb_array_elements(mt.j -> 'tables') WITH ORDINALITY y(t, o)),
  'knownDifferences', mt.j -> 'knownDifferences',
  'excludedTables', mt.j -> 'excludedTables'))
FROM meta mt, run_info ri;
\o
