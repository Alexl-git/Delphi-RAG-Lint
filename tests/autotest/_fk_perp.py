"""_fk_perp.py -- the second writer for run_index_two_writers_fk.ps1 (NOT a run_* runner).

Simulates what TSQLiteSymbolStore.OpenFileTx does to one file on a per-file reindex:
inside ONE transaction DELETE the file's symbols (FK cascade takes call_edges, SET NULL
on refs.symbol_id) and re-insert them with NEW ids. A bump row inserted first keeps the
re-inserted block from being the max rowid, because SQLite re-issues the same ids to a
block that held the max (symbols.id has no AUTOINCREMENT) and no race would exist.

usage: python -I _fk_perp.py <db> <path-suffix> --hold-ms N
         one transaction (BEGIN IMMEDIATE .. sleep N ms .. COMMIT); prints READY once the
         lock is held, then COMMITTED.
       python -I _fk_perp.py <db> <path-suffix> --loop --period-ms N --seconds S
         repeated commits; prints DONE commits=<n>.
       python -I _fk_perp.py <db> <path-suffix> --min-id
         prints the smallest symbols.id of that file and exits.
"""
import sqlite3, sys, time


def arg(name, default=None):
    a = sys.argv
    return a[a.index(name) + 1] if name in a else default


def shift(con, fid, bump_fid, sel, ins):
    rows = con.execute(sel, (fid,)).fetchall()
    bump_id = con.execute(
        "INSERT INTO symbols(file_id, kind, name, qualified_name, start_line, start_col, end_line, end_col)"
        " VALUES (?, 'local_var', 'zz_bump', 'zz_bump', 1, 1, 1, 1)", (bump_fid,)).lastrowid
    con.execute('DELETE FROM symbols WHERE file_id = ?', (fid,))
    remap = {}
    for r in rows:
        np = remap.get(r[1], r[1]) if r[1] is not None else None
        remap[r[0]] = con.execute(ins, (np,) + tuple(r[2:])).lastrowid
    con.execute('DELETE FROM symbols WHERE id = ?', (bump_id,))


def main():
    db, suffix = sys.argv[1], sys.argv[2]
    con = sqlite3.connect(db, timeout=5.0, isolation_level=None)
    con.execute('PRAGMA foreign_keys = ON')
    con.execute('PRAGMA busy_timeout = 5000')
    row = con.execute("SELECT id FROM files WHERE path LIKE ? ESCAPE '|'", ('%' + suffix,)).fetchone()
    if not row:
        print('no files row for', suffix); sys.exit(2)
    fid = row[0]
    if '--min-id' in sys.argv:
        print(con.execute('SELECT min(id) FROM symbols WHERE file_id = ?', (fid,)).fetchone()[0])
        return
    other = con.execute('SELECT id FROM files WHERE id <> ? LIMIT 1', (fid,)).fetchone()
    cols = [r[1] for r in con.execute('PRAGMA table_info(symbols)') if r[1] not in ('id', 'parent_id')]
    sel = 'SELECT id, parent_id, ' + ', '.join(cols) + ' FROM symbols WHERE file_id = ? ORDER BY id'
    ins = 'INSERT INTO symbols(parent_id, ' + ', '.join(cols) + ') VALUES (?' + ', ?' * len(cols) + ')'
    if '--hold-ms' in sys.argv:
        con.execute('BEGIN IMMEDIATE')
        shift(con, fid, other[0], sel, ins)
        print('READY', flush=True)
        time.sleep(float(arg('--hold-ms')) / 1000.0)
        con.execute('COMMIT')
        print('COMMITTED', flush=True)
        return
    period = float(arg('--period-ms', '10')) / 1000.0
    t_end = time.time() + float(arg('--seconds', '10'))
    n = 0
    while time.time() < t_end:
        try:
            con.execute('BEGIN IMMEDIATE')
            shift(con, fid, other[0], sel, ins)
            con.execute('COMMIT')
            n += 1
        except sqlite3.OperationalError:
            try:
                con.execute('ROLLBACK')
            except sqlite3.Error:
                pass
        time.sleep(period)
    print('DONE commits=%d' % n, flush=True)


main()
