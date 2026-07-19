# ConvRulesEditor -- independent FROM/TO platform selection -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let ConvRulesEditor pick the FROM platform and TO platform independently (Win32/Win64/Both), each side's type picker drawing from that platform's library index, selectable via CLI args + UI dropdowns.

**Architecture:** A new pure unit `ConvRules.Platform` models the platform enum and maps a platform to its library DB set. `ConvRulesEditor.dpr` parses `--from-platform`/`--to-platform` and sets globals (lib dir, project DB, initial platforms). `ConvRules.MainForm` computes each side's DB set from its platform, builds two platform combo boxes, and re-scopes the pickers live on change via a new `TEngineAdapter.SetDbs`.

**Tech Stack:** Delphi 13 / RAD Studio 37, plain VCL (no DevExpress, no .dfm -- the UI is code-built), Win64. Design of record: `docs/superpowers/specs/2026-07-17-convrules-editor-platform-selection-design.md`.

## Global Constraints

- Editor is a STANDALONE plain-VCL exe; UI is built in code (no .dfm), no DevExpress.
- **Build the editor:** `dcc64 -B src\tools\convrules-editor\ConvRulesEditor.dpr` via a 3-line rsvars wrapper .bat (call rsvars -> cd -> dcc64), run from PowerShell `Start-Process -Wait` with output redirected to a log; require exit 0 and no `Error`/`Fatal` in the log. A running ConvRulesEditor.exe locks its own exe (F2039) -> `Stop-Process -Name ConvRulesEditor` first. Deploy the built exe to `third_party\dll-win64\ConvRulesEditor.exe`.
- **Build + run tests:** `dcc64 -B src\tools\convrules-editor\tests\ConvRulesModelTests.dpr` (same wrapper), then run the built exe; require the summary line reports `0 fail`.
- **Encoding:** all `.pas`/`.dpr` are strict 7-bit ASCII, CRLF line endings, no BOM, no Unicode. The Write tool emits LF -- after any Write/Edit, re-normalize to CRLF (`[IO.File]::ReadAllText` -> replace `\n`->`\r\n` where the byte before `\n` is not already `\r` -> `WriteAllText`) and verify 0 lone-LF + 0 non-ASCII bytes before building.
- **DocInsight:** `///` spec-comments on every new public declaration.
- **Back-compat:** with no CLI args, FROM defaults to Both and TO to Win64, reproducing today's hard-coded DB sets exactly (`FromDbs`=[Win32,Win64,ProjectDb], `ToDbs`=[Win64,ProjectDb]).
- **Library dir / project DB (today's constants, preserved):** lib dir `C:\Projects\.drag-lint\` (files `library-Win32.sqlite`, `library-Win64.sqlite`); project DB `C:\Projects\DB\ORM3\drag-lint.sqlite`.
- Commit source per task. Do NOT commit the deployed exe (untracked). Do NOT push (user holds push).

---

### Task 1: Platform model unit (`ConvRules.Platform`)

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.Platform.pas`
- Test: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (add cases + `uses`)

**Interfaces:**
- Produces:
  - `TConvPlatform = (cpWin32, cpWin64, cpBoth)`
  - `function ParsePlatform(const AText: string; ADefault: TConvPlatform): TConvPlatform`
  - `function PlatformToStr(APlatform: TConvPlatform): string`
  - `function LibDbsFor(APlatform: TConvPlatform; const ALibDir: string): TArray<string>`

- [ ] **Step 1: Write the failing tests** in `tests/ConvRulesModelTests.dpr`. Add `ConvRules.Platform in '..\ConvRules.Platform.pas'` to the `uses` clause, and add a `procedure TestPlatform;` with these checks, then call it from the main body:

```pascal
procedure TestPlatform;
const
  LibDir = 'C:\Lib\';
var
  d32, d64, dboth: TArray<string>;
begin
  // ParsePlatform: case-insensitive, default fallback
  Check('platform.parse.win32', ParsePlatform('Win32', cpBoth) = cpWin32);
  Check('platform.parse.win64', ParsePlatform('WIN64', cpBoth) = cpWin64);
  Check('platform.parse.both',  ParsePlatform('both',  cpWin32) = cpBoth);
  Check('platform.parse.empty->default',   ParsePlatform('',    cpWin64) = cpWin64);
  Check('platform.parse.unknown->default', ParsePlatform('arm', cpWin32) = cpWin32);

  // PlatformToStr round-trips the tokens
  Check('platform.tostr.win32', PlatformToStr(cpWin32) = 'win32');
  Check('platform.tostr.win64', PlatformToStr(cpWin64) = 'win64');
  Check('platform.tostr.both',  PlatformToStr(cpBoth)  = 'both');

  // LibDbsFor: one lib for a single platform, both for cpBoth (Win32 first)
  d32 := LibDbsFor(cpWin32, LibDir);
  Check('platform.libdbs.win32.count', Length(d32) = 1);
  Check('platform.libdbs.win32.path', d32[0] = 'C:\Lib\library-Win32.sqlite');
  d64 := LibDbsFor(cpWin64, LibDir);
  Check('platform.libdbs.win64.path', (Length(d64) = 1) and (d64[0] = 'C:\Lib\library-Win64.sqlite'));
  dboth := LibDbsFor(cpBoth, LibDir);
  Check('platform.libdbs.both.count', Length(dboth) = 2);
  Check('platform.libdbs.both.order', (dboth[0] = 'C:\Lib\library-Win32.sqlite')
                                  and (dboth[1] = 'C:\Lib\library-Win64.sqlite'));
end;
```

- [ ] **Step 2: Run tests to verify they fail (compile error -- unit missing)**

Build the test dpr (see Global Constraints). Expected: FAIL to compile with `unit ConvRules.Platform not found` (the unit does not exist yet).

- [ ] **Step 3: Create the unit** `src/tools/convrules-editor/ConvRules.Platform.pas`:

```pascal
unit ConvRules.Platform;

{ Pure platform model for the conversion editor: which library index each side
  (FROM / TO) draws its component types from. Headless + unit-tested; no UI, no
  file I/O. The editor and its .dpr both consume this so platform reasoning lives
  in exactly one place. }

interface

uses
  System.SysUtils;

type
  /// <summary>Which platform library a picker side resolves component types
  /// against. cpBoth = the union of both platform libraries -- the FROM safety
  /// net, since some legacy components (e.g. Orpheus TOvcTable) are indexed under
  /// only one platform's library.</summary>
  TConvPlatform = (cpWin32, cpWin64, cpBoth);

/// <summary>Parse a platform token (case-insensitive: 'win32' | 'win64' |
/// 'both'). Returns ADefault for '' or any unrecognized token.</summary>
function ParsePlatform(const AText: string; ADefault: TConvPlatform): TConvPlatform;

/// <summary>The canonical lowercase token for a platform
/// ('win32' | 'win64' | 'both').</summary>
function PlatformToStr(APlatform: TConvPlatform): string;

/// <summary>The library-index DB paths a platform selects, each under ALibDir.
/// cpWin32 -> [ALibDir\library-Win32.sqlite]; cpWin64 -> [...library-Win64...];
/// cpBoth -> [Win32, Win64] in that order. Pure: does not check existence.</summary>
function LibDbsFor(APlatform: TConvPlatform; const ALibDir: string): TArray<string>;

implementation

uses
  System.IOUtils;

function ParsePlatform(const AText: string; ADefault: TConvPlatform): TConvPlatform;
var
  T: string;
begin
  T := LowerCase(Trim(AText));
  if T = 'win32' then Result := cpWin32
  else if T = 'win64' then Result := cpWin64
  else if T = 'both' then Result := cpBoth
  else Result := ADefault;
end;

function PlatformToStr(APlatform: TConvPlatform): string;
begin
  case APlatform of
    cpWin32: Result := 'win32';
    cpWin64: Result := 'win64';
  else
    Result := 'both';
  end;
end;

function LibDbsFor(APlatform: TConvPlatform; const ALibDir: string): TArray<string>;
begin
  case APlatform of
    cpWin32: Result := [TPath.Combine(ALibDir, 'library-Win32.sqlite')];
    cpWin64: Result := [TPath.Combine(ALibDir, 'library-Win64.sqlite')];
  else
    Result := [TPath.Combine(ALibDir, 'library-Win32.sqlite'),
               TPath.Combine(ALibDir, 'library-Win64.sqlite')];
  end;
end;

end.
```

Re-normalize the new file to CRLF + verify ASCII (Global Constraints).

- [ ] **Step 4: Run tests to verify they pass**

Build + run the test dpr. Expected: the 13 `platform.*` checks PASS; summary reports `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Platform.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): platform model unit (TConvPlatform + LibDbsFor)"
```

---

### Task 2: `TEngineAdapter.SetDbs`

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.Engine.pas` (add public method; `FDbList` field already exists at ~line 60)
- Test: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: existing `TEngineAdapter.Create(const AExePath: string; const ADbList: TArray<string>)`, private `FDbList: TArray<string>`, private `function DbArgs: string`.
- Produces: `procedure TEngineAdapter.SetDbs(const ADbs: TArray<string>)` (public) -- replaces the adapter's default DB list used by proptree/scaffold/validate/qname-resolve.

- [ ] **Step 1: Write the failing test** in `tests/ConvRulesModelTests.dpr` (add to a `procedure TestEngineSetDbs;` called from the main body). `DbArgs` is private, so assert via behavior we CAN see: SetDbs changes what `DbArgsFor`-independent calls target. Since `DbArgs` is private, expose a minimal read path by asserting through a public method that uses `FDbList`. The simplest observable: add a public read-only helper `function DbList: TArray<string>` in the SAME task and assert on it.

Add to `TEngineAdapter` public section a getter, and test:

```pascal
procedure TestEngineSetDbs;
var
  eng: TEngineAdapter;
begin
  eng := TEngineAdapter.Create('drag-lint.exe', ['a.sqlite']);
  try
    Check('engine.dblist.initial', (Length(eng.DbList) = 1) and (eng.DbList[0] = 'a.sqlite'));
    eng.SetDbs(['x.sqlite', 'y.sqlite']);
    Check('engine.setdbs.count', Length(eng.DbList) = 2);
    Check('engine.setdbs.values', (eng.DbList[0] = 'x.sqlite') and (eng.DbList[1] = 'y.sqlite'));
  finally
    eng.Free;
  end;
end;
```

- [ ] **Step 2: Run tests to verify they fail**

Build the test dpr. Expected: FAIL to compile -- `SetDbs`/`DbList` not declared on `TEngineAdapter`.

- [ ] **Step 3: Add the methods** to `ConvRules.Engine.pas`. In the `public` section of `TEngineAdapter` (after the constructor), declare:

```pascal
    /// <summary>Replace the adapter's default DB list (used by proptree /
    /// scaffold / validate / class-name resolution). Called when the editor's
    /// FROM or TO platform changes so type resolution targets the new libraries.</summary>
    procedure SetDbs(const ADbs: TArray<string>);
    /// <summary>The adapter's current default DB list (read-only view).</summary>
    function DbList: TArray<string>;
```

In the implementation:

```pascal
procedure TEngineAdapter.SetDbs(const ADbs: TArray<string>);
begin
  FDbList := ADbs;
end;

function TEngineAdapter.DbList: TArray<string>;
begin
  Result := FDbList;
end;
```

Re-normalize CRLF + verify ASCII.

- [ ] **Step 4: Run tests to verify they pass**

Build + run. Expected: the 3 `engine.*` checks PASS; `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Engine.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): TEngineAdapter.SetDbs + DbList for live re-scope"
```

---

### Task 3: `.dpr` CLI parsing + platform globals

**Files:**
- Modify: `src/tools/convrules-editor/ConvRulesEditor.dpr`
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (globals block, interface, lines ~96-100)

**Interfaces:**
- Consumes: `ConvRules.Platform` (Task 1).
- Produces (new globals in `ConvRules.MainForm` interface, set by the .dpr before `CreateForm`):
  - `GEditorLibDir: string` -- library index directory
  - `GEditorProjectDb: string` -- shared project DB (additive)
  - `GEditorFromPlatform: TConvPlatform` -- initial FROM platform
  - `GEditorToPlatform: TConvPlatform` -- initial TO platform
  - `GEditorExe: string` stays as-is.
  - The old `GEditorDbs`/`GEditorFromDbs`/`GEditorToDbs` are REMOVED (Task 4 replaces their consumers). Note for the implementer: Task 4 edits every consumer; do Tasks 3 and 4 together before building, or expect a transient compile error between them.

- [ ] **Step 1: Update the MainForm globals block** (`ConvRules.MainForm.pas`, interface, replace lines ~96-100). Add `ConvRules.Platform` to the interface `uses` (line 21 area). Replace:

```pascal
var
  GEditorExe: string = '';
  GEditorDbs: TArray<string>;
  GEditorFromDbs: TArray<string>;
  GEditorToDbs: TArray<string>;
```

with:

```pascal
var
  GEditorExe: string = '';
  { Library index directory + shared project DB. Each side's picker DB set is
    LibDbsFor(<side platform>, GEditorLibDir) + GEditorProjectDb. }
  GEditorLibDir: string = '';
  GEditorProjectDb: string = '';
  GEditorFromPlatform: TConvPlatform = cpBoth;   // default: FROM union (today's behavior)
  GEditorToPlatform: TConvPlatform = cpWin64;    // default: TO target Win64 (today's behavior)
```

- [ ] **Step 2: Rewrite the `.dpr`** config block. In `ConvRulesEditor.dpr`, add `ConvRules.Platform in 'ConvRules.Platform.pas'` to `uses`. Replace the `LibWin32`/`LibWin64`/`ProjectDb` consts + `FromDbs`/`ToDbs`/`DefaultDbs` functions + the globals assignment (lines ~30-71) with:

```pascal
const
  LibDir    = 'C:\Projects\.drag-lint\';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';

{ Parse --from-platform / --to-platform (case-insensitive win32|win64|both).
  Absent -> defaults that reproduce today's behavior (FROM=Both, TO=Win64). }
function ArgPlatform(const AFlag: string; ADefault: TConvPlatform): TConvPlatform;
var
  i: Integer;
begin
  Result := ADefault;
  for i := 1 to ParamCount - 1 do
    if SameText(ParamStr(i), AFlag) then
      Exit(ParsePlatform(ParamStr(i + 1), ADefault));
end;

var
  Form: TConvRulesForm;
begin
  GEditorExe        := ResolveDragLintExe;
  GEditorLibDir     := LibDir;
  GEditorProjectDb  := ProjectDb;
  GEditorFromPlatform := ArgPlatform('--from-platform', cpBoth);
  GEditorToPlatform   := ArgPlatform('--to-platform', cpWin64);
  Application.Initialize;
  Application.Title := 'ConvRulesEditor';
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TConvRulesForm, Form);
  // NOTE: a bare filename arg (ParamStr(1)) may collide with a flag value; only
  // treat ParamStr(1) as a file when it does not start with '--' and is not a
  // platform-flag value.
  if (ParamCount >= 1) and (not ParamStr(1).StartsWith('--'))
     and (not SameText(ParamStr(1), 'win32')) and (not SameText(ParamStr(1), 'win64'))
     and (not SameText(ParamStr(1), 'both')) then
    try
      Form.LoadFile(ParamStr(1));
    except
      on E: Exception do
        Application.MessageBox(PChar('Could not open ' + ParamStr(1) + #13#10 +
          E.ClassName + ': ' + E.Message), 'ConvRulesEditor', 0);
    end;
  Application.Run;
end.
```

Keep the existing `ResolveDragLintExe` function above this block unchanged.

- [ ] **Step 3: (no standalone test)** -- this task's correctness is verified by the Task 4 build + the Task 6 back-compat data-layer test. Proceed to Task 4 before building (the globals are consumed there).

- [ ] **Step 4: Commit** (after Task 4 builds clean; commit Tasks 3+4 together is acceptable, or commit now with a note that the tree does not yet compile). Recommended: commit at the end of Task 4.

---

### Task 4: MainForm consumes platforms (DB-set helpers + engine construct + LoadAllClasses)

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (constructor ~126-135; `LoadAllClasses` ~357-386; add private helpers + fields)

**Interfaces:**
- Consumes: `GEditorLibDir`, `GEditorProjectDb`, `GEditorFromPlatform`, `GEditorToPlatform` (Task 3); `LibDbsFor` (Task 1); `TEngineAdapter.SetDbs` (Task 2).
- Produces (private on `TConvRulesForm`):
  - fields `FFromPlatform, FToPlatform: TConvPlatform`
  - `function FromDbSet: TArray<string>` = `LibDbsFor(FFromPlatform, GEditorLibDir) + [GEditorProjectDb]`
  - `function ToDbSet: TArray<string>` = `LibDbsFor(FToPlatform, GEditorLibDir) + [GEditorProjectDb]`
  - `function EngineDbSet: TArray<string>` = deduped union of FromDbSet + ToDbSet

- [ ] **Step 1: Add fields + helper declarations** to `TConvRulesForm` private section. After `FToClasses` (~line 34) add:

```pascal
    FFromPlatform: TConvPlatform;     // FROM picker library platform
    FToPlatform  : TConvPlatform;     // TO picker library platform
```

In the private methods block (near `LoadAllClasses`, ~line 76) add:

```pascal
    function FromDbSet: TArray<string>;
    function ToDbSet: TArray<string>;
    function EngineDbSet: TArray<string>;
```

- [ ] **Step 2: Implement the helpers** (in the implementation section, near `LoadAllClasses`):

```pascal
{ Each side's DB set = its platform's library index + the shared project DB
  (additive, so project-declared component types still resolve). }
function TConvRulesForm.FromDbSet: TArray<string>;
begin
  Result := LibDbsFor(FFromPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

function TConvRulesForm.ToDbSet: TArray<string>;
begin
  Result := LibDbsFor(FToPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

{ The engine's default DB set (proptree/scaffold/validate/qname-resolve) must
  resolve BOTH sides' types + project units -- the deduped union of both sides. }
function TConvRulesForm.EngineDbSet: TArray<string>;
var
  seen: TDictionary<string, Boolean>;
  src, db: string;
  arr: TArray<string>;
begin
  Result := [];
  seen := TDictionary<string, Boolean>.Create;
  try
    for src in ['from', 'to'] do
    begin
      if src = 'from' then arr := FromDbSet else arr := ToDbSet;
      for db in arr do
        if not seen.ContainsKey(LowerCase(db)) then
        begin
          seen.Add(LowerCase(db), True);
          Result := Result + [db];
        end;
    end;
  finally
    seen.Free;
  end;
end;
```

- [ ] **Step 3: Seed platforms + construct the engine from `EngineDbSet`.** In the constructor (~line 126-131), after `FBook := TRuleBook.Create;` set the platform fields BEFORE creating the engine, and construct from `EngineDbSet`:

```pascal
  FBook := TRuleBook.Create;
  FFromPlatform := GEditorFromPlatform;
  FToPlatform   := GEditorToPlatform;
  FEngine := TEngineAdapter.Create(GEditorExe, EngineDbSet);
```

- [ ] **Step 4: Point `LoadAllClasses` at the helpers.** In `LoadAllClasses` (~line 365 and ~372), replace `GEditorFromDbs` with `FromDbSet` and `GEditorToDbs` with `ToDbSet`:

```pascal
  // FROM: TComponent descendants of the FROM platform's library (+ project).
  if not FEngine.ListDescendantsOf('TComponent', FromDbSet, FromNames, Err)
     or (Length(FromNames) = 0) then
    FromNames := ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit',
                  'TOvcTable', 'TTable'];
  FFromClasses := FromNames;

  // TO: TControl descendants of the TO platform's library (+ project).
  if not FEngine.ListDescendantsOf('TControl', ToDbSet, ToNames, Err)
     or (Length(ToNames) = 0) then
    ToNames := ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit',
                'TcxGrid'];
  FToClasses := ToNames;
```

- [ ] **Step 5: Build the editor** (Global Constraints recipe). Expected: exit 0, no `Error`/`Fatal`. Deploy the exe.

- [ ] **Step 6: Commit Tasks 3+4**

```bash
git add src/tools/convrules-editor/ConvRulesEditor.dpr src/tools/convrules-editor/ConvRules.MainForm.pas
git commit -m "feat(convrules-editor): per-side platform DB sets from CLI (Win32/Win64/Both)"
```

---

### Task 5: Platform dropdowns + live re-scope

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (BuildUI ~row-1 area; add combos + handlers)

**Interfaces:**
- Consumes: `FFromPlatform`/`FToPlatform`, `FromDbSet`/`ToDbSet`/`EngineDbSet` (Task 4); `PlatformToStr`/`ParsePlatform` (Task 1); `FEngine.SetDbs` (Task 2).
- Produces: two `TComboBox` (`FCbFromPlat`, `FCbToPlat`) + `procedure PlatformChanged(Sender: TObject)`.

- [ ] **Step 1: Declare the combos + handler.** In the private fields (near `FCbFrom`, ~line 43) add:

```pascal
    FCbFromPlat: TComboBox;          // FROM platform (Win32/Win64/Both)
    FCbToPlat  : TComboBox;          // TO platform
```

In the private methods block add:

```pascal
    procedure PlatformChanged(Sender: TObject);
```

- [ ] **Step 2: Build the two combos in `BuildUI`.** Immediately after the `+ New Conversion` button block (~line 228-230, before `FLblFile`), add:

```pascal
  // --- platform selectors: FROM platform / TO platform (re-scope the pickers) ---
  var LblFromPlat: TLabel := TLabel.Create(Self);
  LblFromPlat.Parent := FPanelTop; LblFromPlat.SetBounds(844, 74, 34, 15); LblFromPlat.Caption := 'FROM';
  FCbFromPlat := TComboBox.Create(Self);
  FCbFromPlat.Parent := FPanelTop; FCbFromPlat.SetBounds(882, 71, 80, 23);
  FCbFromPlat.Style := csDropDownList;
  FCbFromPlat.Items.Add('Win32'); FCbFromPlat.Items.Add('Win64'); FCbFromPlat.Items.Add('Both');
  FCbFromPlat.ItemIndex := Ord(FFromPlatform);
  FCbFromPlat.Hint := 'Library platform the FROM types come from'; FCbFromPlat.ShowHint := True;
  FCbFromPlat.OnChange := PlatformChanged;

  var LblToPlat: TLabel := TLabel.Create(Self);
  LblToPlat.Parent := FPanelTop; LblToPlat.SetBounds(968, 74, 22, 15); LblToPlat.Caption := 'TO';
  FCbToPlat := TComboBox.Create(Self);
  FCbToPlat.Parent := FPanelTop; FCbToPlat.SetBounds(994, 71, 80, 23);
  FCbToPlat.Style := csDropDownList;
  FCbToPlat.Items.Add('Win32'); FCbToPlat.Items.Add('Win64'); FCbToPlat.Items.Add('Both');
  FCbToPlat.ItemIndex := Ord(FToPlatform);
  FCbToPlat.Hint := 'Library platform the TO types come from'; FCbToPlat.ShowHint := True;
  FCbToPlat.OnChange := PlatformChanged;
```

Note: `TConvPlatform = (cpWin32, cpWin64, cpBoth)` so `Ord` maps 0/1/2 to Win32/Win64/Both -- the combo item order matches the enum order by construction.

- [ ] **Step 3: Implement `PlatformChanged`** (re-scope live). Add near `LoadAllClasses`:

```pascal
{ A platform dropdown changed: recompute both sides' platforms from the combos,
  update the engine's default DB set, clear the class caches, and reload the
  pickers so they now list the newly-selected platforms' types. }
procedure TConvRulesForm.PlatformChanged(Sender: TObject);
begin
  FFromPlatform := TConvPlatform(FCbFromPlat.ItemIndex);
  FToPlatform   := TConvPlatform(FCbToPlat.ItemIndex);
  FEngine.SetDbs(EngineDbSet);
  // Force LoadAllClasses to re-query (its guard exits when both caches are set).
  FFromClasses := [];
  FToClasses := [];
  FCbFrom.Items.Clear;
  FCbTo.Items.Clear;
  Screen.Cursor := crHourGlass;
  try
    LoadAllClasses;
    SetStatus(Format('Platforms: FROM=%s TO=%s -- %d source + %d target classes.',
      [PlatformToStr(FFromPlatform), PlatformToStr(FToPlatform),
       Length(FFromClasses), Length(FToClasses)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;
```

- [ ] **Step 4: Build the editor** (Global Constraints). Expected: exit 0, no `Error`. Deploy the exe. A 2-second launch smoke (start the exe, confirm it stays alive, close it) confirms the form still constructs.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas
git commit -m "feat(convrules-editor): FROM/TO platform dropdowns with live picker re-scope"
```

---

### Task 6: Data-layer re-scope test + back-compat lock

**Files:**
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TEngineAdapter`, `LibDbsFor`, `TConvPlatform` -- the exact spawn+parse path the pickers use (mirrors the existing `TestPickerDatasource`).

- [ ] **Step 1: Add a platform re-scope + back-compat test** (`procedure TestPlatformRescope;` called from the main body). It builds a real `TEngineAdapter` against per-platform DB sets and asserts the FROM list is discriminated by platform. SKIP (not fail) when the exe or a real library DB is absent (lean-machine safe), matching the existing convention.

```pascal
procedure TestPlatformRescope;
const
  LibDir = 'C:\Projects\.drag-lint\';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';
  Exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';
var
  eng: TEngineAdapter;
  win64Only, win32Only: TArray<string>;
  err: string;
  ok64, ok32: Boolean;
begin
  if not (FileExists(Exe) and FileExists(LibDir + 'library-Win64.sqlite')
          and FileExists(LibDir + 'library-Win32.sqlite')) then
  begin
    Skip('platform.rescope', 'exe or library DBs absent');
    Exit;
  end;
  eng := TEngineAdapter.Create(Exe, LibDbsFor(cpBoth, LibDir) + [ProjectDb]);
  try
    // FROM under Win64-only lists TOvcTable (Orpheus, Win64-indexed);
    // FROM under Win32-only does NOT -- proving platform selection re-scopes.
    ok64 := eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin64, LibDir) + [ProjectDb], win64Only, err);
    ok32 := eng.ListDescendantsOf('TComponent', LibDbsFor(cpWin32, LibDir) + [ProjectDb], win32Only, err);
    Check('platform.rescope.win64.query.ok', ok64);
    Check('platform.rescope.win32.query.ok', ok32);
    Check('platform.rescope.win64.has.TOvcTable', Contains(win64Only, 'TOvcTable'));
    Check('platform.rescope.win32.lacks.TOvcTable', not Contains(win32Only, 'TOvcTable'));
    // The two lists must actually differ (selection is real, not a no-op).
    Check('platform.rescope.win32<>win64', Length(win32Only) <> Length(win64Only));
  finally
    eng.Free;
  end;
end;
```

- [ ] **Step 2: Run tests to verify** (they either PASS with real DBs present, or SKIP cleanly). Build + run the test dpr. Expected: on this machine (DBs present) the 5 `platform.rescope.*` checks PASS; summary `0 fail`. If a `TOvcTable`-under-Win64 assumption proves wrong on the live DB, pick another Win64-only-indexed class the DB actually contains and update the assertion (verify via `drag-lint query descendants --of TComponent --db <lib>` for each platform).

- [ ] **Step 3: Commit**

```bash
git add src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "test(convrules-editor): platform re-scope discrimination + query back-compat"
```

---

## Notes for the executor

- Tasks 3 and 4 are interdependent (Task 3 removes globals Task 4's edits replace). Do both before building; a transient compile error between them is expected. Commit them together (Task 4 Step 6).
- The deployed `ConvRulesEditor.exe` is untracked -- deploy it for smoke tests but do not `git add` it.
- Live UI (actually dropping the combos and eyeballing the re-scoped lists) is not headless-verifiable; it is noted for a human click-through, as with the rest of this UI.
