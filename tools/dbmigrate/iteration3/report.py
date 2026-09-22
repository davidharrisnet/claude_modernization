#!/usr/bin/env python3
"""report: builds MigrationVerificationReport3.docx from verification-results.json and
selftest-results.json, mirroring Report.ps1's section structure (title page, 11 numbered
sections, appendix) since there is no PowerShell/OpenXML on this Linux host. Charts are
drawn with matplotlib instead of System.Drawing; the document itself is assembled as
Markdown and converted with pandoc. Not byte-identical to the OpenXML original, but the
same content and section order, so the three iterations' reports stay comparable.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
DOCS_DIR = HERE.parent.parent.parent / "docs/dbmigrate/iteration3"
BUILD_DIR = HERE / "_report_build"

PASS_COLOR = "#15803D"
FAIL_COLOR = "#B91C1C"
BLUE = "#2563EB"
GREY = "#64748B"


def fig_path(name):
    return BUILD_DIR / name


def donut_chart(passed, total, path):
    fig, ax = plt.subplots(figsize=(4, 4))
    frac = passed / total if total else 0
    color = PASS_COLOR if passed == total else FAIL_COLOR
    ax.pie([frac, 1 - frac], colors=[color, "#E5E7EB"], startangle=90,
           counterclock=False, wedgeprops=dict(width=0.35))
    ax.text(0, 0.05, f"{passed}/{total}", ha="center", va="center", fontsize=22, fontweight="bold")
    ax.text(0, -0.18, "checks passed", ha="center", va="center", fontsize=11, color=GREY)
    ax.set_aspect("equal")
    fig.savefig(path, dpi=150, bbox_inches="tight", transparent=True)
    plt.close(fig)


def bar_chart(title, labels, a, b, name_a, name_b, path, figsize=(9, 4)):
    fig, ax = plt.subplots(figsize=figsize)
    x = range(len(labels))
    w = 0.38
    ax.bar([i - w / 2 for i in x], a, width=w, label=name_a, color=BLUE)
    ax.bar([i + w / 2 for i in x], b, width=w, label=name_b, color="#93C5FD")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=9)
    ax.set_title(title, fontsize=12, fontweight="bold")
    ax.legend(fontsize=9)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def status_grid(tables, path):
    fig, ax = plt.subplots(figsize=(6, 0.4 * len(tables) + 1))
    cols = ["Row count", "Row content"]
    ax.set_xlim(0, len(cols))
    ax.set_ylim(0, len(tables))
    for i, t in enumerate(tables):
        y = len(tables) - i - 1
        for j, ok in enumerate([t["CountPassed"], t["ContentPassed"]]):
            ax.add_patch(plt.Rectangle((j, y), 1, 1, facecolor=PASS_COLOR if ok else FAIL_COLOR, edgecolor="white"))
            ax.text(j + 0.5, y + 0.5, "PASS" if ok else "FAIL", ha="center", va="center",
                     color="white", fontsize=8, fontweight="bold")
        ax.text(-0.1, y + 0.5, t["Name"], ha="right", va="center", fontsize=9)
    for j, c in enumerate(cols):
        ax.text(j + 0.5, len(tables) + 0.15, c, ha="center", va="bottom", fontsize=9, fontweight="bold")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def md_table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join(["---"] * len(header)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def result_word(b):
    return "PASS" if b else "FAIL"


def main():
    results = json.loads((HERE / "verification-results.json").read_text())
    selftest = json.loads((HERE / "selftest-results.json").read_text()) if (HERE / "selftest-results.json").exists() else None
    BUILD_DIR.mkdir(exist_ok=True)

    m = results["Meta"]
    s = results["Summary"]
    tables = results["Tables"]
    checks = results["Checks"]
    domain = results["Domain"]
    passed = results["Passed"]
    tn = m["TargetName"]

    donut_chart(s["ChecksPassed"], s["ChecksTotal"], fig_path("donut.png"))
    bar_chart("Rows per table", [t["Name"] for t in tables],
              [t["SourceRows"] for t in tables], [t["TargetRows"] for t in tables],
              "Local control build (independent)", tn, fig_path("rows.png"))
    status_grid(tables, fig_path("status.png"))

    schema_checks = [c for c in checks if c["Category"] == "Schema"]
    bar_chart("Schema objects compared", [c["Name"].split(" (")[0] for c in schema_checks],
              [c["Source"] for c in schema_checks], [c["Target"] for c in schema_checks],
              "Expected", f"Found in {tn}", fig_path("schema.png"), figsize=(10, 4.5))

    domain_charts = []
    for d in domain[:5]:
        labels, src, tgt = [], [], []
        src_map = {r.split("|")[0]: int(r.split("|")[1]) for r in d["SourceRows"]}
        tgt_map = {r.split("|")[0]: int(r.split("|")[1]) for r in d["TargetRows"]}
        for k in src_map:
            labels.append(k)
            src.append(src_map[k])
            tgt.append(tgt_map.get(k, 0))
        fname = f"domain_{len(domain_charts)}.png"
        bar_chart(d["Name"], labels, src, tgt, "Local control build", tn, fig_path(fname), figsize=(6, 3.5))
        domain_charts.append((d["Name"], fname))

    md = []
    md.append("---\ntitle: Database Migration Verification Report\n---\n")
    md.append(f"# Database Migration Verification Report\n")
    md.append(f"### MasterAntiqueRepair: independent local build cross-checked against {tn}\n")
    md.append(f"**Iteration {m['Iteration']} — {m['IterationTitle']}**\n")
    banner = f"## VERIFICATION {'PASSED' if passed else 'FAILED'}\n\n" \
             f"{s['ChecksPassed']} of {s['ChecksTotal']} checks passed | " \
             f"{s['RowsVerifiedIdentical']} of {s['RowsSource']} rows verified identical | " \
             f"{s['Tables']} tables\n"
    md.append(banner)
    md.append(f"- Source: {m['SourceServer']}")
    md.append(f"- Source database: {m['SourceDatabase']}")
    md.append(f"- Target: {tn}, {m['TargetLocation']}, {m['TargetClient']}\n")

    md.append("## 1. Executive summary\n")
    if passed:
        md.append(f"Two databases were built independently on this Linux host from the same sanitized "
                   f"schema and data — a Docker image (the delivered artifact) and a throwaway local control "
                   f"database built directly with the sqlite3 CLI, no Docker involved — and cross-checked "
                   f"against each other. Every check passed. All {s['RowsSource']} rows across "
                   f"{s['Tables']} tables were found identical between the two builds, the schema objects "
                   f"match, the database rules the application depends on still work, and every migrated "
                   f"account's credentials were confirmed sanitized (see section 7).\n")
    else:
        md.append(f"Verification found differences: {s['ChecksPassed']} of {s['ChecksTotal']} checks passed and "
                   f"{s['RowsVerifiedIdentical']} of {s['RowsSource']} rows were verified identical. "
                   f"See section 8.\n")
    md.append("Everything in this report was produced by deterministic scripts (bash, Python, sqlite3, docker), "
               "not by a language model at run time: the same inputs always produce the same results.\n")
    md.append(md_table(["Measure", "Reference", tn, "Result"], [
        ["Tables", s["Tables"], s["Tables"], result_word(True)],
        ["Rows in all tables", s["RowsSource"], sum(t["TargetRows"] for t in tables),
         result_word(s["RowsSource"] == sum(t["TargetRows"] for t in tables))],
        ["Rows verified identical", s["RowsSource"], s["RowsVerifiedIdentical"],
         result_word(s["RowsVerifiedIdentical"] == s["RowsSource"])],
        ["Checks passed", s["ChecksTotal"], s["ChecksPassed"], result_word(s["ChecksPassed"] == s["ChecksTotal"])],
    ]))
    md.append("")

    md.append("## 2. Scope and method\n")
    md.append("**What was checked.** All application tables: " + ", ".join(t["Name"] for t in tables) + ".\n")
    md.append("**A note on source of truth.** Iteration 3 has no live SQL Server connection from this Linux "
               "host, and does not consult any output artifact from iteration 1 or iteration 2. "
               "\"Reference\" throughout this report means the local control database — built fresh, in "
               "this run, directly with the sqlite3 CLI from the same sanitized input the Docker image was "
               "built from. Agreement between two independently-built copies is the evidence, not agreement "
               "with a stored answer from a prior iteration.\n")
    md.append("**How it was checked:**\n")
    md.append("- Row counts and canonically-ordered row content, hashed and compared between the two "
              "independent builds.")
    md.append("- Schema facts (tables, columns, keys, indexes, the partial active-username index, "
              "auto-increment tables) introspected independently on both builds and compared to each other.")
    md.append("- The same 10 business-summary queries run on both independent builds, compared to each other.")
    md.append("- 5 behaviour tests exercised on a scratch copy inside the container, so the delivered "
              "database was never modified.")
    md.append("- Self-test of the tooling itself: a second build must be byte-identical, an independently "
              "copied database must match, and a deliberately damaged copy must be caught and named.\n")

    md.append("## 3. Results at a glance\n")
    md.append(f"![Donut chart: checks passed]({fig_path('donut.png').name})\n")
    md.append("*Figure 1. Overall outcome of all checks.*\n")
    md.append(f"![Rows per table]({fig_path('rows.png').name})\n")
    md.append("*Figure 2. Row count of every table, reference versus this iteration's built image.*\n")
    md.append(f"![Status grid]({fig_path('status.png').name})\n")
    md.append("*Figure 3. Verification status of each table.*\n")

    md.append("## 4. Data verification in detail\n")
    md.append(md_table(["Table", "Ref. rows", "Target rows", "Diff", "Rows identical", "Result", "Row hash (16)"],
                        [[t["Name"], t["SourceRows"], t["TargetRows"], t["TargetRows"] - t["SourceRows"],
                          t["RowsIdentical"], result_word(t["CountPassed"] and t["ContentPassed"]),
                          t["SourceHash"][:16]] for t in tables]))
    md.append("")

    md.append("## 5. Schema and integrity\n")
    md.append(f"![Schema objects compared]({fig_path('schema.png').name})\n")
    md.append("*Figure 4. Schema object counts, expected versus found.*\n")
    srows = [[c["Name"], c["Source"] if c["Source"] is not None else "-",
              c["Target"] if c["Target"] is not None else "-", result_word(c["Passed"])]
             for c in checks if c["Category"] in ("Schema", "Integrity")]
    md.append(md_table(["Check", "Expected", "Found", "Result"], srows))
    md.append("")

    md.append("## 6. Business-level summaries\n")
    md.append("The same question was asked of the reference and the built image; the answers must match.\n")
    for name, fname in domain_charts:
        md.append(f"![{name}]({fig_path(fname).name})\n")
    drows = []
    for d in domain:
        ans = "; ".join(d["SourceRows"][:4]) + ("; ..." if len(d["SourceRows"]) > 4 else "")
        drows.append([d["Name"], ans, result_word(d["Passed"])])
    md.append(md_table(["Summary", "Answer (identical in target when PASS)", "Result"], drows))
    md.append("")

    md.append("## 7. Behaviour tests, credential sanitization, and tooling self-test\n")
    md.append("Behaviour tests were run on a throw-away copy inside the container; the delivered database "
               "was never modified.\n")
    brows = [[c["Name"], result_word(c["Passed"])] for c in checks if c["Category"] == "Behaviour"]
    md.append(md_table(["Behaviour", "Result"], brows))
    san_rows = [[c["Name"], result_word(c["Passed"])] for c in checks if c["Category"] == "Sanitization"]
    if san_rows:
        md.append("\n### Credential sanitization\n")
        md.append("This is a one-time bootstrap migration; a forced password reset on next login is "
                   "acceptable, so no usable credential is carried into the target at all.\n")
        md.append(md_table(["Check", "Result"], san_rows))
    if selftest:
        md.append("\n### Self-test of the migration tooling\n")
        trows = [[t["Category"], t["Name"], result_word(t["Passed"])] for t in selftest["Tests"]]
        md.append(md_table(["Area", "Test", "Result"], trows))
    md.append("")

    md.append("## 8. Differences found\n")
    diff_rows = []
    for t in tables:
        for mm in t.get("Mismatches", []):
            diff_rows.append([mm["Table"], mm["Key"], mm["Column"], mm["Source"], mm["Target"]])
    for c in checks:
        if not c["Passed"]:
            diff_rows.append([c["Category"], c["Name"], "-", "-", c.get("Detail", "")])
    for d in domain:
        if not d["Passed"]:
            diff_rows.append(["Summary", d["Name"], "-", "; ".join(d["SourceRows"]), "; ".join(d["TargetRows"])])
    if not diff_rows:
        md.append("**None.** No differences were found.\n")
    else:
        md.append(f"{len(diff_rows)} difference(s) found (credential columns are redacted):\n")
        md.append(md_table(["Table/area", "Row/check", "Column", "Reference", "Target"], diff_rows))
    md.append("")

    md.append("## 9. Intentional exclusions and known differences\n")
    md.append("- The Entity Framework migration history table (`__MigrationHistory`) is not migrated.")
    md.append("- The SQL Server `dbo` schema prefix is dropped; table/column names keep their spelling and case.")
    for kd in m.get("KnownDifferences", []):
        md.append(f"- {kd}")
    md.append("")

    md.append("## 10. Reproducibility\n")
    md.append("From `tools/dbmigrate/iteration3/` on a Linux host with Docker:\n")
    md.append("```\n./dbmigrate3.sh all --recreate\n```\n")
    schema_hash = hashlib.sha256((HERE / "01-schema.sql").read_bytes()).hexdigest()
    data_hash = hashlib.sha256((HERE / "02-data-sanitized.sql").read_bytes()).hexdigest()
    md.append(md_table(["Item", "Value"], [
        ["Tooling git commit", results.get("GitCommit", "n/a")],
        ["Target client", m["TargetClient"]],
        ["01-schema.sql SHA-256 (includes MustResetPassword column)", schema_hash],
        ["02-data-sanitized.sql SHA-256 (committed; credentials redacted)", data_hash],
        [f"{tn} target", m["TargetLocation"]],
    ]))
    md.append("")

    md.append("## 11. Sign-off\n")
    md.append(md_table(["Role", "Name", "Signature", "Date"], [
        ["Prepared by", "", "", ""], ["Technical reviewer", "", "", ""], ["Business approver", "", "", ""],
    ]))
    md.append("")

    md.append("## Appendix A. Full row hashes\n")
    md.append("SHA-256 over all rows of each table (canonical form, fixed order), computed on the "
               "reference database and on the built image.\n")
    md.append(md_table(["Table", "Reference SHA-256", "Target SHA-256", "Match"],
                        [[t["Name"], t["SourceHash"], t["TargetHash"], result_word(t["SourceHash"] == t["TargetHash"])]
                         for t in tables]))

    md_text = "\n".join(md)
    md_path = BUILD_DIR / "report.md"
    md_path.write_text(md_text)

    out_path = DOCS_DIR / "MigrationVerificationReport3.docx"
    subprocess.run(["pandoc", str(md_path), "-o", str(out_path), "--resource-path", str(BUILD_DIR)], check=True)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    sys.exit(main())
