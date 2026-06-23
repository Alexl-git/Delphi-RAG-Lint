# Text-Constant Index — Design Spec

**Date:** 2026-06-23
**Status:** Approved design (pending spec review) → writing-plans
**Goal:** Index human/AI-readable string content (messages, captions, exceptions)
so `drag-lint query --text` replaces `grep` for text — returning *only* string
occurrences, never identifier/method hits.

## 1. Problem & Goal

Agents (and humans) frequently `grep` for an error message or caption to find
where it lives. `grep` is noisy: searching `Folder` also returns a variable
`folder`, a method `OpenFolder`, comments, etc. We want a text search that:

- Returns **every** string-literal occurrence of the query (all places).
- Returns **no** non-text hits (identifiers, methods, comments).
- Is sub-second on the large indexes (~1.5M symbols today), so it actually
  *eliminates* grep rather than being a slower alternative.

## 2. Requirements (from brainstorm)

| # | Requirement |
|---|-------------|
| R1 | Index **every non-empty** string literal in `.pas` (incl. `const` strings, `resourcestring`, and **format strings** — kept, they form messages). |
| R2 | Index **.dfm** string-valued property text (Caption, Hint, Text, etc.). |
| R3 | Index **.sql** message-bearing strings only: `CREATE EXCEPTION name 'msg'` and PSQL `EXCEPTION name 'msg'` overrides. (No `COMMENT ON`, no other SQL string literals.) |
| R4 | Default search = **exact phrase, in order**, case-insensitive, whole-word. |
| R5 | `--any-order` = all query words present, any order (whole-word). |
| R6 | `--substring` = grep-like, matches mid-word (`older` → `Folder`). |
| R7 | Show **all** matching locations (no collapsing); each result names its enclosing symbol. |
| R8 | Text-only: a variable/method named `Folder` must **never** be returned. |

**Non-goals:** regex search; matching a phrase that spans two concatenated
literals (`'Folder ' + 'not found'`); indexing comments; `COMMENT ON` text.

## 3. Engine

**SQLite FTS5** (confirmed compiled into FireDAC's static SQLite —
`-DSQLITE_ENABLE_FTS5=1` in `…/source/data/firedac/sqlite_compile.bat`).

- **unicode61** tokenizer → R4 (phrase via `"a b c"`) and R5 (implicit-AND `a b c`),
  case-insensitive, whole-word. Prefix (`folder*`) available for free.
- **trigram** tokenizer (FTS5 core since SQLite 3.34) → R6 substring. Verify the
  bundled SQLite is ≥ 3.34 in the FTS5 spike (almost certainly yes on Studio 37).

## 4. Data Model (SCHEMA_VERSION 9 → 10)

New base table (one row per indexed literal):

```sql
CREATE TABLE IF NOT EXISTS string_literals (
  id          INTEGER PRIMARY KEY,
  file_id     INTEGER NOT NULL REFERENCES files(id)   ON DELETE CASCADE,
  symbol_id   INTEGER          REFERENCES symbols(id)  ON DELETE SET NULL, -- enclosing routine/component
  source      TEXT NOT NULL,   -- 'pas' | 'dfm' | 'sql'
  kind        TEXT NOT NULL,   -- 'literal'|'const'|'resourcestring'|'format'|'dfm-prop'|'sql-exception'
  owner_name  TEXT,            -- const name, DFM property ('Caption'), or exception name
  text        TEXT NOT NULL,   -- DECODED logical text ('' escapes resolved); never empty
  start_line  INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line    INTEGER NOT NULL, end_col   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_string_literals_file   ON string_literals(file_id);
CREATE INDEX IF NOT EXISTS idx_string_literals_symbol ON string_literals(symbol_id);
CREATE INDEX IF NOT EXISTS idx_string_literals_source ON string_literals(source);
```

Two **external-content** FTS5 indexes over `string_literals.text`
(`content='string_literals', content_rowid='id'`), kept in sync by AFTER
INSERT/DELETE/UPDATE triggers — the SQLite-recommended pattern; stores no second
copy of the text and cannot drift on per-file reindex:

```sql
CREATE VIRTUAL TABLE string_fts     USING fts5(text, content='string_literals', content_rowid='id', tokenize='unicode61');
CREATE VIRTUAL TABLE string_fts_tri USING fts5(text, content='string_literals', content_rowid='id', tokenize='trigram');
-- + string_literals_ai / _ad / _au triggers feeding both FTS tables.
```

`Migrate()` adds the table, indexes, FTS vtabs, and triggers on existing DBs
(the existing migration path already ALTERs/creates for prior versions).

**Storage note / risk:** the trigram index is the largest addition (trigrams of
all literal text). If it proves too heavy on the whole-tree index, it can be made
an opt-in build (`index --with-substring`) — flagged for the implementation plan,
not decided now.

## 5. Extraction (per source, on the tree each parser already builds)

- **.pas** (`DRagLint.Parser.Delphi13`): harvest `literalString` nodes. Tag `kind`
  by context — inside a `resourcestring` section → `resourcestring`; RHS of a
  `const` string declaration → `const`; first arg of `Format`/`FmtStr`/`Format`-
  family or containing `%` specifiers → `format`; else `literal`. Resolve `''`
  escapes to logical text. `symbol_id` = nearest enclosing routine/type via the
  existing symbol ranges. Skip empty strings.
- **.dfm** (`DRagLint.Parser.DFM`): for each `property` whose value is a string
  (or string-list), emit `kind='dfm-prop'`, `owner_name=<property name>`,
  `symbol_id=<the component>`. Decode `#nn` char codes and `'a'+'b'` continuations
  into logical text where feasible.
- **.sql** (`DRagLint.Parser.Sql`): emit `kind='sql-exception'` for the message
  string of `CREATE EXCEPTION name 'msg'` and PSQL `EXCEPTION name 'msg'`.
  `owner_name=<exception name>`. (Verify the SQL grammar exposes these nodes
  during the spike; if not, a targeted textual pass for those two forms.)

## 6. Search CLI

```
drag-lint query --text "<query>" [--any-order] [--substring]
                [--source pas|dfm|sql] [--db <p> ...] [--json] [--limit N]
```

- Default → `string_fts MATCH '"<query>"'` (phrase). `--any-order` → `string_fts
  MATCH '<query>'` (implicit AND). `--substring` → `string_fts_tri MATCH
  '<query>'`. All case-insensitive.
- `--source` filters by `source`; multi-`--db` follows the existing manifest
  multi-index behavior; `--limit` defaults to 200 (logged when truncated).
- **Output** (mirrors grep + the existing `query` formatter):
  `path:line:col  [source/kind]  «<text, FTS5 snippet() around the match>»  -> <enclosing qualified symbol>`
  `--json` emits `{file_path,start_line,start_col,source,kind,owner_name,text,enclosing}`.
- Result ordering: by file then line (stable, grep-like); FTS5 `rank` available
  but secondary to "show all places."

## 7. Reindex / Migration behavior

- New tables populate during `index` (literals come from parsing, so — unlike the
  lazily-built `symbol_trigrams` — they **cannot** be back-filled without a
  reparse). After upgrading, existing DBs need a `drag-lint index --all` (or
  incremental over changed files) to populate. The version bump prints a one-line
  note when `--text` is used against a DB with an empty `string_literals`.
- Per-file reindex (`DELETE FROM string_literals WHERE file_id=?` → reinsert) keeps
  FTS correct via the triggers; the new `idx_string_literals_file` makes the delete
  a seek (same lesson as `idx_refs_file`).

## 8. Testing (TDD)

Fixtures under `tests/textindex/` with known content, plus harness assertions:

- `messages.pas`: a `resourcestring SFolderNotFound = 'Folder not found';`, a
  `const CCap = 'Save As';`, a `Format('%d folders in %s', …)`, and a **variable
  named `Folder`** + a method `OpenFolder`.
- `captions.dfm`: `Caption = 'Folder not found'`, `Hint = 'Pick a folder'`.
- `exceptions.sql`: `CREATE EXCEPTION e_no_folder 'Folder not found';`.

Assertions (RED first): `query --text "folder not found"` returns the .pas/.dfm/.sql
locations and **not** the `Folder` variable/`OpenFolder` method (R8); `--any-order
"folder found"` matches; `--substring "older"` matches `Folder`; `--source dfm`
filters; empty strings absent; format string indexed. Plus an FTS5 spike test
(create+query a trigram FTS table) gating the build.

## 9. Open items for the plan

- FTS5/trigram spike (SQLite ≥ 3.34) as task 0.
- Confirm SQL grammar exposes `EXCEPTION`/`CREATE EXCEPTION` message nodes.
- Decide trigram index always-on vs `--with-substring` opt-in if storage is heavy.
