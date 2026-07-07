# Batch A Implementation Plan — forms-csv multi-DB, AutoDoc returns enumeration, AutoDoc facts multi-DB

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed forms-csv and AutoDoc the full manifest DB set so cross-DB relationships resolve, and enumerate real return cases in generated `<returns>` docs.

**Architecture:** Reuse the proven `ResolveConsumerDbs` + multi-store aggregation idiom (as `query find-callers` / `hover` already do) in two consumers that currently open a single DB (forms-csv engine, AutoDoc facts builder). Independently, reuse the pure `MineReturnExpressions` hover miner inside AutoDoc's facts builder, gated by a new `drag-lint.json` docs config key.

**Tech Stack:** Delphi 13 (RAD Studio 37, Win32 CLI + Win64 CLI + Win32 IDE BPL), FireDAC + SQLite, DUnitX where present, PowerShell `run_*.ps1` autotests, `System.JSON`.

## Global Constraints

- **Encoding:** all `.pas` files strict 7-bit ASCII, CRLF line endings. No Unicode, no BOM, no LF. (CLAUDE.md)
- **DocInsight (CDD):** every NEW public type/method/interface gets a `///` `<summary>`/`<param>`/`<returns>`/`<remarks>` spec-comment. Private helpers only when an invariant is non-obvious. (CLAUDE.md)
- **TDD:** failing test first, then implement to green. The doc-comment and the test must agree.
- **Build recipe:** use the `delphi-build` skill. CLI = `src/cli/DRagLint.CLI.dproj` (build Win64 for the test exe `src/cli/Win64/Debug/drag-lint.exe`; also Win32 if a 32-bit consumer needs it). IDE BPL = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio CLOSED (check `Get-Process bds`), via `_bpl_build.bat`.
- **Reindex after symbol-changing builds** only incrementally; don't full-rescan.
- **Commit cadence:** one commit per task (per the step). BPL/DCP binaries go in a SEPARATE `build(plugin):` commit, never mixed with source (v0.88 convention).
- **Autotest naming:** a `tests/autotest/run_*.ps1` script IS a battery member by naming + the `Check`/`$script:Failed`/exit-code convention. Pin the exe to `src/cli/Win64/Debug/drag-lint.exe` (or accept `-Exe`).
- **Implementation order:** Item 3 (Tasks 1-4) → Item 2 (Tasks 5-6) → Item 1 (Tasks 7-10). Item 3 establishes the multi-store fan-out that item 2 mirrors.
- **Signature-growth contract (avoid parameter-order drift):** `TDocFactsBuilder.Build` and `TDocumenter.BuildFor`/the batch driver each gain TWO new optional params across this batch, in this exact positional order: first `const AExtraStores: TArray<ISymbolStore> = nil` (Tasks 5/6), then `AMaxReturnCases: Integer = 20` AFTER it (Tasks 8/10). When Task 5/6 add `AExtraStores`, leave room for `AMaxReturnCases` to be appended last — do NOT insert it before `AExtraStores` later. Final order for all three: `(...existing..., AExtraStores, AMaxReturnCases)`. All new params are trailing + defaulted, so every pre-existing call site keeps compiling untouched.

---

## File Structure

**Item 3 (forms-csv multi-DB):**
- `src/forms/DRagLint.FormsMap.pas` — engine. `GenerateFormsCsv` gains a DB-list overload; `FindNearestFormCaller` / `FindFormViaHook` gain an `AExtraStores` param and fan their `refs` query across stores.
- `src/cli/DRagLint.CLI.pas` — `DoFormsCsv` passes all `DbPaths` (resolve if none).
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — `InvokeGenerateFormsCsv` emits multi-`--db` + exe-version guard.
- `tests/autotest/run_formsmap_multidb.ps1` — NEW two-DB regression test.

**Item 2 (AutoDoc facts multi-DB):**
- `src/doc/DRagLint.Doc.Facts.pas` — `Build` gains optional `AExtraStores`; the 3 caller-facing queries merge across stores.
- `src/doc/DRagLint.Doc.Document.pas`, `src/doc/DRagLint.Doc.Batch.pas` — thread the param.
- `src/cli/DRagLint.CLI.pas` — document verbs resolve + open + pass extra stores.
- `tests/autotest/run_doc_multidb.ps1` — NEW.

**Item 1 (returns enumeration + docs config):**
- `src/index/DRagLint.Index.Manifest.pas` — new `TDocSettings` sub-record + parse/emit/validate.
- `src/doc/DRagLint.Doc.Facts.pas` — mine `ReturnCases` (reuse `MineReturnExpressions`), apply cap.
- `src/doc/DRagLint.Doc.Regions.pas` — emit `Observed:` in `<returns>`.
- `src/cli/DRagLint.CLI.pas` — pass manifest docs cap into the doc build path.
- `tests/autotest/run_doc_returns.ps1` — NEW.

---

## Existing interfaces this plan consumes (verbatim)

```pascal
// DRagLint.Hover.Returns.pas
function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;

// DRagLint.Doc.Facts.pas
TDocFacts = record
  CalledFrom: TArray<TDocFactRef>; Calls: TArray<string>; UsedInUnits: TArray<string>;
  Raises: TArray<string>; ReturnType: string;
  CalledFromTotal, CallsTotal, UsedInTotal: Integer;
  Deprecated: Boolean; DeprecatedMsg: string; SeeAlso: TArray<string>; Since: string;
end;
class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False;
  const ABaseDir: string = ''): TDocFacts;

// DRagLint.Doc.Regions.pas
class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;

// DRagLint.FormsMap.pas
function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
function FindNearestFormCaller(AStore: TSQLiteSymbolStore; const AOwnerClass, ARoutine: string;
  AClassToNode: TDictionary<string, TFormNode>; APasLines: TDictionary<Int64, TArray<string>>;
  AVisited: TDictionary<string, Boolean>; out AFormClass, AFormRoutine: string): Boolean;
// FindFormViaHook has the same AStore-first shape (FormsMap.pas:615).

// ISymbolStore (DRagLint.Core.Interfaces.pas) caller-facing queries used by Build:
//   FindResolvedCallers(ASymId): TArray<...>          (Facts.pas:396)
//   FindUnresolvedNameCallers(AName): TArray<...>      (Facts.pas:404)
//   FindCallersByName(AName): TArray<...>              (Facts.pas:526, used-in)

// DRagLint.CLI.pas
function ResolveConsumerDbs(const AArgs: TArgs): TArray<string>;  // forward at :417
function OpenReadOnlyStore(const ADbPath: string; out AOk: Boolean): ISymbolStore;  // :871

// DRagLint.Index.Manifest.pas
TIndexManifest = record RootDir: string; Settings: TIndexSettings; ... end;
class function TManifestIO.ParseTextEx(const AJson, ARootDir: string; out ASettingsKeys: TSettingsKeySet): TIndexManifest;
```

---

# ITEM 3 — forms-csv multi-DB (Tasks 1-4)

### Task 1: Engine — multi-store caller resolution in `FindNearestFormCaller` / `FindFormViaHook`

**Files:**
- Modify: `src/forms/DRagLint.FormsMap.pas` (`FindNearestFormCaller` ~:517-599; `FindFormViaHook` ~:615-690; and the two hook/edge call sites in `BuildEdges` ~:899, :953 that call `FindNearestFormCaller`)
- Test: `tests/autotest/run_formsmap_multidb.ps1` (created in Task 4; Task 1's own verification is the CLI build + existing `run_formsmap.ps1` staying green)

**Interfaces:**
- Produces: `FindNearestFormCaller(AStore; const AOwnerClass, ARoutine; AClassToNode; APasLines; AVisited; const AExtraStores: TArray<TSQLiteSymbolStore>; out AFormClass, AFormRoutine): Boolean;` — new 6th positional param `AExtraStores` before the `out` params. Same for `FindFormViaHook`. Empty `AExtraStores` = today's single-store behavior byte-for-byte.

- [ ] **Step 1: Add a private helper that runs the name-caller `refs` query across a store list**

In `DRagLint.FormsMap.pas`, add above `FindNearestFormCaller`:

```pascal
/// <summary>Runs the bare-name caller `refs` query for ARoutine against the
/// primary store PLUS every store in AExtraStores, appending (file_id, start_line,
/// path) rows from each. Multi-DB scope: a call site may live in a different index
/// (e.g. COMMON) than the form being resolved. Rows are NOT deduped here -- the
/// caller's AVisited set already prevents re-walking the same (owner.routine).</summary>
/// <param name="APrimary">The project store (owns form enumeration); queried first.</param>
/// <param name="AExtraStores">Additional caller-search-scope stores; may be empty.</param>
/// <param name="ARoutine">Bare method name to match on refs.name_text.</param>
/// <returns>All matching ref rows across the stores.</returns>
type
  TCallerRefRow = record FileId: Int64; StartLine: Integer; Path: string; Store: TSQLiteSymbolStore; end;

function QueryNameCallerRows(APrimary: TSQLiteSymbolStore;
  const AExtraStores: TArray<TSQLiteSymbolStore>; const ARoutine: string): TArray<TCallerRefRow>;
var
  Stores: TArray<TSQLiteSymbolStore>;
  St    : TSQLiteSymbolStore;
  Q     : TFDQuery;
  Rows  : TList<TCallerRefRow>;
  Row   : TCallerRefRow;
begin
  Rows:= TList<TCallerRefRow>.Create;
  try
    Stores:= [APrimary];
    for St in AExtraStores do Stores:= Stores + [St];
    for St in Stores do
    begin
      if St = nil then Continue;
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= St.GetConnection;
        Q.SQL.Text:=
          'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
          'FROM refs r JOIN files f ON f.id = r.file_id ' +
          'WHERE r.name_text = :rout AND f.language LIKE ''delphi%''';
        Q.ParamByName('rout').AsString:= ARoutine;
        Q.Open;
        while not Q.Eof do
        begin
          Row.FileId   := Q.FieldByName('fid').AsLargeInt;
          Row.StartLine:= Q.FieldByName('sl' ).AsInteger;
          Row.Path     := Q.FieldByName('p'  ).AsString;
          Row.Store    := St;
          Rows.Add(Row);
          Q.Next;
        end;
      finally
        Q.Free;
      end;
    end;
    Result:= Rows.ToArray;
  finally
    Rows.Free;
  end;
end;
```

- [ ] **Step 2: Rewrite `FindNearestFormCaller` to use the helper + thread `AExtraStores`**

Change the signature to add `const AExtraStores: TArray<TSQLiteSymbolStore>` as the parameter immediately before `out AFormClass`. Replace the inline `Q` query body (the `Q:= TFDQuery.Create` ... `while not Q.Eof` loop, ~:542-595) with iteration over `QueryNameCallerRows`. The `APasLines` file-read (keyed on FileId+Path), `FindEnclosingImpl`, `AClassToNode.ContainsKey`, and recursion stay identical — but the recursive call now passes `AExtraStores` through, and `APasLines` reads use `Row.Path`:

```pascal
function FindNearestFormCaller(
  AStore       : TSQLiteSymbolStore;
  const AOwnerClass, ARoutine: string;
  AClassToNode : TDictionary<string, TFormNode>;
  APasLines    : TDictionary<Int64, TArray<string>>;
  AVisited     : TDictionary<string, Boolean>;
  const AExtraStores: TArray<TSQLiteSymbolStore>;
  out AFormClass  : string;
  out AFormRoutine: string
): Boolean;
var
  Key: string; Rows: TArray<TCallerRefRow>; R: TCallerRefRow;
  Arr: TArray<string>; COwner, CRout: string;
begin
  Result:= False; AFormClass:= ''; AFormRoutine:= '';
  Key:= AOwnerClass + '.' + ARoutine;
  if AVisited.ContainsKey(Key) then Exit;
  AVisited.Add(Key, True);
  Rows:= QueryNameCallerRows(AStore, AExtraStores, ARoutine);
  for R in Rows do
  begin
    if not APasLines.TryGetValue(R.FileId, Arr) then
    begin
      if TFile.Exists(R.Path) then Arr:= TFile.ReadAllLines(R.Path, TEncoding.ANSI) else Arr:= [];
      APasLines.Add(R.FileId, Arr);
    end;
    COwner:= ''; CRout:= '';
    if (R.StartLine >= 1) and (R.StartLine <= Length(Arr)) and
       FindEnclosingImpl(Arr, R.StartLine, COwner, CRout) and (COwner <> '') and (CRout <> '') then
    begin
      if AClassToNode.ContainsKey(COwner) then
      begin AFormClass:= COwner; AFormRoutine:= CRout; Exit(True); end
      else if FindNearestFormCaller(AStore, COwner, CRout, AClassToNode, APasLines,
                                    AVisited, AExtraStores, AFormClass, AFormRoutine) then Exit(True);
    end;
  end;
end;
```

> NOTE on `APasLines` FileId collision: FileIds are per-DB, so two stores could share a FileId for different files. The cache key must therefore be path-based when extra stores are present. Change `APasLines` to key on `R.Path` (string) instead of FileId to be collision-safe. Update the dictionary type at every declaration site to `TDictionary<string, TArray<string>>` and key all `.TryGetValue`/`.Add` on the path. (There are ~4 such dictionaries created in `BuildEdges`/`GenerateFormsCsv`; grep `TDictionary<Int64, TArray<string>>` in this file and convert each.)

- [ ] **Step 3: Apply the same `AExtraStores` threading to `FindFormViaHook`**

`FindFormViaHook` (~:615) has the same `AStore`-first shape and its own `refs`/hook query. Add `const AExtraStores: TArray<TSQLiteSymbolStore>` in the same position, and where it resolves caller/invocation sites, run them across stores via `QueryNameCallerRows` (or, for the hook-field-specific query, an analogous cross-store loop). Thread `AExtraStores` into any recursive/`FindNearestFormCaller` call it makes.

- [ ] **Step 4: Update the `FindNearestFormCaller`/`FindFormViaHook` call sites in `BuildEdges`**

At ~:899, :907, :953 (grep `FindNearestFormCaller(` and `FindFormViaHook(` in this file), add the `AExtraStores` argument. `BuildEdges` must receive the extra-store list too — add `const AExtraStores: TArray<TSQLiteSymbolStore>` to `BuildEdges` (~:696) and pass it down.

- [ ] **Step 5: Build the CLI (Win64) to verify it compiles**

Use the delphi-build skill: build `src/cli/DRagLint.CLI.dproj` Win64 Debug. Expected: `Build succeeded`, 0 Error(s). (Also Win32 if the plugin links FormsMap — it does not; the plugin shells out to the exe, so Win64 exe is the deliverable.)

- [ ] **Step 6: Run the existing forms map test to confirm no single-DB regression**

Run: `pwsh -File tests/autotest/run_formsmap.ps1`
Expected: `PASS` (single-DB behavior unchanged — `AExtraStores` empty at every existing call site until Task 2/3 wire the list; the fixture project is one DB).

- [ ] **Step 7: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas
git commit -m "feat(forms-csv): caller resolution can span multiple index DBs (AExtraStores)"
```

---

### Task 2: Engine entry — `GenerateFormsCsv` DB-list overload

**Files:**
- Modify: `src/forms/DRagLint.FormsMap.pas` (`GenerateFormsCsv` :65; the body that opens the store + calls `LoadInventory`/`BuildEdges`)

**Interfaces:**
- Produces: `function GenerateFormsCsv(const ADbPaths: TArray<string>; const AProjectFile, ARootForm: string): string; overload;` — `ADbPaths[0]` authoritative for form enumeration + PAS lines; `ADbPaths[1..]` caller search scope. Keep the existing single-path `GenerateFormsCsv(const ADbPath, ...)` as a thin overload calling the new one with `[ADbPath]` (back-compat for any other caller/test).

- [ ] **Step 1: Add the DB-list overload**

Read the current `GenerateFormsCsv` body. It opens one `TSQLiteSymbolStore` on `ADbPath`, builds the inventory, edges, and renders. Refactor:

```pascal
function GenerateFormsCsv(const ADbPaths: TArray<string>; const AProjectFile, ARootForm: string): string; overload;
var
  Primary: TSQLiteSymbolStore;
  Extras : TArray<TSQLiteSymbolStore>;
  I      : Integer;
begin
  if Length(ADbPaths) = 0 then raise Exception.Create('forms-csv: no DB paths');
  Primary:= TSQLiteSymbolStore.Create(ADbPaths[0]);   // match existing construction idiom in this unit
  try
    SetLength(Extras, 0);
    for I:= 1 to High(ADbPaths) do
      Extras:= Extras + [TSQLiteSymbolStore.Create(ADbPaths[I])];
    try
      Result:= GenerateFormsCsvCore(Primary, Extras, AProjectFile, ARootForm);  // the existing body, extracted
    finally
      for var St in Extras do St.Free;
    end;
  finally
    Primary.Free;
  end;
end;

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string; overload;
begin
  Result:= GenerateFormsCsv([ADbPath], AProjectFile, ARootForm);
end;
```

Extract the existing single-store body into `GenerateFormsCsvCore(APrimary: TSQLiteSymbolStore; const AExtras: TArray<TSQLiteSymbolStore>; const AProjectFile, ARootForm: string): string;` and thread `AExtras` into the `BuildEdges(APrimary, ..., AExtras)` call. `LoadInventory`, `IsNavigableForm`, `CaptionForHandler`, `FindComponent` stay on `APrimary` only (project-scoped).

> Match the exact `TSQLiteSymbolStore` construction/open pattern already used in the current `GenerateFormsCsv` body (read it first — it may open read-only or via a factory). Do not invent a constructor.

- [ ] **Step 2: Add DocInsight to the new overload**

```pascal
/// <summary>Generates the forms navigation-map CSV. ADbPaths[0] is the project
/// index (drives which forms are enumerated + PAS-line counts); ADbPaths[1..] are
/// additional indexes searched ONLY to resolve callers/landings whose call site
/// lives in another DB (e.g. COMMON). A form with no caller in ANY store is DEAD.</summary>
/// <param name="ADbPaths">1+ SQLite index paths; [0] authoritative, rest search-scope.</param>
/// <param name="AProjectFile">Project (.dpr/.dproj) whose units scope the inventory.</param>
/// <param name="ARootForm">Root form class (e.g. TfrmMAIN); '' = auto-detect.</param>
/// <returns>ANSI CSV text incl. the FORMS_CSV_ALGORITHM provenance footer.</returns>
```

- [ ] **Step 3: Build the CLI (Win64), expect 0 errors** (delphi-build skill).

- [ ] **Step 4: Run `run_formsmap.ps1`, expect PASS** (single-path overload reproduces old behavior).

- [ ] **Step 5: Commit**

```bash
git add src/forms/DRagLint.FormsMap.pas
git commit -m "feat(forms-csv): GenerateFormsCsv DB-list overload (primary + caller-scope stores)"
```

---

### Task 3: CLI + IDE wiring

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (`DoFormsCsv` :9670-9687)
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (`InvokeGenerateFormsCsv` ~:2255-2318; add exe-version guard)

**Interfaces:**
- Consumes: `GenerateFormsCsv(ADbPaths, AProjectFile, ARootForm)` (Task 2); `ResolveConsumerDbs` (CLI :417).

- [ ] **Step 1: `DoFormsCsv` passes all DB paths / resolves**

Replace the `DbPath := AArgs.DbPaths[0]` selection:

```pascal
function DoFormsCsv(const AArgs: TArgs): Integer;
var
  DbPaths: TArray<string>;
  Csv    : string;
  P      : string;
begin
  if Length(AArgs.DbPaths) > 0 then DbPaths:= AArgs.DbPaths
  else if AArgs.DbPath <> '' then DbPaths:= [AArgs.DbPath]
  else DbPaths:= ResolveConsumerDbs(AArgs);
  if Length(DbPaths) = 0 then begin Writeln(ErrOutput, 'forms-csv: need --db <index.sqlite>'); Exit(2); end;
  for P in DbPaths do
    if not TFile.Exists(P) then begin Writeln(ErrOutput, 'forms-csv: db not found: ', P); Exit(2); end;
  try
    Csv:= DRagLint.FormsMap.GenerateFormsCsv(DbPaths, AArgs.ProjectPath, AArgs.RootForm);
  except
    on E: Exception do begin Writeln(ErrOutput, 'forms-csv: ', E.Message); Exit(1); end;
  end;
  if AArgs.Output <> '' then begin TFile.WriteAllText(AArgs.Output, Csv, TEncoding.ANSI); Writeln('forms-csv: wrote ', AArgs.Output); end
  else Write(Csv);
  Result:= 0;
end;
```

- [ ] **Step 2: IDE menu emits multi-`--db`**

In `InvokeGenerateFormsCsv` (Editor.pas), replace the single-DB command build (`ProjDb := GetActiveProjectDb; CmdLine := Format('... --db "%s" ...', [..., ProjDb, ...])`, ~:2275/:2298) with a project-DB-first, multi-`--db` command using `ResolveActiveIndexDbs(LoadSettings)`:

```pascal
  ProjDb := GetActiveProjectDb;
  var DbList: TArray<string>;
  try DbList := ResolveActiveIndexDbs(LoadSettings); except SetLength(DbList, 0); end;
  // Ensure the project DB is FIRST (authoritative for form enumeration).
  var DbArgs: string := '';
  if (ProjDb <> '') then DbArgs := Format(' --db "%s"', [ProjDb]);
  for var D in DbList do
    if not SameText(D, ProjDb) then DbArgs := DbArgs + Format(' --db "%s"', [D]);
  CmdLine := Format('"%s" forms-csv --project "%s"%s --out "%s"', [ExePath, ProjFile, DbArgs, OutPath]);
```

(Preserve the surrounding job-enqueue + open-CSV logic verbatim; only the `CmdLine` construction and the `ProjDb`/`DbList` lines change.)

- [ ] **Step 3: Exe-version guard after the CSV is produced**

After the job completes and before/at opening the CSV, read the produced file's footer line containing `FORMS_CSV_ALGORITHM=<n>` and compare to the exe's constant. Add a helper in Editor.pas:

```pascal
/// <summary>Warns (log + message) when the just-generated forms CSV footer's
/// FORMS_CSV_ALGORITHM version differs from the value THIS plugin build expects,
/// i.e. a stale drag-lint.exe produced an old-format CSV. Best-effort; never
/// blocks opening the file.</summary>
procedure WarnIfStaleFormsCsv(const ACsvPath: string);
const EXPECTED_FORMS_CSV_ALGO = '4';  // keep in lockstep with FormsMap FORMS_CSV_ALGORITHM
var Lines: TArray<string>; L, FoundVer: string;
begin
  FoundVer := '';
  try
    if not TFile.Exists(ACsvPath) then Exit;
    Lines := TFile.ReadAllLines(ACsvPath, TEncoding.ANSI);
    for L in Lines do
      if Pos('FORMS_CSV_ALGORITHM', L) > 0 then
      begin
        var Eq: Integer := Pos('=', L);
        if Eq > 0 then FoundVer := Trim(Copy(L, Eq + 1, MaxInt));
        Break;
      end;
  except end;
  if (FoundVer <> '') and (FoundVer <> EXPECTED_FORMS_CSV_ALGO) then
  begin
    DebugLog(Format('forms-csv: STALE EXE? csv algo=%s expected=%s', [FoundVer, EXPECTED_FORMS_CSV_ALGO]));
    ShowMessage(Format('drag-lint: the forms CSV was produced by a drag-lint.exe whose format (v%s) differs from this plugin''s expected v%s. The deployed exe may be stale.', [FoundVer, EXPECTED_FORMS_CSV_ALGO]));
  end;
end;
```

Call `WarnIfStaleFormsCsv(OutPath)` right before the code opens the CSV.

> NOTE: verify the footer's actual token format first — grep `FORMS_CSV_ALGORITHM` in `src/forms/DRagLint.FormsMap.pas` and match the exact `KEY=VALUE` vs `KEY: VALUE` shape the footer emits. Adjust the `Pos('=')` parse to the real separator.

- [ ] **Step 4: Build CLI (Win64), expect 0 errors.** (Plugin BPL builds later in Task 4 after tests, RAD Studio closed.)

- [ ] **Step 5: Commit (source only — no BPL yet)**

```bash
git add src/cli/DRagLint.CLI.pas src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(forms-csv): CLI passes all DBs; IDE menu emits multi --db + stale-exe guard"
```

---

### Task 4: Multi-DB forms regression test (headless) + BPL build

**Files:**
- Create: `tests/autotest/run_formsmap_multidb.ps1`

**Interfaces:**
- Consumes: the built `src/cli/Win64/Debug/drag-lint.exe` with Tasks 1-3.

- [ ] **Step 1: Write the failing two-DB test**

```powershell
# forms-csv multi-DB regression: a form reachable only via a launch-body in a
# SECOND index (COMMON) must resolve to its real chain, not "DEAD FORM".
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-formsmap-multidb")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n,$ok,$d=''){ $s=if($ok){'PASS'}else{'FAIL'}; $c=if($ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }; New-Item -ItemType Directory $WorkDir | Out-Null

# CLIENT source: MAIN form + a form (frmPlanEdit) whose ONLY launcher lives in COMMON.
$client = "$WorkDir\client"; New-Item -ItemType Directory $client | Out-Null
@'
unit uMain;
interface
uses Vcl.Forms;
type
  TfrmMAIN = class(TForm)
    procedure btnPlanClick(Sender: TObject);
  end;
  TfrmPlanEdit = class(TForm)
  end;
implementation
procedure TfrmMAIN.btnPlanClick(Sender: TObject);
var P: IPlanList;
begin
  P.EditForm;   // interface dispatch; concrete body is in COMMON
end;
end.
'@ | Set-Content "$client\uMain.pas" -Encoding ascii
# DFM so btnPlanClick has a caption 'Plan' (minimal; adjust to what FormsMap reads).
@'
object frmMAIN: TfrmMAIN
  object btnPlan: TButton
    Caption = 'Plan'
    OnClick = btnPlanClick
  end
end
'@ | Set-Content "$client\uMain.dfm" -Encoding ascii

# COMMON source: the concrete EditForm body that constructs frmPlanEdit.
$common = "$WorkDir\common"; New-Item -ItemType Directory $common | Out-Null
@'
unit uPlanList;
interface
type
  IPlanList = interface ['{11111111-1111-1111-1111-111111111111}'] procedure EditForm; end;
  TPlanList = class(TInterfacedObject, IPlanList)
    procedure EditForm;
  end;
implementation
uses uMain, Vcl.Forms;
procedure TPlanList.EditForm;
begin
  with TfrmPlanEdit.Create(nil) do ShowModal;
end;
end.
'@ | Set-Content "$common\uPlanList.pas" -Encoding ascii

$clientDb = "$WorkDir\client.sqlite"; $commonDb = "$WorkDir\common.sqlite"
& $Exe index $client --db $clientDb | Out-Null
& $Exe index $common --db $commonDb | Out-Null
Check 'dbs built' ((Test-Path $clientDb) -and (Test-Path $commonDb))

# minimal .dproj so --project scopes to the client units
$proj = "$WorkDir\Client.dpr"
@'
program Client;
uses uMain in 'uMain.pas';
begin
end.
'@ | Set-Content $proj -Encoding ascii

function FormsCsv([string[]]$Dbs){ $a=@(); foreach($d in $Dbs){$a+=@('--db',$d)}
  return (& $Exe forms-csv --project $proj @a --root TfrmMAIN 2>&1) -join "`n" }

# 1. CLIENT-only -> frmPlanEdit is DEAD (reproduces the bug)
$only = FormsCsv @($clientDb)
Check 'client-only shows dead/no-path for frmPlanEdit' `
  (($only -match 'PlanEdit') -and (($only -match 'DEAD') -or ($only -match 'no path'))) $only

# 2. CLIENT + COMMON -> frmPlanEdit resolves with the 'Plan' caption in the chain
$both = FormsCsv @($clientDb, $commonDb)
Check 'multi-db resolves frmPlanEdit chain' ($both -match 'PlanEdit') $both
Check 'chain carries Plan caption'          ($both -match "'Plan'") $both
Check 'multi-db frmPlanEdit NOT dead'        (-not (($both -split "`n" | Where-Object { $_ -match 'PlanEdit' }) -match 'DEAD')) $both

# 3. version footer present in output file
$outFile = "$WorkDir\out.csv"
& $Exe forms-csv --project $proj --db $clientDb --db $commonDb --root TfrmMAIN --out $outFile | Out-Null
Check 'footer has FORMS_CSV_ALGORITHM' ((Get-Content $outFile -Raw) -match 'FORMS_CSV_ALGORITHM')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
```

- [ ] **Step 2: Run it, expect PASS**

Run: `pwsh -File tests/autotest/run_formsmap_multidb.ps1`
Expected: `PASS`. If check 2/3 fail, the fixture's caption/DFM wiring or the enclosing-impl resolution needs adjusting to what `FormsMap` actually reads (iterate the fixture, not the engine, unless a real bug surfaces — then apply systematic-debugging).

> The fixture shapes (DFM caption binding, interface decl) are best-effort approximations of what the parser indexes. Expect to tune the fixture in Step 2 so it exercises the real code path; the ASSERTIONS (dead client-only → resolved multi-db → caption present → footer present) are the contract and must not be weakened.

- [ ] **Step 3: Rebuild the IDE BPL (Win32, RAD Studio CLOSED)**

Check `Get-Process bds` is empty. Run `src/delphi-plugin/_bpl_build.bat` via PowerShell `Start-Process cmd -Wait` with output redirected. Confirm `Build succeeded`, 0 Error(s). It auto-deploys to `third_party/dll-win32/`.

- [ ] **Step 4: Commit the test, then the BPL separately**

```bash
git add tests/autotest/run_formsmap_multidb.ps1
git commit -m "test(forms-csv): multi-DB regression -- dead client-only, resolved with COMMON"
git add third_party/dll-win32/dclDragLintWizard.bpl third_party/dll-win32/dclDragLintWizard.dcp
git commit -m "build(plugin): rebuild Win32 BPL for forms-csv multi --db"
```

---

# ITEM 2 — AutoDoc facts multi-DB (Tasks 5-6)

### Task 5: `TDocFactsBuilder.Build` gains `AExtraStores` and merges caller queries

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (`Build` signature :81-83; caller queries :396, :404, :526)

**Interfaces:**
- Produces: `class function Build(const AStore: ISymbolStore; const ASym: TSymbol; AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False; const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil): TDocFacts;` — new trailing optional param. `nil`/empty = today's single-store behavior.

- [ ] **Step 1: Write the failing test (headless CLI)** — deferred to Task 6's `run_doc_multidb.ps1`; Task 5's own gate is: build + existing doc tests green.

- [ ] **Step 2: Add the param + a cross-store caller helper**

Extend `Build`'s signature with `const AExtraStores: TArray<ISymbolStore> = nil`. Add a local helper that merges resolved callers across the primary + extra stores, deduping on `(Location, Display)` (the record's line-free key already used at `Facts.pas:384`). At the resolved-callers block (:396-410), after querying the primary store, loop the extra stores:

```pascal
    ResCallers:= AStore.FindResolvedCallers(ASym.Id);
    for RC in ResCallers do begin FR:= ToFactRef(RC); AddDistinct(FR); end;
    for var ExStore in AExtraStores do
    begin
      if ExStore = nil then Continue;
      for RC in ExStore.FindResolvedCallers(ExStore.FindSymbolIdByQName(ASym.QualifiedName)) do  // see NOTE
      begin FR:= ToFactRef(RC); AddDistinct(FR); end;
    end;
    // unverified name bucket -- name-keyed, so extra stores query by the SAME last segment:
    ResCallers:= AStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName));
    for RC in ResCallers do begin FR:= ToFactRef(RC); FR.Confidence:='unverified'; AddDistinct(FR); end;
    for var ExStore in AExtraStores do
    begin
      if ExStore = nil then Continue;
      for RC in ExStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName)) do
      begin FR:= ToFactRef(RC); FR.Confidence:='unverified'; AddDistinct(FR); end;
    end;
```

> NOTE — resolved callers key on the target's SYMBOL ID, which is per-DB. `ASym.Id` is only valid in the primary store. For an extra store, the same symbol (if present there at all) has a different Id, and typically the symbol is NOT defined in the caller's DB — so `FindResolvedCallers` in an extra store won't find it by primary-Id. Therefore: in extra stores, use the NAME-based bucket only (`FindUnresolvedNameCallers` + `FindCallersByName`), which is Id-independent and is exactly how cross-DB callers surface (a COMMON ref to `EditForm` is a name match). Drop the resolved-caller extra-store loop unless `ISymbolStore` exposes a by-qname resolver; if `FindSymbolIdByQName` does not exist, DO NOT invent it — rely on the name buckets. Verify the interface (`DRagLint.Core.Interfaces.pas`) before writing this; keep only the calls that exist.

- [ ] **Step 3: Merge the used-in (`FindCallersByName`) query across extra stores**

At the used-in block (:526), after the primary query, union the extra stores' `FindCallersByName(LastSeg(...))` results into `UsedInUnits`, deduping unit names (case-insensitive) before the cap.

- [ ] **Step 4: Confirm calls-out + body-scan stay on the primary store** (no change at :456-513 / :469).

- [ ] **Step 5: Build CLI (Win64), 0 errors.**

- [ ] **Step 6: Run existing doc tests, expect PASS** (grep `tests/autotest/run_*.ps1` for a doc/autodoc test; run each — extra-stores default nil preserves behavior).

- [ ] **Step 7: Commit**

```bash
git add src/doc/DRagLint.Doc.Facts.pas
git commit -m "feat(autodoc): called-from/used-in facts can span multiple index DBs"
```

---

### Task 6: Thread `AExtraStores` through the document CLI verbs + test

**Files:**
- Modify: `src/doc/DRagLint.Doc.Document.pas`, `src/doc/DRagLint.Doc.Batch.pas` (pass the param from the documenter through to `Build`)
- Modify: `src/cli/DRagLint.CLI.pas` (document verbs resolve + open extra stores)
- Create: `tests/autotest/run_doc_multidb.ps1`

**Interfaces:**
- Consumes: `Build(..., AExtraStores)` (Task 5); `ResolveConsumerDbs`, `OpenReadOnlyStore` (CLI).

- [ ] **Step 1: Thread the param through Document/Batch**

In `TDocumenter.BuildFor` (Document.pas ~:236) and the batch driver (Batch.pas ~:150), add `const AExtraStores: TArray<ISymbolStore> = nil` and forward it into the `TDocFactsBuilder.Build(...)` call. Keep defaults so existing callers compile unchanged.

- [ ] **Step 2: CLI opens the extra stores**

In the document command handler (grep `DoDocument`/the `document` dispatch in CLI.pas), after opening the primary store on `AArgs.DbPath`, resolve the rest:

```pascal
  var DbList: TArray<string>:= ResolveConsumerDbs(AArgs);
  var Extras: TArray<ISymbolStore>; SetLength(Extras, 0);
  for var D in DbList do
    if not SameText(D, AArgs.DbPath) then
    begin
      var Ok: Boolean; var S:= OpenReadOnlyStore(D, Ok);
      if Ok and (S <> nil) then Extras:= Extras + [S];
    end;
  // pass Extras into BuildFor / the batch driver
```

(Interfaces are refcounted — `ISymbolStore` — so no manual Free.)

- [ ] **Step 3: Write the failing multi-DB doc test**

```powershell
# AutoDoc multi-DB: a symbol's callers that live in a SECOND db appear in the
# generated Called-from / used-in facts.
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-doc-multidb")
$ErrorActionPreference='Stop'; $script:Failed=$false
function Check($n,$ok,$d=''){ $s=if($ok){'PASS'}else{'FAIL'}; $c=if($ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}; New-Item -ItemType Directory $WorkDir|Out-Null

$libDir="$WorkDir\lib"; New-Item -ItemType Directory $libDir|Out-Null
@'
unit uLib;
interface
function Compute(const A: Integer): Integer;
implementation
function Compute(const A: Integer): Integer;
begin Result := A * 2; end;
end.
'@ | Set-Content "$libDir\uLib.pas" -Encoding ascii

$appDir="$WorkDir\app"; New-Item -ItemType Directory $appDir|Out-Null
@'
unit uApp;
interface
implementation
uses uLib;
procedure Run;
begin Compute(21); end;
end.
'@ | Set-Content "$appDir\uApp.pas" -Encoding ascii

$libDb="$WorkDir\lib.sqlite"; $appDb="$WorkDir\app.sqlite"
& $Exe index $libDir --db $libDb | Out-Null
& $Exe index $appDir --db $appDb | Out-Null
Check 'dbs built' ((Test-Path $libDb) -and (Test-Path $appDb))

# document uLib.Compute. Single-db (lib only): NO caller. Multi-db (+app): app is a caller.
$single = (& $Exe document --qname uLib.Compute --db $libDb --json 2>&1) -join "`n"
$multi  = (& $Exe document --qname uLib.Compute --db $libDb --db $appDb --json 2>&1) -join "`n"
Check 'single-db has no uApp caller' (-not ($single -match 'uApp')) $single
Check 'multi-db surfaces uApp caller' ($multi -match 'uApp') $multi

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red;exit 1}else{Write-Host 'PASS' -ForegroundColor Green;exit 0}
```

- [ ] **Step 4: Run it, expect PASS**

Run: `pwsh -File tests/autotest/run_doc_multidb.ps1`
Expected: `PASS`. (If `document --json` doesn't surface called-from in its JSON, assert on the generated remarks text form the verb DOES emit — inspect `document --qname ... --json` output first and key the assertion to a field that actually carries callers, e.g. the rendered `<remarks>` facts block.)

- [ ] **Step 5: Commit**

```bash
git add src/doc/DRagLint.Doc.Document.pas src/doc/DRagLint.Doc.Batch.pas src/cli/DRagLint.CLI.pas tests/autotest/run_doc_multidb.ps1
git commit -m "feat(autodoc): document verbs search all resolved DBs for callers; multi-db test"
```

---

# ITEM 1 — returns enumeration + docs config (Tasks 7-10)

### Task 7: `drag-lint.json` docs config (`TDocSettings.MaxReturnCases`)

**Files:**
- Modify: `src/index/DRagLint.Index.Manifest.pas` (`TDocSettings` record + `TIndexManifest.Docs` field + parse/emit/validate)
- Test: `tests/autotest/run_manifest.ps1` (extend) or a new assertion in the returns test (Task 10)

**Interfaces:**
- Produces: `TDocSettings = record MaxReturnCases: Integer; class function Defaults: TDocSettings; static; end;` and `TIndexManifest.Docs: TDocSettings`. Default `MaxReturnCases = 20`.

- [ ] **Step 1: Declare the record + field**

In the type section (near `TIndexSettings`, :31):

```pascal
  /// <summary>Doc-generation settings, parsed from the manifest 'docs' object.</summary>
  TDocSettings = record
    /// <summary>Max distinct return cases enumerated in a generated &lt;returns&gt;
    /// (the "Observed: ..." list). Default 20. 0 or negative disables enumeration
    /// (bare TODO only).</summary>
    MaxReturnCases: Integer;
    /// <summary>Record with all fields at documented defaults (MaxReturnCases=20).</summary>
    class function Defaults: TDocSettings; static;
  end;
```

Add to `TIndexManifest` (:83): `Docs: TDocSettings;`.

- [ ] **Step 2: Implement `Defaults` + seed it in `ParseTextEx`**

```pascal
class function TDocSettings.Defaults: TDocSettings;
begin Result.MaxReturnCases:= 20; end;
```

In `ParseTextEx` after `Result.Settings := TIndexSettings.Defaults;` (:299) add `Result.Docs := TDocSettings.Defaults;`.

- [ ] **Step 3: Parse the `docs` object**

After the settings block (after :355), mirroring the `sizeGuardMB` numeric pattern:

```pascal
    { -- docs block -- }
    var JDocs: TJSONObject:= Root.GetValue('docs') as TJSONObject;
    if JDocs <> nil then
    begin
      var ND: TJSONNumber:= JDocs.GetValue('max_return_cases') as TJSONNumber;
      if ND <> nil then Result.Docs.MaxReturnCases:= ND.AsInt;
    end;
```

- [ ] **Step 4: Emit in `ToJson` + reject negative in `Validate`**

In `ToJson` add a `"docs"` object with `max_return_cases` (only if it differs from default, or always — match how `settings` emits). In `Validate` add: `if AManifest.Docs.MaxReturnCases < 0 then Exit('docs.max_return_cases must be >= 0');`.

- [ ] **Step 5: Build CLI (Win64), 0 errors.**

- [ ] **Step 6: Round-trip test**

Add to `run_manifest.ps1` (or a quick inline check): write a `drag-lint.json` with `"docs":{"max_return_cases":7}`, and assert whatever manifest-dump/consumer surface reflects 7. If no dump verb exists, defer the assertion to Task 10 (the returns test sets the cap via a fixture manifest and observes the effect).

- [ ] **Step 7: Commit**

```bash
git add src/index/DRagLint.Index.Manifest.pas
git commit -m "feat(manifest): docs config block with max_return_cases (default 20)"
```

---

### Task 8: Mine `ReturnCases` into `TDocFacts`

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (add field :64; mine after :422; uses `DRagLint.Hover.Returns`)

**Interfaces:**
- Consumes: `MineReturnExpressions` (Hover.Returns); `TDocSettings.MaxReturnCases` (Task 7) passed into `Build`.
- Produces: `TDocFacts.ReturnCases: TArray<string>` (capped, XML-unescaped raw RHS; escaping happens at emit).

- [ ] **Step 1: Add the field + uses**

Add `ReturnCases: TArray<string>;` to `TDocFacts` (after `ReturnType`, :34). Add `DRagLint.Hover.Returns` to the implementation `uses`. Add a cap param to `Build`: `AMaxReturnCases: Integer = 20` (place before `AExtraStores` from Task 5, or after — keep defaults so order is back-compat; document the final order in the Produces block here). Final `Build` signature:

```pascal
class function Build(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False;
  const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
  AMaxReturnCases: Integer = 20): TDocFacts;
```

- [ ] **Step 2: Mine the body lines (reuse the already-read source)**

The Calls block reads the body at :489 (`Src := TFile.ReadAllLines(...)`). Return mining needs the same lines. To avoid a second read, hoist the body-line read so BOTH Calls and Returns use it, OR (simpler, low-risk) do a dedicated read guarded by the same `ImplStartLine/ImplEndLine` window. Right after `Result.ReturnType := ParseReturnType(ASym.Signature);` (:422):

```pascal
  // v(item1): enumerate distinct return cases for a function's <returns> doc.
  if (Result.ReturnType <> '') and (AMaxReturnCases > 0)
     and (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var RSrc: TArray<string>;
    try RSrc:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
    except RSrc:= nil; end;
    if Length(RSrc) > 0 then
    begin
      var BodyLines: TArray<string>; SetLength(BodyLines, 0);
      for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(RSrc)) do
        BodyLines:= BodyLines + [RSrc[Ln - 1]];
      var Mined: TArray<string>:= MineReturnExpressions(BodyLines);
      if Length(Mined) > AMaxReturnCases then SetLength(Mined, AMaxReturnCases);
      Result.ReturnCases:= Mined;
    end;
  end;
```

- [ ] **Step 3: Build CLI (Win64), 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/doc/DRagLint.Doc.Facts.pas
git commit -m "feat(autodoc): mine distinct return cases (ReturnCases) via hover Returns miner"
```

---

### Task 9: Emit `Observed:` in `<returns>` (both fresh + existing paths)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (:168-169 fresh; :229-233 existing)

**Interfaces:**
- Consumes: `AFacts.ReturnCases` (Task 8) — already on the `TDocFacts` passed to `MergeComment`; no signature change.

- [ ] **Step 1: Add an XML-escape + observed-suffix helper**

Near the top of the implementation:

```pascal
/// <summary>Builds the "Observed: a; b" suffix (XML-escaped) from mined return
/// cases, or '' when none. Deterministic -> idempotent across runs.</summary>
function ObservedSuffix(const ACases: TArray<string>): string;
  function Esc(const S: string): string;
  begin
    Result:= StringReplace(S, '&', '&amp;', [rfReplaceAll]);
    Result:= StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result:= StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  end;
var i: Integer; Sb: TStringBuilder;
begin
  Result:= '';
  if Length(ACases) = 0 then Exit;
  Sb:= TStringBuilder.Create;
  try
    Sb.Append(' Observed: ');
    for i:= 0 to High(ACases) do
    begin
      if i > 0 then Sb.Append('; ');
      Sb.Append(Esc(ACases[i]));
    end;
    Sb.Append('.');
    Result:= Sb.ToString;
  finally Sb.Free; end;
end;
```

- [ ] **Step 2: Fresh path (:168-169)**

```pascal
      if AHasReturn then
        Sb.AppendLine(APrefix + '<returns>TODO: describe.' + ObservedSuffix(AFacts.ReturnCases) + '</returns>');
```

- [ ] **Step 3: Existing path (:229-233) — only append Observed when the returns text is still the managed stub**

```pascal
    if AHasReturn then
    begin
      var Ret: string:= AExisting.ReturnsText;
      if Trim(Ret) = '' then Ret:= 'TODO: describe.';
      // Author-edited returns (non-stub) win: do NOT inject Observed into hand text.
      if SameText(Trim(Ret), 'TODO: describe.') then
        Ret:= 'TODO: describe.' + ObservedSuffix(AFacts.ReturnCases);
      Sb.AppendLine(APrefix + '<returns>' + Ret + '</returns>');
    end;
```

> Idempotency: a 2nd run parses the prior `<returns>` as `ReturnsText = "TODO: describe. Observed: ..."`, whose `Trim` is NOT `SameText 'TODO: describe.'` — so it is treated as author text and left verbatim, reproducing the SAME string (the Observed part regenerated identically on run 1 and preserved on run 2). This yields byte-identical output. Task 10 asserts this explicitly. If the parser strips the `Observed:` suffix such that `ReturnsText` round-trips back to bare `TODO: describe.`, then it regenerates deterministically instead — also byte-identical. Verify which the parser does in Task 10 Step 2 and keep whichever branch holds; do not weaken the byte-identical assertion.

- [ ] **Step 4: Build CLI (Win64), 0 errors.**

- [ ] **Step 5: Commit**

```bash
git add src/doc/DRagLint.Doc.Regions.pas
git commit -m "feat(autodoc): emit 'Observed: <cases>' in generated <returns> (idempotent, XML-escaped)"
```

---

### Task 10: Wire the cap from the manifest into the doc build + returns test

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (load manifest docs cap, pass into `BuildFor`/`Build` via the doc path)
- Modify: `src/doc/DRagLint.Doc.Document.pas` / `DRagLint.Doc.Batch.pas` (thread `AMaxReturnCases`)
- Create: `tests/autotest/run_doc_returns.ps1`

**Interfaces:**
- Consumes: `TManifestIO.Load`/`ParseTextEx` → `Docs.MaxReturnCases` (Task 7); `Build(..., AMaxReturnCases)` (Task 8).

- [ ] **Step 1: Thread `AMaxReturnCases` through Document/Batch to `Build`**

Add `AMaxReturnCases: Integer = 20` to `TDocumenter.BuildFor` and the batch driver, forwarding into `TDocFactsBuilder.Build(...)`.

- [ ] **Step 2: CLI loads the cap**

In the document dispatch (where the manifest is already loaded for DB resolution, or load via `TManifestIO.Load(EngineDir, StartDir)`), read `Manifest.Docs.MaxReturnCases` and pass it into the documenter call. Fallback 20 if no manifest.

- [ ] **Step 3: Write the failing returns test**

```powershell
# AutoDoc <returns> enumeration + cap + idempotency.
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-doc-returns")
$ErrorActionPreference='Stop'; $script:Failed=$false
function Check($n,$ok,$d=''){ $s=if($ok){'PASS'}else{'FAIL'}; $c=if($ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}; New-Item -ItemType Directory $WorkDir|Out-Null

$src="$WorkDir\src"; New-Item -ItemType Directory $src|Out-Null
@'
unit uRet;
interface
function Grab(const AWidth: Integer): Boolean;
procedure DoNothing;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  Result := False;
  rlines := AWidth;
  Result := rlines <> 0;
end;
procedure DoNothing; begin end;
end.
'@ | Set-Content "$src\uRet.pas" -Encoding ascii

$db="$WorkDir\ret.sqlite"; & $Exe index $src --db $db | Out-Null
Check 'db built' (Test-Path $db)

# document the function -> <returns> should carry Observed: False; rlines <> 0 (escaped)
$doc1 = (& $Exe document --qname uRet.Grab --db $db --json 2>&1) -join "`n"
Check 'returns lists False'        ($doc1 -match 'False') $doc1
Check 'returns lists rlines (esc)' ($doc1 -match 'rlines &lt;> 0') $doc1
# procedure has no <returns> observed
$doc2 = (& $Exe document --qname uRet.DoNothing --db $db --json 2>&1) -join "`n"
Check 'procedure no Observed' (-not ($doc2 -match 'Observed:')) $doc2

# cap: a fixture manifest with max_return_cases=1 -> only ONE case listed
'{ "docs": { "max_return_cases": 1 } }' | Set-Content "$src\drag-lint.json" -Encoding ascii
$docCap = (& $Exe document --qname uRet.Grab --db $db --json 2>&1) -join "`n"
Check 'cap=1 lists exactly one case' `
  ((($docCap -match 'False') -and (-not ($docCap -match 'rlines'))) -or `
   ((-not ($docCap -match 'False')) -and ($docCap -match 'rlines'))) $docCap
Remove-Item "$src\drag-lint.json"

# idempotency: apply twice to a copy, second run must be byte-identical
Copy-Item "$src\uRet.pas" "$WorkDir\uRet_apply.pas"
& $Exe index $WorkDir --db "$WorkDir\apply.sqlite" | Out-Null
& $Exe document --unit "$WorkDir\uRet_apply.pas" --db "$WorkDir\apply.sqlite" --apply --no-backup | Out-Null
$after1 = Get-Content "$WorkDir\uRet_apply.pas" -Raw
& $Exe document --unit "$WorkDir\uRet_apply.pas" --db "$WorkDir\apply.sqlite" --apply --no-backup | Out-Null
$after2 = Get-Content "$WorkDir\uRet_apply.pas" -Raw
Check 'apply is idempotent (byte-identical)' ($after1 -ceq $after2)

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red;exit 1}else{Write-Host 'PASS' -ForegroundColor Green;exit 0}
```

- [ ] **Step 4: Run it, expect PASS**

Run: `pwsh -File tests/autotest/run_doc_returns.ps1`
Expected: `PASS`. If the `document --json` payload doesn't expose the `<returns>` text directly, switch the assertions to `--apply --no-backup` on a fixture copy and grep the modified `.pas` for the `<returns>` line (the apply path definitely writes it). The cap manifest discovery path (`drag-lint.json` beside the source vs beside the exe) must match Task 10 Step 2's load location — align the fixture's manifest placement to where `TManifestIO.Load` looks.

- [ ] **Step 5: Build the IDE BPL (Win32, RAD Studio CLOSED)** — the plugin doesn't call these doc units directly (it shells out), so a BPL rebuild is only needed if the plugin surface changed. It did NOT for items 1/2 (CLI-only). SKIP the BPL rebuild here unless `git status` shows plugin `.pas` changes; the forms-csv BPL from Task 4 already covers the only plugin edit in this batch.

- [ ] **Step 6: Commit**

```bash
git add src/cli/DRagLint.CLI.pas src/doc/DRagLint.Doc.Document.pas src/doc/DRagLint.Doc.Batch.pas tests/autotest/run_doc_returns.ps1
git commit -m "feat(autodoc): manifest max_return_cases wired into <returns>; enumeration + idempotency test"
```

---

## Final verification (before publish)

- [ ] Run the full autotest set touched by this batch: `run_formsmap.ps1`, `run_formsmap_multidb.ps1`, `run_doc_multidb.ps1`, `run_doc_returns.ps1`, plus any pre-existing doc/manifest tests — all `PASS`.
- [ ] `git status` clean of unintended changes; BPL/DCP only in the dedicated `build(plugin):` commit(s).
- [ ] Update `docs/lint/BACKLOG.md` with a LATEST-27 resume block summarizing Batch A shipped (its own commit).
- [ ] Publish: `git push origin main` (user drives push per convention).

---

## Notes for the executor

- **When a fixture doesn't exercise the real path:** tune the FIXTURE, never weaken the assertion. The assertions ARE the contract. If tuning can't make it pass, you've found a real bug — switch to systematic-debugging.
- **`document --json` shape uncertainty:** several tests hedge between `--json` and `--apply` + grep. Inspect the actual verb output ONCE at the start of Task 6/10 and pick the surface that carries the fact you're asserting; don't guess per-test.
- **Interface existence:** before calling any `ISymbolStore`/`TSQLiteSymbolStore` method named in this plan, confirm it exists in `DRagLint.Core.Interfaces.pas` / the store unit. Where a NOTE says "if it doesn't exist, don't invent it," honor that — fall back to the name-based query.
- **ANSI/CRLF:** every `.pas` edit stays 7-bit ASCII + CRLF. The `Observed:` suffix and all new strings are ASCII.
