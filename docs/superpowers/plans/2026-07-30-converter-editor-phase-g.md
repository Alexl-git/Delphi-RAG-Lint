# Converter Editor Phase G Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add theming, a toolbar, type navigation, a reusable enum->property mapping library, `uses`-clause harvesting, and the ReFind BDE corpus to the ConvRules editor.

**Architecture:** Logic goes in PURE units (no VCL, no I/O, no process spawn) so the console suite can test it against inline fixtures; forms stay thin and call into them. Every new DSL construct is one node per line -- the rule model is flat and stays flat. The engine is NOT touched in this phase.

**Tech Stack:** Delphi 13 / RAD Studio 37.0, VCL, `dcc64`. Tests are a console runner (`ConvRulesModelTests.dpr`) using a hand-rolled `Check`/`Skip` harness -- not DUnitX.

## Global Constraints

- `.pas` / `.dfm` are **strict 7-bit ASCII with CRLF**. The Write tool emits LF -- normalise after writing every file.
- DocInsight `///` spec-comments are REQUIRED on every public type, method and interface. The doc-comment and the test must agree.
- Failing test FIRST, then implementation. Non-negotiable.
- Naming: `TMyClass`, `FMyField`, `pMyParam`.
- Pure units may use only `System.*`. Anything touching `Vcl.*`, the registry, the filesystem or a process belongs in a form or an adapter, never in a unit the tests link.
- Build the editor: `build\_build_convrules_editor_local.bat` (call it by ABSOLUTE path -- bare-name `call` does not resolve in this environment).
- Build+run tests: `build\_build_convrules_tests_local.bat`, then run `src\tools\convrules-editor\tests\ConvRulesModelTests.exe` by ABSOLUTE path (bare name exits 9009).
- Baseline before starting: **376 pass / 0 fail / 0 skip**. Never let `skip` rise -- a skip is how this suite has silently gone vacuous three times.
- Do NOT push. Nothing is published until the engine and editor match and are tested on real forms.
- Work in the worktree `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\wt-merge-converter` on branch `merge/converter-into-main`. Never write into `C:\Projects\Delphi-RAG-lint` or `C:\Projects\Delphi-RAG-lint-converter`.

---

### Task 1: Pure theme model

**Files:**
- Create: `src\tools\convrules-editor\ConvRules.Theme.pas`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: nothing.
- Produces: `TThemeMode = (tmLight, tmDark)`; `TThemePref = (tpFollowIde, tpLight, tpDark)`; `function IdeThemeToMode(const AIdeTheme: string): TThemeMode`; `function ResolveThemeMode(APref: TThemePref; const AIdeTheme: string): TThemeMode`; `function ExamineRowColor(AWindowColor: Integer; AMode: TThemeMode): Integer`; `function ThemePrefToStr(APref: TThemePref): string`; `function StrToThemePref(const S: string; ADefault: TThemePref): TThemePref`.

- [ ] **Step 1: Write the failing test**

Add to `ConvRulesModelTests.dpr`, immediately before `procedure TestUnitDirectives;`:

```pascal
{ Pure theme model. The IDE stores its theme at HKCU\Software\Embarcadero\BDS\<ver>\
  Theme, value 'Theme' (observed: 'Dark'). Only 'Dark' means dark; every other value,
  including absent/garbage, means light -- a wrong guess here makes the editor unreadable,
  so the default is the safe one. ExamineRowColor derives the used-row marking from the
  ACTIVE window colour, because the old hard-coded $00D8F5D8 is invisible on a dark style. }
procedure TestThemeModel;
begin
  Check('theme.ide.dark',    IdeThemeToMode('Dark')    = tmDark,  'Dark');
  Check('theme.ide.dark.ci', IdeThemeToMode('dArK')    = tmDark,  'case-insensitive');
  Check('theme.ide.light',   IdeThemeToMode('Light')   = tmLight, 'Light');
  Check('theme.ide.gray',    IdeThemeToMode('Gray')    = tmLight, 'Gray is not dark');
  Check('theme.ide.empty',   IdeThemeToMode('')        = tmLight, 'absent -> light');
  Check('theme.ide.garbage', IdeThemeToMode('Zzz')     = tmLight, 'unknown -> light');

  // An explicit preference must WIN over whatever the IDE says.
  Check('theme.pref.light.wins', ResolveThemeMode(tpLight, 'Dark')  = tmLight);
  Check('theme.pref.dark.wins',  ResolveThemeMode(tpDark,  'Light') = tmDark);
  Check('theme.pref.follow',     ResolveThemeMode(tpFollowIde, 'Dark') = tmDark);
  Check('theme.pref.follow.light', ResolveThemeMode(tpFollowIde, 'Light') = tmLight);

  // The marking must DIFFER from the background it sits on, in both modes -- that is
  // the whole contract. Equality here means an invisible highlight.
  Check('theme.examine.light.differs', ExamineRowColor($00FFFFFF, tmLight) <> $00FFFFFF);
  Check('theme.examine.dark.differs',  ExamineRowColor($00202020, tmDark)  <> $00202020);
  Check('theme.examine.light.is.stable',
    ExamineRowColor($00FFFFFF, tmLight) = ExamineRowColor($00FFFFFF, tmLight), 'pure');

  Check('theme.pref.roundtrip.follow',
    StrToThemePref(ThemePrefToStr(tpFollowIde), tpLight) = tpFollowIde);
  Check('theme.pref.roundtrip.dark',
    StrToThemePref(ThemePrefToStr(tpDark), tpLight) = tpDark);
  Check('theme.pref.unknown.default', StrToThemePref('nonsense', tpFollowIde) = tpFollowIde);
end;
```

Register it by adding `TestThemeModel;` immediately before `TestPropCellText;` in the runner block, and add `ConvRules.Theme in '..\ConvRules.Theme.pas',` to the test project's `uses`.

- [ ] **Step 2: Run test to verify it fails**

Run: `build\_build_convrules_tests_local.bat` via the PowerShell `Start-Process -Wait` recipe.
Expected: FAIL to COMPILE with `F2613 Unit 'ConvRules.Theme' not found`. That is the correct first failure.

- [ ] **Step 3: Write minimal implementation**

Create `src\tools\convrules-editor\ConvRules.Theme.pas`:

```pascal
unit ConvRules.Theme;

{ Pure theme model for the conversion editor: which visual mode applies, and what
  colour the Examine "used" marking takes on top of it.

  Pure + headless -- no VCL, no registry, no I/O. The form reads the registry and the
  active style colour and passes values in, which is what makes every rule here
  unit-testable against inline fixtures. }

interface

uses
  System.SysUtils;

type
  /// <summary>The visual mode actually in force.</summary>
  TThemeMode = (tmLight, tmDark);

  /// <summary>What the user asked for. tpFollowIde defers to the IDE's own setting.</summary>
  TThemePref = (tpFollowIde, tpLight, tpDark);

/// <summary>Maps the IDE's registry theme name to a mode.</summary>
/// <param name="AIdeTheme">Value of HKCU\Software\Embarcadero\BDS\&lt;ver&gt;\Theme\Theme.</param>
/// <returns>tmDark only for 'Dark' (case-insensitive); tmLight for everything else.</returns>
/// <remarks>Light is the deliberate default for absent, empty or unrecognised values:
/// guessing dark wrongly paints dark text on a dark ground, which is unreadable, whereas
/// guessing light wrongly is merely unfashionable.</remarks>
function IdeThemeToMode(const AIdeTheme: string): TThemeMode;

/// <summary>The mode to apply given the user's preference and the IDE's setting.</summary>
/// <param name="APref">The stored preference.</param>
/// <param name="AIdeTheme">The IDE theme name; consulted only WHERE APref is tpFollowIde.</param>
function ResolveThemeMode(APref: TThemePref; const AIdeTheme: string): TThemeMode;

/// <summary>The background for a row Examine marked as used, derived from the active
/// window colour so it stays visible under any style.</summary>
/// <param name="AWindowColor">The style's resolved window colour, as a TColorRef-style
///   BGR integer.</param>
/// <param name="AMode">The mode in force.</param>
/// <returns>A colour guaranteed to differ from AWindowColor.</returns>
/// <remarks>Light mode tints green DOWN from the window colour; dark mode tints UP, so
/// the marking reads as "highlighted" against either ground.</remarks>
function ExamineRowColor(AWindowColor: Integer; AMode: TThemeMode): Integer;

/// <summary>Canonical token for a preference ('followide' | 'light' | 'dark').</summary>
function ThemePrefToStr(APref: TThemePref): string;

/// <summary>Parses a preference token; returns ADefault for anything unrecognised.</summary>
function StrToThemePref(const S: string; ADefault: TThemePref): TThemePref;

implementation

function IdeThemeToMode(const AIdeTheme: string): TThemeMode;
begin
  if SameText(Trim(AIdeTheme), 'Dark') then Result := tmDark else Result := tmLight;
end;

function ResolveThemeMode(APref: TThemePref; const AIdeTheme: string): TThemeMode;
begin
  case APref of
    tpLight: Result := tmLight;
    tpDark : Result := tmDark;
  else
    Result := IdeThemeToMode(AIdeTheme);
  end;
end;

function ExamineRowColor(AWindowColor: Integer; AMode: TThemeMode): Integer;
var
  r, g, b: Integer;
begin
  // Split the BGR integer into channels.
  r := AWindowColor and $FF;
  g := (AWindowColor shr 8) and $FF;
  b := (AWindowColor shr 16) and $FF;
  if AMode = tmLight then
  begin
    // Pull red and blue down, keep green: a pale green wash on a light ground.
    r := r - 39; if r < 0 then r := 0;
    b := b - 39; if b < 0 then b := 0;
  end
  else
  begin
    // Lift green on a dark ground; keep red/blue low so the hue stays green.
    g := g + 48; if g > 255 then g := 255;
    r := r + 8;  if r > 255 then r := 255;
    b := b + 8;  if b > 255 then b := 255;
  end;
  Result := r or (g shl 8) or (b shl 16);
end;

function ThemePrefToStr(APref: TThemePref): string;
begin
  case APref of
    tpLight: Result := 'light';
    tpDark : Result := 'dark';
  else
    Result := 'followide';
  end;
end;

function StrToThemePref(const S: string; ADefault: TThemePref): TThemePref;
var
  T: string;
begin
  T := LowerCase(Trim(S));
  if T = 'light' then Result := tpLight
  else if T = 'dark' then Result := tpDark
  else if T = 'followide' then Result := tpFollowIde
  else Result := ADefault;
end;

end.
```

Normalise to CRLF / 7-bit ASCII after writing.

- [ ] **Step 4: Run test to verify it passes**

Run the suite by absolute path.
Expected: **PASS**, total rises from 376 to 393, `0 fail / 0 skip`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Theme.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): pure theme model (IDE-follow, Light, Dark)"
```

---

### Task 2: Apply the theme in the form

**Files:**
- Modify: `src\tools\convrules-editor\ConvRules.MainForm.pas` (`GridDrawCell` ~line 1374; form creation ~line 584)
- Modify: `src\tools\convrules-editor\ConvRulesEditor.dpr`

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces: `TConvRulesForm.ApplyTheme(AMode: TThemeMode)`; global `GEditorThemePref: TThemePref`.

No new automated test: this is VCL painting and registry I/O, neither of which the console
suite can exercise. Task 1 holds the logic and IS tested. Verification here is the manual
GUI check in Step 4 -- do not skip it, and do not fake a test that would pass without the fix.

- [ ] **Step 1: Read the current painting code**

Read `ConvRules.MainForm.pas` around `GridDrawCell`. Note it hard-codes `$00D8F5D8`,
`clHighlight`, `clBtnFace`, `clWindow`, `clWindowText`, `clHighlightText`, and that
`FGrid.DefaultDrawing` is `False` -- which is exactly why a VCL style does not reach it.

- [ ] **Step 2: Add the registry read and the menu**

In `ConvRulesEditor.dpr`, before `Application.CreateForm`, read the preference and the IDE
theme, then set the global. Add to the `.dpr`:

```pascal
{ Highest installed BDS version key, e.g. '37.0'. '' when none is present. }
function HighestBdsVersion: string;
var
  Reg: TRegistry;
  Keys: TStringList;
  i: Integer;
  best: Double;
  v: Double;
begin
  Result := ''; best := -1;
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Embarcadero\BDS') then
    begin
      Reg.GetKeyNames(Keys);
      for i := 0 to Keys.Count - 1 do
        if TryStrToFloat(Keys[i], v, TFormatSettings.Invariant) and (v > best) then
        begin best := v; Result := Keys[i]; end;
    end;
  finally
    Keys.Free; Reg.Free;
  end;
end;

{ The IDE's own theme name, '' when unreadable. }
function ReadIdeTheme: string;
var
  Reg: TRegistry;
  ver: string;
begin
  Result := '';
  ver := HighestBdsVersion;
  if ver = '' then Exit;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Embarcadero\BDS\' + ver + '\Theme') then
      if Reg.ValueExists('Theme') then Result := Reg.ReadString('Theme');
  finally
    Reg.Free;
  end;
end;
```

Add `System.Win.Registry` to the `.dpr` uses. Read the stored preference from
`HKCU\Software\DragLint\ConvRulesEditor`, value `Theme`, defaulting to `tpFollowIde`, and
assign `GEditorThemePref`.

- [ ] **Step 3: Repaint through StyleServices**

Add `Vcl.Themes` to `ConvRules.MainForm.pas` uses. Replace the body of `GridDrawCell`:

```pascal
procedure TConvRulesForm.GridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var
  Cv  : TCanvas;
  Win : TColor;
begin
  Cv  := FGrid.Canvas;
  Win := StyleServices.GetSystemColor(clWindow);
  if (ARow > 0) and (gdSelected not in State)
     and (Length(FUsedProps) > 0)
     and IsRowUsed(PathOfGridCell(FGrid.Cells[0, ARow]), FUsedProps) then
    Cv.Brush.Color := TColor(ExamineRowColor(Integer(Win), FThemeMode))
  else if gdSelected in State then
    Cv.Brush.Color := StyleServices.GetSystemColor(clHighlight)
  else if gdFixed in State then
    Cv.Brush.Color := StyleServices.GetSystemColor(clBtnFace)
  else
    Cv.Brush.Color := Win;

  if gdSelected in State then Cv.Font.Color := StyleServices.GetSystemColor(clHighlightText)
  else Cv.Font.Color := StyleServices.GetSystemColor(clWindowText);

  Cv.FillRect(Rect);
  Cv.TextRect(Rect, Rect.Left + 2, Rect.Top + 2, FGrid.Cells[ACol, ARow]);
end;
```

Add `FThemeMode: TThemeMode` to the form's private fields and an `ApplyTheme` that calls
`TStyleManager.TrySetStyle` with the light or dark style name, sets `FThemeMode`, and calls
`FGrid.Invalidate`. Link the two styles into the project via *Project > Options >
Application > Appearance* (or `{$R *.res}` style resources) -- without linking, `TrySetStyle`
returns False and nothing changes.

- [ ] **Step 4: Verify manually, in the GUI**

Build and launch the editor. Confirm, and state each result explicitly:
1. It starts dark (the IDE is currently set to `Theme = Dark`).
2. `View > Theme > Light` switches immediately and the grid repaints.
3. Run Examine and confirm the used-row marking is clearly visible in BOTH modes.
4. Select a marked row and confirm the selection still wins over the marking.
5. Restart and confirm the preference persisted.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/ConvRulesEditor.dpr
git commit -m "feat(convrules-editor): follow the IDE theme, with Light/Dark override"
```

---

### Task 3: Toolbar

**Files:**
- Modify: `src\tools\convrules-editor\ConvRules.MainForm.pas`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `TConvRulesForm.FToolbar: TToolBar`; `TConvRulesForm.UpdateToolbarEnabled`.

Do this BEFORE Task 5 so the mapping-editor buttons land in their final home once.

- [ ] **Step 1: Inventory the buttons**

List every `TButton.Create` in `ConvRules.MainForm.pas` (there are 22) with its caption,
hint and handler. Write the inventory into the commit message -- it is the evidence that
nothing was dropped.

- [ ] **Step 2: Add the toolbar and move the actions**

Create a top-aligned `TToolBar` with `ShowCaptions := True`, grouped with separators:
file/working-set, mapping, examine, unit rules. Each `TToolButton.OnClick` points at the
EXISTING handler -- do not copy handler bodies. Remove the old buttons only after their
handler is wired to the new button.

- [ ] **Step 3: Gate the actions that need a selection**

Add:

```pascal
{ Enables only what the current selection supports. Several actions were previously always
  enabled and reported an error only when pressed; that is a worse experience than a
  disabled button, and it hid which state each action actually requires. }
procedure TConvRulesForm.UpdateToolbarEnabled;
begin
  FTbAssign.Enabled     := (FActiveHdr >= 0) and (FGrid.Row > 0) and (FPool.ItemIndex >= 0);
  FTbUnassign.Enabled   := (FActiveHdr >= 0) and (FGrid.Row > 0);
  FTbFindInFrom.Enabled := (FActiveHdr >= 0) and (FPool.ItemIndex >= 0);
  FTbExamine.Enabled    := (FActiveHdr >= 0);
  FTbClearExamine.Enabled := Length(FUsedProps) > 0;
end;
```

Call it from the grid's `OnSelectCell`, the pool's `OnClick`, after Examine, and after a
rule is selected.

- [ ] **Step 4: Verify manually**

Build and launch. Confirm every one of the 22 actions still works from the toolbar, and
that the gated ones enable/disable as the selection changes. State the result.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MainForm.pas
git commit -m "refactor(convrules-editor): consolidate 22 buttons into a toolbar"
```

---

### Task 4: Go to definition + enum members

**Files:**
- Create: `src\tools\convrules-editor\ConvRules.OpenSourceClient.pas` (vendored)
- Modify: `src\tools\convrules-editor\ConvRules.Engine.pas`
- Modify: `src\tools\convrules-editor\ConvRules.MainForm.pas`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TypeOfCell` (already in MainForm).
- Produces: `TEngineAdapter.ResolveTypeLocation(const AType: string; out AFile: string; out ALine: Integer; out AError: string): Boolean`; `TEngineAdapter.EnumMembersOf(const AType: string; out AMembers: TArray<string>; out AError: string): Boolean`; `function SendOpenSource(const AFile: string; ALine: Integer): Boolean`.

- [ ] **Step 1: Vendor the client**

Copy `C:\Projects\Delphi-RAG-Lint-Graph\src\control\DragLint.Graph.OpenSourceClient.pas` to
`src\tools\convrules-editor\ConvRules.OpenSourceClient.pas`. Rename the unit. Add a header:

```pascal
{ VENDORED from C:\Projects\Delphi-RAG-Lint-Graph\src\control\DragLint.Graph.OpenSourceClient.pas
  on 2026-07-30. The wire contract is frozen and documented in that repo's
  docs/ipc-open-source-contract.md -- pipe \\.\pipe\drag-lint-open-source, one framed
  message per connection. Copied rather than referenced by search path so this build does
  not depend on a sibling checkout existing at an absolute path. If the contract ever
  changes, both copies must change together. }
```

Strip anything specific to the graph viewer so it compiles standalone.

- [ ] **Step 2: Write the failing test for the parse step**

The pipe and the engine cannot run in a unit test, but the JSON shape CAN. Add:

```pascal
{ ResolveTypeLocation parses `drag-lint query --name <T> --json`. These pin the parse, which
  is the part that breaks silently: a wrong field name yields "not found" for a type that
  resolved perfectly well. }
procedure TestQueryLocationParse;
var
  f: string; ln: Integer;
begin
  Check('queryloc.parses.first.hit',
    ParseQueryLocation('{"results":[{"file":"C:\\p\\U.pas","line":42}]}', f, ln)
    and (f = 'C:\p\U.pas') and (ln = 42), f + ':' + IntToStr(ln));
  Check('queryloc.empty.results.fails',
    not ParseQueryLocation('{"results":[]}', f, ln), 'empty must not report success');
  Check('queryloc.garbage.fails',
    not ParseQueryLocation('not json', f, ln), 'garbage must not report success');

  var m: TArray<string>;
  Check('enum.members.parsed',
    ParseEnumMembers('{"results":[{"kind":"enum","members":["stOK","stCancel"]}]}', m)
    and (Length(m) = 2) and (m[0] = 'stOK'), 'members');
  Check('enum.nonenum.yields.none',
    not ParseEnumMembers('{"results":[{"kind":"class"}]}', m), 'a class has no members');
end;
```

Register it. Put `ParseQueryLocation` and `ParseEnumMembers` in `ConvRules.Engine.pas`'s
interface as PURE free functions taking the raw JSON text.

- [ ] **Step 2a: Confirm the real JSON shape before trusting the fixture**

Run once and read the actual output; correct the fixtures above if the field names differ:

```
C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\drag-lint.exe query --name TNotifyEvent --json --db C:\Projects\.drag-lint\library-Win64.sqlite
```

A fixture invented from imagination is worse than no test.

- [ ] **Step 3: Run test to verify it fails**

Expected: compile failure, `ParseQueryLocation` not found.

- [ ] **Step 4: Implement the two parsers and the adapter verbs**

Implement `ParseQueryLocation` / `ParseEnumMembers` with `System.JSON`, then
`ResolveTypeLocation` / `EnumMembersOf` on `TEngineAdapter` using the existing
`RunCapture` (so `ENGINE_TIMEOUT_MS` applies for free).

- [ ] **Step 5: Run test to verify it passes**

Expected: PASS, `0 fail / 0 skip`.

- [ ] **Step 6: Wire the context menu**

Add a `TPopupMenu` on the grid and the pool. The item caption is
`'Go to definition of ' + TypeOfCell(<cell>)`, and it is hidden when that is empty. On
click: resolve, then `SendOpenSource`; if that returns False, show `file:line` in the
status bar and copy it to the clipboard. When `EnumMembersOf` succeeds, append the member
list to the status text.

- [ ] **Step 7: Verify manually**

With RAD Studio open, right-click a `Style : TabcButtonStyle` cell and confirm the IDE
jumps to the declaration. Close the IDE and confirm it degrades to file:line + clipboard
instead of failing silently. State both results.

- [ ] **Step 8: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.OpenSourceClient.pas src/tools/convrules-editor/ConvRules.Engine.pas src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): go to a type's definition in the IDE, list enum members"
```

---

### Task 5: `#mapping` / `#apply` in the rule model

**Files:**
- Modify: `src\tools\convrules-editor\ConvRules.Model.pas`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: nothing.
- Produces: `rnkMapping`, `rnkApply` added to `TRuleNodeKind`; `TSetPair = record ToPath, Value: string; end;` and on `TRuleNode`: `MapName: string`, `MapFromType: string`, `MapToTypes: TArray<string>`, `WhenFrom: string`, `WhenValue: string`, `IsElse: Boolean`, `Sets: TArray<TSetPair>`, `ApplyName: string`.

- [ ] **Step 1: Write the failing test**

```pascal
{ #mapping declares a reusable enum -> property-value mapping ONCE, narrowed to a source
  enum and one or more target classes; #apply pulls it into a #convert block. One node per
  line -- the model is flat and must stay flat. #apply is NOT #use: #use already means
  "add a unit to the uses clause". }
procedure TestMappingRules;
var
  B: TRuleBook;
  N: TRuleNode;
begin
  B := TRuleBook.Create;
  try
    N := B.ParseLine('#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton');
    Check('mapping.kind', N.Kind = rnkMapping);
    Check('mapping.name', N.MapName = 'XYZStyle', N.MapName);
    Check('mapping.fromtype', N.MapFromType = 'XYZ.TXYZButtonStyle', N.MapFromType);
    Check('mapping.totypes.count', Length(N.MapToTypes) = 2, IntToStr(Length(N.MapToTypes)));
    Check('mapping.totypes.second', N.MapToTypes[1] = 'cxButtons.TcxBigButton', N.MapToTypes[1]);

    N := B.ParseLine('#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk');
    Check('when.kind', N.Kind = rnkMapping);
    Check('when.name', N.MapName = 'XYZStyle', N.MapName);
    Check('when.from', N.WhenFrom = 'Style', N.WhenFrom);
    Check('when.value', N.WhenValue = 'stOK', N.WhenValue);
    Check('when.not.else', not N.IsElse);
    Check('when.sets.count', Length(N.Sets) = 2, IntToStr(Length(N.Sets)));
    Check('when.sets.0.path', N.Sets[0].ToPath = 'Default', N.Sets[0].ToPath);
    Check('when.sets.0.value', N.Sets[0].Value = 'True', N.Sets[0].Value);
    Check('when.sets.1.path', N.Sets[1].ToPath = 'ModalResult', N.Sets[1].ToPath);

    // Multi-level target paths must survive -- the whole point of the path model.
    N := B.ParseLine('#mapping XYZStyle #when Style = stOK -> Style.ModalResult.Default = True');
    Check('when.nested.path', N.Sets[0].ToPath = 'Style.ModalResult.Default', N.Sets[0].ToPath);

    N := B.ParseLine('#mapping XYZStyle #else -> ModalResult = mrNone');
    Check('else.is.else', N.IsElse);
    Check('else.sets', (Length(N.Sets) = 1) and (N.Sets[0].Value = 'mrNone'));

    N := B.ParseLine('#apply XYZStyle');
    Check('apply.kind', N.Kind = rnkApply);
    Check('apply.name', N.ApplyName = 'XYZStyle', N.ApplyName);

    // #use must NOT be mistaken for #apply.
    N := B.ParseLine('#use FireDAC.Comp.Client');
    Check('use.still.means.unit', N.Kind = rnkUse, 'use must stay a uses-clause directive');
  finally
    B.Free;
  end;
end;

{ An unedited line must come back byte-for-byte; a rule book that rewrites lines it did not
  change makes every diff unreadable. }
procedure TestMappingRoundTrip;
const
  SRC =
    '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton'#13#10 +
    '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'#13#10 +
    '#mapping XYZStyle #else -> ModalResult = mrNone'#13#10 +
    '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'#13#10 +
    '  #apply XYZStyle'#13#10;
var
  B: TRuleBook;
begin
  B := TRuleBook.Create;
  try
    B.LoadFromString(SRC);
    Check('mapping.roundtrip.exact', B.SaveToString = SRC, 'round-trip altered the text');
  finally
    B.Free;
  end;
end;
```

Register both.

- [ ] **Step 2: Run test to verify it fails**

Expected: compile failure -- `rnkMapping` undeclared.

- [ ] **Step 3: Implement**

Add `rnkMapping, rnkApply` to `TRuleNodeKind`, the `TSetPair` record and the new
`TRuleNode` fields with DocInsight comments. Extend `ParseLine`: match `#mapping` first,
then read either `from <Type> to <List>` or `#when <Path> = <Value> -> <sets>` or
`#else -> <sets>`. Split the set list on top-level commas; split each pair on the FIRST
`=`. Extend `Emit` to regenerate all three forms, and `#apply`.

Order matters: test `#apply` BEFORE `#use` in the directive chain only if prefix matching
could confuse them -- they differ from the first character, so either order is safe, but
add the `#use` assertion above regardless.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, `0 fail / 0 skip`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Model.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): #mapping/#apply -- reusable conditional enum to property rules"
```

---

### Task 6: Mapping validation

**Files:**
- Create: `src\tools\convrules-editor\ConvRules.Mappings.pas`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: Task 5's node fields; `TProptree`/`TPropLeaf` from `ConvRules.Engine`.
- Produces: `TMappingIssueKind = (mikUndefined, mikTargetMissing, mikTargetReadOnly, mikBadLiteral, mikToTypeNotDeclared, mikNonExhaustive)`; `TMappingIssue = record Kind: TMappingIssueKind; MapName, Detail: string; end;` `function ValidateMappings(const ANodes: TArray<TRuleNode>; const AToTree: TProptree; const AEnumMembers: TArray<string>; const ABlockToType: string): TArray<TMappingIssue>`.

- [ ] **Step 1: Write the failing test**

```pascal
{ Validation is what makes the mapping trustworthy: an unwritable or absent target is a rule
  that will silently do nothing at apply time. Non-exhaustive is a WARNING, not an error --
  leaving a member unmapped is a legitimate choice. }
procedure TestMappingValidation;
var
  Tree: TProptree;
  Nodes: TArray<TRuleNode>;
  Issues: TArray<TMappingIssue>;

  function HasKind(const A: TArray<TMappingIssue>; K: TMappingIssueKind): Boolean;
  var it: TMappingIssue;
  begin
    for it in A do if it.Kind = K then Exit(True);
    Result := False;
  end;
begin
  Tree := MakeTreeFixture([
    MakeLeaf('Default',     'Boolean',      True),
    MakeLeaf('ModalResult', 'TModalResult', True),
    MakeLeaf('Handle',      'HWND',         False)   // read-only
  ]);

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Issues := ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton');
  Check('validate.clean', Length(Issues) = 0, 'a valid mapping reported issues');

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Nope = True'
  ]);
  Check('validate.missing.target',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetMissing));

  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Handle = 1'
  ]);
  Check('validate.readonly.target',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'cxButtons.TcxButton'), mikTargetReadOnly));

  // Applying to a class the mapping never declared.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Check('validate.totype.not.declared',
    HasKind(ValidateMappings(Nodes, Tree, ['stOK'], 'Vcl.StdCtrls.TButton'), mikToTypeNotDeclared));

  // Two members, one #when, no #else -> WARN, and it must NOT be reported as an error kind.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True'
  ]);
  Issues := ValidateMappings(Nodes, Tree, ['stOK', 'stCancel'], 'cxButtons.TcxButton');
  Check('validate.nonexhaustive.warns', HasKind(Issues, mikNonExhaustive));
  Check('validate.nonexhaustive.not.fatal',
    not HasKind(Issues, mikTargetMissing), 'a gap must not masquerade as a missing target');

  // An #else closes the gap.
  Nodes := ParseAll([
    '#mapping M from X.TStyle to cxButtons.TcxButton',
    '#mapping M #when Style = stOK -> Default = True',
    '#mapping M #else -> ModalResult = mrNone'
  ]);
  Check('validate.else.closes.gap',
    not HasKind(ValidateMappings(Nodes, Tree, ['stOK','stCancel'], 'cxButtons.TcxButton'),
                mikNonExhaustive));

  Check('validate.apply.undefined',
    HasKind(ValidateMappings(ParseAll(['#apply Ghost']), Tree, [], 'cxButtons.TcxButton'),
            mikUndefined));
end;
```

Write the `MakeTreeFixture` / `MakeLeaf` / `ParseAll` helpers next to the test if the file
has no equivalents; check first -- several fixture helpers already exist.

- [ ] **Step 2: Run test to verify it fails**

Expected: compile failure, `ValidateMappings` not found.

- [ ] **Step 3: Implement `ConvRules.Mappings.pas`**

Pure unit. Group nodes by `MapName`; for each `#apply`, find its declaration; check the
block's To type against `MapToTypes`; for every `Sets` entry check the path exists in
`AToTree` and `IsWritable`; when `AEnumMembers` is non-empty, check every `WhenValue` is a
member and report `mikNonExhaustive` if a member has neither a `#when` nor an `#else`.
DocInsight on every public declaration.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, `0 fail / 0 skip`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Mappings.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): validate #mapping targets, declared To types and exhaustiveness"
```

---

### Task 7: Mapping editor UI

**Files:**
- Create: `src\tools\convrules-editor\ConvRules.MappingForm.pas`
- Modify: `src\tools\convrules-editor\ConvRules.MainForm.pas`

**Interfaces:**
- Consumes: Tasks 4 (`EnumMembersOf`), 5 (node fields), 6 (`ValidateMappings`).
- Produces: `TMappingForm.EditMapping(const AName: string; var ANodes: TArray<TRuleNode>): Boolean`.

Verification is manual -- the logic it drives is already covered by Tasks 5 and 6.

- [ ] **Step 1: Build the form in code**

Follow the existing convention: no `.dfm`, controls created in the constructor. Left: a
list of the source enum's members (from `EnumMembersOf`, falling back to the members named
in existing `#when` lines when the type does not resolve). Right: a grid of
`ToPath | Value` for the selected member, with Add and Remove. A `#else` pseudo-member sits
at the end of the member list.

- [ ] **Step 2: Validate live**

After every edit call `ValidateMappings` and show the issues in a status strip. Warnings
(`mikNonExhaustive`, `mikBadLiteral`) are shown but do NOT block OK; errors
(`mikTargetMissing`, `mikTargetReadOnly`, `mikToTypeNotDeclared`, `mikUndefined`) do.

- [ ] **Step 3: Hook it up**

Add a `Mappings...` toolbar button (Task 3's mapping group). In `RefreshGrid`, render a
From leaf consumed by a `#when` as `<conditional: N cases>` in the To column, and treat it
as assigned so `RefreshPool` stops offering it. Make Auto-Match skip such rows.

- [ ] **Step 4: Verify manually**

Create a mapping against a real enum, add two targets to one member, save, reload, confirm
the file round-trips and the grid shows `<conditional: N cases>`. State the result.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.MappingForm.pas src/tools/convrules-editor/ConvRules.MainForm.pas
git commit -m "feat(convrules-editor): mapping editor for conditional enum rules"
```

---

### Task 8: Harvest `uses` clauses in Examine

**Files:**
- Modify: `src\tools\convrules-editor\ConvRules.Usage.pas`
- Modify: `src\tools\convrules-editor\ConvRules.MainForm.pas`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: the existing Examine file-picking path.
- Produces: `function ScanUsesClauses(const APasText: string): TArray<string>`.

- [ ] **Step 1: Write the failing test**

```pascal
{ Harvesting the units a form actually uses is what turns the Unit Rules tab from a blank
  page into a work list. Both clauses count; a unit used only in the implementation still
  has to be converted. }
procedure TestScanUsesClauses;
const
  SRC =
    'unit Foo;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  Winapi.Windows, FLDRDEF,'#13#10 +
    '  DBTables;'#13#10 +
    'implementation'#13#10 +
    'uses BDEConst, Vcl.Forms;'#13#10 +
    'end.'#13#10;
var
  u: TArray<string>;
  function Has(const N: string): Boolean;
  var s: string;
  begin
    for s in u do if SameText(s, N) then Exit(True);
    Result := False;
  end;
begin
  u := ScanUsesClauses(SRC);
  Check('uses.interface.harvested', Has('FLDRDEF'), 'FLDRDEF');
  Check('uses.multiline.harvested', Has('DBTables'), 'DBTables (second line of the clause)');
  Check('uses.implementation.harvested', Has('BDEConst'), 'BDEConst');
  Check('uses.dotted.kept.whole', Has('Winapi.Windows'), 'a dotted unit is ONE name');
  Check('uses.count', Length(u) = 5, IntToStr(Length(u)));

  // 'uses' inside a comment or a string must not create phantom units.
  Check('uses.in.comment.ignored',
    Length(ScanUsesClauses('// uses Ghost;'#13#10'implementation'#13#10)) = 0, 'comment');
end;
```

- [ ] **Step 2: Run test to verify it fails**

Expected: compile failure, `ScanUsesClauses` not found.

- [ ] **Step 3: Implement**

Add `ScanUsesClauses` to `ConvRules.Usage.pas` -- pure, taking text. Scan for a `uses`
keyword at statement position, accumulate to the terminating `;`, split on commas, trim,
skip `//` and `{ }` comment content. Keep dotted names whole. De-duplicate
case-insensitively. DocInsight stating the interface+implementation rule and the
comment-skipping limitation.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, `0 fail / 0 skip`.

- [ ] **Step 5: Prefill the Unit Rules tab**

In `DoExamine`, after the property scan, call `ScanUsesClauses` on every selected `.pas`,
merge, and prefill the Unit Rules FROM list. Do NOT create rules -- only offer candidates.
Skip units that already have a `#use`/`#unuse`/`#useswap` rule. Let the user delete rows,
and let one source unit map to several replacements via the existing `#useswap`.

- [ ] **Step 6: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.Usage.pas src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules-editor): Examine harvests uses clauses into the Unit Rules FROM list"
```

---

### Task 9: Adopt the ReFind BDE->FireDAC corpus

**Files:**
- Create: `src\tools\convrules-editor\tests\fixtures\FireDAC_Migrate_BDE.txt` (copied)
- Create: `src\tools\convrules-editor\tests\fixtures\FireDAC_Rename_Units.txt` (copied)
- Create: `docs\converter\refind-corpus.md`
- Test: `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TRuleBook.LoadFromString` / `SaveToString`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Copy the corpus**

From `C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples\Object Pascal\Database\FireDAC\Tool\reFind\`:
`BDE2FDMigration\FireDAC_Migrate_BDE.txt` and `AD2FDMigration\FireDAC_Rename_Units.txt`.
Copy VERBATIM -- do not reformat, do not convert line endings, do not "fix" anything.

- [ ] **Step 2: Write the failing test**

```pascal
{ Our DSL is a reFind superset, so Embarcadero's own migration file should load without
  landing in rnkUnknown -- that is the claim, and this is what checks it. It also gives us
  a real corpus instead of invented fixtures. Skips (visibly) when the fixture is absent. }
procedure TestReFindCorpusLoads;
var
  B: TRuleBook;
  path, txt: string;
  N: TRuleNode;
  unknown, recognised: Integer;
begin
  path := FixturePath('FireDAC_Migrate_BDE.txt');
  if not TFile.Exists(path) then
  begin
    Skip('refind.bde', 'fixture absent: ' + path);
    Exit;
  end;
  txt := TFile.ReadAllText(path);
  B := TRuleBook.Create;
  try
    B.LoadFromString(txt);
    unknown := 0; recognised := 0;
    // NOTE: ConvRules.Model exposes NodesInBlock / UnitNodes / ConvertHeaders. Check its
    // interface for an all-nodes accessor BEFORE writing this loop; if none exists, add
    //   function AllNodes: TArray<TRuleNode>;
    // to TRuleBook (with DocInsight) as part of THIS task rather than inventing a call.
    for N in B.AllNodes do
      if N.Kind = rnkUnknown then Inc(unknown)
      else if not (N.Kind in [rnkBlank, rnkComment]) then Inc(recognised);

    // The file is known to use #unuse, #remove, #remove DFM: and #migrate -- all of which
    // this DSL claims to support. A non-trivial recognised count guards against a parser
    // that "passes" by classifying everything as blank.
    Check('refind.bde.recognised.nontrivial', recognised >= 20, IntToStr(recognised));
    Check('refind.bde.no.unknown', unknown = 0, Format('%d unknown lines', [unknown]));
    Check('refind.bde.roundtrip', B.SaveToString = txt, 'round-trip altered the corpus');
  finally
    B.Free;
  end;
end;
```

Add a `FixturePath` helper resolving relative to the test exe. Register the test.

- [ ] **Step 3: Run it and READ the failures**

Expected: this may legitimately FAIL on first run, and that is the point -- it measures how
close the DSL really is. For every `rnkUnknown` line, decide explicitly:
- the DSL supports it and the parser is wrong -> fix the parser, in its own commit;
- the DSL does not support it -> keep it verbatim as `rnkUnknown` (never drop it) and
  record the construct in `docs\converter\refind-corpus.md`.

Do NOT weaken the assertion to make it green. Lowering `recognised >= 20` or deleting the
`no.unknown` check is exactly the failure mode this task exists to prevent.

- [ ] **Step 4: Document what was adopted**

Write `docs\converter\refind-corpus.md`: where the files came from, which constructs
loaded cleanly, which did not and why, and that the `BDE2FDMigration\Demo` mastapp project
is available as a real-form scan fixture. Note the licensing position -- Embarcadero sample
files, internal use only while unpublished, revisit before any public release.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/tests/fixtures docs/converter/refind-corpus.md src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "test(convrules): adopt the ReFind BDE->FireDAC corpus as a fixture"
```

---

### Task 10: Full verification pass

**Files:** none changed unless a defect is found.

- [ ] **Step 1: Clean build both artifacts**

Build the editor and the test runner from scratch. Expect `BUILD_EXITCODE=0` and no
`[dcc64 Error]`.

- [ ] **Step 2: Run the suite and read the counts**

Expected: all green, **`0 fail` AND `0 skip`**. A skip means a live test silently did not
run -- treat it as a failure and find out why.

- [ ] **Step 3: Deploy the PAIR and smoke-test**

Copy `ConvRulesEditor.exe` AND `drag-lint.exe` (plus `drag-lint.json` and the three
`tree-sitter*.dll`) to
`C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\`, backing up the previous set
first. Confirm `drag-lint.exe --help | findstr refs-as-leaves` matches before shipping.

- [ ] **Step 4: Exercise it on a real form**

Open `sample.rules`, run Examine over a real ORM3 form, and confirm: search boxes filter,
used rows are marked in both themes, the To column shows types, Go to definition opens the
IDE, and a mapping round-trips.

- [ ] **Step 5: Update the records**

Update `docs\converter\BACKLOG-editor-features.md` (mark G1-G5, G7 done) and
`docs\RESUME-proptree-and-converter.md`. Reconcile the spec: if anything was built
differently from `2026-07-30-converter-editor-phase-g-design.md`, amend the spec -- a stale
spec is worse than none.

- [ ] **Step 6: Commit**

```bash
git add -A docs
git commit -m "docs(converter): reconcile Phase G spec and backlog with what shipped"
```

---

## Not in this plan

- **The engine.** `#mapping` is authored and validated by the editor; `convert-apply`
  ignores it until the engine gains conditional, per-instance evaluation. See G6.1 of the
  spec. Do not file this as a bug.
- **G8, the documentation deliverable** (DSL design message + human manual) -- written
  after this plan lands, describing what exists.
- Pushing anything to GitHub.
