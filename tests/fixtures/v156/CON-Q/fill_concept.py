"""v156 CON-Q: hand-fills the concept_* tables (design 2.2) of an indexed copy of the app folder so
that `query --concept` can be tested before the copy step of lane CON-I exists.
usage: python -I fill_concept.py <db> <repo file> <variant>   variant = app | norepo | manyid | missing
"""
import os
import sqlite3
import sys

db_path, repo_path, variant = sys.argv[1], sys.argv[2], sys.argv[3]
con = sqlite3.connect(db_path)
cur = con.cursor()


def file_id(name):
    row = cur.execute("SELECT id, path FROM files WHERE lower(path) LIKE ?", ('%' + name.lower(),)).fetchone()
    assert row, name
    return row[0], row[1]


def line_of(path, marker, nth=1):
    seen = 0
    with open(path, 'r', encoding='ascii') as handle:
        for number, text in enumerate(handle, 1):
            if marker in text:
                seen += 1
                if seen == nth:
                    return number
    raise AssertionError(marker)


def symbol_id(qname_tail):
    row = cur.execute("SELECT id FROM symbols WHERE qualified_name LIKE ? ORDER BY id LIMIT 1",
                      ('%' + qname_tail,)).fetchone()
    assert row, qname_tail
    return row[0]


dfm_id, dfm = file_id('uMain.dfm')
pas_id, pas = file_id('uMain.pas')
tools_id, tools = file_id('uTools.pas')
for table in ('concept_links', 'concept_texts', 'concept_fields', 'repo_copy'):
    cur.execute('DELETE FROM ' + table)

with_repo = variant in ('app', 'manyid')
if with_repo:
    stamp = 1795000000
    os.utime(repo_path, (stamp, stamp))
    cur.execute("INSERT INTO repo_copy (id, state, repo_path, repo_sha256, repo_size, repo_mtime_unix, "
                "repo_schema_version, copied_at_unix, checked_at_unix, copy_format, derived_format, derived_at_unix) "
                "VALUES (1, 'copied', ?, 'x', ?, ?, 5, ?, ?, 1, 1, ?)",
                (repo_path, os.path.getsize(repo_path), stamp, stamp, stamp, stamp))
    fields = [('CUSTOMERS', '', '', ''), ('CUSTOMERS', 'ID', '', 'INTEGER'),
              ('CUSTOMERS', 'NAME', 'Customer name', 'VARCHAR(40)'),
              ('CUSTOMERS', 'CREDIT_LIMIT', 'Credit limit', 'DECFLOAT(16)'), ('CUSTOMERS', 'NOTES', '', 'BLOB'),
              ('SUPPLIERS', '', '', ''), ('SUPPLIERS', 'ID', '', 'INTEGER'),
              ('SUPPLIERS', 'NAME', 'Supplier name', 'VARCHAR(40)'),
              ('ACCOUNTS', '', '', ''), ('ACCOUNTS', 'MAX_CREDIT', 'Limit of the credit', 'DECFLOAT(16)')]
    if variant == 'manyid':
        for number in range(1, 7):
            fields += [('T%d' % number, '', '', ''), ('T%d' % number, 'ID', '', 'INTEGER')]
    cur.executemany("INSERT INTO concept_fields (table_name, field_name, caption, type_text) VALUES (?, ?, ?, ?)", fields)
    cur.executemany("INSERT INTO concept_texts (place, text_kind, table_name, field_name, text) "
                    "VALUES ('repository', ?, ?, ?, ?)",
                    [('caption', 'CUSTOMERS', 'NAME', 'Customer name'),
                     ('description', 'CUSTOMERS', 'NAME', 'Legal name of the buyer'),
                     ('caption', 'CUSTOMERS', 'CREDIT_LIMIT', 'Credit limit'),
                     ('caption', 'SUPPLIERS', 'NAME', 'Supplier name'),
                     ('caption', 'ACCOUNTS', 'MAX_CREDIT', 'Limit of the credit'),
                     ('table-description', 'CUSTOMERS', '', 'Buyers of the shop')])
else:
    state = 'missing' if variant == 'missing' else 'not-configured'
    cur.execute("INSERT INTO repo_copy (id, state, repo_path) VALUES (1, ?, ?)",
                (state, repo_path if variant == 'missing' else ''))

cur.executemany("INSERT INTO concept_texts (place, text_kind, table_name, field_name, text, uses) "
                "VALUES ('project', ?, ?, ?, ?, ?)",
                [('display-label', 'CUSTOMERS', 'NAME', 'Client name', 2),
                 ('grid-caption', 'CUSTOMERS', 'NAME', 'Cust. name', 1),
                 ('hint', 'CUSTOMERS', 'NAME', 'Type the legal name here', 1),
                 ('display-label', '', 'PHONE', 'Phone number', 1)])

link = ("INSERT INTO concept_links (link_kind, confidence, table_name, field_name, file_id, line, col, form_name, "
        "form_class, component_name, dataset_name, symbol_id, enclosing_symbol_id, via, caption) "
        "VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)")
save_id = symbol_id('TfrmMain.Save')
copy_id = symbol_id('uTools.CopyName')
rows = [
    ('persistent-field', 'resolved', 'CUSTOMERS', 'NAME', dfm_id, line_of(dfm, 'qryCustomersNAME'), 'frmMain', 'TfrmMain',
     'qryCustomersNAME', 'qryCustomers', symbol_id('TfrmMain.qryCustomersNAME'), None, 'sql', 'Client name'),
    ('grid-column', 'resolved', 'CUSTOMERS', 'NAME', dfm_id, line_of(dfm, 'colName'), 'frmMain', 'TfrmMain',
     'colName', 'qryCustomers', None, None, 'repo-grid', 'Cust. name'),
    ('edit-control', 'resolved', 'CUSTOMERS', 'NAME', dfm_id, line_of(dfm, 'edName'), 'frmMain', 'TfrmMain',
     'edName', 'qryCustomers', None, None, 'sql', ''),
    ('persistent-field', 'resolved', 'SUPPLIERS', 'NAME', dfm_id, line_of(dfm, 'qrySuppliersNAME'), 'frmMain', 'TfrmMain',
     'qrySuppliersNAME', 'qryCustomers', None, None, 'origin', ''),
    ('persistent-field', 'by-name-only', '', 'PHONE', dfm_id, line_of(dfm, 'qryCustomersPHONE'), 'frmMain', 'TfrmMain',
     'qryCustomersPHONE', 'qryCustomers', None, None, '', 'Phone number'),
    ('code', 'resolved', 'CUSTOMERS', 'NAME', pas_id, line_of(pas, "FieldByName('NAME')"), 'frmMain', 'TfrmMain',
     '', 'qryCustomers', None, save_id, 'FieldByName', ''),
    ('code', 'by-name-only', '', 'NAME', tools_id, line_of(tools, "FieldByName('NAME')"), '', '',
     '', 'pDs', None, copy_id, 'FieldByName', ''),
]
for nth in range(1, 5):
    rows.append(('code', 'by-name-only', '', 'ID', tools_id, line_of(tools, "FieldByName('ID')", nth), '', '',
                 '', 'pDs', None, copy_id, 'FieldByName', ''))
cur.executemany(link, rows)
cur.execute("INSERT INTO concept_texts_fts(concept_texts_fts) VALUES('rebuild')")
con.commit()
con.close()
print('filled', variant)
