#!/usr/bin/env python3
r"""refs_ab_diff.py -- set-diff two drag-lint indexes built from the SAME source.

Written for docs\PLAN-extractor-batch-2026-08-30.md sec 4.4 / sec 5. The A/B
protocol there builds one index with the OLD engine and one with the NEW engine
over identical sources; the only legitimate difference is rows the extractor
change ADDED.

WHY FULL SITE LISTS AND NOT COUNTS: counts alone once hid a false negative in
this repo -- an equal number of rows removed and added nets to zero. Every diff
below is a genuine set difference in BOTH directions, and the full member list
is written to disk so a human can verify sampled sites against source.

Read-only: opens both databases with mode=ro. Safe against a live index.

usage: refs_ab_diff.py A.sqlite B.sqlite --out <dir>
"""

import argparse
import os
import sqlite3
import sys

# Kill thresholds from the plan's sec 7. Growth beyond these is not a failure
# this script can adjudicate -- it STOPS and makes a human look.
REFS_GROWTH_KILL_PCT = 5.0
EDGES_GROWTH_KILL_PCT = 10.0

REFS_SQL = """
SELECT LOWER(f.path), r.start_line, r.start_col, r.kind, LOWER(r.name_text)
FROM refs r JOIN files f ON f.id = r.file_id
"""

# The caller SITE identifies the edge; target_symbol_id is a local rowid and
# cannot be compared across two separately built databases.
EDGES_SQL = """
SELECT LOWER(f.path), r.start_line, r.start_col,
       LOWER(COALESCE(t.qualified_name, '<unresolved>')), e.confidence
FROM call_edges e
JOIN refs r    ON r.id = e.ref_id
JOIN files f   ON f.id = r.file_id
LEFT JOIN symbols t ON t.id = e.target_symbol_id
"""

ANCESTORS_SQL = """
SELECT LOWER(s.qualified_name), a.ordinal, LOWER(a.ancestor_name)
FROM type_ancestors a JOIN symbols s ON s.id = a.symbol_id
"""

TABLES = [
    ("refs", REFS_SQL, REFS_GROWTH_KILL_PCT),
    ("call_edges", EDGES_SQL, EDGES_GROWTH_KILL_PCT),
    ("type_ancestors", ANCESTORS_SQL, None),
]


def load(db_path, sql):
    if not os.path.isfile(db_path):
        sys.exit("no such database: %s" % db_path)
    uri = "file:%s?mode=ro" % db_path.replace("?", "%3f").replace("#", "%23")
    con = sqlite3.connect(uri, uri=True)
    try:
        return [tuple(row) for row in con.execute(sql)]
    finally:
        con.close()


def write_list(path, rows):
    with open(path, "w", encoding="ascii", errors="replace", newline="\r\n") as fh:
        for row in rows:
            fh.write("|".join(str(c) for c in row) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a_db")
    ap.add_argument("b_db")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    verdict_lines = []
    kill = False

    for name, sql, growth_kill in TABLES:
        a_rows = load(args.a_db, sql)
        b_rows = load(args.b_db, sql)
        a_set, b_set = set(a_rows), set(b_rows)

        # Multiset guard: a duplicated span is the register-E1 double-emit
        # shape, and set() would silently swallow it.
        a_dupes = len(a_rows) - len(a_set)
        b_dupes = len(b_rows) - len(b_set)

        only_a = sorted(a_set - b_set)
        only_b = sorted(b_set - a_set)
        write_list(os.path.join(args.out, "%s_only_in_A.txt" % name), only_a)
        write_list(os.path.join(args.out, "%s_only_in_B.txt" % name), only_b)

        growth = (100.0 * (len(b_rows) - len(a_rows)) / len(a_rows)) if a_rows else 0.0
        verdict_lines.append(
            "%-15s A=%-8d B=%-8d  removed=%-6d added=%-6d  growth=%+.2f%%"
            % (name, len(a_rows), len(b_rows), len(only_a), len(only_b), growth)
        )

        # These changes are strictly ADDITIVE. Removal is a restructure, not an
        # extension -- the plan calls that a kill in every table.
        if only_a:
            verdict_lines.append("    KILL: %d row(s) present in A and MISSING in B" % len(only_a))
            kill = True
        if b_dupes > a_dupes:
            verdict_lines.append(
                "    KILL: duplicate rows rose %d -> %d (double-emit at an identical span)"
                % (a_dupes, b_dupes))
            kill = True
        if growth_kill is not None and growth > growth_kill:
            verdict_lines.append(
                "    STOP: growth %+.2f%% exceeds the %.1f%% threshold -- re-diagnose before landing"
                % (growth, growth_kill))
            kill = True

    # A ref changing KIND at an identical span is the T3i hazard (something
    # silently becoming a `call`). Set-diff alone reports that as one removal
    # plus one addition, which reads as ordinary churn -- so name it directly.
    a_kind = {(p, l, c, n): k for (p, l, c, k, n) in load(args.a_db, REFS_SQL)}
    b_kind = {(p, l, c, n): k for (p, l, c, k, n) in load(args.b_db, REFS_SQL)}
    flips = sorted((k, a_kind[k], b_kind[k]) for k in a_kind.keys() & b_kind.keys()
                   if a_kind[k] != b_kind[k])
    write_list(os.path.join(args.out, "refs_kind_flips.txt"),
               [(p, l, c, n, old, new) for ((p, l, c, n), old, new) in flips])
    if flips:
        verdict_lines.append("    KILL: %d ref(s) changed KIND at an identical span (T3i)" % len(flips))
        kill = True

    report = "\n".join(verdict_lines)
    print(report)
    print()
    print("VERDICT: %s" % ("KILL -- do not land" if kill else "clean (additive only)"))
    with open(os.path.join(args.out, "summary.txt"), "w",
              encoding="ascii", errors="replace", newline="\r\n") as fh:
        fh.write(report + "\n\nVERDICT: %s\n"
                 % ("KILL -- do not land" if kill else "clean (additive only)"))
    return 1 if kill else 0


if __name__ == "__main__":
    sys.exit(main())
