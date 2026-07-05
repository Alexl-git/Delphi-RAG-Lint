---
title: "AutoDocument Chunk 1: generate + repair DocInsight from the index (managed regions)"
date: 2026-07-05
status: approved
author: Claude
---

# AutoDocument Chunk 1

## Summary

Track 2 of the drag-lint action roadmap: **generate and repair DocInsight
doc-comments from what the index already knows.** This is the most *differentiated*
capability drag-lint has -- nobody else can auto-write DocInsight from a symbol
index. Chunk 1 is the full vertical slice PROVEN on a single public declaration
(mirroring AutoFix Chunk 1): detect existing/missing/stale docs -> generate or
repair a DocInsight comment -> insert via `TTextEditApplier` -> a `document` CLI
verb (`--json` for AI orchestration) -> an IDE "Document it" menu item. Chunk 2
later widens to whole-unit / whole-project.

The core design is **managed regions**: drag-lint owns specific, sentinel-fenced
parts of the comment and regenerates them idempotently; everything outside those
regions is hand-written and never touched. It never fabricates prose -- a missing
`<summary>` gets a `TODO: describe.` marker, and every emitted section is a
ground-truth fact from the index or the signature.

Ships as release **v0.90.0-alpha**. No index-schema change expected (v13).

## Background: what already exists

Surveyed 2026-07-05 (do NOT rebuild these):

- **`TDocStubGenerator.Generate(store, qname, format): string`**
  (`src/refactor/DRagLint.Refactor.DocStub.pas`) -- emits a string stub:
  `<summary>TODO`, one `<param name="X">TODO` per parameter (names parsed from the
  signature), `<returns>TODO` when the symbol returns a value. Single symbol, by
  qname, resolved via `FindSymbolsByQualifiedName[0]`. **No insert path (string
  only), no `<remarks>`/`<exception>`.** Its signature-parsing helpers are the
  reusable backbone: `ExtractParamList(sig)`, `ParseParamNames(list)` (handles
  `const/var/out/in/array of` + grouped `A, B: T`), `SignatureHasReturn(sig)`,
  `ReadSourceLine(path, line)` (fallback when the DB signature is empty).
- **`TDocCommentScanner.Scan` + `TDocCommentParser` -> `TParsedDoc`**
  (`src/parser/DRagLint.Parser.DocComments.pas`, `TParsedDoc` in Model.pas:220) --
  parses an existing comment into `Summary, Remarks, ReturnsText,
  Params: TArray<TDocParam>{Name,Desc}, Exceptions, ..., StartLine, EndLine,
  HasContent`. `StartLine`/`EndLine` give the existing comment's span (what to
  replace/extend). **No stale-param detection** -- built here by diffing
  `TParsedDoc.Params[].Name` vs the signature's param names.
- **`ISymbolStore`** (`src/core/DRagLint.Core.Interfaces.pas`):
  `FindSymbolsByQualifiedName`, `FindCallersByName(callee): TArray<TReference>`
  (Called-from), `FindCallersByNameWithContext`, `FindReferencesTo(symbolId)`,
  `GetUnitUsesForFile`, `GetSymbolDoc(symbolId): TParsedDoc` /
  `UpsertSymbolDoc`, `GetFilePath(fileId)`.
- **`TTextEdit` + `TTextEditApplier.Apply(edits, backup)` / `RenderDryRun`**
  (`src/refactor/DRagLint.Refactor.TextEdit.pas`) -- the same edit engine AutoFix
  uses. `tekInsertLines` (insert a new comment above a decl), `tekDeleteLines` +
  `tekInsertLines` (replace an existing comment span). ANSI/CRLF/.bak preserved.
- **`generate-docs --qname X [--format xmldoc|pasdoc]`** (`DoGenerateDocs`,
  CLI.pas:6116) -- print-only. **Stays as the legacy stub; the new insert-capable
  verb is `document`.** `DoFindUnit` (CLI.pas:6149) is the template for the new
  verb (store open -> build edits -> `--json`/`--apply`/`--no-backup` +
  `RenderDryRun`).
- **No missing-doc lint rule exists.** (Out of scope for this chunk; a
  `missing-doc` report-only rule is a candidate for a later chunk.)

## Scope

### In scope (Chunk 1)

1. Generate a DocInsight comment for a single public declaration lacking one.
2. Repair/extend an existing comment: preserve hand-written prose, (re)generate the
   managed regions, add missing `<param>` tags, remove tags for deleted params.
3. The **managed facts block** inside `<remarks>`: **Called from**, **Calls**,
   **Used in units**, **Raises** (exceptions), and **Returns** (for functions) --
   all index/AST-grounded; a list longer than 15 shows its top 10 + `(+N more)`
   (see the Cap rule in Design 2 for the exact threshold).
4. `document --qname X [--apply] [--json] [--no-backup] [--db PATH]` CLI verb.
5. IDE "Document it" context-menu item on a symbol node (live-smoke).
6. Publish v0.90.0-alpha.

### Explicitly NOT in scope

- **Semantic-drift detection** -- when a unit's BEHAVIOUR changes and the
  hand-written `<summary>` prose needs updating. The user deferred this; it needs
  understanding intent, not structure. Left for later.
- Whole-unit / whole-project batch (Chunk 2, roadmap 2.2/2.3).
- The RAD Studio DocInsight/XML-doc-collection investigation spike (roadmap 2.3).
- A `missing-doc` lint rule.
- Fabricating `<summary>` or `<param>` descriptions (never -- a wrong summary is
  worse than none; always `TODO: describe.`).

## Design

### 1. Managed-region model

drag-lint owns two kinds of sentinel-fenced region; everything else is preserved
verbatim.

**(a) The facts block** -- a fenced region inside `<remarks>`:

```pascal
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: Unit1.DoThing (U1.pas:42), Unit2.Run (U2.pas:88) (+7 more)
/// Calls: Helper.Parse, TFoo.Create
/// Used in units: U1, U2, U3
/// Raises: EParseError, EIOError
/// <!-- drag-lint:auto END -->
/// </remarks>
```

**(b) Per-param sentinels** -- each auto-ADDED `<param>` carries its own marker so
regen can add tags for new params and remove tags for deleted ones without touching
hand-filled descriptions:

```pascal
/// <param name="pDelta">TODO: describe.</param><!-- drag-lint:auto param -->
```

**Sentinel constants** (single source of truth, e.g. in `DRagLint.Doc.Regions`):
`AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->'`,
`AUTO_END = '<!-- drag-lint:auto END -->'`,
`AUTO_PARAM = '<!-- drag-lint:auto param -->'`. All ASCII, live on `///` lines.

**Regeneration is idempotent:** locate each managed region by its sentinel, replace
its body wholesale, re-emit. Because the whole managed block is replaced, stale
facts (removed callers, deleted params) simply disappear -- no diffing. A hand-typed
`<param>` (no `AUTO_PARAM` marker) is NEVER removed, only flagged if stale (see 4).

### 2. Grounded facts (`DRagLint.Doc.Facts`)

New unit. Given a resolved `TSymbol` + `ISymbolStore`, returns a pure-data record:

```pascal
type
  TDocFactRef = record Display: string; Location: string; end; // "Unit.Method", "file:line"
  TDocFacts = record
    CalledFrom : TArray<TDocFactRef>;  // FindCallersByName(short name)
    Calls      : TArray<string>      ; // outgoing calls within the body
    UsedInUnits: TArray<string>      ; // for a TYPE: distinct units referencing it
    Raises     : TArray<string>      ; // 'raise EFoo' class names in the body
    ReturnType : string              ; // '' when not a function
    CalledFromTotal, CallsTotal, UsedInTotal: Integer; // pre-cap totals for '(+N more)'
  end;
  TDocFactsBuilder = class
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
  end;
```

- **Called from**: `FindCallersByName(LastSeg(qname))`; map each `TReference` to
  `TDocFactRef` (enclosing symbol name via `enclosing_symbol_id` when available,
  else the file; `GetFilePath` + line for Location). Dedupe.
- **Calls**: references whose `enclosing_symbol_id` = this symbol (the v0.82
  attribution) -> the callee names. If that query is not directly exposed, derive
  from `GetSymbolSlice`/body scan. **IMPLEMENTATION NOTE:** confirm the exact store
  method for "outgoing calls of a symbol" first; if none is clean, scan the symbol's
  body text for `Ident(` call sites (bounded, best-effort) and label the section
  accordingly. This is the one fact whose query needs verification during T-build.
- **Used in units**: only for type-like kinds (`skClass`, `skInterface`, `skRecord`,
  `skType`); `FindCallersByName(typeName)` -> distinct owning units via `GetFilePath`.
- **Raises**: scan the symbol's body (slice) for `raise <Ident>` at statement level;
  collect distinct class names. Reuse the lexer-aware scan idiom from the `raise-*`
  rules to skip strings/comments.
- **ReturnType**: from `Sym.Signature` (parse the `: T` after the param list) or
  empty; drives whether `<returns>` is emitted.

**Cap rule (user):** each list is capped at **10** displayed entries; when the true
total is **> 15**, append `(+N more)` where `N = total - 10`. (Between 11 and 15 the
list shows all -- the cap only bites past 15, avoiding a "+1 more" for a trivial
overflow.) Totals are carried in the `*Total` fields.

### 3. Region engine (`DRagLint.Doc.Regions`)

New unit. Owns the sentinel format and the text manipulation. Pure functions over
strings -> `TTextEdit`; never queries the index.

```pascal
type
  TDocRegions = class
    /// Render the fenced facts block body (the lines between AUTO_BEGIN/END,
    /// each prefixed '/// '), from TDocFacts. Empty sections are omitted; if no
    /// facts at all, returns '' (no block emitted).
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
    /// Given the existing comment text (or '' for none) and the target column
    /// prefix, produce the merged comment lines: preserved prose + regenerated
    /// managed facts block (inside <remarks>) + managed <param> tags.
    class function MergeComment(const AExisting: TParsedDoc; const ASigParams: TArray<string>;
      const AFacts: TDocFacts; AHasReturn: Boolean; const APrefix: string): string;
  end;
```

`MergeComment` rules:
- If `AExisting.HasContent` is False (no comment): emit a fresh comment --
  `<summary>TODO`, one `<param name=X>TODO</param><!--auto param-->` per signature
  param, `<returns>TODO` if `AHasReturn`, and `<remarks>` with the facts block.
- If a comment exists: keep `Summary`, `Remarks` prose OUTSIDE the fenced block,
  and every hand-typed `<param>` (with its Desc). Then: (i) replace the fenced
  facts block (or insert one into `<remarks>`, creating `<remarks>` if absent);
  (ii) for each signature param with no existing `<param>`, add one with an
  `AUTO_PARAM` marker; (iii) for each `AUTO_PARAM`-marked `<param>` whose name is
  no longer a signature param, drop it; (iv) for a HAND-typed `<param>` whose name
  is no longer a signature param (stale), append ` <!-- drag-lint: param no longer
  exists -->` to that line (flag, never delete hand prose).
- Preserve the declaration's indentation (`APrefix` = the `///` prefix + leading
  whitespace matching the decl).

### 4. Orchestrator (`DRagLint.Doc.Document`)

New unit -- what the CLI verb and IDE menu both call.

```pascal
type
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound);
  TDocumentResult = record
    Action: TDocumentAction; QName, FilePath: string; Line: Integer;
    Edits: TArray<TTextEdit>;
  end;
  TDocumenter = class
    class function BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
  end;
```

`BuildFor`: resolve `AQName` (`FindSymbolsByQualifiedName[0]`; `daNotFound` if none).
Read the existing comment above the decl (scan the source region above
`Sym.StartLine`, parse to `TParsedDoc`). Parse signature params
(`ExtractParamList`+`ParseParamNames`) and return (`SignatureHasReturn`). Build
facts (`TDocFactsBuilder`). Merge (`TDocRegions.MergeComment`). Diff the merged
comment against the existing text: identical -> `daUnchanged` (no edits); no prior
comment -> `daCreated` (a `tekInsertLines` above `Sym.StartLine`); changed ->
`daExtended` (delete the old comment span `[TParsedDoc.StartLine, EndLine]` +
insert the merged one). Return the edit set.

### 5. CLI verb (`document`)

`document --qname <Foo.TBar.Baz> [--apply] [--json] [--no-backup] [--db PATH]`.
Template: `DoFindUnit`. Dry-run by default: print `RenderDryRun(edits)` + the
merged comment preview. `--apply`: `TTextEditApplier.Apply(edits, not NoBackup)`.
`--json`: emit one object `{qname, file, line, action, edits}` (action in
`created|extended|unchanged|not_found`). Exit 0 ok/unchanged, 1 not-found/no-edit,
2 usage. `generate-docs` is unchanged (legacy print-only).

### 6. IDE "Document it"

Structure-tab context menu: right-click a symbol node -> **Document it**. Resolve
the node's qname, spawn `document --file <unit> --qname <q> --apply` (staged Win64
exe via the shared `DragLintExe` resolver), reload the buffer with the deferred
`ForceQueue` + `IOTAModule.Refresh` pattern (same as "Fix it"). Not unit-testable
-> ends in a LIVE SMOKE. Cut last if oversized; the CLI verb is the shippable core.

## Testing

Fixtures under `tests/autodoc/fixtures/` (ASCII, CRLF, unit name = filename) +
PowerShell harnesses mirroring `tests/autofix/` (copy to C:\TEMP scratch, run from
a neutral CWD, assert exact output):

- **`run_doc_generate.ps1`** -- an undocumented public routine -> `document --apply`
  -> assert a `<summary>TODO`, one `<param>` sentinel per param, `<returns>` when a
  function, and a fenced `<remarks>` facts block with the expected Called-from line.
- **`run_doc_idempotent.ps1`** -- run `document --apply` twice -> the file is
  byte-identical after the second run (managed regions are stable).
- **`run_doc_extend.ps1`** -- a routine with a hand-written `<summary>` + one filled
  `<param>` -> `document --apply` -> the prose is preserved verbatim, a missing
  `<param>` sentinel is added, and the facts block is inserted.
- **`run_doc_stale_param.ps1`** -- an `AUTO_PARAM`-marked `<param>` for a param that
  no longer exists is removed on regen; a HAND-typed stale `<param>` is flagged (not
  deleted).
- **`run_doc_cap.ps1`** -- a fixture project with > 15 callers -> the Called-from
  line shows 10 entries + `(+N more)`.
- **`run_doc_verb.ps1`** -- `--json` action reporting (created/extended/unchanged);
  dry-run does not modify the file; `--apply` writes a `.bak`.

Guardrail: full battery (lint 154/154, store 16/16, autofix 9 suites) stays green.

## Verification & publish

- Build via the delphi-build skill (staged Win64 exe in `third_party/dll-win64/`).
- Battery green + all `run_doc_*` harnesses.
- No index-schema change expected (v13). IDE change ends in a live smoke.
- Final whole-branch opus review -> bump VERSION (`DRagLint.CLI.pas:6`) to
  `0.90.0-alpha` -> CHANGELOG -> BACKLOG -> pack -> tag `v0.90.0-alpha` ->
  GitHub release. Release commit = CLI.pas + CHANGELOG + BACKLOG only; any rebuilt
  BPL/DCP in a SEPARATE `build(plugin):` commit; the release ZIP is CLI-only.

## Risks & mitigations

- **"Calls" (outgoing) query uncertainty.** The clean store method for a symbol's
  outgoing calls needs confirming; fallback is a bounded body text-scan. Mitigated
  by making it the first thing verified in the plan, and by the section being
  omittable (RenderFactsBlock skips empty sections) if it proves unreliable this
  chunk -- Called-from is the headline feature and is solid.
- **Comment-span detection off-by-one** (which lines are the existing comment) ->
  a mis-replaced region. Mitigated by `TParsedDoc.StartLine/EndLine` from the
  existing scanner + dry-run (default) never writing, + the idempotency test.
- **Fabrication risk.** Never emit prose we can't ground; `<summary>`/`<param>`
  bodies are always `TODO: describe.`; every facts line is index/AST-derived.
- **Managed-region tampering.** If a user hand-edits inside the fenced block, regen
  overwrites it (documented behaviour -- the block is explicitly ours). Hand prose
  belongs outside the sentinels.

## Out-of-band context

- Roadmap: `docs/lint/drag-lint TODO plan.md` Track 2 (2.1 = this chunk).
- Cadence (user): publish chunk -> plan next -> handoff -> clear -> implement.
- Next-chunk candidates (user asked to gather more doc sources): `<seealso>` from
  related symbols, `<since>`/`@deprecated` from VCS or `deprecated` directives,
  whole-unit/project batch, the DocInsight-collection spike, a `missing-doc` rule.
