# v0.16 — Doc-Comment Extraction (Slice A)

**Date:** 2026-05-28
**Status:** Design approved, ready for plan
**Slice:** A of A/B1/B2 path to "CodeInsight alternative inside Delphi IDE"

## 1. Overview & Goals

When `drag-lint index` finishes, every symbol that has a doc comment in source has a
structured record in a new `symbol_docs` table. Consumers (CLI, MCP, LSP, future
OTAPI plugin) get rich `summary` / `params` / `returns` / `remarks` without
re-parsing source on every read.

### Non-goals

- Generating docs from code (TableTools already does this).
- Validating doc quality / lint rules over docs (defer to v0.17 lint pack).
- Translating between formats (no XMLDoc <-> PasDoc conversion).
- Markdown rendering (consumers render however they like; we store plain text +
  structured tags).

### Success criteria

1. On the drag-lint self-corpus, every public method/class with a `///` block gets
   a populated `symbol_docs.summary`.
2. On a PasDoc-heavy corpus (DUnitX or any `@param`-using library),
   `@param` / `@returns` map cleanly into `params_json` / `returns_text`.
3. CLI: `drag-lint hover --qname Foo.Bar` returns formatted doc output.
4. MCP: `get_symbol_doc` tool returns the structured record as JSON.
5. LSP: `textDocument/hover` payload includes parsed summary + remarks instead of
   raw block.
6. Re-indexing a file with edited docs updates `symbol_docs` (full re-emit per
   file, same semantics as `symbols`).
7. Index time on DevExpress within 10% of v0.15.
8. Zero outbound calls. Pure local parse.

### Carried TODOs

- Investigate Zed editor LSP-host compatibility. If our LSP is spec-compliant, Zed
  should host it; verify after v0.17.
- OTAPI wizard lives in its own v0.21 spec.

## 2. Schema Additions

Schema version bumps `3 -> 4`. Migration auto-runs in
`DRagLint.Storage.Schema.pas`.

```sql
CREATE TABLE symbol_docs (
  symbol_id        INTEGER PRIMARY KEY REFERENCES symbols(id) ON DELETE CASCADE,
  format           TEXT NOT NULL,        -- 'xmldoc' | 'pasdoc' | 'oneline' | 'loose'
  raw_block        TEXT NOT NULL,        -- original comment text, unmodified
  summary          TEXT,                 -- <summary> or first paragraph
  remarks          TEXT,                 -- <remarks> or @remarks
  returns_text     TEXT,                 -- <returns> or @returns
  params_json      TEXT,                 -- [{"name":"X","desc":"..."}, ...]
  exceptions_json  TEXT,                 -- [{"type":"EFoo","desc":"..."}, ...]
  example_text     TEXT,                 -- <example> or @example
  seealso_json     TEXT,                 -- ["Foo.Bar", "Baz"]
  since_text       TEXT,                 -- @since / <since>
  deprecated       INTEGER DEFAULT 0,    -- 0/1 flag
  start_line       INTEGER,              -- comment block start line
  end_line         INTEGER
);

CREATE INDEX idx_symbol_docs_format ON symbol_docs(format);
CREATE INDEX idx_symbol_docs_deprecated
  ON symbol_docs(deprecated) WHERE deprecated = 1;
```

### Column rationale

- `summary` is the hot-path read (completion quick-info, MCP previews).
- `params_json` powers signatureHelp (parameter-by-parameter docs in v0.20).
- `deprecated` is a sparse index for cheap `find --doc-tag deprecated`.
- `format` lets future passes target one style (e.g. lint unknown PasDoc tags).
- `start_line` / `end_line` let the IDE plugin jump to the doc block source.

### Re-emit semantics

Full delete-and-reinsert per file on reindex. No orphan rows possible due to
`ON DELETE CASCADE`. Same per-file transaction as `symbols`.

### Storage cost estimates

| Corpus | Documented symbols | Storage |
|---|---|---|
| Self (16 files) | ~50 | < 100 KB |
| Spring4D | ~5000 | ~5 MB |
| Micronite (44k symbols, ~10% documented) | ~4400 | 2-5 MB |
| DevExpress (473k symbols, ~5% documented) | ~24000 | 10-20 MB |

All trivial relative to existing index sizes.

### Migration

Existing v3 DBs continue to query. `symbol_docs` populates lazily on first
reindex after upgrade. Queries against undocumented symbols return NULL summary.

## 3. Parser Pipeline

New module: `src/parser/DRagLint.Parser.DocComments.pas`.

### Step 1 — Comment collection

Single regex pass over file source text collects all comment regions into a
sorted list:

```pascal
type
  TDocCommentKind = (
    dckTripleSlash,       // ///
    dckDoubleSlashOne,    // //1
    dckTripleSlashOne,    // ///1
    dckPasDocCurly,       // {** ... *}
    dckPasDocParen,       // (** ... *)
    dckLooseLine,         // // (preceding, no doc marker)
    dckLooseBlock         // { ... } (preceding, no doc marker)
  );

  TDocCommentRegion = record
    StartLine: Integer;
    EndLine:   Integer;
    Kind:      TDocCommentKind;
    RawText:   string;
  end;
```

Adjacent same-kind comments merge into one region (a 10-line `///` block is one
region, not 10).

### Step 2 — Association

When `DRagLint.Parser.Delphi13` emits a symbol with declaration line `L`, look up
the region whose `EndLine in [L-1-AllowBlankLineGap, L-1]`. `AllowBlankLineGap`
is configurable (default 1).

**Trailing same-line docs** (`FName: string; // user name`) captured when
`region.StartLine = L` and the comment starts after the symbol's last token
column on that line. Applies to single-line decls only (fields, properties,
const, var, type alias). Multi-line decls (methods, classes) never pick up
trailing-line docs.

Comment-region detection respects string literals: `'foo // bar'` is not a
comment. Reuses the same literal-aware tokenization the v0.9
`inline-comment-in-multiline-args` lint already does.

### Step 3 — Format detection

| Source pattern | Detected format |
|---|---|
| `///` lines with `<...>` tags | `xmldoc` |
| `///` lines without tags | `oneline` |
| `//1` or `///1` lines | `oneline` |
| `{** ... *}` block | `pasdoc` |
| `(** ... *)` block | `pasdoc` |
| Loose `//` or `{ }` preceding decl | `loose` (off by default) |

### Step 4 — Tag extraction

Dispatch to format-specific parser (Section 4). Returns a populated `TParsedDoc`
record matching the `symbol_docs` columns.

### Step 5 — Persist

Single `INSERT` into `symbol_docs` keyed by `symbol_id` returned from the
existing symbol upsert in `DRagLint.Storage.SQLite.UpsertSymbol`.

### Interface vs implementation precedence

When a method has docs both at its interface-section declaration and its
implementation, the **interface wins**. The declaration line is the canonical
symbol. Impl-only docs are captured when no interface doc exists.

### Performance budget

One regex pass per file, binary-search lookup against sorted regions ->
effectively `O(n log n)`. Expected overhead:

- Self-corpus (16 files): < 50 ms
- Micronite (795 files): < 500 ms
- DevExpress (4460 files): < 2 s

Total index time stays within the 10% budget.

## 4. Doc-Extraction Rules Per Format

All parsers live in `DRagLint.Parser.DocComments` as private functions of
`TDocCommentParser`. Each takes `(rawBlock, kind)` and returns `TParsedDoc`.

### 4.1 XMLDoc (`///`)

Regex extraction, no XML DOM (per v0.2 lesson — MSXML/OmniXML wiring was
finicky).

| Tag | Column |
|---|---|
| `<summary>...</summary>` | `summary` |
| `<param name="X">...</param>` | append to `params_json` |
| `<returns>...</returns>` | `returns_text` |
| `<remarks>...</remarks>` | `remarks` |
| `<exception cref="EFoo">...</exception>` | append to `exceptions_json` |
| `<example>...</example>` | `example_text` |
| `<seealso cref="X"/>` / `<see cref="X"/>` | append to `seealso_json` |
| `<since>...</since>` | `since_text` |
| `<deprecated/>` | `deprecated = 1` |
| Untagged text before first tag | `summary` fallback |

Each `///` prefix stripped from each line. Internal whitespace collapsed.
Paragraph breaks preserved with `\n\n`.

### 4.2 PasDoc (`{** *}` / `(** *)`)

| Tag | Column |
|---|---|
| First paragraph (until first `@tag` or blank line) | `summary` |
| `@param X desc` | append to `params_json` |
| `@returns desc` / `@return desc` | `returns_text` |
| `@throws TFoo desc` / `@raises TFoo desc` | append to `exceptions_json` |
| `@remarks desc` | `remarks` |
| `@example ...` | `example_text` (greedy until block end or next `@`) |
| `@see X, Y, Z` | `seealso_json` |
| `@since X` | `since_text` |
| `@deprecated` | `deprecated = 1` |
| `@author`, `@version` | captured into `remarks` (low priority, no dedicated column) |

### 4.3 Oneline (`///`, `//1`, `///1` with no XML tags)

- Strip leading marker + whitespace from each line.
- Join with single space -> `summary`.
- All other columns NULL.

### 4.4 Loose (`//` / `{ }` preceding, no doc markers)

Off by default. Enabled via `.drag-lint.json` `"docs.captureLooseComments":
true`. Treated identically to oneline but tagged `format = 'loose'` so
consumers can filter low-confidence docs out.

Heuristic noise filter: ignore blocks where > 50% of lines start with
`TODO|FIXME|HACK|XXX|REVIEW|=====|-----|#####|Copyright|(c)`. Those land in
the existing `todos` table or are dropped.

### 4.5 Multi-paragraph handling

Blank lines inside `<summary>` or PasDoc first-paragraph terminate that field
but get rejoined with `\n\n` if the field genuinely spans paragraphs. Stored as
plain text with `\n\n` between paragraphs; consumers render however they like.

### 4.6 Cross-format edge case

A symbol with both a `{** *}` block 3 lines above AND a `///` block immediately
above -> `///` wins. Format precedence is purely line-distance, never
format-quality.

## 5. Consumer Surfaces

### 5.1 CLI additions

In `DRagLint.CLI.pas`:

```
drag-lint hover --qname Foo.TBar.Baz [--format md|plain|json]
  -> resolves symbol, renders parsed doc:

  Foo.TBar.Baz(value: Integer): string
  Summary: Computes the baz for the given value.
  Params:
    value -- input integer, must be > 0
  Returns: the baz as a string
  Raises: EArgumentException on value <= 0

drag-lint find --doc-tag deprecated
  -> list all deprecated symbols

drag-lint find --doc-contains "thread safety"
  -> grep parsed docs (summary | remarks | example)

drag-lint find --no-docs --kind method --public
  -> coverage gap report (undocumented public methods)
```

### 5.2 MCP additions

In `DRagLint.MCP.Server.pas`, alongside existing `find_callers` / `find_symbol`
/ `lint`:

- `get_symbol_doc` — input `{qname}`, returns structured row as JSON
- `find_by_doc_tag` — input `{tag: "deprecated"|"since"|...}`, returns symbol list
- `find_undocumented` — input `{kind?, public_only?}`, returns coverage gaps

### 5.3 LSP additions

In `DRagLint.LSP.Server.pas`:

- `textDocument/hover` payload upgraded — when a `symbol_docs` row exists,
  render Markdown with summary, params table, returns, exceptions, since /
  deprecated badges. Falls back to current behavior when no doc row.
- No completion / signatureHelp yet — those are v0.20 (Slice B1).

### 5.4 `.drag-lint.json` additions

```json
{
  "docs": {
    "captureLooseComments": false,
    "implPrecedence": "interface",
    "allowBlankLineGap": 1
  }
}
```

## 6. Out-of-Scope Roadmap (named, not designed)

| Version | Headline | One-line scope |
|---|---|---|
| **v0.17** | Blast-radius pack | `drag-lint impact` (transitive callers) + `surface` (class interface only) + `slice` (symbol-relevant unit chunks) + `find-callers --context N` |
| **v0.18** | Context bundles + benchmark | `drag-lint context --task "..."` returns minimum AI-ready slice. Benchmark suite measures token reduction vs raw file reads on Micronite. Headline selling point. |
| **v0.19** | Type-at-position | `drag-lint typeat <file>:<line>:<col>` returns inferred type chain. Heavier — needs type resolution pass. |
| **v0.20** | LSP completion (Slice B1) | `textDocument/completion`, `signatureHelp`, diagnostics push from lint, doc-aware quick info. Uses everything from v0.16–v0.19. |
| **v0.21** | OTAPI wizard (Slice B2) | RAD Studio IDE plugin that calls the local LSP over stdio, renders inside the editor surface. Replaces / augments Help Insight + Code Completion. |
| **v0.22+** | Confidence-tagged refs + clusters + hotspots (Slice C) | The Graphify-inspired track. Independent; can land any time after v0.16. |

## 7. Stop Criteria for v0.16

1. Self-corpus indexed, every `///`-documented symbol has populated
   `symbol_docs.summary`.
2. Spring4D test (PasDoc-heavy) — `@param` / `@returns` correctly mapped.
3. `drag-lint hover --qname X` prints sensible output.
4. MCP `get_symbol_doc` returns valid JSON for documented symbols.
5. LSP hover shows summary / params / returns inline.
6. `drag-lint find --no-docs --public` produces a coverage report on Micronite.
7. Re-indexing a file with edited docs updates rows (no orphans, no stale).
8. Index time on DevExpress within 10% of v0.15.

## 8. Positioning Notes (Embarcadero AI / Graphify)

drag-lint is a **retrieval and structural-analysis layer**. It indexes what
exists. It does not generate code. Embarcadero Smart CodeInsight (announced
2026-05-28) is LLM-backed code generation — different category, complementary.

Selling-point claim, benchable in v0.18:

> drag-lint cuts AI assistant per-task token usage on Delphi codebases by an
> order of magnitude, with zero data leaving the machine.

vs Graphify (`safishamsi/graphify`): drag-lint has a real Delphi 13 grammar,
ships as a single Win64 binary (no Python runtime), has lint built in, is
.dproj-aware, and never sends anything outbound. Graphify is broader (33
languages, multi-modal). Different shapes of tool.
