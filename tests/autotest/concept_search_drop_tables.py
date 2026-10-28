"""Drop the concept-search tables + triggers from a drag-lint index DB.

Used by run_concept_search.ps1 to simulate an index built before the feature
existed. Usage: python -I concept_search_drop_tables.py <db>
Prints DROPPED <n> on success; exit 1 if anything concept-search remains, exit 2 if there was nothing to drop\n(a drop of nothing would make the degrade check vacuous).
"""
import sqlite3
import sys

db = sys.argv[1]
con = sqlite3.connect(db)
had = con.execute("SELECT count(*) FROM sqlite_master WHERE name='symbol_search_fts'").fetchone()[0]
if not had:
    print('NOTHING-TO-DROP: symbol_search_fts absent before the drop')
    sys.exit(2)
names = [r[0] for r in con.execute(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'symbol_search%'")]
for n in names:
    con.execute('DROP TRIGGER IF EXISTS "%s"' % n)
con.execute('DROP TABLE IF EXISTS symbol_search_fts')
con.execute('DROP TABLE IF EXISTS symbol_search')
con.commit()
left = [r[0] for r in con.execute(
    "SELECT name FROM sqlite_master WHERE name LIKE 'symbol_search%'")]
con.close()
print('DROPPED triggers=%d left=%s' % (len(names), ','.join(left)))
sys.exit(1 if left else 0)
