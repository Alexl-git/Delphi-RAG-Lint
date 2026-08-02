# Generic / Inherited Member Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hover / `typeat` on a generic-or-inherited instance member (e.g. `ATokens.Count` where `TTokenList = TList<TToken>`) resolves to the REAL member symbol (`System.Generics.Collections.TList<T>.Count`) across DBs, and never renders a wrong member.

**Architecture:** Make `TTypeAtResolver` multi-store: the store owning the hovered file is primary; all stores are searched for cross-DB type/member resolution. When a member is not a direct child of the LHS type, walk same-store ancestors, then unwrap type-aliases and match the generic base by base-name + arity across stores, resolving the member (and its own ancestry) on that base. A new `OwnerTypeFallback` result flag lets the LSP render an honest owner-type note instead of an arbitrary `Symbols[0]` when resolution genuinely fails.

**Tech Stack:** Delphi 13 (RAD Studio 37), Win64 CLI exe, SQLite index via `ISymbolStore`, PowerShell integration autotests driving the built exe.

## Global Constraints

- `.pas` files: strict 7-bit ASCII, CRLF line endings, no BOM.
- DocInsight `///` spec-comment REQUIRED on every new public declaration (the new `Resolve` overload); private helpers documented only when non-obvious.
- Block `{ }` comments MUST NOT contain `{`, `}`, or `...` (comments do not nest -- a repeated trap). Use `//` for anything naming JSON shapes or generic braces.
- Build the CLI exe with `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log; a healthy build shows `BUILD_EXITCODE=0` and no `[dcc] Error`.
- No sqlite3 CLI on this box; read DBs with `C:\Python314\python.exe` (`?mode=ro`) if needed.
- Autotests take `-Exe <path>` and default to `third_party/dll-win64/drag-lint.exe`; they are stderr-banner-sensitive (join output with newlines and regex-match).
- User HOLDS commit/push this session. The per-task "Commit" steps below stage the work; do NOT `git push`. If the user prefers, commits can be deferred to one labeled commit at the end -- confirm before committing.

## Reference: current resolver contract

`src/resolver/DRagLint.Resolver.TypeAt.pas`:

```pascal
TTypeAtResult = record
  FileName   : string    ;
  Line       : Integer   ;
  Col        : Integer   ;
  Token      : string    ;
  Containing : TSymbol   ;
  HasContain : Boolean   ;
  Resolved   : TSymbol   ;
  HasResolved: Boolean   ;
  Doc        : TParsedDoc;
  HasDoc     : Boolean   ;
  Note       : string    ;
end;

TTypeAtResolver = class
  class function Resolve(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TTypeAtResult;
  class function ExtractTokenAt(...): string;
  class function RenderText(const AResult: TTypeAtResult): string;
  class function RenderJson(const AResult: TTypeAtResult): string;
end;
```

The single-store `Resolve` body: reads the file, extracts the token + LHS at
`ALine/ACol`, finds the containing symbol, and (for `Foo.Bar` member access)
resolves `Foo` to a symbol then `FindChildSymbolByName(Foo.Id, 'Bar')`; on a
direct-child miss for a type LHS it returns the owner type with a note. This plan
generalizes that member step and makes the whole thing multi-store.

Store primitives used (all already on `ISymbolStore`):
- `FindFileIdByPath(path): Int64`
- `FindSymbolByExactNameAnywhere(name): TSymbol`
- `FindChildSymbolByName(parentId, name): TSymbol`
- `GetTransitiveAncestors(symId): TArray<TTypeAncestor>` (each has an `.Id`)
- `FindSymbolsByPrefix(prefix, limit): TArray<TSymbol>`
- `TSymbol` fields: `Id, Kind, Name, QualifiedName, Signature`; `Kind in [skClass, skRecord, skInterface, skTypeAlias, skProperty, ...]`.

---

## File Structure

- `src/resolver/DRagLint.Resolver.TypeAt.pas` -- MODIFY: add `OwnerTypeFallback` field; add multi-store `Resolve` overload; add private helpers `ParseGenericBase`, `GenericArityOfName`, `FindTypeAnywhere`, `ResolveMemberOnType`; extend `RenderJson`.
- `src/cli/DRagLint.CLI.pas` -- MODIFY: `DoTypeAt` resolves multiple `--db` and passes the store array.
- `src/lsp/DRagLint.LSP.Server.pas` -- MODIFY: `HandleHover` passes `FStores`; honor `OwnerTypeFallback`.
- `tests/autotest/run_typeat_generic_member.ps1` -- CREATE: the cross-DB + ancestry + floor regression test.

---

## Task 1: Multi-store resolver overload + `OwnerTypeFallback` flag + `typeat` multi-`--db`

Establishes the multi-store scaffolding and the honest-floor flag, WITHOUT yet adding ancestry/generic resolution. After this task: `typeat` accepts several `--db`; a symbol declared only in a second DB resolves; a member that is not a direct child of a type LHS yields `owner_type_fallback:true` in JSON (the floor), never an arbitrary symbol.

**Files:**
- Modify: `src/resolver/DRagLint.Resolver.TypeAt.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (`DoTypeAt`, ~6600-6635)
- Test: `tests/autotest/run_typeat_generic_member.ps1` (create; Task-1 checks only, more added in Tasks 2-3)

**Interfaces:**
- Produces: `class function TTypeAtResolver.Resolve(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer): TTypeAtResult;` and `TTypeAtResult.OwnerTypeFallback: Boolean`.
- Consumes: nothing new.

- [ ] **Step 1: Add the failing test (cross-store bare symbol + floor)**

Create `tests/autotest/run_typeat_generic_member.ps1`:

```powershell
# drag-lint typeat GENERIC / INHERITED member resolution regression test.
#
# Bug (live IDE): hovering an instance member that is inherited or lives on a
# generic base (e.g. ATokens.Count where TTokenList = TList<TToken>) mis-resolved
# to an arbitrary same-named symbol, because TTypeAtResolver only checked DIRECT
# children of the LHS type and was single-store (the generic base lives in a
# separate library DB).
#
# This test is HERMETIC: two synthetic DBs stand in for (project DB, library DB).
#
# Usage: pwsh -File tests/autotest/run_typeat_generic_member.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-typeat-generic"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- LIBRARY db (db B): a generic base class with a Count property + an ancestor.
$libDir = "$WorkDir\lib"; New-Item -ItemType Directory $libDir | Out-Null
@'
unit MyColl;

interface

type
  TMyEnumerable<T> = class
  public
    function ToArray: TArray<T>;
  end;

  TMyList<T> = class(TMyEnumerable<T>)
  public
    property Count: NativeInt read GetCount;
  end;

implementation

end.
'@ | Set-Content "$libDir\MyColl.pas" -Encoding ascii
$dbLib = "$WorkDir\lib.sqlite"
$idxL = & $Exe index $libDir --db $dbLib 2>&1
Check 'index lib exits 0' ($LASTEXITCODE -eq 0) (($idxL | Select-Object -Last 1))

# --- PROJECT db (db A): the alias + a consumer that does ATokens.Count.
$prjDir = "$WorkDir\prj"; New-Item -ItemType Directory $prjDir | Out-Null
$consumer = "$prjDir\Consumer.pas"
@'
unit Consumer;

interface

type
  TThing = class end;
  TThingList = TMyList<TThing>;

  TUser = class
  public
    ATokens: TThingList;
    procedure Use;
  end;

var
  GGlobalOnlyInPrj: Integer;

implementation

procedure TUser.Use;
var
  N: NativeInt;
begin
  N := ATokens.Count;
  GGlobalOnlyInPrj := N;
end;

end.
'@ | Set-Content $consumer -Encoding ascii
$dbPrj = "$WorkDir\prj.sqlite"
$idxP = & $Exe index $prjDir --db $dbPrj 2>&1
Check 'index prj exits 0' ($LASTEXITCODE -eq 0) (($idxP | Select-Object -Last 1))

$lines = Get-Content $consumer

# --- Task 1a: a bare symbol declared ONLY in db A resolves via typeat (baseline
#     multi-store sanity: proves --db is plural and the flat lookup is scanned).
$gLineText = '  GGlobalOnlyInPrj := N;'
$gIdx = [Array]::IndexOf($lines, $gLineText); Check 'located G line' ($gIdx -ge 0)
$gLine = $gIdx + 1
$gCol  = $gLineText.IndexOf('GGlobalOnlyInPrj') + 1
$gOut  = (& $Exe typeat "${consumer}:${gLine}:${gCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'bare symbol resolves (multi-db accepted)' ($gOut -match '"resolved":"Consumer\.GGlobalOnlyInPrj"') $gOut

# --- Task 1b: FLOOR -- ATokens.Count is NOT a direct child of the alias; before
#     Tasks 2-3 it must report owner_type_fallback:true (honest), NOT a wrong symbol.
$cLineText = '  N := ATokens.Count;'
$cIdx = [Array]::IndexOf($lines, $cLineText); Check 'located Count line' ($cIdx -ge 0)
$cLine = $cIdx + 1
$cCol  = $cLineText.IndexOf('.Count') + 2   # 1-based col ON the 'C' of Count
$cOut  = (& $Exe typeat "${consumer}:${cLine}:${cCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'Count is not mis-resolved to an arbitrary symbol (floor active)' `
    ($cOut -match '"owner_type_fallback":true') $cOut

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run it -- expect FAIL**

Run: `pwsh -File tests/autotest/run_typeat_generic_member.ps1`
Expected: FAIL. `typeat` today ignores the 2nd `--db` (uses `AArgs.DbPath` = last only) AND `RenderJson` has no `owner_type_fallback` key, so both new checks fail.

- [ ] **Step 3: Add the `OwnerTypeFallback` field + JSON key**

In `DRagLint.Resolver.TypeAt.pas`, add to `TTypeAtResult` (after `Note`):

```pascal
    Note              : string ;
    OwnerTypeFallback : Boolean;
    ResolvedStoreIndex: Integer;   // index into the AStores array the Resolved symbol came from; -1 if none
```

Initialize `ResolvedStoreIndex := -1` at the top of `Resolve` (the record starts
zeroed, so set it explicitly). Whenever the code assigns `Result.Resolved`, also
set `Result.ResolvedStoreIndex` to the index of the store that produced it (see the
`StoreIndexOf` helper added in Step 4). This lets `HandleHover` pick the correct
`HitStore` for a member that came from a DIFFERENT store than the hovered file
(e.g. the library DB for a generic base).

In the owner-type fallback branch (currently ~line 210-217) set it:

```pascal
      else if LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias] then
      begin
        Result.Resolved         := LhsSym;
        Result.HasResolved      := True;
        Result.OwnerTypeFallback:= True;
        Result.Note:= Format('owner type %s (member may be inherited)', [LhsSym.QualifiedName]);
      end
```

Extend `RenderJson` (currently ~line 305) to emit the key (booleans as literal true/false):

```pascal
class function TTypeAtResolver.RenderJson( const AResult: TTypeAtResult): string;
var
  Fb: string;
begin
  if AResult.OwnerTypeFallback then Fb:= 'true' else Fb:= 'false';
  Result:= Format(
    '{"file":"%s","line":%d,"col":%d,"token":"%s",' +
    '"containing":"%s","resolved":"%s","signature":"%s","note":"%s",' +
    '"owner_type_fallback":%s}', [
      StringReplace(AResult.FileName, '\', '/', [rfReplaceAll]), AResult.Line, AResult.Col, AResult.Token,
      AResult.Containing.QualifiedName, AResult.Resolved.QualifiedName,
      AResult.Resolved.Signature, AResult.Note, Fb]);
end;
```

- [ ] **Step 4: Add the multi-store `Resolve` overload; make the single-store one a wrapper**

Add to the class declaration (with DocInsight):

```pascal
    /// <summary>Resolves the symbol referenced at a file position, searching
    /// every supplied store for cross-DB type and member resolution.</summary>
    /// <param name="AStores">All open stores. The store that OWNS AFile is the
    /// primary (file-scoped lookups use it); the rest are searched only for
    /// type/member resolution. Must not be empty.</param>
    /// <returns>The resolution result. OwnerTypeFallback is True when the LHS
    /// type resolved but the member could not be found on it or any base.</returns>
    class function Resolve(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer): TTypeAtResult; overload;
    class function Resolve(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TTypeAtResult; overload;
```

Move the existing body into the array overload. Change the file-scoped store to a
`Primary` selected by ownership; change the two flat name lookups
(`FindSymbolByExactNameAnywhere` for the LHS type at ~line 190, and for the bare
identifier at ~line 247) to a new helper `FindTypeAnywhere` that returns the
symbol AND the store it came from:

```pascal
// Private helpers (implementation section, above Resolve):

function StoreIndexOf(const AStores: TArray<ISymbolStore>; const AStore: ISymbolStore): Integer;
// Index of AStore within AStores by reference; -1 if not present / nil.
var
  I: Integer;
begin
  Result:= -1;
  if AStore = nil then Exit;
  for I:= 0 to High(AStores) do
    if AStores[I] = AStore then Exit(I);
end;

function FindTypeAnywhere(const AStores: TArray<ISymbolStore>; const AName: string;
  out AStore: ISymbolStore): TSymbol;
var
  I  : Integer;
  Sym: TSymbol;
begin
  FillChar(Result, SizeOf(Result), 0);
  AStore:= nil;
  for I:= 0 to High(AStores) do
  begin
    Sym:= AStores[I].FindSymbolByExactNameAnywhere(AName);
    if Sym.Id > 0 then
    begin
      AStore:= AStores[I];
      Exit(Sym);
    end;
  end;
end;
```

At each `Result.Resolved := <sym>` assignment in the moved body, follow it with
`Result.ResolvedStoreIndex := StoreIndexOf(AStores, <the store that produced sym>)`
(for the LHS member path that store is `LhsStore`; for the bare-identifier flat
path it is the store `FindTypeAnywhere` returned; for the owner-type floor it is
`LhsStore`).

At the top of the array overload, select the primary store:

```pascal
var
  Primary: ISymbolStore;
  LhsStore: ISymbolStore;
...
  if Length(AStores) = 0 then begin Result.Note:= 'no store'; Exit; end;
  Primary:= AStores[0];
  for var si:= 0 to High(AStores) do
    if AStores[si].FindFileIdByPath(AFile) > 0 then begin Primary:= AStores[si]; Break; end;
```

Replace every `AStore.` in the moved body with `Primary.` EXCEPT the LHS/bare
name lookups, which become `FindTypeAnywhere(AStores, <name>, LhsStore)` and then
use `LhsStore` for the subsequent `FindChildSymbolByName`. (For the bare-identifier
branch, the enclosing-routine scope check stays on `Primary`; only the final flat
fallback uses `FindTypeAnywhere`.)

Add the thin wrapper:

```pascal
class function TTypeAtResolver.Resolve(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TTypeAtResult;
begin
  Result:= Resolve(TArray<ISymbolStore>.Create(AStore), AFile, ALine, ACol);
end;
```

- [ ] **Step 5: `DoTypeAt` resolves multiple `--db`**

In `DRagLint.CLI.pas` `DoTypeAt` (~6600-6635), replace the single-store open with
a store array built from all resolved DBs (mirror `DoHover`'s `ResolveConsumerDbs`):

```pascal
var Dbs: TArray<string>:= ResolveConsumerDbs(AArgs);
if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite>.'); Exit(2); end;
var Stores: TArray<ISymbolStore>;
SetLength(Stores, 0);
for var D in Dbs do
begin
  if not TFile.Exists(D) then Continue;
  var S: ISymbolStore:= TSQLiteSymbolStore.Create(D);
  S.Migrate;
  SetLength(Stores, Length(Stores) + 1);
  Stores[High(Stores)]:= S;
end;
if Length(Stores) = 0 then begin Writeln('ERROR: no usable database.'); Exit(2); end;
TAResult:= TTypeAtResolver.Resolve(Stores, FilePart, Line, Col);
```

Verify `ResolveConsumerDbs` honors repeated `--db` (it does for `hover`/`find-callers`); if `typeat`'s arg parsing only kept the last `--db`, ensure the parser appends `--db` to the same list used by `hover`. (Check `TArgs` -- the multi-db list is already populated for the consumer verbs; `typeat` just was not reading it.)

- [ ] **Step 6: Build the exe**

Run (PowerShell):
```
Start-Process -FilePath cmd.exe -ArgumentList '/c','build\build_draglint_win64.bat' -Wait -RedirectStandardOutput "$env:TEMP\bd.log" -RedirectStandardError "$env:TEMP\bd.err.log"
```
Then read `$env:TEMP\bd.log`; expect `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 7: Run the test against the freshly built exe -- expect PASS**

Run: `pwsh -File tests/autotest/run_typeat_generic_member.ps1 -Exe src\cli\Win64\Release\drag-lint.exe`
(or the path `build_draglint_win64.bat` writes; then it also copies to `third_party/dll-win64/drag-lint.exe`).
Expected: both Task-1 checks PASS (`bare symbol resolves`, `floor active`).

- [ ] **Step 8: Commit**

```bash
git add src/resolver/DRagLint.Resolver.TypeAt.pas src/cli/DRagLint.CLI.pas tests/autotest/run_typeat_generic_member.ps1
git commit -m "feat(resolver): multi-store typeat overload + OwnerTypeFallback floor flag + typeat multi--db"
```

---

## Task 2: Same-store ancestry member resolution

When a member is not a direct child of the LHS type, walk that type's transitive ancestors (in the LHS type's store) and resolve the member on an ancestor. Fixes project-internal inheritance in a single DB.

**Files:**
- Modify: `src/resolver/DRagLint.Resolver.TypeAt.pas`
- Test: `tests/autotest/run_typeat_generic_member.ps1` (add checks)

**Interfaces:**
- Produces: private `function ResolveMemberOnType(const AStore: ISymbolStore; ATypeId: Int64; const AMember: string): TSymbol;` (returns the member symbol or `Id=0`).
- Consumes: `FindTypeAnywhere` + `LhsStore` from Task 1.

- [ ] **Step 1: Add the failing ancestry check to the test**

Append to `run_typeat_generic_member.ps1` before the final summary. Add a fixture unit in the PROJECT dir with a plain (non-generic) ancestor, re-index, and hover a member that lives on the ancestor:

```powershell
# --- Task 2: project-internal inheritance -- member on a plain ancestor resolves.
@'
unit Inh;

interface

type
  TBase = class
  public
    procedure BaseOp;
  end;

  TDerived = class(TBase)
  public
    procedure DerivedOp;
  end;

implementation

procedure TBase.BaseOp; begin end;
procedure TDerived.DerivedOp;
var
  D: TDerived;
begin
  D.BaseOp;
end;

end.
'@ | Set-Content "$prjDir\Inh.pas" -Encoding ascii
$idxP2 = & $Exe index $prjDir --db $dbPrj 2>&1   # incremental reindex of prj dir
Check 'reindex prj (with Inh) exits 0' ($LASTEXITCODE -eq 0) (($idxP2 | Select-Object -Last 1))

$inh = "$prjDir\Inh.pas"
$inhLines = Get-Content $inh
$inhCallText = '  D.BaseOp;'
$inhIdx = [Array]::IndexOf($inhLines, $inhCallText); Check 'located D.BaseOp line' ($inhIdx -ge 0)
$inhLine = $inhIdx + 1
$inhCol  = $inhCallText.IndexOf('.BaseOp') + 2
$inhOut  = (& $Exe typeat "${inh}:${inhLine}:${inhCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'inherited member resolves to the ancestor method' `
    ($inhOut -match '"resolved":"Inh\.TBase\.BaseOp"') $inhOut
```

- [ ] **Step 2: Run -- expect the new check to FAIL**

Run: `pwsh -File tests/autotest/run_typeat_generic_member.ps1 -Exe <built exe>`
Expected: the ancestry check FAILs (currently `D.BaseOp` -> owner-type floor, `resolved` = `Inh.TDerived`, not `Inh.TBase.BaseOp`).

- [ ] **Step 3: Implement `ResolveMemberOnType` with an ancestry walk**

Add the helper (implementation section):

```pascal
function ResolveMemberOnType(const AStore: ISymbolStore; ATypeId: Int64; const AMember: string): TSymbol;
// Direct child first, then each transitive ancestor (same store). Id=0 if none.
var
  Anc: TArray<TTypeAncestor>;
  I  : Integer;
begin
  Result:= AStore.FindChildSymbolByName(ATypeId, AMember);
  if Result.Id > 0 then Exit;
  Anc:= AStore.GetTransitiveAncestors(ATypeId);
  for I:= 0 to High(Anc) do
  begin
    Result:= AStore.FindChildSymbolByName(Anc[I].Id, AMember);
    if Result.Id > 0 then Exit;
  end;
  FillChar(Result, SizeOf(Result), 0);
end;
```

In the member-access branch, replace the direct `FindChildSymbolByName` +
owner-type fallback (Task 1's block) with:

```pascal
      ResolvedSym:= ResolveMemberOnType(LhsStore, LhsSym.Id, Result.Token);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved          := ResolvedSym;
        Result.HasResolved       := True;
        Result.ResolvedStoreIndex:= StoreIndexOf(AStores, LhsStore);
      end
      else if LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias] then
      begin
        // GENERIC-BASE step (Task 3) will slot in HERE before the floor.
        Result.Resolved          := LhsSym;
        Result.HasResolved       := True;
        Result.OwnerTypeFallback := True;
        Result.ResolvedStoreIndex:= StoreIndexOf(AStores, LhsStore);
        Result.Note:= Format('owner type %s (member may be inherited)', [LhsSym.QualifiedName]);
      end
      else Result.Note:= 'Member ' + Result.Token + ' not found on ' + LhsSym.QualifiedName + '.';
```

- [ ] **Step 4: Build + run -- expect PASS**

Rebuild (Task 1 Step 6 recipe). Run the test. Expected: Task-1 checks still PASS, the ancestry check now PASSES.

- [ ] **Step 5: Commit**

```bash
git add src/resolver/DRagLint.Resolver.TypeAt.pas tests/autotest/run_typeat_generic_member.ps1
git commit -m "feat(resolver): resolve inherited members via same-store ancestry walk"
```

---

## Task 3: Generic-base cross-store resolution

When same-store ancestry misses and the LHS is a type-alias to a generic instantiation (`TThingList = TMyList<TThing>`), parse the base name + arity from the alias signature, find the matching generic class across ALL stores (base-name + arity, RTL-preferred on ambiguity), and resolve the member on it (including that base's own ancestors).

**Files:**
- Modify: `src/resolver/DRagLint.Resolver.TypeAt.pas`
- Test: `tests/autotest/run_typeat_generic_member.ps1` (flip the floor check to a positive resolution)

**Interfaces:**
- Produces: private `function ParseGenericBase(const ASig: string; out ABaseName: string; out AArity: Integer): Boolean;`, `function GenericArityOfName(const AName: string): Integer;`, `function FindGenericBaseAnywhere(const AStores: TArray<ISymbolStore>; const ABaseName: string; AArity: Integer; out AStore: ISymbolStore): TSymbol;`.
- Consumes: `ResolveMemberOnType` (Task 2), `FindTypeAnywhere` (Task 1).

- [ ] **Step 1: Turn the Task-1 floor check into a positive-resolution check**

In `run_typeat_generic_member.ps1`, REPLACE the Task-1b floor assertion for `ATokens.Count` with the real expectation (keep a separate genuinely-unresolvable floor check, added below):

```powershell
# --- Task 3: ATokens.Count -> the generic base's Count property, cross-DB.
Check 'ATokens.Count resolves to the generic base Count property' `
    ($cOut -match '"resolved":"MyColl\.TMyList<T>\.Count"') $cOut
Check 'and shows the real signature' ($cOut -match '"signature":"NativeInt"') $cOut

# --- Floor still honest for a genuinely-absent member.
$absText = '  N := ATokens.Count;'   # reuse the line; probe a bogus member name via a new site
@'
unit NoSuch;
interface
type
  TThing2 = class end;
  TList2 = TMyList<TThing2>;
  TU2 = class procedure P; end;
implementation
procedure TU2.P;
var L: TList2;
begin
  L.Nonexistent;
end;
end.
'@ | Set-Content "$prjDir\NoSuch.pas" -Encoding ascii
& $Exe index $prjDir --db $dbPrj 2>&1 | Out-Null
$ns = "$prjDir\NoSuch.pas"; $nsLines = Get-Content $ns
$nsText = '  L.Nonexistent;'
$nsLine = [Array]::IndexOf($nsLines, $nsText) + 1
$nsCol  = $nsText.IndexOf('.Nonexistent') + 2
$nsOut  = (& $Exe typeat "${ns}:${nsLine}:${nsCol}" --db $dbPrj --db $dbLib --format json 2>&1) -join "`n"
Check 'absent member -> honest owner-type floor (not a wrong symbol)' `
    ($nsOut -match '"owner_type_fallback":true') $nsOut
```

- [ ] **Step 2: Run -- expect the generic-resolution checks to FAIL**

Expected: `ATokens.Count` still hits the floor (`owner_type_fallback:true`), so the two positive checks FAIL; the absent-member floor check PASSES.

- [ ] **Step 3: Implement the generic-base helpers**

```pascal
function ParseGenericBase(const ASig: string; out ABaseName: string; out AArity: Integer): Boolean;
// 'TList<TToken>' -> ('TList', 1); 'TDictionary<TKey, TList<T>>' -> ('TDictionary', 2).
// AArity = 1 + count of TOP-LEVEL commas inside the OUTERMOST <...>. False when no '<'.
var
  I, Depth, Lt: Integer;
begin
  Result:= False; ABaseName:= ''; AArity:= 0;
  Lt:= Pos('<', ASig);
  if Lt <= 1 then Exit;
  ABaseName:= Trim(Copy(ASig, 1, Lt - 1));
  if ABaseName = '' then Exit;
  AArity:= 1; Depth:= 0;
  for I:= Lt to Length(ASig) do
  begin
    case ASig[I] of
      '<': Inc(Depth);
      '>': begin Dec(Depth); if Depth = 0 then Break; end;
      ',': if Depth = 1 then Inc(AArity);
    end;
  end;
  Result:= True;
end;

function GenericArityOfName(const AName: string): Integer;
// Arity of a symbol NAME like 'TList<T>' or 'TDictionary<TKey, TValue>'; 0 if non-generic.
var
  Dummy: string;
begin
  if not ParseGenericBase(AName, Dummy, Result) then Result:= 0;
end;

function FindGenericBaseAnywhere(const AStores: TArray<ISymbolStore>; const ABaseName: string;
  AArity: Integer; out AStore: ISymbolStore): TSymbol;
// Find a class/interface named ABaseName + '<...>' with matching arity across all
// stores. Prefer a System.* qname on ambiguity, else first in store order.
var
  I, J: Integer;
  Cands: TArray<TSymbol>;
  Best : TSymbol;
  BestStore: ISymbolStore;
  HaveBest : Boolean;
begin
  FillChar(Result, SizeOf(Result), 0); AStore:= nil;
  HaveBest:= False; FillChar(Best, SizeOf(Best), 0); BestStore:= nil;
  for I:= 0 to High(AStores) do
  begin
    Cands:= AStores[I].FindSymbolsByPrefix(ABaseName + '<', 200);
    for J:= 0 to High(Cands) do
    begin
      if not (Cands[J].Kind in [skClass, skInterface]) then Continue;
      if GenericArityOfName(Cands[J].Name) <> AArity then Continue;
      if not HaveBest then
      begin
        Best:= Cands[J]; BestStore:= AStores[I]; HaveBest:= True;
      end
      else if (not StartsText('System.', Best.QualifiedName))
           and StartsText('System.', Cands[J].QualifiedName) then
      begin
        // RTL-preferred disambiguation.
        Best:= Cands[J]; BestStore:= AStores[I];
      end;
    end;
  end;
  if HaveBest then begin Result:= Best; AStore:= BestStore; end;
end;
```

Add `System.StrUtils` to the uses clause for `StartsText`/`StringReplace` if not
already present (`StringReplace` is in `System.SysUtils`, already used; `StartsText`
is in `System.StrUtils`).

- [ ] **Step 4: Wire the generic step into the member branch (before the floor)**

This step restructures the Task-2 block so the generic step runs BEFORE the floor.
Replace the entire `else if LhsSym.Kind in [...]` branch from Task 2 with:

```pascal
      else if LhsSym.Kind in [skClass, skRecord, skInterface, skTypeAlias] then
      begin
        // Alias to a generic instantiation? Unwrap the signature, match the
        // generic base by (name, arity) across stores, resolve the member there
        // (incl. that base's own ancestors via ResolveMemberOnType).
        var GBase: string;
        var GArity: Integer;
        var GenStore: ISymbolStore;
        if (LhsSym.Kind = skTypeAlias) and ParseGenericBase(LhsSym.Signature, GBase, GArity) then
        begin
          var BaseSym: TSymbol:= FindGenericBaseAnywhere(AStores, GBase, GArity, GenStore);
          if BaseSym.Id > 0 then
          begin
            var Mem: TSymbol:= ResolveMemberOnType(GenStore, BaseSym.Id, Result.Token);
            if Mem.Id > 0 then
            begin
              Result.Resolved          := Mem;
              Result.HasResolved       := True;
              Result.OwnerTypeFallback := False;
              Result.ResolvedStoreIndex:= StoreIndexOf(AStores, GenStore);
              Result.Note:= Format('resolved via generic base %s', [BaseSym.QualifiedName]);
            end;
          end;
        end;
        // Floor -- only if the generic step did not resolve.
        if not Result.HasResolved then
        begin
          Result.Resolved          := LhsSym;
          Result.HasResolved       := True;
          Result.OwnerTypeFallback := True;
          Result.ResolvedStoreIndex:= StoreIndexOf(AStores, LhsStore);
          Result.Note:= Format('owner type %s (member may be inherited)', [LhsSym.QualifiedName]);
        end;
      end
      else Result.Note:= 'Member ' + Result.Token + ' not found on ' + LhsSym.QualifiedName + '.';
```

YAGNI: no separate ambiguity note this increment -- `FindGenericBaseAnywhere`
already applies the RTL-preferred rule internally; `Result.Note` just names the
chosen base. Non-alias generic LHS (a variable whose own type name is itself
generic, not via an alias) is left for D5 -- not needed for the motivating case.

- [ ] **Step 5: Build + run -- expect all checks PASS**

Rebuild. Run the full `run_typeat_generic_member.ps1`. Expected: cross-DB
`ATokens.Count -> MyColl.TMyList<T>.Count` + `signature NativeInt` PASS; the
ancestry check (Task 2) PASS; the absent-member floor PASS; the bare-symbol
multi-db check PASS.

- [ ] **Step 6: Commit**

```bash
git add src/resolver/DRagLint.Resolver.TypeAt.pas tests/autotest/run_typeat_generic_member.ps1
git commit -m "feat(resolver): cross-store generic-base member resolution (alias unwrap + base+arity match)"
```

---

## Task 4: LSP HandleHover -- pass all stores + honor the floor

Make the live-IDE hover path use the new capability: pass `FStores` to the resolver, and when it returns the honest owner-type floor, render that instead of falling back to an arbitrary `Symbols[0]`.

**Files:**
- Modify: `src/lsp/DRagLint.LSP.Server.pas` (`HandleHover`, ~950-1050)
- Verify: `tests/autotest/run_hover_callsite.ps1` (existing regression stays green)

**Interfaces:**
- Consumes: `TTypeAtResolver.Resolve(FStores, ...)` and `TTypeAtResult.OwnerTypeFallback`.

- [ ] **Step 1: Pass `FStores` at both resolver call sites**

At ~line 976 (the call-site disambiguation) change:
```pascal
        var TAR:= TTypeAtResolver.Resolve(HomeStore, Path, Line + 1, Col + 1);
```
to pass the whole store set (the HomeStore anchoring still happens INSIDE the
resolver via file ownership):
```pascal
        var TAR:= TTypeAtResolver.Resolve(FStores, Path, Line + 1, Col + 1);
```
At ~line 1038 (no-doc narrowing) change:
```pascal
        var TAResult:= TTypeAtResolver.Resolve( HitStore, Path, Line + 1, Col + 1);
```
to:
```pascal
        var TAResult:= TTypeAtResolver.Resolve( FStores, Path, Line + 1, Col + 1);
```

- [ ] **Step 2: Honor `OwnerTypeFallback` in the disambiguation block**

In the `if (not FoundDeclImpl) and (Length(Symbols) > 1)` block (~965-984),
extend the accept condition so a fully-resolved member overrides `Sel` (using
`ResolvedStoreIndex` to pick the correct `HitStore` -- the member may live in the
library store, not the hovered file's store), and an owner-type floor sets a flag
the code below uses to render honestly rather than leaving `Sel = Symbols[0]`.

Replace the current block body:

```pascal
        var TAR:= TTypeAtResolver.Resolve(FStores, Path, Line + 1, Col + 1);
        if TAR.HasResolved and (TAR.Resolved.Id > 0) and SameText(TAR.Resolved.Name, Ident) then
        begin
          // Full resolution (incl. generic/inherited members): take the real symbol
          // and switch HitStore to the store it actually came from.
          Sel:= TAR.Resolved;
          if (TAR.ResolvedStoreIndex >= 0) and (TAR.ResolvedStoreIndex <= High(FStores)) then
          begin
            HitStore:= FStores[TAR.ResolvedStoreIndex];
            Symbols := HitStore.FindSymbolsByExactName(Ident);
          end;
        end
        else if TAR.HasResolved and TAR.OwnerTypeFallback and (TAR.Resolved.Id > 0) then
        begin
          // Honest floor: remember the owner type so the render path below shows
          // "Type.Member -- inherited member; owner type QName" instead of the
          // arbitrary Symbols[0].
          OwnerFloorType := TAR.Resolved;     // new local TSymbol, declared above
          HaveOwnerFloor := True;             // new local Boolean, declared above
        end;
```

Declare two locals near the top of `HandleHover` (with the other hover locals):
`var OwnerFloorType: TSymbol;` and `var HaveOwnerFloor: Boolean;` initialized
`HaveOwnerFloor := False;`.

Then, at the point where the handler decides what markdown to emit (just before the
`Doc:= HitStore.GetSymbolDoc(Sel.Id);` block, ~line 1014), add a short-circuit:

```pascal
    if HaveOwnerFloor then
    begin
      MdValue:= Format('%s.%s'#10#10'_inherited member; owner type_ `%s`',
        [OwnerFloorType.Name, Ident, OwnerFloorType.QualifiedName]);
      // fall through to the SAME response-send code the success path uses with MdValue.
    end
    else
    begin
      // ... existing Doc.HasContent / no-doc rendering that assigns MdValue ...
    end;
```

Keep the existing response-transport code (the JSON-RPC reply that wraps `MdValue`)
as the single send site -- do not duplicate it. If the existing structure makes an
`if/else` awkward, guard the existing render block with `if not HaveOwnerFloor` and
set `MdValue` in the floor case before it; the goal is exactly one place that sends
`MdValue`.

- [ ] **Step 3: Build the exe (LSP is in the same exe)**

Rebuild via `build/build_draglint_win64.bat`. Expect `BUILD_EXITCODE=0`.

- [ ] **Step 4: Run the existing hover regression + the new typeat test**

Run:
```
pwsh -File tests/autotest/run_hover_callsite.ps1 -Exe <built exe>
pwsh -File tests/autotest/run_typeat_generic_member.ps1 -Exe <built exe>
pwsh -File tests/autotest/run_typeat_scope.ps1 -Exe <built exe>
```
Expected: all PASS (callsite regression green proves the FStores change did not
break single-store call-site resolution; scope test green proves the multi-store
refactor preserved param/local scoping).

- [ ] **Step 5: Commit**

```bash
git add src/lsp/DRagLint.LSP.Server.pas
git commit -m "feat(lsp): hover passes all stores to resolver + renders honest owner-type floor"
```

---

## Task 5: Full battery + deploy + live verification

**Files:** none (verification + deploy).

- [ ] **Step 1: Run the whole autotest battery**

Run the battery runner (the repo's aggregate; e.g. `tests/autotest/run_all.ps1` if
present, else run each `run_*.ps1`). Expected: no regressions vs the pre-change
baseline. Record the pass count.

- [ ] **Step 2: Deploy the CLI exe (IDE CLOSED)**

Confirm no `bds.exe` / live LSP `drag-lint.exe` is running (they lock the exe).
`build/build_draglint_win64.bat` copies to `third_party/dll-win64/drag-lint.exe`;
verify the deployed exe's `--version`.

- [ ] **Step 3: Live-IDE verification (user)**

User reopens RAD Studio, restarts the LSP so the new exe is spawned, hovers
`ATokens.Count` in YADF -> expect `TMyList/TList<T>.Count : NativeInt` (real
signature), and confirms an inherited member and an unresolvable member both read
honestly (no arbitrary wrong symbol).

- [ ] **Step 4: (Deferred to the combined session) reindex note**

Resolution is index-READ only -- no reindex needed for item #2. (Items #1/#3 are
UI-only.) Reindex is only relevant after `document --apply` line shifts, which this
work does not do.

---

## Self-Review notes (already reconciled against the spec)

- Spec "multi-store `TTypeAtResolver`" -> Task 1 (overload + wrapper).
- Spec "same-store ancestry" -> Task 2.
- Spec "alias unwrap -> generic base (cross-store)" + "match by base-name + arity" + "RTL-preferred disambiguation" -> Task 3.
- Spec "`OwnerTypeFallback` field + HandleHover honors it" -> Task 1 (field) + Task 4 (HandleHover).
- Spec "`typeat` multi-`--db`, battery-testable" -> Task 1 Step 5 + the whole `run_typeat_generic_member.ps1`.
- Spec testing: cross-DB positive (Task 3), same-store ancestry (Task 2), floor (Task 3), regression (Task 4 Step 4), live verify (Task 5).
- Non-goal (uses-closure disambiguation, `.Count` caller scoping) -> not implemented; RTL-preferred heuristic used instead, as specified.
