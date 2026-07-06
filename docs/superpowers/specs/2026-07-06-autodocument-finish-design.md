---
title: "AutoDocument Finish: batch, doc-sources, missing-doc + doc-drift, DocInsight spike"
date: 2026-07-06
status: approved
author: Claude
---

# AutoDocument Finish

## Summary

Completes Track 2 (AutoDocument) of the drag-lint action roadmap end-to-end,
including the previously deferred semantic-drift work. AutoDocument Chunk 1
(v0.90.0-alpha) proved the full vertical slice on a **single** public
declaration: detect existing/missing/stale docs -> generate or repair a
DocInsight comment via **managed regions** -> insert via the shared apply
substrate -> a `document --qname` CLI verb + an IDE "Document it" menu. This
milestone widens that to **whole-unit and whole-project batch**, adds three new
ground-truth **doc-sources**, ships two new **lint rules** (`missing-doc`,
`doc-drift`), reframes the deferred **semantic-drift** work as a deterministic
doc-vs-code diff, and runs a short **DocInsight-collection spike**.

The whole milestone preserves the two Chunk-1 invariants: **never fabricate
prose** (a missing `<summary>` becomes a `TODO: describe.` marker, never a guess;
every emitted section is a ground-truth fact from the index or signature) and
**idempotency** (a second run produces byte-identical output).

Ships as **v0.93.0-alpha**. No index-schema change expected (still v14). One new,
opt-in, gracefully-degrading external dependency: `git` (for `<since>` and the
optional change-since-documented drift signal).

## Background: what already exists (do NOT rebuild)

Surveyed 2026-07-05/06:

- **`src/doc/DRagLint.Doc.Facts.pas`** -- `TDocFactsBuilder.Build(store, sym):
  TDocFacts`. Pulls index facts: Called-from (resolved callers, post-D5),
  outgoing Calls, Used-in, Raises, Returns type. `TDocFacts` is the record the
  managed block renders from.
- **`src/doc/DRagLint.Doc.Regions.pas`** -- `TDocRegions`. Owns the sentinel
  fences (`<!-- drag-lint:auto BEGIN/END -->`, per-param `<!-- drag-lint:auto
  param -->`) and `MergeComment(existing, sigParams, facts, hasRet, prefix)`:
  regenerates ONLY the managed block, preserves hand prose, idempotent.
- **`src/doc/DRagLint.Doc.Document.pas`** -- `TDocDocument`, the single-decl
  orchestrator: `TDocFactsBuilder.Build` -> `TDocRegions.MergeComment` ->
  `TTextEdits`. This is what batch drives N times.
- **`src/refactor/DRagLint.Refactor.DocStub.pas`** -- `TDocStubGenerator` +
  signature-parsing backbone: `ExtractParamList`, `ParseParamNames` (handles
  `const/var/out/in/array of` + grouped `A, B: T`), `SignatureHasReturn`,
  `ReadSourceLine`. Reused by drift's param/returns diffing.
- **`src/parser/DRagLint.Parser.DocComments.pas`** -- `TDocCommentScanner.Scan`
  + `TDocCommentParser` -> `TParsedDoc` (`Summary, Remarks, ReturnsText,
  Params: TArray<TDocParam>{Name,Desc}, Exceptions, StartLine, EndLine,
  HasContent`). The drift engine diffs `TParsedDoc` against the signature.
- **Apply substrate:** `TTextEditApplier` + the CLI `FinalizeAndOutput` path that
  `lint-all --fix` already uses (ordering, `.bak` backups, `--json`, ShouldKeep
  rule gating). Batch reuses this; it does NOT build a new apply path.
- **Closure/uses scanner** (`src/index/DRagLint.Index.Closure.pas`,
  `TClosureResolver.Resolve(dproj)`) -- yields the project's file set for the
  project-wide batch scope.

## Architecture: two engines, thin consumers

Two new reusable engines in `src/doc/`; everything else is a thin skin over them.

### Engine 1 -- `TDocBatch` (`src/doc/DRagLint.Doc.Batch.pas`)

Drives `TDocDocument` (Chunk 1) across a set of public declarations and produces
ONE `TTextEdits` set that flows through the existing `TTextEditApplier` +
`FinalizeAndOutput` path.

- `DocumentUnit(store, unitFile, opts): TTextEdits` -- every public/published
  declaration in one unit.
- `DocumentProject(store, dproj, opts): TTextEdits` -- every public declaration
  across the closure's file set (or `DocumentAll` for the whole index).
- `TDocBatchOptions = record Stubs: Boolean; IncludeSeeAlso, IncludeDeprecated,
  IncludeSince: Boolean; ... end;`
- **Default = facts-only.** For each decl: always write/refresh the managed FACTS
  block + preserve hand prose. Emit a `TODO: describe.` `<summary>` stub ONLY
  when the decl has NO doc at all AND `Stubs=True` (`--stubs`). This prevents a
  project run from flooding the tree with hundreds of TODOs.
- **Scope = public/published surface only** (the project CDD rule): private
  helpers are skipped unless they already carry a doc-comment (then their facts
  block is still refreshed).
- **Idempotency at scale:** a second batch run is byte-identical (inherits
  `MergeComment`'s managed-region idempotency; batch adds no per-run-varying
  content -- caller line numbers etc. are already file-name-only per the Chunk-1
  fix).

### Engine 2 -- `TDocDrift` (`src/doc/DRagLint.Doc.Drift.pas`)

A pure analysis function -- no mutation, no LLM, deterministic diffing only.

- `Analyze(store, sym, parsedDoc): TArray<TDocDriftFinding>`.
- `TDocDriftFinding = record Kind: TDocDriftKind; Detail: string; Fixable:
  Boolean; Line: Integer; end;`
- Consumed by the `doc-drift` lint rule (report) and, for the fixable subset, by
  `TDocBatch` (repair).

Consumers (all thin): the CLI verbs, the two lint rules, and the IDE menu items.
The new doc-sources extend `TDocFactsBuilder` + `TDocRegions`, so single-decl AND
batch inherit them with no consumer change.

## CLI + IDE surface

### Batch verbs

- `document --unit <file> [--apply] [--stubs] [--json] [--no-backup]`
- `document --project <dproj> [--apply] [--stubs] [--json] [--no-backup]` and/or
  `document-all` (whole index).
- Default (no `--apply`) = preview (the edits + a summary count). `--stubs` opt-in
  (default facts-only). `--json` for AI orchestration. Single-decl `document
  --qname` (Chunk 1) is unchanged.

### New doc-sources (into the managed facts block -- all ground-truth)

- **`<seealso cref>`** -- the most-related symbols from the index/call graph
  (resolved receiver types, sibling declarations, top callees), **capped** (a
  small N, e.g. 3-5) and always inside the managed block so it regenerates. A
  heuristic for "related," but every cref is a real indexed symbol.
- **`@deprecated`** -- a `<remarks>` deprecation note when the symbol carries
  Delphi's `deprecated` directive (with its message string if present). 100%
  ground-truth (it is in the declaration).
- **`<since>`** -- from `git blame`/`git log` of the declaration line.
  **OPT-IN via `--since`.** DEGRADES SILENTLY: emits nothing when git is absent,
  the repo is unavailable, or the decl line cannot be confidently attributed
  (moved/reformatted). Never emits a wrong `<since>` -- absence over a guess.
- **Stale-param hardening** -- the existing stale-param detection (doc param not
  in signature) is hardened to run correctly at unit/project scale (renamed /
  removed / reordered params flagged consistently across a batch).

### Two new lint rules -- BOTH ON BY DEFAULT (see "ON-by-default" section)

- **`missing-doc`** -- a public/published declaration has no DocInsight
  doc-comment. **Public surface ONLY** (private helpers exempt per CDD).
  Report-only.
- **`doc-drift`** -- a doc-comment is structurally stale vs the code (the
  `TDocDrift` signals below). Report-only + participates in `--fix` for its
  mechanically-safe subset. Both rules respect the existing per-rule
  enable/severity config (dial down without turning off).

### IDE

- "Document unit" / "Document project" menu items (drive `TDocBatch`).
- `doc-drift` findings appear as diagnostics with a "Fix it" for the safe subset
  (reuses the AutoFix Fix-it/Fix-all wiring).

## Semantic-drift (`doc-drift`) -- deterministic signals, no NLU

The deferred "semantic-drift" is reframed as a DETERMINISTIC doc-vs-code diff
(drag-lint is pure Object Pascal, no LLM calls). `TDocDrift.Analyze` flags:

- **Param drift** (emphasis): `<param name="X">` where X is not in the current
  signature (renamed/removed); a signature param with no `<param>` (added);
  a **volatile-param** mismatch -- a `var`/`out` param documented as input-only,
  or whose mode changed since the doc was written.
- **Returns drift** (emphasis): `<returns>` present but the routine returns
  nothing; routine now returns a value but has no `<returns>`; the return **type**
  changed from what the prose documents.
- **Exception drift:** `<exception cref="E">` for an `E` the body no longer raises
  (from the index Raises facts).
- **Identifier drift:** hand summary/remarks mention an identifier that was
  renamed/removed -- BOUNDED to high-confidence exact matches only (never a fuzzy
  guess).
- **Facts-block staleness:** the managed `<!-- drag-lint:auto -->` block differs
  from a fresh index render.

**Fixable subset (`--fix`), mechanically safe only:**
- facts-block refresh (always idempotent-safe);
- adding a missing `<param>` / `<returns>` stub for an added param / new return.

**Report-only (NEVER auto-rewrites prose):** renamed-param prose, return-type
changes, identifier mentions. These are flagged for a human -- honoring the
no-fabrication rule. An honest "this may have drifted, re-check" beats a wrong
auto-edit.

## ON-by-default: the deliberate tradeoff + mitigations (PROMINENT)

Both new rules ship **ON by default** -- a deliberate departure from the
project's usual OFF-by-default-for-new-rules convention (user decision
2026-07-06). Because `missing-doc` ON means the FIRST `lint`/`lint-all` run on
any existing codebase (including drag-lint's own tree, which has many
`TODO: describe.` stubs and undocumented helpers) surfaces a LARGE wave of
findings, the design bakes in three mitigations so "ON" is usable, not noise:

1. **`missing-doc` is public/published-surface ONLY.** Private helpers are exempt
   (matches the CDD rule -- docs required on public surface, optional on private).
   This is the single biggest noise reducer.
2. **Per-rule configurability preserved.** Both rules honor the existing
   enable/severity config, so a user can lower severity or scope them without
   turning them off -- ON-by-default is the starting point, not a straitjacket.
3. **Measured first-run.** The first-run finding count on drag-lint's own tree is
   MEASURED and DOCUMENTED (like the AutoFix 163-rule sweep), so the noise level
   is a known, stated number in the release notes -- not a surprise. If the
   measured wave is unreasonable, that is a signal to revisit the default before
   ship (a data-driven checkpoint, not a silent commitment).

A `TODO: describe.` stub that drag-lint itself emitted does NOT count as
"documented" for `missing-doc` (a stub is a request for a human summary, not a
doc) -- but it also is not re-flagged endlessly: `missing-doc` fires on NO
managed block at all, `doc-drift` owns the "your stub/prose is stale" case, so
the two rules do not double-report the same decl.

## DocInsight-collection spike (standalone investigation)

One investigation task, produces a short findings note (NOT code): does RAD Studio
collect documentation into a specified folder during compilation (the
DocInsight / XML-doc output option), what is it supposed to emit, and why did it
never give meaningful results for the user? Confirm what it emits, then record a
recommendation: "we supersede the built-in" vs "we feed/augment it." Outcome
feeds a FUTURE decision, does not gate this milestone.

## Rollout, safety, testing

- **v0.93.0-alpha.** No schema change (v14). `<since>`/git is the only new
  external dependency: opt-in + degrades silently.
- **Idempotency preserved end-to-end:** second batch run byte-identical; drift
  `--fix` idempotent (a fixed doc is drift-free on re-analysis).
- **No fabrication:** batch facts-only by default; drift never rewrites prose;
  `<since>` absent over wrong.
- **TDD + fixtures:** new suites `run_document_unit`, `run_document_project`,
  `run_doc_drift`, `run_missing_doc`, plus fixtures for: stubs-opt-in (facts-only
  default vs `--stubs`), idempotency (2nd run byte-identical), git-absent
  `<since>` degradation, each drift signal (param/returns/exception/identifier/
  facts-stale), and the public-surface-only `missing-doc` scope. The FULL existing
  battery stays green: lint 154, store 16, autodoc (existing 7 + new), autofix 9,
  callresolve 12, + the 9 preprocess harnesses.
- **Build gate:** the delphi-build recipe (rsvars + msbuild Win64, ExitCode 0 /
  `OK: staged`, no dcc64 errors). ASCII/CRLF/no-BOM discipline on all new files.
- **Execution:** superpowers:subagent-driven-development, PHASED so the structural
  pieces land first and `doc-drift` (the reframed deferred item) is the FINAL
  bounded phase -- if drift proves fuzzier than the deterministic design assumes,
  batch + doc-sources + `missing-doc` + the spike still ship a complete
  "AutoDocument finished" milestone.

## Out of scope

- LLM-written prose / true intent understanding (drag-lint is pure Object Pascal,
  no LLM API calls -- an explicit project rule). `doc-drift` detects STRUCTURAL
  staleness only.
- `expand`-style anything; no index-schema change.
- Convert-Components (Track 3) and Refactoring (Track 4) -- separate tracks.
