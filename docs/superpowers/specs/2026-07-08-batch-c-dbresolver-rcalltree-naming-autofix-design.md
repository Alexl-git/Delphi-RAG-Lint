# Batch C -- DbResolver project-name probe + Reverse call-tree report + Naming autofix (phase 1)

> **Date:** 2026-07-08
> **Status:** design approved; ready for implementation plan.
> **Scope:** three independent post-v0.95 features, sequenced small -> large. Ride
> the next version bump (currently untagged post-v0.95, `main`=`05d29d4`).
> **Deferred (out of scope):** architectural charts (Track 5.3) -- its own
> brainstorm; naming autofix **phase 2** (prefix-adding, e.g. `client -> FClient`).

## Why these three, together

They are the top of the roadmap candidate list (`docs/lint/drag-lint TODO plan.md`)
and, critically, **each reuses an engine that already ships** -- so all three are
bounded feature-wiring jobs, not new-engine builds:

- **DbResolver fix** -- a filed TODO with the exact prescription already exists.
- **Reverse call-tree** -- the upward traversal + cycle-guard already exist
  (`callgraph --direction callers`); the closest report-verb template
  (`deps-report`) is fresh.
- **Naming autofix (phase 1)** -- the global-rename engine is fully ready and a
  naming rule is *already* fixable (`reserved-word-casing`), proving the pattern.

The three touch disjoint code, so they can be implemented in any order (or in
parallel). Recommended sequence lands the smaller wins first: **1 -> 2 -> 3**.

---

## Feature 1 -- DbResolver project-name probe (fixes "Code Elements 0")

### Problem
The IDE Structure tree shows `Code Elements (0)` when a project's index was written
to `<projdir>\<projname>.sqlite` (the project-name file that `index --project` and
older workflows produce) instead of the settings-template file
`<projdir>\drag-lint.sqlite`. The resolver never probes the project-name file,
silently falls back to a workspace/global DB that lacks this file's symbols, and
`outline --db <that>` returns 0. Diagnostics are unaffected because they come from
the LSP server, not `outline`.

A filed TODO in `src/delphi-plugin/DragLint.Plugin.DbResolver.pas:25-36` prescribes
the fix verbatim.

### Change
- In `PrimaryDbForProject` (`:529`) and the ancestor walk `FindAncestorDb`
  (`:398`, canonical-name const `:411`), **also probe
  `ChangeFileExt(AProjPath, '.sqlite')`** = `<projdir>\<projname>.sqlite`.
- **Prefer whichever exists and is non-empty.** Order of candidates at each level:
  1. the settings-template file (`<projdir>\drag-lint.sqlite`) -- unchanged, so
     existing setups keep their exact behaviour;
  2. the project-name file (`<projdir>\<projname>.sqlite`) -- **new**;
  before falling through to the workspace/global ancestor DB and the manifest/
  siblings/library sources. The project-name file therefore wins over the masking
  workspace fallback, which is the whole point.
- "Non-empty" = file exists and size > 0 (a zero-byte or absent file is not a
  candidate). No schema probe at resolution time (keep it cheap); the existing
  consumer already tolerates an empty/other DB by showing 0.
- Remove/close the TODO comment block once done.

### Isolation / boundaries
The probe-order decision is extracted into a **pure, OTA-free helper**
(e.g. `PickProjectDb(const AProjDir, AProjPath: string): string` returning the
chosen path or `''`), so it can be unit-tested headlessly without a live IDE.
`PrimaryDbForProject` / `FindAncestorDb` call the helper; they keep the OTA glue.

### Testing
- **Headless (the automatable gate):** a test that points the helper at a temp dir
  containing only `<projname>.sqlite` (non-empty) and asserts it is chosen over an
  absent/zero-byte template file; a second case with both present asserts the
  template still wins (back-compat); a third with neither asserts `''` (fall
  through). No IDE needed.
- **Live-IDE smoke (one line, user runs):** open a project whose index is
  `<projname>.sqlite`, confirm the Structure tree now shows a non-zero
  `Code Elements (N)`.

### Deliverable touchpoints
- `src/delphi-plugin/DragLint.Plugin.DbResolver.pas` (probe + helper).
- **BPL rebuild required** (this is plugin source) -- Win32, RAD Studio closed.
- One headless test (`tests/autotest/run_dbresolver_probe.ps1` or a DUnitX case,
  whichever the helper's testability allows).

### Risk
Very low. Purely additive to the probe order; zero behaviour change when the
template-named file exists.

---

## Feature 2 -- Reverse call-tree report (`reverse-calltree`)

### Goal
A first-class, navigable **"who calls X, and who calls them"** N-deep *reverse*
tree, per symbol, with call sites (`unit:line`) and cycle markers. **CLI-only** --
no IDE right-click this slice (the IDE menus are already overloaded; keeping it
CLI-only also keeps the whole feature headlessly testable, no BPL work).

### What already exists (reused, not rebuilt)
- **Upward traversal + cycle-guard:** `DoCallGraph --direction callers`
  (`src/cli/DRagLint.CLI.pas:9946`) walks `ISymbolStore.FindResolvedCallers` with a
  global-visited `TDictionary<Int64,Boolean>` that emits `(cycle)` on re-encounter
  (`:9839`). Root resolution via `ResolveEndpointIds`.
- **Report-verb template:** `deps-report` -- a pure
  `BuildDepsReport(stores, opts): TDepsReport` engine in
  `src/report/DRagLint.Report.Deps.pas` (record model + summary + edge list, no
  I/O, borrows the store) with `RenderText`/`RenderJson`/CSV renderers and an
  `--edges` toggle (`DoDepsReport` at `DRagLint.CLI.pas:5757`).

### Two real gaps this feature fills
1. **Call-site `unit:line` per edge.** `TCallEdge`
   (`src/core/DRagLint.Core.Model.pas:127`) carries only
   `RefId`/`TargetSymbolId`/`ReceiverTypeSymbolId`/`Confidence` -- **no location**.
   The engine must **join `RefId` -> `refs`** to recover the caller's call-site
   file:line for each edge. This is the one genuinely new store/SQL surface.
2. **No chart emit on the caller tree.** `callgraph` renders text + `--json` only.
   Add `--format mermaid|dot`, borrowing the unit-level `graph` verb's existing
   dot/mermaid emit as the precedent (`DoGraph`, `DRagLint.CLI.pas:3234`).

### New units / wiring
- **Engine:** new `src/report/DRagLint.Report.RCallTree.pas` -- a pure
  `BuildReverseCallTree(const AStores: TArray<ISymbolStore>; const ARootQName: string;
  const AOpts: TRCallTreeOptions): TReverseCallTree` following the `deps-report`
  shape (borrows stores, no I/O).
  - **Node record:** `{ QName: string; Site: string {unit:line of the call site};
    Cycle: Boolean; Callers: TArray<node> }`.
  - **Summary record:** node count, max depth reached, cycle count, whether the
    depth cap truncated the tree.
  - **Options record:** `Depth` (default 3, matching `callgraph`), multi-store,
    `NamePattern`/root selection consistent with the existing endpoint resolver.
  - **Designed for reuse:** AutoDoc's future `<remarks>` "Called from"
    (Track 2.1) can call this engine at `depth=1` -- documented here, **not wired
    in this batch** (no Track 2 scope creep).
- **Verb:** new `reverse-calltree` -> `DoReverseCallTree` in the CLI, dispatched
  alongside `callgraph`. Root via the existing `ResolveEndpointIds`. Flags:
  `--name`/`--qname`, `--depth N` (default 3), `--format text|mermaid|dot`,
  `--json`, repeatable `--db`. (Verb name chosen for clarity + obvious pairing with
  `callgraph`; a short alias like `who-calls` is a later cosmetic nicety, not this
  slice.)
- **Renderers:** text tree (indented, `unit:line` per node + `(cycle)` marker),
  JSON (schema `reverse-calltree/1`, nested `{qname, site, cycle, callers:[...]}`),
  and mermaid/dot.

### Isolation / boundaries
The engine is a pure function over borrowed stores with a record return -- same
contract as `BuildDepsReport`. Renderers are separate and stateless. The
`RefId -> refs` join is the only new store interaction; it belongs in the engine
(or a thin store method if one already exposes ref lookups -- confirm during
implementation).

### Testing (fully headless)
A fixture project with a known caller chain `A -> B -> C` plus a deliberate cycle:
- reverse tree from `C` surfaces `B` then `A` with correct `unit:line` call sites;
- the cycle path emits the `(cycle)` marker exactly once (no infinite walk);
- `--depth 1` truncates to direct callers and the summary flags truncation;
- `--json` matches the `reverse-calltree/1` schema; `--format dot|mermaid` emits
  parseable output (node/edge count assertion).
Battery script `tests/autotest/run_reverse_calltree.ps1` (established autotest
pattern).

### Deliverable touchpoints
- New `src/report/DRagLint.Report.RCallTree.pas` (engine + records).
- `src/cli/DRagLint.CLI.pas` (`DoReverseCallTree` + dispatch + arg defaults +
  renderers, or renderers in the engine unit matching `deps-report`'s split).
- `tests/autotest/run_reverse_calltree.ps1` + fixture.
- **No BPL / IDE work.** CLI Win64 rebuild + deploy to `third_party/dll-win64`.

### Risk
Low-medium. Traversal + cycle-guard are proven. New surface = the `RefId->refs`
join (straightforward) and dot/mermaid emit (has a precedent).

---

## Feature 3 -- Naming autofix, phase 1 (re-casing via the rename engine)

### Goal
Make selected naming-convention findings **fixable** -- "Fix it" in the IDE and
`lint --fix` on the CLI -- by **synthesizing the corrected identifier** and driving
the existing global-rename engine. **Phase 1 = re-casing only** (mechanical,
collision-safe). Prefix-ADDING (`client -> FClient`, param `x -> pX`) is
**deferred to phase 2** and out of scope here.

### What already exists (reused)
- **Rename engine, fully ready** -- `src/refactor/DRagLint.Refactor.Rename.pas`:
  `TRenameRefactoring.Build` (store-backed global rename, decl + all reference
  sites, sorted back-to-front for safe apply), `BuildLocal` (pure-AST routine-local
  rename for scoped vars/params), `Apply` (ANSI/CRLF, optional `.bak`),
  `ConflictReason` (collision check -- non-empty reason when the target is reserved
  or collides with a sibling under the same parent). **The token match at the
  stored position is already case-insensitive** (`SameText` then forward-scan),
  which is exactly right for re-casing.
- **Precedent that a naming rule can be an autofix:** `reserved-word-casing` is
  *already* in `FIXABLE_RULE_IDS` and fixed by lowercasing (`DRagLint.CLI.pas:4227`,
  branch ~`:4587`).
- **Store-backed autofix append pattern:** `doc-drift`/`missing-doc` are fixable
  with **no** `BuildAutofixEdits` branch -- their edits come from
  `TDocumenter.BuildFor`, appended in `FinalizeAndOutput` (`DRagLint.CLI.pas:4753`);
  the `FIXABLE_RULE_IDS` comment (`:4218-4224`) documents this exception. A
  rename-driven naming fix follows **this** precedent, because rename yields
  `TRenameEdit` (Rename.pas), not `TTextEdit` (TextEdit.pas) -- two distinct applier
  types. It does **not** go through the pure-text `BuildAutofixEdits` chain.

### The core new work -- the name synthesizer
Naming findings carry only the offending identifier + a human `Message` -- **no
computed "expected name"** (`TNamingChecker.EmitAt`,
`src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas:327`). Phase 1 adds a small,
pure **name-synthesizer**: given the offending name + the `TNamingConfig` style for
its rule (`src/lint/DRagLint.Lint.Config.pas:16`), produce the corrected
identifier. Phase-1 rules:

| Rule id (finding)   | Synthesis            | Rename call        | Scope            |
|---------------------|----------------------|--------------------|------------------|
| `method-pascalcase` | -> PascalCase        | `Build` (global)   | cross-unit sites |
| `local-var-casing`  | -> configured style  | `BuildLocal`       | routine-local    |
| `const-casing`      | -> configured style  | `Build` / `BuildLocal` by scope | unit or local |
| `reserved-word-casing` | (unchanged -- already fixed) | existing text fix | -- |

`local-var-casing` uses `BuildLocal` (safest -- no cross-unit refs).
`const-casing` chooses `Build` (unit-level const) vs `BuildLocal` (routine-local
const) by the symbol's scope; the synthesizer/dispatcher determines which from the
finding + store.

The synthesizer is a **pure function** (`SynthesizeCasedName(AOldName: string;
AStyle: ...): string`) -- unit-testable in isolation, no store, no I/O.

### Configurable -- reuse the existing mechanism (no new config concept)
A naming rule is offered as a fix only when **both**:
1. the code **registers it fixable** -- its id is added to `FIXABLE_RULE_IDS`
   (bumps the array bound; wired to the store-backed append dispatch, per the
   `doc-drift` precedent); **and**
2. the user **opts in** -- its id is in the existing `AutoFixIds` set of
   `drag-lint-lint.json` (`TLintConfig.IsAutoFix`/`AutoFixIds`,
   `src/lint/DRagLint.Lint.Config.pas:74`).

"Registered-fixable" (the code *can* fix it) is deliberately separate from
"permitted" (the user asked). **Ships opt-in** -- these ids are NOT auto-added to
the default `AutoFixIds`, so no identifiers change unless the user configures it.
This matches how every other fixable rule already gates and avoids a second config
surface parallel to `AutoFixIds`.

### Safety guards (load-bearing for phase 2)
- Every synthesized rename runs through `TRenameRefactoring.ConflictReason` **first**;
  a non-empty reason -> **skip** that fix (do not apply), so we never introduce a
  collision or a reserved-word target.
- Re-casing is inherently collision-free in a case-insensitive language (the
  re-cased name denotes the same symbol), so phase-1 skips will be rare -- but the
  guard is kept as defense-in-depth and becomes essential in phase 2.
- **Dry-run is the default** (`--fix` shows, `--apply` writes), per the established
  convention; `.bak` backups via the engine's `Apply`.

### IDE "Fix it"
The IDE "Fix it" affordance keys off `IsFixableRule`/`FIXABLE_RULE_IDS`, so a
newly-registered naming rule lights up automatically. Whether that requires a BPL
rebuild (if any plugin-side list is duplicated) or is purely CLI-driven is
**confirmed during implementation**; the CLI path (`lint --fix`) needs no IDE work
regardless.

### Isolation / boundaries
- **Name synthesizer** -- pure, testable, no dependencies beyond `TNamingConfig`.
- **Rename dispatch** -- the store-backed append in `FinalizeAndOutput` that, for a
  fixable naming finding, synthesizes the name, runs `ConflictReason`, and (if
  clear) calls `Build`/`BuildLocal` and folds the `TRenameEdit`s into the applied
  set -- mirroring the `doc-drift` `TDocumenter.BuildFor` append.
- **Registration** -- `FIXABLE_RULE_IDS` + the guard test that the id list and the
  dispatch stay in lockstep.

### Testing (headless)
Per-rule fixtures (mis-cased method with N call sites; mis-cased local; mis-cased
const, unit-level and routine-local):
- `lint --fix --apply` produces the correctly-cased identifier at **every** site;
- respects the `AutoFixIds` opt-in -- **no** fix applied when the id is not listed;
- **skips** cleanly when `ConflictReason` is non-empty (synthesized-name collision),
  applying nothing for that finding;
- dry-run (`--fix` without `--apply`) previews without writing.
Plus the existing **list-agreement guard test** extended to the new ids. Battery
script `tests/autotest/run_naming_autofix.ps1`.

### Deliverable touchpoints
- New `src/refactor/DRagLint.Refactor.NamingFix.pas` (or a section in an existing
  refactor unit) -- the synthesizer + the rename dispatch helper.
- `src/cli/DRagLint.CLI.pas` -- `FIXABLE_RULE_IDS` additions + the store-backed
  append wiring in `FinalizeAndOutput`.
- `tests/autotest/run_naming_autofix.ps1` + fixtures; extend the guard test.
- CLI Win64 rebuild + deploy. **Possible** BPL rebuild for "Fix it" -- confirm.

### Risk
Medium (largest of the three). Engine proven and re-casing is the safe subset, but
the synthesizer + store-backed rename append are new integration surface. Kept
opt-in and dry-run-default to de-risk. Phase 2 (prefix-adding) inherits the exact
same plumbing -- so getting the dispatch + guard right here pays forward.

---

## Cross-cutting

- **Sequencing:** DbResolver -> reverse-calltree -> naming autofix. Independent
  code, so parallel is possible; the sequence lands smaller/lower-risk wins first.
- **Build/deploy:** Feature 2 + 3 = CLI Win64 rebuild (`third_party/dll-win64`).
  Feature 1 = **plugin BPL Win32 rebuild** (RAD Studio closed). Reindex the
  self-index if symbols the tool queries changed.
- **Release:** all three ride the next version bump (post-v0.95, untagged). Cut a
  release after the batch is green.
- **Docs:** update `docs/lint/drag-lint TODO plan.md` (mark 5.1 done, note naming
  autofix phase-1 shipped + phase-2 pending), the CLI/verb reference, and
  `BACKLOG.md`.

## Explicitly out of scope
- Architectural charts (Track 5.3) -- separate brainstorm.
- Naming autofix **phase 2** (prefix-adding) -- separate slice; this batch builds
  the plumbing it will reuse.
- IDE right-click for reverse call-tree -- deferred (menu overload).
- Any change to the graph **viewer** (separate repo; only the vendored exe is here).
