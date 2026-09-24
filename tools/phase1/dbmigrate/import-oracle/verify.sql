-- import-oracle verification: checks the loaded Oracle schema against source-metadata.json.
-- Run by `ingest.sh verify` inside the container as SYS (operating-system authentication, no password), after a prologue of
-- DEFINE lines written by ingest.sh (v_pdb, v_schema, v_dir, v_schema_sha, v_data_sha, v_run_time, v_tool_commit, v_image,
-- v_container; every value checked against a strict pattern first).
-- Prints one line per check (PASS|FAIL <TAB> category <TAB> name <TAB> detail), a SUMMARY line, then the results JSON between
-- the lines JSON-BEGIN and JSON-END (ingest.sh writes it to verification-results.json, the report's source).
-- Nothing executable is read from the metadata: every query is built here from names that must match ^[a-z][a-z0-9_]*$ and
-- pass DBMS_ASSERT.SIMPLE_SQL_NAME. Every query against the migrated schema is dynamic SQL, so a missing table or column
-- gives a FAIL line, not a compile error. The rule tests run between SAVEPOINT and ROLLBACK TO with explicit ids >= 1000001
-- (an identity sequence is never rolled back), and the script ends with ROLLBACK: nothing is changed.
-- SQL*Plus substitutes an ampersand followed by a name everywhere, even inside PL/SQL text and comments: never write a literal
-- ampersand below (use CHR(38)).

SET VERIFY OFF FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 32767 TRIMOUT ON TRIMSPOOL ON TAB OFF ECHO OFF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
ALTER SESSION SET CONTAINER = &v_pdb;
ALTER SESSION SET NLS_SORT = BINARY;
ALTER SESSION SET NLS_COMP = BINARY;
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';
CREATE OR REPLACE DIRECTORY mar_verify_dir AS '&v_dir';
ALTER SESSION SET CURRENT_SCHEMA = &v_schema;
-- After the container switch: switching container resets the DBMS_OUTPUT buffer.
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED

DECLARE
  c_schema      CONSTANT VARCHAR2(128) := UPPER('&v_schema');
  c_pdb         CONSTANT VARCHAR2(128) := UPPER('&v_pdb');
  c_schema_sha  CONSTANT VARCHAR2(64)  := '&v_schema_sha';
  c_data_sha    CONSTANT VARCHAR2(64)  := '&v_data_sha';
  c_ts          CONSTANT VARCHAR2(30)  := 'YYYY-MM-DD HH24:MI:SS.FF3';
  c_test_id     CONSTANT NUMBER        := 1000001;

  TYPE t_list   IS TABLE OF VARCHAR2(32767);
  TYPE t_bag    IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(32767);
  TYPE t_check  IS RECORD (status VARCHAR2(4), category VARCHAR2(30), name VARCHAR2(400), detail VARCHAR2(4000));
  TYPE t_checks IS TABLE OF t_check;
  TYPE t_nummap IS TABLE OF NUMBER INDEX BY VARCHAR2(128);

  g_checks      t_checks := t_checks();
  g_meta        JSON_OBJECT_T;
  g_tables      JSON_ARRAY_T;
  g_table_res   JSON_ARRAY_T := JSON_ARRAY_T();
  g_summary_res JSON_ARRAY_T := JSON_ARRAY_T();
  g_seq         t_nummap;
  g_rows_ok     NUMBER := 0;
  g_rows_total  NUMBER := 0;
  g_version     VARCHAR2(100);
  g_banner      VARCHAR2(400);
  g_charset     VARCHAR2(100);
  g_maxstr      VARCHAR2(100);
  g_lensem      VARCHAR2(100);

  -- ---------------------------------------------------------------- helpers
  -- Record one check. A NULL outcome counts as a failure.
  PROCEDURE chk(p_ok BOOLEAN, p_cat VARCHAR2, p_name VARCHAR2, p_detail VARCHAR2) IS
  BEGIN
    g_checks.EXTEND;
    g_checks(g_checks.LAST).status   := CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END;
    g_checks(g_checks.LAST).category := p_cat;
    g_checks(g_checks.LAST).name     := SUBSTR(p_name, 1, 400);
    g_checks(g_checks.LAST).detail   := SUBSTR(p_detail, 1, 4000);
  END;

  -- A target name from the metadata, validated before it is ever put into SQL text.
  FUNCTION nm(p VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p IS NULL OR LENGTH(p) > 128 OR NOT REGEXP_LIKE(p, '^[a-z][a-z0-9_]*$') THEN
      RAISE_APPLICATION_ERROR(-20001, 'unexpected identifier in the metadata: ' || SUBSTR(p, 1, 60));
    END IF;
    RETURN DBMS_ASSERT.SIMPLE_SQL_NAME(p);
  END;

  FUNCTION read_file(p_name VARCHAR2) RETURN CLOB IS
    b BFILE := BFILENAME('MAR_VERIFY_DIR', p_name);
    c CLOB; dst INTEGER := 1; src INTEGER := 1; lang INTEGER := DBMS_LOB.DEFAULT_LANG_CTX; warn INTEGER;
  BEGIN
    DBMS_LOB.CREATETEMPORARY(c, TRUE);
    DBMS_LOB.FILEOPEN(b, DBMS_LOB.FILE_READONLY);
    DBMS_LOB.LOADCLOBFROMFILE(c, b, DBMS_LOB.LOBMAXSIZE, dst, src, NLS_CHARSET_ID('AL32UTF8'), lang, warn);
    DBMS_LOB.FILECLOSE(b);
    RETURN c;
  END;

  -- A JSON member as text: '' for a missing or null member, the plain value for a string, the JSON text otherwise.
  FUNCTION jtxt(o JSON_OBJECT_T, k VARCHAR2) RETURN VARCHAR2 IS
    e JSON_ELEMENT_T;
  BEGIN
    IF o IS NULL OR NOT o.has(k) THEN RETURN NULL; END IF;
    e := o.get(k);
    IF e.is_null THEN RETURN NULL; END IF;
    IF e.is_string THEN RETURN o.get_string(k); END IF;
    RETURN e.to_string;
  END;

  FUNCTION jbool(o JSON_OBJECT_T, k VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    IF o IS NULL OR NOT o.has(k) OR o.get(k).is_null THEN RETURN NULL; END IF;
    RETURN o.get_boolean(k);
  END;

  FUNCTION jobj(a JSON_ARRAY_T, i PLS_INTEGER) RETURN JSON_OBJECT_T IS
  BEGIN
    RETURN TREAT(a.get(i) AS JSON_OBJECT_T);
  END;

  FUNCTION strings(a JSON_ARRAY_T) RETURN t_list IS
    l t_list := t_list();
  BEGIN
    IF a IS NULL THEN RETURN l; END IF;
    FOR i IN 0 .. a.get_size - 1 LOOP
      l.EXTEND; l(l.LAST) := a.get_string(i);
    END LOOP;
    RETURN l;
  END;

  FUNCTION to_json(l t_list) RETURN JSON_ARRAY_T IS
    a JSON_ARRAY_T := JSON_ARRAY_T();
  BEGIN
    FOR i IN 1 .. l.COUNT LOOP a.append(l(i)); END LOOP;
    RETURN a;
  END;

  FUNCTION joined(l t_list, sep VARCHAR2) RETURN VARCHAR2 IS
    r VARCHAR2(32767);
  BEGIN
    FOR i IN 1 .. l.COUNT LOOP r := r || CASE WHEN i > 1 THEN sep END || l(i); END LOOP;
    RETURN r;
  END;

  -- Byte-order sort (associative array keys are kept in binary order under NLS_SORT=BINARY; duplicates are counted).
  FUNCTION sorted(l t_list) RETURN t_list IS
    bag t_bag; k VARCHAR2(32767); r t_list := t_list();
  BEGIN
    FOR i IN 1 .. l.COUNT LOOP
      bag(l(i)) := CASE WHEN bag.EXISTS(l(i)) THEN bag(l(i)) + 1 ELSE 1 END;
    END LOOP;
    k := bag.FIRST;
    WHILE k IS NOT NULL LOOP
      FOR j IN 1 .. bag(k) LOOP r.EXTEND; r(r.LAST) := k; END LOOP;
      k := bag.NEXT(k);
    END LOOP;
    RETURN r;
  END;

  FUNCTION same(e t_list, a t_list) RETURN BOOLEAN IS
  BEGIN
    IF e.COUNT <> a.COUNT THEN RETURN FALSE; END IF;
    FOR i IN 1 .. e.COUNT LOOP
      IF e(i) IS NULL AND a(i) IS NULL THEN CONTINUE; END IF;
      IF e(i) IS NULL OR a(i) IS NULL OR e(i) <> a(i) THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN TRUE;
  END;

  -- Human-readable difference between two lists (only for the detail text; the check itself is same()).
  FUNCTION diff(e t_list, a t_list) RETURN VARCHAR2 IS
    r t_list := t_list(); found BOOLEAN;
  BEGIN
    FOR i IN 1 .. e.COUNT LOOP
      found := FALSE;
      FOR j IN 1 .. a.COUNT LOOP IF a(j) = e(i) THEN found := TRUE; EXIT; END IF; END LOOP;
      IF NOT found THEN r.EXTEND; r(r.LAST) := 'expected ' || e(i); END IF;
    END LOOP;
    FOR j IN 1 .. a.COUNT LOOP
      found := FALSE;
      FOR i IN 1 .. e.COUNT LOOP IF a(j) = e(i) THEN found := TRUE; EXIT; END IF; END LOOP;
      IF NOT found THEN r.EXTEND; r(r.LAST) := 'found ' || a(j); END IF;
    END LOOP;
    IF r.COUNT = 0 THEN RETURN 'same items, different order'; END IF;
    RETURN SUBSTR(joined(sorted(r), '; '), 1, 4000);
  END;

  -- Defaults and index expressions: compare without quotes, parentheses, spaces or case.
  FUNCTION norm(t VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN UPPER(TRANSLATE(t, 'x"''() ' || CHR(9) || CHR(10) || CHR(13), 'x'));
  END;

  -- Canonical cell text for strings: lowercase hex of the UTF-8 bytes (the database character set is AL32UTF8).
  FUNCTION hex_of(v VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN LOWER(RAWTOHEX(UTL_RAW.CAST_TO_RAW(v)));
  END;

  FUNCTION hex_of_clob(c CLOB) RETURN VARCHAR2 IS
    b BLOB; dst INTEGER := 1; src INTEGER := 1; lang INTEGER := DBMS_LOB.DEFAULT_LANG_CTX; warn INTEGER;
    r VARCHAR2(32767); pos INTEGER := 1; n INTEGER;
  BEGIN
    IF DBMS_LOB.GETLENGTH(c) = 0 THEN RETURN NULL; END IF;
    DBMS_LOB.CREATETEMPORARY(b, TRUE);
    DBMS_LOB.CONVERTTOBLOB(b, c, DBMS_LOB.LOBMAXSIZE, dst, src, NLS_CHARSET_ID('AL32UTF8'), lang, warn);
    n := DBMS_LOB.GETLENGTH(b);
    WHILE pos <= n LOOP
      r := r || LOWER(RAWTOHEX(DBMS_LOB.SUBSTR(b, 8000, pos)));   -- VALUE_ERROR past 32767: reported as a table failure
      pos := pos + 8000;
    END LOOP;
    DBMS_LOB.FREETEMPORARY(b);
    RETURN r;
  END;

  -- Row count and canonical content hash of one table, built from the metadata's column list. Canonical form (defined by the
  -- export, independent of any database): cells joined by | in column order; NULL ~; i:<decimal>, b:1|0,
  -- t:yyyy-MM-dd HH:mm:ss.fff, s:<hex of UTF-8>; rows sorted by their own text in byte order, joined by LF; SHA-256.
  PROCEDURE table_hash(p_t JSON_OBJECT_T, p_n OUT NUMBER, p_h OUT VARCHAR2) IS
    cols JSON_ARRAY_T := p_t.get_array('columns');
    col JSON_OBJECT_T; cn VARCHAR2(130); kind VARCHAR2(30); sel VARCHAR2(32767);
    TYPE t_txt IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
    kinds t_txt; lobs t_txt;
    cur INTEGER; rc INTEGER; v VARCHAR2(32767); vc CLOB; r_text VARCHAR2(32767); cell VARCHAR2(32767);
    bag t_bag; k VARCHAR2(32767); txt CLOB; is_first BOOLEAN := TRUE;
  BEGIN
    FOR i IN 0 .. cols.get_size - 1 LOOP
      col := jobj(cols, i);
      cn := nm(col.get_string('targetName'));
      kind := col.get_string('kind');
      kinds(i + 1) := kind;
      lobs(i + 1) := CASE WHEN kind = 'string' AND col.get_string('dataType') = 'CLOB' THEN 'Y' ELSE 'N' END;
      sel := sel || CASE WHEN i > 0 THEN ', ' END || CASE kind
        WHEN 'int'      THEN 'TO_CHAR(' || cn || ')'
        WHEN 'bit'      THEN 'CASE WHEN ' || cn || ' THEN ''1'' WHEN NOT ' || cn || ' THEN ''0'' END'
        WHEN 'datetime' THEN 'TO_CHAR(' || cn || ', ''' || c_ts || ''')'
        WHEN 'string'   THEN cn
      END;
      IF kind IS NULL OR kind NOT IN ('int', 'bit', 'datetime', 'string') THEN
        RAISE_APPLICATION_ERROR(-20002, 'column ' || cn || ' has a kind this tool does not handle: ' || kind);
      END IF;
    END LOOP;
    cur := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(cur, 'SELECT ' || sel || ' FROM ' || nm(p_t.get_string('targetName')), DBMS_SQL.NATIVE);
    FOR i IN 1 .. kinds.COUNT LOOP
      IF lobs(i) = 'Y' THEN DBMS_SQL.DEFINE_COLUMN(cur, i, vc); ELSE DBMS_SQL.DEFINE_COLUMN(cur, i, v, 32767); END IF;
    END LOOP;
    rc := DBMS_SQL.EXECUTE(cur);
    p_n := 0;
    WHILE DBMS_SQL.FETCH_ROWS(cur) > 0 LOOP
      p_n := p_n + 1;
      FOR i IN 1 .. kinds.COUNT LOOP
        IF lobs(i) = 'Y' THEN
          DBMS_SQL.COLUMN_VALUE(cur, i, vc);
          cell := CASE WHEN vc IS NULL THEN '~' ELSE 's:' || hex_of_clob(vc) END;
        ELSE
          DBMS_SQL.COLUMN_VALUE(cur, i, v);
          cell := CASE WHEN v IS NULL THEN '~'
                       WHEN kinds(i) = 'int' THEN 'i:' || v
                       WHEN kinds(i) = 'bit' THEN 'b:' || v
                       WHEN kinds(i) = 'datetime' THEN 't:' || v
                       ELSE 's:' || hex_of(v) END;
        END IF;
        r_text := CASE WHEN i = 1 THEN cell ELSE r_text || '|' || cell END;
      END LOOP;
      bag(r_text) := CASE WHEN bag.EXISTS(r_text) THEN bag(r_text) + 1 ELSE 1 END;
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(cur);
    DBMS_LOB.CREATETEMPORARY(txt, TRUE);
    k := bag.FIRST;
    WHILE k IS NOT NULL LOOP
      FOR j IN 1 .. bag(k) LOOP
        IF NOT is_first THEN DBMS_LOB.WRITEAPPEND(txt, 1, CHR(10)); END IF;
        DBMS_LOB.WRITEAPPEND(txt, LENGTH(k), k);
        is_first := FALSE;
      END LOOP;
      k := bag.NEXT(k);
    END LOOP;
    -- An empty table hashes the empty string (DBMS_CRYPTO hashes an empty CLOB to e3b0c442...).
    p_h := LOWER(RAWTOHEX(DBMS_CRYPTO.HASH(txt, DBMS_CRYPTO.HASH_SH256)));
    DBMS_LOB.FREETEMPORARY(txt);
  EXCEPTION WHEN OTHERS THEN
    IF cur IS NOT NULL AND DBMS_SQL.IS_OPEN(cur) THEN DBMS_SQL.CLOSE_CURSOR(cur); END IF;
    RAISE;
  END;

  FUNCTION identity_next(p_table VARCHAR2, p_col VARCHAR2) RETURN NUMBER IS
    n NUMBER;
  BEGIN
    -- LAST_NUMBER is the next value to be issued right after RESTART START WITH (and before any use); once values are
    -- used it is the high-water mark of the cache instead. Read without NEXTVAL, which is never rolled back.
    SELECT s.last_number INTO n
      FROM dba_tab_identity_cols c JOIN dba_sequences s ON s.sequence_owner = c.owner AND s.sequence_name = c.sequence_name
     WHERE c.owner = c_schema AND c.table_name = UPPER(p_table) AND c.column_name = UPPER(p_col);
    RETURN n;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  PROCEDURE out_line(p VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p);
  END;

  -- ---------------------------------------------------------------- 1. environment
  PROCEDURE check_environment IS
    minv NUMBER := NVL(TO_NUMBER(jtxt(g_meta.get_object('meta'), 'minOracleVersion')), 23);
  BEGIN
    SELECT version_full INTO g_version FROM v$instance;
    SELECT banner INTO g_banner FROM v$version WHERE ROWNUM = 1;
    SELECT value INTO g_charset FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';
    SELECT UPPER(value) INTO g_maxstr FROM v$parameter WHERE name = 'max_string_size';
    SELECT UPPER(value) INTO g_lensem FROM v$parameter WHERE name = 'nls_length_semantics';
    chk(TO_NUMBER(REGEXP_SUBSTR(g_version, '^[0-9]+')) >= minv, 'environment', 'Oracle server version is supported',
        'server ' || g_version || ', minimum ' || minv);
    chk(g_charset = 'AL32UTF8', 'environment', 'Database character set is AL32UTF8', g_charset);
    chk(g_maxstr IN ('STANDARD', 'EXTENDED'), 'environment', 'MAX_STRING_SIZE reported',
        g_maxstr || CASE g_maxstr WHEN 'STANDARD' THEN ': a VARCHAR2 value is limited to 4000 bytes'
                                  WHEN 'EXTENDED' THEN ': a VARCHAR2 value may use up to 32767 bytes' END);
    chk(jtxt(g_meta, 'schemaVersion') = '1', 'environment', 'Metadata format is version 1',
        'schemaVersion ' || NVL(jtxt(g_meta, 'schemaVersion'), 'missing'));
  END;

  -- ---------------------------------------------------------------- 2. transfer integrity
  PROCEDURE check_integrity IS
    m JSON_OBJECT_T := g_meta.get_object('meta');
  BEGIN
    chk(c_schema_sha = jtxt(m, 'schemaSha256'), 'integrity', jtxt(m, 'schemaFile') || ' matches the recorded SHA-256',
        'expected ' || SUBSTR(jtxt(m, 'schemaSha256'), 1, 16) || ', found ' || SUBSTR(c_schema_sha, 1, 16));
    chk(c_data_sha = jtxt(m, 'dataSha256'), 'integrity', jtxt(m, 'dataFile') || ' matches the recorded SHA-256',
        'expected ' || SUBSTR(jtxt(m, 'dataSha256'), 1, 16) || ', found ' || SUBSTR(c_data_sha, 1, 16));
  END;

  -- ---------------------------------------------------------------- 3. row counts and content hashes
  PROCEDURE check_contents IS
    t JSON_OBJECT_T; tn VARCHAR2(130); n NUMBER; h VARCHAR2(64); en NUMBER; r JSON_OBJECT_T; err VARCHAR2(4000);
    found_total NUMBER := 0;
  BEGIN
    FOR i IN 0 .. g_tables.get_size - 1 LOOP
      t := jobj(g_tables, i);
      tn := t.get_string('targetName');
      en := TO_NUMBER(jtxt(t, 'rowCount'));
      g_rows_total := g_rows_total + NVL(en, 0);
      n := NULL; h := NULL; err := NULL;
      BEGIN
        table_hash(t, n, h);
      EXCEPTION WHEN OTHERS THEN err := 'could not read the table: ' || SQLERRM;
      END;
      r := JSON_OBJECT_T();
      r.put('sourceName', t.get_string('sourceName'));
      r.put('targetName', tn);
      r.put('expectedRows', en);
      IF n IS NULL THEN r.put_null('actualRows'); ELSE r.put('actualRows', n); END IF;
      r.put('expectedSha256', jtxt(t, 'rowSha256'));
      IF h IS NULL THEN r.put_null('actualSha256'); ELSE r.put('actualSha256', h); END IF;
      g_table_res.append(r);
      IF err IS NOT NULL THEN
        chk(FALSE, 'counts', 'Table ' || tn || ' row count', err);
        chk(FALSE, 'hashes', 'Table ' || tn || ' content hash', err);
        CONTINUE;
      END IF;
      found_total := found_total + n;
      IF n = en AND h = jtxt(t, 'rowSha256') THEN g_rows_ok := g_rows_ok + n; END IF;
      chk(n = en, 'counts', 'Table ' || tn || ' row count', 'expected ' || en || ', found ' || n);
      chk(h = jtxt(t, 'rowSha256'), 'hashes', 'Table ' || tn || ' content hash',
          'expected ' || SUBSTR(jtxt(t, 'rowSha256'), 1, 16) || ', found ' || SUBSTR(h, 1, 16));
    END LOOP;
    chk(found_total = TO_NUMBER(jtxt(g_meta.get_object('expectations'), 'totalRows')), 'counts', 'Total rows across all tables',
        'expected ' || jtxt(g_meta.get_object('expectations'), 'totalRows') || ', found ' || found_total);
  END;

  -- ---------------------------------------------------------------- 4. schema
  PROCEDURE check_schema IS
    t JSON_OBJECT_T; c JSON_OBJECT_T; f JSON_OBJECT_T; ix JSON_OBJECT_T; k JSON_OBJECT_T;
    tn VARCHAR2(130); e t_list; a t_list; keys t_list; dirs t_list; names t_list := t_list(); n NUMBER; expr VARCHAR2(32767);
    PROCEDURE push(l IN OUT NOCOPY t_list, v VARCHAR2) IS BEGIN l.EXTEND; l(l.LAST) := v; END;
  BEGIN
    -- The set of tables: nothing missing, nothing extra.
    e := t_list();
    FOR i IN 0 .. g_tables.get_size - 1 LOOP push(e, jobj(g_tables, i).get_string('targetName')); END LOOP;
    e := sorted(e);
    SELECT LOWER(table_name) BULK COLLECT INTO a FROM dba_tables WHERE owner = c_schema ORDER BY LOWER(table_name);
    chk(same(e, a), 'schema', 'The schema has exactly the expected tables',
        CASE WHEN same(e, a) THEN a.COUNT || ' tables' ELSE diff(e, a) END);

    FOR i IN 0 .. g_tables.get_size - 1 LOOP
      t := jobj(g_tables, i);
      tn := t.get_string('targetName');
      push(names, tn);
      SELECT COUNT(*) INTO n FROM dba_tables WHERE owner = c_schema AND table_name = UPPER(tn);
      IF n = 0 THEN
        chk(FALSE, 'schema', 'Table ' || tn || ' structure', 'table missing');
        CONTINUE;
      END IF;

      -- Columns, in order: name, type, length in characters, precision, scale, nullability, default, identity (BY DEFAULT).
      e := t_list();
      FOR j IN 0 .. t.get_array('columns').get_size - 1 LOOP
        c := jobj(t.get_array('columns'), j);
        push(names, c.get_string('targetName'));
        push(e, c.get_string('targetName') || ' ' || jtxt(c, 'dataType') || ' len=' || jtxt(c, 'maxLength')
               || ' p=' || jtxt(c, 'precision') || ' s=' || jtxt(c, 'scale')
               || CASE WHEN jbool(c, 'nullable') THEN ' null' ELSE ' not-null' END
               || ' default=' || norm(jtxt(c, 'default'))
               || CASE WHEN jbool(c, 'identity') THEN ' identity-by-default' END);
      END LOOP;
      SELECT LOWER(tc.column_name) || ' ' || tc.data_type
             || ' len=' || CASE tc.char_used WHEN 'C' THEN TO_CHAR(tc.char_length) WHEN 'B' THEN tc.data_length || '-bytes' END
             || ' p=' || tc.data_precision || ' s=' || tc.data_scale
             || CASE WHEN tc.nullable = 'Y' THEN ' null' ELSE ' not-null' END
             || ' default=' || CASE WHEN ic.column_name IS NULL THEN
                  UPPER(TRANSLATE(tc.data_default_vc, 'x"''() ' || CHR(9) || CHR(10) || CHR(13), 'x')) END
             || CASE WHEN ic.generation_type = 'BY DEFAULT' THEN ' identity-by-default'
                     WHEN ic.generation_type IS NOT NULL THEN ' identity-' || LOWER(REPLACE(ic.generation_type, ' ', '-')) END
        BULK COLLECT INTO a
        FROM dba_tab_columns tc
        LEFT JOIN dba_tab_identity_cols ic ON ic.owner = tc.owner AND ic.table_name = tc.table_name AND ic.column_name = tc.column_name
       WHERE tc.owner = c_schema AND tc.table_name = UPPER(tn)
       ORDER BY tc.column_id;
      chk(same(e, a), 'schema', 'Table ' || tn || ' columns',
          CASE WHEN same(e, a) THEN a.COUNT || ' columns: names, types, lengths, nullability, defaults, identity' ELSE diff(e, a) END);

      -- Primary key: name pk_<table>, columns in order.
      e := t_list('pk_' || tn || ' (' || joined(strings(t.get_array('primaryKey')), ', ') || ')');
      SELECT LOWER(con.constraint_name) || ' (' || LISTAGG(LOWER(cc.column_name), ', ') WITHIN GROUP (ORDER BY cc.position) || ')'
        BULK COLLECT INTO a
        FROM dba_constraints con JOIN dba_cons_columns cc ON cc.owner = con.owner AND cc.constraint_name = con.constraint_name
       WHERE con.owner = c_schema AND con.table_name = UPPER(tn) AND con.constraint_type = 'P'
       GROUP BY con.constraint_name;
      chk(same(e, a), 'schema', 'Table ' || tn || ' primary key',
          'expected ' || joined(e, '; ') || ', found ' || NVL(joined(a, '; '), 'none'));

      -- Foreign keys: name, columns, referenced table and columns, delete rule (the omitted clause is NO ACTION).
      e := t_list();
      FOR j IN 0 .. t.get_array('foreignKeys').get_size - 1 LOOP
        f := jobj(t.get_array('foreignKeys'), j);
        push(names, f.get_string('targetName'));
        push(e, f.get_string('targetName') || ' (' || joined(strings(f.get_array('columns')), ', ') || ') -> '
               || f.get_string('refTable') || ' (' || joined(strings(f.get_array('refColumns')), ', ') || ') on delete '
               || f.get_string('onDelete'));
      END LOOP;
      e := sorted(e);
      SELECT LOWER(con.constraint_name) || ' ('
             || (SELECT LISTAGG(LOWER(cc.column_name), ', ') WITHIN GROUP (ORDER BY cc.position) FROM dba_cons_columns cc
                  WHERE cc.owner = con.owner AND cc.constraint_name = con.constraint_name) || ') -> '
             || LOWER(rc.table_name) || ' ('
             || (SELECT LISTAGG(LOWER(cc.column_name), ', ') WITHIN GROUP (ORDER BY cc.position) FROM dba_cons_columns cc
                  WHERE cc.owner = rc.owner AND cc.constraint_name = rc.constraint_name) || ') on delete ' || con.delete_rule
        BULK COLLECT INTO a
        FROM dba_constraints con JOIN dba_constraints rc ON rc.owner = con.r_owner AND rc.constraint_name = con.r_constraint_name
       WHERE con.owner = c_schema AND con.table_name = UPPER(tn) AND con.constraint_type = 'R'
       ORDER BY 1;
      chk(same(e, a), 'schema', 'Table ' || tn || ' foreign keys',
          CASE WHEN same(e, a) THEN a.COUNT || ' foreign keys: names, columns, targets, delete rules' ELSE diff(e, a) END);

      -- Indexes other than the primary key's and LOB indexes: name, uniqueness, keys (expressions from DBA_IND_EXPRESSIONS),
      -- direction. The metadata's filter is implemented inside the key expression (Oracle has no partial index).
      e := t_list();
      FOR j IN 0 .. t.get_array('indexes').get_size - 1 LOOP
        ix := jobj(t.get_array('indexes'), j);
        push(names, ix.get_string('targetName'));
        keys := t_list(); dirs := t_list();
        FOR q IN 0 .. ix.get_array('columns').get_size - 1 LOOP
          k := jobj(ix.get_array('columns'), q);
          push(keys, norm(NVL(jtxt(k, 'expression'), jtxt(k, 'column'))));
          push(dirs, CASE WHEN jbool(k, 'descending') THEN 'DESC' ELSE 'ASC' END);
        END LOOP;
        push(e, ix.get_string('targetName') || CASE WHEN jbool(ix, 'unique') THEN ' unique' ELSE ' plain' END
               || ' (' || joined(keys, ', ') || ') ' || joined(dirs, ','));
      END LOOP;
      e := sorted(e);
      a := t_list();
      FOR x IN (SELECT i.owner, i.index_name, i.uniqueness FROM dba_indexes i
                 WHERE i.table_owner = c_schema AND i.table_name = UPPER(tn) AND i.index_type <> 'LOB'
                   AND NOT EXISTS (SELECT 1 FROM dba_constraints p WHERE p.owner = i.table_owner AND p.table_name = i.table_name
                                      AND p.constraint_type = 'P' AND p.index_name = i.index_name)
                 ORDER BY LOWER(i.index_name)) LOOP
        keys := t_list(); dirs := t_list();
        FOR y IN (SELECT column_name, column_position, descend FROM dba_ind_columns
                   WHERE index_owner = x.owner AND index_name = x.index_name ORDER BY column_position) LOOP
          expr := NULL;
          FOR z IN (SELECT column_expression FROM dba_ind_expressions
                     WHERE index_owner = x.owner AND index_name = x.index_name AND column_position = y.column_position) LOOP
            expr := z.column_expression;   -- a LONG, readable in PL/SQL
          END LOOP;
          push(keys, norm(NVL(expr, y.column_name)));
          push(dirs, y.descend);
        END LOOP;
        push(a, LOWER(x.index_name) || CASE WHEN x.uniqueness = 'UNIQUE' THEN ' unique' ELSE ' plain' END
               || ' (' || joined(keys, ', ') || ') ' || joined(dirs, ','));
      END LOOP;
      chk(same(e, a), 'schema', 'Table ' || tn || ' indexes',
          CASE WHEN same(e, a) THEN a.COUNT || ' indexes: names, uniqueness, keys and expressions' ELSE diff(e, a) END);
    END LOOP;

    SELECT COUNT(*) INTO n FROM dba_indexes
     WHERE table_owner = c_schema AND (status NOT IN ('VALID', 'N/A') OR NVL(funcidx_status, 'ENABLED') <> 'ENABLED');
    chk(n = 0, 'schema', 'No unusable or disabled indexes', n || ' unusable or disabled');

    -- Every name in the schema (tables, columns, foreign keys, indexes) is usable unquoted: none is an Oracle reserved word.
    a := t_list();
    FOR i IN 1 .. names.COUNT LOOP
      SELECT COUNT(*) INTO n FROM v$reserved_words WHERE keyword = UPPER(names(i)) AND reserved = 'Y';
      IF n > 0 THEN push(a, names(i)); END IF;
    END LOOP;
    chk(a.COUNT = 0, 'schema', 'No identifier is an Oracle reserved word',
        CASE WHEN a.COUNT = 0 THEN names.COUNT || ' names checked against V$RESERVED_WORDS'
             ELSE 'reserved: ' || joined(sorted(a), ', ') END);
  END;

  -- ---------------------------------------------------------------- 5. business summaries
  -- The Oracle form of the ten summaries (the metadata's sourceSql is SQL Server text, recorded for documentation only and
  -- never executed). Cells joined by |, NULL as the empty string (Oracle's || already treats NULL so), timestamps
  -- yyyy-MM-dd HH:mm:ss.fff; compared as rows sorted in byte order.
  FUNCTION summary_sql(p_name VARCHAR2) RETURN VARCHAR2 IS
    f CONSTANT VARCHAR2(40) := ', ''' || c_ts || ''')';
  BEGIN
    RETURN CASE p_name
      WHEN 'Users by type' THEN
        'SELECT discriminator || ''|'' || COUNT(*) AS r FROM users GROUP BY discriminator'
      WHEN 'Users active vs soft-deleted' THEN
        'SELECT s || ''|'' || COUNT(*) AS r FROM (SELECT CASE WHEN deleted_at IS NULL THEN ''active'' ELSE ''soft-deleted'' END AS s'
        || ' FROM users) GROUP BY s'
      WHEN 'Users per role' THEN
        'SELECT r.name || ''|'' || COUNT(*) AS r FROM user_roles ur JOIN roles r ON r.id = ur.role_id GROUP BY r.name'
      WHEN 'Tickets by state' THEN
        'SELECT TO_CHAR(state) || ''|'' || COUNT(*) AS r FROM tickets GROUP BY state'
      WHEN 'Tickets assigned vs unassigned' THEN
        'SELECT s || ''|'' || COUNT(*) AS r FROM (SELECT CASE WHEN user_id IS NULL THEN ''unassigned'' ELSE ''assigned'' END AS s'
        || ' FROM tickets) GROUP BY s'
      WHEN 'Audit events by action' THEN
        'SELECT TO_CHAR(action) || ''|'' || COUNT(*) AS r FROM audit_logs GROUP BY action'
      WHEN 'Comments per ticket (distribution)' THEN
        'SELECT n || ''|'' || COUNT(*) AS r FROM (SELECT COUNT(*) AS n FROM comments GROUP BY ticket_id) GROUP BY n'
      WHEN 'Comment and commented-ticket totals' THEN
        'SELECT (SELECT COUNT(*) FROM comments) || ''|'' || (SELECT COUNT(DISTINCT ticket_id) FROM comments) AS r FROM dual'
      WHEN 'Ticket date ranges' THEN
        'SELECT TO_CHAR(MIN(submitted_date)' || f || ' || ''|'' || TO_CHAR(MAX(submitted_date)' || f
        || ' || ''|'' || TO_CHAR(MIN(assigned_date)' || f || ' || ''|'' || TO_CHAR(MAX(assigned_date)' || f
        || ' || ''|'' || TO_CHAR(MIN(completed_date)' || f || ' || ''|'' || TO_CHAR(MAX(completed_date)' || f
        || ' AS r FROM tickets'
      WHEN 'Account and audit date ranges' THEN
        'SELECT TO_CHAR((SELECT MIN(created_at) FROM users)' || f || ' || ''|'' || TO_CHAR((SELECT MAX(created_at) FROM users)' || f
        || ' || ''|'' || TO_CHAR((SELECT MIN(timestamp) FROM audit_logs)' || f
        || ' || ''|'' || TO_CHAR((SELECT MAX(timestamp) FROM audit_logs)' || f || ' AS r FROM dual'
    END;
  END;

  PROCEDURE check_summaries IS
    s JSON_OBJECT_T; q VARCHAR2(4000); e t_list; a t_list; err VARCHAR2(4000); r JSON_OBJECT_T;
    known t_list := t_list('Users by type', 'Users active vs soft-deleted', 'Users per role', 'Tickets by state',
                           'Tickets assigned vs unassigned', 'Audit events by action', 'Comments per ticket (distribution)',
                           'Comment and commented-ticket totals', 'Ticket date ranges', 'Account and audit date ranges');
    sums JSON_ARRAY_T := g_meta.get_array('summaries'); found BOOLEAN;
  BEGIN
    FOR i IN 0 .. sums.get_size - 1 LOOP
      s := jobj(sums, i);
      e := strings(s.get_array('expectedRows'));
      q := summary_sql(s.get_string('name'));
      a := NULL; err := NULL;
      IF q IS NULL THEN
        err := 'no Oracle query is defined for this summary';
      ELSE
        BEGIN
          EXECUTE IMMEDIATE 'SELECT r FROM (' || q || ') ORDER BY r' BULK COLLECT INTO a;
        EXCEPTION WHEN OTHERS THEN err := SQLERRM;
        END;
      END IF;
      r := JSON_OBJECT_T();
      r.put('name', s.get_string('name'));
      r.put('expectedRows', s.get_array('expectedRows'));
      IF a IS NULL THEN r.put_null('actualRows'); ELSE r.put('actualRows', to_json(a)); END IF;
      g_summary_res.append(r);
      chk(err IS NULL AND same(e, a), 'summaries', s.get_string('name'),
          CASE WHEN err IS NOT NULL THEN err
               WHEN same(e, a) THEN joined(a, ', ')
               ELSE 'expected [' || joined(e, ', ') || '], found [' || joined(a, ', ') || ']' END);
    END LOOP;
    FOR i IN 1 .. known.COUNT LOOP
      found := FALSE;
      FOR j IN 0 .. sums.get_size - 1 LOOP
        IF jobj(sums, j).get_string('name') = known(i) THEN found := TRUE; END IF;
      END LOOP;
      IF NOT found THEN chk(FALSE, 'summaries', known(i), 'defined here but not recorded in the metadata'); END IF;
    END LOOP;
  END;

  -- ---------------------------------------------------------------- 6. sanitization and expectations
  PROCEDURE check_sanitization IS
    x JSON_OBJECT_T := g_meta.get_object('expectations');
    n NUMBER; bad NUMBER; dups NUMBER;
  BEGIN
    chk(jbool(g_meta.get_object('meta'), 'sanitizeCredentials'), 'sanitization', 'The export was made with credentials sanitized',
        'sanitizeCredentials = ' || NVL(jtxt(g_meta.get_object('meta'), 'sanitizeCredentials'), 'missing'));
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*), COUNT(CASE WHEN password_hash IS NOT NULL OR security_stamp IS NOT NULL'
        || ' OR must_reset_password IS NULL OR NOT must_reset_password THEN 1 END) FROM users' INTO n, bad;
      chk(n = TO_NUMBER(jtxt(x, 'usersCount')), 'sanitization', 'User count',
          'expected ' || jtxt(x, 'usersCount') || ', found ' || n);
      chk(bad = 0 AND jbool(x, 'usersSanitized'), 'sanitization',
          'Every user has no password hash or security stamp and must reset the password', bad || ' of ' || n || ' users not sanitized');
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (SELECT LOWER(name) FROM users WHERE deleted_at IS NULL'
        || ' GROUP BY LOWER(name) HAVING COUNT(*) > 1)' INTO dups;
      chk((dups = 0) = jbool(x, 'noDuplicateActiveUsernamesIgnoringCase'), 'sanitization',
          'No two active usernames differ only by case', dups || ' duplicates');
    EXCEPTION WHEN OTHERS THEN
      chk(FALSE, 'sanitization', 'Users table readable for the sanitization checks', SQLERRM);
    END;
  END;

  -- ---------------------------------------------------------------- 7. rules
  -- 7a. Identity sequences continue after the loaded ids. Checked first, without NEXTVAL, so nothing is consumed.
  PROCEDURE check_sequences IS
    t JSON_OBJECT_T; c JSON_OBJECT_T; idcol VARCHAR2(130); expected NUMBER; nxt NUMBER; tn VARCHAR2(130);
  BEGIN
    FOR i IN 0 .. g_tables.get_size - 1 LOOP
      t := jobj(g_tables, i);
      tn := t.get_string('targetName');
      idcol := NULL;
      FOR j IN 0 .. t.get_array('columns').get_size - 1 LOOP
        c := jobj(t.get_array('columns'), j);
        IF jbool(c, 'identity') THEN idcol := c.get_string('targetName'); EXIT; END IF;
      END LOOP;
      CONTINUE WHEN idcol IS NULL;
      -- An empty table has no identityLast: its identity was never restarted and starts at 1.
      expected := NVL(TO_NUMBER(jtxt(t, 'identityLast')), 0) + 1;
      nxt := identity_next(tn, idcol);
      IF nxt IS NOT NULL THEN g_seq(tn) := nxt; END IF;
      chk(nxt = expected, 'rules', 'New ' || tn || ' ids continue after the loaded ones',
          'next value ' || NVL(TO_CHAR(nxt), 'missing (no identity column)') || ', expected ' || expected);
    END LOOP;
  END;

  -- 7b. Behaviour tests, each between SAVEPOINT and ROLLBACK TO, with explicit ids far above the data.
  PROCEDURE check_behaviour IS
    u_id NUMBER; uname VARCHAR2(4000); tid NUMBER; outcome VARCHAR2(4000); got VARCHAR2(4000); v VARCHAR2(32767);
    c_ts0 CONSTANT VARCHAR2(40) := 'TIMESTAMP ''2026-01-01 00:00:00.000''';
    -- Built with the export's literal form: quote doubling, CHR(n) for control characters, UNISTR for non-ASCII (the emoji as
    -- a UTF-16 surrogate pair). Expected bytes written out independently: a, quote, b, backslash, c, ampersand, d, TAB, CR, LF, e, U+00E9, U+1F600.
    c_awkward_sql CONSTANT VARCHAR2(400) := '''a''''b\c'' || CHR(38) || ''d'' || CHR(9) || CHR(13) || CHR(10) || ''e'''
                                            || ' || UNISTR(''\00E9'') || UNISTR(''\D83D\DE00'')';
    c_awkward_hex CONSTANT VARCHAR2(100) := '6127625c632664090d0a65c3a9f09f9880';
    FUNCTION code(p NUMBER) RETURN VARCHAR2 IS BEGIN RETURN 'rejected (ORA-' || LPAD(-p, 5, '0') || ')'; END;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE 'SELECT id, name FROM users WHERE deleted_at IS NULL AND name <> UPPER(name) ORDER BY id'
        || ' FETCH FIRST 1 ROW ONLY' INTO u_id, uname;
      EXECUTE IMMEDIATE 'SELECT MIN(id) FROM tickets' INTO tid;
    EXCEPTION WHEN OTHERS THEN u_id := NULL;
    END;

    -- A second active user whose name differs only by case is rejected (function-based unique index).
    outcome := NULL;
    IF u_id IS NOT NULL THEN
      SAVEPOINT sp_rule;
      BEGIN
        EXECUTE IMMEDIATE 'INSERT INTO users (id, name, created_at, discriminator) VALUES (:1, :2, ' || c_ts0 || ', ''Customer'')'
          USING c_test_id, UPPER(uname);
        outcome := 'accepted';
      EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
      END;
      ROLLBACK TO sp_rule;
    END IF;
    chk(outcome = 'rejected (ORA-00001)', 'rules', 'A second active user differing only by case is rejected',
        'inserting ''' || UPPER(uname) || ''' while ''' || uname || ''' is active: ' || NVL(outcome, 'no user to test with'));

    -- A soft-deleted username can be reused.
    outcome := NULL;
    IF u_id IS NOT NULL THEN
      SAVEPOINT sp_rule;
      BEGIN
        EXECUTE IMMEDIATE 'UPDATE users SET deleted_at = ' || c_ts0 || ' WHERE id = :1' USING u_id;
        EXECUTE IMMEDIATE 'INSERT INTO users (id, name, created_at, discriminator) VALUES (:1, :2, ' || c_ts0 || ', ''Customer'')'
          USING c_test_id + 1, uname;
        outcome := 'accepted';
      EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
      END;
      ROLLBACK TO sp_rule;
    END IF;
    chk(outcome = 'accepted', 'rules', 'A soft-deleted username can be reused',
        '''' || uname || ''' soft-deleted, then inserted again: ' || NVL(outcome, 'no user to test with'));

    -- Two soft-deleted users may share a name (a B-tree index stores no all-NULL key, so they are absent from it).
    outcome := NULL;
    SAVEPOINT sp_rule;
    BEGIN
      FOR i IN 2 .. 3 LOOP
        EXECUTE IMMEDIATE 'INSERT INTO users (id, name, created_at, discriminator, deleted_at) VALUES (:1, ''rule-test'', '
          || c_ts0 || ', ''Customer'', ' || c_ts0 || ')' USING c_test_id + i;
      END LOOP;
      outcome := 'accepted';
    EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
    END;
    ROLLBACK TO sp_rule;
    chk(outcome = 'accepted', 'rules', 'Two soft-deleted users may share a name', 'two soft-deleted ''rule-test'' users: ' || outcome);

    -- A comment pointing at a user and ticket that do not exist is rejected.
    outcome := NULL;
    SAVEPOINT sp_rule;
    BEGIN
      EXECUTE IMMEDIATE 'INSERT INTO comments (id, user_id, ticket_id, text, created_at) VALUES (:1, 999999999, 999999999,'
        || ' ''orphan'', ' || c_ts0 || ')' USING c_test_id + 4;
      outcome := 'accepted';
    EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
    END;
    ROLLBACK TO sp_rule;
    chk(outcome = 'rejected (ORA-02291)', 'rules', 'A comment with a non-existent user and ticket is rejected', outcome);

    -- A BOOLEAN column rejects a value that is not a boolean ('maybe'; numbers and 'yes'/'no' are converted, not rejected).
    outcome := NULL;
    IF u_id IS NOT NULL THEN
      SAVEPOINT sp_rule;
      BEGIN
        EXECUTE IMMEDIATE 'UPDATE users SET email_confirmed = ''maybe'' WHERE id = :1' USING u_id;
        outcome := 'accepted';
      EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
      END;
      ROLLBACK TO sp_rule;
    END IF;
    chk(outcome = 'rejected (ORA-61800)', 'rules', 'A BOOLEAN column rejects a value that is not a boolean',
        'setting email_confirmed to ''maybe'': ' || NVL(outcome, 'no user to test with'));

    -- Text written in the export's literal form comes back byte for byte.
    outcome := NULL; got := NULL;
    IF u_id IS NOT NULL AND tid IS NOT NULL THEN
      SAVEPOINT sp_rule;
      BEGIN
        EXECUTE IMMEDIATE 'INSERT INTO comments (id, user_id, ticket_id, text, created_at) VALUES (:1, :2, :3, ' || c_awkward_sql
          || ', ' || c_ts0 || ')' USING c_test_id + 5, u_id, tid;
        EXECUTE IMMEDIATE 'SELECT text FROM comments WHERE id = :1' INTO v USING c_test_id + 5;
        got := hex_of(v);
        outcome := CASE WHEN got = c_awkward_hex THEN 'identical' ELSE 'different' END;
      EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
      END;
      ROLLBACK TO sp_rule;
    END IF;
    chk(outcome = 'identical', 'rules', 'Quote, backslash, ampersand, control characters, accent and emoji round-trip',
        'CHR/UNISTR literal stored and read back: ' || NVL(outcome, 'no user or ticket to test with')
        || CASE WHEN outcome = 'different' THEN ' (hex ' || got || ')' END);

    -- VARCHAR2(n CHAR) holds n characters within the byte limit: 2,000 two-byte characters (4,000 bytes) fit in comments.text;
    -- 1,334 three-byte characters (4,002 bytes) are rejected unless MAX_STRING_SIZE = EXTENDED.
    outcome := NULL; got := NULL;
    IF u_id IS NOT NULL AND tid IS NOT NULL THEN
      SAVEPOINT sp_rule;
      BEGIN
        v := NULL;
        FOR i IN 1 .. 2000 LOOP v := v || UNISTR('\00E9'); END LOOP;   -- built in PL/SQL: RPAD would cut silently at 4000 bytes
        EXECUTE IMMEDIATE 'INSERT INTO comments (id, user_id, ticket_id, text, created_at) VALUES (:1, :2, :3, :4, ' || c_ts0 || ')'
          USING c_test_id + 6, u_id, tid, v;
        outcome := 'accepted';
      EXCEPTION WHEN OTHERS THEN outcome := code(SQLCODE);
      END;
      BEGIN
        v := NULL;
        FOR i IN 1 .. 1334 LOOP v := v || UNISTR('\20AC'); END LOOP;
        EXECUTE IMMEDIATE 'INSERT INTO comments (id, user_id, ticket_id, text, created_at) VALUES (:1, :2, :3, :4, ' || c_ts0 || ')'
          USING c_test_id + 7, u_id, tid, v;
        got := 'accepted';
      EXCEPTION WHEN OTHERS THEN got := code(SQLCODE);
      END;
      ROLLBACK TO sp_rule;
    END IF;
    chk(outcome = 'accepted' AND got = CASE WHEN g_maxstr = 'EXTENDED' THEN 'accepted' ELSE 'rejected (ORA-12899)' END, 'rules',
        'Text columns hold their length in characters up to the byte limit',
        '2,000 two-byte characters (4,000 bytes) in comments.text: ' || NVL(outcome, 'no user or ticket to test with')
        || '; 1,334 three-byte characters (4,002 bytes): ' || NVL(got, 'not tested') || ' (MAX_STRING_SIZE ' || g_maxstr || ')');
  END;

  -- 7c. The rule tests left nothing behind: no test rows, and no identity sequence moved.
  PROCEDURE check_leftovers IS
    n1 NUMBER; n2 NUMBER; moved NUMBER := 0; t JSON_OBJECT_T; c JSON_OBJECT_T; tn VARCHAR2(130);
  BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE id >= :1' INTO n1 USING c_test_id - 1;
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM comments WHERE id >= :1' INTO n2 USING c_test_id - 1;
    FOR i IN 0 .. g_tables.get_size - 1 LOOP
      t := jobj(g_tables, i);
      tn := t.get_string('targetName');
      CONTINUE WHEN NOT g_seq.EXISTS(tn);
      FOR j IN 0 .. t.get_array('columns').get_size - 1 LOOP
        c := jobj(t.get_array('columns'), j);
        IF jbool(c, 'identity') AND NVL(identity_next(tn, c.get_string('targetName')), -1) <> g_seq(tn) THEN
          moved := moved + 1;
        END IF;
      END LOOP;
    END LOOP;
    chk(n1 + n2 = 0 AND moved = 0, 'rules', 'The rule tests left the database unchanged',
        (n1 + n2) || ' test rows left, ' || moved || ' sequences moved');
  EXCEPTION WHEN OTHERS THEN
    chk(FALSE, 'rules', 'The rule tests left the database unchanged', SQLERRM);
  END;

  -- ---------------------------------------------------------------- output
  PROCEDURE output IS
    o JSON_OBJECT_T := JSON_OBJECT_T(); env JSON_OBJECT_T := JSON_OBJECT_T(); run JSON_OBJECT_T := JSON_OBJECT_T();
    m JSON_OBJECT_T := g_meta.get_object('meta'); inp JSON_ARRAY_T := JSON_ARRAY_T(); f JSON_OBJECT_T;
    chks JSON_ARRAY_T := JSON_ARRAY_T(); c JSON_OBJECT_T; model JSON_ARRAY_T := JSON_ARRAY_T(); t JSON_OBJECT_T; mt JSON_OBJECT_T;
    passed NUMBER := 0; raw_json CLOB; pretty CLOB; pos INTEGER := 1; nl INTEGER; len INTEGER;
  BEGIN
    FOR i IN 1 .. g_checks.COUNT LOOP
      IF g_checks(i).status = 'PASS' THEN passed := passed + 1; END IF;
      out_line(g_checks(i).status || CHR(9) || g_checks(i).category || CHR(9) || g_checks(i).name || CHR(9)
               || REPLACE(REPLACE(g_checks(i).detail, CHR(9), ' '), CHR(10), ' '));
      c := JSON_OBJECT_T();
      c.put('seq', i); c.put('status', g_checks(i).status); c.put('category', g_checks(i).category);
      c.put('name', g_checks(i).name); c.put('detail', NVL(g_checks(i).detail, ''));
      chks.append(c);
    END LOOP;
    out_line('SUMMARY' || CHR(9) || passed || CHR(9) || g_checks.COUNT || CHR(9) || g_rows_ok || CHR(9) || g_rows_total);

    o.put('schemaVersion', 1);
    o.put('tool', 'import-oracle');
    o.put('status', CASE WHEN passed = g_checks.COUNT THEN 'PASS' ELSE 'FAIL' END);
    o.put('checksPassed', passed);
    o.put('checksTotal', g_checks.COUNT);
    o.put('rowsVerified', g_rows_ok);
    o.put('rowsTotal', g_rows_total);
    o.put('database', LOWER(c_pdb));
    env.put('serverVersion', g_version);
    env.put('banner', g_banner);
    env.put('characterSet', g_charset);
    env.put('maxStringSize', g_maxstr);
    env.put('lengthSemantics', g_lensem);
    env.put('image', '&v_image');
    env.put('container', '&v_container');
    env.put('pluggableDatabase', LOWER(c_pdb));
    env.put('schema', LOWER(c_schema));
    o.put('environment', env);
    run.put('runTimeUtc', '&v_run_time');
    run.put('toolGitCommit', '&v_tool_commit');
    o.put('run', run);
    o.put('source', m.get_object('source'));
    o.put('sourceExport', g_meta.get_object('run'));
    f := JSON_OBJECT_T(); f.put('file', jtxt(m, 'schemaFile')); f.put('expectedSha256', jtxt(m, 'schemaSha256'));
    f.put('actualSha256', c_schema_sha); inp.append(f);
    f := JSON_OBJECT_T(); f.put('file', jtxt(m, 'dataFile')); f.put('expectedSha256', jtxt(m, 'dataSha256'));
    f.put('actualSha256', c_data_sha); inp.append(f);
    o.put('inputs', inp);
    o.put('tables', g_table_res);
    o.put('summaries', g_summary_res);
    o.put('checks', chks);
    FOR i IN 0 .. g_tables.get_size - 1 LOOP
      t := jobj(g_tables, i);
      mt := JSON_OBJECT_T();
      mt.put('sourceName', t.get_string('sourceName')); mt.put('targetName', t.get_string('targetName'));
      mt.put('columns', t.get_array('columns')); mt.put('primaryKey', t.get_array('primaryKey'));
      mt.put('foreignKeys', t.get_array('foreignKeys')); mt.put('indexes', t.get_array('indexes'));
      model.append(mt);
    END LOOP;
    o.put('schemaModel', model);
    o.put('knownDifferences', g_meta.get_array('knownDifferences'));
    o.put('excludedTables', g_meta.get_array('excludedTables'));

    raw_json := o.to_clob;
    SELECT JSON_SERIALIZE(raw_json RETURNING CLOB PRETTY) INTO pretty FROM dual;
    out_line('JSON-BEGIN');
    len := DBMS_LOB.GETLENGTH(pretty);
    WHILE pos <= len LOOP
      nl := DBMS_LOB.INSTR(pretty, CHR(10), pos);
      IF nl = 0 THEN nl := len + 1; END IF;
      out_line(DBMS_LOB.SUBSTR(pretty, nl - pos, pos));
      pos := nl + 1;
    END LOOP;
    out_line('JSON-END');
  END;

BEGIN
  g_meta := JSON_OBJECT_T.parse(read_file('source-metadata.json'));
  g_tables := g_meta.get_array('tables');

  -- Each group records a FAIL instead of stopping the run when something is missing or broken.
  BEGIN check_environment; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'environment', 'Environment readable', SQLERRM); END;
  BEGIN check_integrity; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'integrity', 'Integrity checks ran', SQLERRM); END;
  BEGIN check_contents; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'counts', 'Row counts and hashes ran', SQLERRM); END;
  BEGIN check_schema; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'schema', 'Schema checks ran', SQLERRM); END;
  BEGIN check_summaries; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'summaries', 'Summary checks ran', SQLERRM); END;
  BEGIN check_sanitization; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'sanitization', 'Sanitization checks ran', SQLERRM); END;
  BEGIN check_sequences; EXCEPTION WHEN OTHERS THEN chk(FALSE, 'rules', 'Sequence checks ran', SQLERRM); END;
  BEGIN check_behaviour; EXCEPTION WHEN OTHERS THEN ROLLBACK; chk(FALSE, 'rules', 'Rule tests ran', SQLERRM); END;
  check_leftovers;
  ROLLBACK;
  output;
END;
/

ROLLBACK;
DROP DIRECTORY mar_verify_dir;
EXIT SUCCESS ROLLBACK
