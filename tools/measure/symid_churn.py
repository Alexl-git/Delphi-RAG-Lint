"""Symbol-id churn of one re-emitted file: before-DB vs after-DB (both copies).
usage: py -I tools/measure/symid_churn.py <before.sqlite> <after.sqlite> <file-name-suffix>
Prints: symbols before/after, ids kept (today), would-keep under GH18 reuse (key + fingerprint),
foreign rows bound to the file's symbols before, names in scope today vs with reuse, refs those names pull."""
import sqlite3, sys, hashlib

POS = {'id', 'file_id', 'parent_id', 'start_line', 'start_col', 'end_line', 'end_col',
       'impl_start_line', 'impl_end_line'}
LOCAL = {'local_var', 'param'}


def load(db, suffix):
    c = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
    fid = c.execute("SELECT id FROM files WHERE lower(path) LIKE ?", ('%' + suffix.lower(),)).fetchone()[0]
    cols = [r[1] for r in c.execute('PRAGMA table_info(symbols)')]
    rows = c.execute('SELECT * FROM symbols WHERE file_id = ? ORDER BY id', (fid,)).fetchall()
    return c, fid, cols, rows


def keyed(cols, rows):
    ix = {n: i for i, n in enumerate(cols)}
    byid = {r[ix['id']]: r for r in rows}
    keys, out, seen = {}, {}, {}

    def k(r):
        rid = r[ix['id']]
        if rid in keys:
            return keys[rid]
        p = r[ix['parent_id']]
        pk = k(byid[p]) if p in byid else None
        sig = None if r[ix['kind']] == 'property' else r[ix['signature']]
        base = (r[ix['kind']], (r[ix['qualified_name']] or '').lower(), sig, pk)
        n = seen.get(base, 0)
        seen[base] = n + 1
        keys[rid] = base + (n,)
        return keys[rid]

    for r in rows:
        kk = k(r)
        fp = hashlib.sha1(repr([r[i] for i, n in enumerate(cols) if n not in POS]).encode()).hexdigest()
        out[kk] = (r[ix['id']], fp, r[ix['name']], r[ix['kind']])
    return out


def scope_refs(c, names, fid):
    if not names:
        return 0, 0
    c.execute('CREATE TEMP TABLE IF NOT EXISTS n (n TEXT COLLATE NOCASE PRIMARY KEY)')
    c.execute('DELETE FROM n')
    c.executemany('INSERT OR IGNORE INTO n VALUES (?)', [(x,) for x in names])
    r = c.execute('SELECT count(*), count(DISTINCT file_id) FROM refs WHERE file_id <> ? AND '
                  'name_text COLLATE NOCASE IN (SELECT n FROM n)', (fid,)).fetchone()
    return r


def main():
    b, bf, bcols, brows = load(sys.argv[1], sys.argv[3])
    a, af, acols, arows = load(sys.argv[2], sys.argv[3])
    kb, ka = keyed(bcols, brows), keyed(acols, arows)
    kept_today = len({v[0] for v in kb.values()} & {v[0] for v in ka.values()})
    same = [k for k in ka if k in kb and ka[k][1] == kb[k][1]]
    changed = [k for k in ka if k in kb and ka[k][1] != kb[k][1]]
    added = [k for k in ka if k not in kb]
    removed = [k for k in kb if k not in ka]
    print('symbols before %d after %d' % (len(brows), len(arows)))
    print('ids kept today %d (churn %d)' % (kept_today, len(arows) - kept_today))
    print('reuse: claimed-same %d claimed-changed %d added %d removed %d' % (len(same), len(changed), len(added), len(removed)))
    ids = ','.join(str(v[0]) for v in kb.values()) or '-1'
    for t, col in [('refs', 'symbol_id'), ('call_edges', 'target_symbol_id'),
                   ('member_accesses', 'member_symbol_id'), ('ref_types', 'type_symbol_id')]:
        try:
            if t == 'refs':
                n = b.execute('SELECT count(*) FROM refs WHERE file_id <> ? AND symbol_id IN (%s)' % ids, (bf,)).fetchone()[0]
            else:
                n = b.execute('SELECT count(*) FROM %s WHERE %s IN (%s)' % (t, col, ids)).fetchone()[0]
            print('foreign rows bound before: %s.%s %d' % (t, col, n))
        except sqlite3.Error as e:
            print('foreign %s: %s' % (t, e))
    names_today = {v[2].lower() for v in list(kb.values()) + list(ka.values()) if v[3] not in LOCAL and v[2]}
    moved = changed + added
    names_reuse = {ka[k][2].lower() for k in moved if ka[k][3] not in LOCAL and ka[k][2]} | \
                  {kb[k][2].lower() for k in removed + changed if kb[k][3] not in LOCAL and kb[k][2]}
    print('scope names today %d -> refs/files elsewhere %s' % (len(names_today), scope_refs(b, names_today, bf)))
    print('scope names reuse %d -> refs/files elsewhere %s' % (len(names_reuse), scope_refs(b, names_reuse, bf)))
    for k in (changed + added + removed)[:15]:
        print('  moved:', k[:2], k[2][:60] if k[2] else k[2])


main()
