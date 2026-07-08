# Batch D -- engine bug fixes (A/B/C) + naming autofix phase 2 + IDE items (presets, right-click, dock focus) + cleanups

> **Date:** 2026-07-08
> **Status:** design approved; ready for implementation plan.
> **Scope:** eight tasks in ONE phased plan, sequenced so dependencies resolve and
> same-type work groups (headless engine/CLI first, IDE-only last -> grouped BPL
> builds). Rides the next version bump (post-v0.96, likely v0.97.0-alpha).
> **Predecessor:** Batch C (v0.96.0-alpha) shipped reverse-calltree + naming autofix
> phase 1 + the DbResolver fix. This batch clears the pre-existing findings Batch C
> filed (A/B/C) and builds the deferred follow-ons (naming phase 2, the IDE
> right-click, presets), plus the two small cleanups and a dock focus bug the user
> raised.

## Why these, together

All eight reuse existing surfaces -- no new engines. They cluster into two phases by
testability, with three real dependencies:

- **C before naming phase 2** -- phase 2 adds differing-length (prefix) edits; the
  applier must order same-line edits by column first (C) or a later same-line edit's
  offset is invalidated.
- **A before naming phase 2** -- promoting the impl-header rename into the engine lets
  phase 2 (and the standalone `rename` verb) get impl headers for free, and lets
  NamingFix drop its local workaround instead of extending it.
- **B is independent but riskiest** -- it touches the core parser ref-walk; kept as its
  own task with extra review, splittable without blocking the other seven.

## Global constraints (bind every task)

- **Encoding:** all `.pas`/`.dfm`/`.dpr`/`.dproj`/`.dpk` files strict 7-bit ASCII, no
  BOM, CRLF. DocInsight comments ASCII.
- **DocInsight (CDD):** every new/changed public type/function gets a `///`
  `<summary>` (+ `<param>`/`<returns>`/`<remarks>` as apt). Comment and test agree.
- **TDD** for the headless tasks (C/A/phase-2/B): failing test first, then green. IDE
  tasks are NOT headless-testable -- build gate + live smoke only; do NOT fabricate UI
  tests.
- **Build:** use the `delphi-build` skill recipe (rsvars + msbuild via
  `Start-Process cmd.exe -Wait` + log; `BUILD_EXITCODE=0`, no `[dcc] Error`). CLI =
  Win64 (`src/cli/drag-lint.dproj`); plugin = Win32 (`src/delphi-plugin/dclDragLintWizard.dproj`),
  RAD Studio (`bds.exe`) CLOSED. Deploy CLI Win64 -> `third_party/dll-win64`; BPL
  auto-deploys to `third_party/dll-win32`.
- **Commit cadence:** one source commit per task; the final BPL/DCP in its own
  `build(plugin):` commit.
- **Release:** rides the next version bump; user drives push/tag/release.

---

## PHASE 1 -- Engine / CLI (headless-testable)

### Task C -- TTextEditApplier same-line column tiebreak

**Problem.** `TTextEditApplier.Apply`'s comparer
(`src/refactor/DRagLint.Refactor.TextEdit.pas:106-109`) sorts edits by line only
(`EditTopLine(B) - EditTopLine(A)`). Two edits on the same line compare equal, so their
relative order is unstable; a left-to-right same-line pair with *differing lengths*
(e.g. prefix-adding) shifts the columns of the later edit and corrupts it. Today this
is latent (phase-1 re-casing is length-preserving), but it is load-bearing for naming
phase 2.

**Change.** Add a column-DESC tiebreak, matching the proven
`TRenameRefactoring.CompareEdits` ordering:
```pascal
Result := EditTopLine(B) - EditTopLine(A);
if Result = 0 then Result := B.Col - A.Col;
```
Line-based edits (`tekDeleteLines`/`tekInsertLines`) carry `Col = 0`, so the tiebreak is
a no-op for them -- safe.

**Test (headless).** A fixture applying two differing-length `tekReplaceInLine` edits on
one line (a real prefix-add shape, e.g. two params on one line both gaining a prefix)
-> assert both applied correctly, no corruption. This is the RED that phase 2 relies on.
A dedicated `run_textedit_sameline.ps1`, or extend the existing autofix battery's
same-line stress case to a differing-length pair.

**Risk.** Very low. 2-line change; matches an existing proven comparer.

### Task A -- promote impl-header rename into TRenameRefactoring.Build

**Problem.** `TRenameRefactoring.Build`
(`src/refactor/DRagLint.Refactor.Rename.pas:86-134`) emits the declaration-site edit
(`Sym.StartLine`/`StartCol`) plus one edit per `FindCallersByName` row, but NEVER the
method's IMPLEMENTATION header (`procedure TFoo.Bar;` in the implementation section).
That occurrence is neither the decl symbol nor a `refs` row -- the parser treats a
`defProc` as a definition, not a usage. So the standalone `rename` verb leaves impl
headers stale. Batch C worked around this LOCALLY in
`NamingFix.BuildImplHeaderEdit` (`DRagLint.Refactor.NamingFix.pas:153-195`).

**Change.** Promote the workaround into `Build`:
- The impl location is already on the symbol: `TSymbol.ImplStartLine`/`ImplEndLine`
  (`src/core/DRagLint.Core.Model.pas:75-76`), populated by the parser and read back by
  the store. `Build` already has `Sym` + `AStore.GetFilePath(Sym.FileId)`.
- In `Build`, when `Sym.ImplStartLine > 0` and `<> Sym.StartLine`, read that source
  line, find the short name preceded by `.` (the dotted `Type.Name` member shape), and
  emit an additional `TRenameEdit{ Line := ImplStartLine; Col := <dot+1> }`. Build's
  `Apply` (`Rename.pas:201-217`) already does its own forward-scan token match, so a
  `TRenameEdit` (no `EndCol`) works through the existing applier -- no `TTextEdit`
  needed.
- Guard exactly like the workaround: skip when `ImplStartLine <= 0` or
  `= StartLine` (abstract/interface/inline methods have no separate impl header).
- **Then simplify NamingFix:** remove `BuildImplHeaderEdit` and its call
  (`NamingFix.pas:303-307`) -- the promoted `Build` now covers it. Net code reduction.

**Test (headless).** Rename a method that has a call site in ANOTHER unit (via the
standalone `rename` verb) -> assert the interface decl, the call site, AND the impl
header all update. Plus: NamingFix's phase-1 battery (`run_naming_autofix.ps1`) must
still pass after it drops the workaround (the impl-header re-casing still happens, now
via `Build`).

**Risk.** Low-medium. Self-contained logic move; the phase-1 battery is the regression
guard that the promotion is behavior-equivalent for the naming path.

### Task Phase 2 -- naming autofix prefix-adding

**Depends on:** C (differing-length same-line edits) + A (impl headers via `Build`).

**Goal.** Extend naming autofix from re-casing (phase 1) to PREFIX-ADDING: make
`field-name-prefix`, `param-name-prefix`, and `type-name-prefix` findings fixable
(`client -> FClient`, param `x -> pX`, `myclass -> TMyClass`). Opt-in via the existing
`AutoFixIds`, off by default, dry-run default -- exactly like phase 1.

**What exists (reused).** `BuildNamingFixEdits`
(`DRagLint.Refactor.NamingFix.pas:197-318`) already dispatches per rule-id and drives
the rename engine: globals via `Build` + `ResolveSymbolAt` + `ConflictReason`; locals
via `BuildLocal`. `BuildLocal` already syncs BOTH the impl `defProc` header (via `Walk`)
AND the interface/forward `declProc` headers (via `SyncForwardHeaders`,
`Rename.pas:392-456`). The prefix rules fire in
`src/diagnostics/DRagLint.Diagnostics.NamingChecks.pas` (`type-name-prefix` :531-559,
`field-name-prefix` :640, `param-name-prefix` :699-702/:772-775); the finding carries
NO structured prefix -- the fix re-reads the prefix from `TNamingConfig` (as phase-1
already re-reads the case).

**Changes.**
1. **New pure helper** `SynthesizePrefixedName(const AOldName, APrefix: string): string`
   = `APrefix + Cap(AOldName)` (e.g. `client -> FClient`; idempotent if already
   prefixed -- if `AOldName` already `StartsWithPrefix(APrefix)`, return it unchanged).
   Pure, unit-testable, sits beside `SynthesizeCasedName`.
2. **Dispatch:** add the 3 prefix rule-ids to `BuildNamingFixEdits`' filter. Pick the
   prefix per rule from `TNamingConfig`: `type-name-prefix` ->
   Class/Exception/Interface/Pointer prefix by the symbol's kind; `field-name-prefix`
   -> `FieldPrefix`; `param-name-prefix` -> `ParamPrefix`. Compute
   `NewName := SynthesizePrefixedName(OldName, prefix)`; skip if unchanged.
3. **Route:** `param-name-prefix` -> `BuildLocal` (routine-local; already syncs both
   headers). `field-name-prefix` / `type-name-prefix` -> global `Build` + the existing
   `ConflictReason` guard.
4. **THE NEW SAFETY WORK:** prefix-adding CHANGES the identifier (unlike re-casing), so
   collisions are real (e.g. `pX` already a local/param in that routine). `BuildLocal`
   currently has NO collision check. Add a collision guard to the `BuildLocal` path: if
   the target name already exists as a sibling in the routine's scope (a local/param of
   the same routine), SKIP the fix (do not apply) -- mirroring how the global `Build`
   path skips on non-empty `ConflictReason`. The guard is the load-bearing correctness
   piece of this task.

**Test (headless).** Per-rule fixtures: a field/param/type needing a prefix -> assert
the identifier gains the prefix at the decl AND every reference AND (for params/methods)
both headers. Plus: opt-in gate (no fix when the id isn't in `AutoFixIds`),
**collision-skip** (a param whose prefixed name already exists in scope -> no edit, exit
0), a differing-length same-line case (two params on one line both prefixed -> both
correct, exercising Task C), dry-run, determinism. `run_naming_prefix_autofix.ps1`.

**Risk.** Medium. The rename plumbing is proven; the new surfaces are the prefix
synthesizer and the `BuildLocal` collision guard. Opt-in + dry-run-default de-risk.

### Task B -- index bare-RHS-identifier reads as references

**Problem.** Under `--deep`, the parser ref-walk
(`src/parser/DRagLint.Parser.Delphi13.pas:1343-1385`, gated on
`AState.EmitUsageRefs`) captures identifier reads ONLY inside these shapes: `exprDot`
lhs base, `assignment` lhs (a `write`), `exprArgs` children, and `attribute`. A lone
identifier that is the ENTIRE right-hand side of an assignment (`Result := maxItems;`)
hits no case and falls through the default recurse -- emitting no `refs` row. So
const/var rename-at-use-site (and any ref consumer) misses that shape.

**Change.** Add a bare-`identifier` case to the usage-ref block that emits a `read`
ref, **carefully gated to expression-position identifiers only**:
- The dot-lhs / args / assignment-lhs handlers already `Exit` before generic recursion,
  so those identifiers won't double-emit.
- The gate MUST exclude declaration-name identifiers (a `declVar`/`declProc`/`declType`
  name node) and type-name identifiers (a `typeref`), or the index balloons with
  false "reads" of every declaration. The safe scope is: an `identifier` node reached
  as an expression operand -- e.g. the RHS of an `assignment`, an argument that is a
  bare identifier, a statement-expression -- NOT a declaration/type context.
- Emit `EmitRef(..., 'read')` for that identifier only.

**Test (headless).** A fixture with `x := maxConst;` and `Result := someVar;` -> after
`index --deep`, assert a `refs` row exists for `maxConst`/`someVar` at the read site
(e.g. via `find-callers`/`impact`/a refs query, or by driving `const-casing`/naming
rename-at-use and asserting the use site is now rewritten). CRUCIAL negative assertion:
assert declaration-name and type-name identifiers did NOT gain spurious `read` refs
(guard against over-capture). Compare a small fixture's ref count before/after to bound
the blast radius.

**Risk.** MEDIUM-HIGH (the batch's risk item). Touches core reference extraction ->
affects index size and every ref/callgraph/impact consumer. Gets extra review scrutiny;
splittable out of the batch if it proves thornier than scoped. It does NOT block the
other seven tasks.

---

## PHASE 2 -- IDE-only (BPL build + live smoke; NOT headless-testable)

All five land before a SINGLE final Win32 BPL build (RAD Studio closed). No fabricated
UI tests.

### Task Cleanup (a) -- delete the dead singular OptionsFrame.pas

**Confirmed dead.** `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas` (SINGULAR,
class `TDragLintOptionsFrame`) is referenced nowhere live -- its claimed
`ShowSettingsDialog` caller no longer exists; the live options path is the PLURAL
`DragLint.Plugin.OptionsFrames.pas` (4 frames). Its layout helpers
(`NewGroup/NewLabel/NewEdit/NewCheck`) are already duplicated as `DLNew*` in the plural
unit -- nothing to fold.

**Change.** Remove the unit from `dclDragLintWizard.dpk` `contains` (:55) and
`dclDragLintWizard.dproj` `<DCCReference>` (:93); delete the file. (The test fixture
`tests/fixtures/T52_options.dpr` references the class -- verify whether that fixture is
live; if it is dead too, note it; do NOT break a live test.)

**Gate.** BPL builds clean without the unit.

### Task Cleanup (b) -- manifest write ANSI -> UTF8

**Change.** `DragLint.Plugin.OptionsFrames.pas:750` (`TDLLinterOptionsFrame.WriteMaxReturnCases`)
writes with `TEncoding.ANSI`; the canonical `TManifestIO.Save`
(`src/index/DRagLint.Index.Manifest.pas`, ends ~:738) writes `TEncoding.UTF8`. Change
the frame's write to `TEncoding.UTF8` (byte-identical for ASCII today; correct and
consistent going forward). The read at :722 uses default encoding and is UTF8-compatible.

**Gate.** BPL build; live smoke -- edit max_return_cases, confirm the written JSON is
still read back correctly.

### Task Presets combo (naming convention presets)

**Goal.** A 2-3 preset selector for naming conventions, so users pick a bundle instead
of hand-editing each `naming.*` param.

**Placement (key finding).** Naming is ALREADY IDE-editable on the dock's Lint Options
tab -- `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` binds every `naming.*`
param to inline editors and writes the project `drag-lint-lint.json`. So the preset
selector is a COMBO at the TOP of THIS existing frame, NOT a new Tools->Options
sub-page.

**Change.** Add a "Naming preset" combobox to `LintOptionsFrame` with:
- **Embarcadero (`A...`)** -- the Embarcadero/ORM3 house convention (param prefix `A`,
  the RAD Studio standard).
- **House (`p...`)** -- the CLAUDE.md convention (`pMyParam`, `FMyField`, `TMyClass`).
- **Custom** -- leaves the current values as-is (user-edited).

Presets are a small constant table in Pascal (each = a bundle of prefixes + cases).
Selecting a preset BULK-SETS the naming param editors, which then persist through the
existing JSON writer. Selecting "Custom" (or manually editing any field) leaves values
untouched. On load, if the current values match a known preset's bundle, show that
preset; else show "Custom".

**Gate.** BPL build + live smoke: pick a preset -> the naming fields update -> saved
`drag-lint-lint.json` reflects the bundle; editing a field afterward flips the combo to
Custom.

### Task reverse-calltree IDE right-click (text only)

**Goal.** A right-click / menu action on a symbol that shows its reverse call tree as
TEXT in an editor buffer. (Graphical in-dock rendering is DEFERRED -- see the TODO
below; the dock viewer reads the DB directly and lives in a separate repo, so it cannot
render our tree without out-of-repo work.)

**Change.** Mirror the proven `InvokeImpact` pattern
(`src/delphi-plugin/DragLint.Plugin.Editor.pas:3072-3081`): a new
`InvokeReverseCallTree` added under the "Inspect Symbol" submenu (:3837-3842). It calls
`DLAskQName` (pre-fills from the identifier under the cursor, :2922-2933), resolves the
active DB (`GetActiveProjectDb`, :1370), and runs
`DLRunReport(Format('reverse-calltree --qname "%s" --db "%s"', [Q, Db]),
'drag-lint-reverse-calltree.txt')` (:2878-2906) -- the off-thread runner that opens the
output in the editor. `Editor.pas` only; the verb already exists (`DoReverseCallTree`,
`CLI.pas:10044`).

**Gate.** BPL build + live smoke: right-click a symbol -> the text tree opens in an
editor buffer.

### Task Dock focus-stealing fix

**Problem (user-reported).** The drag-lint dock self-selects to the front whenever the
user switches to another IDE tab (Project Manager, etc.). Desired: show on top ONCE at
IDE startup, then stay where it is -- it updates in the background regardless; the user
clicks the tab when they want it.

**Change (systematic-debugging first).** LOCATE the focus-assertion before changing it:
a `Show`/`Activate`/`ForceShow`/`Select`/`BringToFront` call in the dock's
show/update/notify path (`src/delphi-plugin/DragLint.Plugin.DockForm.pas` and/or
`GraphWindow.pas`) that fires on updates rather than only first display. Make the dock:
(a) show-on-top once at startup (keep existing first-show behavior), and (b) never
force-select itself again on a background update. Background data updates must continue
regardless of which tab is focused.

**Gate.** BPL build + live smoke: switch to Project Manager -> the dock stays put; the
dock still updates in the background; IDE startup still surfaces it on top once.

---

## Cross-cutting

- **Two BPL rebuilds minimized:** all five IDE tasks land before ONE final Win32 BPL
  build (RAD Studio closed). One CLI Win64 rebuild covers the phase-1 tasks; if Task B
  changes what later queries hit, reindex the self-index incrementally.
- **Sequencing:** C -> A -> phase 2 -> B (phase 1), then cleanups a/b -> presets ->
  right-click -> dock focus (phase 2), then final builds + docs.
- **Docs:** update `docs/lint/BACKLOG.md` (mark A/B/C fixed, naming phase 2 shipped,
  right-click shipped text-only, dock focus fixed, cleanups done); update the roadmap
  (`drag-lint TODO plan.md`) Track 1.1 (naming phase 2 done) and any verb/IDE docs.
- **Release:** rides the next version bump (likely v0.97.0-alpha); ask at release time
  whether to cut it. User drives push/tag/release.

## Filed TODO (not built this batch)

- **In-Delphi tree renderer / Graphviz-subset as a second dock tab.** A native VCL
  renderer that consumes `TRCallTree` (from `BuildReverseCallTree`) directly -- no
  `.dot` round-trip and no dependence on the DB-wired `drag_lint_graph` viewer (which
  reads the SQLite index directly and lives in a separate repo). This is how the
  reverse call tree (and other trees) could render graphically IN the IDE. NOTE: the
  claimed Delphi compiler `--graphviz` switch that emits a `.gv` of the uses graph
  appears NOT to exist (no such documented `dcc32`/`dcc64` option); treat as false
  unless the live `dcc64 --help` on the target RAD Studio 37 shows it. Non-urgent.

## Explicitly out of scope

- Graphical/in-dock rendering of the reverse call tree (needs the separate viewer repo
  or the filed in-Delphi renderer TODO).
- Track 5.3 architectural charts.
- Any change to the `drag_lint_graph` viewer (separate repo; only the vendored exe is
  here).
