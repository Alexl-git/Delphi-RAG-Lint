# C8CHAIN -- ancestor-first conversion chains in the ConvRulesEditor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Convert tab builds an inheritance dependency graph over the listed units, walks every chain to its root, offers to insert every ancestor that still holds a rule book's From type (root first, intermediate classes included), and never runs a descendant before its ancestor: the E7 order warning becomes a blocking question whose Yes reorders the list.

**Architecture:** All decisions stay in the PURE unit `ConvRules.Inheritance` (a new per-unit `Ancestors` graph beside the existing per-instance verdicts; `AncestorChain` becomes the union of both; a stable ancestor-first topological order; the blocking E7 texts). `ConvRules.ConvertTab` only wires the Yes answer to `SetSources` and the job. The 1.42 engine's own in-batch ancestor-first order (`OrderUnitsAncestorFirst`, lane/142-conv-apply 460f9a16) is kept as a second safety net: the editor's order is a superset of it and the engine's sort is stable, so an editor-ordered list passes through unchanged. No capability gate: the engine shipped no capability for the order, the version string is not a drift signal (editor CLAUDE.md), and a 1.41 pin needs the editor's order anyway.

**Tech Stack:** Delphi 13 (dcc64, Win64), the editor's console model tests (`tests\ConvRulesModelTests.dpr` + `tests\inc\*.inc`), the GUI driver `tests\gui\drive-inherited-offer.ps1` (pwsh), drag-lint pin `C:\Projects\Delphi-RAG-lint\third_party\engine-pinned\1.40.0-alpha-20261103-145611\drag-lint.exe` (below: `$DL`).

**Spec:** `C:\Projects\Delphi-RAG-lint\docs\CONVERTER-BACKLOG.md` lines 38-52 (the "D5 inherited .dfm" and "C8CHAIN -- OWNER RULING Q5 2026-10-28" bullets). Engine side read for this plan: `git -C C:\TEMP\claude\lanes\142\conv-apply\wt show 460f9a16` (Apply.pas: `OrderUnitsAncestorFirst` / `OrderUnitsByDependencies`; CLI: units[] stays in --unit order, text prints one order note; no new `info` capability).

## Paths and commands used by every task

* Worktree `WT` = `C:\Projects\Delphi-RAG-lint-wt\conv-c8chain` (branch `conv/c8chain`, base main c2c4b750). Never edit `C:\Projects\Delphi-RAG-lint`.
* Editor dir `ED` = `WT\src\tools\convrules-editor`. Scratch `SC` = `C:\TEMP\claude\lanes\convc8\c8chain\scratch`.
* Worktree DB `WTDB` = `ED\_D-RAG\ConvRulesEditor.sqlite` (created by Task 1; never pass the main tree's DB).
* Build tests (PowerShell, delphi-build recipe): `Start-Process -Wait -NoNewWindow -FilePath cmd.exe -ArgumentList '/c', ('"' + 'WT\build\_build_convrules_tests_local.bat' + '" > "SC\tests-build.log" 2>&1')` then `Select-String -Path SC\tests-build.log -Pattern 'BUILD_EXITCODE|Error|Fatal'`. Pass = `BUILD_EXITCODE=0`, no `Error`.
* Run tests (no engine beside the runner; live tests SKIP): `& ED\tests\ConvRulesModelTests.exe > SC\tests.log; Select-String -Path SC\tests.log -Pattern '^FAIL|model-tests:'`. Baseline on main: 3117 pass / 0 fail / 20 skip (editor CLAUDE.md).
* Build editor: the same `Start-Process` with `WT\build\_build_convrules_editor_local.bat` (NO `stage` argument) -> `ED\ConvRulesEditor.exe`.
* Lint (after every edit, from the editor CLAUDE.md "Lint-clean by default"):
  ```
  $DL index --project ED\ConvRulesEditor.dpr --db WTDB
  $DL lint ED\ConvRules.Inheritance.pas --db WTDB --enable magic-literal,multiple-statements-per-line,commented-out-code
  $DL lint-all --db WTDB --enable magic-literal,multiple-statements-per-line,commented-out-code
  ```
  Report the counts; every new finding is fixed or carries a `dl:ok <rule>@<hash> -- REVIEWED 2026-11-xx <why>` marker. Never `--fix --apply` here.
* Encoding: `.pas` / `.inc` / `.ps1` are 7-bit ASCII, CRLF. After Write/Edit run `[IO.File]::WriteAllText($p, ([IO.File]::ReadAllText($p) -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new())` on each touched file, then `WT\tests\autotest\run_encoding_guard.ps1`.
* Commit with a pathspec only: `git -C WT commit -m "<msg>" -- <paths>`.
* Engine need: Tasks 1-7 are PURE or build-only (no engine process). Task 8 needs the live pin (staged copy). Task 9 needs `featuregen.exe` only.

## Global Constraints

* Owner ruling Q5 (spec): "No inherited unit converts before its ancestor is converted"; chains walked "to the very original"; per ancestor in the batch -> order it first; not in the batch -> "already converted?" = search the ancestor for the rule books' From types; still there -> offer and insert root first; none left -> converted; intermediate classes that re-open no instance are included; E7 stops being a warning with "anyway".
* Engine 1.42 already skips a child whose ancestor is unconverted (`ancestor_state` "unconverted") and orders an in-batch run ancestor-first; the editor is the only place that can ADD an ancestor to the run or stop a run.
* The editor always runs `--apply` (`ConvRules.Engine.pas:1738`): the engine's dry-run note is not the editor's concern.
* `ConvRules.Inheritance` stays PURE: no UI, no engine, no file I/O beyond the injected `TDfmTextReader` / `TClassLookup`.
* Spec E5 wording for verdict notes stays verbatim (`inherits N <types> instance(s) from <Unit> -- convert it first (recommended)`).
* Paths compare as `PathIndex` does (ExpandFileName'd, case-insensitive). `MAX_CHAIN_DEPTH` and the `REASON_*` constants are reused, not duplicated.
* `IfThen` evaluates both arguments; `TJSONNumber` is not a `TJSONString` (editor CLAUDE.md traps) -- not touched here but still in force.

## Review Focus

1. A descendant listed with NO inherited From instance whose ancestor still holds a From type: the strict ruling orders the ancestor first and offers it on add (Task 4 test `ag.analyze.no.instance.strict`). Owner question Q-A below.
2. A chain that leaves the project index (library form, other project): no block, no offer, the existing OutsideNote only (Task 3 `ag.walk.outside.stops`, Task 4 `ag.analyze.outside.silent`).
3. An ancestor whose .dfm is binary or unreadable: the unit is Known = False and the existing gate asks ONCE; never a silent run (Task 3 `ag.walk.binary.error`, Task 4 `ag.analyze.error.unknown`).
4. Two descendants of one ancestor in one add: the ancestor is inserted once, root first, and the second offer has nothing left to ask (Task 5 `ag.chain.dedupe`, Task 7 manual check, Task 8 D3 check unchanged).
5. A dependency cycle in the index (impossible for classes, conceivable through frames): the order falls back to the caller's order and nothing is dropped (Task 6 `ag.order.cycle.caller.order`).

---

## Task 1: Baseline -- worktree index, builds, counts (pure)

**Files:** none edited. Creates `WTDB`, `SC\*.log`.

- [ ] **Step 1: Index the worktree** -- `$DL index --project ED\ConvRulesEditor.dpr --db WTDB`. Expected: summary line with `files=` > 50, `files` not > `walked`.
- [ ] **Step 2: Build and run the model tests** (commands above). Expected: `BUILD_EXITCODE=0`; `model-tests: 3117 pass / 0 fail / 20 skip` (or the count main carries; record it in `SC\baseline.txt`).
- [ ] **Step 3: Build the editor** (no `stage`). Expected `BUILD_EXITCODE=0`, `ED\ConvRulesEditor.exe` newer than the sources.
- [ ] **Step 4: Lint baseline** -- `lint-all` command above; record the total in `SC\baseline.txt` (this is the number later tasks must not exceed without a marker).

No commit.

---

## Task 2: `TAncestorUnit`, `Ancestors`, `FromTypesIn` (pure)

**Files:**
- Modify: `ED\ConvRules.Inheritance.pas` (types after `TChainUnit` ~:191; `TUnitInheritance` :222-232; a new function after `UnitNameOf` :286)
- Create: `ED\tests\inc\AncestorGraphTests.inc`
- Modify: `ED\tests\ConvRulesModelTests.dpr` (`{$I inc\AncestorGraphTests.inc}` after line 16304; call `TestAncestorFromTypes;` after `TestRuleChainsUi;`)

**Interfaces (produces):**
```pascal
/// <summary>One ancestor unit of a listed unit's dependency graph (C8CHAIN, owner ruling Q5).</summary>
TAncestorUnit = record
  /// <summary>The ancestor's .pas.</summary>
  PasPath: string;
  /// <summary>As TChainUnit.Depth: 1 = the form's parent, larger = further up; frame
  /// chains continue the count after the form chain.</summary>
  Depth  : Integer;
  /// <summary>The checked books' From types still in it (its .dfm objects, any opener,
  /// and its From-typed fields), bare names, distinct, first seen. [] = treated as converted.</summary>
  Types  : TArray<string>;
end;
```
`TUnitInheritance` gains `/// <summary>Every indexed ancestor unit up to the root (form chain, then each inline frame's chain), root first; [] when not Known or the unit has no indexed class.</summary> Ancestors: TArray<TAncestorUnit>;`

```pascal
/// <summary>PURE: the checked From types a unit still holds (the "already converted?" test of
/// owner ruling Q5).</summary>
/// <param name="ADfmText">The unit's .dfm as text; '' for no .dfm.</param>
/// <param name="AFields">Its class's From-typed fields (TClassInfo.Fields).</param>
/// <param name="APairs">The checked books' pairs.</param>
/// <returns>Bare names of every ListDfmInstances type (object, inherited and inline alike)
/// and every field type that IsFromType; distinct, first seen (.dfm first, then fields).
/// [] for no pairs.</returns>
function FromTypesIn(const ADfmText: string; const AFields: TArray<TFieldDecl>; const APairs: TArray<TTypePair>): TArray<string>;
```

- [ ] **Step 1: Write the DocInsight comments and the failing test.** In the new `.inc`:
```pascal
{ C8CHAIN: ancestor dependency graph -- plan docs\superpowers\plans\2026-11-03-converter-c8chain.md }
const
  AG_BASE_PAS = 'fx\Base.pas';  AG_MID_PAS = 'fx\Mid.pas';  AG_LEAF_PAS = 'fx\Leaf.pas';  AG_FRM_PAS = 'fx\Frm.pas';
  AG_CRLF = #13#10;
  AG_BASE_DFM = 'object BaseForm: TBase' + AG_CRLF + '  object tblX: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';
  AG_MID_DFM  = 'inherited MidForm: TMid' + AG_CRLF + 'end';
  AG_MID_OWN_DFM = 'inherited MidForm: TMid' + AG_CRLF + '  object lblOwn: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';

function AgPairs: TArray<TTypePair>;  // TTable -> TFDTable, TQuery -> TFDQuery (fill FromType/ToType)
function AgField(const AName, AType: string): TFieldDecl;

procedure TestAncestorFromTypes;
begin
  Check('ag.from.object', string.Join(',', FromTypesIn(AG_BASE_DFM, [], AgPairs)) = 'TTable');
  Check('ag.from.inherited.and.inline', string.Join(',', FromTypesIn('object F: TX' + AG_CRLF + '  inherited a: TTable' + AG_CRLF + '  end' + AG_CRLF
    + '  inline f: TQuery' + AG_CRLF + '  end' + AG_CRLF + 'end', [], AgPairs)) = 'TTable,TQuery');
  Check('ag.from.fields', string.Join(',', FromTypesIn('', [AgField('qry', 'Bde.DBTables.TQuery'), AgField('lbl', 'TLabel')], AgPairs)) = 'TQuery');
  Check('ag.from.distinct', string.Join(',', FromTypesIn(AG_BASE_DFM, [AgField('t2', 'TTable')], AgPairs)) = 'TTable');
  Check('ag.from.none', Length(FromTypesIn(AG_MID_DFM, [], AgPairs)) = 0);
  Check('ag.from.no.pairs', Length(FromTypesIn(AG_BASE_DFM, [], [])) = 0);
end;
```
- [ ] **Step 2: Build the tests; expect a compile error** (`FromTypesIn` undeclared) -- that is the RED.
- [ ] **Step 3: Add the types, the field and `FromTypesIn`** in `ConvRules.Inheritance.pas` (uses `ListDfmInstances`, `BareType`, `IsFromType`; `TDfmInstance.TypeName` for every row with Depth > 0 -- the root header's own class is not an instance).
- [ ] **Step 4: Build + run.** Expected: baseline + 6 pass, 0 fail.
- [ ] **Step 5: Lint** (commands above); counts unchanged or every new finding resolved.
- [ ] **Step 6: Commit** -- `git -C WT commit -m "feat(converter): C8CHAIN T2 -- TAncestorUnit, Ancestors, FromTypesIn" -- src/tools/convrules-editor/ConvRules.Inheritance.pas src/tools/convrules-editor/tests/inc/AncestorGraphTests.inc src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

---

## Task 3: `AncestorGraphOf` -- the walk to the root (pure)

**Files:**
- Modify: `ED\ConvRules.Inheritance.pas` (declaration after `ResolveInstance` ~:305; implementation beside `WalkChain` ~:1057)
- Modify: `ED\tests\inc\AncestorGraphTests.inc` (+ `TestAncestorGraphWalk`, registered in the .dpr)

**Interfaces (produces):**
```pascal
/// <summary>PURE: a listed unit's ancestor dependency graph (owner ruling Q5): every indexed
/// class above AOwn up to the root, then every inline frame class's chain (the frame unit
/// itself first), each with the From types it still holds.</summary>
/// <param name="AOwn">The unit's own class (Found); its ParentClass starts the form chain.</param>
/// <param name="AFrameClasses">The classes of the unit's .dfm `inline` blocks, distinct.</param>
/// <param name="ALookup">The project index.</param>
/// <param name="AReader">The file system; drMissing = no .dfm (no From type from a .dfm).</param>
/// <param name="APairs">The checked books' pairs.</param>
/// <param name="AError">'' or why the walk could not decide (REASON_FAILED / REASON_CYCLE /
/// REASON_DEPTH / REASON_DFM text as the instance walk words them); the result is then [].</param>
/// <returns>Root first (Depth descending, stable; a unit met on several chains keeps its largest
/// Depth and the union of its Types). A class not in the index ends its chain without error
/// (outside). AOwn.PasPath itself is never listed.</returns>
function AncestorGraphOf(const AOwn: TClassInfo; const AFrameClasses: TArray<string>; const ALookup: TClassLookup;
  const AReader: TDfmTextReader; const APairs: TArray<TTypePair>; out AError: string): TArray<TAncestorUnit>;
```
Algorithm (not determined by the signature): one `Depth` counter across chains. `WalkClasses(AStart)`: `Seen := []`; loop while `Cls <> ''`: cycle (`MatchText(Cls, Seen)`) -> `AError := Format(REASON_CYCLE, [Cls])`, exit; `Length(Seen) >= MAX_CHAIN_DEPTH` -> `REASON_DEPTH`; `Info := ALookup(Cls)`; `Failed` -> `WithCause(Format(REASON_FAILED, [Cls]), Info.Error)`; not `Found` -> break; `Inc(Depth)`; read `ChangeFileExt(Info.PasPath, DFM_EXT)`: `drUnreadable` or text starting `BINARY_DFM_SIGNATURE` -> `Format(REASON_DFM, [Cls, dfm])`; `drMissing` -> `''`; merge `TAncestorUnit(Info.PasPath, Depth, FromTypesIn(text, Info.Fields, APairs))`; `Cls := Info.ParentClass`. Form chain from `AOwn.ParentClass`; then each frame class from ITSELF. Sort with the stable insertion sort `AncestorChain` already uses (extract it into a local helper both share). Any error -> `Result := nil`.

- [ ] **Step 1: Failing test** (`FakeLookup` rows `'Class|Path|Parent|fields'` and `FakeReader` from the .dpr :10543/:10598):
```pascal
procedure TestAncestorGraphWalk;
var
  G: TArray<TAncestorUnit>;  Err: string;
  function Own: TClassInfo;  // Found, PasPath AG_LEAF_PAS, ParentClass 'TMid'
  function Paths(const A: TArray<TAncestorUnit>): string;  // PasPaths joined ','
  function Rows: TArray<string>;  // ['TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TForm']  (TForm absent = outside)
  function Reader: TDfmTextReader; // AG_MID_PAS/.dfm -> AG_MID_DFM, AG_BASE_PAS/.dfm -> AG_BASE_DFM
begin
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), Reader, AgPairs, Err);
  Check('ag.walk.root.first', (Err = '') and (Paths(G) = AG_BASE_PAS + ',' + AG_MID_PAS), Err + ' ' + Paths(G));
  Check('ag.walk.depth', (G[0].Depth = 2) and (G[1].Depth = 1));
  Check('ag.walk.types', (string.Join(',', G[0].Types) = 'TTable') and (Length(G[1].Types) = 0));
  Check('ag.walk.outside.stops', True); // covered by root.first: TForm is not a row and raises no error
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase|qry:TQuery', 'TBase|' + AG_BASE_PAS + '|TForm'], nil), Reader, AgPairs, Err);
  Check('ag.walk.fields.count', string.Join(',', G[1].Types) = 'TQuery');
  G:= AncestorGraphOf(Own, ['TFrm'], FakeLookup(Rows + ['TFrm|' + AG_FRM_PAS + '|TFrame'], nil),
    FakeReader([ChangeFileExt(AG_MID_PAS, '.dfm'), ChangeFileExt(AG_BASE_PAS, '.dfm'), ChangeFileExt(AG_FRM_PAS, '.dfm')], [AG_MID_DFM, AG_BASE_DFM, AG_BASE_DFM]), AgPairs, Err);
  Check('ag.walk.frame.after.forms', (Paths(G) = AG_FRM_PAS + ',' + AG_BASE_PAS + ',' + AG_MID_PAS) and (G[0].Depth = 3), Paths(G));
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TMid'], nil), Reader, AgPairs, Err);
  Check('ag.walk.cycle.error', (Length(G) = 0) and (Pos('TMid', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(['TMid|' + AG_MID_PAS + '|TBase', 'TBase|!|boom'], nil), Reader, AgPairs, Err);
  Check('ag.walk.failed.error', (Length(G) = 0) and (Pos('boom', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([ChangeFileExt(AG_BASE_PAS, '.dfm')], [FAKE_UNREADABLE_DFM]), AgPairs, Err);
  Check('ag.walk.unreadable.error', (Length(G) = 0) and (Pos('Base.dfm', Err) > 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([ChangeFileExt(AG_BASE_PAS, '.dfm')], [BINARY_DFM_SIGNATURE + 'xx']), AgPairs, Err);
  Check('ag.walk.binary.error', (Length(G) = 0) and (Err <> ''), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), FakeReader([], []), AgPairs, Err);
  Check('ag.walk.missing.dfm.ok', (Err = '') and (Length(G) = 2) and (Length(G[0].Types) = 0), Err);
  G:= AncestorGraphOf(Own, [], FakeLookup(Rows, nil), Reader, [], Err);
  Check('ag.walk.no.pairs', (Err = '') and (Length(G) = 2) and (Length(G[0].Types) = 0));
end;
```
(Drop `ag.walk.outside.stops` if the reviewer objects to a vacuous line; the behaviour is asserted by `ag.walk.root.first`.)
- [ ] **Step 2: Build -> compile error (RED).**
- [ ] **Step 3: Implement `AncestorGraphOf`** per the algorithm. Sorting: a private `procedure SortDeepestFirst(var AUnits: TArray<TAncestorUnit>)` (stable insertion sort on Depth descending, the same shape as the one inside `AncestorChain`, which sorts `TChainUnit` -- two tiny sorts, no generic helper).
- [ ] **Step 4: Build + run.** Expected: all `ag.walk.*` pass, 0 fail overall.
- [ ] **Step 5: Lint** (both scopes).
- [ ] **Step 6: Commit** -- `feat(converter): C8CHAIN T3 -- AncestorGraphOf walks every chain to the root`.

---

## Task 4: `AnalyzeUnit` fills `Ancestors` (pure)

**Files:**
- Modify: `ED\ConvRules.Inheritance.pas` (`AnalyzeWith` :1257-1308; the `AnalyzeUnit` DocInsight :307-334 gains a sentence on `Ancestors`)
- Modify: `ED\tests\inc\AncestorGraphTests.inc` (+ `TestAnalyzeAncestors`)

**Interfaces:** consumes `AncestorGraphOf` (Task 3). Produces the filled `TUnitInheritance.Ancestors` that Tasks 5-7 read.

New `AnalyzeWith` order (replaces lines 1270-1292):
1. Pairs empty or no readable text .dfm or no root class -> `Exit` (unchanged, E3).
2. `LWanted` as today.
3. `LOwn := ALookup(RootClass)`. `Failed` -> `Error`, exit (now for every unit, not only one with wanted instances). Not `Found` -> `Known := (Length(LWanted) = 0) and not Assigned(ACodeUses)` and exit (today's two outcomes, unchanged).
4. `Ancestors := AncestorGraphOf(LOwn, <TypeName of each LScan.Instances with Opener = doInline, distinct>, ALookup, AReader, APairs, LErr)`; `LErr <> ''` -> `Error := LErr`, `Known := False`, exit.
5. `(Length(LWanted) = 0) and not Assigned(ACodeUses)` -> `Known := True`, exit (E3, Ancestors kept).
6. The existing verdict loop and `AddCodeUses`, unchanged. A `Known = False` exit clears `Verdicts` AND `Ancestors`.

- [ ] **Step 1: Failing test:**
```pascal
procedure TestAnalyzeAncestors;
const
  LEAF_INH_DFM = 'inherited LeafForm: TLeaf' + AG_CRLF + '  inherited tblX: TTable' + AG_CRLF + '  end' + AG_CRLF + 'end';
  LEAF_OWN_DFM = 'inherited LeafForm: TLeaf' + AG_CRLF + '  object lblMine: TLabel' + AG_CRLF + '  end' + AG_CRLF + 'end';
var
  U: TUnitInheritance;
  function Rows: TArray<string>; // ['TLeaf|' + AG_LEAF_PAS + '|TMid', 'TMid|' + AG_MID_PAS + '|TBase', 'TBase|' + AG_BASE_PAS + '|TForm']
  function Rd(const ALeafDfm, AMidDfm: string): TDfmTextReader; // Leaf/Mid/Base .dfm texts, Base = AG_BASE_DFM
begin
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_INH_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.ancestors.root.first', U.Known and (Length(U.Ancestors) = 2) and SameText(U.Ancestors[0].PasPath, AG_BASE_PAS) and SameText(U.Ancestors[1].PasPath, AG_MID_PAS), U.Error);
  Check('ag.analyze.intermediate.converted', Length(U.Ancestors[1].Types) = 0);
  Check('ag.analyze.verdicts.kept', (Length(U.Verdicts) = 1) and (U.Verdicts[0].State = asUnconverted));
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_INH_DFM, AG_MID_OWN_DFM), nil);
  Check('ag.analyze.intermediate.unconverted', string.Join(',', U.Ancestors[1].Types) = 'TTable');
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(Rows, nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.no.instance.strict', U.Known and (Length(U.Verdicts) = 0) and (Length(U.Ancestors) = 2) and (string.Join(',', U.Ancestors[0].Types) = 'TTable'), U.Error);
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(['TLeaf|' + AG_LEAF_PAS + '|TForm'], nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.outside.silent', U.Known and (Length(U.Ancestors) = 0), U.Error);
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup(['TLeaf|' + AG_LEAF_PAS + '|TMid', 'TMid|' + AG_MID_PAS + '|TBase', 'TBase|!|boom'], nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.error.unknown', (not U.Known) and (Pos('boom', U.Error) > 0) and (Length(U.Ancestors) = 0), U.Error);
  U:= AnalyzeUnit(AG_LEAF_PAS, AgPairs, FakeLookup([], nil), Rd(LEAF_OWN_DFM, AG_MID_DFM), nil);
  Check('ag.analyze.own.not.indexed.e3', U.Known and (Length(U.Ancestors) = 0));
end;
```
- [ ] **Step 2: Build + run -> `ag.analyze.*` FAIL** (Ancestors empty), everything else green.
- [ ] **Step 3: Restructure `AnalyzeWith`** as listed. Update the `AnalyzeUnit` DocInsight (`<returns>` mentions `Ancestors`; `<remarks>`: a Failed own-class lookup is now unknown for every unit).
- [ ] **Step 4: Build + run.** Expected: 0 fail; every pre-existing `code.use.*` / `inherit.*` check still passes (if `code.use.lookup.failed`-style checks move, the E3 rule above is what the plan fixes -- do not weaken the test).
- [ ] **Step 5: Lint.** **Step 6: Commit** -- `feat(converter): C8CHAIN T4 -- AnalyzeUnit fills the ancestor graph`.

---

## Task 5: `AncestorChain` = verdicts + graph; `UnconvertedTypes`; E5 note (pure)

**Files:**
- Modify: `ED\ConvRules.Inheritance.pas` (`AncestorChain` :439-448 / :1500; `UnconvertedTypes` :518-522 / :1619; `InheritanceRowNote` :421-437 / :1470; a new constant `NOTE_ANCESTOR_FMT`)
- Modify: `ED\tests\inc\AncestorGraphTests.inc` (+ `TestAncestorChainUnion`)

**Interfaces (produces, signatures unchanged, contracts widened):**
* `AncestorChain(AUnit)`: the union of (a) the chain units of its asUnconverted verdicts and (b) `Ancestors` with `Length(Types) > 0`; de-duplicated by path, Depth descending stable (a unit in both keeps the larger Depth). `[]` when nothing is unconverted. DocInsight: replace "An ancestor that never mentions an instance is not offered" with "An intermediate ancestor is offered when it still holds a From type, whether or not it re-opens an instance (owner ruling Q5)".
* `UnconvertedTypes(AUnit)`: verdict types first, then each unconverted ancestor's `Types`, distinct first seen.
* `InheritanceRowNote`: after the verdict parts and before the outside notes, one part per unconverted ancestor whose PasPath is neither a verdict's `DeclaringPas` nor in any verdict's `Chain`: `NOTE_ANCESTOR_FMT = 'descends from %s, which still has %s -- convert it first (recommended)'` (`UnitNameOf(PasPath)`, types `', '`-joined). Root first.

- [ ] **Step 1: Failing test:**
```pascal
procedure TestAncestorChainUnion;
var
  U: TUnitInheritance;
  function Anc(const APas: string; ADepth: Integer; const ATypes: TArray<string>): TAncestorUnit;
begin
  U:= Default(TUnitInheritance); U.UnitPas:= AG_LEAF_PAS; U.Known:= True;
  U.Ancestors:= [Anc(AG_BASE_PAS, 2, ['TTable']), Anc(AG_MID_PAS, 1, [])];
  Check('ag.chain.graph.only', string.Join(',', AncestorChain(U)) = AG_BASE_PAS, string.Join(',', AncestorChain(U)));
  U.Ancestors[1].Types:= ['TQuery'];
  Check('ag.chain.intermediate.included', string.Join(',', AncestorChain(U)) = AG_BASE_PAS + ',' + AG_MID_PAS);
  Check('ag.chain.types.union', string.Join(',', UnconvertedTypes(U)) = 'TTable,TQuery');
  Check('ag.chain.note', InheritanceRowNote(U, True) = 'descends from Base, which still has TTable -- convert it first (recommended); descends from Mid, which still has TQuery -- convert it first (recommended)', InheritanceRowNote(U, True));
  // a verdict naming Base: Base is listed once, and the E5 part replaces the ancestor part for it
  SetLength(U.Verdicts, 1); U.Verdicts[0]:= Default(TInstanceVerdict);
  U.Verdicts[0].Instance.Name:= 'tblX'; U.Verdicts[0].Instance.TypeName:= 'TTable'; U.Verdicts[0].State:= asUnconverted;
  U.Verdicts[0].DeclaringUnit:= 'Base'; U.Verdicts[0].DeclaringPas:= AG_BASE_PAS;
  SetLength(U.Verdicts[0].Chain, 1); U.Verdicts[0].Chain[0].PasPath:= AG_BASE_PAS; U.Verdicts[0].Chain[0].Depth:= 2;
  Check('ag.chain.dedupe', string.Join(',', AncestorChain(U)) = AG_BASE_PAS + ',' + AG_MID_PAS, string.Join(',', AncestorChain(U)));
  Check('ag.chain.note.verdict.first', InheritanceRowNote(U, True) = 'inherits 1 TTable instance(s) from Base -- convert it first (recommended); descends from Mid, which still has TQuery -- convert it first (recommended)', InheritanceRowNote(U, True));
  U.Ancestors:= nil;
  Check('ag.chain.verdicts.only.unchanged', string.Join(',', AncestorChain(U)) = AG_BASE_PAS);
end;
```
- [ ] **Step 2: Build + run -> `ag.chain.*` FAIL.**
- [ ] **Step 3: Implement** the three widened functions and the constant.
- [ ] **Step 4: Build + run.** Expected 0 fail; `inherit.chain.*`, `inherit.note.*`, `inherit.offer.*` (dpr :11882-11946, :12036) unchanged and green.
- [ ] **Step 5: Lint.** **Step 6: Commit** -- `feat(converter): C8CHAIN T5 -- AncestorChain unions the graph; E5 ancestor note`.

---

## Task 6: `OrderAncestorFirst`, blocking E7 texts (pure)

**Files:**
- Modify: `ED\ConvRules.Inheritance.pas` (`OrderWarningText` :503-510 / :1606 and `OrderCancelledText` :512-516 / :1614 REPLACED; constants `ORDER_TAIL`, `ORDER_TAIL_N1`, `ORDER_CANCELLED`, `ORDER_CANCELLED_N1` :580-590 replaced)
- Modify: `ED\tests\ConvRulesModelTests.dpr` :11915-11916, :11941-11946 (the three E7 text checks move to the new API)
- Modify: `ED\tests\inc\AncestorGraphTests.inc` (+ `TestAncestorOrder`)

**Interfaces (produces):**
```pascal
/// <summary>PURE: AList in the order Convert runs it -- every listed unit after the listed
/// members of its AncestorChain (owner ruling Q5: strict ancestor-first). Stable: units with no
/// constraint between them keep their order, so an ancestor-first list is returned unchanged
/// (the 1.42 engine's own in-batch order then has nothing to move).</summary>
/// <param name="AList">The source list.</param>
/// <param name="AUnits">The listed units' analyses (any order; a unit without one has no constraint).</param>
/// <returns>A permutation of AList. Each pass takes the FIRST remaining unit whose listed
/// ancestors are all placed; a cycle cannot be ordered, so its units follow in list order --
/// nothing is dropped. Unlisted ancestors impose nothing.</returns>
function OrderAncestorFirst(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>): TArray<string>;

/// <summary>PURE: the blocking E7 question (replaces the warning with "anyway").</summary>
/// <param name="AWarnings">OrderWarnings' lines; not empty.</param>
/// <param name="AOrdered">OrderAncestorFirst's answer.</param>
/// <returns>ORDER_HEAD, the lines one per line, a blank line, then 'Convert runs ancestors first:
/// Base.pas, Mid.pas, Leaf.pas. Reorder the list and run?' (file names, ', '-joined).</returns>
function OrderBlockText(const AWarnings, AOrdered: TArray<string>): string;

const
  /// <summary>The status after No to the E7 question (every engine).</summary>
  ORDER_CANCELLED_TEXT = 'Convert cancelled: nothing was run.';
```
`OrderWarnings` keeps its signature and `ARetypeSupported` (the line wording). `OrderWarningText` and `OrderCancelledText` are deleted (their only caller is `ConvertTab.InheritanceChecksPass`, rewired in Task 7; build the editor only after Task 7).

- [ ] **Step 1: Failing test:**
```pascal
procedure TestAncestorOrder;
var
  Leaf, Mid, Base: TUnitInheritance;  Warn: TArray<string>;
  function WithAnc(const APas: string; const AAnc: TArray<TAncestorUnit>): TUnitInheritance; // Known, UnitPas, Ancestors
  function Anc(const APas: string; ADepth: Integer): TAncestorUnit; // Types ['TTable']
begin
  Leaf:= WithAnc(AG_LEAF_PAS, [Anc(AG_BASE_PAS, 2), Anc(AG_MID_PAS, 1)]);
  Mid := WithAnc(AG_MID_PAS, [Anc(AG_BASE_PAS, 1)]);
  Base:= WithAnc(AG_BASE_PAS, []);
  Check('ag.order.root.first', string.Join(',', OrderAncestorFirst([AG_LEAF_PAS, AG_MID_PAS, AG_BASE_PAS], [Leaf, Mid, Base])) = AG_BASE_PAS + ',' + AG_MID_PAS + ',' + AG_LEAF_PAS);
  Check('ag.order.stable', string.Join(',', OrderAncestorFirst(['fx\X.pas', AG_BASE_PAS, AG_LEAF_PAS], [Leaf, Base])) = 'fx\X.pas,' + AG_BASE_PAS + ',' + AG_LEAF_PAS);
  Check('ag.order.unlisted.ignored', string.Join(',', OrderAncestorFirst([AG_LEAF_PAS, 'fx\X.pas'], [Leaf])) = AG_LEAF_PAS + ',fx\X.pas');
  Check('ag.order.unconverted.constrains', string.Join(',', OrderAncestorFirst([AG_MID_PAS, AG_BASE_PAS], [WithAnc(AG_MID_PAS, [Anc(AG_BASE_PAS, 1)])]))
    = AG_BASE_PAS + ',' + AG_MID_PAS);
  Mid:= WithAnc(AG_MID_PAS, [Anc(AG_BASE_PAS, 1)]);
  Mid.Ancestors[0].Types:= nil; // Base treated as converted: no constraint, list unchanged
  Check('ag.order.converted.no.constraint', string.Join(',', OrderAncestorFirst([AG_MID_PAS, AG_BASE_PAS], [Mid])) = AG_MID_PAS + ',' + AG_BASE_PAS);
  Check('ag.order.cycle.caller.order', string.Join(',', OrderAncestorFirst([AG_MID_PAS, AG_BASE_PAS], [WithAnc(AG_MID_PAS, [Anc(AG_BASE_PAS, 1)]), WithAnc(AG_BASE_PAS, [Anc(AG_MID_PAS, 1)])])) = AG_MID_PAS + ',' + AG_BASE_PAS);
  Check('ag.order.case.insensitive', string.Join(',', OrderAncestorFirst([UpperCase(AG_LEAF_PAS), AG_BASE_PAS], [Leaf])) = AG_BASE_PAS + ',' + UpperCase(AG_LEAF_PAS));
  Warn:= OrderWarnings([AG_LEAF_PAS, AG_BASE_PAS], [Leaf], True);
  Check('ag.block.text', OrderBlockText(Warn, [AG_BASE_PAS, AG_LEAF_PAS]) = 'Some units are listed above an ancestor that is not converted yet:' + sLineBreak
    + Warn[0] + sLineBreak + sLineBreak + 'Convert runs ancestors first: Base.pas, Leaf.pas. Reorder the list and run?', OrderBlockText(Warn, [AG_BASE_PAS, AG_LEAF_PAS]));
  Check('ag.block.no.anyway', not ContainsText(OrderBlockText(Warn, [AG_BASE_PAS, AG_LEAF_PAS]), 'anyway'));
  Check('ag.block.cancel.text', ORDER_CANCELLED_TEXT = 'Convert cancelled: nothing was run.');
end;
```
- [ ] **Step 2: Build -> compile error (RED).**
- [ ] **Step 3: Implement**; delete the two old functions and their four constants; rewrite dpr :11915-11916 to `OrderBlockText(Warn, [BASE_PAS, MID_PAS, LEAF_PAS])` assertions (`StartsWith(ORDER_HEAD)`, `Contains(Warn[0])`, `EndsWith('Reorder the list and run?')`), :11941-11946 to the no-retype LINE wording only (`Warn[0] = 'Leaf.pas is listed above its ancestor Base.pas.'`) and `ORDER_CANCELLED_TEXT`.
- [ ] **Step 4: Build + run.** 0 fail.
- [ ] **Step 5: Lint** (an `unused-public-symbol` on `OrderBlockText` / `OrderAncestorFirst` is expected until Task 7 -- note it, do not mark it). **Step 6: Commit** -- `feat(converter): C8CHAIN T6 -- OrderAncestorFirst and the blocking E7 question`.

---

## Task 7: ConvertTab wiring (build-only, no engine)

**Files:**
- Modify: `ED\ConvRules.ConvertTab.pas` (`InheritanceChecksPass` :225 declaration, :1591-1633 body; `ConvertClick` :1726-1732)

**Interfaces:** consumes Task 5 `AncestorChain` / `UnconvertedTypes` (already called at :1239, :1256, :1263 -- no change), Task 6 `OrderAncestorFirst`, `OrderBlockText`, `ORDER_CANCELLED_TEXT`.

- [ ] **Step 1: Change the signature** to `function InheritanceChecksPass(var pUnits: TArray<string>): Boolean;` (DocInsight on the declaration: "pUnits leaves in run order: after Yes to the E7 question the list is reordered ancestor-first and SetSources shows it"). Replace lines 1620-1632 with:
  ```pascal
  // C8CHAIN (owner ruling Q5): a descendant above an unconverted ancestor never runs in
  // that order. Yes reorders the list and runs; No runs nothing.
  var LWarn: TArray<string>:= OrderWarnings(pUnits, InheritanceOfAll(pUnits), FRetypeOk);
  if Length(LWarn) > 0 then
  begin
    var LOrdered: TArray<string>:= OrderAncestorFirst(pUnits, InheritanceOfAll(pUnits));
    var LText: string:= OrderBlockText(LWarn, LOrdered);
    FHost.SetStatus(StringReplace(LText, sLineBreak, ' ', [rfReplaceAll]), False); // mirrored for the GUI driver
    if AskBlockingDrops(LText, mtWarning) <> mrYes then
    begin
      FHost.SetStatus(ORDER_CANCELLED_TEXT, False);
      Exit(False);
    end;
    SetSources(LOrdered);
    pUnits:= LOrdered;
  end;
  ```
  `ConvertClick`: `if not InheritanceChecksPass(Units) then ...` stays; `Job.Units := Units` (:1732) now receives the ordered list. Check `SetSources` (:363) does not clear `FInherit` (it must not re-analyse; if it does, call `FSources.Invalidate` instead and set the items directly -- read the body first).
- [ ] **Step 2: Build the editor** -> `BUILD_EXITCODE=0`. Build + run the model tests -> 0 fail (the tests' closure does not include the tab; this proves nothing about it -- the GUI driver in Task 8 does).
- [ ] **Step 3: Lint** -- `lint ED\ConvRules.ConvertTab.pas` + `lint-all`; the Task 6 unused-public findings are gone.
- [ ] **Step 4: Commit** -- `feat(converter): C8CHAIN T7 -- E7 blocks: Yes reorders ancestor-first and runs`.

---

## Task 8: GUI driver -- the chain case with a RED proof (needs the live pin)

**Files:**
- Modify: `ED\tests\gui\drive-inherited-offer.ps1` (header comment :1-29; `param` :29; fixture :388-552; expected texts :559-561; new block after the D3 check :656 and before `-ProofGateYes`; `-ProofGateYes` block)

**Setup:** stage a copy of the pin dir `C:\Projects\Delphi-RAG-lint\third_party\engine-pinned\1.40.0-alpha-20261103-145611\` to `SC\stage\` (exe, DLLs, `drag-lint.json`, `rules\`), copy `ED\ConvRulesEditor.exe` beside it; run `pwsh -NoProfile -File ED\tests\gui\vcl-atoms.ps1` first if the editor CLAUDE.md says so for this driver's siblings. Run: `pwsh -NoProfile -File ED\tests\gui\drive-inherited-offer.ps1 -Exe SC\stage\ConvRulesEditor.exe > SC\gui.log`; read `SC\gui.log` with `Select-String 'PASS|FAIL|gui-inherited'`. 15-minute timeout per run; kill the runner's TREE on a stall (memory: GUI batteries stall unseen).

- [ ] **Step 1: Extend the fixture.** Add `Mid.pas` (`TMidForm = class(TAncForm)` with field `Label9: TLabel` -- under `-ProofMidConverted` the field and the .dfm object are `TStaticText`) + `Mid.dfm` (`inherited MidForm: TMidForm` + `object Label9: <type>` + `Caption = 'Mid'`; it does NOT re-open `Label1`), `Leaf.pas` (`TLeafForm = class(TMidForm)`, uses `Mid`) + `Leaf.dfm` (`inherited LeafForm: TLeafForm` + `inherited Label1: TLabel` + `Caption = 'Leaf'`). List both in `Fix.dpr` (`Mid in 'Mid.pas' {MidForm}`, `Leaf in 'Leaf.pas' {LeafForm}`) -- the index is the compile closure. `param([string]$Exe, [switch]$ProofNoInheritance, [switch]$ProofGateYes, [switch]$ProofMidConverted)`; `$mid`, `$leaf` path variables beside `$desc`.
- [ ] **Step 2: Update the expected texts** (:560-561) for both capability branches: `$orderText = '*Convert runs ancestors first: Anc.pas, Desc.pas. Reorder the list and run?*'`; `$cancelText = 'Convert cancelled: nothing was run.'`. `$offerText` unchanged (Desc's chain is still only Anc).
- [ ] **Step 3: Add the case** (after `offer.no.to.all.once`):
  ```powershell
  # --- C8CHAIN: Leaf -> Mid -> Anc; Mid re-opens no instance but still holds a TLabel of its own ---
  ClearSources $src $del
  [void](WaitFor { @([CT]::Items($src)).Count -eq 0 } 10)
  $e = PickFile $p.Id $add $leaf
  $prompt = WaitCls $p.Id 'TMessageForm' 20
  $st = Status $main
  Check 'chain.intermediate.offered' (($e -eq '') -and ($prompt -ne [IntPtr]::Zero) -and ($st -like 'Add Anc.pas, Mid.pas ahead of Leaf.pas?*')) "$e status: $st"
  if ($prompt -ne [IntPtr]::Zero) { $e = Answer $p.Id 'Yes' } else { $e = 'no prompt' }
  [void](WaitFor { @([CT]::Items($src)).Count -eq 3 } 10)
  WaitAddSettled $p.Id $main 3
  $items = [CT]::Items($src)
  Check 'chain.yes.inserts.root.first' (($e -eq '') -and ($items.Count -eq 3) -and ($items[0] -eq $anc) -and ($items[1] -eq $mid) -and ($items[2] -eq $leaf)) "$e items: $($items -join ' | ')"
  # E7 blocking: Leaf, Mid, Anc listed in that order -> the question names the ancestor-first order; No runs nothing
  ClearSources $src $del
  [void](WaitFor { @([CT]::Items($src)).Count -eq 0 } 10)
  $e = PickFile $p.Id $add $leaf; $prompt = WaitCls $p.Id 'TMessageForm' 20; if ($prompt -ne [IntPtr]::Zero) { [void](Answer $p.Id 'No') }
  [void](WaitFor { @([CT]::Items($src)).Count -eq 1 } 10)
  $e = PickFile $p.Id $add $mid; $prompt = WaitCls $p.Id 'TMessageForm' 20; if ($prompt -ne [IntPtr]::Zero) { [void](Answer $p.Id 'No') }
  [void](WaitFor { @([CT]::Items($src)).Count -eq 2 } 10)
  $e = PickFile $p.Id $add $anc
  WaitAddSettled $p.Id $main 3
  [void](WaitIdle $p.Id $main 90)
  Click $conv
  $warn = WaitCls $p.Id 'TMessageForm' 30
  $st = Status $main
  Check 'order.blocking.text' (($warn -ne [IntPtr]::Zero) -and ($st -like '*Convert runs ancestors first: Anc.pas, Mid.pas, Leaf.pas. Reorder the list and run?*') -and -not ($st -like '*anyway*')) "status: $st"
  if ($warn -ne [IntPtr]::Zero) { [void](Answer $p.Id 'No') }
  [void](WaitFor { (Status $main) -eq $cancelText } 10)
  Check 'order.blocking.no.runs.nothing' (((Status $main) -eq $cancelText) -and -not (Test-Path -LiteralPath ($leaf + '.BCK1')) -and -not (Test-Path -LiteralPath ($mid + '.BCK1'))) (Status $main)
  ```
  In the `-ProofGateYes` block, after `Answer 'Yes'` and before `$ended`: `$items = [CT]::Items($src); Check 'order.yes.reordered' (($items.Count -eq 2) -and ($items[0] -eq $anc) -and ($items[1] -eq $desc)) ($items -join ' | ')`.
- [ ] **Step 4: RED first on the pre-C8CHAIN exe.** A pre-branch editor: copy `C:\Projects\Delphi-RAG-lint\src\tools\convrules-editor\ConvRulesEditor.exe` (read-only use of the main tree; check its mtime predates this branch) or build one from a second worktree at c2c4b750 (never stash or checkout in WT). Put it in `SC\stage-old\` beside the same pin copy and run the driver. Expected FAIL: `chain.intermediate.offered`, `chain.yes.inserts.root.first`, `order.blocking.text`, `order.warning` (old text) -- record the exact counts in the header comment.
- [ ] **Step 5: GREEN on this branch's exe.** Expected `gui-inherited-offer: 20 pass / 0 fail` (16 + 4). Then `-ProofMidConverted`: expected 18 / 2 -- `chain.intermediate.offered` (offer reads `Add Anc.pas ahead of Leaf.pas?`) and `order.blocking.text` (order `Mid.pas, Anc.pas, Leaf.pas`) FAIL, the proof that both checks can. Then `-ProofGateYes`: 21 / 0 (a ~20 s real run). Record all three measurements in the header comment (:1-29) with the date.
- [ ] **Step 6: Encoding guard** on the .ps1; **Commit** -- `test(converter): C8CHAIN T8 -- drive-inherited-offer chain case (20 / 0; -ProofMidConverted 18 / 2)`.

---

## Task 9: Docs, registry, whole-branch lint (featuregen only)

**Files:**
- Modify: `ED\CLAUDE.md` (test kit line `drive-inherited-offer.ps1 16` -> `20 -- ... (-ProofMidConverted = 18 / 2; -ProofGateYes 21)`; unit map `Inheritance` line: "+ C8CHAIN ancestor graph (`AncestorGraphOf`, `OrderAncestorFirst`, blocking E7)")
- Modify: `WT\docs\CONVERTER-BACKLOG.md` (the C8CHAIN bullet: prefix `DONE conv/c8chain <sha>` and one line on what the editor does vs the 1.42 engine order)
- Modify: `WT\docs\wiki\convrules-editor.md` (the C8 / inherited-instances section: the graph, the "already converted?" test, the Yes-reorders question, the engine 1.42 order as the second net)
- Modify: `WT\features\entries\convrules-editor.json` (the inherited-instances steps/questions updated) then `featuregen normalise`, `featuregen build --all`, `featuregen verify --id convrules-editor --by CONVERTER`; `WT\tests\autotest\run_feature_registry_guard.ps1` and `run_docs_sync_guard.ps1` green.

- [ ] **Step 1: Docs edits** as listed (ASCII, no state notes in CLAUDE.md).
- [ ] **Step 2: featuregen** (build it first with `WT\build\_build_featuregen_local.bat` if missing); commit the regenerated `docs\wiki`, `features\generated\`, `WWW\help\dl\` files WITH the entry.
- [ ] **Step 3: Whole-branch lint sweep** (repo CLAUDE.md): reindex `WTDB`; `lint-all --db WTDB --enable multiple-statements-per-line,magic-literal,commented-out-code`; one `lint <unit>` per changed unit (`ConvRules.Inheritance.pas`, `ConvRules.ConvertTab.pas`) with the same `--enable` plus `review-marker-stale,review-marker-unused`; every `dl:ok` the branch adds re-checked. Report the counts against `SC\baseline.txt`.
- [ ] **Step 4: Final model-test run** (0 fail) and the encoding guard. **Commit** -- `docs(converter): C8CHAIN T9 -- wiki, registry, CLAUDE.md counts`.
- [ ] **Step 5: Report** (do not merge): commits, test counts (model: before/after; GUI: 20/0, 18/2, 21/0, pre-branch RED list), lint counts, and the owner questions below.

---

## Decisions recorded (for the reviewer)

1. **Engine order reuse:** not relied on. The 1.42 engine orders only in-batch ancestors that declare the descendant's inherited/inline From objects; the editor needs the graph anyway to ADD a missing ancestor, to include an intermediate holding unrelated From types, and to block. Editor ordering is kept on every engine (1.41 pins convert ancestor-first only if the list is), with no capability gate -- the engine shipped none, and `OrderUnitsByDependencies` is stable so an editor-ordered list is a no-op for it.
2. **Blocking E7:** one Yes/No question; Yes = `SetSources(OrderAncestorFirst(..))` and run that order, No = `ORDER_CANCELLED_TEXT`. No "anyway" path on any engine; the retype-dependent E7 texts are deleted (the no-retype engines predate every pin in use).
3. **"Already converted?"** = `FromTypesIn(ancestor .dfm, From-typed fields)` is empty. Fields count because an E2b code use of an inherited From-typed field is a real dependency the .dfm never shows.
4. **Intermediates:** included iff they still hold a From type; a converted intermediate imposes no order and is not offered.
5. **Dry run:** nothing to do; the editor only runs `--apply`.

## Open owner questions

* **Q-A (Review Focus 1):** a listed descendant with NO inherited From instance whose ancestor still holds a From type -- the plan applies the literal ruling (ancestor first, offered on add). If the owner wants the offer only when an inherited instance exists, Task 4 keeps `Ancestors` and Task 5 filters `AncestorChain` by `Length(AUnit.Verdicts) > 0` -- a one-line change.
* **Q-B:** a chain that leaves the index (library/other-project ancestor) stays a note, never a block -- confirm, since the ruling says "to the very original".
