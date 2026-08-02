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

---

## Addendum 2026-07-07 -- STRUCTURAL / SEMANTIC facts the index should hold (grounded in a real session)

**Context:** The original wish list above is *text/discovery*-oriented (stale index, non-Delphi
files, regex, globs, SQL DDL). This addendum covers the OTHER half the user flagged: the
*structural* facts an agent re-derives by hand-reading source because the index doesn't expose
them. These are the ones that most reduce **context/memory load** -- an index query returns a
digested fact; a Grep returns raw lines the agent must re-parse mentally. Eliminating them
"makes the agent aware of the codebase" without spending context to become aware.

**Why this matters beyond tokens (user's framing, verbatim intent):** grep-elimination isn't
only a token/time saving. Each raw grep hit pollutes the working context with source lines that
must be re-read and re-interpreted; a structured index answer is a *fact*, not evidence-to-parse.
Fewer raw lines in context = less to hold in memory = simpler, more reliable reasoning. The index
is pre-digested memory of the codebase; the more structure it holds, the less of the agent's
finite context is burned re-discovering that structure.

### How these were found (honest provenance)
Enumerated from the enum-helper-generator brainstorm session (2026-07-07), where the agent had to
hand-read source to learn things the index *could* have answered:
- how a `record helper` is classified -> it's `skRecord` with the target buried in the `Heritage`
  string; there is **no first-class "helper for T" edge**. (This is the trigger for this addendum.)
- the source span of an enum type decl (to place a generated sibling decl after it).
- the position of the `implementation` keyword (to place generated method bodies).
- what `HeritageTextOf` actually captures (had to read the parser).

### SEMANTIC wish list (prioritised) -- structural facts, not text

#### S1 -- relationship edges the index almost has but doesn't expose cleanly
1. **First-class HELPER edge.** `record helper for T` / `class helper for T` should store the
   *target type* as a resolved edge (like `type_ancestors`), not as heritage text a consumer must
   string-parse. Query: `helpers-of <T>` (does a helper exist? where?), `helper-target <THelper>`.
   Directly enables the enum-helper generator's "create-only-if-missing" guard and the
   `enum-helper-separate-units` lint rule **without heritage-string parsing**. *(Being delivered
   with the enum-helper milestone -- 2026-07-07.)*
2. **Section-anchor facts per unit.** Store the byte/line position of `interface`,
   `implementation`, `initialization`, `finalization` keywords per file (the section markers exist
   as `skInitialization`/`skFinalization` symbols but the plain `implementation` anchor isn't a
   queryable position). Any code-gen/refactor that inserts into a section (enum helper, extract
   method, add-uses) needs this; today it's a source scan. Query: `unit-anchors <file>`.
3. **`uses`-clause membership as a query.** "Does unit X already use unit Y?" / "list X's interface
   vs implementation uses." The uses graph exists for scope resolution (`TFileScopeEdge`) but isn't
   exposed as a direct "is Y in X's uses list, and in which section" query -- needed by every
   refactor that must add a unit to `uses`. Query: `uses-of <unit> [--section]`, `add-uses-target`.

#### S2 -- declaration-shape facts (avoid re-reading a decl to learn its shape)
4. **Enum member ORDINALS (explicit literals).** The index stores member name+order but NOT the
   literal `= -2` / `= 65`. Storing the explicit ordinal (when present) would let a consumer reason
   about signed/gap/out-of-range members without reading source. (The enum-helper feature dodged
   this via the "one Byte template" decision, but a future signed-byte variant or a range-lint would
   want it.)
5. **Const/var VALUES for simple literals.** `const Foo = 'drag-lint.exe';` -> store the literal
   value so "what is Foo" and "where is the value 'drag-lint.exe'" are index queries (ties to
   wish-list item 6, literal-usage). Today reading the const decl is a source read.
6. **Type-alias TARGET.** `TFoo = TBar;` / `TFoo = type Integer;` -> store the aliased target as an
   edge so alias chains are walkable without reading the decl. (`skTypeAlias` exists but the target
   isn't a resolved edge.)
7. **Set / array-of / record-of element types.** e.g. `TFooSet = set of TFoo`. Enables "what sets
   contain TFoo", relevant to enum work (`set of <enum>`).

#### S3 -- "make me aware" overview queries (reduce the need to read many files)
8. **Unit OUTLINE query.** `outline <unit>` = the ordered declaration skeleton (types, their
   members' signatures, routines) WITHOUT bodies -- one query that replaces opening the file to
   learn its shape. (`context` bundles do part of this for one symbol; an outline is whole-unit.)
9. **"What's in this file" / file-symbol roster** by kind. `symbols-in <file> [--kind]` -- list all
   enums, all classes, all forms in a file/dir, so "which units declare an enum with no helper" is a
   query, not a scan. Directly powers a "generate helpers for all bare enums in this unit" batch mode.
10. **Cross-reference DENSITY / fan-in-out already exist** (CBO/RFC/fan-in) -- surface them in a
    plain `stats <symbol>` so "is this heavily used" is a query, not a find-callers count.

### Non-goals for this addendum
- Not proposing the agent NEVER reads source -- reading a routine body to understand its logic is
  legitimate. The target is eliminating grep/read for STRUCTURAL FACTS the index can hold as data.
- Schema churn is real: each item is a column/table + a migration + a reindex. Batch them into
  deliberate schema bumps (as D5 did), not one-per-PR.

### Suggested sequencing
- **This milestone (enum-helper):** S1.1 (helper edge) -- required, being built.
- **Fold in cheaply if the schema is already bumping:** S1.2 (section anchors) -- the enum-helper
  placement needs the `implementation` anchor anyway; storing it as a queryable fact costs little
  more than computing it inline.
- **Next dedicated "indexer awareness" milestone:** brainstorm S1.3 + S2 + S3 as a set (one schema
  bump, one reindex). This is the "more index functions" brainstorm the user asked to schedule.

## Addendum 2026-07-27 -- audited from the Phase 3 controller session (measured, not recalled)

The controller ran nine Greps in one session. **Four were avoidable and one assumption was wrong**;
the rest hit two real coverage gaps. Each row was verified against the live self-index
(`C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`), not reasoned about.

### Avoidable -- the index already answers these today

| What I grepped | What I should have run | Verified |
| --- | --- | --- |
| `Prefix` in one `.pas` (to find where a local is assigned) | `query --name Prefix` | **Locals ARE indexed.** Returns `kind=local_var`, `DRagLint.Doc.Document.TDocumenter.BuildForSymbol.Prefix : string`. **I had assumed locals were out of scope -- they are not.** The qualified name names the declaring routine, which is exactly what the Grep was for. |
| `function NormalizeCommentLines` | `query --name NormalizeCommentLines` | Returns the full signature + `[impl-only]`. |
| a regex for the `...Stub` function declaration | `query --name Generate` | Returns `TDocStubGenerator.Generate` with its full signature. |
| `'/// '` and `'///'` string literals across `src/` | `query --text "TODO: describe" --source pas` | Returns `[pas/literal]` hits with `file:line:col` **and** the owning unit. This is the single highest-value under-used verb: **string-literal search is an index job.** |

**Correction to record:** the belief that "the index holds declarations, not locals" is FALSE and was
the reason for the first Grep. `local_var` is a first-class `kind`.

### Genuine gaps -- Grep was correct, and here is what would retire it

| Gap | Evidence from this session | Value |
| --- | --- | --- |
| **`.ps1` is not indexed** | `tests/` holds **180 `run_*.ps1` runners**. "Which runner asserts X?" came up repeatedly across nine tasks and is only answerable by Grep. `query --text "OK: staged"` returns **0 matches** because `--source` covers `pas\|dfm\|sql` only. | **Highest.** The test battery is a primary artifact of this repo; agents search it constantly. Assertion text is exactly the FTS5 use case already built. |
| **`.bat` / `.cmd` not indexed** | Finding an unguarded `copy` across `build/*.bat` (a real defect: the script printed `OK: staged` over a failed copy) required Grep. | Low volume, but trivially cheap once `.ps1` lands -- same file-scanner, same FTS5 table. |
| **`.md` not indexed** | This project keeps its working state in markdown: `docs/lint/BACKLOG.md` is the resume document, plus specs, plans and defect registers. Four of the nine Greps were markdown lookups. | Medium-high. Distinct from code search, but it is where "what did we decide and why" lives. |

**Proposed shape, deliberately minimal:** extend the existing FTS5 text index with a `source` value
per non-Delphi family (`ps1`, `bat`, `md`) rather than inventing a second mechanism, so
`query --text "<phrase>" --source ps1` works the way `--source pas` already does. No symbol
extraction, no AST -- text + `file:line:col` is enough to retire every Grep in the table above.

**Guardrail worth keeping in mind:** `.md` and `.ps1` under `tests/` include generated output
(`tests/autotest/results/*.json`, `logs/`) that should be excluded, or the text index inherits the
noise the `.gitignore` was just added to suppress.

## Addendum 2026-07-28 -- **E4: A CORRECTNESS HOLE, not a coverage gap. Read this before trusting a negative.**

Everything above this line is about *files the index does not cover*. This entry is different and more
serious: it is about **Delphi code the index does cover, answering incompletely and silently.**

**Nested routines (a `procedure`/`function` declared inside another routine's body) are not indexed at
all -- no symbol, no refs.** Confirmed by direct query of the self-index, not inferred:

| Query | Result |
| --- | --- |
| `select kind, count(*) from symbols group by kind` | `local_var` **13,993**, `param` 7,211, `method` 2,761, `function` 1,769, `procedure` 1,048 ... |
| symbols whose `qualified_name` implies routine-in-routine nesting | **0** |
| control: `local_var` inside a routine body | present, e.g. `DRagLint.Doc.Document.TDocumenter.BuildForSymbol.Path` |

So the indexer **does** walk routine bodies -- it emits ~14k locals from inside them -- but it does not
emit the nested routines themselves. That asymmetry suggests an omission in the symbol emitter rather
than a design decision, though this addendum does not attempt to prove that.

**Why it matters more than a missing file type:**

- `query --name <NestedRoutine>` returns **nothing**, which is indistinguishable from "no such symbol".
- `query find-callers --name X` **misses call sites located inside nested routines**, so "0 callers"
  can be simply wrong.
- Any index-based *enumeration* of call sites under-counts, silently.
- **The failure mode is a confident empty result, not an error.** Every other gap in this document
  announces itself (the file is not there, so nothing matches and you know why).

**How it was found, which is the part worth generalising:** during T3i, `query find-callers` **missed a
real fourth consumer** of a predicate the task was fixing. Grep found it. Had the enumeration been
trusted, the task would have shipped a fix to three of four sites believing it had covered all of them.

**Practical rule until this is closed:** the index is authoritative for a **positive** answer
(it found something, and it is AST-exact). For a **negative** answer -- "no callers", "no such symbol",
"that is the complete set" -- corroborate with a text search before relying on it, *especially* when the
answer is load-bearing for a decision. Note `query --text` is not a substitute: it covers string
literals and comments, not identifiers.

**Related, disclosed alongside it (register E5):** a paren-less dotted call in expression position
(`T := TThing.Create;`) emits no `call` ref, so it is invisible to call-graph queries too. Same class:
an incomplete answer that looks complete.
