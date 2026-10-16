"""Compare two drag-lint index databases of the SAME source tree, table by table.

Used to prove an indexer performance change is output-neutral. Rows are compared
by NATURAL KEY, not by id: every id column is translated in SQL into what it
names (a file -> its path; a symbol -> file, kind, qualified name, position; a
ref -> file, kind, name, span; a literal -> file, position, kind, source), so an
edit to ONE source file between the two runs -- which shifts every id allocated
after it -- shows up as that file's rows and nothing else.

Memory stays flat on a multi-million-row index: each row is hashed and summed
into one order-independent digest per (table, owning file), and only the groups
whose digests differ are re-read to print sample rows.

FTS5 shadow tables are skipped -- their segment layout depends on flush order,
not content -- and each FTS5 index is compared through its fts5vocab 'instance'
view instead: (term, column, offset) per literal. Wall-clock values (*_at
columns, schema_meta *_unix keys), sqlite_stat1 and the closure_cache table with its
schema_meta key are excluded.

Files whose sha256 differs between the two databases are reported as SOURCE
CHANGED and their own groups are excluded; rows in OTHER files that differ
because they point into a changed file are still reported, marked as such.

usage: python index_db_diff.py <a.sqlite> <b.sqlite> [--show N]
exit 0 = identical (outside changed sources), 1 = differences found.
"""
import hashlib
import sqlite3
import sys

MASK = 0xFFFFFFFFFFFFFFFF


def SK(a, f):
    """Natural key of the symbol aliased `a`, whose file is aliased `f`."""
    return "lower(%s.path), %s.kind, %s.qualified_name, %s.start_line, %s.start_col" % (f, a, a, a, a)


def SYM(a, f, col):
    return "LEFT JOIN symbols %s ON %s.id = %s LEFT JOIN files %s ON %s.id = %s.file_id" % (a, a, col, f, f, a)


# name -> (select list with the GROUP expression first, FROM/JOIN clause, group expression)
TABLES = {
    'files': (
        "lower(f.path), f.path, f.mtime_unix, f.sha256, f.language, f.last_compiled_unix, f.indexed_at_fingerprint",
        "files f", "lower(f.path)"),
    'symbols': (
        "lower(f.path), s.kind, s.name, s.qualified_name, s.signature, s.modifiers, s.section, s.heritage, "
        "s.is_virtual, s.start_line, s.start_col, s.end_line, s.end_col, s.impl_start_line, s.impl_end_line, "
        "s.prop_access, s.directives, s.vis_explicit, s.generic_params, s.is_helper, " + SK('p', 'pf'),
        "symbols s JOIN files f ON f.id = s.file_id " + SYM('p', 'pf', 's.parent_id'), "lower(f.path)"),
    'refs': (
        "lower(f.path), r.kind, r.name_text, r.start_line, r.start_col, r.end_line, r.end_col, r.receiver_text, "
        "r.external_target, " + SK('t', 'tf') + ", " + SK('e', 'ef'),
        "refs r JOIN files f ON f.id = r.file_id " + SYM('t', 'tf', 'r.symbol_id') + " " + SYM('e', 'ef', 'r.enclosing_symbol_id'),
        "lower(f.path)"),
    'call_edges': (
        "lower(f.path), r.kind, r.name_text, r.start_line, r.start_col, r.end_line, r.end_col, c.confidence, "
        + SK('t', 'tf') + ", " + SK('v', 'vf'),
        "call_edges c JOIN refs r ON r.id = c.ref_id JOIN files f ON f.id = r.file_id "
        + SYM('t', 'tf', 'c.target_symbol_id') + " " + SYM('v', 'vf', 'c.receiver_type_symbol_id'),
        "lower(f.path)"),
    'member_accesses': (
        "lower(f.path), r.kind, r.name_text, r.start_line, r.start_col, r.end_line, r.end_col, m.mode, "
        "m.accessor_kind, " + SK('t', 'tf') + ", " + SK('a', 'af') + ", " + SK('v', 'vf'),
        "member_accesses m JOIN refs r ON r.id = m.ref_id JOIN files f ON f.id = r.file_id "
        + SYM('t', 'tf', 'm.member_symbol_id') + " " + SYM('a', 'af', 'm.accessor_symbol_id') + " "
        + SYM('v', 'vf', 'm.receiver_type_symbol_id'),
        "lower(f.path)"),
    'string_literals': (
        "lower(f.path), l.source, l.kind, l.owner_name, l.text, l.start_line, l.start_col, l.end_line, l.end_col, "
        + SK('t', 'tf'),
        "string_literals l JOIN files f ON f.id = l.file_id " + SYM('t', 'tf', 'l.symbol_id'), "lower(f.path)"),
    'string_fts_docsize': (
        "lower(f.path), l.source, l.kind, l.start_line, l.start_col, d.sz",
        "string_fts_docsize d JOIN string_literals l ON l.id = d.id JOIN files f ON f.id = l.file_id", "lower(f.path)"),
    'string_fts_tri_docsize': (
        "lower(f.path), l.source, l.kind, l.start_line, l.start_col, d.sz",
        "string_fts_tri_docsize d JOIN string_literals l ON l.id = d.id JOIN files f ON f.id = l.file_id", "lower(f.path)"),
    'symbol_docs': (
        "lower(f.path), " + SK('s', 'f') + ", d.format, d.raw_block, d.summary, d.remarks, d.returns_text, "
        "d.params_json, d.exceptions_json, d.example_text, d.seealso_json, d.since_text, d.deprecated, "
        "d.start_line, d.end_line",
        "symbol_docs d JOIN symbols s ON s.id = d.symbol_id JOIN files f ON f.id = s.file_id", "lower(f.path)"),
    'symbol_facts': (
        "lower(f.path), " + SK('s', 'f') + ", x.reads_fields, x.writes_fields, x.returns_owner, x.cyclomatic, "
        "x.body_loc, x.dfm_event, x.sql_reads, x.sql_writes, x.covered_by, x.mutates_params, x.ui_affinity, "
        "x.touches, x.wiring, x.effect_free, x.effect_summary, x.effect_witness",
        "symbol_facts x JOIN symbols s ON s.id = x.symbol_id JOIN files f ON f.id = s.file_id", "lower(f.path)"),
    'symbol_trigrams': (
        "lower(f.path), " + SK('s', 'f') + ", g.trigram",
        "symbol_trigrams g JOIN symbols s ON s.id = g.symbol_id JOIN files f ON f.id = s.file_id", "lower(f.path)"),
    'type_ancestors': (
        "lower(f.path), " + SK('s', 'f') + ", a.ordinal, a.ancestor_name, a.ancestor_kind, " + SK('t', 'tf')
        + ", lower(af.path), a.ancestor_type_args",
        "type_ancestors a JOIN symbols s ON s.id = a.symbol_id JOIN files f ON f.id = s.file_id "
        + SYM('t', 'tf', 'a.ancestor_symbol_id') + " LEFT JOIN files af ON af.id = a.ancestor_file_id",
        "lower(f.path)"),
    'type_helpers': (
        "lower(f.path), " + SK('s', 'f') + ", h.target_name, " + SK('t', 'tf') + ", lower(hf.path), h.helper_kind",
        "type_helpers h JOIN symbols s ON s.id = h.helper_symbol_id JOIN files f ON f.id = s.file_id "
        + SYM('t', 'tf', 'h.target_symbol_id') + " LEFT JOIN files hf ON hf.id = h.target_file_id",
        "lower(f.path)"),
    'unit_uses': (
        "lower(f.path), u.unit_name, u.unit_name_norm, u.section, u.in_path, lower(tf.path), u.start_line, "
        "u.start_col, u.end_line, u.end_col",
        "unit_uses u JOIN files f ON f.id = u.file_id LEFT JOIN files tf ON tf.id = u.target_file_id", "lower(f.path)"),
    'di_bindings': (
        "lower(f.path), b.interface_name, b.impl_name, b.lifetime, b.start_line, b.start_col, b.end_line, b.end_col",
        "di_bindings b JOIN files f ON f.id = b.file_id", "lower(f.path)"),
    'compiler_findings': (
        "lower(coalesce(f.path, c.raw_path)), c.raw_path, c.code, c.severity, c.line_no, c.col_no, c.message",
        "compiler_findings c LEFT JOIN files f ON f.id = c.file_id", "lower(coalesce(f.path, c.raw_path))"),
    'schema_meta': ("'*', key, value", "schema_meta WHERE key NOT LIKE '%_unix' AND key <> 'closure_cache_fp'", None),
}
# Tables that hold no per-file rows on the corpora this is used for; compared
# generically (every column except ids and *_at) so a non-empty one is not skipped.
GENERIC = ('fb_columns', 'fb_datasets', 'fb_enum_values', 'fb_field_info', 'fb_relations', 'orm_links')
# closure_cache (2026-10-14) is a cache of the compile-closure walk, not index
# data: a fresh copy has none, a run that walked has it.
SKIP = {'sqlite_stat1', 'sqlite_sequence', 'closure_cache'}
FTS_SHADOW_SUFFIXES = ('_data', '_idx', '_config', '_content', '_docsize')


def open_ro(path):
    return sqlite3.connect("file:%s?mode=ro" % path.replace("\\", "/"), uri=True)


def fts_tables(conn):
    return [n for (n,) in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE 'CREATE VIRTUAL TABLE%USING fts5%'")]


def query_for(conn, table):
    if table in TABLES:
        sel, frm, gexpr = TABLES[table]
        return "SELECT %s FROM %s" % (sel, frm), gexpr
    if table in GENERIC:
        cols = [r[1] for r in conn.execute("PRAGMA table_info('%s')" % table)
                if r[1] != 'id' and not r[1].endswith('_at')]
        return "SELECT '*', %s FROM '%s'" % (",".join('"%s"' % c for c in cols), table), None
    raise SystemExit("index_db_diff: no comparison defined for table %r -- add it to TABLES or GENERIC" % table)


def fts_query(fts):
    return ("SELECT lower(f.path), l.source, l.kind, l.start_line, l.start_col, v.term, v.col, v.offset "
            "FROM temp.v_%s v JOIN string_literals l ON l.id = v.doc JOIN files f ON f.id = l.file_id" % fts,
            "lower(f.path)")


def digests(conn, sql):
    out = {}
    for row in conn.execute(sql):
        h = int.from_bytes(hashlib.blake2b(repr(row[1:]).encode("utf-8", "surrogatepass"), digest_size=8).digest(), "little")
        n, acc = out.get(row[0], (0, 0))
        out[row[0]] = (n + 1, (acc + h) & MASK)
    return out


def rows_of(conn, sql, group_expr, group):
    if not group_expr:
        return {tuple(r[1:]) for r in conn.execute(sql)}
    where = (" AND " if " WHERE " in sql else " WHERE ") + "%s = ?" % group_expr
    return {tuple(r[1:]) for r in conn.execute(sql + where, (group,))}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 3
    if "--show" in sys.argv:
        args.remove(str(show))
    pa, pb = args
    ca, cb = open_ro(pa), open_ro(pb)
    for c in (ca, cb):
        for f in fts_tables(c):
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS temp.v_%s USING fts5vocab(main, '%s', 'instance')" % (f, f))

    sha_a = dict(ca.execute("SELECT lower(path), sha256 FROM files"))
    sha_b = dict(cb.execute("SELECT lower(path), sha256 FROM files"))
    changed = {p for p in sha_a.keys() & sha_b.keys() if sha_a[p] != sha_b[p]}
    for p in sorted(changed):
        print("  SOURCE CHANGED between the runs (excluded): %s" % p)
    for p in sorted(sha_a.keys() ^ sha_b.keys()):
        print("  FILE ONLY IN %s: %s" % ("A" if p in sha_a else "B", p))

    def names(c):
        fts = set(fts_tables(c))
        return {n for (n,) in c.execute("SELECT name FROM sqlite_master WHERE type='table'")
                if n not in SKIP and n not in fts
                and not any(n == f + s for f in fts for s in FTS_SHADOW_SUFFIXES)} | \
               {n + '_docsize' for n in fts}
    ta, tb = names(ca), names(cb)
    diffs = 0
    for t in sorted(ta ^ tb):
        print("  TABLE ONLY IN %s: %s" % ("A" if t in ta else "B", t))
        diffs += 1
    jobs = [(t,) + query_for(ca, t) for t in sorted(ta & tb)]
    jobs += [(f + ' (fts5vocab)',) + fts_query(f) for f in sorted(set(fts_tables(ca)) & set(fts_tables(cb)))]
    for label, sql, gexpr in jobs:
        da, db = digests(ca, sql), digests(cb, sql)
        total = sum(n for n, _ in da.values())
        bad = sorted(g for g in da.keys() | db.keys() if g not in changed and da.get(g) != db.get(g))
        print("  %-28s %10d rows  %s" % (label, total, "same" if not bad else "DIFF in %d file(s)" % len(bad)))
        if not bad:
            continue
        diffs += 1
        for g in bad[:show]:
            a, b = rows_of(ca, sql, gexpr, g), rows_of(cb, sql, gexpr, g)
            print("      %s: only A %d, only B %d" % (g, len(a - b), len(b - a)))
            for tag, only in (("A", a - b), ("B", b - a)):
                for r in sorted(only, key=repr)[:show]:
                    into = any(isinstance(v, str) and v in changed for v in r)
                    print("        %s%s %s" % (tag, " [points into a changed file]" if into else "", repr(r)[:220]))
    print("IDENTICAL" + (" (outside %d changed source file(s))" % len(changed) if changed else "")
          if diffs == 0 else "%d TABLE(S) DIFFER" % diffs)
    sys.exit(0 if diffs == 0 else 1)


if __name__ == "__main__":
    main()
