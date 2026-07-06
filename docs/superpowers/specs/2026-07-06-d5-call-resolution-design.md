---
title: "D5 indexer milestone: receiver-type call resolution + call_edges + resolved query surface"
date: 2026-07-06
status: approved
author: Claude
---

# D5: Receiver-Type Call Resolution

## Summary

drag-lint's references are **name-only** today: the parser emits every call/identifier
ref with `SymbolId := 0` ("unresolved at parse time"), and consumers match by short
name. That produces **confidently-wrong facts** for common method names -- e.g.
`document --qname DRagLint.CLI.Run` lists `DoFbSnapshot`/`DoLinkOrm`/`DoLintAll` as
callers, but those call *different* `Run` methods (`TFbSnapshot.Run`, `TOrmLinker.Run`,
...); the corpus has ~13 distinct symbols named `Run`.

D5 adds **receiver-type call resolution**: a whole-DB post-index pass (`ResolveCallTargets`)
that types the receiver at each call site, resolves the call to a specific target symbol,
and records the result -- with a confidence -- in a new `call_edges` table. Consumers then
read *resolved* callers/callees instead of name-matches.

Primary motivations: (1) fix the AutoDocument Called-from false-positive bug; (2) enable a
precise resolved-query surface (find-callers --resolved, find-callees, call-path/callgraph)
that materially improves how humans and agents understand a codebase; (3) it also removes
the forms-csv L2 text-scan and makes polymorphic dispatch precise (find-callers/impact/graph
benefit in later opt-in work). Schema bump v13 -> v14.

## Background: what exists (surveyed 2026-07-06)

- **Refs are name-only.** `TReference.SymbolId := 0` (Parser.Delphi13.pas:151, "unresolved
  at parse time"). `refs.symbol_id` column exists but is never a resolved target.
- **Whole-DB resolution-pass pattern exists** and D5 mirrors it: `ResolveUnitUseTargets`
  and `ResolveAncestry` (SQLite.pas:2527 / :2645) run after per-file indexing -- pull
  everything into memory, resolve using name-candidates + the `unit_uses` file-scope graph,
  batch-write edges (e.g. `type_ancestors`). `ResolveTypeCategory(typeName, fileId)`
  (depth-capped alias-chasing) resolves a type name in a file's scope.
- **`FindReferencesTo(ASymbolId)`** (Interfaces.pas:76) already exists -- once refs carry a
  resolved target, precise callers are a `WHERE target_symbol_id = X` query.
- **Type capture, empirically verified (2026-07-06):**
  - FIELDS carry their declared type: `Emit(skField, ..., TypeTextOf(...))` ->
    `recv.TFoo.FBar : TBar` (in the symbol's Signature). PROPERTIES too (skProperty +
    TypeTextOf, Parser.Delphi13.pas:918/938).
  - LOCAL VARS and PARAMS are NOT emitted as symbols today (`query --name L` = 0 matches on
    a fixture with `var L: TBar`). Typing local/param receivers needs NEW parser work.
- **`enclosing_symbol_id`** on refs (v13) gives the innermost routine body containing a ref
  -- the basis for "which method makes this call" (Model.pas:95).
- **Schema:** `SCHEMA_VERSION = 13` (Schema.pas:6). `IsSchemaCurrent` gates read-only
  verbs; a version mismatch invalidates `FileIsUpToDate`'s sha/mtime skip, forcing reparse.
- **Library index** built via `index --scan-libraries-win` (Win32+Win64) or the manifest
  `Library` section (`index --all --only Library`) -> `library-Win32.sqlite`/`-Win64.sqlite`.

## Scope

### In scope (D5)

1. New parser emission: **all local vars + params as typed symbols** (a complete local symbol
   table incl. primitives -- see Design 3). Powers D5's receiver typing AND future
   context/hover/refactoring queries.
2. New whole-DB pass **`ResolveCallTargets`** with maximal receiver typing (8 receiver kinds).
3. New **`call_edges`** table (schema v14).
4. AutoDocument **Called-from** switches to resolved callers (the bug fix), with the 3-way
   confidence render (plain / `?` / excluded).
5. AutoDocument **Calls** facts upgrade to resolved callees (replaces the T3 body-scan where
   resolved). *In scope but cuttable if the chunk runs heavy.*
6. New CLI verbs: `find-callers --resolved`, `find-callees --qname X`, `ambiguous-calls`,
   and `call-path`/`callgraph` (the graph-traversal pair is the heaviest; cut first if
   trimming).
7. Migration v13 -> v14; rollout step that auto-starts the library reindex in the background.

### Explicitly NOT in scope

- Opting find-callers (default, name-based) / impact / graph / forms-csv over to resolved
  edges -- a later chunk (D5 provides the data; those consumers switch separately to avoid
  regressing long-standing behavior).
- Flow-sensitive receiver typing (a var reassigned to different types across a body). D5
  types by declaration; a receiver whose runtime type differs is either correctly the
  declared type or falls to `?`.
- Resolving calls into third-party/library code beyond what's indexed.

## Design

### 1. Architecture & data flow

D5 is a whole-DB post-index pass; the parser is unchanged EXCEPT for the new typed-local/param
emission (Design 3). Pipeline order (after all files indexed):

```
index files -> ResolveUnitUseTargets -> ResolveAncestry -> ResolveCallTargets (NEW, runs last)
```

`ResolveCallTargets` depends on both predecessors: the `unit_uses` graph for scope, and
`type_ancestors` for the method-on-type-chain walk. For each call/method ref that names a
routine, it types the receiver (Design 3), walks the receiver type's own + ancestor chain for
the method name, classifies confidence (Design 4), and writes a `call_edges` row.

Consumers read `call_edges` instead of name-matching. AutoDocument switches first; other verbs
opt in later.

### 2. The `call_edges` table (schema v14)

Mirrors `type_ancestors`' style; rebuilt wholesale each `ResolveCallTargets` run (always
consistent with current symbols).

```sql
CREATE TABLE IF NOT EXISTS call_edges (
  ref_id                  INTEGER NOT NULL,   -- FK to refs.id (the call site)
  target_symbol_id        INTEGER NOT NULL,   -- the resolved callee symbol
  confidence              TEXT    NOT NULL,   -- 'certain' | 'ambiguous'
  receiver_type_symbol_id INTEGER,            -- resolved receiver type (NULL for bare/global calls)
  PRIMARY KEY (ref_id)
);
CREATE INDEX IF NOT EXISTS idx_call_edges_target ON call_edges(target_symbol_id);
CREATE INDEX IF NOT EXISTS idx_call_edges_ref    ON call_edges(ref_id);
```

- **One row per resolved call ref** (`ref_id` PK). A ref resolves to at most one target.
- **No row = the resolver couldn't type the receiver at all** -> the `?` bucket, derived at
  query time.
- **`confidence`** drives rendering: `certain` -> plain; `ambiguous` -> `?` (an ambiguous
  edge still records a best-guess target so it stays queryable).
- **`receiver_type_symbol_id`** stored though not needed for Called-from -- cheap once
  computed, and it's the richer-edge data that justifies a dedicated table over reusing
  `refs.symbol_id`; enables the later find-callers/impact opt-in + polymorphic precision.
- `idx_call_edges_target` makes "all sites whose resolved target = this symbol" a fast index
  hit (the core Called-from query).

**Query derivation for "callers of symbol S", over refs whose `name_text` = S.Name.**
The rule follows the user's invariant: *100%-certain-ours -> plain; confirmed-different ->
excluded; anything less than 100% -> shown with `?`.*
- `call_edges` row with `target = S`, `confidence = certain` -> **caller, plain** (ground truth).
- `call_edges` row with `target = S`, `confidence = ambiguous` -> **caller, `?`** (best-guess
  points at S but not certain).
- name-match ref with **no** `call_edges` row -> **caller, `?`** (receiver untypable; unverified
  name-match).
- `call_edges` row with `target != S`, `confidence = certain` -> **excluded** (confirmed to call
  a specific different symbol -- this is what fixes the bug).
- `call_edges` row with `target != S`, `confidence = ambiguous` -> **caller, `?`** (best-guess
  points elsewhere but not certain, so we do NOT confidently exclude it -- less than 100% -> `?`).

### 3. Receiver typing (the maximal resolver)

For each call ref `X.M(...)` (or bare `M(...)`), determine the type of receiver `X`, then walk
that type's own + ancestor chain (`type_ancestors`) for a method `M`. Receiver kinds (all
data-backed after the parser addition below):

1. **Bare `M` / `Self.M`** -> the enclosing method's owning class (via `enclosing_symbol_id`
   -> its `ParentId`). **`inherited M`** -> walk to the parent class first.
2. **Field `FBar.M`** -> the field symbol's declared type (captured today).
3. **Property `Prop.M`** -> the property symbol's type (captured today).
4. **Typed local `L.M`** -> NEW: parser emits `L` as a typed symbol; look up in the enclosing
   routine's scope.
5. **Param `AFoo.M`** -> NEW: parser emits params as typed symbols; look up in the routine's
   param scope.
6. **Cast `(X as TBar).M` / `TBar(X).M`** -> the cast target type `TBar` (parse the cast).
7. **`with TBar-expr do M`** -> the `with` receiver's type (track the active `with` scope over
   the ref's line range).
8. **Function-return `GetFoo.M`** -> `GetFoo`'s return type (return types are captured).

**New parser work (kinds 4 & 5):** emit local vars + params as symbols carrying `TypeTextOf`.
**Emit ALL locals and params, including primitive-typed ones** (user decision 2026-07-06) --
a complete local symbol table, not just receiver-eligible types. Rationale: locals/params have
value well beyond D5's receiver typing -- context bundles, hover, and future refactorings
(rename-local, inline-variable, unused-local, change-signature) all want typed locals in the
index, and today they are dropped entirely (invisible to every query). D5 is the reason to build
it; the value is broader and permanent.
- New symbol kinds: `skLocalVar` and `skParam` (or reuse `skVarDecl` for locals + a new
  `skParam`). Each carries its declared type in `Signature` (via `TypeTextOf`), `ParentId` =
  the enclosing routine symbol, and its decl line span.
- Params come from the routine header; locals from the routine's `var` section(s). Both are
  scoped to the routine (looked up by `ParentId` = enclosing routine during resolution).
- **Size impact (measured, honest):** on `src/` (118 files) the current index is 3,332 symbols;
  emitting all locals+params is estimated at **roughly +8,000-10,000 symbols (>2x)** for source,
  and the libraries (RTL/VCL/DevExpress) scale far larger in absolute rows. Reindex is
  correspondingly slower -- which is exactly why the library reindex runs as an unattended
  background rollout step (Design 6). Measure the real delta during implementation and record it
  in the ship notes; if it proves prohibitive on the full library tree, the fallback is a config
  flag (default on) to restrict local/param emission -- but the chosen default is emit-all.

**Conservative at every step:** any receiver expression not in 1-8, a type name that doesn't
resolve in scope, or alias-chasing past the depth cap -> **no `call_edges` row** (`?` bucket).
Never fabricate a target.

### 4. Confidence classification

After typing the receiver and walking its type's own + ancestor chain for method `M`:

- **`certain`** -- receiver type resolved unambiguously AND `M` resolves to **exactly one**
  symbol on that chain.
- **`ambiguous` (`?`)** -- receiver type unknown / aliased past the depth cap, OR `M` matches
  **more than one** candidate (overloads, multiple in-scope, or an interface with multiple
  implementors). A best-guess `target_symbol_id` is still recorded (queryable) but rendered
  with `?`.
- **excluded from another symbol's callers** -- when `M` resolves `certain` to exactly one
  symbol, that row is recorded normally and never appears in ANY OTHER symbol's caller list.
  (Only a `certain` different-target excludes; an `ambiguous` different-target still shows with
  `?` -- see the query derivation in Design 2.)
- **method not found on the chain** (likely a receiver mis-type) -> no row (`?`).

Invariant: **any doubt -> `?` or exclude, never a wrong `certain`.** We only *hide* a potential
caller when we are `certain` it calls a specific different symbol; anything less than certain is
shown with `?`.

### 5. Consumers, rendering & new query verbs

**A. AutoDocument Called-from (the bug fix).** `Doc.Facts.Build` switches from
`FindCallersByName(name)` (Doc.Facts.pas:244) to a new store method
`FindResolvedCallers(targetSymbolId)`. Render per Design 2's query derivation: plain
(`certain`-ours), `?` (`ambiguous` either way, or no-row), excluded (`certain`-different-target
only). The existing `(+N more)` cap and dedupe apply to the combined list; `?` items sort after
plain ones.
Used-in (Doc.Facts.pas:312) resolves analogously for type receivers.

**B. AutoDocument Calls facts (in scope, cuttable).** Replace the T3 best-effort body-scan
`Ident(` heuristic with resolved callees (via find-callees data) where available; fall back
to the scan for unresolved sites. Fixes a second AutoDocument imprecision.

**C. New CLI verbs** (read `call_edges`; text + `--json`, following repo verb conventions):
1. **`find-callers --name X --resolved [--db]`** -- precise callers
   (`WHERE target_symbol_id = X`), each tagged `certain`/`ambiguous`. WITHOUT `--resolved`,
   existing name-based behavior is unchanged (no regression).
2. **`find-callees --qname X [--db]`** -- X's resolved outgoing calls (`call_edges` joined to
   `refs WHERE enclosing_symbol_id = X`), each with target + confidence.
3. **`ambiguous-calls [--qname X | --file F] [--db]`** -- the `?` bucket (confidence =
   ambiguous, or name-match with no row); a resolver-coverage diagnostic.
4. **`call-path --from A --to B [--max-depth N] [--db]`** and
   **`callgraph --qname X [--direction callers|callees] [--depth N] [--db]`** -- recursive
   traversal over `call_edges`, cycle-guarded (visited-set), depth-capped; text tree + JSON.
   **Heaviest piece; late tasks; first cut if the chunk must be trimmed.**

### 6. Migration, rollout & auto-reindex

**Schema bump v13 -> v14.** Additive migration creates `call_edges` + indexes. The new typed
local/param symbols require a reparse; because `IsSchemaCurrent` now reports a mismatch on
every existing DB, the normal index flow reparses all files (v11 -> v13 precedent). No
half-populated states: a DB is either pre-v14 (Called-from falls back to name-based = current
behavior) or fully v14 (precise).

**Auto-reindex the libraries (rollout step, NOT an exe feature).** Because v14 forces a full
reparse and the library indexes are the long pole (~1 hr+, heavier now with typed locals/
params), the D5 rollout -- once the new `drag-lint.exe` is built and staged to
`third_party/dll-win64/` -- launches the library reindex as a **detached background process**:
- `index --scan-libraries-win` -> `library-Win32.sqlite` / `library-Win64.sqlite`, running
  unattended while other work proceeds.
- Logs to `C:\TEMP\d5-library-reindex.log` with start/end timestamps (progress checkable).
- Does NOT block the rest of rollout (per-project DBs reindex fast; libraries catch up).
- Kills any orphaned `drag-lint.exe` / `drag_lint_graph.exe` first (the known reindex/pack
  lock gotcha).
This is a plan task (the final rollout step launches the background reindex); the exe itself
does NOT auto-spawn reindexes on schema mismatch (surprising for a CLI). Per-project CLIENT/
SERVER DBs and the manifest DBs reindex via the normal `index --all` flow on next touch.

## Testing

- **`tests/callresolve/`** resolver harnesses: fixtures with each receiver kind (Self, field,
  property, typed local, param, cast, with, function-return) -> assert `certain` /
  `ambiguous` / excluded / no-row per case.
- **Called-from regression (the bug):** a fixture with two same-named methods on different
  types, each with a distinct caller -> assert `document --qname A.Run` lists ONLY A's real
  caller (B's caller excluded), and an untypable name-match shows with `?`.
- **New verbs:** `find-callers --resolved`, `find-callees`, `ambiguous-calls`,
  `call-path`/`callgraph` -- fixture-driven, `--json` shape asserted.
- **Migration:** a v13 DB -> open -> v14, `call_edges` present, reparse populates it.
- **Guardrail (green throughout):** lint 154/154, store 16/16, autodoc 7/7, autofix 9/9.

## Verification & publish

- Build via the delphi-build skill (staged Win64 exe).
- Full battery + the new `callresolve` harnesses green.
- Final whole-branch review -> bump `DRagLint.CLI.pas:6` VERSION -> CHANGELOG -> BACKLOG ->
  pack -> tag -> GitHub release. Release commit = CLI.pas + CHANGELOG + BACKLOG only; any
  rebuilt BPL in a separate `build(plugin):` commit; release ZIP CLI-only.
- **After staging the release exe: launch the background library reindex (Design 6).**

## Risks & mitigations

- **Wrong `certain` (a confidently-wrong resolved target).** The worst failure -- it would
  re-introduce false facts under a "verified" label. Mitigated by the conservative
  classifier (Design 4): any ambiguity -> `?` or no row; `certain` requires an unambiguous
  receiver type AND a single method match. The Called-from regression test locks the `Run`
  case.
- **Index-size growth from emitting ALL locals/params (>2x symbols, user-chosen).** Accepted for
  the broader value (complete local symbol table -> context/hover/refactorings). Reindex cost
  absorbed by the unattended background library reindex (Design 6). Measure the real delta during
  implementation and record it in ship notes. Fallback if prohibitive on the full library tree: a
  config flag (default = emit-all) to restrict emission -- but emit-all is the chosen default.
- **Receiver-typing coverage gaps** (untyped receivers -> `?`). Honest by design: `?` marks
  the uncertainty rather than guessing; `ambiguous-calls` surfaces the gaps for iteration.
- **Chunk size.** D5 is large (parser change + resolution pass + schema + 4 verbs + 2
  AutoDocument consumers). Cut order if trimming: (1) call-path/callgraph, (2) the Calls-facts
  upgrade (B), (3) narrow receiver kinds 6-8 (cast/with/return) to a follow-up -- leaving the
  Self/field/property/local/param core + Called-from fix + find-callers/callees/ambiguous.

## Out-of-band context

- Bug diagnosis + D5 motivation: `docs/lint/BACKLOG.md` (D5 item + top RESUME note, commit
  86f0b58).
- Cadence (user): publish chunk -> plan next -> handoff -> clear -> implement.
- Later opt-in candidates (separate chunks): find-callers-default / impact / graph / forms-csv
  L2-removal switch to resolved edges; flow-sensitive receiver typing; `impl_of` +
  `proc-assign` edge kinds in `call_edges`.
