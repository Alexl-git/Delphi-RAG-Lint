# dfm_properties + comment_facts -- two additive file-fact tables (wave 151, lane ST)

Status: accepted for 151 (lane ST writes the API; Y2 fills `dfm_properties`, W1 fills
`comment_facts`). Schema: written at 24 in the lane; INT sets SCHEMA_VERSION 25 once.
SCHEMA_READ_MIN stays 23.

## Problem

Two kinds of source fact are re-derived from file text by every consumer:

* DFM property values (FormsMap: DfmShownOnCreate, ReadCaption, ReadActionRef; hover /
  forms-csv). `dfm_nav_props` (150 Y2) keeps only the navigation subset (Caption, Action,
  Item*, events...), one value line, no position, no nesting.
* Comments: the DocInsight scanner (Parser.DocComments), the `dl:ok` review markers
  (Lint.ReviewMarker) and bookmarks (Lint.Bookmarks) each scan the text with their own
  lexer. They disagree at the edges (a `//` inside a string, `{$...}` directives,
  `(* *)` nesting) and every one costs a re-read of the file.

## Options

| | option | verdict |
|---|---|---|
| A | widen `dfm_nav_props` (more columns, every property) and add comment columns to an existing table | rejected: a 150-built v24 DB has the old shape, so a writer INSERT fails (the pp_directives precedent: a NEW table is the only additive change a probe can see) |
| B | two NEW tables, each probed on its own (`HasDfmProperties`, `HasCommentFacts`), written through the existing per-file `PutFileFacts` call | **chosen** |
| C | one generic `file_facts(kind, key, value, ...)` EAV table | rejected: untyped, no useful index, every reader re-parses the value column |
| D | keep the scanners, cache their results in memory | rejected: no cross-process reuse (LSP, CLI, IDE all re-scan) |

## Chosen design (B)

### dfm_properties -- one row per property assignment of a text .dfm

| column | type | meaning |
|---|---|---|
| file_id | INTEGER NOT NULL FK files ON DELETE CASCADE | the .dfm |
| ordinal | INTEGER NOT NULL | row order in the file (0..), assigned by the store |
| object_ordinal | INTEGER NOT NULL | the owning block = `dfm_objects.ordinal` of the same file_id; -1 when no block encloses it |
| parent | INTEGER NOT NULL | `ordinal` of the enclosing property row (a collection `item` or a nested list), -1 at object level |
| depth | INTEGER NOT NULL | 0 = direct property of the object; +1 per enclosing collection item / nested value |
| name | TEXT NOT NULL | the property name as written, dotted kept (`Font.Name`, `Items.Strings`) |
| value_text | TEXT NOT NULL | the value: a string DECODED (doubled quotes, `#nnn`, `+` continuations joined); anything else its source text, line breaks kept as `#10`; '' for list / collection / item / binary (content in the child rows: list elements name '', collection items name 'item') |
| value_kind | TEXT NOT NULL | `string`, `integer`, `float`, `ident`, `set`, `list`, `collection`, `item`, `binary`, `other` |
| start_line, start_col, end_line, end_col | INTEGER NOT NULL | 1-based; columns in UTF-8 bytes (as `dfm_objects` and `symbols`) |

Indexes: `(file_id, ordinal)`, `(file_id, object_ordinal)`, `(name COLLATE NOCASE)`.
Record: `TDfmPropertyRow` (Core.Model). Producer: `DRagLint.Parser.DFMProps.ExtractDfmPropertyRows
(AFilePath, AText, AObjects)` -- STUB returning `[]` in ST; lane Y2 implements it. Called by the
indexer for every `.dfm` (AText = '' for a binary .dfm; the producer may re-read the file).

Relation to `dfm_nav_props`: superset, not a replacement. `dfm_nav_*` stays (forms-csv /
menu-tree read it) until a later ruling retires it.

### comment_facts -- one row per comment of a Pascal source file

| column | type | meaning |
|---|---|---|
| file_id | INTEGER NOT NULL FK files ON DELETE CASCADE | the file |
| ordinal | INTEGER NOT NULL | source order (0..), assigned by the store |
| start_offset, end_offset | INTEGER NOT NULL | 0-based character offsets into the decoded text, end EXCLUSIVE |
| line, col, end_line | INTEGER NOT NULL | 1-based; col in UTF-8 bytes from the line start (the pp_directives rule) |
| kind | TEXT NOT NULL | the opener: `//`, `///`, `{`, `(*` |
| text | TEXT NOT NULL | the comment exactly as written, delimiters included |
| anchor_kind | TEXT NOT NULL | `end-of-line` (code before it on its line), `statement` (own line inside a routine body), `block` (own line, begins a comment run), `next-declaration` (directly above a declaration), `''` = not decided |
| anchor_symbol_id | INTEGER NULL FK symbols ON DELETE SET NULL | the declaration a `next-declaration` / `end-of-line` comment documents; NULL = none |

Directives `{$...}` and `(*$...*)` are NOT comments and never get a row (they are
`pp_directives` / `pp_regions` facts). A `//` inside a string literal is not a comment.
Indexes: `(file_id, ordinal)`, `(anchor_symbol_id)` (FK child, the v0.85 PERF rule).
Record: `TCommentFactRow` (Core.Model); `AnchorSymbolIdx` is an index into
`TParseResult.Symbols` (-1 = none) that the store maps to `symbols.id` through the same
IdxToId map `dfm_objects.symbol_id` uses. Producer: `DRagLint.Index.CommentFacts.ExtractCommentFacts
(AFilePath, AText, ASymbols)` -- STUB returning `[]` in ST; lane W1 implements it (Q2: table
+ anchors + parity with today's scanners; consumers are NOT rewired in 151). AText is the
text the DocInsight scanner sees in IndexFileBody (`SourceText`).

### Store API (Core.Interfaces.ISymbolStore)

* `PutFileFacts(..., const ADfmProperties: TArray<TDfmPropertyRow>; const AComments:
  TArray<TCommentFactRow>; ASymbolIds)` -- two new parameters; each table is deleted +
  re-inserted for the file inside its file tx only when its own probe is True.
* `HasDfmProperties` / `HasCommentFacts` -- one `TableExists` probe per table, cached.
* `GetDfmProperties(AFileId)` / `GetCommentFacts(AFileId)` -- rows in ordinal order; empty
  when the table is absent. `GetCommentFacts` returns `AnchorSymbolId` (Int64, 0 = NULL) and
  `AnchorSymbolIdx = -1`.

### Reader rule (read-compat)

Table present -> read it. Table absent (a schema 23 / 24 DB opened read-only by a 25 engine)
-> today's text path. "Present but no rows for this file" means the file was not (re)indexed
by a producing engine: readers treat it like absent for that file (the pp_directives rule).
Both tables are created by `Migrate` (not SCHEMA_DDL: SCHEMA_DDL_FTS5_FIRST does not move),
so any writer open of a 23 / 24 DB adds them; the re-parse that the extractor bump forces
fills them.

## Riding item: RS2 (6) hatch

`NoteScopeRemoval`'s 150-RS2 (6) receiver-side closure gets its own escape hatch,
`DRAGLINT_NO_SCOPED_RECEIVER_CLOSURE=1`, so the eviction guard's C2p polarity control can
observe the widening alone again (INT4 FOUND 1). Not `DRAGLINT_NO_SCOPED_RESOLVE`: that name
already exists and switches the WHOLE scoped pass off (WHOLE-DB), which C2o / C4 rely on.

## Reversible assumptions

1. Put goes through `PutFileFacts` (the plan's wording), not separate `PutDfmProperties` /
   `PutCommentFacts`; Has / Get are per table.
2. Column choices above (`parent`, `end_line`, kind spelled as the opener) are ST's; Y2 / W1 may
   ADD columns before INT's bump without a new probe, never rename or drop one.
3. Comment facts cover the files the producer accepts (W1 decides by extension); the indexer
   calls it for every non-binary file.
4. New hatch name (above) instead of reusing `DRAGLINT_NO_SCOPED_RESOLVE`.
