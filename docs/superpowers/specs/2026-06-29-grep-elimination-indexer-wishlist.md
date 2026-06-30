# Eliminating Grep in favour of the drag-lint indexer -- wish list

**Date:** 2026-06-29
**Context:** The global rule is "drag-lint FIRST, Grep second." In practice an agent still reaches for Grep. This doc audits *why*, states what is already achievable today, and lists concrete indexer features that would let us drop Grep almost entirely. Implement the features later; for now this is the backlog.

## Root causes -- why Grep still gets used (audited from a real session editing this repo)

1. **Stale / missing self-index of the code being edited.** The `DragLint` section (`Delphi-RAG-lint.sqlite`) is configured, but during an active editing session the DB lags the working tree (e.g. it was dated Jun 26 while the working tree had a brand-new `ParseCache` unit, a rewritten `AstChecks`, and CLI edits from Jun 28-29). Querying a stale index returns wrong/missing symbols, so Grep-on-the-working-tree is *more correct* for code you just changed. **This is the #1 driver.**
2. **Non-Delphi files aren't indexed.** The text/FTS index covers `.pas`/`.dfm`/`.sql`. Rule definitions (`rules/*.json`), tree-sitter queries (`*.scm`), build configs (`.dproj`/`.dpr` as text), and docs (`*.md`) are not searchable -- so "which rule JSON defines `large-magic-number`?" or "where is this `.scm` capture?" falls back to Grep/Glob.
3. **No regex / code-pattern text search.** `query --text` is exact-phrase / `--any-order` / `--substring` only. A search like `ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe'` (a repeated code idiom with punctuation/regex) cannot be expressed, so Grep is used.
4. **Locating a repeated code idiom / literal isn't a symbol query.** "Find every site that resolves the exe path" is neither `find-callers <fn>` nor a clean symbol lookup; it's a literal+structural pattern. Today that's Grep.
5. **File discovery (Glob).** Listing files by name/glob ("all `*.scm` under rules/") is Glob, not an indexer feature today.

## What is already achievable today (use these, don't Grep)

- **Symbol lookup / callers / uses** of indexed Delphi code: `drag-lint query --name X --db <db>`, `... find-callers`, `... resolve-uses`, `... --json`. Works well **when the index is fresh**.
- **String / message / caption search** in `.pas`/`.dfm`/`.sql`: `drag-lint query --text "<phrase>" [--any-order|--substring] [--source pas|dfm|sql]`.
- **Understanding a symbol** without reading whole files: `drag-lint context --task "modify <Qual>" --db <db> --format markdown`.
- **Keep the self-index fresh:** after a build/edit that changed symbols, **incrementally** reindex only the changed dir/DB: `drag-lint index <changedDir> --db Delphi-RAG-lint.sqlite` (or `index --all --only DragLint`). Then query. For this repo the DB is `C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite` (manifest section name `DragLint`).

**Agent workflow rule going forward:** before searching this repo's own Delphi code, ensure the `DragLint` index is fresh (incremental reindex of the files I just touched), then `query`/`query --text`. Use Grep only for (a) non-Delphi files, (b) regex/idiom patterns, (c) when an index genuinely can't be made fresh in time.

## Wish list (prioritised) -- features to add to the indexer

### P1 -- closes the biggest gaps
1. **Working-tree / "live" query mode.** A `--working-tree` (or auto-dirty-reparse) flag that re-parses files newer than the index on the fly (or auto-incrementally reindexes dirty files before answering), so queries reflect un-indexed edits. Removes the "stale index -> Grep" driver entirely for active sessions.
2. **Regex text search.** Add `query --text --regex <pattern>` (and/or `--glob`) over the FTS corpus, so code idioms with punctuation can be matched without Grep. (FTS5 trigram already underlies `--text`; expose a regex/LIKE path.)
3. **Index non-Delphi project files into the text index.** Optionally index `rules/*.json`, `*.scm`, `*.dproj`/`*.dpr` (as text), and `*.md` so rule/config/doc searches go through `query --text --source <ext>`. At minimum a `--source any` / `--include-ext json,scm,md` switch.

### P2 -- structural / discovery
4. **AST / s-expression pattern search.** "Find every expression matching `(binary_expression ... '+' (string_literal))`" or a named idiom -- a structural query beyond symbol-name lookup. Would replace Grep for "find all call sites resolving the exe path"-type tasks.
5. **`query files --glob <pat>`** -- list indexed files by name/glob, replacing Glob for file discovery within indexed roots.
6. **Literal-usage query.** "Where is the string literal/const value `'drag-lint.exe'` used?" as a first-class query (distinct from symbol/caption text search), returning located usages.

### P2 -- SQL DDL schema index (user-flagged 2026-06-30, "very soon")
9. **Structured SQL DDL index -- eliminate grepping `.sql`.** Today `.sql` is only in the FTS *text*
   index (phrase/substring), so "what columns does TOOLASSG have?", "which table has an OPERID FK?",
   "where is generator/exception X defined?" still fall back to Grep over `.sql`. Add a **structured
   DDL parse** of `CREATE TABLE/VIEW/PROCEDURE/TRIGGER/GENERATOR/EXCEPTION/INDEX` (+ `ALTER TABLE`)
   into queryable rows: table -> columns (name/type/nullable/default), PK/FK/unique constraints,
   view definitions, proc/trigger signatures, generators, exceptions. Then `drag-lint sql describe
   <table>`, `... sql columns <table>`, `... sql refs <table|column>`, `... sql find <name>` --
   schema queries without Grep. Firebird-4 dialect first (DECFLOAT, 63-char ids, `FETCH FIRST`);
   reuse the existing `DRagLint.Parser.Sql` + `MS*.sql` migration-file convention. Pairs with the
   `fb_*` Firebird MCP (which queries a *live* DB) -- this indexes the *DDL source files* so it works
   offline and tracks the schema-as-written in git.

### P3 -- ergonomics
7. **Freshness reporting.** `query` warns when the index mtime is older than the newest source file under its roots (so a stale answer is never silently trusted). Pairs with P1.
8. **One-shot "reindex-then-query".** A convenience flag (`query --reindex-first`) that incrementally refreshes the target DB's changed files before answering, for scripted/agent use.

## Acceptance / done-when
Grep usage in a typical session drops to only: binary/asset inspection and truly ad-hoc one-offs. Specifically, after P1+P2: (a) editing-then-searching this repo no longer needs Grep, (b) rule/config/doc searches use `query --text`, (c) code-idiom searches use `--regex` or the AST pattern query.
