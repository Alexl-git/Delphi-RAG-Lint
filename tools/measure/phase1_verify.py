"""Phase 1 measurement replay -- READ ONLY.

Reproduces (or refutes) the four measurements the autodoc Phase 3 group reported
in docs/INBOX-REPLY-proptree-branch-collision-2026-07-29.md, on the corpora on
this machine. Every connection is opened mode=ro; nothing here writes.

Usage: python phase1_verify.py <item>   where item in 1|3|4|all
"""
import os
import sqlite3
import sys

DBS = [
    ("library-Win64", r"C:\Projects\.drag-lint\library-Win64.sqlite"),
    ("ORM3", r"C:\Projects\DB\ORM3\drag-lint.sqlite"),
    ("M2022", r"C:\Projects\.drag-lint\M2022.sqlite"),
    ("self", r"C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite"),
]


def conn(path):
    return sqlite3.connect("file:%s?mode=ro" % path.replace("\\", "/"), uri=True)


def stem_of(path):
    base = path.replace("/", "\\").split("\\")[-1]
    dot = base.rfind(".")
    return (base[:dot] if dot > 0 else base).lower()


def ext_of(path):
    base = path.replace("/", "\\").split("\\")[-1]
    dot = base.rfind(".")
    return base[dot:].lower() if dot > 0 else ""


def item1(name, path):
    c = conn(path)
    print("== item 1 :: %s" % name)
    # 1a. kind='unit' symbols by file extension.
    rows = c.execute(
        "SELECT f.path, COUNT(*) FROM symbols s JOIN files f ON f.id=s.file_id "
        "WHERE s.kind='unit' GROUP BY f.path").fetchall()
    byext = {}
    for p, n in rows:
        byext[ext_of(p)] = byext.get(ext_of(p), 0) + n
    print("   kind='unit' symbols by ext: %s" % sorted(byext.items()))
    # .dpk symbol load
    dpk = c.execute(
        "SELECT COUNT(*) FROM files WHERE path GLOB '*.[dD][pP][kK]'").fetchone()[0]
    dpksym = c.execute(
        "SELECT COUNT(*) FROM symbols s JOIN files f ON f.id=s.file_id "
        "WHERE f.path GLOB '*.[dD][pP][kK]'").fetchone()[0]
    print("   .dpk files=%d  symbols in them=%d" % (dpk, dpksym))
    # extension census
    allpaths = c.execute("SELECT id, path FROM files").fetchall()
    census = {}
    for _i, p in allpaths:
        census[ext_of(p)] = census.get(ext_of(p), 0) + 1
    print("   files by ext (top 8): %s"
          % sorted(census.items(), key=lambda kv: -kv[1])[:8])
    # case census of .pas
    up = c.execute("SELECT COUNT(*) FROM files WHERE path GLOB '*.PAS'").fetchone()[0]
    lo = c.execute("SELECT COUNT(*) FROM files WHERE path GLOB '*.pas'").fetchone()[0]
    print("   paths ending '.PAS'=%d  '.pas'=%d" % (up, lo))
    # 1b. stems where a .pas collides with a non-.pas
    per = {}
    for _i, p in allpaths:
        per.setdefault(stem_of(p), []).append(p)
    collide = 0
    for stem, ps in per.items():
        has_pas = any(ext_of(x) == ".pas" for x in ps)
        has_non = any(ext_of(x) != ".pas" for x in ps)
        if has_pas and has_non:
            collide += 1
    print("   stems where a .pas collides with a non-.pas: %d" % collide)
    # 1c. non-.pas files that WIN under last-wins, in `SELECT id, path FROM files`
    #     order. Replay the real accumulator: AddOrSetValue = last wins.
    scan = c.execute("SELECT id, path FROM files").fetchall()
    winner = {}
    for i, p in scan:
        st = stem_of(p)
        if st:
            winner[st] = p
    nonpas_wins = [(s, winner[s]) for s in winner
                   if ext_of(winner[s]) != ".pas"
                   and any(ext_of(x) == ".pas" for x in per.get(s, []))]
    print("   non-.pas files that WIN under last-wins (colliding stems only): %d"
          % len(nonpas_wins))
    for s, p in sorted(nonpas_wins)[:10]:
        print("      %s -> %s" % (s, os.path.basename(p)))
    # 1d. unit_uses rows already targeting a non-.pas
    rows = c.execute(
        "SELECT COUNT(*) FROM unit_uses u JOIN files f ON f.id=u.target_file_id "
        "WHERE LOWER(f.path) NOT LIKE '%.pas'").fetchone()[0]
    print("   SHIPPED unit_uses rows targeting a non-.pas: %d" % rows)
    det = c.execute(
        "SELECT f.path, COUNT(*) FROM unit_uses u JOIN files f ON f.id=u.target_file_id "
        "WHERE LOWER(f.path) NOT LIKE '%.pas' GROUP BY f.path ORDER BY 2 DESC LIMIT 8"
    ).fetchall()
    for p, n in det:
        print("      %s x%d" % (os.path.basename(p), n))
    c.close()


def item3(name, path):
    c = conn(path)
    print("== item 3 :: %s" % name)
    dup = c.execute(
        "SELECT COUNT(*) FROM (SELECT qualified_name FROM symbols "
        "WHERE qualified_name IS NOT NULL AND qualified_name <> '' "
        "GROUP BY qualified_name HAVING COUNT(*)>1)").fetchone()[0]
    print("   duplicate qnames: %d" % dup)
    dupt = c.execute(
        "SELECT COUNT(*) FROM (SELECT qualified_name FROM symbols "
        "WHERE kind IN ('class','interface','record') AND qualified_name IS NOT NULL "
        "AND qualified_name <> '' GROUP BY qualified_name HAVING COUNT(*)>1)").fetchone()[0]
    print("   duplicate qnames of kind class/interface/record: %d" % dupt)
    # impl term discriminates (takes both values inside the group)
    impl = c.execute(
        "SELECT COUNT(*) FROM (SELECT qualified_name, "
        "  MIN(CASE WHEN impl_start_line IS NOT NULL AND impl_start_line>0 THEN 0 ELSE 1 END) mn, "
        "  MAX(CASE WHEN impl_start_line IS NOT NULL AND impl_start_line>0 THEN 0 ELSE 1 END) mx "
        "  FROM symbols WHERE qualified_name IS NOT NULL AND qualified_name <> '' "
        "  GROUP BY qualified_name HAVING COUNT(*)>1 AND mn<>mx)").fetchone()[0]
    print("   impl term discriminates for: %d" % impl)
    implt = c.execute(
        "SELECT COUNT(*) FROM (SELECT qualified_name, "
        "  MIN(CASE WHEN impl_start_line IS NOT NULL AND impl_start_line>0 THEN 0 ELSE 1 END) mn, "
        "  MAX(CASE WHEN impl_start_line IS NOT NULL AND impl_start_line>0 THEN 0 ELSE 1 END) mx "
        "  FROM symbols WHERE kind IN ('class','interface','record') "
        "  AND qualified_name IS NOT NULL AND qualified_name <> '' "
        "  GROUP BY qualified_name HAVING COUNT(*)>1 AND mn<>mx)").fetchone()[0]
    print("   impl term discriminates among class/interface/record: %d" % implt)
    stubexpr = ("CASE WHEN kind IN ('class','interface') "
                "AND COALESCE(TRIM(heritage),'')='' AND end_line<=start_line "
                "THEN 1 ELSE 0 END")
    stub = c.execute(
        "SELECT COUNT(*) FROM (SELECT qualified_name, MIN(%s) mn, MAX(%s) mx "
        "  FROM symbols WHERE kind IN ('class','interface','record') "
        "  AND qualified_name IS NOT NULL AND qualified_name <> '' "
        "  GROUP BY qualified_name HAVING COUNT(*)>1 AND mn<>mx)"
        % (stubexpr, stubexpr)).fetchone()[0]
    print("   stub term discriminates among class/interface/record: %d" % stub)
    # System.TObject, old order (no ORDER BY -> rowid/scan order) vs new
    rows = c.execute(
        "SELECT id, file_id, start_line, end_line, COALESCE(heritage,'<NULL>'), kind "
        "FROM symbols WHERE qualified_name='System.TObject'").fetchall()
    print("   System.TObject rows (unordered scan order):")
    for r in rows:
        print("      id=%s file=%s lines=%s..%s heritage=%r kind=%s" % r)
    c.close()


def item4(name, path):
    c = conn(path)
    print("== item 4 :: %s" % name)
    tot = c.execute("SELECT COUNT(*) FROM unit_uses").fetchone()[0]
    pad = c.execute(
        "SELECT COUNT(*) FROM unit_uses WHERE unit_name GLOB '*[ '||char(9)||char(10)||char(13)||']*'"
    ).fetchone()[0]
    padun = c.execute(
        "SELECT COUNT(*) FROM unit_uses WHERE target_file_id IS NULL AND "
        "unit_name GLOB '*[ '||char(9)||char(10)||char(13)||']*'").fetchone()[0]
    print("   unit_uses rows=%d  with embedded whitespace=%d  of those unresolved=%d"
          % (tot, pad, padun))
    ex = c.execute(
        "SELECT unit_name FROM unit_uses WHERE unit_name GLOB '*[ '||char(9)||char(10)||char(13)||']*' "
        "LIMIT 5").fetchall()
    for (u,) in ex:
        print("      %r" % u)
    us = c.execute(
        "SELECT COUNT(*) FROM symbols WHERE kind='unit' AND "
        "name GLOB '*[ '||char(9)||char(10)||char(13)||']*'").fetchone()[0]
    ust = c.execute("SELECT COUNT(*) FROM symbols WHERE kind='unit'").fetchone()[0]
    print("   kind='unit' symbols with embedded whitespace: %d of %d" % (us, ust))
    c.close()


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    only = sys.argv[2] if len(sys.argv) > 2 else None
    for name, path in DBS:
        if only and name != only:
            continue
        if not os.path.exists(path):
            print("!! missing: %s (%s)" % (name, path))
            continue
        if which in ("1", "all"):
            item1(name, path)
        if which in ("3", "all"):
            item3(name, path)
        if which in ("4", "all"):
            item4(name, path)
        print("")


main()
