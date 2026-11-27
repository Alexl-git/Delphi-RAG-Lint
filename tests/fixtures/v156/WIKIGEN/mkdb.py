"""Builds the hand-filled project index fixture for run_v156_WIKIGEN.ps1 (usage: python -I mkdb.py <db file>)."""
import sqlite3
import sys

c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE files(id INTEGER PRIMARY KEY, path TEXT);
CREATE TABLE symbols(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE repo_copy(id INTEGER PRIMARY KEY, state TEXT, repo_sha256 TEXT, copied_at_unix INTEGER);
CREATE TABLE concept_texts(id INTEGER PRIMARY KEY, place TEXT, text_kind TEXT, table_name TEXT, field_name TEXT, text TEXT);
CREATE TABLE concept_links(id INTEGER PRIMARY KEY, link_kind TEXT, confidence TEXT, table_name TEXT, field_name TEXT,
  file_id INTEGER, line INTEGER, col INTEGER, form_name TEXT, form_class TEXT, component_name TEXT, dataset_name TEXT,
  symbol_id INTEGER, enclosing_symbol_id INTEGER, via TEXT, caption TEXT);
INSERT INTO files VALUES (1, 'C:\\P\\uMain.dfm'), (2, 'C:\\P\\uMain.pas'), (3, 'C:\\P\\uTools.pas');
INSERT INTO symbols VALUES (1, 'CityChanged'), (2, 'CopyCity');
INSERT INTO repo_copy VALUES (1, 'copied', 'deadbeef', 1700000000);
INSERT INTO concept_texts VALUES (1, 'project', 'display-label', 'CUSTOMER', 'CITY', 'Town');
INSERT INTO concept_links VALUES
 (1, 'grid-column', 'resolved', 'CUSTOMER', 'CITY', 1, 12, 1, 'frmMain', 'TfrmMain', 'colCity', 'qryCust', NULL, NULL, 'sql', ''),
 (2, 'edit-control', 'resolved', 'CUSTOMER', 'CITY', 1, 30, 1, 'frmMain', 'TfrmMain', 'edCity', 'qryCust', NULL, NULL, 'sql', ''),
 (3, 'code', 'resolved', 'CUSTOMER', 'CITY', 2, 57, 1, '', '', '', 'qryCust', NULL, 1, 'sql', ''),
 (4, 'code', 'by-name-only', '', 'CITY', 3, 9, 1, '', '', '', '', NULL, 2, '', '');
""")
c.commit()
c.close()
