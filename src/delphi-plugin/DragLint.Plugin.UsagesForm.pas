unit DragLint.Plugin.UsagesForm;

{ v0.33 Find Usages form.
  Non-modal fsStayOnTop TForm showing all callers of a symbol, grouped by
  file in a TTreeView.  Double-click on a child node navigates the editor.

  Call ShowFindUsages() from the main IDE thread only.
  The form is self-freeing (Action := caFree) and singleton-guarded. }

interface

uses
  System.Classes, Vcl.Controls;

procedure ShowFindUsages(const ASymbolName, AExePath, ADbPath: string); overload;
{ v0.40.3: pass every --db path the resolver picked so callers from
  SERVER + COMMON + library DBs show up alongside the active project's. }
procedure ShowFindUsages(const ASymbolName, AExePath: string;
  const ADbPaths: TArray<string>); overload;
procedure HideFindUsages;

{ v0.42: build the Find-Usages UI in a dock-panel tab: a symbol search box on
  top of the (reparented, non-modal) usages tree. Enter runs find-callers for
  the typed symbol against the resolved project DBs. }
procedure CreateEmbeddedUsages(AOwner: TComponent; AParent: TWinControl);

implementation

uses
  System.SysUtils, System.JSON, System.StrUtils,
  Vcl.Forms, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ToolWin,
  Vcl.ExtCtrls, Vcl.Graphics,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.DbResolver,  { v0.40.5: ResolverDiagnostic for debug node }
  DragLint.Plugin.Settings;

{ v0.40.5: local copy of the BPL build-stamp helper to avoid circular use
  with DragLint.Plugin.Editor (which already imports this unit). Same
  semantics as Editor.PluginBuildTag — reads the loaded BPL's file modtime. }
function LocalBuildTag: string;
var
  ModName: string;
  Age: TDateTime;
begin
  ModName := GetModuleName(HInstance);
  if (ModName <> '') and FileAge(ModName, Age) then
    Result := 'v0.40.5-alpha (BPL built ' +
              FormatDateTime('yyyy-mm-dd hh:nn:ss', Age) + ')'
  else
    Result := 'v0.40.5-alpha';
end;

{ ---- TUsageNodeData: stores file + line in tree node.Data ---- }

type
  TUsageNodeData = class
    FilePath: string;
    Line:     Integer;
  end;

{ ---- TDragLintUsagesForm ---- }

type
  TDragLintUsagesForm = class(TForm)
  private
    FLblTitle:   TLabel;
    FToolBar:    TToolBar;
    FBtnRefresh: TToolButton;
    FBtnClose:   TToolButton;
    FTree:       TTreeView;
    FSymbolName: string;
    FExePath:    string;
    FDbPath:     string;            { kept for legacy single-DB callers }
    FDbPaths:    TArray<string>;    { v0.40.3: multi-DB list }
    FWidth:      string;            { v0.42: narrow|wide|very-wide }
    FLastCallerNode: TTreeNode;
    procedure BtnRefreshClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages, DefaultDraw: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure ClearNodeData;
    procedure RunQuery;
    procedure ParseUsagesGrouped(const AOutput: string; out AParsed: Boolean);
    procedure NavigateToNode(ANode: TTreeNode);
    procedure ParseTextOutput(const AOutput: string);
    function  AddNodeData(AParent: TTreeNode; const AText, AFile: string;
                ALine: Integer): TTreeNode;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetWidth(const AWidth: string);   { v0.42: narrow|wide|very-wide }
    procedure LoadUsages(const ASymbolName, AExePath, ADbPath: string); overload;
    procedure LoadUsages(const ASymbolName, AExePath: string;
      const ADbPaths: TArray<string>); overload;
  end;

var
  GUsagesForm: TDragLintUsagesForm = nil;

{ ---- helper: spawn process and capture stdout+stderr ---- }

function RunCaptureStdout(const ACmdLine: string;
  out AOutput: string; ATimeoutMs: Integer): Integer;
var
  SA:         TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI:         TStartupInfoW;
  PI:         TProcessInformation;
  Buf:        array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  ExitCode:   DWORD;
  WideCmd:    string;
  SB:         TStringBuilder;
  TV:         DWORD;
begin
  Result  := -1;
  AOutput := '';
  SA.nLength              := SizeOf(SA);
  SA.bInheritHandle       := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb         := SizeOf(SI);
    SI.dwFlags    := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd),
       nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then TV := INFINITE
    else                     TV := DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TV);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---- TDragLintUsagesForm ---- }

constructor TDragLintUsagesForm.Create(AOwner: TComponent);
var
  Panel: TPanel;
begin
  inherited CreateNew(AOwner);
  { v0.40.5: stamp the form caption with the loaded BPL's modtime so a
    glance at the title bar tells the user which build is live. Mirrors
    the Test Connection dialog's PluginBuildTag pattern. }
  Caption      := 'drag-lint Find Usages  -  ' + LocalBuildTag;
  Width        := 520;
  Height       := 420;
  Position     := poDefaultPosOnly;
  FormStyle    := fsStayOnTop;
  BorderIcons  := [biSystemMenu, biMinimize, biMaximize];
  OnClose      := FormClose;
  OnDestroy    := FormDestroy;

  Panel := TPanel.Create(Self);
  Panel.Parent     := Self;
  Panel.Align      := alTop;
  Panel.Height     := 56;
  Panel.BevelOuter := bvNone;

  FLblTitle := TLabel.Create(Panel);
  FLblTitle.Parent   := Panel;
  FLblTitle.Align    := alTop;
  FLblTitle.Caption  := 'Find usages of: (none)';
  FLblTitle.Height   := 24;
  FLblTitle.Layout   := tlCenter;

  FToolBar := TToolBar.Create(Panel);
  FToolBar.Parent       := Panel;
  FToolBar.Align        := alClient;
  FToolBar.ShowCaptions := True;
  FToolBar.Flat         := True;
  FToolBar.Height       := 28;

  FBtnRefresh := TToolButton.Create(FToolBar);
  FBtnRefresh.Parent  := FToolBar;
  FBtnRefresh.Caption := 'Refresh';
  FBtnRefresh.OnClick := BtnRefreshClick;

  FBtnClose := TToolButton.Create(FToolBar);
  FBtnClose.Parent  := FToolBar;
  FBtnClose.Caption := 'Close';
  FBtnClose.OnClick := BtnCloseClick;

  FTree := TTreeView.Create(Self);
  FTree.Parent        := Self;
  FTree.Align         := alClient;
  FTree.ReadOnly      := True;
  FTree.ShowLines     := True;
  FTree.HideSelection := False;
  FTree.OnDblClick    := TreeDblClick;
  { v0.42: custom-draw caller rows so the searched identifier is highlighted
    (bold + amber) inside the code snippet. }
  FTree.OnAdvancedCustomDrawItem := TreeAdvancedCustomDrawItem;

  FLastCallerNode := nil;
  FWidth := 'narrow';
end;

procedure TDragLintUsagesForm.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  Action      := caFree;
  GUsagesForm := nil;
end;

procedure TDragLintUsagesForm.FormDestroy(Sender: TObject);
begin
  ClearNodeData;
end;

procedure TDragLintUsagesForm.ClearNodeData;

  procedure WalkNodes(ANode: TTreeNode);
  begin
    while ANode <> nil do
    begin
      WalkNodes(ANode.getFirstChild);
      if Assigned(ANode.Data) then
      begin
        TUsageNodeData(ANode.Data).Free;
        ANode.Data := nil;
      end;
      ANode := ANode.getNextSibling;
    end;
  end;

begin
  FLastCallerNode := nil;
  if FTree.Items.Count > 0 then
    WalkNodes(FTree.Items[0]);
end;

function TDragLintUsagesForm.AddNodeData(AParent: TTreeNode;
  const AText, AFile: string; ALine: Integer): TTreeNode;
var
  ND: TUsageNodeData;
begin
  ND          := TUsageNodeData.Create;
  ND.FilePath := AFile;
  ND.Line     := ALine;
  if AParent = nil then
    Result := FTree.Items.Add(nil, AText)
  else
    Result := FTree.Items.AddChild(AParent, AText);
  Result.Data := ND;
end;

function IsIdentBoundary(const AText: string; AIndex: Integer): Boolean;
{ True when position AIndex (1-based; may be 0 or > length for the edges) is
  NOT part of a Pascal identifier -- used to keep highlighting to whole-word
  matches of the symbol, so "Foo" doesn't light up inside "FooBar". }
var
  C: Char;
begin
  if (AIndex < 1) or (AIndex > Length(AText)) then Exit(True);
  C := AText[AIndex];
  Result := not (CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

procedure TDragLintUsagesForm.TreeAdvancedCustomDrawItem(
  Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
{ v0.42: full self-draw of caller rows so we can render the matched identifier
  in bold amber while leaving the rest of the snippet plain. Self-drawing (vs
  overlaying) guarantees exact alignment because every segment's X is computed
  from one origin. Only caller rows (Data with a real Line) are custom-drawn;
  file headers / debug nodes fall through to the default renderer. }
var
  ND:        TUsageNodeData;
  Txt, Term: string;
  R:         TRect;
  Cv:        TCanvas;
  Selected:  Boolean;
  X, P, StartAt: Integer;
  Seg:       string;
begin
  DefaultDraw := True;
  if Stage <> cdPrePaint then Exit;
  if FSymbolName = '' then Exit;
  if not (TObject(Node.Data) is TUsageNodeData) then Exit;
  ND := TUsageNodeData(Node.Data);
  if ND.Line <= 0 then Exit;       { only real caller rows }

  Txt  := Node.Text;
  Term := FSymbolName;
  if Pos(LowerCase(Term), LowerCase(Txt)) = 0 then Exit;  { nothing to mark }

  Cv := Sender.Canvas;
  R  := Node.DisplayRect(True);
  Selected := (cdsSelected in State) or (cdsMarked in State);

  Cv.Font.Assign(FTree.Font);
  if Selected then
  begin
    Cv.Brush.Color := clHighlight;
    Cv.Font.Color  := clHighlightText;
  end
  else
  begin
    Cv.Brush.Color := clWindow;
    Cv.Font.Color  := clWindowText;
  end;
  Cv.FillRect(R);
  Cv.Brush.Style := bsClear;

  X := R.Left + 2;
  StartAt := 1;
  repeat
    { next whole-word, case-insensitive occurrence at/after StartAt }
    P := PosEx(LowerCase(Term), LowerCase(Txt), StartAt);
    while (P > 0) and
          not (IsIdentBoundary(Txt, P - 1) and
               IsIdentBoundary(Txt, P + Length(Term))) do
      P := PosEx(LowerCase(Term), LowerCase(Txt), P + 1);

    if P = 0 then
    begin
      Seg := Copy(Txt, StartAt, MaxInt);
      if Seg <> '' then
      begin
        Cv.Font.Style := [];
        if not Selected then Cv.Font.Color := clWindowText;
        Cv.TextOut(X, R.Top, Seg);
      end;
      Break;
    end;

    { plain text before the match }
    if P > StartAt then
    begin
      Seg := Copy(Txt, StartAt, P - StartAt);
      Cv.Font.Style := [];
      if not Selected then Cv.Font.Color := clWindowText;
      Cv.TextOut(X, R.Top, Seg);
      Inc(X, Cv.TextWidth(Seg));
    end;

    { the matched identifier: bold + amber (plain bold when selected) }
    Seg := Copy(Txt, P, Length(Term));
    Cv.Font.Style := [fsBold];
    if not Selected then Cv.Font.Color := TColor($004080FF) { amber/orange BGR };
    Cv.TextOut(X, R.Top, Seg);
    Inc(X, Cv.TextWidth(Seg));

    StartAt := P + Length(Term);
  until False;

  DefaultDraw := False;
end;

procedure TDragLintUsagesForm.SetWidth(const AWidth: string);
begin
  FWidth := AWidth;
  if FSymbolName <> '' then
    RunQuery;   { re-run at the new width (cheap; query-time over the index) }
end;

procedure TDragLintUsagesForm.ParseUsagesGrouped(const AOutput: string;
  out AParsed: Boolean);
{ v0.42: render the grouped JSON from `drag-lint usages`. Top-level keys:
  declarations (kind/qname/file/line), reads/writes/calls/types/attributes/
  events (each file/line/col), and impact (depth/callers/units). Each category
  becomes a root tree node with navigable child rows. }
var
  Root: TJSONValue;
  Obj:  TJSONObject;

  procedure AddRefGroup(const AKey, ACaption: string);
  var
    Arr: TJSONArray;
    i, Ln, Cl: Integer;
    O: TJSONObject;
    F: string;
    GroupNode: TTreeNode;
  begin
    if not Obj.TryGetValue<TJSONArray>(AKey, Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode := AddNodeData(nil, Format('%s (%d)', [ACaption, Arr.Count]), '', 0);
    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O := TJSONObject(Arr.Items[i]);
      F := ''; Ln := 0; Cl := 0;
      O.TryGetValue<string>('file', F);
      O.TryGetValue<Integer>('line', Ln);
      O.TryGetValue<Integer>('col', Cl);
      AddNodeData(GroupNode,
        Format('%s:%d', [ExtractFileName(F), Ln]), F, Ln);
    end;
    GroupNode.Expand(False);
  end;

  procedure AddDeclGroup;
  var
    Arr: TJSONArray;
    i, Ln: Integer;
    O: TJSONObject;
    F, QN, Kd: string;
    GroupNode: TTreeNode;
  begin
    if not Obj.TryGetValue<TJSONArray>('declarations', Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode := AddNodeData(nil, Format('Declaration (%d)', [Arr.Count]), '', 0);
    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O := TJSONObject(Arr.Items[i]);
      F := ''; QN := ''; Kd := ''; Ln := 0;
      O.TryGetValue<string>('kind', Kd);
      O.TryGetValue<string>('qname', QN);
      O.TryGetValue<string>('file', F);
      O.TryGetValue<Integer>('line', Ln);
      AddNodeData(GroupNode,
        Format('%s  %s  (%s:%d)', [Kd, QN, ExtractFileName(F), Ln]), F, Ln);
    end;
    GroupNode.Expand(False);
  end;

  procedure AddImpactGroup;
  var
    Arr: TJSONArray;
    i, Dp, Ca, Un: Integer;
    O: TJSONObject;
    GroupNode: TTreeNode;
  begin
    if not Obj.TryGetValue<TJSONArray>('impact', Arr) then Exit;
    if Arr.Count = 0 then Exit;
    GroupNode := AddNodeData(nil, 'Impact (transitive callers)', '', 0);
    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O := TJSONObject(Arr.Items[i]);
      Dp := 0; Ca := 0; Un := 0;
      O.TryGetValue<Integer>('depth', Dp);
      O.TryGetValue<Integer>('callers', Ca);
      O.TryGetValue<Integer>('units', Un);
      AddNodeData(GroupNode,
        Format('depth %d: %d callers across %d units', [Dp, Ca, Un]), '', 0);
    end;
    GroupNode.Expand(False);
  end;

begin
  AParsed := False;
  Root := TJSONObject.ParseJSONValue(AOutput);
  if not (Root is TJSONObject) then
  begin
    if Root <> nil then Root.Free;
    Exit;
  end;
  try
    Obj := TJSONObject(Root);
    if Obj.GetValue('reads') = nil then Exit;  { not the usages shape }
    AParsed := True;
    AddDeclGroup;
    AddRefGroup('reads',      'Reads');
    AddRefGroup('writes',     'Writes');
    AddRefGroup('calls',      'Calls');
    AddRefGroup('types',      'Type uses');
    AddRefGroup('attributes', 'Attributes');
    AddRefGroup('events',     'Event handlers');
    AddImpactGroup;
  finally
    Root.Free;
  end;
end;

procedure TDragLintUsagesForm.ParseTextOutput(const AOutput: string);
{ v0.40.5: the CLI's `query find-callers` text output format is:
    <file>:<line>:<col>  <symbol_name>
       <ctx_line>: <code>
       <ctx_line>: <code>
    <file>:<line>:<col>  <symbol_name>
       ...
    N caller(s)
  No '->' anywhere. Earlier parser looked for ' -> ' and so dropped
  every match. Fix: recognise the header by trailing :LINE:COL pattern
  at the position before the symbol name (two spaces separator). }
var
  Lines:    TStringList;
  i:        Integer;
  Line:     string;
  Location: string;
  CFile:    string;
  CLine:    Integer;
  HdrSep:   Integer;
  p1, p2:  Integer;
  k:        Integer;
  LastFile: string;
  FileNode: TTreeNode;
  CallerNode: TTreeNode;
  ND:       TUsageNodeData;
  SymName:  string;
begin
  Lines     := TStringList.Create;
  LastFile  := '';
  FileNode  := nil;
  CallerNode := nil;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      if Line = '' then Continue;

      { Context sub-line (indented) }
      if Line[1] = ' ' then
      begin
        if CallerNode <> nil then
        begin
          ND := TUsageNodeData.Create;
          ND.FilePath := TUsageNodeData(CallerNode.Data).FilePath;
          ND.Line     := 0;
          var SubNode: TTreeNode;
          SubNode := FTree.Items.AddChild(CallerNode, Trim(Line));
          SubNode.Data := ND;
        end;
        Continue;
      end;

      { Skip the trailing "N caller(s)" summary line. }
      if Pos(' caller(s)', Line) > 0 then Continue;
      if Pos(' callers found', Line) > 0 then Continue;

      { Caller header line: <file>:<line>:<col>  <symbol_name>
        Two-space separator between location and name. }
      HdrSep := Pos('  ', Line);
      if HdrSep <= 0 then Continue;
      Location := Copy(Line, 1, HdrSep - 1);
      SymName  := Trim(Copy(Line, HdrSep, MaxInt));
      { Skip if SymName contains spaces (not a caller header). }
      if Pos(' ', SymName) > 0 then Continue;

      p1 := 0;
      p2 := 0;
      for k := Length(Location) downto 1 do
        if Location[k] = ':' then
        begin
          if p2 = 0 then p2 := k
          else if p1 = 0 then
          begin
            p1 := k;
            Break;
          end;
        end;
      if (p1 > 0) and (p2 > p1) then
      begin
        CFile := Copy(Location, 1, p1 - 1);
        CLine := StrToIntDef(Copy(Location, p1 + 1, p2 - p1 - 1), 0);
      end
      else
      begin
        CFile := Location;
        CLine := 0;
      end;

      if not SameText(CFile, LastFile) then
      begin
        LastFile := CFile;
        FileNode := AddNodeData(nil,
          ExtractFileName(CFile) + '  [' + CFile + ']', CFile, 0);
      end;

      CallerNode := AddNodeData(FileNode,
        Format('Line %d  %s', [CLine, SymName]),
        CFile, CLine);
      FLastCallerNode := CallerNode;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TDragLintUsagesForm.RunQuery;
var
  CmdLine, Output: string;
  ExitCode:        Integer;
  Parsed:          Boolean;
  i:               Integer;
begin
  FTree.Items.BeginUpdate;
  try
    ClearNodeData;
    FTree.Items.Clear;

    if FExePath = '' then
    begin
      AddNodeData(nil, '(drag-lint.exe path not configured)', '', 0);
      Exit;
    end;

    { v0.42: the new 'usages' command finds reads/writes/etc. (not just calls)
      and supports the width selector. }
    if FWidth = '' then FWidth := 'narrow';
    CmdLine := Format('"%s" usages --name "%s" --width %s',
      [FExePath, FSymbolName, FWidth]);
    { v0.40.3: emit one --db per resolved path. Falls back to legacy
      single-DB if FDbPaths is empty but FDbPath is set. }
    if Length(FDbPaths) > 0 then
    begin
      for var P in FDbPaths do
        if P <> '' then
          CmdLine := CmdLine + Format(' --db "%s"', [P]);
    end
    else if FDbPath <> '' then
      CmdLine := CmdLine + Format(' --db "%s"', [FDbPath]);
    CmdLine := CmdLine + ' --format json';

    ExitCode := RunCaptureStdout(CmdLine, Output, 30000);

    if ExitCode < 0 then
    begin
      AddNodeData(nil, '(failed to spawn drag-lint.exe)', '', 0);
      Exit;
    end;

    Output := Trim(Output);

    if (Length(Output) > 0) and (Output[1] = '{') then
    begin
      ParseUsagesGrouped(Output, Parsed);   { v0.42 grouped usages JSON }
      if not Parsed then
        ParseTextOutput(Output);
    end
    else
      ParseTextOutput(Output);

    if FTree.Items.Count = 0 then
    begin
      { v0.40.5: dump the raw command line + first 400 chars of stdout +
        every --db argument the resolver passed, so we can see what the
        plugin actually ran when 0 callers comes back. Top-level node
        for each. }
      var DbgRoot := AddNodeData(nil, '== DEBUG (v0.40.5): command + output ==', '', 0);
      AddNodeData(DbgRoot, 'Exit code: ' + IntToStr(ExitCode), '', 0);
      AddNodeData(DbgRoot, 'CmdLine: ' + CmdLine, '', 0);
      AddNodeData(DbgRoot, 'Output length: ' + IntToStr(Length(Output)), '', 0);
      var DbgOut := Copy(Output, 1, 400);
      AddNodeData(DbgRoot, 'Output[0..400]: ' + DbgOut, '', 0);
      if Length(FDbPaths) > 0 then
      begin
        AddNodeData(DbgRoot, 'FDbPaths count: ' + IntToStr(Length(FDbPaths)), '', 0);
        for var P2 in FDbPaths do
          AddNodeData(DbgRoot, '  - ' + P2 + ' (exists=' +
            BoolToStr(FileExists(P2), True) + ')', '', 0);
      end
      else
        AddNodeData(DbgRoot, 'FDbPaths is empty; FDbPath="' + FDbPath + '"', '', 0);

      { v0.40.5: full resolver diagnostic so we can see WHY the project DB
        was or wasn't selected. }
      var DiagRoot := AddNodeData(nil, '== DEBUG: resolver state ==', '', 0);
      var Diag := ResolverDiagnostic(LoadSettings);
      var DiagLines := TStringList.Create;
      try
        DiagLines.Text := Diag;
        for var DL in DiagLines do
          AddNodeData(DiagRoot, DL, '', 0);
      finally
        DiagLines.Free;
      end;
      DiagRoot.Expand(False);
      DbgRoot.Expand(False);

      { v0.40.3: be honest about scope. drag-lint's indexer captures
        top-level declarations (types, methods, fields, properties,
        constants, units) but NOT procedure parameters or local
        variables. If the user asked about a local they're never
        going to get a hit, so surface a useful hint instead of just
        "(no callers found)". The lowercase-A leading prefix
        (AItemLink, AButton, AParam, ASender...) is the Delphi
        convention for parameters and a strong scope signal. }
      var Hint: string;
      Hint := '(no callers found)';
      if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['A', 'a']) and
         CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint := Hint +
          '  -  "' + FSymbolName + '" looks like a parameter (A-prefix).' +
          '  drag-lint indexes types, methods, fields, and constants -' +
          ' not procedure parameters or local variables.'
      else if (Length(FSymbolName) > 1) and CharInSet(FSymbolName[1], ['F', 'f']) and
              CharInSet(FSymbolName[2], ['A'..'Z']) then
        Hint := Hint +
          '  -  "' + FSymbolName + '" looks like a private field (F-prefix).' +
          '  If this is on a class declared in the project,' +
          ' make sure the project DB is current (Tools > drag-lint > Lint Buffer).'
      else
        Hint := Hint +
          '  -  if "' + FSymbolName + '" is a procedure parameter or' +
          ' local variable, that is expected -' +
          ' drag-lint does not index local scopes.';
      AddNodeData(nil, Hint, '', 0);
    end;

    for i := 0 to FTree.Items.Count - 1 do
      if FTree.Items[i].Level = 0 then
        FTree.Items[i].Expand(False);
  finally
    FTree.Items.EndUpdate;
  end;
end;

procedure TDragLintUsagesForm.BtnRefreshClick(Sender: TObject);
begin
  RunQuery;
end;

procedure TDragLintUsagesForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TDragLintUsagesForm.NavigateToNode(ANode: TTreeNode);
var
  ND:  TUsageNodeData;
  ESS: IOTAEditorServices;
  AS_: IOTAActionServices;
  EV:  IOTAEditView;
  Pos: IOTAEditPosition;
begin
  if ANode = nil then Exit;
  if ANode.Data = nil then Exit;
  ND := TUsageNodeData(ANode.Data);
  if (ND.FilePath = '') or (ND.Line <= 0) then Exit;

  if Supports(BorlandIDEServices, IOTAActionServices, AS_) then
    AS_.OpenFile(ND.FilePath);

  if Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV := ESS.TopView;
    if EV <> nil then
    begin
      Pos := EV.Position;
      if Pos <> nil then
      begin
        Pos.GotoLine(ND.Line);
        EV.Paint;
      end;
    end;
  end;
end;

procedure TDragLintUsagesForm.TreeDblClick(Sender: TObject);
begin
  NavigateToNode(FTree.Selected);
end;

procedure TDragLintUsagesForm.LoadUsages(const ASymbolName, AExePath,
  ADbPath: string);
begin
  FSymbolName := ASymbolName;
  FExePath    := AExePath;
  FDbPath     := ADbPath;
  SetLength(FDbPaths, 0);
  FLblTitle.Caption := 'Find usages of: ' + ASymbolName;
  RunQuery;
end;

procedure TDragLintUsagesForm.LoadUsages(const ASymbolName, AExePath: string;
  const ADbPaths: TArray<string>);
begin
  FSymbolName := ASymbolName;
  FExePath    := AExePath;
  FDbPath     := '';
  FDbPaths    := ADbPaths;
  FLblTitle.Caption := 'Find usages of: ' + ASymbolName;
  RunQuery;
end;

{ ---- embedded (dock tab) ---- }

type
  { Holds the search edit + reparented usages form for a dock tab, and runs the
    query on Enter. Owned by the dock frame (AOwner) so it lives/dies with it. }
  TUsagesEmbedCtl = class(TComponent)
  public
    FUsages: TDragLintUsagesForm;
    FEdit:   TEdit;
    FCombo:  TComboBox;
    function  CurrentWidth: string;
    procedure RunFor(const ASym: string);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ComboChange(Sender: TObject);
  end;

function TUsagesEmbedCtl.CurrentWidth: string;
begin
  if FCombo = nil then Exit('narrow');
  case FCombo.ItemIndex of
    1: Result := 'wide';
    2: Result := 'very-wide';
  else Result := 'narrow';
  end;
end;

procedure TUsagesEmbedCtl.RunFor(const ASym: string);
var
  Exe: string;
  Dbs: TArray<string>;
begin
  if (ASym = '') or (FUsages = nil) then Exit;
  Exe := LoadSettings.ExePath;
  if (Exe = '') or not FileExists(Exe) then
    Exe := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Exe) then Exe := 'drag-lint.exe';
  Dbs := ResolveActiveIndexDbs(LoadSettings);
  FUsages.SetWidth(CurrentWidth);   { set width before the query }
  FUsages.LoadUsages(ASym, Exe, Dbs);
end;

procedure TUsagesEmbedCtl.EditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key <> VK_RETURN then Exit;
  Key := 0;
  RunFor(Trim(FEdit.Text));
end;

procedure TUsagesEmbedCtl.ComboChange(Sender: TObject);
begin
  { re-run at the new width if a symbol is already loaded }
  RunFor(Trim(FEdit.Text));
end;

procedure CreateEmbeddedUsages(AOwner: TComponent; AParent: TWinControl);
var
  Pnl:   TPanel;
  Lbl:   TLabel;
  Edit:  TEdit;
  Combo: TComboBox;
  Frm:   TDragLintUsagesForm;
  Ctl:   TUsagesEmbedCtl;
begin
  { search row on top: label + edit + width selector }
  Pnl := TPanel.Create(AOwner);
  Pnl.Parent     := AParent;
  Pnl.Align      := alTop;
  Pnl.Height     := 28;
  Pnl.BevelOuter := bvNone;

  Lbl := TLabel.Create(AOwner);
  Lbl.Parent  := Pnl;
  Lbl.Align   := alLeft;
  Lbl.Layout  := tlCenter;
  Lbl.Caption := ' Usages of: ';

  Combo := TComboBox.Create(AOwner);
  Combo.Parent := Pnl;
  Combo.Align  := alRight;
  Combo.Width  := 110;
  Combo.Style  := csDropDownList;
  Combo.Items.Add('Narrow');
  Combo.Items.Add('Wide');
  Combo.Items.Add('Very wide');
  Combo.ItemIndex := 0;

  Edit := TEdit.Create(AOwner);
  Edit.Parent   := Pnl;
  Edit.Align    := alClient;
  Edit.TextHint := 'symbol name, then Enter';

  { reparented usages tree fills the rest }
  Frm := TDragLintUsagesForm.Create(AOwner);
  Frm.BorderStyle := bsNone;
  Frm.FormStyle   := fsNormal;
  Frm.Align       := alClient;
  Frm.Parent      := AParent;
  Frm.Visible     := True;

  Ctl := TUsagesEmbedCtl.Create(AOwner);
  Ctl.FUsages := Frm;
  Ctl.FEdit   := Edit;
  Ctl.FCombo  := Combo;
  Edit.OnKeyDown := Ctl.EditKeyDown;
  Combo.OnChange := Ctl.ComboChange;
end;

{ ---- public API ---- }

procedure ShowFindUsages(const ASymbolName, AExePath, ADbPath: string);
begin
  if GUsagesForm = nil then
    GUsagesForm := TDragLintUsagesForm.Create(nil);

  GUsagesForm.LoadUsages(ASymbolName, AExePath, ADbPath);

  if not GUsagesForm.Visible then
    GUsagesForm.Show;
  GUsagesForm.BringToFront;
end;

procedure ShowFindUsages(const ASymbolName, AExePath: string;
  const ADbPaths: TArray<string>);
begin
  if GUsagesForm = nil then
    GUsagesForm := TDragLintUsagesForm.Create(nil);

  GUsagesForm.LoadUsages(ASymbolName, AExePath, ADbPaths);

  if not GUsagesForm.Visible then
    GUsagesForm.Show;
  GUsagesForm.BringToFront;
end;

procedure HideFindUsages;
begin
  if GUsagesForm <> nil then
  begin
    GUsagesForm.Hide;
    FreeAndNil(GUsagesForm);
  end;
end;

initialization

finalization
  if GUsagesForm <> nil then
    FreeAndNil(GUsagesForm);

end.
