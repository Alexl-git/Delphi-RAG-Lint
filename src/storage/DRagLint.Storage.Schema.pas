unit DRagLint.Storage.Schema;

interface

const
  SCHEMA_VERSION = 6;

  // Each statement is terminated with a semicolon on its own conceptual block.
  // We rely on FireDAC ExecSQL with a single statement per call (split at ';').
  SCHEMA_DDL: array[0..36] of string = (
    'CREATE TABLE IF NOT EXISTS schema_meta (' +
    '  key   TEXT PRIMARY KEY,' +
    '  value TEXT NOT NULL' +
    ')',

    'CREATE TABLE IF NOT EXISTS files (' +
    '  id          INTEGER PRIMARY KEY,' +
    '  path        TEXT NOT NULL UNIQUE,' +
    '  mtime_unix  INTEGER NOT NULL,' +
    '  sha256      TEXT NOT NULL,' +
    '  parsed_at   INTEGER NOT NULL,' +
    '  language    TEXT NOT NULL' +
    ')',

    'CREATE TABLE IF NOT EXISTS symbols (' +
    '  id              INTEGER PRIMARY KEY,' +
    '  file_id         INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  parent_id       INTEGER REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  kind            TEXT NOT NULL,' +
    '  name            TEXT NOT NULL,' +
    '  qualified_name  TEXT NOT NULL,' +
    '  signature       TEXT,' +
    '  modifiers       TEXT,' +
    '  start_line      INTEGER NOT NULL,' +
    '  start_col       INTEGER NOT NULL,' +
    '  end_line        INTEGER NOT NULL,' +
    '  end_col         INTEGER NOT NULL' +
    ')',

    'CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name)',
    'CREATE INDEX IF NOT EXISTS idx_symbols_qname ON symbols(qualified_name)',
    'CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file_id)',
    'CREATE INDEX IF NOT EXISTS idx_symbols_parent ON symbols(parent_id)',

    'CREATE TABLE IF NOT EXISTS refs (' +
    '  id          INTEGER PRIMARY KEY,' +
    '  symbol_id   INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  file_id     INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  kind        TEXT NOT NULL,' +
    '  name_text   TEXT NOT NULL,' +
    '  start_line  INTEGER NOT NULL,' +
    '  start_col   INTEGER NOT NULL,' +
    '  end_line    INTEGER NOT NULL,' +
    '  end_col     INTEGER NOT NULL' +
    ')',

    // v2: trigram inverted index for fast fuzzy lookup. Populated lazily on
    // first fuzzy query for any DB that's missing it (so v1 .sqlite files
    // upgrade transparently).
    'CREATE TABLE IF NOT EXISTS symbol_trigrams (' +
    '  trigram     TEXT NOT NULL,' +
    '  symbol_id   INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  PRIMARY KEY (trigram, symbol_id)' +
    ') WITHOUT ROWID',

    'CREATE INDEX IF NOT EXISTS idx_symbol_trigrams_trigram ' +
    '  ON symbol_trigrams(trigram)',

    // v3: compiler-log ingest. One row per finding extracted from a
    // dcc32/dcc64/msbuild log; cross-referenced to the files table when
    // the path matches an indexed file (otherwise file_id is NULL and the
    // raw path is preserved in raw_path).
    'CREATE TABLE IF NOT EXISTS compiler_findings (' +
    '  id          INTEGER PRIMARY KEY,' +
    '  file_id     INTEGER REFERENCES files(id) ON DELETE SET NULL,' +
    '  raw_path    TEXT NOT NULL,' +
    '  code        TEXT NOT NULL,' +
    '  severity    TEXT NOT NULL,' +
    '  line_no     INTEGER,' +
    '  col_no      INTEGER,' +
    '  message     TEXT NOT NULL,' +
    '  imported_at INTEGER NOT NULL' +
    ')',

    'CREATE INDEX IF NOT EXISTS idx_compiler_findings_code ' +
    '  ON compiler_findings(code)',

    // v4: symbol-level documentation comments (XMLDoc, PasDoc, oneline).
    // One row per documented symbol. Format-tagged so future passes can
    // target a style. raw_block preserves the original text for fallback.
    'CREATE TABLE IF NOT EXISTS symbol_docs (' +
    '  symbol_id        INTEGER PRIMARY KEY REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  format           TEXT NOT NULL,' +
    '  raw_block        TEXT NOT NULL,' +
    '  summary          TEXT,' +
    '  remarks          TEXT,' +
    '  returns_text     TEXT,' +
    '  params_json      TEXT,' +
    '  exceptions_json  TEXT,' +
    '  example_text     TEXT,' +
    '  seealso_json     TEXT,' +
    '  since_text       TEXT,' +
    '  deprecated       INTEGER NOT NULL DEFAULT 0,' +
    '  start_line       INTEGER,' +
    '  end_line         INTEGER' +
    ')',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_format ON symbol_docs(format)',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_deprecated ' +
    '  ON symbol_docs(deprecated) WHERE deprecated = 1',

    // v0.40.4: unit_uses captures every entry in every uses clause across the
    // codebase. One row per (file, section, unit_name). Powers circular-
    // dependency detection, interface->implementation move-down suggestions,
    // and unused-unit elimination utilities in graphing + lint tools.
    'CREATE TABLE IF NOT EXISTS unit_uses (' +
    '  id              INTEGER PRIMARY KEY,' +
    '  file_id         INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  unit_name       TEXT NOT NULL,' +
    // Lowercased trailing segment for join-friendly lookups against files.
    // For "System.SysUtils" this is "sysutils" so we can match
    // files.path -> basename -> stem -> lowercase.
    '  unit_name_norm  TEXT NOT NULL,' +
    '  section         TEXT NOT NULL,' +     // interface|implementation|program|package
    '  in_path         TEXT,' +               // text from `in ''...''`; NULL if absent
    '  target_file_id  INTEGER REFERENCES files(id) ON DELETE SET NULL,' +
    '  start_line      INTEGER NOT NULL,' +
    '  start_col       INTEGER NOT NULL,' +
    '  end_line        INTEGER,' +
    '  end_col         INTEGER' +
    ')',

    'CREATE INDEX IF NOT EXISTS idx_unit_uses_file '       +
    '  ON unit_uses(file_id)',
    'CREATE INDEX IF NOT EXISTS idx_unit_uses_unit_norm '  +
    '  ON unit_uses(unit_name_norm)',
    'CREATE INDEX IF NOT EXISTS idx_unit_uses_section '    +
    '  ON unit_uses(section)',
    'CREATE INDEX IF NOT EXISTS idx_unit_uses_target '     +
    '  ON unit_uses(target_file_id) WHERE target_file_id IS NOT NULL',

    // v0.40.5 Tier 2: live Firebird snapshot tables.
    // Each snapshot stamps `snapshot_at` so multiple snapshots can coexist
    // for drift detection (compare runs across days/weeks).
    'CREATE TABLE IF NOT EXISTS fb_relations (' +
    '  id                   INTEGER PRIMARY KEY,' +
    '  name                 TEXT NOT NULL,' +
    '  sql_table_symbol_id  INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  owner                TEXT,' +
    '  system_flag          INTEGER NOT NULL DEFAULT 0,' +
    '  description          TEXT,' +
    '  snapshot_at          INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_relations_name ON fb_relations(name)',

    'CREATE TABLE IF NOT EXISTS fb_columns (' +
    '  id                   INTEGER PRIMARY KEY,' +
    '  relation_id          INTEGER NOT NULL REFERENCES fb_relations(id) ON DELETE CASCADE,' +
    '  name                 TEXT NOT NULL,' +
    '  position             INTEGER NOT NULL,' +
    '  field_source         TEXT,' +
    '  field_type           INTEGER,' +
    '  field_length         INTEGER,' +
    '  field_scale          INTEGER,' +
    '  field_precision      INTEGER,' +
    '  nullable             INTEGER NOT NULL DEFAULT 1,' +
    '  default_value        TEXT,' +
    '  sql_column_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  description          TEXT,' +
    '  snapshot_at          INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_columns_relation ON fb_columns(relation_id)',
    'CREATE INDEX IF NOT EXISTS idx_fb_columns_name ON fb_columns(name)',

    'CREATE TABLE IF NOT EXISTS fb_field_info (' +
    '  id              INTEGER PRIMARY KEY,' +
    '  field_name      TEXT NOT NULL,' +
    '  table_name      TEXT,' +
    '  display_label   TEXT,' +
    '  display_format  TEXT,' +
    '  edit_format     TEXT,' +
    '  visible         INTEGER,' +
    '  read_only       INTEGER,' +
    '  triggered       INTEGER,' +
    '  display_width   INTEGER,' +
    '  fib_version     INTEGER,' +
    '  snapshot_at     INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_field_info_field ON fb_field_info(field_name)',
    'CREATE INDEX IF NOT EXISTS idx_fb_field_info_table ON fb_field_info(table_name)',

    'CREATE TABLE IF NOT EXISTS fb_datasets (' +
    '  id                          INTEGER PRIMARY KEY,' +
    '  ds_id                       INTEGER,' +
    '  description                 TEXT,' +
    '  select_sql                  TEXT,' +
    '  update_sql                  TEXT,' +
    '  insert_sql                  TEXT,' +
    '  delete_sql                  TEXT,' +
    '  refresh_sql                 TEXT,' +
    '  name_generator              TEXT,' +
    '  key_field                   TEXT,' +
    '  update_table_name           TEXT,' +
    '  update_only_modified_fields INTEGER,' +
    '  conditions                  TEXT,' +
    '  fib_version                 INTEGER,' +
    '  snapshot_at                 INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_datasets_ds_id ON fb_datasets(ds_id)',
    'CREATE INDEX IF NOT EXISTS idx_fb_datasets_table ON fb_datasets(update_table_name)',

    'CREATE TABLE IF NOT EXISTS fb_enum_values (' +
    '  id           INTEGER PRIMARY KEY,' +
    '  enum_name    TEXT NOT NULL,' +
    '  value_code   TEXT NOT NULL,' +
    '  value_label  TEXT,' +
    '  fib_version  INTEGER,' +
    '  snapshot_at  INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_fb_enum_name ON fb_enum_values(enum_name)',

    // v0.40.5 Tier 3: Delphi <-> SQL ORM bindings.
    // Cross-DB: delphi_db_index / sql_db_index track which --db each end
    // came from (matches the LSP store ordering). delphi_symbol_id and
    // sql_symbol_id are LOCAL to their respective DBs.
    'CREATE TABLE IF NOT EXISTS orm_links (' +
    '  id                INTEGER PRIMARY KEY,' +
    '  delphi_symbol_id  INTEGER NOT NULL,' +
    '  delphi_db_index   INTEGER NOT NULL DEFAULT 0,' +
    '  sql_symbol_id     INTEGER NOT NULL,' +
    '  sql_db_index      INTEGER NOT NULL DEFAULT 0,' +
    '  confidence        REAL NOT NULL DEFAULT 1.0,' +
    '  link_kind         TEXT NOT NULL,' +     // class_to_table | iface_to_table | field_to_column
    '  evidence          TEXT,' +
    '  computed_at       INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_orm_links_delphi ON orm_links(delphi_symbol_id, delphi_db_index)',
    'CREATE INDEX IF NOT EXISTS idx_orm_links_sql    ON orm_links(sql_symbol_id, sql_db_index)',
    'CREATE INDEX IF NOT EXISTS idx_orm_links_kind   ON orm_links(link_kind)'
  );

implementation

end.
