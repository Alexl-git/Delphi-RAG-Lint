unit DRagLint.Storage.Schema;

interface

const
  SCHEMA_VERSION = 15;

  // First index in SCHEMA_DDL that requires the SQLite FTS5 module.
  // Statements before this index are plain DDL safe on any SQLite build.
  // v14 (D5): call_edges (base SQLite, no FTS5) was inserted at indices
  // 47-49 (before the FTS5 block), so the FTS5-first index shifted from
  // 47 to 50 -- update this constant whenever entries are inserted before
  // the FTS5 block.
  // v15: type_helpers (base SQLite, no FTS5) adds 3 more statements,
  // shifting the FTS5-first index from 50 to 53.
  SCHEMA_DDL_FTS5_FIRST = 53;

  // Each statement is terminated with a semicolon on its own conceptual block.
  // We rely on FireDAC ExecSQL with a single statement per call (split at ';').
  //
  // INVARIANT (v0.83.1): no statement here may reference a column that was
  // retrofitted onto an existing table by a Migrate() ALTER (v9 impl spans,
  // v11 heritage, v12 is_virtual, v13 refs.enclosing_symbol_id). This array
  // runs BEFORE the ALTERs, and CREATE TABLE IF NOT EXISTS leaves an old
  // table's shape untouched -- so e.g. an index on such a column aborts the
  // whole migration with "no such column" on every pre-vN database. Indexes
  // on retrofitted columns belong in Migrate(), after their ALTER.
  SCHEMA_DDL: array[0..57] of string = (
    'CREATE TABLE IF NOT EXISTS schema_meta (' + '  key   TEXT PRIMARY KEY,' + '  value TEXT NOT NULL' + ')',

    'CREATE TABLE IF NOT EXISTS files (' + '  id          INTEGER PRIMARY KEY,' + '  path        TEXT NOT NULL UNIQUE,' + '  mtime_unix  INTEGER NOT NULL,' +
    '  sha256      TEXT NOT NULL,' + '  parsed_at   INTEGER NOT NULL,' + '  language    TEXT NOT NULL' + ')',

    'CREATE TABLE IF NOT EXISTS symbols (' + '  id              INTEGER PRIMARY KEY,' + '  file_id         INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  parent_id       INTEGER REFERENCES symbols(id) ON DELETE CASCADE,' + '  kind            TEXT NOT NULL,' + '  name            TEXT NOT NULL,' +
    '  qualified_name  TEXT NOT NULL,' + '  signature       TEXT,' + '  modifiers       TEXT,' + '  section         TEXT,' + // interface | implementation (usability)
    // v11 (M1): raw ancestor list text for class/interface symbols ('TBar, IBaz');
    // NULL for non-class/interface or no ancestors. Migrate() ALTERs it onto
    // pre-v11 tables. Name normalization + cross-unit resolution happen later.
    '  heritage        TEXT,' +
    // v12 (M1): 1 when a method is virtually dispatched (virtual/dynamic/override),
    // else 0/NULL. Powers cross-unit virtual-method-in-constructor. Migrate() ALTERs.
    '  is_virtual      INTEGER,' +
    '  start_line      INTEGER NOT NULL,' + '  start_col       INTEGER NOT NULL,' + '  end_line        INTEGER NOT NULL,' + '  end_col         INTEGER NOT NULL,' +
    // v9: implementation body span (header..final 'end'); 0 when no body.
    // Migrate() ALTERs these onto pre-v9 tables (CREATE TABLE IF NOT EXISTS
    // does not add columns to an existing table).
    '  impl_start_line INTEGER,' + '  impl_end_line   INTEGER' + ')',

    'CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name)', 'CREATE INDEX IF NOT EXISTS idx_symbols_qname ON symbols(qualified_name)',
    'CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file_id)', 'CREATE INDEX IF NOT EXISTS idx_symbols_parent ON symbols(parent_id)',

    'CREATE TABLE IF NOT EXISTS refs (' + '  id          INTEGER PRIMARY KEY,' + '  symbol_id   INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  file_id     INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' + '  kind        TEXT NOT NULL,' + '  name_text   TEXT NOT NULL,' + '  start_line  INTEGER NOT NULL,' +
    '  start_col   INTEGER NOT NULL,' + '  end_line    INTEGER NOT NULL,' + '  end_col     INTEGER NOT NULL,' +
    // v13 (v0.82): the innermost routine whose impl body [impl_start_line..
    // impl_end_line] contains this ref's start_line; NULL when the ref is not
    // inside any routine body. Attributed per-file in IndexFile. Migrate()
    // ALTERs it onto pre-v13 tables (additive; CREATE TABLE IF NOT EXISTS
    // never adds columns to an existing table).
    '  enclosing_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL' + ')',

    // v0.42 perf: per-file re-index does DELETE FROM refs WHERE file_id, and
    // deleting a symbol fires the FK refs.symbol_id ON DELETE SET NULL. Without
    // these two indexes both operations scan the whole refs table, so per-file
    // indexing cost grew with the DB (0.04 -> 0.55 s/file fresh; ~3.2 s/file
    // re-index on a 1.2 GB DB). With them it's an index seek.
    'CREATE INDEX IF NOT EXISTS idx_refs_file ON refs(file_id)', 'CREATE INDEX IF NOT EXISTS idx_refs_symbol ON refs(symbol_id)',
    // v13 note: idx_refs_enclosing (on refs.enclosing_symbol_id) is created in
    // Migrate() after the ALTER that retrofits the column -- see the INVARIANT
    // comment above SCHEMA_DDL. Do not add it here.

    // v2: trigram inverted index for fast fuzzy lookup. Populated lazily on
    // first fuzzy query for any DB that's missing it (so v1 .sqlite files
    // upgrade transparently).
    'CREATE TABLE IF NOT EXISTS symbol_trigrams (' + '  trigram     TEXT NOT NULL,' + '  symbol_id   INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  PRIMARY KEY (trigram, symbol_id)' + ') WITHOUT ROWID',

    'CREATE INDEX IF NOT EXISTS idx_symbol_trigrams_trigram ' + '  ON symbol_trigrams(trigram)',

    // v0.42 perf: the PK (trigram, symbol_id) can't serve symbol_id-only
    // lookups, so the FK symbol_trigrams.symbol_id ON DELETE CASCADE scanned
    // the entire (multi-million row) trigram table for every symbol deleted
    // during a per-file re-index. Index symbol_id so the cascade is a seek.
    'CREATE INDEX IF NOT EXISTS idx_symbol_trigrams_symbol ' + '  ON symbol_trigrams(symbol_id)',

    // v3: compiler-log ingest. One row per finding extracted from a
    // dcc32/dcc64/msbuild log; cross-referenced to the files table when
    // the path matches an indexed file (otherwise file_id is NULL and the
    // raw path is preserved in raw_path).
    'CREATE TABLE IF NOT EXISTS compiler_findings (' + '  id          INTEGER PRIMARY KEY,' + '  file_id     INTEGER REFERENCES files(id) ON DELETE SET NULL,' +
    '  raw_path    TEXT NOT NULL,' + '  code        TEXT NOT NULL,' + '  severity    TEXT NOT NULL,' + '  line_no     INTEGER,' + '  col_no      INTEGER,' +
    '  message     TEXT NOT NULL,' + '  imported_at INTEGER NOT NULL' + ')',

    'CREATE INDEX IF NOT EXISTS idx_compiler_findings_code ' + '  ON compiler_findings(code)',

    // v4: symbol-level documentation comments (XMLDoc, PasDoc, oneline).
    // One row per documented symbol. Format-tagged so future passes can
    // target a style. raw_block preserves the original text for fallback.
    'CREATE TABLE IF NOT EXISTS symbol_docs (' + '  symbol_id        INTEGER PRIMARY KEY REFERENCES symbols(id) ON DELETE CASCADE,' + '  format           TEXT NOT NULL,' +
    '  raw_block        TEXT NOT NULL,' + '  summary          TEXT,' + '  remarks          TEXT,' + '  returns_text     TEXT,' + '  params_json      TEXT,' +
    '  exceptions_json  TEXT,' + '  example_text     TEXT,' + '  seealso_json     TEXT,' + '  since_text       TEXT,' + '  deprecated       INTEGER NOT NULL DEFAULT 0,' +
    '  start_line       INTEGER,' + '  end_line         INTEGER' + ')',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_format ON symbol_docs(format)',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_deprecated ' + '  ON symbol_docs(deprecated) WHERE deprecated = 1',

    // v0.40.4: unit_uses captures every entry in every uses clause across the
    // codebase. One row per (file, section, unit_name). Powers circular-
    // dependency detection, interface->implementation move-down suggestions,
    // and unused-unit elimination utilities in graphing + lint tools.
    'CREATE TABLE IF NOT EXISTS unit_uses (' + '  id              INTEGER PRIMARY KEY,' + '  file_id         INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  unit_name       TEXT NOT NULL,' +
    // Lowercased trailing segment for join-friendly lookups against files.
    // For "System.SysUtils" this is "sysutils" so we can match
    // files.path -> basename -> stem -> lowercase.
    '  unit_name_norm  TEXT NOT NULL,' + '  section         TEXT NOT NULL,' + // interface|implementation|program|package
    '  in_path         TEXT,' + // text from `in ''...''`; NULL if absent
    '  target_file_id  INTEGER REFERENCES files(id) ON DELETE SET NULL,' + '  start_line      INTEGER NOT NULL,' + '  start_col       INTEGER NOT NULL,' +
    '  end_line        INTEGER,' + '  end_col         INTEGER' + ')',

    'CREATE INDEX IF NOT EXISTS idx_unit_uses_file ' + '  ON unit_uses(file_id)', 'CREATE INDEX IF NOT EXISTS idx_unit_uses_unit_norm ' + '  ON unit_uses(unit_name_norm)',
    'CREATE INDEX IF NOT EXISTS idx_unit_uses_section ' + '  ON unit_uses(section)', 'CREATE INDEX IF NOT EXISTS idx_unit_uses_target ' +
    '  ON unit_uses(target_file_id) WHERE target_file_id IS NOT NULL',

    // v0.40.5 Tier 2: live Firebird snapshot tables.
    // Each snapshot stamps `snapshot_at` so multiple snapshots can coexist
    // for drift detection (compare runs across days/weeks).
    'CREATE TABLE IF NOT EXISTS fb_relations (' + '  id                   INTEGER PRIMARY KEY,' + '  name                 TEXT NOT NULL,' +
    '  sql_table_symbol_id  INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' + '  owner                TEXT,' + '  system_flag          INTEGER NOT NULL DEFAULT 0,' +
    '  description          TEXT,' + '  snapshot_at          INTEGER NOT NULL' + ')', 'CREATE INDEX IF NOT EXISTS idx_fb_relations_name ON fb_relations(name)',

    'CREATE TABLE IF NOT EXISTS fb_columns (' + '  id                   INTEGER PRIMARY KEY,' +
    '  relation_id          INTEGER NOT NULL REFERENCES fb_relations(id) ON DELETE CASCADE,' + '  name                 TEXT NOT NULL,' +
    '  position             INTEGER NOT NULL,' + '  field_source         TEXT,' + '  field_type           INTEGER,' + '  field_length         INTEGER,' +
    '  field_scale          INTEGER,' + '  field_precision      INTEGER,' + '  nullable             INTEGER NOT NULL DEFAULT 1,' + '  default_value        TEXT,' +
    '  sql_column_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' + '  description          TEXT,' + '  snapshot_at          INTEGER NOT NULL' + ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_columns_relation ON fb_columns(relation_id)', 'CREATE INDEX IF NOT EXISTS idx_fb_columns_name ON fb_columns(name)',

    'CREATE TABLE IF NOT EXISTS fb_field_info (' + '  id              INTEGER PRIMARY KEY,' + '  field_name      TEXT NOT NULL,' + '  table_name      TEXT,' +
    '  display_label   TEXT,' + '  display_format  TEXT,' + '  edit_format     TEXT,' + '  visible         INTEGER,' + '  read_only       INTEGER,' + '  triggered       INTEGER,' +
    '  display_width   INTEGER,' + '  fib_version     INTEGER,' + '  snapshot_at     INTEGER NOT NULL' + ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_field_info_field ON fb_field_info(field_name)', 'CREATE INDEX IF NOT EXISTS idx_fb_field_info_table ON fb_field_info(table_name)',

    'CREATE TABLE IF NOT EXISTS fb_datasets (' + '  id                          INTEGER PRIMARY KEY,' + '  ds_id                       INTEGER,' +
    '  description                 TEXT,' + '  select_sql                  TEXT,' + '  update_sql                  TEXT,' + '  insert_sql                  TEXT,' +
    '  delete_sql                  TEXT,' + '  refresh_sql                 TEXT,' + '  name_generator              TEXT,' + '  key_field                   TEXT,' +
    '  update_table_name           TEXT,' + '  update_only_modified_fields INTEGER,' + '  conditions                  TEXT,' + '  fib_version                 INTEGER,' +
    '  snapshot_at                 INTEGER NOT NULL' + ')', 'CREATE INDEX IF NOT EXISTS idx_fb_datasets_ds_id ON fb_datasets(ds_id)',
    'CREATE INDEX IF NOT EXISTS idx_fb_datasets_table ON fb_datasets(update_table_name)',

    'CREATE TABLE IF NOT EXISTS fb_enum_values (' + '  id           INTEGER PRIMARY KEY,' + '  enum_name    TEXT NOT NULL,' + '  value_code   TEXT NOT NULL,' +
    '  value_label  TEXT,' + '  fib_version  INTEGER,' + '  snapshot_at  INTEGER NOT NULL' + ')', 'CREATE INDEX IF NOT EXISTS idx_fb_enum_name ON fb_enum_values(enum_name)',

    // v0.40.5 Tier 3: Delphi <-> SQL ORM bindings.
    // Cross-DB: delphi_db_index / sql_db_index track which --db each end
    // came from (matches the LSP store ordering). delphi_symbol_id and
    // sql_symbol_id are LOCAL to their respective DBs.
    'CREATE TABLE IF NOT EXISTS orm_links (' + '  id                INTEGER PRIMARY KEY,' + '  delphi_symbol_id  INTEGER NOT NULL,' +
    '  delphi_db_index   INTEGER NOT NULL DEFAULT 0,' + '  sql_symbol_id     INTEGER NOT NULL,' + '  sql_db_index      INTEGER NOT NULL DEFAULT 0,' +
    '  confidence        REAL NOT NULL DEFAULT 1.0,' + '  link_kind         TEXT NOT NULL,' + // class_to_table | iface_to_table | field_to_column
    '  evidence          TEXT,' + '  computed_at       INTEGER NOT NULL' + ')', 'CREATE INDEX IF NOT EXISTS idx_orm_links_delphi ON orm_links(delphi_symbol_id, delphi_db_index)',
    'CREATE INDEX IF NOT EXISTS idx_orm_links_sql    ON orm_links(sql_symbol_id, sql_db_index)', 'CREATE INDEX IF NOT EXISTS idx_orm_links_kind   ON orm_links(link_kind)',

    // v8 (2026-06-17): Spring4D DI bindings. One row per resolved
    // RegisterType<TImpl>.Implements<IIntf> registration. interface_name and
    // impl_name are stored verbatim, including nested generics. Per-file cascade
    // matches the symbols/refs reindex path.
    'CREATE TABLE IF NOT EXISTS di_bindings (' + '  id             INTEGER PRIMARY KEY,' + '  file_id        INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  interface_name TEXT NOT NULL,' + '  impl_name      TEXT NOT NULL,' + '  lifetime       TEXT NOT NULL,' + '  start_line     INTEGER NOT NULL,' +
    '  start_col      INTEGER NOT NULL,' + '  end_line       INTEGER NOT NULL,' + '  end_col        INTEGER NOT NULL' + ')',
    'CREATE INDEX IF NOT EXISTS idx_di_interface ON di_bindings(interface_name)', 'CREATE INDEX IF NOT EXISTS idx_di_impl      ON di_bindings(impl_name)',

    // v14 (D5): resolved call-site edges. One row per ref that was resolved
    // to a concrete call target; ref_id is the PK so a ref resolves to at
    // most one edge. receiver_type_symbol_id is the (optional) statically
    // known type of the call receiver, used to disambiguate overloads/
    // virtual dispatch in later D5 tasks. Base SQLite only (no FTS5), so it
    // is placed before the FTS5 block -- keep SCHEMA_DDL_FTS5_FIRST in sync.
    'CREATE TABLE IF NOT EXISTS call_edges (' +
    '  ref_id                  INTEGER NOT NULL PRIMARY KEY REFERENCES refs(id) ON DELETE CASCADE,' +
    '  target_symbol_id        INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  confidence              TEXT    NOT NULL,' +
    '  receiver_type_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_call_edges_target ON call_edges(target_symbol_id)',
    'CREATE INDEX IF NOT EXISTS idx_call_edges_ref    ON call_edges(ref_id)',

    // v15: first-class helper-target edges. One row per record/class helper
    // declaration linked to its target type (e.g. 'record helper for TColor').
    // Captured at parse time from the declHelper node (the target type in the
    // typeref after the 'for' keyword; helper-marked symbols carry is_helper=1
    // and the target text in heritage), resolved and linked at index time
    // (like type_ancestors).
    'CREATE TABLE IF NOT EXISTS type_helpers (' +
      '  helper_symbol_id INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
      '  target_name      TEXT NOT NULL,' +
      '  target_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
      '  target_file_id   INTEGER,' +
      '  helper_kind      TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS idx_type_helpers_helper ON type_helpers(helper_symbol_id)',
    'CREATE INDEX IF NOT EXISTS idx_type_helpers_target ON type_helpers(target_name)'

    // v10: string-content index (text search) --------------------------------
    , 'CREATE TABLE IF NOT EXISTS string_literals (' + '  id         INTEGER PRIMARY KEY,' +
    '  file_id    INTEGER NOT NULL REFERENCES files(id)  ON DELETE CASCADE,' +
    '  symbol_id  INTEGER          REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  source     TEXT NOT NULL,' + '  kind       TEXT NOT NULL,' + '  owner_name TEXT,' +
    '  text       TEXT NOT NULL,' + '  start_line INTEGER NOT NULL,' + '  start_col INTEGER NOT NULL,' +
    '  end_line   INTEGER NOT NULL,' + '  end_col   INTEGER NOT NULL' + ')'
    , 'CREATE INDEX IF NOT EXISTS idx_string_literals_file   ON string_literals(file_id)'
    , 'CREATE INDEX IF NOT EXISTS idx_string_literals_symbol ON string_literals(symbol_id)'
    , 'CREATE INDEX IF NOT EXISTS idx_string_literals_source ON string_literals(source)'
    , 'CREATE VIRTUAL TABLE IF NOT EXISTS string_fts USING fts5(' +
    '  text, content=''string_literals'', content_rowid=''id'', tokenize=''unicode61'')'
    , 'CREATE VIRTUAL TABLE IF NOT EXISTS string_fts_tri USING fts5(' +
    '  text, content=''string_literals'', content_rowid=''id'', tokenize=''trigram'')'
    , 'CREATE TRIGGER IF NOT EXISTS string_literals_ai AFTER INSERT ON string_literals BEGIN' +
    '  INSERT INTO string_fts(rowid, text) VALUES (new.id, new.text);' +
    '  INSERT INTO string_fts_tri(rowid, text) VALUES (new.id, new.text); END'
    , 'CREATE TRIGGER IF NOT EXISTS string_literals_ad AFTER DELETE ON string_literals BEGIN' +
    '  INSERT INTO string_fts(string_fts, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts_tri(string_fts_tri, rowid, text) VALUES (''delete'', old.id, old.text); END'
    , 'CREATE TRIGGER IF NOT EXISTS string_literals_au AFTER UPDATE ON string_literals BEGIN' +
    '  INSERT INTO string_fts(string_fts, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts_tri(string_fts_tri, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts(rowid, text) VALUES (new.id, new.text);' +
    '  INSERT INTO string_fts_tri(rowid, text) VALUES (new.id, new.text); END');

implementation

end.
