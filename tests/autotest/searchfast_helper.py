"""Read or prepare a scratch drag-lint index for run_v154_SEARCHFAST.ps1.

Usage: python -I searchfast_helper.py <verb> <db>
  dump       one line: row count, MATCH counts, trigger count, FTS5 integrity, hash of the search rows
  plan       the query plan of the statement FTS5 runs to drop a merged segment
  stat       the recorded row counts of the FTS5 data tables
  poison     record 2 rows for them, as an ANALYZE of an empty database does
  counts     rows in symbol_search, in the FTS5 docsize table, and procedures
  changerow  change one search row (control)
  unindexed  delete one search row behind the FTS5 index's back (control)
"""
import hashlib
import sqlite3
import sys

DATA = "('string_fts_data', 'symbol_search_fts_data')"
verb, db = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db, timeout=10.0, isolation_level=None)


def one(sql, args=()):
    return c.execute(sql, args).fetchone()[0]


def dump():
    h = hashlib.sha256()
    n = 0
    for r in c.execute('SELECT f.path, s.start_line, s.kind, s.name, x.tokens, x.summary, x.remarks '
                       'FROM symbol_search x JOIN symbols s ON s.id = x.symbol_id JOIN files f ON f.id = s.file_id '
                       'ORDER BY 1, 2, 3, 4, 5'):
        h.update(repr(r).encode())
        n += 1
    hits = [one('SELECT count(*) FROM symbol_search_fts WHERE symbol_search_fts MATCH ?', (w,))
            for w in ('lantern', 'handle', 'handlerow2step7', 'pelican')]
    trg = one("SELECT count(*) FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'symbol_search%'")
    try:
        c.execute("INSERT INTO symbol_search_fts(symbol_search_fts, rank) VALUES ('integrity-check', 1)")
        fts = 'intact'
    except sqlite3.DatabaseError:
        fts = 'BROKEN'
    return 'rows=%d hits=%s triggers=%d fts=%s sha=%s' % (n, hits, trg, fts, h.hexdigest()[:16])


if verb == 'dump':
    print(dump())
elif verb == 'plan':
    print(c.execute('EXPLAIN QUERY PLAN DELETE FROM symbol_search_fts_data WHERE id>=? AND id<=?', (1, 2)).fetchall()[0][3])
elif verb == 'stat':
    print(' '.join('%s=%s' % r for r in c.execute(
        'SELECT tbl, stat FROM sqlite_stat1 WHERE idx IS NULL AND tbl IN ' + DATA + ' ORDER BY 1')))
elif verb == 'poison':
    c.execute('DELETE FROM sqlite_stat1 WHERE idx IS NULL AND tbl IN ' + DATA)
    c.execute("INSERT INTO sqlite_stat1(tbl, idx, stat) VALUES ('string_fts_data', NULL, '2'), ('symbol_search_fts_data', NULL, '2')")
elif verb == 'counts':
    print(one('SELECT count(*) FROM symbol_search'), one('SELECT count(*) FROM symbol_search_fts_docsize'),
          one("SELECT count(*) FROM symbols WHERE kind = 'procedure'"))
elif verb == 'changerow':
    c.execute("UPDATE symbol_search SET tokens = tokens || ' zebra' WHERE symbol_id = (SELECT max(symbol_id) FROM symbol_search)")
elif verb == 'unindexed':
    c.execute('DROP TRIGGER symbol_search_ad')
    c.execute('DELETE FROM symbol_search WHERE symbol_id = (SELECT max(symbol_id) FROM symbol_search)')
else:
    sys.exit('unknown verb ' + verb)
c.close()
