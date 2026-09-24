-- import-oracle report: renders MigrationVerificationReport.html from verification-results.json and selftest-results.json (or
-- null), both copied by `ingest.sh report` into /tmp/marreport in the container. Run there as SYS in the container database's root:
-- PL/SQL is only the template engine; the migrated data is never read. The page is printed between the lines HTML-BEGIN and
-- HTML-END, which ingest.sh writes to docs/phase1/dbmigrate/import-oracle/. Deterministic: the same JSON always gives a
-- byte-identical page (the run time shown is the one recorded in the JSON).

SET DEFINE OFF
SET VERIFY OFF FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 32767 TRIMOUT ON TRIMSPOOL ON TAB OFF ECHO OFF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
CREATE OR REPLACE DIRECTORY mar_report_dir AS '/tmp/marreport';
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED

DECLARE
  r      JSON_OBJECT_T;      -- verification results
  s      JSON_OBJECT_T;      -- self-test results, NULL when not run
  checks JSON_ARRAY_T;
  page   CLOB;

  -- ---------------------------------------------------------------- helpers
  FUNCTION read_file(p_name VARCHAR2) RETURN CLOB IS
    b BFILE := BFILENAME('MAR_REPORT_DIR', p_name);
    c CLOB; dst INTEGER := 1; src INTEGER := 1; lang INTEGER := DBMS_LOB.DEFAULT_LANG_CTX; warn INTEGER;
  BEGIN
    DBMS_LOB.CREATETEMPORARY(c, TRUE);
    DBMS_LOB.FILEOPEN(b, DBMS_LOB.FILE_READONLY);
    DBMS_LOB.LOADCLOBFROMFILE(c, b, DBMS_LOB.LOBMAXSIZE, dst, src, NLS_CHARSET_ID('AL32UTF8'), lang, warn);
    DBMS_LOB.FILECLOSE(b);
    RETURN c;
  END;

  PROCEDURE w(t VARCHAR2) IS
  BEGIN
    IF t IS NOT NULL THEN DBMS_LOB.WRITEAPPEND(page, LENGTH(t), t); END IF;
  END;

  FUNCTION h(t VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(t, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
  END;

  FUNCTION jtxt(o JSON_OBJECT_T, k VARCHAR2) RETURN VARCHAR2 IS
    e JSON_ELEMENT_T;
  BEGIN
    IF o IS NULL OR NOT o.has(k) THEN RETURN NULL; END IF;
    e := o.get(k);
    IF e.is_null THEN RETURN NULL; END IF;
    IF e.is_string THEN RETURN o.get_string(k); END IF;
    RETURN e.to_string;
  END;

  FUNCTION jobj(a JSON_ARRAY_T, i PLS_INTEGER) RETURN JSON_OBJECT_T IS
  BEGIN
    RETURN TREAT(a.get(i) AS JSON_OBJECT_T);
  END;

  FUNCTION jarr(o JSON_OBJECT_T, k VARCHAR2) RETURN JSON_ARRAY_T IS
  BEGIN
    IF o IS NULL OR NOT o.has(k) OR NOT o.get(k).is_array THEN RETURN JSON_ARRAY_T(); END IF;
    RETURN o.get_array(k);
  END;

  FUNCTION jlist(a JSON_ARRAY_T, sep VARCHAR2, esc BOOLEAN := TRUE) RETURN VARCHAR2 IS
    t VARCHAR2(32767);
  BEGIN
    FOR i IN 0 .. a.get_size - 1 LOOP
      t := t || CASE WHEN i > 0 THEN sep END || CASE WHEN esc THEN h(a.get_string(i)) ELSE a.get_string(i) END;
    END LOOP;
    RETURN t;
  END;

  FUNCTION badge(status VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF status = 'PASS' THEN RETURN '<span class="badge pass">PASS</span>'; END IF;
    RETURN '<span class="badge fail">' || h(NVL(status, 'FAIL')) || '</span>';
  END;

  -- Overall status of the checks of a category whose name starts with a prefix.
  FUNCTION group_status(cat VARCHAR2, prefix VARCHAR2) RETURN VARCHAR2 IS
    c JSON_OBJECT_T; n PLS_INTEGER := 0; ok BOOLEAN := TRUE;
  BEGIN
    FOR i IN 0 .. checks.get_size - 1 LOOP
      c := jobj(checks, i);
      IF c.get_string('category') = cat AND SUBSTR(c.get_string('name'), 1, LENGTH(prefix)) = prefix THEN
        n := n + 1;
        IF c.get_string('status') <> 'PASS' THEN ok := FALSE; END IF;
      END IF;
    END LOOP;
    RETURN CASE WHEN n = 0 THEN 'N/A' WHEN ok THEN 'PASS' ELSE 'FAIL' END;
  END;

  PROCEDURE checks_table(cat VARCHAR2) IS
    c JSON_OBJECT_T;
  BEGIN
    w('<div class="scroll"><table><thead><tr><th scope="col">Check</th><th scope="col">Detail</th><th scope="col">Result</th></tr></thead><tbody>' || CHR(10));
    FOR i IN 0 .. checks.get_size - 1 LOOP
      c := jobj(checks, i);
      IF c.get_string('category') = cat THEN
        w('<tr><td>' || h(c.get_string('name')) || '</td><td class="detail">' || h(c.get_string('detail')) || '</td><td>'
          || badge(c.get_string('status')) || '</td></tr>' || CHR(10));
      END IF;
    END LOOP;
    w('</tbody></table></div>' || CHR(10));
  END;

  FUNCTION category_text(cat VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE cat
      WHEN 'environment' THEN 'The Oracle server is version 23 or later and uses AL32UTF8; MAX_STRING_SIZE is recorded; the metadata format is the expected one.'
      WHEN 'integrity' THEN 'The two SQL files are byte-for-byte the ones the metadata was recorded for (SHA-256).'
      WHEN 'counts' THEN 'Every table has exactly the number of rows the source had.'
      WHEN 'hashes' THEN 'Every table''s full contents, in a canonical text form, hash to the same SHA-256 as the source.'
      WHEN 'schema' THEN 'Tables, columns, types, nullability, defaults, identity columns, keys, foreign keys and indexes match; no name is a reserved word.'
      WHEN 'summaries' THEN 'Ten business questions give the same answers as on the source.'
      WHEN 'sanitization' THEN 'No user has a password hash or security stamp; every user must reset the password.'
      WHEN 'rules' THEN 'Database rules behave as in the legacy system (each test is rolled back to a savepoint).'
    END;
  END;

  -- One business summary: a bar chart when every row is "label|count", else the expected and found rows side by side.
  PROCEDURE summary_block(sm JSON_OBJECT_T) IS
    rows_a JSON_ARRAY_T; e JSON_ARRAY_T := jarr(sm, 'expectedRows'); a JSON_ARRAY_T := jarr(sm, 'actualRows');
    v VARCHAR2(4000); lbl VARCHAR2(4000); num NUMBER; mx NUMBER := 0; bars BOOLEAN := TRUE; status VARCHAR2(10); detail VARCHAR2(4000);
    c JSON_OBJECT_T; n PLS_INTEGER;
  BEGIN
    rows_a := CASE WHEN sm.has('actualRows') AND sm.get('actualRows').is_array THEN a ELSE e END;
    FOR i IN 0 .. checks.get_size - 1 LOOP
      c := jobj(checks, i);
      IF c.get_string('category') = 'summaries' AND c.get_string('name') = sm.get_string('name') THEN
        status := c.get_string('status'); detail := c.get_string('detail'); EXIT;
      END IF;
    END LOOP;
    IF rows_a.get_size = 0 THEN bars := FALSE; END IF;
    FOR i IN 0 .. rows_a.get_size - 1 LOOP
      v := rows_a.get_string(i);
      IF NOT REGEXP_LIKE(v, '^[^|]*\|[0-9]+$') THEN bars := FALSE; EXIT; END IF;
      mx := GREATEST(mx, TO_NUMBER(SUBSTR(v, INSTR(v, '|') + 1)));
    END LOOP;
    w('<div class="summary"><h3>' || h(sm.get_string('name')) || ' ' || badge(status) || '</h3>' || CHR(10));
    IF bars THEN
      w('<ul class="bars">' || CHR(10));
      FOR i IN 0 .. rows_a.get_size - 1 LOOP
        v := rows_a.get_string(i);
        lbl := SUBSTR(v, 1, INSTR(v, '|') - 1);
        num := TO_NUMBER(SUBSTR(v, INSTR(v, '|') + 1));
        w('<li><span class="bl">' || h(NVL(lbl, '(none)')) || '</span><span class="bt" aria-hidden="true"><span class="bf" style="width:'
          || CASE WHEN mx > 0 THEN TO_CHAR(ROUND(100 * num / mx, 1), 'FM990.0') ELSE '0' END || '%"></span></span><span class="bv">'
          || num || '</span></li>' || CHR(10));
      END LOOP;
      w('</ul>' || CHR(10));
    ELSE
      w('<div class="scroll"><table><thead><tr><th scope="col">Expected (SQL Server)</th><th scope="col">Found (Oracle)</th></tr></thead><tbody>' || CHR(10));
      n := GREATEST(e.get_size, a.get_size);
      FOR i IN 0 .. n - 1 LOOP
        w('<tr><td><code>' || CASE WHEN i < e.get_size THEN h(e.get_string(i)) END || '</code></td><td><code>'
          || CASE WHEN i < a.get_size THEN h(a.get_string(i)) END || '</code></td></tr>' || CHR(10));
      END LOOP;
      w('</tbody></table></div>' || CHR(10));
    END IF;
    w(CASE sm.get_string('name')
        WHEN 'Tickets by state' THEN '<p class="note">States are the legacy workflow codes: 0 = SUBMITTED, 1 = INPROGRESS, 2 = COMPLETED.</p>'
        WHEN 'Audit events by action' THEN '<p class="note">Actions are the numeric codes stored by the legacy application.</p>'
        WHEN 'Comments per ticket (distribution)' THEN '<p class="note">Label = comments on a ticket; value = number of tickets with that many comments.</p>'
        WHEN 'Ticket date ranges' THEN '<p class="note">Earliest and latest submitted, assigned and completed dates.</p>'
        WHEN 'Account and audit date ranges' THEN '<p class="note">Earliest and latest account creation and audit event.</p>'
      END);
    w(CASE WHEN status = 'PASS' THEN '<p class="match">Identical to the source.</p>'
           ELSE '<p class="mismatch">' || h(detail) || '</p>' END || '</div>' || CHR(10));
  END;

  PROCEDURE print_page IS
    pos INTEGER := 1; nl INTEGER; len INTEGER := DBMS_LOB.GETLENGTH(page);
  BEGIN
    DBMS_OUTPUT.PUT_LINE('HTML-BEGIN');
    WHILE pos <= len LOOP
      nl := DBMS_LOB.INSTR(page, CHR(10), pos);
      IF nl = 0 THEN nl := len + 1; END IF;
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(page, nl - pos, pos));
      pos := nl + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('HTML-END');
  END;

  -- ---------------------------------------------------------------- sections
  PROCEDURE head_and_summary IS
    env JSON_OBJECT_T := r.get_object('environment'); pass BOOLEAN := r.get_string('status') = 'PASS';
    st VARCHAR2(200);
  BEGIN
    st := CASE WHEN s IS NOT NULL THEN jtxt(s, 'passed') || ' / ' || jtxt(s, 'total') ELSE 'not run' END;
    w('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Oracle Migration Verification</title>
<style>
:root { --bg:#f7f7f5; --surface:#ffffff; --text:#1c1c1a; --muted:#5b5b57; --border:#d9d9d4; --accent:#2f5d8a;
  --pass:#1f6b3a; --pass-bg:#e3f1e7; --fail:#9b1c1c; --fail-bg:#fbe4e4; --bar:#2f5d8a; --track:#e8e8e3; --code-bg:#f0f0ec; }
' || CHR(64) || 'media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#161615; --surface:#1f1f1d; --text:#ececea;
  --muted:#a8a8a2; --border:#3a3a37; --accent:#8db6e0; --pass:#8fd4a6; --pass-bg:#1d3526; --fail:#f2a3a3; --fail-bg:#3d1f1f;
  --bar:#8db6e0; --track:#2c2c2a; --code-bg:#2a2a27; } }
:root[data-theme="dark"] { --bg:#161615; --surface:#1f1f1d; --text:#ececea; --muted:#a8a8a2; --border:#3a3a37; --accent:#8db6e0;
  --pass:#8fd4a6; --pass-bg:#1d3526; --fail:#f2a3a3; --fail-bg:#3d1f1f; --bar:#8db6e0; --track:#2c2c2a; --code-bg:#2a2a27; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width:980px; margin:0 auto; padding:32px 16px 64px; }
h1 { font-size:1.9rem; line-height:1.2; margin:.2rem 0 .4rem; }
h2 { font-size:1.35rem; margin:2.4rem 0 .6rem; padding-top:.6rem; border-top:1px solid var(--border); }
h3 { font-size:1.05rem; margin:1.4rem 0 .5rem; display:flex; gap:.6rem; align-items:center; flex-wrap:wrap; }
p, li { max-width:72ch; }
.eyebrow { color:var(--muted); font-size:.85rem; letter-spacing:.04em; text-transform:uppercase; margin:0; }
.lede { color:var(--muted); margin-top:0; }
.banner { border-radius:10px; padding:16px 20px; margin:20px 0; border:2px solid; }
.banner.pass { background:var(--pass-bg); border-color:var(--pass); }
.banner.fail { background:var(--fail-bg); border-color:var(--fail); }
.banner-title { font-weight:700; font-size:1.25rem; margin:0 0 .2rem; }
.banner.pass .banner-title { color:var(--pass); } .banner.fail .banner-title { color:var(--fail); }
.banner p:last-child { margin:0; }
.tiles { display:grid; grid-template-columns:repeat(auto-fit, minmax(170px, 1fr)); gap:12px; margin:16px 0; }
.tile { background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:12px 14px; }
.tile .k { color:var(--muted); font-size:.82rem; margin:0; } .tile .v { font-size:1.5rem; font-weight:650; margin:.1rem 0 0; }
.scroll { overflow-x:auto; margin:.6rem 0 1rem; border:1px solid var(--border); border-radius:8px; background:var(--surface); }
table { border-collapse:collapse; width:100%; font-size:.9rem; }
th, td { text-align:left; padding:7px 10px; border-bottom:1px solid var(--border); vertical-align:top; }
thead th { background:var(--code-bg); font-weight:600; white-space:nowrap; }
tbody tr:last-child td { border-bottom:0; }
td.num { text-align:right; font-variant-numeric:tabular-nums; }
td.detail { color:var(--muted); word-break:break-word; }
code, .mono { font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size:.85em; }
code { background:var(--code-bg); padding:1px 4px; border-radius:4px; word-break:break-all; }
pre { background:var(--code-bg); padding:12px 14px; border-radius:8px; overflow-x:auto; font-size:.85rem; }
pre code { background:none; padding:0; }
.badge { display:inline-block; font-size:.72rem; font-weight:700; letter-spacing:.04em; padding:2px 8px; border-radius:999px; }
.badge.pass { color:var(--pass); background:var(--pass-bg); border:1px solid var(--pass); }
.badge.fail { color:var(--fail); background:var(--fail-bg); border:1px solid var(--fail); }
.summary { background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:4px 16px 12px; margin:12px 0; }
.bars { list-style:none; padding:0; margin:.4rem 0; }
.bars li { display:grid; grid-template-columns:minmax(90px, 160px) 1fr 3.5em; gap:10px; align-items:center; margin:5px 0; max-width:none; }
.bl { font-size:.9rem; overflow-wrap:anywhere; } .bv { font-variant-numeric:tabular-nums; text-align:right; font-weight:600; }
.bt { display:block; height:14px; background:var(--track); border-radius:4px; overflow:hidden; }
.bf { display:block; height:100%; background:var(--bar); border-radius:4px; }
.note { color:var(--muted); font-size:.85rem; margin:.3rem 0; }
.match { color:var(--pass); font-size:.88rem; margin:.3rem 0 0; } .mismatch { color:var(--fail); font-size:.88rem; margin:.3rem 0 0; }
dl { display:grid; grid-template-columns:minmax(140px, 220px) 1fr; gap:6px 16px; margin:.6rem 0; }
dt { color:var(--muted); } dd { margin:0; overflow-wrap:anywhere; }
' || CHR(64) || 'media (max-width: 560px) { dl { grid-template-columns:1fr; } dd { margin-bottom:6px; } .bars li { grid-template-columns:80px 1fr 3em; } }
footer { color:var(--muted); font-size:.85rem; margin-top:3rem; border-top:1px solid var(--border); padding-top:1rem; }
</style>
</head>
<body>
<main>
<header>
<p class="eyebrow">MasterAntiqueRepair &middot; database migration &middot; import-oracle (proof of concept)</p>
<h1>Oracle migration verification report</h1>
<p class="lede">The SQL Server export from export-oracle, loaded into Oracle AI Database 26ai Free in a Docker container on Linux and checked against the metadata recorded at export.</p>
</header>
');
    w('<section class="banner ' || CASE WHEN pass THEN 'pass' ELSE 'fail' END || '" role="status" aria-label="Overall result"><p class="banner-title">'
      || CASE WHEN pass THEN 'VERIFICATION PASSED' ELSE 'VERIFICATION FAILED' END || '</p><p>' || jtxt(r, 'checksPassed') || ' of '
      || jtxt(r, 'checksTotal') || ' checks passed &middot; ' || jtxt(r, 'rowsVerified') || ' of ' || jtxt(r, 'rowsTotal')
      || ' rows verified identical &middot; '
      || CASE WHEN s IS NOT NULL THEN 'self-test ' || jtxt(s, 'passed') || ' of ' || jtxt(s, 'total') || ' passed' ELSE 'self-test not run' END
      || '</p></section>' || CHR(10));
    w('<section aria-labelledby="summary"><h2 id="summary">Executive summary</h2>' || CHR(10));
    w('<p>All ' || jarr(r, 'tables').get_size || ' tables and ' || jtxt(r, 'rowsTotal')
      || ' rows exported from the legacy SQL Server database were loaded into Oracle ' || h(jtxt(env, 'serverVersion'))
      || ' and compared with the record made at export. '
      || CASE WHEN pass THEN 'Every row count and every table''s full-content fingerprint matches the source, the schema is as designed, the ten business summaries give the same answers, every user''s credentials are removed, and the database rules (case-insensitive unique usernames through a function-based index, reuse of soft-deleted names, foreign keys, BOOLEAN values, identity columns, multi-byte text) behave as expected.'
              ELSE 'Some checks failed; they are listed below with the table or rule concerned.' END
      || ' This is a proof of concept alongside PostgreSQL, which remains the Phase 2 database.</p>' || CHR(10));
    w('<div class="tiles">'
      || '<div class="tile"><p class="k">Checks passed</p><p class="v">' || jtxt(r, 'checksPassed') || ' / ' || jtxt(r, 'checksTotal') || '</p></div>'
      || '<div class="tile"><p class="k">Rows verified identical</p><p class="v">' || jtxt(r, 'rowsVerified') || ' / ' || jtxt(r, 'rowsTotal') || '</p></div>'
      || '<div class="tile"><p class="k">Tables</p><p class="v">' || jarr(r, 'tables').get_size || '</p></div>'
      || '<div class="tile"><p class="k">Tooling self-test</p><p class="v">' || st || '</p></div>'
      || '</div></section>' || CHR(10));
  END;

  PROCEDURE method IS
    TYPE t_cat IS TABLE OF VARCHAR2(30);
    cats t_cat := t_cat(); c JSON_OBJECT_T; known BOOLEAN; passed PLS_INTEGER; total PLS_INTEGER;
  BEGIN
    w('<section aria-labelledby="method"><h2 id="method">Scope and method</h2>
<p>The Linux machine cannot reach the SQL Server database, so the comparison is made against <code>source-metadata.json</code>: a record written on Windows at export time from the source catalog and the same in-memory rows the SQL files were generated from, by a separate code path. The tool starts an Oracle container with no published network port, checks the files are the ones the record describes, creates a schema-only account (no password; nobody can log in as it), runs the schema and data scripts in it with SQL*Plus (stopping at the first error), and runs the checks below in PL/SQL inside the container as SYS through operating-system authentication. No data leaves the container and no password is kept.</p>
<p>Row content is compared with a fingerprint: every row of a table is written in one fixed text form (integers in decimal, true/false as 1/0, timestamps to the millisecond, text as the hex of its UTF-8 bytes, NULL distinct from empty text), the rows are sorted, and the whole table is hashed with SHA-256. A single changed character anywhere in a table changes its hash. The form is database-independent, so the fingerprints recorded at export equal those of the PostgreSQL export of the same data.</p>
<div class="scroll"><table><thead><tr><th scope="col">Category</th><th scope="col">What is checked</th><th scope="col" class="num">Passed</th><th scope="col">Result</th></tr></thead><tbody>' || CHR(10));
    FOR i IN 0 .. checks.get_size - 1 LOOP
      known := FALSE;
      FOR j IN 1 .. cats.COUNT LOOP IF cats(j) = jobj(checks, i).get_string('category') THEN known := TRUE; END IF; END LOOP;
      IF NOT known THEN cats.EXTEND; cats(cats.LAST) := jobj(checks, i).get_string('category'); END IF;
    END LOOP;
    FOR j IN 1 .. cats.COUNT LOOP
      passed := 0; total := 0;
      FOR i IN 0 .. checks.get_size - 1 LOOP
        c := jobj(checks, i);
        IF c.get_string('category') = cats(j) THEN
          total := total + 1;
          IF c.get_string('status') = 'PASS' THEN passed := passed + 1; END IF;
        END IF;
      END LOOP;
      w('<tr><td>' || INITCAP(cats(j)) || '</td><td>' || h(category_text(cats(j))) || '</td><td class="num">' || passed || ' / ' || total
        || '</td><td>' || badge(CASE WHEN passed = total THEN 'PASS' ELSE 'FAIL' END) || '</td></tr>' || CHR(10));
    END LOOP;
    w('</tbody></table></div></section>' || CHR(10));
  END;

  PROCEDURE tables_section IS
    t JSON_OBJECT_T; tabs JSON_ARRAY_T := jarr(r, 'tables'); found NUMBER := 0; ok BOOLEAN;
  BEGIN
    w('<section aria-labelledby="tables"><h2 id="tables">Tables: row counts and content hashes</h2>
<p>Hashes show the first 16 of 64 hex characters. The two empty tables hash the empty string (<code>e3b0c442&hellip;</code>).</p>
<div class="scroll"><table><thead><tr><th scope="col">Source (SQL Server)</th><th scope="col">Target (Oracle)</th><th scope="col" class="num">Source rows</th><th scope="col" class="num">Loaded rows</th><th scope="col">Source hash</th><th scope="col">Loaded hash</th><th scope="col">Result</th></tr></thead><tbody>' || CHR(10));
    FOR i IN 0 .. tabs.get_size - 1 LOOP
      t := jobj(tabs, i);
      found := found + NVL(TO_NUMBER(jtxt(t, 'actualRows')), 0);
      ok := jtxt(t, 'actualRows') = jtxt(t, 'expectedRows') AND jtxt(t, 'actualSha256') = jtxt(t, 'expectedSha256');
      w('<tr><td>' || h(jtxt(t, 'sourceName')) || '</td><td><code>' || h(jtxt(t, 'targetName')) || '</code></td><td class="num">'
        || jtxt(t, 'expectedRows') || '</td><td class="num">' || NVL(jtxt(t, 'actualRows'), '&ndash;') || '</td><td><code>'
        || SUBSTR(jtxt(t, 'expectedSha256'), 1, 16) || '</code></td><td><code>' || NVL(SUBSTR(jtxt(t, 'actualSha256'), 1, 16), '&ndash;')
        || '</code></td><td>' || badge(CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END) || '</td></tr>' || CHR(10));
    END LOOP;
    w('<tr><td><strong>Total</strong></td><td></td><td class="num"><strong>' || jtxt(r, 'rowsTotal') || '</strong></td><td class="num"><strong>'
      || found || '</strong></td><td></td><td></td><td></td></tr>' || CHR(10) || '</tbody></table></div></section>' || CHR(10));
  END;

  PROCEDURE schema_section IS
    model JSON_ARRAY_T := jarr(r, 'schemaModel'); t JSON_OBJECT_T; c JSON_OBJECT_T; f JSON_OBJECT_T; ix JSON_OBJECT_T; k JSON_OBJECT_T;
    cols JSON_ARRAY_T; keys VARCHAR2(4000); notes VARCHAR2(400);
  BEGIN
    w('<section aria-labelledby="schema"><h2 id="schema">Schema</h2>
<p>Each table as designed in the export (source names on the left, Oracle names and types on the right), with the result of comparing it against the live Oracle data dictionary (<code>DBA_TAB_COLUMNS</code>, <code>DBA_CONSTRAINTS</code>, <code>DBA_INDEXES</code>, <code>DBA_IND_EXPRESSIONS</code>). Identifiers were renamed to lowercase snake_case and are unquoted, so Oracle stores them in upper case; data values were not changed.</p>' || CHR(10));
    FOR i IN 0 .. model.get_size - 1 LOOP
      t := jobj(model, i);
      w('<h3><code>' || h(t.get_string('targetName')) || '</code> &larr; ' || h(t.get_string('sourceName')) || ' '
        || badge(group_status('schema', 'Table ' || t.get_string('targetName') || ' ')) || '</h3>' || CHR(10));
      w('<div class="scroll"><table><thead><tr><th scope="col">Source column</th><th scope="col">Source type</th><th scope="col">Oracle column</th><th scope="col">Oracle type</th><th scope="col">Null</th><th scope="col">Default</th><th scope="col">Notes</th></tr></thead><tbody>' || CHR(10));
      cols := jarr(t, 'columns');
      FOR j IN 0 .. cols.get_size - 1 LOOP
        c := jobj(cols, j);
        notes := NULL;
        IF c.has('identity') AND c.get_boolean('identity') THEN notes := 'identity (generated by default)'; END IF;
        IF c.has('synthetic') AND c.get_boolean('synthetic') THEN
          notes := notes || CASE WHEN notes IS NOT NULL THEN '; ' END || 'added at export (not in the source)';
        END IF;
        w('<tr><td>' || h(jtxt(c, 'sourceName')) || '</td><td>' || h(jtxt(c, 'sourceType')) || '</td><td><code>' || h(jtxt(c, 'targetName'))
          || '</code></td><td>' || h(jtxt(c, 'targetType')) || '</td><td>' || CASE WHEN c.get_boolean('nullable') THEN 'yes' ELSE 'no' END
          || '</td><td>' || h(jtxt(c, 'default')) || '</td><td>' || notes || '</td></tr>' || CHR(10));
      END LOOP;
      w('</tbody></table></div><ul>' || CHR(10));
      w('<li>Primary key <code>pk_' || h(t.get_string('targetName')) || '</code>: <code>' || jlist(jarr(t, 'primaryKey'), ', ') || '</code></li>' || CHR(10));
      FOR j IN 0 .. jarr(t, 'foreignKeys').get_size - 1 LOOP
        f := jobj(jarr(t, 'foreignKeys'), j);
        w('<li>Foreign key <code>' || h(jtxt(f, 'targetName')) || '</code>: (' || jlist(jarr(f, 'columns'), ', ') || ') &rarr; <code>'
          || h(jtxt(f, 'refTable')) || '</code> (' || jlist(jarr(f, 'refColumns'), ', ') || '), on delete ' || h(jtxt(f, 'onDelete'))
          || CASE WHEN jtxt(f, 'onDelete') = 'NO ACTION' THEN ' (clause omitted: Oracle''s default)' END || '</li>' || CHR(10));
      END LOOP;
      FOR j IN 0 .. jarr(t, 'indexes').get_size - 1 LOOP
        ix := jobj(jarr(t, 'indexes'), j);
        keys := NULL;
        FOR q IN 0 .. jarr(ix, 'columns').get_size - 1 LOOP
          k := jobj(jarr(ix, 'columns'), q);
          keys := keys || CASE WHEN q > 0 THEN ', ' END || h(NVL(jtxt(k, 'expression'), jtxt(k, 'column')))
                  || CASE WHEN k.get_boolean('descending') THEN ' DESC' END;
        END LOOP;
        w('<li>' || CASE WHEN ix.get_boolean('unique') THEN 'Unique' ELSE 'Plain' END || ' index <code>' || h(jtxt(ix, 'targetName'))
          || '</code> on (<code>' || keys || '</code>)'
          || CASE WHEN jtxt(ix, 'filter') IS NOT NULL THEN ', a function-based index that implements the source filter <code>' || h(jtxt(ix, 'filter'))
                  || '</code> (Oracle has no partial index; rows outside the filter produce an all-NULL key, which is not stored)' END
          || '</li>' || CHR(10));
      END LOOP;
      w('</ul>' || CHR(10));
    END LOOP;
    w('<h3>Schema checks</h3>' || CHR(10));
    checks_table('schema');
    w('</section>' || CHR(10));
  END;

  PROCEDURE rest IS
    sums JSON_ARRAY_T := jarr(r, 'summaries'); tests JSON_ARRAY_T; t JSON_OBJECT_T; env JSON_OBJECT_T := r.get_object('environment');
    inp JSON_ARRAY_T := jarr(r, 'inputs'); src JSON_OBJECT_T := r.get_object('source'); sx JSON_OBJECT_T := r.get_object('sourceExport');
    diffs JSON_ARRAY_T := jarr(r, 'knownDifferences'); c JSON_OBJECT_T;
  BEGIN
    w('<section aria-labelledby="summaries"><h2 id="summaries">Business summaries</h2>
<p>The same ten questions export-oracle asked of SQL Server, answered by Oracle queries and compared with the answers recorded from SQL Server.</p>' || CHR(10));
    FOR i IN 0 .. sums.get_size - 1 LOOP summary_block(jobj(sums, i)); END LOOP;
    w('</section>' || CHR(10));

    w('<section aria-labelledby="sanitization"><h2 id="sanitization">Credential sanitization</h2>
<p>The export removed every credential before anything was written to disk: <code>password_hash</code> and <code>security_stamp</code> are NULL for every user and <code>must_reset_password</code> (a column added at export) is true, so every migrated account must set a new password. Nothing else was changed: usernames, timestamps, ticket descriptions and comment text are exactly as in the source.</p>' || CHR(10));
    checks_table('sanitization');
    w('</section>' || CHR(10));

    w('<section aria-labelledby="rules"><h2 id="rules">Rule tests</h2>
<p>These try things the database must allow or refuse, each between a savepoint and a rollback to it. Test rows use explicit ids far above the data, so no identity sequence moves; the sequences are read first (from <code>DBA_SEQUENCES.LAST_NUMBER</code>, without drawing a value) and the last check confirms nothing was left behind. Oracle-specific findings are recorded here too: a <code>BOOLEAN</code> column silently converts numbers and words such as <code>''yes''</code> but rejects <code>''maybe''</code>; text written in the export''s <code>CHR</code>/<code>UNISTR</code> literal form comes back byte for byte; and with <code>MAX_STRING_SIZE = ' || h(jtxt(env, 'maxStringSize')) || '</code> a <code>VARCHAR2(2000 CHAR)</code> value is also limited to 4,000 bytes.</p>' || CHR(10));
    checks_table('rules');
    w('</section>' || CHR(10));

    w('<section aria-labelledby="selftest"><h2 id="selftest">Tooling self-test</h2>
<p>Proves the checker itself can be trusted: it gives the same answer every time and catches real damage. It runs on a separate, temporary container; the delivered database is never modified.</p>' || CHR(10));
    IF s IS NOT NULL THEN
      w('<div class="scroll"><table><thead><tr><th scope="col">Test</th><th scope="col">Detail</th><th scope="col">Result</th></tr></thead><tbody>' || CHR(10));
      tests := jarr(s, 'tests');
      FOR i IN 0 .. tests.get_size - 1 LOOP
        t := jobj(tests, i);
        w('<tr><td>' || h(jtxt(t, 'name')) || '</td><td class="detail">' || h(jtxt(t, 'detail')) || '</td><td>' || badge(jtxt(t, 'status'))
          || '</td></tr>' || CHR(10));
      END LOOP;
      w('</tbody></table></div>' || CHR(10));
    ELSE
      w('<p>The self-test has not been run (<code>ingest.sh selftest</code>).</p>' || CHR(10));
    END IF;
    w('</section>' || CHR(10));

    w('<section aria-labelledby="differences"><h2 id="differences">Known differences from the legacy database</h2><ul>' || CHR(10));
    FOR i IN 0 .. diffs.get_size - 1 LOOP w('<li>' || h(diffs.get_string(i)) || '</li>' || CHR(10)); END LOOP;
    w('<li>Excluded on purpose: ');
    FOR i IN 0 .. jarr(r, 'excludedTables').get_size - 1 LOOP
      w(CASE WHEN i > 0 THEN ', ' END || '<code>' || h(jarr(r, 'excludedTables').get_string(i)) || '</code>');
    END LOOP;
    w(' (Entity Framework migration history, not application data).</li>' || CHR(10)
      || '<li>Credentials were invalidated, not carried over (see Credential sanitization).</li></ul>
<h3>What this verification is and is not</h3>
<ul><li>It compares the database with a record made at export, not with the live SQL Server database, which this machine cannot reach. The record was produced by a separate code path from the SQL, so this is a real end-to-end check of the export and the load.</li>
<li>It guards against mistakes, not tampering: someone with write access could change both the record and the SQL files.</li>
<li>Timestamps have no time zone, and whether the legacy application stored UTC or local time is unknown; no conversion was made.</li>
<li>Usernames are unique regardless of case only through the function-based index on <code>LOWER(name)</code>, so sign-in must compare <code>LOWER(name) = LOWER(:input)</code>.</li>
<li>Oracle 23ai or later only (<code>BOOLEAN</code>, multi-row <code>INSERT</code>); Oracle 19c would need a different export.</li></ul>
</section>' || CHR(10));

    w('<section aria-labelledby="all"><h2 id="all">All checks</h2>
<div class="scroll"><table><thead><tr><th scope="col" class="num">#</th><th scope="col">Category</th><th scope="col">Check</th><th scope="col">Detail</th><th scope="col">Result</th></tr></thead><tbody>' || CHR(10));
    FOR i IN 0 .. checks.get_size - 1 LOOP
      c := jobj(checks, i);
      w('<tr><td class="num">' || jtxt(c, 'seq') || '</td><td>' || h(jtxt(c, 'category')) || '</td><td>' || h(jtxt(c, 'name'))
        || '</td><td class="detail">' || h(jtxt(c, 'detail')) || '</td><td>' || badge(jtxt(c, 'status')) || '</td></tr>' || CHR(10));
    END LOOP;
    w('</tbody></table></div></section>' || CHR(10));

    w('<section aria-labelledby="repro"><h2 id="repro">Reproducibility</h2>
<p>On a Linux machine with Docker Engine, bash and <code>sha256sum</code>, from the repository root:</p>
<pre><code>tools/phase1/dbmigrate/import-oracle/ingest.sh all --recreate   # load, verify, selftest, report
tools/phase1/dbmigrate/import-oracle/ingest.sh verify           # re-check the running database
docker exec -it mar-oracle sqlplus / as sysdba                  # look around (no password: OS authentication)
  ALTER SESSION SET CONTAINER = FREEPDB1;
  ALTER SESSION SET CURRENT_SCHEMA = masterantique;</code></pre>
<dl>' || CHR(10));
    w('<dt>Verified</dt><dd>' || h(jtxt(r.get_object('run'), 'runTimeUtc')) || ' UTC, tool commit <code>' || h(jtxt(r.get_object('run'), 'toolGitCommit'))
      || '</code></dd>' || CHR(10));
    w('<dt>Oracle</dt><dd>' || h(jtxt(env, 'banner')) || '; character set ' || h(jtxt(env, 'characterSet')) || ', MAX_STRING_SIZE '
      || h(jtxt(env, 'maxStringSize')) || ', NLS_LENGTH_SEMANTICS ' || h(jtxt(env, 'lengthSemantics')) || '</dd>' || CHR(10));
    w('<dt>Docker image</dt><dd><code>' || h(jtxt(env, 'image')) || '</code></dd>' || CHR(10));
    w('<dt>Container / database</dt><dd><code>' || h(jtxt(env, 'container')) || '</code> / pluggable database <code>'
      || h(jtxt(env, 'pluggableDatabase')) || '</code>, schema <code>' || h(jtxt(env, 'schema'))
      || '</code> (no password), no published port</dd>' || CHR(10));
    FOR i IN 0 .. inp.get_size - 1 LOOP
      c := jobj(inp, i);
      w('<dt>' || h(jtxt(c, 'file')) || '</dt><dd><code>' || h(jtxt(c, 'actualSha256')) || '</code>'
        || CASE WHEN jtxt(c, 'actualSha256') = jtxt(c, 'expectedSha256') THEN ' (matches the record)'
                ELSE ' (record: ' || h(jtxt(c, 'expectedSha256')) || ')' END || '</dd>' || CHR(10));
    END LOOP;
    w('<dt>Source</dt><dd>' || h(jtxt(src, 'version')) || ', database <code>' || h(jtxt(src, 'database')) || '</code> on <code>'
      || h(jtxt(src, 'server')) || '</code></dd>' || CHR(10));
    w('<dt>Exported</dt><dd>' || h(jtxt(sx, 'runTimeUtc')) || ' UTC, export tool commit <code>' || h(jtxt(sx, 'toolGitCommit'))
      || '</code> (export-oracle)</dd>' || CHR(10));
    w('</dl></section>
<footer><p>Generated by <code>tools/phase1/dbmigrate/import-oracle/ingest.sh report</code> from <code>verification-results.json</code> and <code>selftest-results.json</code>. Description: <code>docs/phase1/dbmigrate/import-oracle/README.md</code>; instructions for Claude Code: <code>tools/phase1/dbmigrate/import-oracle/CLAUDE.md</code>.</p></footer>
</main>
</body>
</html>');
  END;

BEGIN
  DECLARE st CLOB;
  BEGIN
    r := JSON_OBJECT_T.parse(read_file('report-results.json'));
    -- The self-test file is the results object, or the word null when the self-test has not run (JSON_ELEMENT_T.parse rejects a
    -- bare null with ORA-40587).
    st := read_file('report-selftest.json');
    IF TRIM(TRANSLATE(DBMS_LOB.SUBSTR(st, 100, 1), CHR(10) || CHR(13), '  ')) <> 'null' THEN s := JSON_OBJECT_T.parse(st); END IF;
  END;
  checks := jarr(r, 'checks');
  DBMS_LOB.CREATETEMPORARY(page, TRUE);
  head_and_summary;
  method;
  tables_section;
  schema_section;
  rest;
  print_page;
END;
/

DROP DIRECTORY mar_report_dir;
EXIT SUCCESS
