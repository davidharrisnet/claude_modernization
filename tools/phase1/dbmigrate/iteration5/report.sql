-- Iteration 5 report: renders MigrationVerificationReport5.html from verification-results.json (and
-- selftest-results.json, or null). Run by `ingest.sh report` inside the container, in the default 'postgres'
-- database: psql is only the template engine here; the migrated data is never read. Deterministic: the same JSON
-- always gives a byte-identical page (the run time shown is the one recorded in the JSON).

\set results `cat /tmp/report-results.json`
\set selftest `cat /tmp/report-selftest.json`
SET client_min_messages = warning;

CREATE TEMP TABLE r AS SELECT :'results'::jsonb AS j, :'selftest'::jsonb AS s;

CREATE FUNCTION pg_temp.h(t text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

CREATE FUNCTION pg_temp.badge(status text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN status = 'PASS' THEN '<span class="badge pass">PASS</span>'
              ELSE '<span class="badge fail">' || pg_temp.h(coalesce(status, 'FAIL')) || '</span>' END;
$$;

-- Overall status of the checks whose name starts with a prefix, within a category.
CREATE FUNCTION pg_temp.group_status(j jsonb, cat text, prefix text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN count(*) = 0 THEN 'N/A'
              WHEN bool_and(c ->> 'status' = 'PASS') THEN 'PASS' ELSE 'FAIL' END
  FROM jsonb_array_elements(j -> 'checks') c
  WHERE c ->> 'category' = cat AND c ->> 'name' LIKE prefix || '%';
$$;

-- A table of checks for the given categories.
CREATE FUNCTION pg_temp.checks_table(j jsonb, cats text[]) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '<div class="scroll"><table><thead><tr><th scope="col">Check</th><th scope="col">Detail</th>'
      || '<th scope="col">Result</th></tr></thead><tbody>'
      || coalesce(string_agg(format('<tr><td>%s</td><td class="detail">%s</td><td>%s</td></tr>',
                    pg_temp.h(c ->> 'name'), pg_temp.h(c ->> 'detail'), pg_temp.badge(c ->> 'status')),
                  '' ORDER BY (c ->> 'seq')::int), '')
      || '</tbody></table></div>'
  FROM jsonb_array_elements(j -> 'checks') c
  WHERE c ->> 'category' = ANY (cats);
$$;

-- One business summary: a bar chart when every row is "label|count", else the expected and found rows.
CREATE FUNCTION pg_temp.summary_block(sm jsonb, checks jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  WITH rows AS (
    SELECT v, o FROM jsonb_array_elements_text(coalesce(sm -> 'actualRows', sm -> 'expectedRows')) WITH ORDINALITY x(v, o)
  ), bar AS (
    SELECT bool_and(v ~ '^[^|]*\|[0-9]+$') AND count(*) > 0 AS ok,
           max(split_part(v, '|', 2)::numeric) FILTER (WHERE v ~ '^[^|]*\|[0-9]+$') AS mx
    FROM rows
  ), st AS (
    SELECT c ->> 'status' AS status, c ->> 'detail' AS detail FROM jsonb_array_elements(checks) c
    WHERE c ->> 'category' = 'summaries' AND c ->> 'name' = sm ->> 'name' LIMIT 1
  )
  SELECT '<div class="summary"><h3>' || pg_temp.h(sm ->> 'name') || ' ' || pg_temp.badge((SELECT status FROM st)) || '</h3>'
    || CASE WHEN (SELECT ok FROM bar) THEN
         '<ul class="bars">' || (SELECT string_agg(format(
             '<li><span class="bl">%s</span><span class="bt" aria-hidden="true"><span class="bf" style="width:%s%%"></span></span><span class="bv">%s</span></li>',
             pg_temp.h(CASE WHEN split_part(v, '|', 1) = '' THEN '(none)' ELSE split_part(v, '|', 1) END),
             CASE WHEN (SELECT mx FROM bar) > 0
                  THEN round(100 * split_part(v, '|', 2)::numeric / (SELECT mx FROM bar), 1)::text ELSE '0' END,
             split_part(v, '|', 2)), '' ORDER BY o) FROM rows) || '</ul>'
       ELSE
         '<div class="scroll"><table><thead><tr><th scope="col">Expected (SQL Server)</th><th scope="col">Found (PostgreSQL)</th></tr></thead><tbody>'
         || coalesce((SELECT string_agg(format('<tr><td><code>%s</code></td><td><code>%s</code></td></tr>',
                pg_temp.h(e.v), pg_temp.h(a.v)), '' ORDER BY coalesce(e.o, a.o))
              FROM jsonb_array_elements_text(sm -> 'expectedRows') WITH ORDINALITY e(v, o)
              FULL JOIN jsonb_array_elements_text(coalesce(sm -> 'actualRows', '[]')) WITH ORDINALITY a(v, o) ON a.o = e.o), '')
         || '</tbody></table></div>'
       END
    || CASE sm ->> 'name'
         WHEN 'Tickets by state' THEN '<p class="note">States are the legacy workflow codes: 0 = SUBMITTED, 1 = INPROGRESS, 2 = COMPLETED.</p>'
         WHEN 'Audit events by action' THEN '<p class="note">Actions are the numeric codes stored by the legacy application.</p>'
         WHEN 'Comments per ticket (distribution)' THEN '<p class="note">Label = comments on a ticket; value = number of tickets with that many comments.</p>'
         WHEN 'Ticket date ranges' THEN '<p class="note">Earliest and latest submitted, assigned and completed dates.</p>'
         WHEN 'Account and audit date ranges' THEN '<p class="note">Earliest and latest account creation and audit event.</p>'
         ELSE '' END
    || CASE WHEN (SELECT status FROM st) = 'PASS' THEN '<p class="match">Identical to the source.</p>'
            ELSE '<p class="mismatch">' || pg_temp.h((SELECT detail FROM st)) || '</p>' END
    || '</div>';
$$;

CREATE FUNCTION pg_temp.category_text(cat text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE cat
    WHEN 'environment' THEN 'The PostgreSQL server is version 15 or later and uses UTF-8; the metadata format is the expected one.'
    WHEN 'integrity' THEN 'The two SQL files are byte-for-byte the ones the metadata was recorded for (SHA-256).'
    WHEN 'counts' THEN 'Every table has exactly the number of rows the source had.'
    WHEN 'hashes' THEN 'Every table''s full contents, in a canonical text form, hash to the same SHA-256 as the source.'
    WHEN 'schema' THEN 'Tables, columns, types, nullability, defaults, identity columns, keys, foreign keys and indexes match.'
    WHEN 'summaries' THEN 'Ten business questions give the same answers as on the source.'
    WHEN 'sanitization' THEN 'No user has a password hash or security stamp; every user must reset the password.'
    WHEN 'rules' THEN 'Database rules behave as in the legacy system (tested in a transaction that is rolled back).'
    ELSE '' END;
$$;

\o /tmp/report.html
SELECT
'<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Migration Verification Report 5</title>
<style>
:root { --bg:#f7f7f5; --surface:#ffffff; --text:#1c1c1a; --muted:#5b5b57; --border:#d9d9d4; --accent:#2f5d8a;
  --pass:#1f6b3a; --pass-bg:#e3f1e7; --fail:#9b1c1c; --fail-bg:#fbe4e4; --bar:#2f5d8a; --track:#e8e8e3; --code-bg:#f0f0ec; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#161615; --surface:#1f1f1d; --text:#ececea;
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
@media (max-width: 560px) { dl { grid-template-columns:1fr; } dd { margin-bottom:6px; } .bars li { grid-template-columns:80px 1fr 3em; } }
footer { color:var(--muted); font-size:.85rem; margin-top:3rem; border-top:1px solid var(--border); padding-top:1rem; }
</style>
</head>
<body>
<main>
<header>
<p class="eyebrow">MasterAntiqueRepair &middot; database migration &middot; iteration 5</p>
<h1>Migration verification report</h1>
<p class="lede">The SQL Server export from iteration 4, loaded into PostgreSQL in a Docker container on Linux and checked against the metadata recorded at export.</p>
</header>
'
-- banner and executive summary
|| format('<section class="banner %s" role="status" aria-label="Overall result"><p class="banner-title">%s</p><p>%s of %s checks passed &middot; %s of %s rows verified identical%s</p></section>
',
     CASE WHEN r.j ->> 'status' = 'PASS' THEN 'pass' ELSE 'fail' END,
     CASE WHEN r.j ->> 'status' = 'PASS' THEN 'VERIFICATION PASSED' ELSE 'VERIFICATION FAILED' END,
     r.j ->> 'checksPassed', r.j ->> 'checksTotal', r.j ->> 'rowsVerified', r.j ->> 'rowsTotal',
     CASE WHEN jsonb_typeof(r.s) = 'object'
          THEN format(' &middot; self-test %s of %s passed', r.s ->> 'passed', r.s ->> 'total') ELSE ' &middot; self-test not run' END)
|| '<section aria-labelledby="summary"><h2 id="summary">Executive summary</h2>'
|| format('<p>All %s tables and %s rows exported from the legacy SQL Server database were loaded into PostgreSQL %s and compared with the record made at export. %s</p>',
     jsonb_array_length(r.j -> 'tables'), r.j ->> 'rowsTotal', pg_temp.h(split_part(r.j -> 'environment' ->> 'serverVersion', ' ', 1)),
     CASE WHEN r.j ->> 'status' = 'PASS'
          THEN 'Every row count and every table''s full-content fingerprint matches the source, the schema is as designed, the ten business summaries give the same answers, every user''s credentials are removed, and the database rules (case-insensitive unique usernames, reuse of soft-deleted names, foreign keys, identity sequences) behave as expected.'
          ELSE 'Some checks failed; they are listed below with the table or rule concerned.' END)
|| '<div class="tiles">'
|| format('<div class="tile"><p class="k">Checks passed</p><p class="v">%s / %s</p></div>', r.j ->> 'checksPassed', r.j ->> 'checksTotal')
|| format('<div class="tile"><p class="k">Rows verified identical</p><p class="v">%s / %s</p></div>', r.j ->> 'rowsVerified', r.j ->> 'rowsTotal')
|| format('<div class="tile"><p class="k">Tables</p><p class="v">%s</p></div>', jsonb_array_length(r.j -> 'tables'))
|| format('<div class="tile"><p class="k">Tooling self-test</p><p class="v">%s</p></div>',
     CASE WHEN jsonb_typeof(r.s) = 'object' THEN format('%s / %s', r.s ->> 'passed', r.s ->> 'total') ELSE 'not run' END)
|| '</div></section>
'
-- scope and method
|| '<section aria-labelledby="method"><h2 id="method">Scope and method</h2>
<p>The Linux machine cannot reach the SQL Server database, so the comparison is made against <code>source-metadata.json</code>: a record written on Windows at export time from the source catalog and the same in-memory rows the SQL files were generated from, by a separate code path. The tool starts a PostgreSQL container with no published network port, checks the files are the ones the record describes, loads the schema and then the data (stopping at the first error), and runs the checks below with <code>psql</code> inside the container. No data leaves the container.</p>
<p>Row content is compared with a fingerprint: every row of a table is written in one fixed text form (integers in decimal, true/false as 1/0, timestamps to the millisecond, text as the hex of its UTF-8 bytes, NULL distinct from empty text), the rows are sorted, and the whole table is hashed with SHA-256. A single changed character anywhere in a table changes its hash.</p>
<div class="scroll"><table><thead><tr><th scope="col">Category</th><th scope="col">What is checked</th><th scope="col" class="num">Passed</th><th scope="col">Result</th></tr></thead><tbody>'
|| (SELECT string_agg(format('<tr><td>%s</td><td>%s</td><td class="num">%s / %s</td><td>%s</td></tr>',
          initcap(cat), pg_temp.h(pg_temp.category_text(cat)), passed, total,
          pg_temp.badge(CASE WHEN passed = total THEN 'PASS' ELSE 'FAIL' END)), '' ORDER BY first_seq)
    FROM (SELECT c ->> 'category' AS cat, count(*) FILTER (WHERE c ->> 'status' = 'PASS') AS passed, count(*) AS total,
                 min((c ->> 'seq')::int) AS first_seq
          FROM jsonb_array_elements(r.j -> 'checks') c GROUP BY 1) g)
|| '</tbody></table></div></section>
'
-- tables
|| '<section aria-labelledby="tables"><h2 id="tables">Tables: row counts and content hashes</h2>
<p>Hashes show the first 16 of 64 hex characters. The two empty tables hash the empty string (<code>e3b0c442&hellip;</code>).</p>
<div class="scroll"><table><thead><tr><th scope="col">Source (SQL Server)</th><th scope="col">Target (PostgreSQL)</th><th scope="col" class="num">Source rows</th><th scope="col" class="num">Loaded rows</th><th scope="col">Source hash</th><th scope="col">Loaded hash</th><th scope="col">Result</th></tr></thead><tbody>'
|| (SELECT string_agg(format('<tr><td>%s</td><td><code>%s</code></td><td class="num">%s</td><td class="num">%s</td><td><code>%s</code></td><td><code>%s</code></td><td>%s</td></tr>',
          pg_temp.h(t ->> 'sourceName'), pg_temp.h(t ->> 'targetName'), t ->> 'expectedRows', coalesce(t ->> 'actualRows', '&ndash;'),
          left(t ->> 'expectedSha256', 16), coalesce(left(t ->> 'actualSha256', 16), '&ndash;'),
          pg_temp.badge(CASE WHEN t -> 'actualRows' = t -> 'expectedRows' AND t ->> 'actualSha256' = t ->> 'expectedSha256'
                             THEN 'PASS' ELSE 'FAIL' END)), '' ORDER BY o)
    FROM jsonb_array_elements(r.j -> 'tables') WITH ORDINALITY x(t, o))
|| format('<tr><td><strong>Total</strong></td><td></td><td class="num"><strong>%s</strong></td><td class="num"><strong>%s</strong></td><td></td><td></td><td></td></tr>',
     r.j ->> 'rowsTotal', (SELECT coalesce(sum((t ->> 'actualRows')::bigint), 0) FROM jsonb_array_elements(r.j -> 'tables') t))
|| '</tbody></table></div></section>
'
-- schema
|| '<section aria-labelledby="schema"><h2 id="schema">Schema</h2>
<p>Each table as designed in the export (source names on the left, PostgreSQL names and types on the right), with the result of comparing it against the live PostgreSQL catalog. Identifiers were renamed to lowercase snake_case; data values were not changed.</p>'
|| (SELECT string_agg(
       format('<h3><code>%s</code> &larr; %s %s</h3>', pg_temp.h(t ->> 'targetName'), pg_temp.h(t ->> 'sourceName'),
              pg_temp.badge(pg_temp.group_status(r.j, 'schema', 'Table ' || (t ->> 'targetName') || ' ')))
    || '<div class="scroll"><table><thead><tr><th scope="col">Source column</th><th scope="col">Source type</th><th scope="col">PostgreSQL column</th><th scope="col">PostgreSQL type</th><th scope="col">Null</th><th scope="col">Default</th><th scope="col">Notes</th></tr></thead><tbody>'
    || (SELECT string_agg(format('<tr><td>%s</td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
             pg_temp.h(c ->> 'sourceName'), pg_temp.h(c ->> 'sourceType'), pg_temp.h(c ->> 'targetName'), pg_temp.h(c ->> 'targetType'),
             CASE WHEN (c ->> 'nullable')::boolean THEN 'yes' ELSE 'no' END, pg_temp.h(c ->> 'default'),
             concat_ws('; ', CASE WHEN (c ->> 'identity')::boolean THEN 'identity (generated by default)' END,
                             CASE WHEN (c ->> 'synthetic')::boolean THEN 'added at export (not in the source)' END)),
           '' ORDER BY o) FROM jsonb_array_elements(t -> 'columns') WITH ORDINALITY y(c, o))
    || '</tbody></table></div><ul>'
    || format('<li>Primary key: <code>%s</code></li>',
              (SELECT string_agg(pg_temp.h(k), ', ' ORDER BY o) FROM jsonb_array_elements_text(t -> 'primaryKey') WITH ORDINALITY z(k, o)))
    || coalesce((SELECT string_agg(format('<li>Foreign key <code>%s</code>: (%s) &rarr; <code>%s</code> (%s), on delete %s</li>',
             pg_temp.h(f ->> 'targetName'),
             (SELECT string_agg(pg_temp.h(v), ', ') FROM jsonb_array_elements_text(f -> 'columns') v),
             pg_temp.h(f ->> 'refTable'),
             (SELECT string_agg(pg_temp.h(v), ', ') FROM jsonb_array_elements_text(f -> 'refColumns') v),
             pg_temp.h(f ->> 'onDelete')), '' ORDER BY f ->> 'targetName' COLLATE "C")
           FROM jsonb_array_elements(t -> 'foreignKeys') f), '')
    || coalesce((SELECT string_agg(format('<li>%s index <code>%s</code> on (%s)%s</li>',
             CASE WHEN (i ->> 'unique')::boolean THEN 'Unique' ELSE 'Plain' END, pg_temp.h(i ->> 'targetName'),
             (SELECT string_agg(pg_temp.h(coalesce(k ->> 'expression', k ->> 'column'))
                                || CASE WHEN (k ->> 'descending')::boolean THEN ' DESC' ELSE '' END, ', ' ORDER BY o)
                FROM jsonb_array_elements(i -> 'columns') WITH ORDINALITY z(k, o)),
             CASE WHEN i ->> 'filter' IS NOT NULL THEN ' where <code>' || pg_temp.h(i ->> 'filter') || '</code>' ELSE '' END),
           '' ORDER BY i ->> 'targetName' COLLATE "C")
           FROM jsonb_array_elements(t -> 'indexes') i), '')
    || '</ul>', '' ORDER BY o)
    FROM jsonb_array_elements(r.j -> 'schemaModel') WITH ORDINALITY x(t, o))
|| '<h3>Schema checks</h3>' || pg_temp.checks_table(r.j, ARRAY['schema'])
|| '</section>
'
-- business summaries
|| '<section aria-labelledby="summaries"><h2 id="summaries">Business summaries</h2>
<p>The same ten questions the earlier iterations asked, answered by PostgreSQL queries and compared with the answers recorded from SQL Server.</p>'
|| (SELECT string_agg(pg_temp.summary_block(sm, r.j -> 'checks'), '' ORDER BY o)
    FROM jsonb_array_elements(r.j -> 'summaries') WITH ORDINALITY x(sm, o))
|| '</section>
'
-- sanitization and rules
|| '<section aria-labelledby="sanitization"><h2 id="sanitization">Credential sanitization</h2>
<p>The export removed every credential before anything was written to disk: <code>password_hash</code> and <code>security_stamp</code> are NULL for every user and <code>must_reset_password</code> (a column added at export) is true, so every migrated account must set a new password. Nothing else was changed: usernames, timestamps, ticket descriptions and comment text are exactly as in the source.</p>'
|| pg_temp.checks_table(r.j, ARRAY['sanitization'])
|| '</section>
<section aria-labelledby="rules"><h2 id="rules">Rule tests</h2>
<p>These try things the database must allow or refuse, inside blocks that are always rolled back. Test rows use explicit ids far above the data, so no identity sequence moves; the sequences are checked first, and the last check confirms nothing was left behind.</p>'
|| pg_temp.checks_table(r.j, ARRAY['rules'])
|| '</section>
'
-- self-test
|| '<section aria-labelledby="selftest"><h2 id="selftest">Tooling self-test</h2>
<p>Proves the checker itself can be trusted: it gives the same answer every time and catches real damage. It runs on a separate, temporary container; the delivered database is never modified.</p>'
|| CASE WHEN jsonb_typeof(r.s) = 'object' THEN
     '<div class="scroll"><table><thead><tr><th scope="col">Test</th><th scope="col">Detail</th><th scope="col">Result</th></tr></thead><tbody>'
     || (SELECT string_agg(format('<tr><td>%s</td><td class="detail">%s</td><td>%s</td></tr>',
             pg_temp.h(t ->> 'name'), pg_temp.h(t ->> 'detail'), pg_temp.badge(t ->> 'status')), '' ORDER BY o)
         FROM jsonb_array_elements(r.s -> 'tests') WITH ORDINALITY x(t, o))
     || '</tbody></table></div>'
   ELSE '<p>The self-test has not been run (<code>ingest.sh selftest</code>).</p>' END
|| '</section>
'
-- known differences
|| '<section aria-labelledby="differences"><h2 id="differences">Known differences from the legacy database</h2><ul>'
|| (SELECT string_agg('<li>' || pg_temp.h(d) || '</li>', '' ORDER BY o)
    FROM jsonb_array_elements_text(r.j -> 'knownDifferences') WITH ORDINALITY x(d, o))
|| format('<li>Excluded on purpose: %s (Entity Framework migration history, not application data).</li>',
     (SELECT string_agg('<code>' || pg_temp.h(v) || '</code>', ', ') FROM jsonb_array_elements_text(r.j -> 'excludedTables') v))
|| '<li>Credentials were invalidated, not carried over (see Credential sanitization).</li></ul>
<h3>What this verification is and is not</h3>
<ul><li>It compares the database with a record made at export, not with the live SQL Server database, which this machine cannot reach. The record was produced by a separate code path from the SQL, so this is a real end-to-end check of the export and the load.</li>
<li>It guards against mistakes, not tampering: someone with write access could change both the record and the SQL files.</li>
<li>Timestamps have no time zone, and whether the legacy application stored UTC or local time is unknown; no conversion was made.</li>
<li>Usernames are unique regardless of case only through the <code>lower(name)</code> index, so Phase 2 sign-in must compare <code>lower(name) = lower(:input)</code>.</li></ul>
</section>
'
-- all checks
|| '<section aria-labelledby="all"><h2 id="all">All checks</h2>
<div class="scroll"><table><thead><tr><th scope="col" class="num">#</th><th scope="col">Category</th><th scope="col">Check</th><th scope="col">Detail</th><th scope="col">Result</th></tr></thead><tbody>'
|| (SELECT string_agg(format('<tr><td class="num">%s</td><td>%s</td><td>%s</td><td class="detail">%s</td><td>%s</td></tr>',
          c ->> 'seq', pg_temp.h(c ->> 'category'), pg_temp.h(c ->> 'name'), pg_temp.h(c ->> 'detail'), pg_temp.badge(c ->> 'status')),
          '' ORDER BY (c ->> 'seq')::int)
    FROM jsonb_array_elements(r.j -> 'checks') c)
|| '</tbody></table></div></section>
'
-- reproducibility
|| '<section aria-labelledby="repro"><h2 id="repro">Reproducibility</h2>
<p>On a Linux machine with Docker Engine, bash and <code>sha256sum</code>, from the repository root:</p>
<pre><code>tools/phase1/dbmigrate/iteration5/ingest.sh all --recreate   # load, verify, selftest, report
tools/phase1/dbmigrate/iteration5/ingest.sh verify           # re-check the running database
docker exec -it mar-postgres psql -U masterantique -d masterantique   # look around (no password needed inside)</code></pre>
<dl>'
|| format('<dt>Verified</dt><dd>%s UTC, tool commit <code>%s</code></dd>', pg_temp.h(r.j -> 'run' ->> 'runTimeUtc'), pg_temp.h(r.j -> 'run' ->> 'toolGitCommit'))
|| format('<dt>PostgreSQL</dt><dd>%s, encoding %s</dd>', pg_temp.h(r.j -> 'environment' ->> 'serverVersion'), pg_temp.h(r.j -> 'environment' ->> 'serverEncoding'))
|| format('<dt>Docker image</dt><dd><code>%s</code></dd>', pg_temp.h(r.j -> 'environment' ->> 'image'))
|| format('<dt>Container / database</dt><dd><code>%s</code> / <code>%s</code>, schema <code>%s</code>, no published port</dd>',
     pg_temp.h(r.j -> 'environment' ->> 'container'), pg_temp.h(r.j ->> 'database'), pg_temp.h(r.j -> 'environment' ->> 'schema'))
|| (SELECT string_agg(format('<dt>%s</dt><dd><code>%s</code>%s</dd>', pg_temp.h(i ->> 'file'), pg_temp.h(i ->> 'actualSha256'),
          CASE WHEN i ->> 'actualSha256' = i ->> 'expectedSha256' THEN ' (matches the record)' ELSE ' (record: ' || pg_temp.h(i ->> 'expectedSha256') || ')' END),
          '' ORDER BY o)
    FROM jsonb_array_elements(r.j -> 'inputs') WITH ORDINALITY x(i, o))
|| format('<dt>Source</dt><dd>%s, database <code>%s</code> on <code>%s</code></dd>',
     pg_temp.h(r.j -> 'source' ->> 'version'), pg_temp.h(r.j -> 'source' ->> 'database'), pg_temp.h(r.j -> 'source' ->> 'server'))
|| format('<dt>Exported</dt><dd>%s UTC, export tool commit <code>%s</code> (iteration 4)</dd>',
     pg_temp.h(r.j -> 'sourceExport' ->> 'runTimeUtc'), pg_temp.h(r.j -> 'sourceExport' ->> 'toolGitCommit'))
|| '</dl></section>
<footer><p>Generated by <code>tools/phase1/dbmigrate/iteration5/ingest.sh report</code> from <code>verification-results.json</code> and <code>selftest-results.json</code>. Plan: <code>docs/phase1/dbmigrate/iteration5/ITERATION5_PLAN.md</code>; record: <code>docs/phase1/dbmigrate/iteration5/ITERATION5.md</code>.</p></footer>
</main>
</body>
</html>'
FROM r;
\o
