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
exit 0 = identical (outside changed sources), 1 = differences found, 2 = a table has no comparison.
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

def RK(a, f):
    """Natural key of the ref aliased `a`, whose file is aliased `f` (the file's path comes first)."""
    return "lower(%s.path), %s.kind, %s.name_text, %s.start_line, %s.start_col, %s.end_line, %s.end_col" % (
        f, a, a, a, a, a, a)


def REF(a, f, col):
    return "JOIN refs %s ON %s.id = %s JOIN files %s ON %s.id = %s.file_id" % (a, a, col, f, f, a)


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
    # prop_types_filled is '<version>;<unix time of the fill>': the version is compared, the time is not.
    'schema_meta': ("'*', key, CASE WHEN key = 'prop_types_filled' AND instr(value, ';') > 0 "
                    "THEN substr(value, 1, instr(value, ';')) ELSE value END", "schema_meta WHERE key NOT LIKE '%_unix' AND key <> 'closure_cache_fp'", None),
    # 1.52.1 INCR18: the tables the resolve pass and the later extractors added since this tool
    # was written. Without them the tool stopped at the first one ('attributes') with exit 1 --
    # the same code as "differences found".
    'ref_types': (
        RK('r', 'f') + ", x.type_qname, x.via, " + SK('t', 'tf'),
        "ref_types x " + REF('r', 'f', 'x.ref_id') + " " + SYM('t', 'tf', 'x.type_symbol_id'), "lower(f.path)"),
    'ref_element_types': (
        RK('r', 'f') + ", x.type_qname, " + SK('t', 'tf'),
        "ref_element_types x " + REF('r', 'f', 'x.ref_id') + " " + SYM('t', 'tf', 'x.type_symbol_id'), "lower(f.path)"),
    'ref_receivers': (
        RK('r', 'f') + ", " + RK('q', 'qf'),
        "ref_receivers x " + REF('r', 'f', 'x.ref_id') + " " + REF('q', 'qf', 'x.receiver_ref_id'), "lower(f.path)"),
    'ref_host_bindings': (
        RK('r', 'f') + ", lower(hf.path), " + SK('t', 'tf'),
        "ref_host_bindings x " + REF('r', 'f', 'x.ref_id') + " JOIN files hf ON hf.id = x.host_file_id "
        + SYM('t', 'tf', 'x.symbol_id'), "lower(f.path)"),
    'classref_args': (
        RK('r', 'f') + ", x.arg_index, x.confidence, " + SK('p', 'pf') + ", " + SK('c', 'cf'),
        "classref_args x " + REF('r', 'f', 'x.ref_id') + " " + SYM('p', 'pf', 'x.param_symbol_id') + " "
        + SYM('c', 'cf', 'x.class_symbol_id'), "lower(f.path)"),
    'data_flows': (
        "lower(f.path), " + SK('s', 'sf') + ", " + SK('o', 'of') + ", x.dst_kind, x.dst_line, x.dst_col, x.dst_index, "
        "x.dst_name, x.dst_receiver, x.src_kind, x.src_index, x.src_line, x.src_col, x.src_name, x.via_local, x.cond",
        "data_flows x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id') + " "
        + SYM('o', 'of', 'x.owner_id'), "lower(f.path)"),
    'dispatch_edges': (
        SK('b', 'f') + ", x.kind, x.confidence, " + SK('i', 'xf'),
        "dispatch_edges x JOIN symbols b ON b.id = x.base_symbol_id JOIN files f ON f.id = b.file_id "
        + SYM('i', 'xf', 'x.impl_symbol_id'), "lower(f.path)"),
    'init_deps': (
        SK('b', 'f') + ", x.target_unit, x.via_name",
        "init_deps x JOIN symbols b ON b.id = x.unit_symbol_id JOIN files f ON f.id = b.file_id", "lower(f.path)"),
    'inc_variants': (
        "lower(f.path), lower(hf.path), x.variant, x.ctx_sha",
        "inc_variants x JOIN files f ON f.id = x.file_id JOIN files hf ON hf.id = x.host_file_id", "lower(f.path)"),
    'dfm_objects': (
        "lower(f.path), x.ordinal, x.name, x.class_name, x.parent_name, x.obj_kind, x.depth, x.start_line, "
        "x.start_col, x.end_line, x.end_col, " + SK('t', 'tf'),
        "dfm_objects x JOIN files f ON f.id = x.file_id " + SYM('t', 'tf', 'x.symbol_id'), "lower(f.path)"),
    'attributes': (
        "lower(f.path), x.ordinal, x.attr_name, x.arg_text, x.line, x.col, " + SK('t', 'tf'),
        "attributes x JOIN files f ON f.id = x.file_id " + SYM('t', 'tf', 'x.symbol_id'), "lower(f.path)"),
    'comment_facts': (
        "lower(f.path), x.ordinal, x.start_offset, x.end_offset, x.line, x.col, x.end_line, x.kind, x.text, "
        "x.anchor_kind, " + SK('t', 'tf'),
        "comment_facts x JOIN files f ON f.id = x.file_id " + SYM('t', 'tf', 'x.anchor_symbol_id'), "lower(f.path)"),
    'symbol_search': (
        "lower(f.path), " + SK('s', 'f') + ", x.tokens, x.summary, x.remarks",
        "symbol_search x JOIN symbols s ON s.id = x.symbol_id JOIN files f ON f.id = s.file_id", "lower(f.path)"),
    'symbol_search_fts_docsize': (
        "lower(f.path), " + SK('s', 'f') + ", d.sz",
        "symbol_search_fts_docsize d JOIN symbols s ON s.id = d.id JOIN files f ON f.id = s.file_id", "lower(f.path)"),
    # 1.56 lane EXT-S: the tables of the 1.56 extractor bump (DDL: SCHEMA_DDL_V156 in DRagLint.Storage.Schema).
    'symbol_extras': (
        "lower(f.path), " + SK('s', 'sf') + ", x.noreturn, x.variant_part, x.variant_tag, x.param_mode, x.param_index",
        "symbol_extras x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id'), "lower(f.path)"),
    'ds_field_accesses': (
        "lower(f.path), " + SK('s', 'sf') + ", x.ordinal, x.mode, x.line, x.col, x.shape, x.dataset_text, x.field_text, "
        "x.field_name, x.name_kind, x.name_text, x.accessor, x.root_kind, x.root_name, x.root_index, x.with_ctx, "
        "x.rhs_start_line, x.rhs_start_col, x.rhs_end_line, x.rhs_end_col, x.stmt_line, x.stmt_col",
        "ds_field_accesses x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id'), "lower(f.path)"),
    'loop_facts': (
        "lower(f.path), " + SK('s', 'sf') + ", x.ordinal, x.parent, x.kind, x.start_line, x.start_col, x.end_line, "
        "x.end_col, x.cond_start_line, x.cond_start_col, x.cond_end_line, x.cond_end_col",
        "loop_facts x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id'), "lower(f.path)"),
    'call_literal_args': (
        "lower(f.path), " + SK('s', 'sf') + ", x.ordinal, x.call_line, x.call_col, x.callee_name, x.receiver_text, "
        "x.arg_index, x.arg_count, x.lit_line, x.lit_col, x.lit_kind, x.value",
        "call_literal_args x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id'), "lower(f.path)"),
    'indirect_edges': (
        "lower(tf.path), " + SK('t', 'tf') + ", " + SK('c', 'cf') + ", r.kind, r.name_text, r.start_line, r.start_col, "
        "x.kind, x.via_text, lower(bf.path), x.bind_line, x.bind_col, x.confidence",
        "indirect_edges x JOIN symbols t ON t.id = x.target_symbol_id JOIN files tf ON tf.id = t.file_id "
        + SYM('c', 'cf', 'x.caller_symbol_id') + " LEFT JOIN refs r ON r.id = x.ref_id "
        "LEFT JOIN files bf ON bf.id = x.bind_file_id", "lower(tf.path)"),
    # the *_unix stamps differ between two runs by design
    'repo_copy': (
        "'*', x.state, x.repo_path, x.repo_sha256, x.repo_size, x.repo_schema_version, x.copy_format, "
        "x.derived_format, x.last_error", "repo_copy x", None),
    'concept_links': (
        "lower(f.path), x.link_kind, x.confidence, x.table_name, x.field_name, x.line, x.col, x.form_name, "
        "x.form_class, x.component_name, x.dataset_name, " + SK('s', 'sf') + ", " + SK('e', 'ef') + ", x.via, x.caption",
        "concept_links x JOIN files f ON f.id = x.file_id " + SYM('s', 'sf', 'x.symbol_id') + " "
        + SYM('e', 'ef', 'x.enclosing_symbol_id'), "lower(f.path)"),
    'concept_texts_fts_docsize': (
        "'*', t.place, t.text_kind, t.table_name, t.field_name, t.text, d.sz",
        "concept_texts_fts_docsize d JOIN concept_texts t ON t.id = d.id", None),
}
# 1.56: columns a 1.56 writer ALTERs onto an existing table; compared when the database has them
# (a pair of pre-1.56 databases has neither).
OPTIONAL_COLS = {'data_flows': ('x.val_class',), 'symbol_facts': ('x.must_writes',)}
# Per-file tables with no id column but file_id: every other column, grouped by the file's path.
FILE_GENERIC = ('file_includes', 'dfm_nav_nodes', 'dfm_nav_props', 'dfm_properties', 'pp_regions', 'pp_directives',
                'project_settings')
# Tables that hold no per-file rows on the corpora this is used for; compared
# generically (every column except ids and *_at) so a non-empty one is not skipped.
GENERIC = ('fb_columns', 'fb_datasets', 'fb_enum_values', 'fb_field_info', 'fb_relations', 'orm_links',
           'concept_fields', 'concept_texts')   # 1.56 CONCEPT: no per-file rows; ids are excluded
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
        have = {r[1] for r in conn.execute("PRAGMA table_info('%s')" % table)}
        for col in OPTIONAL_COLS.get(table, ()):
            if col.split('.')[1] in have:
                sel += ", " + col
        return "SELECT %s FROM %s" % (sel, frm), gexpr
    if table in GENERIC:
        cols = [r[1] for r in conn.execute("PRAGMA table_info('%s')" % table)
                if r[1] != 'id' and not r[1].endswith('_at')]
        return "SELECT '*', %s FROM '%s'" % (",".join('"%s"' % c for c in cols), table), None
    if table in FILE_GENERIC:
        cols = [r[1] for r in conn.execute("PRAGMA table_info('%s')" % table) if r[1] != 'file_id']
        return ("SELECT lower(f.path), %s FROM '%s' x JOIN files f ON f.id = x.file_id"
                % (",".join('x."%s"' % c for c in cols), table), "lower(f.path)")
    # exit 2, not 1: 1 means "the databases differ", and a caller must not read a missing
    # comparison as a difference (or, worse, a positive control as satisfied).
    sys.stderr.write("index_db_diff: no comparison defined for table %r -- add it to TABLES, GENERIC or FILE_GENERIC\n" % table)
    sys.exit(2)


def fts_query(fts):
    if fts.startswith('concept_texts'):   # 1.56 CONCEPT: content_rowid = concept_texts.id, no per-file rows
        return ("SELECT '*', t.place, t.text_kind, t.table_name, t.field_name, v.term, v.col, v.offset "
                "FROM temp.v_%s v JOIN concept_texts t ON t.id = v.doc" % fts, None)
    if fts.startswith('symbol_search'):   # content_rowid = symbol_id, not a string_literals id
        return ("SELECT lower(f.path), s.kind, s.qualified_name, s.start_line, s.start_col, v.term, v.col, v.offset "
                "FROM temp.v_%s v JOIN symbols s ON s.id = v.doc JOIN files f ON f.id = s.file_id" % fts,
                "lower(f.path)")
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
