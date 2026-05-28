#!/usr/bin/env python
import sqlite3
import sys

db_path = sys.argv[1]
try:
    c = sqlite3.connect(db_path)
    r = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='symbol_docs'").fetchall()
    c.close()
    if r:
        print('symbol_docs')
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
