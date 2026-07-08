# Batch C Implementation Plan -- DbResolver probe + reverse-calltree + naming autofix (phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three independent post-v0.95 drag-lint features -- a DbResolver project-name DB probe (fixes "Code Elements 0"), a first-class `reverse-calltree` report, and phase-1 naming autofix (re-casing) via the existing rename engine.

**Architecture:** Each feature reuses a shipped engine. DbResolver adds one probe candidate to two functions. reverse-calltree adds a pure `deps-report`-style engine unit + a CLI verb + renderers, reading the caller traversal that already carries call-site data. Naming autofix adds a pure name-synthesizer + a store-backed rename append in `FinalizeAndOutput`, mirroring the existing `doc-drift` append; gated by the existing `AutoFixIds` mechanism.

**Tech Stack:** Delphi 13 (Studio 37), Win32 (plugin BPL) + Win64 (CLI), FireDAC/SQLite index, TreeSitter parse, PowerShell autotest batteries. Spec: `docs/superpowers/specs/2026-07-08-batch-c-dbresolver-rcalltree-naming-autofix-design.md`.

## Global Constraints

- **Encoding (all `.pas`/`.dfm`):** strict 7-bit ASCII, no BOM, CRLF line endings. Never introduce Unicode or LF. DocInsight comments are ASCII too.
- **DocInsight (CDD):** every new public type/function gets a `///` `<summary>` (+ `<param>`/`<returns>`/`<remarks>` as apt). Comment and test must agree.
- **TDD:** failing test first, then minimal implementation to green.
- **Naming:** `TMyClass`, `FMyField`, `pMyParam`; Delphi 13 idioms (`if`-ternary, `is not`).
- **Build:** use the `delphi-build` skill recipe (rsvars + msbuild via `Start-Process cmd.exe -Wait` with a log; check `BUILD_EXITCODE=0`, no `[dcc32 Error]`/`error F2039`). CLI = Win64 (`src/cli/drag-lint.dproj`), plugin = Win32 (`src/delphi-plugin/dclDragLintWizard.dproj`). Close RAD Studio (`bds.exe`) before a BPL build (it holds the lock -> F2039).
- **Deploy after build:** CLI Win64 exe -> `third_party/dll-win64/drag-lint.exe`; plugin BPL auto-deploys to `third_party/dll-win32/`.
- **Frequent commits:** one per task (or per green sub-slice), conventional-commit style.
- **Self-index freshness:** if symbols the tool queries changed, reindex incrementally (`feedback_draglint_over_grep`); not required for these edits unless a later query depends on them.

---

# FEATURE 1 -- DbResolver project-name probe

Touches only `src/delphi-plugin/DragLint.Plugin.DbResolver.pas`. **Plugin BPL rebuild required (Win32, RAD Studio closed).** The end-to-end (outline in a live IDE) is IDE-only, so the automatable gate is a unit test of the extracted probe helper.

### Task 1: Extract a pure `PickProjectDb` helper + probe the project-name file

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.DbResolver.pas` (add helper; call it from `PrimaryDbForProject` :240 and `FindAncestorDb` :398; remove the TODO block :25-36)
- Test: `tests/autotest/run_dbresolver_probe.ps1` (drives a tiny console harness -- see Step 1 note) OR a DUnitX case if a plugin test project exists

**Interfaces:**
- Consumes: `ResolveDbPath(const ATemplate, AProjDir: string): string` (from `DRagLint.Plugin.Settings.pas:198` -- substitutes `<projdir>`), `TDragLintSettings.DbPathTemplate`.
- Produces: `function PickProjectDb(const AProjPath: string; const ASettings: TDragLintSettings): string;` -- returns the chosen existing-and-non-empty DB path for a `.dproj`, or `''`. Candidate order: template-resolved file, then `<projdir>\<projname>.sqlite`. Pure (no OTA).

- [ ] **Step 1: Write the failing test**

The probe logic is pure (paths + file existence), so it is testable without the IDE. Because the helper lives in a BPL unit that pulls in OTA/registry units, **the practical headless harness is a tiny throwaway console program** that `uses` only the pure pieces. Create `tests/autotest/run_dbresolver_probe.ps1` that (a) writes a temp dir with fixture `.sqlite` files, (b) compiles+runs a 30-line console harness (`tests/autotest/fixtures/dbprobe/DbProbeHarness.dpr`) linking `DRagLint.Plugin.Settings` + a **copy of the pure `PickProjectDb` body**, (c) asserts the chosen path. To avoid duplicating logic, put `PickProjectDb` in a NEW tiny pure unit `src/delphi-plugin/DragLint.Plugin.DbProbe.pas` (no OTA uses) that BOTH the resolver and the harness link.

`tests/autotest/fixtures/dbprobe/DbProbeHarness.dpr`:
```pascal
program DbProbeHarness;
{$APPTYPE CONSOLE}
uses System.SysUtils, DRagLint.Plugin.Settings, DRagLint.Plugin.DbProbe;
var
  Settings: TDragLintSettings;
  Chosen  : string;
begin
  // args: <projPath> <dbPathTemplate>
  Settings := Default(TDragLintSettings);
  Settings.DbPathTemplate := ParamStr(2);
  Chosen := PickProjectDb(ParamStr(1), Settings);
  Writeln(Chosen);
end.
```

`tests/autotest/run_dbresolver_probe.ps1` (asserting the three cases):
```powershell
# CASE A: only <projname>.sqlite present, non-empty -> chosen over absent template file
# CASE B: both present -> template file still wins (back-compat)
# CASE C: neither present -> '' (empty output)
# Build DbProbeHarness.dpr with rsvars+msbuild (Win64 Debug), then run per-case.
# Assert: A -> ends-with 'MyProj.sqlite'; B -> ends-with 'drag-lint.sqlite'; C -> ''.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_dbresolver_probe.ps1`
Expected: FAIL -- `DRagLint.Plugin.DbProbe` / `PickProjectDb` does not exist yet (compile error building the harness).

- [ ] **Step 3: Write the pure unit**

Create `src/delphi-plugin/DragLint.Plugin.DbProbe.pas`:
```pascal
unit DRagLint.Plugin.DbProbe;

interface

uses
  DRagLint.Plugin.Settings;

/// <summary>Chooses the on-disk index DB for a project's own directory: the
/// settings-template file (`&lt;projdir&gt;\drag-lint.sqlite`) if it exists and is
/// non-empty, else the project-name file (`&lt;projdir&gt;\&lt;projname&gt;.sqlite`,
/// i.e. ChangeFileExt of the .dproj) if it exists and is non-empty, else ''.
/// Template-first preserves existing setups; the project-name probe fixes the
/// "Code Elements 0" case where a project was indexed to &lt;projname&gt;.sqlite.
/// Pure: only path math + file existence/size, no OTA.</summary>
/// <param name="AProjPath">Full path to the .dproj (or '').</param>
/// <param name="ASettings">Resolver settings; DbPathTemplate drives the template file.</param>
/// <returns>Chosen existing non-empty DB path, or '' when neither candidate qualifies.</returns>
function PickProjectDb(const AProjPath: string; const ASettings: TDragLintSettings): string;

implementation

uses
  System.SysUtils, System.IOUtils;

function ExistsNonEmpty(const APath: string): Boolean;
begin
  Result := (APath <> '') and TFile.Exists(APath) and (TFile.GetSize(APath) > 0);
end;

function PickProjectDb(const AProjPath: string; const ASettings: TDragLintSettings): string;
var
  ProjDir : string;
  Template: string;
  ByName  : string;
begin
  Result := '';
  if AProjPath = '' then Exit;
  ProjDir  := ExtractFilePath(AProjPath);
  Template := ResolveDbPath(ASettings.DbPathTemplate, ProjDir);
  if ExistsNonEmpty(Template) then Exit(Template);
  ByName := ChangeFileExt(AProjPath, '.sqlite'); // <projdir>\<projname>.sqlite
  if ExistsNonEmpty(ByName) then Exit(ByName);
end;

end.
```
Add `DRagLint.Plugin.DbProbe` to the plugin `.dpk` `contains` clause and the `.dproj` `<DCCReference>` (per the LESSON in memory: a unit in DCCReference but NOT `.dpk contains` + unreferenced is NOT compiled).

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/autotest/run_dbresolver_probe.ps1`
Expected: PASS (A -> project-name file; B -> template file; C -> '').

- [ ] **Step 5: Wire the helper into the resolver + delete the TODO**

In `DragLint.Plugin.DbResolver.pas`, add `DRagLint.Plugin.DbProbe` to `uses`. In `ResolveActiveIndexDbs` at :527-537, replace the `PrimaryDbForProject`/`FindAncestorDb` primary pick so the project-name file is tried before the ancestor fallback:
```pascal
  if ProjPath <> '' then
  begin
    PrimaryDb := PickProjectDb(ProjPath, ASettings); // template-first, then <projname>.sqlite
    if PrimaryDb <> '' then AddUnique(Result, PrimaryDb)
    else
    begin
      ProjDir := ExtractFilePath(ProjPath);
      AncestorDb := FindAncestorDb(ProjDir, ASettings);
      if AncestorDb <> '' then AddUnique(Result, AncestorDb);
    end;
  end;
```
Also add the project-name candidate to `FindAncestorDb`'s per-level `Candidates` list (:422-431) so an ancestor `<dirname>.sqlite` is found on the walk-up:
```pascal
    // after the CANONICAL_TEMPLATE candidate:
    SetLength(Candidates, Length(Candidates) + 1);
    Candidates[High(Candidates)] := IncludeTrailingPathDelimiter(Dir)
      + ExtractFileName(ExcludeTrailingPathDelimiter(Dir)) + '.sqlite';
```
Delete the TODO comment block at :25-36 (fixed) and update `ResolverDiagnostic` (:463) to call `PickProjectDb` for the `PrimaryDb` line so the diagnostic reflects the new probe.

- [ ] **Step 6: Build the plugin BPL (RAD Studio closed) + verify 0 errors**

Run the `delphi-build` recipe for `src/delphi-plugin/dclDragLintWizard.dproj` (Win32, Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc32 Error]`, BPL deployed to `third_party/dll-win32/`.

- [ ] **Step 7: Commit**

```bash
git add src/delphi-plugin/DRagLint.Plugin.DbProbe.pas src/delphi-plugin/DragLint.Plugin.DbResolver.pas src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj tests/autotest/run_dbresolver_probe.ps1 tests/autotest/fixtures/dbprobe/DbProbeHarness.dpr third_party/dll-win32/dclDragLintWizard.bpl
git commit -m "fix(plugin): probe <projdir>\\<projname>.sqlite in DB resolution (fixes Code Elements 0)"
```

- [ ] **Step 8: Note the live-IDE smoke check (user runs, not automatable)**

Record in the commit body / batch smoke checklist: open a project whose index is `<projname>.sqlite`, confirm the Structure tree shows `Code Elements (N>0)`.

---

# FEATURE 2 -- reverse-calltree report

CLI-only; **no BPL/IDE work**. CLI Win64 rebuild + deploy at the end. Reuses the caller traversal, which -- confirmed in code -- already queries the call-site line (it is currently dropped).

### Task 2: Carry the call-site line on `TResolvedCaller` (additive, zero blast radius)

**Files:**
- Modify: `src/core/DRagLint.Core.Model.pas:149-154` (add a field)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas:1046` (populate it from the already-selected `start_line`)
- Test: covered by Task 4's battery (asserts the line surfaces); add a focused note here.

**Interfaces:**
- Produces: `TResolvedCaller.CallSiteLine: Integer` -- 1-based line of the call site in the caller's file (0 if unknown). `Location` (filename-only) is unchanged, so existing consumers (callgraph, AutoDoc) are unaffected.

- [ ] **Step 1: Add the field with DocInsight**

In `DRagLint.Core.Model.pas`, extend `TResolvedCaller`:
```pascal
  TResolvedCaller = record
    EnclosingSymbolId: Int64  ;
    EnclosingQName   : string ;
    Location         : string ; // filename only (unchanged; existing consumers rely on this)
    /// <summary>1-based line of the call site in the caller's file; 0 when unknown.
    /// Added for reverse-calltree; other consumers may ignore it.</summary>
    CallSiteLine     : Integer;
    Confidence       : string ;
  end;
```

- [ ] **Step 2: Populate it in the store (the line is already SELECTed)**

`FindResolvedCallers` already selects `r.start_line` (`DRagLint.Storage.SQLite.pas:1022`) but only sets the filename. After line 1046 add:
```pascal
      R.Location  := ExtractFileName(Q.FieldByName('file_path').AsString);
      if Q.FieldByName('start_line').IsNull then R.CallSiteLine := 0
      else R.CallSiteLine := Q.FieldByName('start_line').AsInteger;
```

- [ ] **Step 3: Build CLI Win64 to verify it compiles**

Run the `delphi-build` recipe for `src/cli/drag-lint.dproj` (Win64, Debug).
Expected: `BUILD_EXITCODE=0`, no `[dcc Error]`.

- [ ] **Step 4: Commit**

```bash
git add src/core/DRagLint.Core.Model.pas src/storage/DRagLint.Storage.SQLite.pas
git commit -m "feat(store): carry call-site line on TResolvedCaller (for reverse-calltree)"
```

### Task 3: Reverse-calltree engine unit (pure, deps-report-shaped)

**Files:**
- Create: `src/report/DRagLint.Report.RCallTree.pas`
- Test: exercised via the CLI in Task 4 (the engine is pure but has no standalone Delphi test project; the `.ps1` battery is the gate, matching `deps-report`).

**Interfaces:**
- Consumes: `ISymbolStore.GetSymbolById`, `ISymbolStore.FindResolvedCallers` (returns `TArray<TResolvedCaller>` with `EnclosingSymbolId`, `EnclosingQName`, `Location`, `CallSiteLine`).
- Produces:
  - `TRCallNode = record QName: string; Site: string; Cycle: Boolean; Callers: TArray<TRCallNode>; end;` (`Site` = `unit:line`, '' for the root)
  - `TRCallSummary = record NodeCount, MaxDepthReached, CycleCount: Integer; Truncated: Boolean; end;`
  - `TRCallTree = record Root: TRCallNode; Summary: TRCallSummary; end;`
  - `TRCallOptions = record Depth: Integer; end;` (default depth 3)
  - `function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64; const AOpts: TRCallOptions): TRCallTree;`

- [ ] **Step 1: Write the engine**

```pascal
unit DRagLint.Report.RCallTree;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Interfaces;

type
  /// <summary>One node of the reverse (upward) call tree: a symbol, its call
  /// site into the child it calls (unit:line), a cycle marker, and its own
  /// callers. Root.Site is ''. Callers is empty at the depth cap or when a
  /// node is a cycle re-encounter.</summary>
  TRCallNode = record
    QName  : string;
    Site   : string;            // unit:line of THIS node's call into its child; '' for root
    Cycle  : Boolean;           // True: already expanded elsewhere; Callers left empty
    Callers: TArray<TRCallNode>;
  end;

  /// <summary>Whole-tree totals.</summary>
  TRCallSummary = record
    NodeCount      : Integer;
    MaxDepthReached: Integer;
    CycleCount     : Integer;
    Truncated      : Boolean;   // True when the depth cap stopped a non-cyclic expansion
  end;

  /// <summary>The reverse call tree rooted at a symbol, plus summary totals.</summary>
  TRCallTree = record
    Root   : TRCallNode;
    Summary: TRCallSummary;
  end;

  /// <summary>Tuning knobs for BuildReverseCallTree.</summary>
  TRCallOptions = record
    Depth: Integer;             // remaining levels of callers to expand; default 3
  end;

/// <summary>Builds the N-deep REVERSE call tree rooted at ARootId: who calls the
/// root, who calls them, ... Reuses ISymbolStore.FindResolvedCallers. Bounded by
/// AOpts.Depth AND a global-visited set so recursive cycles terminate: a
/// re-encountered symbol yields a node with Cycle=True and no further expansion
/// (same policy as callgraph). Borrows AStore; no I/O.</summary>
/// <param name="AStore">Open store (ids are per-DB).</param>
/// <param name="ARootId">Symbol id of the tree root.</param>
/// <param name="AOpts">Depth cap.</param>
/// <returns>The tree + summary. Root.Site is ''.</returns>
function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;

implementation

function BuildReverseCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;
var
  Visited: TDictionary<Int64, Boolean>;
  Sum    : TRCallSummary;

  function Expand(AId: Int64; ADepth, ALevel: Integer; const ASite: string): TRCallNode;
  var
    Callers: TArray<TResolvedCaller>;
    C      : TResolvedCaller;
    Kids   : TList<TRCallNode>;
  begin
    Result := Default(TRCallNode);
    Result.QName := AStore.GetSymbolById(AId).QualifiedName;
    Result.Site  := ASite;
    Inc(Sum.NodeCount);
    if ALevel > Sum.MaxDepthReached then Sum.MaxDepthReached := ALevel;
    if Visited.ContainsKey(AId) then
    begin
      Result.Cycle := True;
      Inc(Sum.CycleCount);
      Exit;
    end;
    Visited.Add(AId, True);
    if ADepth <= 0 then Exit;
    Callers := AStore.FindResolvedCallers(AId);
    if Length(Callers) = 0 then Exit;
    Kids := TList<TRCallNode>.Create;
    try
      // ADepth >= 1 here (ADepth <= 0 returned above). At ADepth = 1 the children
      // are expanded but THEIR callers are cut by the depth cap -> mark truncated
      // whenever a child itself has callers we won't reach.
      if (ADepth = 1) and (Length(Callers) > 0) then Sum.Truncated := True;
      for C in Callers do
      begin
        if C.EnclosingSymbolId <= 0 then Continue;
        Kids.Add(Expand(C.EnclosingSymbolId, ADepth - 1, ALevel + 1,
          Format('%s:%d', [C.Location, C.CallSiteLine])));
      end;
      Result.Callers := Kids.ToArray;
    finally
      Kids.Free;
    end;
  end;

begin
  Sum := Default(TRCallSummary);
  Visited := TDictionary<Int64, Boolean>.Create;
  try
    Result.Root := Expand(ARootId, AOpts.Depth, 0, '');
    Result.Summary := Sum;
  finally
    Visited.Free;
  end;
end;

end.
```

Add `DRagLint.Report.RCallTree` to `src/cli/drag-lint.dproj` `<DCCReference>` (it is referenced by CLI.pas in Task 4, so it will compile).

**Reusability note (spec requirement):** `BuildReverseCallTree` is a pure function over a borrowed store with a record return, and depth is a parameter. AutoDoc's future `<remarks>` "Called from" (Track 2.1) can therefore call it with `AOpts.Depth = 1` to get the direct callers (each `TRCallNode.Callers[i].QName` + `.Site`) with no rework. This is NOT wired in this batch -- it is the reason the engine is a standalone unit rather than inlined in the CLI verb.

- [ ] **Step 2: Build CLI Win64 to verify it compiles**

Run the `delphi-build` recipe for `src/cli/drag-lint.dproj`.
Expected: `BUILD_EXITCODE=0` (unit compiles; unused until Task 4 wires the verb -- a reference is added there).

- [ ] **Step 3: Commit**

```bash
git add src/report/DRagLint.Report.RCallTree.pas src/cli/drag-lint.dproj
git commit -m "feat(report): reverse-calltree engine (pure, cycle-guarded, deps-report-shaped)"
```

### Task 4: `reverse-calltree` CLI verb + text/json/dot/mermaid renderers + battery

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (add `DoReverseCallTree` near `DoCallGraph` ~:9946; dispatch near :11292; ensure `--depth`/`--format`/`--json`/`--db`/`--qname`/`--name` are parsed -- `--depth` default 3 already exists at :502)
- Test: `tests/autotest/run_reverse_calltree.ps1`

**Interfaces:**
- Consumes: `BuildReverseCallTree` (Task 3), `ResolveEndpointIds(Store, AArgs.QName): TArray<Int64>` (existing, used by `DoCallGraph:9973`), `OpenReadOnlyStore` (:9970), `TArgs` fields `QName`, `Depth`, `Format`/`AsJson`, `DbPath`/`DbPaths`.
- Produces: verb `reverse-calltree` returning 0 (ok), 1 (qname unresolved), 2 (usage/db error) -- matching `DoCallGraph`'s exit contract.

- [ ] **Step 1: Write the failing battery test**

Create `tests/autotest/run_reverse_calltree.ps1` following `run_deps_report.ps1`'s structure (temp workdir, `Write-Ascii` for 7-bit ASCII, `Check` helper, index then assert, deterministic re-run). Fixture: a caller chain plus a cycle.
```powershell
# FIXTURE (chain A->B->C, plus cycle P<->Q):
#   unit chainc; ... procedure C; begin end;                    <- root
#   unit chainb; uses chainc; procedure B; begin C; end;        <- calls C at a known line
#   unit chaina; uses chainb; procedure A; begin B; end;        <- calls B
#   unit cyc;    procedure P; forward; procedure Q; begin P; end; procedure P; begin Q; end;
#
# Assertions (against 'reverse-calltree --qname C --db <db> --json'):
#   - root qname endsWith '.C' (or 'C')
#   - root.callers contains B; B.callers contains A     (upward direction)
#   - a caller node's site matches '<unit>:<line>' with a numeric line (CallSiteLine surfaced)
#   - '--depth 1' truncates: A is absent under C's tree; summary.truncated == true
#   - cycle: 'reverse-calltree --qname P --db <db> --json' has a node with cycle==true, no infinite output
#   - '--format dot' output contains 'digraph'; '--format mermaid' contains 'graph'
#   - text ('--format text' or default) is indented and contains 'C' then 'B'
#   - two --json runs are byte-identical (determinism)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_reverse_calltree.ps1`
Expected: FAIL -- `reverse-calltree` is not a known verb (nonzero exit / usage error).

- [ ] **Step 3: Implement `DoReverseCallTree` + renderers**

Add near `DoCallGraph`. Renderers convert `TRCallTree` to text (indented, `unit:line` + `(cycle)`), JSON (schema `reverse-calltree/1`), and dot/mermaid (borrow the node/edge emit shape from `DoGraph` :3234). Multi-`--db`: resolve the first store that contains the qname (mirror the hover multi-db precedent -- iterate `DbPaths`, pick the first whose `ResolveEndpointIds` is non-empty).
```pascal
/// <summary>drag-lint reverse-calltree --qname X [--depth N] [--format text|json|dot|mermaid]
/// [--json] --db PATH ... -- the N-deep REVERSE call tree rooted at X: who calls X,
/// who calls them, with call sites (unit:line) and cycle markers. Reuses the
/// resolved caller traversal (FindResolvedCallers) via BuildReverseCallTree. Text
/// is an indented tree (2 spaces/level); --format dot|mermaid emit a chart; --json /
/// --format json emit schema reverse-calltree/1. With multiple --db, the first DB
/// that resolves the qname is used (ids are per-DB).</summary>
/// <param name="AArgs">QName=root, Depth=tree depth (default 3), Format/AsJson=output,
/// DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname unresolved in every DB; 2 usage error / no readable db.</returns>
function DoReverseCallTree(const AArgs: TArgs): Integer;
```
- Root resolution: iterate the resolved DB list; for the first store where `ResolveEndpointIds(Store, AArgs.QName)` is non-empty, build the tree per root id (an overloaded name may resolve to several roots -- emit one tree each, array-wrap in JSON like `DoCallGraph:9987`).
- Depth: `if AArgs.Depth < 0 then 0` (as `DoCallGraph:9966`), else `AArgs.Depth` (default 3).
- Format precedence: if `--format` is `dot`/`mermaid`/`json` use it; else if `--json` set emit JSON; else text. (Document that, like `deps-report`, `--format` is the primary switch.)

- [ ] **Step 4: Wire the dispatch**

Near `DRagLint.CLI.pas:11292` (`'callgraph' -> DoCallGraph`), add:
```pascal
    else if SameText(Verb, 'reverse-calltree') then Result := DoReverseCallTree(Args)
```
Add `DRagLint.Report.RCallTree` to CLI.pas `uses`.

- [ ] **Step 5: Build CLI Win64 + run the battery to green**

Build `src/cli/drag-lint.dproj` (Win64), deploy exe to `third_party/dll-win64/drag-lint.exe`, then:
Run: `pwsh tests/autotest/run_reverse_calltree.ps1`
Expected: PASS (all assertions).

- [ ] **Step 6: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_reverse_calltree.ps1 src/cli/Win64/Debug/drag-lint.exe third_party/dll-win64/drag-lint.exe
git commit -m "feat(cli): reverse-calltree verb -- upward call tree with call sites (text/json/dot/mermaid)"
```

---

# FEATURE 3 -- naming autofix, phase 1 (re-casing)

CLI/engine work; the IDE "Fix it" lights up from `FIXABLE_RULE_IDS` automatically (confirm whether the plugin duplicates that list -- if so a BPL rebuild follows). Ships **opt-in** via `AutoFixIds`.

### Task 5: Pure name synthesizer

**Files:**
- Create: `src/refactor/DRagLint.Refactor.NamingFix.pas` (synthesizer now; the rename dispatch is added in Task 6)
- Test: `tests/autotest/run_naming_synth.ps1` (console harness like Feature 1) OR fold into Task 7's battery. Prefer a small dedicated harness since the synthesizer is pure and cheap to unit-test.

**Interfaces:**
- Consumes: nothing but the identifier string + a style tag.
- Produces:
  - `TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);`
  - `function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;` -- returns the re-cased identifier (same letters, adjusted case). Idempotent (already-correct name returns itself).
  - `function StyleFromConfigText(const AConfigCase: string): TNameStyle;` -- maps `'PascalCase'|'camelCase'|'UPPER_CASE'` (the `TNamingConfig.MethodCase`/`LocalCase`/`ConstCase` vocabulary) to `TNameStyle`; defaults to `nsPascalCase`.

- [ ] **Step 1: Write the failing test**

`tests/autotest/fixtures/namesynth/NameSynthHarness.dpr` (console, `uses DRagLint.Refactor.NamingFix`) printing `SynthesizeCasedName(ParamStr(1), StyleFromConfigText(ParamStr(2)))`. `tests/autotest/run_naming_synth.ps1` asserts:
```
# doThing   PascalCase -> DoThing
# DoThing   PascalCase -> DoThing   (idempotent)
# MyValue   camelCase  -> myValue
# maxCount  UPPER_CASE -> MAXCOUNT  (or MAX_COUNT? -> see Step 3 decision: pure recase = MAXCOUNT)
# X         PascalCase -> X
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh tests/autotest/run_naming_synth.ps1`
Expected: FAIL -- unit/functions do not exist (harness compile error).

- [ ] **Step 3: Implement the synthesizer**

```pascal
unit DRagLint.Refactor.NamingFix;

interface

type
  /// <summary>Target casing styles, matching TNamingConfig's textual vocabulary.</summary>
  TNameStyle = (nsPascalCase, nsCamelCase, nsUpperCase);

/// <summary>Maps a TNamingConfig case string ('PascalCase' | 'camelCase' |
/// 'UPPER_CASE') to a TNameStyle. Unknown/empty -> nsPascalCase.</summary>
function StyleFromConfigText(const AConfigCase: string): TNameStyle;

/// <summary>Returns AOldName re-cased to AStyle WITHOUT changing its letters or
/// inserting separators (a pure, collision-free re-casing in a case-insensitive
/// language). PascalCase upper-cases the first char; camelCase lower-cases it;
/// UPPER_CASE upper-cases the whole identifier. Idempotent. Empty -> ''.</summary>
/// <param name="AOldName">The offending identifier verbatim.</param>
/// <param name="AStyle">Target style.</param>
/// <returns>The re-cased identifier.</returns>
function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;

implementation

uses
  System.SysUtils;

function StyleFromConfigText(const AConfigCase: string): TNameStyle;
begin
  if SameText(AConfigCase, 'camelCase') then Result := nsCamelCase
  else if SameText(AConfigCase, 'UPPER_CASE') then Result := nsUpperCase
  else Result := nsPascalCase;
end;

function SynthesizeCasedName(const AOldName: string; AStyle: TNameStyle): string;
begin
  if AOldName = '' then Exit('');
  case AStyle of
    nsUpperCase : Result := UpperCase(AOldName);
    nsCamelCase : Result := LowerCase(AOldName[1]) + Copy(AOldName, 2, MaxInt);
    else          Result := UpperCase(AOldName[1]) + Copy(AOldName, 2, MaxInt); // nsPascalCase
  end;
end;

end.
```
DECISION (record in the unit's remarks): phase-1 is **pure re-casing only** -- no separator insertion. `UPPER_CASE` therefore yields `MAXCOUNT`, not `MAX_COUNT` (word-boundary detection is a phase-2 concern; keep phase-1 collision-free and mechanical).

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh tests/autotest/run_naming_synth.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/refactor/DRagLint.Refactor.NamingFix.pas tests/autotest/run_naming_synth.ps1 tests/autotest/fixtures/namesynth/NameSynthHarness.dpr src/cli/drag-lint.dproj
git commit -m "feat(refactor): pure name-recasing synthesizer for naming autofix"
```

### Task 6: Register naming rules as fixable + store-backed rename append

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- `FIXABLE_RULE_IDS` (:4226, bump the array bound) + the store-backed append in `FinalizeAndOutput` (mirror the doc-drift block :4753-4778)
- Modify: `src/refactor/DRagLint.Refactor.NamingFix.pas` -- add a dispatch that turns a naming finding into rename edits (keeps the CLI thin)
- Test: `tests/autotest/run_naming_autofix.ps1` (Task 7)

**Interfaces:**
- Consumes: `SynthesizeCasedName`/`StyleFromConfigText` (Task 5), `TRenameRefactoring.Build`/`BuildLocal`/`ConflictReason` (`DRagLint.Refactor.Rename.pas:29/50/38`), `TNamingConfig` (`DRagLint.Lint.Config.pas:16`, fields `MethodCase`/`LocalCase`/`ConstCase`), `TLintFinding` (`RuleId`, `FilePath`, `StartLine`, `StartCol`, `EndCol`), `ISymbolStore`, the effective `TLintConfig` (for `IsAutoFix`).
- Produces:
  - In `DRagLint.Refactor.NamingFix.pas`: `function BuildNamingFixEdits(const AStore: ISymbolStore; const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig; out AFixCount: Integer): TArray<TTextEdit>;` -- for each fixable naming finding, recover the offending identifier from source at (StartLine, StartCol..EndCol), synthesize the target name, run `ConflictReason`, and (if clear) build rename edits and convert them to `TTextEdit`. Returns applied edits; increments `AFixCount` per fixed identifier. Skips (no edit) on conflict or unresolved symbol.

- [ ] **Step 1: Write the failing test (per-rule fixtures)**

Author `tests/autotest/run_naming_autofix.ps1` (Task 7 owns the full battery, but write the RED skeleton here so this task's implementation has a target). Minimal RED assertion: `lint --fix --apply` on a fixture with a mis-cased method (opted-in via `AutoFixIds`) rewrites every call site. See Task 7 Step 1 for the full fixture.

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh tests/autotest/run_naming_autofix.ps1`
Expected: FAIL -- the naming rule is not fixable yet (no edit produced; identifier unchanged).

- [ ] **Step 3: Add the rule ids to `FIXABLE_RULE_IDS`**

Extend the array (bump `array[0..10]` -> `array[0..13]`) and keep the guard test in mind (the id list must agree with the dispatch):
```pascal
  FIXABLE_RULE_IDS: array[0..13] of string = (
    'self-assignment', 'redundant-parentheses', 'redundant-cast', 'redundant-not-not', 'redundant-as-tobject', 'boolean-comparison-true', 'reserved-word-casing',
    'redundant-assigned-free', 'off-by-one-count', 'doc-drift', 'missing-doc',
    'method-pascalcase', 'local-var-casing', 'const-casing');
```

- [ ] **Step 4: Implement `BuildNamingFixEdits`**

In `DRagLint.Refactor.NamingFix.pas` add (uses `DRagLint.Refactor.Rename`, `DRagLint.Refactor.TextEdit`, `DRagLint.Core.Interfaces`, `DRagLint.Core.Model`, `DRagLint.Lint.Config`):
```pascal
function BuildNamingFixEdits(const AStore: ISymbolStore;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  out AFixCount: Integer): TArray<TTextEdit>;
```
Per finding:
1. Skip unless `RuleId` in {`method-pascalcase`,`local-var-casing`,`const-casing`}.
2. Recover the offending identifier from the source line at `[StartCol, EndCol)` (read the file's `StartLine`; the finding gives `StartCol`/`EndCol`). This is robust to per-rule message wording.
3. Pick the style: `method-pascalcase` -> `StyleFromConfigText(ANaming.MethodCase)`; `local-var-casing` -> `StyleFromConfigText(ANaming.LocalCase)`; `const-casing` -> `StyleFromConfigText(first ANaming.ConstCase, default 'UPPER_CASE')`.
4. `NewName := SynthesizeCasedName(OldName, style)`. If `SameText(NewName, OldName)` and `NewName = OldName` (already exactly cased) -> skip (nothing to do).
5. Build rename edits:
   - `local-var-casing` -> `TRenameRefactoring.BuildLocal(FilePath, StartLine, StartCol, NewName)` (routine-local, no store, safe scope).
   - `method-pascalcase` / unit-level `const-casing` -> derive the qualified name from `AStore` (find the symbol whose decl is at `FilePath`/`StartLine`/`StartCol`), then `if TRenameRefactoring.ConflictReason(AStore, QName, NewName) = '' then Build(AStore, QName, NewName)` else skip.
6. Convert each `TRenameEdit` to a `TTextEdit` (`tekReplaceInLine` at Line/Col replacing `OldName` with `NewName`; the applier orders back-to-front like the rename engine's own sort). Append to the result; `Inc(AFixCount)` once per fixed identifier (not per site).

Record in a `<remarks>`: re-casing is collision-free in a case-insensitive language, but `ConflictReason` is still run as defense-in-depth and is load-bearing for phase 2.

- [ ] **Step 5: Wire the store-backed append in `FinalizeAndOutput`**

After the doc-drift append (`DRagLint.CLI.pas:4778`), add a parallel block gated on opt-in:
```pascal
    { Naming re-casing autofix (phase 1): store-backed like doc-drift. Only for
      findings whose rule is BOTH registered-fixable AND opted-in via AutoFixIds.
      The synthesizer + rename engine live in DRagLint.Refactor.NamingFix. }
    if AStore <> nil then
    begin
      var NamingTargets: TArray<TLintFinding> := nil;
      for F in Targeted do
        if (SameText(F.RuleId, 'method-pascalcase') or SameText(F.RuleId, 'local-var-casing')
            or SameText(F.RuleId, 'const-casing')) and LintCfg.IsAutoFix(F.RuleId) then
          NamingTargets := NamingTargets + [F];
      if Length(NamingTargets) > 0 then
      begin
        var NFCount: Integer;
        var NFEdits := DRagLint.Refactor.NamingFix.BuildNamingFixEdits(AStore, NamingTargets, LintCfg.Naming, NFCount);
        if Length(NFEdits) > 0 then
        begin
          Edits := Edits + NFEdits;
          Inc(FixCount, NFCount);
        end;
      end;
    end;
```
(`LintCfg` is the effective `TLintConfig` in scope in `FinalizeAndOutput` -- confirm its identifier name at the call site and match it; `Naming` is its public field.) Add `DRagLint.Refactor.NamingFix` to CLI.pas `uses`.

- [ ] **Step 6: Build CLI Win64 to verify it compiles**

Run the `delphi-build` recipe for `src/cli/drag-lint.dproj`.
Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 7: Commit**

```bash
git add src/cli/DRagLint.CLI.pas src/refactor/DRagLint.Refactor.NamingFix.pas
git commit -m "feat(autofix): register naming re-casing rules as fixable via the rename engine (opt-in)"
```

### Task 7: Naming-autofix battery (all rules + opt-in + conflict skip + dry-run)

**Files:**
- Modify/complete: `tests/autotest/run_naming_autofix.ps1`
- Modify: the existing `FIXABLE_RULE_IDS`/dispatch guard test (extend for the 3 new ids)

**Interfaces:**
- Consumes: the built `drag-lint.exe` (Win64) with the wired autofix.

- [ ] **Step 1: Complete the battery**

Fixtures + assertions (7-bit ASCII via `Write-Ascii`; a `drag-lint-lint.json` opting the rules in via `AutoFixIds`):
```powershell
# FIXTURE 1 (method-pascalcase): a unit with `procedure doThing;` defined + called
#   at 2 sites. Config AutoFixIds includes 'method-pascalcase'.
#   lint --fix --apply -> every 'doThing' becomes 'DoThing' (decl + both calls).
# FIXTURE 2 (local-var-casing): a routine with a mis-cased local used twice ->
#   BuildLocal rewrites decl + both uses; nothing outside the routine changes.
# FIXTURE 3 (const-casing): a unit-level const 'maxItems' with ConstCase UPPER_CASE
#   -> becomes 'MAXITEMS' at decl + use.
# OPT-IN GATE: run the SAME fixture with AutoFixIds NOT listing the rule ->
#   identifier is UNCHANGED (registered-fixable but not permitted).
# CONFLICT SKIP: a fixture where the synthesized name already exists as a sibling
#   (force ConflictReason non-empty) -> no edit applied, identifier unchanged,
#   exit still 0.
# DRY-RUN: 'lint --fix' (no --apply) -> preview only, file on disk unchanged.
# Determinism: two --fix --apply runs on a fresh copy produce identical results.
```
Follow `run_deps_report.ps1` for harness scaffolding (`Check`, temp workdir, `& $Exe`, `exit 1` on any FAIL).

- [ ] **Step 2: Run the battery to green**

Run: `pwsh tests/autotest/run_naming_autofix.ps1`
Expected: PASS.

- [ ] **Step 3: Extend + run the fixable-id guard test**

Run the existing guard test that asserts `FIXABLE_RULE_IDS` and the fix dispatch agree (locate it via the comment at `DRagLint.CLI.pas:4221` "a guard test asserts they agree"). Confirm it still passes with the 3 new ids (they are store-backed-append, like doc-drift/missing-doc, so the guard must treat them as the doc-drift exception -- update the guard's allowlist of store-backed ids if it enumerates them).
Expected: PASS.

- [ ] **Step 4: Confirm the IDE "Fix it" path**

Grep the plugin (`src/delphi-plugin/*.pas`) for any duplicated fixable-id list or `IsFixableRule` use. If the plugin calls the CLI/`IsFixableRule` (single source of truth), no BPL change is needed -- note that. If it hard-codes a list, add the 3 ids and rebuild the BPL (Win32, RAD Studio closed). Record the outcome in the commit body.

- [ ] **Step 5: Commit**

```bash
git add tests/autotest/run_naming_autofix.ps1 tests/autotest/<guard-test-if-changed>
git commit -m "test(autofix): naming re-casing battery -- all rules, opt-in gate, conflict skip, dry-run"
```

---

# BATCH WRAP-UP

### Task 8: Full battery + docs + release note

**Files:**
- Modify: `docs/lint/drag-lint TODO plan.md` (mark 5.1 done; note naming autofix phase-1 shipped + phase-2 pending)
- Modify: CLI/verb reference doc + `docs/lint/BACKLOG.md` (new RESUME note)
- Modify: any `AI-USAGE`/`AI-INDEX-FIRST` doc that lists verbs (add `reverse-calltree`)

- [ ] **Step 1: Run the whole autotest battery**

Run the batch's new scripts plus a representative regression set (e.g. `run_deps_report.ps1`, `run_doc_returns.ps1`, `run_manifest.ps1`) against the freshly-built Win64 exe.
Expected: all PASS (no regression).

- [ ] **Step 2: Update the roadmap + docs**

In `docs/lint/drag-lint TODO plan.md`: under Track 5.1 mark it shipped (text/json/dot/mermaid, CLI-only, IDE right-click deferred). Under Track 1.1 note naming autofix **phase 1 shipped** (re-casing: method-pascalcase/local-var-casing/const-casing, opt-in via AutoFixIds) and **phase 2 (prefix-adding) still pending**. Add the DbResolver fix to the "done" record. Add `reverse-calltree` to any verb list in the AI docs.

- [ ] **Step 3: Write the BACKLOG RESUME note (LATEST-33)**

Append a `RESUME 2026-07-08 (LATEST-33)` block to `docs/lint/BACKLOG.md` summarizing the three shipped features, the exit-code contracts, the opt-in gate, and the deferred items (arch charts 5.3; naming phase 2; reverse-calltree IDE right-click).

- [ ] **Step 4: Commit**

```bash
git add "docs/lint/drag-lint TODO plan.md" docs/lint/BACKLOG.md docs/AI-USAGE.md docs/AI-INDEX-FIRST.md
git commit -m "docs(batch-c): mark 5.1 + naming autofix phase-1 shipped; DbResolver fix; RESUME LATEST-33"
```

- [ ] **Step 5: Offer the release cut**

The batch rides the next version bump (post-v0.95, untagged). Do NOT push or tag -- the user drives push. Report the branch state (commits ahead of origin) and hand off the live-IDE smoke items (Feature 1 outline; Feature 3 "Fix it" if the BPL changed) for the user to verify.

---

## Notes on de-risking discovered during planning (do not re-investigate)

- **Feature 2 call-site line already queried.** `FindResolvedCallers` (`DRagLint.Storage.SQLite.pas:1022`) already `SELECT`s `r.start_line` and joins `refs`->`files`; it only DROPS the line (`:1046` keeps just the filename). Task 2 is therefore an additive field, not a new join -- zero blast radius on existing consumers.
- **`TResolvedCaller` already has `Location`** (`DRagLint.Core.Model.pas:152`) -- filename only; leave it, add `CallSiteLine` beside it.
- **Naming findings carry no identifier text**, only location + a human message (`DRagLint.Diagnostics.NamingChecks.pas:327` `EmitAt` sets `StartLine`/`StartCol`/`EndCol`). Recover the identifier from source at `[StartCol, EndCol)` -- do NOT parse the message.
- **Rename engine signatures** (`DRagLint.Refactor.Rename.pas`): `Build(store, AQName, ANewName)` (:29, needs a qualified name), `BuildLocal(AFile, ALine, ACol, ANewName)` (:50, needs file+line/col -- naming findings have these), `ConflictReason(store, AQName, ANewName)` (:38), `Apply(edits, backups)` (:30). The token match is case-insensitive (`:201`), ideal for re-casing.
- **Store-backed append precedent** is the doc-drift block (`DRagLint.CLI.pas:4753-4778`) -- copy its shape exactly for the naming append.
