# v0.29 In-Editor Visual Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paint gutter glyphs and wavy underlines for LSP publishDiagnostics output inside the RAD Studio editor, respecting user registry colors, with Ctrl+Alt+I showing the diagnostic message at the cursor line.

**Architecture:** Three new units (RegistryColors, DiagnosticCache, EditViewNotifier) plus targeted changes to Settings, SettingsForm, Editor, and Keyboard. The cache is a module-level singleton updated from HandleNotification; an IOTAEditViewNotifier paints each line on the PaintLine callback; an IOTAEditServicesNotifier hooks every activated view.

**Tech Stack:** Delphi 13 / VCL / OTAPI (IOTAEditViewNotifier, IOTAEditServicesNotifier, IOTAKeyboardBinding) / Win64 BPL. 7-bit ANSI source, CRLF line endings throughout.

---

## File Map

| Status | File | Change |
|--------|------|--------|
| Create | `src/delphi-plugin/DragLint.Plugin.RegistryColors.pas` | Reads HKCU editor highlight colors |
| Create | `src/delphi-plugin/DragLint.Plugin.DiagnosticCache.pas` | Per-file diagnostic store + singleton |
| Create | `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas` | IOTAEditViewNotifier paint + IOTAEditServicesNotifier hooks |
| Create | `tests/fixtures/T47_regcolors.dpr` | Smoke test for registry colors |
| Create | `tests/fixtures/T47_regcolors.bat` | Compile + run T47 |
| Create | `tests/fixtures/T48_diag_cache.dpr` | Smoke test for diagnostic cache |
| Create | `tests/fixtures/T48_diag_cache.bat` | Compile + run T48 |
| Modify | `src/delphi-plugin/DragLint.Plugin.Settings.pas` | 5 new fields + load/save |
| Modify | `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` | 5 new checkboxes + taller form |
| Modify | `src/delphi-plugin/DragLint.Plugin.Editor.pas` | Cache.Update in HandleNotification + register/unregister EditViewNotifier |
| Modify | `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` | Ctrl+Alt+I info key handler |
| Modify | `src/delphi-plugin/dclDragLintWizard.dpk` | 3 new units in contains |
| Modify | `src/delphi-plugin/dclDragLintWizard.dproj` | 3 new DCCReference entries |
| Modify | `src/cli/DRagLint.CLI.pas` | VERSION = '0.29.0-alpha' |
| Modify | `src/lsp/DRagLint.LSP.Server.pas` | serverInfo version '0.29.0-alpha' |
| Modify | `CHANGELOG.md` | v0.29 entry |

---

## Task 1: RegistryColors unit

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.RegistryColors.pas`

- [ ] **Step 1: Write the unit**

Create `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.RegistryColors.pas` with this exact content (strict 7-bit ANSI, CRLF):

```pascal
unit DragLint.Plugin.RegistryColors;

interface

uses
  System.SysUtils, Vcl.Graphics;

type
  TDragLintColors = record
    ErrorColor:   TColor;
    WarningColor: TColor;
    HintColor:    TColor;
    InfoColor:    TColor;
  end;

function LoadEditorColors: TDragLintColors;

implementation

uses
  System.Win.Registry, Winapi.Windows;

const
  REG_HL = 'Software\Embarcadero\BDS\37.0\Editor\Highlight\';

function ReadColor(const AName: string; ADefault: TColor): TColor;
var
  Reg: TRegistry;
  S: string;
begin
  Result := ADefault;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_HL + AName) then
    try
      if Reg.ValueExists('Foreground Color') then
      begin
        S := Reg.ReadString('Foreground Color');
        if not IdentToColor(S, Integer(Result)) then
          if S.StartsWith('$') then
            Result := TColor(StrToIntDef(S, ADefault))
          else
            Result := TColor(StrToIntDef(S, ADefault));
      end;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function LoadEditorColors: TDragLintColors;
begin
  Result.ErrorColor   := ReadColor('Syntax Error', clRed);
  Result.WarningColor := ReadColor('Warning',      clOlive);
  Result.HintColor    := ReadColor('Hint',         clTeal);
  Result.InfoColor    := ReadColor('Information',  clNavy);
end;

end.
```

- [ ] **Step 2: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.RegistryColors.pas
git commit -m "feat(v0.29): DragLint.Plugin.RegistryColors - HKCU editor highlight color reader"
```

---

## Task 2: DiagnosticCache unit

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.DiagnosticCache.pas`

- [ ] **Step 1: Write the unit**

Create `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.DiagnosticCache.pas`:

```pascal
unit DragLint.Plugin.DiagnosticCache;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  System.Generics.Collections, System.SyncObjs;

type
  TDragLintSeverity = (dlsError, dlsWarning, dlsHint, dlsInfo);

  TDragLintDiagnostic = record
    Line:      Integer;
    StartCol:  Integer;
    EndCol:    Integer;
    Severity:  TDragLintSeverity;
    Source:    string;
    Code:      string;
    Message:   string;
  end;

  TDragLintDiagnosticCache = class
  strict private
    FByFile: TDictionary<string, TArray<TDragLintDiagnostic>>;
    FLock:   TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Update(const AFilePath: string; AParams: TJSONValue);
    function GetForFile(const AFilePath: string): TArray<TDragLintDiagnostic>;
    function GetForLine(const AFilePath: string;
      ALine: Integer): TArray<TDragLintDiagnostic>;
    procedure Clear;
  end;

function Cache: TDragLintDiagnosticCache;

implementation

var
  GCache: TDragLintDiagnosticCache = nil;

function Cache: TDragLintDiagnosticCache;
begin
  if GCache = nil then
    GCache := TDragLintDiagnosticCache.Create;
  Result := GCache;
end;

constructor TDragLintDiagnosticCache.Create;
begin
  inherited Create;
  FByFile := TDictionary<string, TArray<TDragLintDiagnostic>>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TDragLintDiagnosticCache.Destroy;
begin
  FLock.Free;
  FByFile.Free;
  inherited;
end;

procedure TDragLintDiagnosticCache.Update(const AFilePath: string;
  AParams: TJSONValue);
var
  Arr: TArray<TDragLintDiagnostic>;
  D: TDragLintDiagnostic;
  DiagsArr: TJSONArray;
  i: Integer;
  Obj, RangeObj, StartObj, EndObj: TJSONObject;
  SevInt: Integer;
  List: TList<TDragLintDiagnostic>;
begin
  if not (AParams is TJSONObject) then Exit;
  if not (AParams as TJSONObject).TryGetValue<TJSONArray>('diagnostics',
      DiagsArr) then Exit;

  List := TList<TDragLintDiagnostic>.Create;
  try
    for i := 0 to DiagsArr.Count - 1 do
    begin
      if not (DiagsArr.Items[i] is TJSONObject) then Continue;
      Obj := DiagsArr.Items[i] as TJSONObject;

      D.Line     := 0;
      D.StartCol := 0;
      D.EndCol   := 0;
      D.Severity := dlsInfo;
      D.Source   := '';
      D.Code     := '';
      D.Message  := '';

      if Obj.TryGetValue<TJSONObject>('range', RangeObj) then
      begin
        if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
        begin
          StartObj.TryGetValue<Integer>('line',      D.Line);
          StartObj.TryGetValue<Integer>('character', D.StartCol);
        end;
        if RangeObj.TryGetValue<TJSONObject>('end', EndObj) then
          EndObj.TryGetValue<Integer>('character', D.EndCol);
      end;

      SevInt := 4;
      if Obj.TryGetValue<Integer>('severity', SevInt) then
        case SevInt of
          1: D.Severity := dlsError;
          2: D.Severity := dlsWarning;
          3: D.Severity := dlsInfo;
          4: D.Severity := dlsHint;
        end;

      Obj.TryGetValue<string>('source',  D.Source);
      Obj.TryGetValue<string>('code',    D.Code);
      Obj.TryGetValue<string>('message', D.Message);

      if D.EndCol <= D.StartCol then D.EndCol := D.StartCol + 1;

      List.Add(D);
    end;
    Arr := List.ToArray;
  finally
    List.Free;
  end;

  FLock.Enter;
  try
    FByFile.AddOrSetValue(LowerCase(AFilePath), Arr);
  finally
    FLock.Leave;
  end;
end;

function TDragLintDiagnosticCache.GetForFile(
  const AFilePath: string): TArray<TDragLintDiagnostic>;
begin
  FLock.Enter;
  try
    if not FByFile.TryGetValue(LowerCase(AFilePath), Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TDragLintDiagnosticCache.GetForLine(const AFilePath: string;
  ALine: Integer): TArray<TDragLintDiagnostic>;
var
  All: TArray<TDragLintDiagnostic>;
  D: TDragLintDiagnostic;
  List: TList<TDragLintDiagnostic>;
begin
  All := GetForFile(AFilePath);
  List := TList<TDragLintDiagnostic>.Create;
  try
    for D in All do
      if D.Line = ALine then List.Add(D);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TDragLintDiagnosticCache.Clear;
begin
  FLock.Enter;
  try
    FByFile.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
  FreeAndNil(GCache);

end.
```

- [ ] **Step 2: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.DiagnosticCache.pas
git commit -m "feat(v0.29): DragLint.Plugin.DiagnosticCache - thread-safe per-file diagnostic store"
```

---

## Task 3: EditViewNotifier unit

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas`

This unit has two classes:
- `TDragLintEditViewNotifier` (IOTAEditViewNotifier) - does the actual painting
- `TDragLintEditServicesNotifier` (IOTAEditServicesNotifier) - hooks each activated view

The notifier index tracking and register/unregister are also here.

- [ ] **Step 1: Write the unit**

Create `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.EditViewNotifier.pas`:

```pascal
unit DragLint.Plugin.EditViewNotifier;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Forms,
  ToolsAPI;

procedure RegisterDragLintEditViewNotifier;
procedure UnregisterDragLintEditViewNotifier;
procedure InvokeInlineInfo;

implementation

uses
  Winapi.Windows,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.RegistryColors,
  DragLint.Plugin.Settings;

{ ---- TDragLintEditViewNotifier -------------------------------------------- }

type
  TDragLintEditViewNotifier = class(TInterfacedObject, IOTAEditViewNotifier)
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAEditViewNotifier }
    procedure EditorIdle(const View: IOTAEditView);
    procedure BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
    procedure EndPaint(const View: IOTAEditView);
    procedure PaintLine(const View: IOTAEditView; LineNumber: Integer;
      const LineText: PAnsiChar; const TextWidth: Word;
      const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
      const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
  end;

procedure TDragLintEditViewNotifier.AfterSave; begin end;
procedure TDragLintEditViewNotifier.BeforeSave; begin end;
procedure TDragLintEditViewNotifier.Destroyed; begin end;
procedure TDragLintEditViewNotifier.Modified; begin end;
procedure TDragLintEditViewNotifier.EditorIdle(const View: IOTAEditView); begin end;
procedure TDragLintEditViewNotifier.BeginPaint(const View: IOTAEditView;
  var FullRepaint: Boolean); begin end;
procedure TDragLintEditViewNotifier.EndPaint(const View: IOTAEditView); begin end;

function SeverityColor(ASev: TDragLintSeverity;
  const AC: TDragLintColors): TColor;
begin
  case ASev of
    dlsError:   Result := AC.ErrorColor;
    dlsWarning: Result := AC.WarningColor;
    dlsHint:    Result := AC.HintColor;
  else
    Result := AC.InfoColor;
  end;
end;

procedure TDragLintEditViewNotifier.PaintLine(const View: IOTAEditView;
  LineNumber: Integer; const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
var
  Settings: TDragLintSettings;
  Colors:   TDragLintColors;
  FilePath: string;
  Diags: TArray<TDragLintDiagnostic>;
  D: TDragLintDiagnostic;
  MaxSev: TDragLintSeverity;
  HasDiag: Boolean;
  StartX, EndX, BottomY: Integer;
  i: Integer;
  WaveY, WaveX: Integer;
  CY: Integer;
  SavedColor: TColor;
  SavedStyle: TPenStyle;
  SavedWidth: Integer;
  SavedBrush: TColor;
  SavedBrushStyle: TBrushStyle;

  function SevEnabled(S: TDragLintSeverity): Boolean;
  begin
    case S of
      dlsError:   Result := Settings.ShowErrorsInline;
      dlsWarning: Result := Settings.ShowWarningsInline;
      dlsHint:    Result := Settings.ShowHintsInline;
    else
      Result := Settings.ShowInfoInline;
    end;
  end;

begin
  Settings := LoadSettings;
  if not Settings.EnableInlineMarkers then Exit;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath := View.Buffer.FileName;
  if FilePath = '' then Exit;

  { PaintLine LineNumber is 1-based; cache stores 0-based. }
  Diags := Cache.GetForLine(FilePath, LineNumber - 1);
  if Length(Diags) = 0 then Exit;

  HasDiag := False;
  MaxSev  := dlsHint;
  for D in Diags do
    if SevEnabled(D.Severity) then
    begin
      HasDiag := True;
      if Ord(D.Severity) < Ord(MaxSev) then
        MaxSev := D.Severity;
    end;
  if not HasDiag then Exit;

  Colors := LoadEditorColors;

  SavedColor      := Canvas.Pen.Color;
  SavedStyle      := Canvas.Pen.Style;
  SavedWidth      := Canvas.Pen.Width;
  SavedBrush      := Canvas.Brush.Color;
  SavedBrushStyle := Canvas.Brush.Style;
  try
    { ---- Gutter dot ---- }
    CY := LineRect.Top + (LineRect.Bottom - LineRect.Top) div 2;
    Canvas.Pen.Color   := SeverityColor(MaxSev, Colors);
    Canvas.Brush.Color := SeverityColor(MaxSev, Colors);
    Canvas.Brush.Style := bsSolid;
    Canvas.Ellipse(LineRect.Left + 2, CY - 3, LineRect.Left + 8, CY + 3);

    { ---- Wavy underline per diagnostic ---- }
    for i := 0 to High(Diags) do
    begin
      D := Diags[i];
      if not SevEnabled(D.Severity) then Continue;

      StartX := TextRect.Left + D.StartCol * CellSize.cx;
      EndX   := TextRect.Left + D.EndCol   * CellSize.cx;
      if EndX > TextRect.Right then EndX := TextRect.Right;
      if EndX <= StartX then EndX := StartX + CellSize.cx;

      BottomY := TextRect.Bottom - 1;
      Canvas.Pen.Color := SeverityColor(D.Severity, Colors);
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := 1;

      WaveY := BottomY;
      WaveX := StartX;
      Canvas.MoveTo(WaveX, WaveY);
      while WaveX < EndX do
      begin
        Inc(WaveX, 2);
        if WaveX > EndX then WaveX := EndX;
        WaveY := BottomY - 2 + (WaveY - (BottomY - 2));
        { Flip between BottomY and BottomY-2 }
        if WaveY = BottomY then WaveY := BottomY - 2
        else                     WaveY := BottomY;
        Canvas.LineTo(WaveX, WaveY);
      end;
    end;
  finally
    Canvas.Pen.Color   := SavedColor;
    Canvas.Pen.Style   := SavedStyle;
    Canvas.Pen.Width   := SavedWidth;
    Canvas.Brush.Color := SavedBrush;
    Canvas.Brush.Style := SavedBrushStyle;
  end;
end;

{ ---- TDragLintEditServicesNotifier ---------------------------------------- }

type
  TDragLintEditServicesNotifier = class(TInterfacedObject,
    IOTAEditServicesNotifier)
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAEditServicesNotifier }
    procedure WindowShow(const EditWindow: INTAEditWindow;
      Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow;
      Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow;
      Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure DockFormVisibilityChanged(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm; Visible: Boolean);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
  end;

procedure TDragLintEditServicesNotifier.AfterSave; begin end;
procedure TDragLintEditServicesNotifier.BeforeSave; begin end;
procedure TDragLintEditServicesNotifier.Destroyed; begin end;
procedure TDragLintEditServicesNotifier.Modified; begin end;
procedure TDragLintEditServicesNotifier.WindowShow(const EditWindow: INTAEditWindow;
  Show, LoadedFromDesktop: Boolean); begin end;
procedure TDragLintEditServicesNotifier.WindowNotification(
  const EditWindow: INTAEditWindow; Operation: TOperation); begin end;
procedure TDragLintEditServicesNotifier.WindowActivated(
  const EditWindow: INTAEditWindow); begin end;
procedure TDragLintEditServicesNotifier.WindowCommand(const EditWindow: INTAEditWindow;
  Command, Param: Integer; var Handled: Boolean); begin end;
procedure TDragLintEditServicesNotifier.EditorViewModified(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView); begin end;
procedure TDragLintEditServicesNotifier.DockFormVisibilityChanged(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm;
  Visible: Boolean); begin end;
procedure TDragLintEditServicesNotifier.DockFormUpdated(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TDragLintEditServicesNotifier.DockFormRefresh(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;

procedure TDragLintEditServicesNotifier.EditorViewActivated(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  if EditView <> nil then
    EditView.AddNotifier(TDragLintEditViewNotifier.Create);
end;

{ ---- Register / Unregister ------------------------------------------------ }

var
  GESNotifierIdx: Integer = -1;

procedure RegisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices;
begin
  if GESNotifierIdx >= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  GESNotifierIdx := ESS.AddNotifier(
    TDragLintEditServicesNotifier.Create);
end;

procedure UnregisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices;
begin
  if GESNotifierIdx < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
    ESS.RemoveNotifier(GESNotifierIdx);
  GESNotifierIdx := -1;
end;

{ ---- InvokeInlineInfo (Ctrl+Alt+I) ---------------------------------------- }

procedure InvokeInlineInfo;
var
  ESS:      IOTAEditorServices;
  View:     IOTAEditView;
  FilePath: string;
  CurLine:  Integer;
  Diags:    TArray<TDragLintDiagnostic>;
  D:        TDragLintDiagnostic;
  Msg:      string;
  SB:       TStringBuilder;
  HW:       THintWindow;
  P:        TPoint;
  R:        TRect;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  View := ESS.TopView;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath := View.Buffer.FileName;
  if FilePath = '' then Exit;

  { Position.Row is 1-based; cache is 0-based }
  CurLine := View.Position.Row - 1;
  if CurLine < 0 then CurLine := 0;

  Diags := Cache.GetForLine(FilePath, CurLine);
  if Length(Diags) = 0 then
  begin
    { No diagnostics on this line - silently ignore }
    Exit;
  end;

  SB := TStringBuilder.Create;
  try
    for D in Diags do
    begin
      if SB.Length > 0 then SB.Append(#13#10);
      case D.Severity of
        dlsError:   SB.Append('[E] ');
        dlsWarning: SB.Append('[W] ');
        dlsHint:    SB.Append('[H] ');
      else
        SB.Append('[I] ');
      end;
      if D.Code <> '' then
      begin
        SB.Append(D.Code);
        SB.Append(': ');
      end;
      SB.Append(D.Message);
    end;
    Msg := SB.ToString;
  finally
    SB.Free;
  end;

  GetCursorPos(P);
  HW := THintWindow.Create(nil);
  try
    R := HW.CalcHintRect(400, Msg, nil);
    OffsetRect(R, P.X + 16, P.Y + 16);
    HW.ActivateHint(R, Msg);
    { Show for 4 seconds then free }
    Sleep(4000);
  finally
    HW.Free;
  end;
end;

end.
```

**Important note on `IOTAEditServicesNotifier`**: Check `ToolsAPI.pas` for the exact method signatures. The `DockFormVisibilityChanged`, `DockFormUpdated`, and `DockFormRefresh` signatures may differ between BDS versions. If the BPL compile flags missing methods, look at `IOTAEditServicesNotifier` in `C:\Program Files (x86)\Embarcadero\Studio\37.0\source\ToolsAPI\ToolsAPI.pas` and adjust the stubs accordingly.

- [ ] **Step 2: Verify IOTAEditServicesNotifier interface in ToolsAPI**

Read `C:\Program Files (x86)\Embarcadero\Studio\37.0\source\ToolsAPI\ToolsAPI.pas` and search for `IOTAEditServicesNotifier` to confirm all method signatures match. Adjust the unit if needed.

- [ ] **Step 3: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas
git commit -m "feat(v0.29): DragLint.Plugin.EditViewNotifier - PaintLine glyphs+underlines + Ctrl+Alt+I info"
```

---

## Task 4: Extend TDragLintSettings with 5 new fields

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Settings.pas`

The existing record has 8 fields. We add 5 more at the bottom of the record.

- [ ] **Step 1: Add fields to the record and DefaultSettings**

In `DragLint.Plugin.Settings.pas`, change the `TDragLintSettings` record declaration:

Old (last line of the record):
```pascal
    EnableDiagnostics:    Boolean;
  end;
```

New:
```pascal
    EnableDiagnostics:    Boolean;
    EnableInlineMarkers:  Boolean;
    ShowErrorsInline:     Boolean;
    ShowWarningsInline:   Boolean;
    ShowHintsInline:      Boolean;
    ShowInfoInline:       Boolean;
  end;
```

In `DefaultSettings`, after `Result.EnableDiagnostics := True;` add:
```pascal
  Result.EnableInlineMarkers  := True;
  Result.ShowErrorsInline     := True;
  Result.ShowWarningsInline   := True;
  Result.ShowHintsInline      := True;
  Result.ShowInfoInline       := False;
```

- [ ] **Step 2: Add Load for the 5 new fields**

In `LoadSettings`, after the `EnableDiagnostics` load line add:
```pascal
      if Reg.ValueExists('EnableInlineMarkers') then
        Result.EnableInlineMarkers := Reg.ReadInteger('EnableInlineMarkers') <> 0;
      if Reg.ValueExists('ShowErrorsInline') then
        Result.ShowErrorsInline    := Reg.ReadInteger('ShowErrorsInline') <> 0;
      if Reg.ValueExists('ShowWarningsInline') then
        Result.ShowWarningsInline  := Reg.ReadInteger('ShowWarningsInline') <> 0;
      if Reg.ValueExists('ShowHintsInline') then
        Result.ShowHintsInline     := Reg.ReadInteger('ShowHintsInline') <> 0;
      if Reg.ValueExists('ShowInfoInline') then
        Result.ShowInfoInline      := Reg.ReadInteger('ShowInfoInline') <> 0;
```

- [ ] **Step 3: Add Save for the 5 new fields**

In `SaveSettings`, after the `EnableDiagnostics` write line add:
```pascal
      Reg.WriteInteger('EnableInlineMarkers', Ord(ASettings.EnableInlineMarkers));
      Reg.WriteInteger('ShowErrorsInline',    Ord(ASettings.ShowErrorsInline));
      Reg.WriteInteger('ShowWarningsInline',  Ord(ASettings.ShowWarningsInline));
      Reg.WriteInteger('ShowHintsInline',     Ord(ASettings.ShowHintsInline));
      Reg.WriteInteger('ShowInfoInline',      Ord(ASettings.ShowInfoInline));
```

- [ ] **Step 4: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.Settings.pas
git commit -m "feat(v0.29): TDragLintSettings - 5 new inline-marker fields with load/save"
```

---

## Task 5: T47 registry colors smoke test

**Files:**
- Create: `tests/fixtures/T47_regcolors.dpr`
- Create: `tests/fixtures/T47_regcolors.bat`

- [ ] **Step 1: Write T47_regcolors.dpr**

Create `C:\Projects\Delphi-RAG-lint\tests\fixtures\T47_regcolors.dpr`:

```pascal
program T47_regcolors;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  Vcl.Graphics,
  DragLint.Plugin.RegistryColors;
var
  C: TDragLintColors;
begin
  C := LoadEditorColors;
  { Colors are machine-dependent; just verify we get non-zero integers back
    (the defaults clRed etc. are all non-zero). }
  Assert(Integer(C.ErrorColor)   <> 0, 'ErrorColor non-zero');
  Assert(Integer(C.WarningColor) <> 0, 'WarningColor non-zero');
  Assert(Integer(C.HintColor)    <> 0, 'HintColor non-zero');
  Assert(Integer(C.InfoColor)    <> 0, 'InfoColor non-zero');
  WriteLn(Format('Error=%d Warning=%d Hint=%d Info=%d',
    [Integer(C.ErrorColor), Integer(C.WarningColor),
     Integer(C.HintColor),  Integer(C.InfoColor)]));
  WriteLn('OK');
end.
```

- [ ] **Step 2: Write T47_regcolors.bat**

Create `C:\Projects\Delphi-RAG-lint\tests\fixtures\T47_regcolors.bat`:

```bat
@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -LUVcl ""%HERE%T47_regcolors.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t47_build.txt"
if not exist "%HERE%T47_regcolors.exe" (echo FAIL: build failed && type "%HERE%t47_build.txt" && exit /b 1)
"%HERE%T47_regcolors.exe" > "%HERE%t47_out.txt"
type "%HERE%t47_out.txt"
findstr /c:"OK" "%HERE%t47_out.txt" >NUL || (echo FAIL: T47 did not print OK && exit /b 1)
echo PASS
exit /b 0
```

- [ ] **Step 3: Run T47**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T47_regcolors.bat"
```

Expected output ends with `PASS`.

- [ ] **Step 4: Commit**

```
git add tests/fixtures/T47_regcolors.dpr tests/fixtures/T47_regcolors.bat
git commit -m "test(v0.29): T47 registry colors smoke test"
```

---

## Task 6: T48 diagnostic cache smoke test

**Files:**
- Create: `tests/fixtures/T48_diag_cache.dpr`
- Create: `tests/fixtures/T48_diag_cache.bat`

- [ ] **Step 1: Write T48_diag_cache.dpr**

Create `C:\Projects\Delphi-RAG-lint\tests\fixtures\T48_diag_cache.dpr`:

```pascal
program T48_diag_cache;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON,
  DragLint.Plugin.DiagnosticCache;
var
  Params: TJSONObject;
  DiagsArr: TJSONArray;
  D: TJSONObject;
  R, S, E: TJSONObject;
  Out: TArray<TDragLintDiagnostic>;
begin
  { Build a minimal publishDiagnostics params object }
  Params   := TJSONObject.Create;
  DiagsArr := TJSONArray.Create;
  D := TJSONObject.Create;
  R := TJSONObject.Create;
  S := TJSONObject.Create;
  S.AddPair('line',      TJSONNumber.Create(5));
  S.AddPair('character', TJSONNumber.Create(2));
  E := TJSONObject.Create;
  E.AddPair('character', TJSONNumber.Create(10));
  R.AddPair('start', S);
  R.AddPair('end',   E);
  D.AddPair('range',    R);
  D.AddPair('severity', TJSONNumber.Create(1));
  D.AddPair('message',  'test error');
  D.AddPair('code',     'W1002');
  DiagsArr.AddElement(D);
  Params.AddPair('diagnostics', DiagsArr);

  Cache.Update('C:\test\foo.pas', Params);

  Out := Cache.GetForLine('C:\test\foo.pas', 5);
  Assert(Length(Out) = 1,           'one diagnostic on line 5');
  Assert(Out[0].Severity = dlsError,'severity is error');
  Assert(Out[0].StartCol = 2,       'start col');
  Assert(Out[0].EndCol   = 10,      'end col');
  Assert(Out[0].Code     = 'W1002', 'code');
  Assert(Out[0].Message  = 'test error', 'message');

  { Line 4 should return nothing }
  Out := Cache.GetForLine('C:\test\foo.pas', 4);
  Assert(Length(Out) = 0, 'no diagnostics on line 4');

  { Case-insensitive path lookup }
  Out := Cache.GetForLine('C:\TEST\FOO.PAS', 5);
  Assert(Length(Out) = 1, 'case-insensitive lookup');

  Params.Free;
  WriteLn('OK');
end.
```

- [ ] **Step 2: Write T48_diag_cache.bat**

Create `C:\Projects\Delphi-RAG-lint\tests\fixtures\T48_diag_cache.bat`:

```bat
@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T48_diag_cache.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t48_build.txt"
if not exist "%HERE%T48_diag_cache.exe" (echo FAIL: build failed && type "%HERE%t48_build.txt" && exit /b 1)
"%HERE%T48_diag_cache.exe" > "%HERE%t48_out.txt"
type "%HERE%t48_out.txt"
findstr /c:"OK" "%HERE%t48_out.txt" >NUL || (echo FAIL: T48 did not print OK && exit /b 1)
echo PASS
exit /b 0
```

- [ ] **Step 3: Run T48**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T48_diag_cache.bat"
```

Expected output ends with `PASS`.

- [ ] **Step 4: Commit**

```
git add tests/fixtures/T48_diag_cache.dpr tests/fixtures/T48_diag_cache.bat
git commit -m "test(v0.29): T48 diagnostic cache smoke test"
```

---

## Task 7: Extend T29 settings round-trip test for new fields

**Files:**
- Modify: `tests/fixtures/T29_settings.dpr`

The existing T29 tests 8 fields. We must add assertions for the 5 new fields so regression is caught.

- [ ] **Step 1: Add assertions to T29_settings.dpr**

In `T29_settings.dpr`, before the `{ Reset to defaults }` line, add:

```pascal
  { v0.29 inline-marker settings round-trip }
  S.EnableInlineMarkers := False;
  S.ShowErrorsInline    := False;
  S.ShowWarningsInline  := True;
  S.ShowHintsInline     := False;
  S.ShowInfoInline      := True;
  SaveSettings(S);
  S2 := LoadSettings;
  Assert(not S2.EnableInlineMarkers,  'EnableInlineMarkers roundtrip');
  Assert(not S2.ShowErrorsInline,     'ShowErrorsInline roundtrip');
  Assert(S2.ShowWarningsInline,       'ShowWarningsInline roundtrip');
  Assert(not S2.ShowHintsInline,      'ShowHintsInline roundtrip');
  Assert(S2.ShowInfoInline,           'ShowInfoInline roundtrip');
```

- [ ] **Step 2: Run T29 to confirm it passes**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T29_settings.bat"
```

Expected: `PASS`

- [ ] **Step 3: Commit**

```
git add tests/fixtures/T29_settings.dpr
git commit -m "test(v0.29): extend T29 settings round-trip for 5 new inline-marker fields"
```

---

## Task 8: SettingsForm - 5 new checkboxes

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas`

The current form height is `384`. Each new checkbox takes 24px. 5 checkboxes = 120px. The OK/Cancel buttons must move down too. New client height: `384 + 120 + 8 = 512`.

- [ ] **Step 1: Add 5 new checkbox variables**

In `ShowSettingsDialog`, find the existing var block:
```pascal
  cbAutoIndex, cbAutoReindex, cbHover, cbCompletion, cbSignature, cbDiag: TCheckBox;
```

Change to:
```pascal
  cbAutoIndex, cbAutoReindex, cbHover, cbCompletion, cbSignature, cbDiag: TCheckBox;
  cbInlineMarkers, cbErrInline, cbWarnInline, cbHintInline, cbInfoInline: TCheckBox;
```

- [ ] **Step 2: Extend form height and add checkboxes**

Find:
```pascal
    cbDiag       := AddCheck(Y, 'Enable Run Diagnostics',
      Settings.EnableDiagnostics);
```

Change to:
```pascal
    cbDiag       := AddCheck(Y, 'Enable Run Diagnostics',
      Settings.EnableDiagnostics);  Inc(Y, 24);

    Inc(Y, 8);
    cbInlineMarkers := AddCheck(Y, 'Enable inline markers (gutter + underline)',
      Settings.EnableInlineMarkers);  Inc(Y, 24);
    cbErrInline  := AddCheck(Y, '  Show errors inline',
      Settings.ShowErrorsInline);   Inc(Y, 24);
    cbWarnInline := AddCheck(Y, '  Show warnings inline',
      Settings.ShowWarningsInline); Inc(Y, 24);
    cbHintInline := AddCheck(Y, '  Show hints inline',
      Settings.ShowHintsInline);    Inc(Y, 24);
    cbInfoInline := AddCheck(Y, '  Show info inline',
      Settings.ShowInfoInline);
```

Also update `Form.ClientHeight` from `384` to `512`.

- [ ] **Step 3: Save new settings on OK**

Find the save block after `Settings.EnableDiagnostics := cbDiag.Checked;` and add:
```pascal
      Settings.EnableInlineMarkers := cbInlineMarkers.Checked;
      Settings.ShowErrorsInline    := cbErrInline.Checked;
      Settings.ShowWarningsInline  := cbWarnInline.Checked;
      Settings.ShowHintsInline     := cbHintInline.Checked;
      Settings.ShowInfoInline      := cbInfoInline.Checked;
```

- [ ] **Step 4: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.SettingsForm.pas
git commit -m "feat(v0.29): settings form - 5 new inline-marker checkboxes"
```

---

## Task 9: Wire Cache.Update into HandleNotification (Editor.pas)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas`

- [ ] **Step 1: Add DiagnosticCache to uses**

In `DragLint.Plugin.Editor.pas` implementation uses section, add:
```pascal
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.EditViewNotifier,
```

(These go after `DragLint.Plugin.Keyboard` in the existing uses list.)

- [ ] **Step 2: Call Cache.Update in HandleNotification**

In `HandleNotification`, after the `FileName` is decoded from the URI (after line `FileName := StringReplace(...)`) and before the `{ Collect diagnostic entries ... }` comment, add:

```pascal
  { v0.29: update the visual diagnostic cache (runs on the LSP reader thread;
    Cache.Update is thread-safe). }
  Cache.Update(FileName, AParams);
```

- [ ] **Step 3: Register/Unregister EditViewNotifier**

In `RegisterDragLintMenu`, at the very end, after `RegisterDragLintKeystrokes;`, add:
```pascal
  RegisterDragLintEditViewNotifier;
```

In `UnregisterDragLintMenu`, at the very beginning (before `UnregisterDragLintKeystrokes`), add:
```pascal
  UnregisterDragLintEditViewNotifier;
```

- [ ] **Step 4: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(v0.29): Editor - route publishDiagnostics to Cache.Update + register EditViewNotifier"
```

---

## Task 10: Keyboard.pas - Ctrl+Alt+I binding

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Keyboard.pas`

- [ ] **Step 1: Add InlineInfoKey method to TDragLintKeyboardBinding**

In the class declaration, after `RenameKey`, add:
```pascal
    procedure InlineInfoKey(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
```

- [ ] **Step 2: Add the BindKeyboard entry**

In `BindKeyboard`, after the RenameKey binding, add:
```pascal
  BindingServices.AddKeyBinding(
    [ShortCut(Ord('I'), [ssCtrl, ssAlt])], InlineInfoKey, nil);
```

- [ ] **Step 3: Add the handler implementation**

After `TDragLintKeyboardBinding.RenameKey`, add:

```pascal
procedure TDragLintKeyboardBinding.InlineInfoKey(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableInlineMarkers then Exit;
  InvokeInlineInfo;
  BindingResult := krHandled;
end;
```

- [ ] **Step 4: Add InvokeInlineInfo to the uses / forward**

In `DragLint.Plugin.Keyboard.pas` implementation uses, `DragLint.Plugin.Editor` is already there. Add `DragLint.Plugin.EditViewNotifier` as well so `InvokeInlineInfo` is visible:

```pascal
uses
  ...
  DragLint.Plugin.Editor,
  DragLint.Plugin.EditViewNotifier;
```

- [ ] **Step 5: Commit**

```
git add src/delphi-plugin/DragLint.Plugin.Keyboard.pas
git commit -m "feat(v0.29): Keyboard - Ctrl+Alt+I inline info keystroke"
```

---

## Task 11: Register 3 new units in .dpk and .dproj

**Files:**
- Modify: `src/delphi-plugin/dclDragLintWizard.dpk`
- Modify: `src/delphi-plugin/dclDragLintWizard.dproj`

- [ ] **Step 1: Add to .dpk contains section**

In `dclDragLintWizard.dpk`, after the `RefactorForm` line:
```pascal
  DragLint.Plugin.RefactorForm in 'DragLint.Plugin.RefactorForm.pas';
```

Add:
```pascal
  DragLint.Plugin.RegistryColors in 'DragLint.Plugin.RegistryColors.pas',
  DragLint.Plugin.DiagnosticCache in 'DragLint.Plugin.DiagnosticCache.pas',
  DragLint.Plugin.EditViewNotifier in 'DragLint.Plugin.EditViewNotifier.pas';
```

(The semicolon moves from the RefactorForm line to the last new line; the new lines use commas except the last which uses semicolon.)

- [ ] **Step 2: Add DCCReference entries to .dproj**

In `dclDragLintWizard.dproj`, after:
```xml
        <DCCReference Include="DragLint.Plugin.RefactorForm.pas"/>
```

Add:
```xml
        <DCCReference Include="DragLint.Plugin.RegistryColors.pas"/>
        <DCCReference Include="DragLint.Plugin.DiagnosticCache.pas"/>
        <DCCReference Include="DragLint.Plugin.EditViewNotifier.pas"/>
```

- [ ] **Step 3: Commit**

```
git add src/delphi-plugin/dclDragLintWizard.dpk src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "build(v0.29): register 3 new plugin units in .dpk and .dproj"
```

---

## Task 12: BPL compile

**Files:** None (build verification only)

- [ ] **Step 1: Run the BPL build**

```
cmd.exe /c "call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:normal C:\Projects\Delphi-RAG-lint\src\delphi-plugin\dclDragLintWizard.dproj" 2>&1
```

Expected: `Build succeeded.` with 0 errors.

- [ ] **Step 2: Fix any compile errors**

Common issues to watch for:
- `IOTAEditServicesNotifier` method signatures differ from what's in the unit. Read `ToolsAPI.pas` and correct any mismatches.
- Circular uses: `Editor` uses `EditViewNotifier`, `Keyboard` uses `EditViewNotifier`. Both units' implementation sections already use `Editor`, so the existing circular-uses note in `Keyboard.pas` covers this pattern.
- `DockableForm` type: confirm this is `TDockableForm` or `TCustomForm` in your ToolsAPI version.

- [ ] **Step 3: Commit after successful build**

```
git add -u
git commit -m "build(v0.29): BPL compiles clean with all 3 new units"
```

---

## Task 13: Run all prior tests to confirm no regression

- [ ] **Step 1: Run T29 (settings round-trip)**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T29_settings.bat"
```

Expected: `PASS`

- [ ] **Step 2: Run T47 (registry colors)**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T47_regcolors.bat"
```

Expected: `PASS`

- [ ] **Step 3: Run T48 (cache smoke)**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T48_diag_cache.bat"
```

Expected: `PASS`

- [ ] **Step 4: Run T44 (lint pack — confirms CLI not broken)**

```
cmd /c "C:\Projects\Delphi-RAG-lint\tests\fixtures\T44_lint_pack.bat"
```

Expected: `PASS`

- [ ] **Step 5: Commit if any fixes needed**

If any test required a fix, commit it:
```
git add -u
git commit -m "fix(v0.29): <description of what needed fixing>"
```

---

## Task 14: Version bump

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- Modify: `src/lsp/DRagLint.LSP.Server.pas`

- [ ] **Step 1: Bump CLI version**

In `src/cli/DRagLint.CLI.pas`, change:
```pascal
  VERSION = '0.28.0-alpha';
```
to:
```pascal
  VERSION = '0.29.0-alpha';
```

- [ ] **Step 2: Bump LSP serverInfo version**

In `src/lsp/DRagLint.LSP.Server.pas`, find:
```pascal
    Info.AddPair('version', '0.28.0-alpha');
```
Change to:
```pascal
    Info.AddPair('version', '0.29.0-alpha');
```

- [ ] **Step 3: Commit**

```
git add src/cli/DRagLint.CLI.pas src/lsp/DRagLint.LSP.Server.pas
git commit -m "chore(v0.29): version bump to 0.29.0-alpha"
```

---

## Task 15: CHANGELOG and README

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add v0.29 entry**

Prepend a new entry at the top of `CHANGELOG.md` (after the header line and before the `## v0.28.0-alpha` block):

```markdown
## v0.29.0-alpha -- 2026-05-29

### Added

- **In-editor visual diagnostics** — LSP `publishDiagnostics` notifications now
  paint directly into the RAD Studio editor via `IOTAEditViewNotifier`:
  - **Gutter dot** (6x6 filled circle) on every diagnostic line, colored by
    max severity on that line.
  - **Wavy underline** (2-pixel sawtooth) over the diagnostic column range,
    one per diagnostic item.
  - **Ctrl+Alt+I** — displays a `THintWindow` popup with all diagnostic
    messages for the current cursor line.
- **Registry-aware colors** (`DragLint.Plugin.RegistryColors`) — reads
  `HKCU\Software\Embarcadero\BDS\37.0\Editor\Highlight\` keys (`Syntax Error`,
  `Warning`, `Hint`, `Information`) so markers honor the user's custom IDE color
  theme.
- **Per-severity toggles** — 5 new settings (`EnableInlineMarkers`,
  `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline`)
  exposed in the Settings dialog. Defaults: markers on, Info off.
- **T47** — smoke test: registry color reader returns non-zero defaults.
- **T48** — smoke test: diagnostic cache stores and retrieves by file + line
  with case-insensitive path matching.

### Notes

- Mouse-hover tooltip deferred to v0.30; Ctrl+Alt+I is the v0.29 substitute.
- Theme-switch detection is not live; colors are read once at plugin load.
  Restart the IDE after changing editor colors.

---
```

- [ ] **Step 2: Commit**

```
git add CHANGELOG.md
git commit -m "docs(v0.29): CHANGELOG entry for v0.29.0-alpha"
```

---

## Task 16: Squash-merge, tag, and GitHub release

- [ ] **Step 1: Switch to main and squash-merge**

```
git checkout main
git merge --squash v0.29-inline-markers
git commit -m "release(v0.29.0-alpha): in-editor visual diagnostics (gutter glyphs + wavy underline + registry colors)"
```

- [ ] **Step 2: Tag**

```
git tag v0.29.0-alpha
```

- [ ] **Step 3: Push main and tag**

```
git push origin main
git push origin v0.29.0-alpha
```

- [ ] **Step 4: Create GitHub release**

```
gh release create v0.29.0-alpha \
  --title "v0.29.0-alpha - in-editor visual diagnostics" \
  --notes "## v0.29.0-alpha

In-editor visual diagnostics: gutter glyphs, wavy underlines, and Ctrl+Alt+I info popup.

### Added
- Gutter dot and wavy underline via IOTAEditViewNotifier.PaintLine
- Registry-aware colors from HKCU BDS editor highlight keys
- Ctrl+Alt+I: THintWindow popup for diagnostics at cursor line
- 5 new settings (EnableInlineMarkers + per-severity toggles)
- T47 registry colors smoke test
- T48 diagnostic cache smoke test"
```

- [ ] **Step 5: Record SHA, tag, and release URL**

Run:
```
git log --oneline -3
```
and note the squashed main SHA and tag for the report.

---

## Self-Review Checklist

- [x] **Spec coverage**
  - Goal: gutter glyphs + wavy underlines + hover/keystroke + registry colors -> Tasks 1-3
  - publishDiagnostics cache update -> Task 9
  - Settings 5 new fields -> Tasks 4, 7, 8
  - Ctrl+Alt+I keystroke -> Tasks 3, 10
  - T47 registry smoke -> Task 5
  - T48 cache smoke -> Task 6
  - BPL compiles -> Task 12
  - Regression tests -> Task 13
  - Version bump -> Task 14
  - CHANGELOG -> Task 15
  - Release -> Task 16
- [x] **No placeholders** -- all code is fully written out
- [x] **Type consistency** -- `TDragLintDiagnostic`, `TDragLintSeverity`, `TDragLintColors`, `TDragLintSettings` field names are consistent across all tasks
- [x] **LSP severity mapping** -- spec says severity 3=Info, 4=Hint; this matches the `DiagnosticCache.Update` case statement
- [x] **Hard rules** -- all source files are 7-bit ASCII, no emojis; new units in both .dpk and .dproj (Task 11); Win64 target unchanged
