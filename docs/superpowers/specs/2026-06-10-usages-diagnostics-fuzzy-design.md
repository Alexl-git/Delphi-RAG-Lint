# Design: Find-Usages (B) + Diagnostics display (C) + Fuzzy speed (D)

Status: approved to implement (user delegated implementation 2026-06-10).
Branch: `v0.40.3-multidb-hover-buffer` (current). All work local; push held.

## Context

- Parser (`DRagLint.Parser.Delphi13`) currently emits references only for `call`
  and `type_use`. Declarations of vars/fields/properties/consts are symbols, but
  their *usages* are not captured -> Find-Usages misses `dxDBGrid1.X := ...`.
- DFM parser emits `skComponent` (component tree) + `event-binding` refs
  (`OnClick = Handler`). Already indexed.
- `impact` CLI command walks transitive callers (blast radius by call graph).
- Diagnostics: `DiagnosticCache` + `EditViewNotifier` render gutter/squiggle
  markers; `check-ast` produces syntax errors; lint produces warnings/infos.
  Gap = nothing auto-runs them on save.
- Fuzzy: trigram pre-filter matches any symbol sharing >=1 trigram, then
  Levenshtein over all candidates -> ~3.2 s on 1.5M symbols.

---

## B. Find Usages: usage-refs + width selector + deep/shallow flag

### B1. Indexer: capture identifier usage references (deep mode)
New ref kinds emitted by the Delphi parser, in addition to `call`/`type_use`:
- `read`  - an identifier used in expression position (base/entity of a member
  access `X.Y` -> ref `X`; a standalone identifier expression; an argument).
- `write` - an identifier that is the target of an assignment (`X := ...` -> `X`).
- `attribute` - the name inside an attribute `[Foo]`.

Rules / scope:
- Only in expression context. Do NOT emit for: declaration name positions,
  type positions (already `type_use`), the callee of a call (already `call`),
  unit names in `uses`.
- Base-of-member-access is the key case for components (`dxDBGrid1.DataSource`).
- Gated by an indexer flag `EmitUsageRefs` (see B4). Off -> today's behaviour.

Implementation: a property `TDelphi13Parser.EmitUsageRefs: Boolean` (default
False) checked in `Walk` before emitting `read`/`write`/`attribute`. The
indexer sets it from the scan depth.

### B2. CLI: `drag-lint usages`
`drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db ...] [--depth N] [--format text|json]`
- **narrow** (default): the declaration of `X` + every ref to exactly `X`
  (`call`/`type_use`/`read`/`write`/`attribute`).
- **wide**: narrow, plus - if `X` resolves to a DFM `skComponent` - its child
  components (DFM subtree), the event handlers wired to `X` and those children
  (`event-binding` refs), the published field declaration, and all refs to each
  of those names.
- **very-wide**: wide, plus the transitive call chain out of each event handler
  (reuse `FindTransitiveCallers`, depth-capped by `--depth`, default 3).
Output grouped by category: Declaration / Reads / Writes / Calls / Type uses /
Attributes / Event handlers / Subcomponents / Impact. JSON mirrors the groups.

Width is purely query-time over already-indexed data -> switching width is free.

### B3. Plugin: width selector on the Find Usages tab
- Add a 3-state selector (radio group or combobox: Narrow / Wide / Very-wide)
  next to the symbol box in `CreateEmbeddedUsages`.
- On Enter or selector change, run `usages --name <X> --width <w>` (instead of
  the current `find-callers`), parse the grouped JSON, render grouped tree.
- Double-click still navigates; matched-term highlight retained.

### B4. Scan depth flag (one scanner, not two)
- `index` / `scan-all` gain `--deep` / `--shallow` (default: deep for project &
  active scans, shallow for `--scan-libraries`). `scan-all` sets per dictionary.
- Deep => indexer `EmitUsageRefs := True`. Shallow => today's behaviour.
- Requires a one-time re-index of the user's project + active-projects DBs
  (incremental; libraries stay shallow).

### B verification
- Fixture unit using a component-like var: `query`/`usages` finds reads, writes,
  member-access base. T-fixture `T44_usages.bat`.
- `usages --width wide` on a DFM form component returns its handlers/subcomponents.

---

## C. Diagnostics display (syntax errors / warnings / infos)

### C1. Auto-run on save
- In `SaveNotifier.AfterSave` (already fires, already debounced), in addition to
  the reindex, run `drag-lint check-ast <file> --format json` (syntax errors)
  and `drag-lint lint <file> --format json` (warnings/infos) for `.pas`.
- Parse findings -> `DiagnosticCache.Update(file, findings)` -> existing
  `EditViewNotifier` renders gutter marks + squiggles; Structure "Diagnostics"
  node already lists them.
- Severity mapping: AST error -> error; lint -> warning/info per rule metadata.
- Setting `AutoDiagnosticsOnSave` (default on) so it can be turned off.

### C2. Live-ish without a compiler
- Syntax errors come from `check-ast` (tree-sitter ERROR/MISSING) - no compiler,
  fast. Compiler hints/warnings remain on-demand via existing Compile&&Diagnose.
- Run off the save (debounced) to avoid editor lag; spawn detached, publish when
  it returns (main-thread Queue, same pattern as the reindex status message).

### C verification
- Save a file with a deliberate syntax error -> squiggle + Structure entry.
- Save a file tripping a lint rule -> warning marker.

---

## D. Fuzzy lookup speed

### D1. Narrow the candidate set
In `FindSymbolsFuzzy`:
- Require a minimum number of shared trigrams instead of >=1:
  `... WHERE trigram IN (...) GROUP BY symbol_id HAVING COUNT(*) >= :minShared`
  with `minShared = max(1, (Length(Grams) + 1) div 2)` (>= half the pattern's
  trigrams). Uses the new `idx_symbol_trigrams_symbol` index.
- Length pre-filter: skip candidates whose `abs(len(name) - len(pattern)) > MaxD`
  before computing Levenshtein (Levenshtein >= length difference).
- Cap the Levenshtein-scored set defensively (e.g. first N by trigram overlap)
  if still large.

### D verification
- `query --name csmRed --fuzzy --db <library>` (a miss) drops from ~3.2 s to
  well under 1 s; results still correct (closest matches returned).

---

## Sequencing
1. **D** (small, isolated, immediate win; no re-index).
2. **C** (medium; reuses cache/marker pipeline; no re-index).
3. **B** (large; parser + CLI + plugin + project re-index). Do B last so the
   re-index happens once at the end.

Each step: build -> test (fixture / empirical) -> commit -> deploy. Plugin
changes deploy to `third_party\dll-win32` when the IDE is closed, else staged.

## Risks
- B parser usage-refs: noise / index growth on projects (acceptable per user;
  libraries stay shallow). Member-access-base heuristic must avoid double-emit
  with `call`. Pin exact grammar node types during impl.
- B width "wide": depends on DFM component/event data already indexed; verify
  the join from a component symbol to its DFM children + event-binding refs.
- C: must never lag the editor or surface exceptions into the IDE save path
  (spawn detached; swallow errors - same discipline as existing notifiers).
