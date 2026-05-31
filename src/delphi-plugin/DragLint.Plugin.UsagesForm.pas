unit DragLint.Plugin.UsagesForm;

{ v0.33 Find Usages form.
  Non-modal fsStayOnTop TForm showing all callers of a symbol, grouped by
  file in a TTreeView.  Double-click on a child node navigates the editor.

  Call ShowFindUsages() from the main IDE thread only.
  The form is self-freeing (Action := caFree) and singleton-guarded. }

interface

procedure ShowFindUsages(const ASymbolName, AExePath, ADbPath: string); overload;
{ v0.40.3: pass every --db path the resolver picked so callers from
  SERVER + COMMON + library DBs show up alongside the active project's. }
procedure ShowFindUsages(const ASymbolName, AExePath: string;
  const ADbPaths: TArray<string>); overload;
procedure HideFindUsages;

implementation

uses
  System.SysUtils, System.Classes, System.JSON,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ToolWin,
  Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI;

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
    FLastCallerNode: TTreeNode;
    procedure BtnRefreshClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure ClearNodeData;
    procedure RunQuery;
    procedure NavigateToNode(ANode: TTreeNode);
    procedure ParseJsonOutput(const AOutput: string; out AParsed: Boolean);
    procedure ParseTextOutput(const AOutput: string);
    function  AddNodeData(AParent: TTreeNode; const AText, AFile: string;
                ALine: Integer): TTreeNode;
  public
    constructor Create(AOwner: TComponent); override;
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

  FLastCallerNode := nil;
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

procedure TDragLintUsagesForm.ParseJsonOutput(const AOutput: string;
  out AParsed: Boolean);
var
  JRoot:    TJSONValue;
  JObj:     TJSONObject;
  JCallers: TJSONArray;
  JCaller:  TJSONObject;
  i:        Integer;
  CFile:    string;
  CLine:    Integer;
  CCtx:     string;
  LastFile: string;
  FileNode: TTreeNode;
  CNode:    TTreeNode;
begin
  AParsed  := False;
  JRoot := TJSONObject.ParseJSONValue(AOutput);
  if JRoot = nil then Exit;
  try
    if not (JRoot is TJSONObject) then Exit;
    JObj := JRoot as TJSONObject;
    if not JObj.TryGetValue<TJSONArray>('callers', JCallers) then Exit;

    AParsed  := True;
    LastFile := '';
    FileNode := nil;
    for i := 0 to JCallers.Count - 1 do
    begin
      if not (JCallers.Items[i] is TJSONObject) then Continue;
      JCaller := JCallers.Items[i] as TJSONObject;
      CFile   := '';
      CLine   := 0;
      CCtx    := '';
      JCaller.TryGetValue<string>('file',    CFile);
      JCaller.TryGetValue<Integer>('line',   CLine);
      JCaller.TryGetValue<string>('context', CCtx);

      if not SameText(CFile, LastFile) then
      begin
        LastFile := CFile;
        FileNode := AddNodeData(nil,
          ExtractFileName(CFile) + '  [' + CFile + ']', CFile, 0);
      end;

      CNode := AddNodeData(FileNode,
        Format('Line %d  %s', [CLine, Trim(CCtx)]), CFile, CLine);
      FLastCallerNode := CNode;
    end;
  finally
    JRoot.Free;
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

    CmdLine := Format('"%s" query find-callers --name "%s" --context 3',
      [FExePath, FSymbolName]);
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
      ParseJsonOutput(Output, Parsed);
      if not Parsed then
        ParseTextOutput(Output);
    end
    else
      ParseTextOutput(Output);

    if FTree.Items.Count = 0 then
    begin
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
      if (Length(FSymbolName) > 1) and (FSymbolName[1] in ['A', 'a']) and
         (FSymbolName[2] in ['A'..'Z']) then
        Hint := Hint +
          '  -  "' + FSymbolName + '" looks like a parameter (A-prefix).' +
          '  drag-lint indexes types, methods, fields, and constants -' +
          ' not procedure parameters or local variables.'
      else if (Length(FSymbolName) > 1) and (FSymbolName[1] in ['F', 'f']) and
              (FSymbolName[2] in ['A'..'Z']) then
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
