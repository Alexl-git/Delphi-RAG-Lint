# Lazy Unknown-Property-Type Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete proptree's lazy unknown-property-type recovery so that when a query resolves a bare/unknown property up the class tree, the recovered type is persisted DOWN the tree onto every bare/unknown occurrence in the queried class's ancestor+descendant closure (never overwriting an explicit type), and the real type is returned.

**Architecture:** Extend the existing per-property resolution in proptree's `Walk` (`src/report/DRagLint.Convert.PropTree.pas`). Persist a recovered type for BOTH recovery paths (inherited + bridged), not just the bridge. Add a propagation helper that, once per walked class, computes the class's ancestor+descendant closure and stamps the recovered type onto every same-named bare property in it. Best-effort/idempotent, reusing `MemoizePropertyType`.

**Tech Stack:** Delphi 13 (Studio 37), Win64 console build (`build/build_draglint_win64.bat`), FireDAC/SQLite symbol store, PowerShell autotest harness (`run_proptree_ancestry_bridge.ps1`), Python 3.14 stdlib sqlite3 for raw-DB assertions.

## Global Constraints

- All `.pas` source: strict 7-bit ASCII, CRLF, no BOM. Verify after every Write/Edit.
- DocInsight `///` spec-comments on any new public method.
- **Safety rule (load-bearing):** down-propagation updates a class's property ONLY when that property's own signature is empty/bare (`ParseTypeToken(sig) = ''`). NEVER overwrite a property that declares its own explicit type.
- Lazy/query-triggered only -- NO proactive batch pass over the whole index.
- Write-back is best-effort: `MemoizePropertyType` already no-ops on a read-only handle and swallows write errors; a query must never fail on a write-lock.
- Idempotent: a re-query of any propagated property must perform zero writes.
- Auto write-back is the DEFAULT (`--no-write-back` opts out); `--write-back` is NOT a valid flag. Any test must NOT pass `--write-back`.
- Rooting decision: propagate over the QUERIED class's ancestor+descendant closure (reachable via resolved edges), NOT rooted at the far-side declaring class -- the unresolved alias edge breaks downward transitivity from the declaring class.
- Build recipe: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; success = `BUILD_EXITCODE=0`, no `[dcc] Error`.
- Spec: `docs/superpowers/specs/2026-07-20-lazy-unknown-property-type-resolution-design.md`.

---

### Task 1: Fix the stale ancestry-bridge test + add propagation/safety assertions (failing test)

**Files:**
- Modify: `tests/autotest/run_proptree_ancestry_bridge.ps1` (correct to auto-write-back default; extend the fixture + assertions)

**Interfaces:**
- Produces: the executable spec that Task 2 must satisfy.

**Context:** The existing test is stale — it predates the auto-write-back default. Its `--write-back` calls now hit an unknown flag (non-JSON error), and its "signature is empty after a read-only query" assertion is wrong (a plain read now memoizes). This task rewrites those assertions to the current default AND adds a descendant class (`TcxSpeedButton`, bare Align -> must be propagated) plus a safety-case class (`TcxTypedButton`, explicit `Align: TMyAlign` -> must NOT be overwritten).

- [ ] **Step 1: Extend the CxKit fixture** — in `run_proptree_ancestry_bridge.ps1`, replace the `CxKit.pas` Write-Ascii body with:

```pascal
unit CxKit;

interface

uses
  VclKit;

type
  TcxBaseButton = TCustomButton;   // alias => broken edge

  TcxCustomButton = class(TcxBaseButton)
  published
    property Align;                // bare (intermediate)
  end;

  TcxButton = class(TcxCustomButton)
  published
    property Align;                // bare (the queried leaf)
    property Caption;
  end;

  TcxSpeedButton = class(TcxButton) // DESCENDANT of the queried class
  published
    property Align;                // bare -> must be propagated to TAlign
  end;

  TMyAlign = (maNone, maFull);

  TcxTypedButton = class(TcxButton) // SAFETY CASE: explicit own type
  published
    property Align: TMyAlign;      // must NOT be overwritten
  end;

implementation

end.
```

- [ ] **Step 2: Rewrite the write-back / propagation section** — replace everything from the `# --- 2. Write-back memoization` comment to the end of file with:

```powershell
# --- 2. Auto write-back is the DEFAULT: a plain read memoizes the queried row. ----
$dbw = Join-Path $WorkDir 'bridge_wb.sqlite'
Copy-Item $db $dbw -Force

$script:PyAny = Join-Path $WorkDir 'read_sig.py'
Write-Ascii $script:PyAny @'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); c = con.cursor()
r = c.execute(
    "SELECT signature FROM symbols WHERE name='Align' AND kind='property' "
    "AND parent_id IN (SELECT id FROM symbols WHERE name=? AND kind='class')",
    (sys.argv[2],)
).fetchone()
print('' if r is None else (r[0] or ''))
con.close()
'@
function Get-Sig([string]$Database,[string]$Cls){ return (python $script:PyAny $Database $Cls).Trim() }

# Query the leaf once (auto write-back default) -> resolves + persists + propagates.
$null = Get-Tree $dbw 'CxKit.TcxButton'

Check "queried TcxButton.Align memoized ': TAlign'"        ((Get-Sig $dbw 'TcxButton')       -eq ': TAlign')
Check "intermediate TcxCustomButton.Align propagated"       ((Get-Sig $dbw 'TcxCustomButton') -eq ': TAlign')
Check "descendant TcxSpeedButton.Align propagated"          ((Get-Sig $dbw 'TcxSpeedButton')  -eq ': TAlign')
Check "SAFETY: TcxTypedButton.Align NOT overwritten"        ((Get-Sig $dbw 'TcxTypedButton')  -eq ': TMyAlign')

# Idempotency: a second query performs no further mutation.
$sigBefore = Get-Sig $dbw 'TcxSpeedButton'
$null = Get-Tree $dbw 'CxKit.TcxButton'
Check "idempotent: TcxSpeedButton.Align unchanged on re-query" ((Get-Sig $dbw 'TcxSpeedButton') -eq $sigBefore)

# Read-only DB: resolution still returns TAlign, no write attempted/succeeds.
$dbro = Join-Path $WorkDir 'bridge_ro.sqlite'
Copy-Item $db $dbro -Force
$treeRo = Get-Tree $dbro 'CxKit.TcxButton' # (no --write-back flag; default is auto, but RO handle no-ops)
$alignRo = @($treeRo.properties) | Where-Object { $_.path -eq 'Align' } | Select-Object -First 1
Check "read-only still resolves Align=TAlign" ($null -ne $alignRo -and $alignRo.type -eq 'TAlign') "type=$($alignRo.type)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

Also DELETE the now-obsolete `$script:PyQuery`/`Get-AlignSig` block and the old section-2 body (superseded by the above). Keep the section-1 read-only resolution asserts (Align=TAlign, not the FMX decoy, not unknown).

- [ ] **Step 3: Run to verify the propagation asserts FAIL** (against the current, un-modified exe)

```powershell
$env:ErrorActionPreference='Continue'; & .\tests\autotest\run_proptree_ancestry_bridge.ps1 -Exe .\src\cli\Win64\Debug\drag-lint.exe
```
Expected: section 1 + `queried TcxButton.Align memoized` PASS (already works); `intermediate ... propagated`, `descendant ... propagated` FAIL (propagation not implemented); `SAFETY ...` PASS (nothing overwrites it yet, it has an explicit type); read-only PASS. The two propagation FAILs are the target.

- [ ] **Step 4: Commit the failing test**

```powershell
$b=[IO.File]::ReadAllBytes("tests\autotest\run_proptree_ancestry_bridge.ps1"); ($b | Where-Object {$_ -gt 127}).Count
git add tests/autotest/run_proptree_ancestry_bridge.ps1
git commit -m "test(proptree): auto-write-back default + down-propagation/safety asserts (failing)"
```
Expected: non-ASCII `0`; commit succeeds.

---

### Task 2: Implement persist-both-paths + down-propagation over the queried class closure

**Files:**
- Modify: `src/report/DRagLint.Convert.PropTree.pas` (extend `Walk`; add a propagation helper)

**Interfaces:**
- Consumes: `AStore.GetTransitiveAncestors`, `AStore.FindDescendantNames`, `AStore.FindSymbolByExactNameAnywhere`, `AStore.FindChildSymbolByName`, `AStore.MemoizePropertyType`, the unit-local `ParseTypeToken`, `BodyOf`.
- Produces: proptree now persists recovered types (both paths) and propagates them across the queried class's ancestor+descendant closure, bare-only.

- [ ] **Step 1: Add a closure-collector + propagation helper as nested routines** inside the same outer routine that hosts `Walk` (alongside `CollectProps`/`ResolveInheritedType`). Place before `Walk`:

```pascal
  // Class ids of AClass + its transitive (resolved) ancestors + transitive
  // descendants -- the connected tree reachable via RESOLVED edges. Used to
  // propagate a recovered property type onto every bare same-named occurrence.
  // Computed once per walked class (cached by the caller).
  function ClosureClassIds(const AClass: TSymbol): TArray<Int64>;
  var
    Ids : TList<Int64>;
    Seen: TDictionary<Int64, Boolean>;
    A   : TTypeAncestor;
    Nm  : string;
    Sym : TSymbol;
    procedure AddId(AId: Int64);
    begin
      if (AId > 0) and not Seen.ContainsKey(AId) then begin Seen.Add(AId, True); Ids.Add(AId); end;
    end;
  begin
    Ids  := TList<Int64>.Create;
    Seen := TDictionary<Int64, Boolean>.Create;
    try
      AddId(AClass.Id);
      for A in AStore.GetTransitiveAncestors(AClass.Id) do
        if A.Resolved and (A.SymbolId > 0) then AddId(A.SymbolId);
      for Nm in AStore.FindDescendantNames(AClass.Name) do
      begin
        Sym := BodyOf(AStore.FindSymbolByExactNameAnywhere(Nm));
        if (Sym.Id > 0) and (Sym.Kind = skClass) then AddId(Sym.Id);
      end;
      Result := Ids.ToArray;
    finally
      Ids.Free;
      Seen.Free;
    end;
  end;

  // Stamp ATypeTok onto every class in AClassIds whose child property APropName
  // exists AND is bare (empty signature). Best-effort; never overwrites an
  // explicit type (the safety rule). Returns the number of rows updated.
  function PropagateBareType(const AClassIds: TArray<Int64>;
    const APropName, ATypeTok: string): Integer;
  var
    Cid  : Int64;
    Child: TSymbol;
  begin
    Result := 0;
    for Cid in AClassIds do
    begin
      Child := AStore.FindChildSymbolByName(Cid, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) and (ParseTypeToken(Child.Signature) = '') then
        if AStore.MemoizePropertyType(Child.Id, ATypeTok) then Inc(Result);
    end;
  end;
```

- [ ] **Step 2: Extend `Walk` to compute the closure once and propagate per resolved bare property.** In `Walk`, add a local `ClosureIds: TArray<Int64>` and a `ClosureDone: Boolean` (lazy-compute on first need). Replace the memoize line (`if ViaBridge and (Prop.Id > 0) then AStore.MemoizePropertyType(Prop.Id, Tok);`) with:

```pascal
      // Persist a RECOVERED type (own signature was empty, resolved up-tree) for
      // BOTH recovery paths -- not just the bridge -- then propagate it DOWN/UP
      // across the queried class's connected tree onto every bare occurrence.
      if (OwnTok = '') and (Tok <> '') then
      begin
        if not ClosureDone then begin ClosureIds := ClosureClassIds(AClass); ClosureDone := True; end;
        PropagateBareType(ClosureIds, Prop.Name, Tok);
        // Ensure the queried row itself is stamped even if the closure walk
        // somehow missed it (e.g. name-lookup ambiguity): direct memoize.
        if Prop.Id > 0 then AStore.MemoizePropertyType(Prop.Id, Tok);
      end;
```

Declare `ClosureIds: TArray<Int64>;` and `ClosureDone: Boolean;` in `Walk`'s var block, and initialize `ClosureDone := False;` at the top of `Walk` (before the property loop). `OwnTok` and `Tok` are already locals in `Walk`.

- [ ] **Step 3: Verify uses/types are available.** Ensure the unit's uses includes `System.Generics.Collections` (for `TList<Int64>`/`TDictionary`). `TTypeAncestor`, `TSymbol`, `skClass` come from `DRagLint.Core.Model`/`Interfaces` (already used by proptree). If `FindDescendantNames` or `FindSymbolByExactNameAnywhere` is not on `ISymbolStore`, add the missing method to the interface + `TSQLiteSymbolStore` (both exist per the CLI `query descendants`/proptree usage -- confirm and only add if genuinely absent).

- [ ] **Step 4: Build the exe**

```powershell
$log = "$env:TEMP\build_unktype.log"
Start-Process -FilePath "cmd.exe" -ArgumentList '/c','build\build_draglint_win64.bat' -Wait -NoNewWindow -RedirectStandardOutput $log
Select-String -Path $log -Pattern 'BUILD_EXITCODE|\[dcc\] Error' | Select-Object -First 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 5: Run the test to verify it PASSES**

```powershell
& .\tests\autotest\run_proptree_ancestry_bridge.ps1 -Exe .\src\cli\Win64\Debug\drag-lint.exe
```
Expected: all `[PASS]` including `intermediate ... propagated`, `descendant ... propagated`, `SAFETY: ... NOT overwritten`, `idempotent`, `read-only`. Final `PASS`.

- [ ] **Step 6: Verify encoding + commit**

```powershell
$b=[IO.File]::ReadAllBytes("src\report\DRagLint.Convert.PropTree.pas"); ($b | Where-Object {$_ -gt 127}).Count
git add src/report/DRagLint.Convert.PropTree.pas
git commit -m "feat(proptree): lazy down-propagation of recovered unknown property types (bare-only, both paths)"
```
Expected: non-ASCII `0`; commit succeeds.

---

### Task 3: Regression + deploy

**Files:** none (build already done in Task 2)

- [ ] **Step 1: Run proptree + convert regressions**

```powershell
foreach ($t in 'run_proptree.ps1','run_convert_rules.ps1','run_convert_apply.ps1') {
  Write-Host "=== $t ===" -ForegroundColor Cyan
  & ".\tests\autotest\$t" -Exe .\src\cli\Win64\Debug\drag-lint.exe
}
```
Expected: each ends `PASS` (exit 0). If `run_proptree.ps1` asserts anything about a plain read NOT memoizing, that is another stale assertion -- update it to the auto-write-back default the same way (only if it fails for that reason).

- [ ] **Step 2: Deploy the exe**

```powershell
Copy-Item .\src\cli\Win64\Debug\drag-lint.exe .\third_party\dll-win64\drag-lint.exe -Force
(Get-FileHash .\src\cli\Win64\Debug\drag-lint.exe).Hash -eq (Get-FileHash .\third_party\dll-win64\drag-lint.exe).Hash
```
Expected: `True`.

- [ ] **Step 3: Commit the deployed exe if tracked+changed**

```powershell
git status --porcelain third_party/dll-win64/drag-lint.exe
# if tracked+modified:
git add third_party/dll-win64/drag-lint.exe; git commit -m "build: deploy drag-lint.exe with lazy unknown-type down-propagation"
```

---

## Self-Review

**Spec coverage:**
- "up-resolve" -> unchanged existing `ResolveInheritedType`/`ResolveViaBridgedAncestry`. ✓
- "persist BOTH paths (gap #2)" -> Task 2 Step 2 condition `if (OwnTok='') and (Tok<>'')` (no `ViaBridge` gate). ✓
- "down-propagate (gap #1)" -> Task 2 `ClosureClassIds` + `PropagateBareType`. ✓ (Rooted at queried-class closure, a robustness refinement over the spec's declaring-class rooting -- documented in Global Constraints, because the unresolved alias edge breaks downward transitivity from the declaring class.)
- "safety rule" -> `PropagateBareType` updates only `ParseTypeToken(sig)=''`. ✓ (Task 1 `TcxTypedButton` proves it.)
- "return the real type" -> unchanged (`Node.TypeName := Tok`). ✓
- "lazy, no batch pass" -> propagation fires only inside a query's `Walk`. ✓
- "idempotent / best-effort / read-only" -> reuses `MemoizePropertyType` (no-op on RO, swallows errors); Task 1 asserts idempotency + read-only. ✓

**Placeholder scan:** No TBD/TODO; all code + commands shown with expected output. ✓ (Task 2 Step 3 says "only add if genuinely absent" -- both methods are confirmed present via existing usage, so this is a guard, not a placeholder.)

**Type consistency:** `ClosureClassIds(AClass): TArray<Int64>` and `PropagateBareType(AClassIds, APropName, ATypeTok): Integer` used exactly as defined. `OwnTok`/`Tok`/`Prop`/`AClass` are existing `Walk` locals. ✓
