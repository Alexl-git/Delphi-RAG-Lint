"""uses_target_replay.py -- replay TSQLiteSymbolStore.ResolveUnitUseTargets over an
index and classify every distinct used unit name by the EXTENSION OF THE FILE IT
WOULD WIN.

WHY THIS FILE EXISTS. Two comments -- src/storage/DRagLint.Storage.SQLite.pas
(ResolveUnitUseTargets' header) and tests/autotest/run_proptree_ancestor_climb.ps1
(its header) -- publish per-corpus figures for the fix-round-1 defect where a
non-unit file could claim a unit's stem. Register K18 records what happens when a
figure like that is produced by a script nobody committed: it cannot be
re-derived and it drifts. T4b set the opposite precedent with returns_blast.py.
This is that precedent applied to those figures.

WHAT IT REPLAYS, and the ONE deviation, stated. Faithful to the Pascal:

  * the scan is `SELECT id, path FROM files` with no ORDER BY. SQLite serves it
    from the UNIQUE index on files.path (EXPLAIN QUERY PLAN: `SCAN files USING
    COVERING INDEX sqlite_autoindex_files_1`), so the order is ascending by RAW
    PATH BYTES under the default BINARY collation. That is why the extension only
    decides a stem collision when everything before it is byte-identical: case
    and directory position are compared first.
  * stem = LowerCase(basename without extension); the FIRST file to reach a stem
    keeps it (`if not FullToFile.ContainsKey(Stem)`).
  * tail = the text after the stem's last dot; the first stem to claim a tail
    keeps it, and a tail claimed by a DIFFERENT stem is ambiguous and resolves
    nothing.
  * pass 1 matches LOWER(unit_name) against a full stem; pass 2 matches
    unit_name_norm against an unambiguous tail, on rows pass 1 left NULL.
  * DEVIATION: --unfiltered omits the shipped `if Ext <> '.pas' then Continue`
    guard. That is the whole point -- it reproduces the PRE-FIX behaviour whose
    blast radius the two comments quote. --filtered replays the shipped code.

THE CLASSIFIER, because a count without one is what K18 and T4b fix round 4 are
both about. Unit counted: DISTINCT LOWER(TRIM(unit_name)) over unit_uses. Three
criteria are printed, and they are NOT the same set:

  (A) the WINNING file is not a .pas  -- the criterion the comments state, and the
      only one that matches the harm they describe (an empty scope, because the
      winner declares no classes).
  (B) the stem is claimed by SOME non-.pas file, won or not -- strictly wider.
  (C) a non-.pas competitor exists and LOSES -- the counter-examples to any claim
      that a colliding non-unit file "always won".

Measured 2026-07-29 at c4b78d0, unfiltered:

  corpus          files  uses rows  distinct names  (A)  (A or B)  (C)
  library-Win64    6909      85157            5094  608       613    5
  ORM3              836      14223            1199   57        62    5
  M2022             564      14120             856  197       205    8
  self (drag-lint)  642       1836             402   25        25    0

The published 613 / 62 / 205 / 25 are (A or B), not (A). The comments now
publish (A) and name it.

Usage:
  python tools/measure/uses_target_replay.py [--filtered] [<db> ...]
  (no db arguments = the four indexes in DEFAULT_DBS below)
"""
import ntpath
import os
import sqlite3
import sys

DEFAULT_DBS = [
    ('library-Win64', r'C:\Projects\.drag-lint\library-Win64.sqlite'),
    ('ORM3',          r'C:\Projects\DB\ORM3\drag-lint.sqlite'),
    ('M2022',         r'C:\Projects\.drag-lint\M2022.sqlite'),
    ('self',          r'C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite'),
]


def build_maps(rows, filtered):
    """(full-stem -> winner, tail -> winner, ambiguous tails, stem -> extensions).

    `rows` must arrive in the scan order the store sees. Winners are first-wins,
    exactly as the Pascal dictionaries are populated.
    """
    full, tail_to, stem_of_tail, tail_ambig = {}, {}, {}, set()
    stems_by_ext = {}
    for fid, path in rows:
        ext = os.path.splitext(path)[1].lower()
        base = ntpath.basename(path.replace('/', '\\'))
        stem = os.path.splitext(base)[0].lower()
        if stem:
            stems_by_ext.setdefault(stem, set()).add(ext)
        if filtered and ext != '.pas':
            continue
        if not stem:
            continue
        if stem not in full:
            full[stem] = (fid, path, ext)
        dot = stem.rfind('.')
        tail = stem[dot + 1:] if dot >= 0 else stem
        if tail:
            if tail in stem_of_tail:
                if stem_of_tail[tail] != stem:
                    tail_ambig.add(tail)
            else:
                stem_of_tail[tail] = stem
                tail_to[tail] = (fid, path, ext)
    return full, tail_to, tail_ambig, stems_by_ext


def run(name, db, filtered):
    con = sqlite3.connect('file:' + db + '?mode=ro', uri=True)
    files = list(con.execute('SELECT id, path FROM files'))
    uses = list(con.execute('SELECT unit_name, unit_name_norm FROM unit_uses'))
    plan = list(con.execute('EXPLAIN QUERY PLAN SELECT id, path FROM files'))
    con.close()

    full, tail_to, tail_ambig, stems_by_ext = build_maps(files, filtered)

    per_key = {}
    for un, norm in uses:
        key = (un or '').strip().lower()
        per_key.setdefault(key, set()).add(((un or '').lower(), norm or ''))

    winner_not_pas, claimed_by_non_pas, non_pas_loses, resolved = set(), set(), set(), set()
    for key, variants in per_key.items():
        win = None
        for lu, _norm in sorted(variants):
            if lu in full:
                win = full[lu]
                break
        if win is None:
            for _lu, norm in sorted(variants):
                if norm in tail_to and norm not in tail_ambig:
                    win = tail_to[norm]
                    break
        exts = stems_by_ext.get(key, set())
        if exts - {'.pas'}:
            claimed_by_non_pas.add(key)
        if win is not None:
            resolved.add(key)
            if win[2] != '.pas':
                winner_not_pas.add(key)
            elif exts - {'.pas'}:
                non_pas_loses.add(key)

    print('== %s   (%s)' % (name, 'FILTERED, .pas only -- the shipped code'
                            if filtered else 'UNFILTERED -- the pre-fix behaviour'))
    print('   scan plan            : %s' % (plan[0][-1] if plan else '?'))
    print('   files / uses rows    : %d / %d' % (len(files), len(uses)))
    print('   distinct LOWER(TRIM(unit_name)) : %d   resolved: %d' % (len(per_key), len(resolved)))
    print('   (A) WINNING file is not a .pas .................. %d' % len(winner_not_pas))
    print('   (B) stem claimed by a non-.pas file, won or not .. %d' % len(claimed_by_non_pas))
    print('   (A or B) -- the figure published before 2026-07-29 %d'
          % len(winner_not_pas | claimed_by_non_pas))
    print('   (C) a non-.pas competitor exists and LOSES ....... %d' % len(non_pas_loses))
    for k in sorted(non_pas_loses):
        print('        loses: %-24s exts=%-18s winner=%s'
              % (k, ','.join(sorted(stems_by_ext[k])), full.get(k, ('', '(via tail)', ''))[1]))
    return len(winner_not_pas), len(winner_not_pas | claimed_by_non_pas), len(non_pas_loses)


def main(argv):
    filtered = '--filtered' in argv
    dbs = [a for a in argv if not a.startswith('--')]
    todo = [(os.path.basename(d), d) for d in dbs] if dbs else DEFAULT_DBS
    for nm, p in todo:
        if not os.path.exists(p):
            print('== %s   SKIPPED, not present: %s' % (nm, p))
            continue
        run(nm, p, filtered)


if __name__ == '__main__':
    main(sys.argv[1:])
