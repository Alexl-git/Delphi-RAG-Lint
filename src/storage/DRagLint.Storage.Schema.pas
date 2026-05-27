unit DRagLint.Storage.Schema;

interface

const
  SCHEMA_VERSION = 2;

  // Each statement is terminated with a semicolon on its own conceptual block.
  // We rely on FireDAC ExecSQL with a single statement per call (split at ';').
  SCHEMA_DDL: array[0..9] of string = (
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
    '  ON symbol_trigrams(trigram)'
  );

implementation

end.
