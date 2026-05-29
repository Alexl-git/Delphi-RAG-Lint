unit DragLint.Plugin.Editor;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  Vcl.Menus, Vcl.Dialogs,
  ToolsAPI,
  DragLint.Plugin.LspClient,
  DragLint.Plugin.ProjectNotifier,
  DragLint.Plugin.Settings,
  DragLint.Plugin.SettingsForm,
  DragLint.Plugin.HoverForm,
  DragLint.Plugin.CompletionForm,
  DragLint.Plugin.SignatureForm,
  DragLint.Plugin.RefactorForm,
  DragLint.Plugin.StructureForm,
  DragLint.Plugin.UsagesForm,
  DragLint.Plugin.SymbolSearchForm;

procedure RegisterDragLintMenu;
procedure UnregisterDragLintMenu;

{ Invoke* procedures are also called by the keyboard binding unit }
procedure InvokeHover(Sender: TObject);
procedure InvokeCompletion(Sender: TObject);
procedure InvokeSignatureHelp(Sender: TObject);
procedure InvokeDiagnostics(Sender: TObject);
procedure InvokeRename(Sender: TObject);
{ v0.26: compiler diagnostics }
procedure InvokeCompileDiagnose(Sender: TObject);
procedure InvokeImportLog(Sender: TObject);
{ v0.27: YADF format integration }
procedure InvokeFormatYadf(Sender: TObject);
{ v0.30: structure form }
procedure InvokeShowStructure(Sender: TObject);
{ v0.31: AST checks }
procedure InvokeRunAstChecks(Sender: TObject);
{ v0.33: find usages + symbol search }
procedure InvokeFindUsages(Sender: TObject);
procedure InvokeSymbolSearch(Sender: TObject);

implementation

uses
  System.Generics.Collections,
  Vcl.Forms,
  Winapi.Windows,
  DragLint.Plugin.Keyboard,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.EditViewNotifier,
  DragLint.Plugin.HoverTracker;

{ ---- TMenuActionWrapper ---- }
{ OnClick is TNotifyEvent (method pointer); plain procedures cannot be
  assigned to it directly.  This tiny helper bridges the gap. }

type
  TMenuProc = procedure(Sender: TObject);

  TMenuActionWrapper = class
  private
    FProc: TMenuProc;
  public
    constructor Create(AProc: TMenuProc);
    procedure HandleClick(Sender: TObject);
  end;

constructor TMenuActionWrapper.Create(AProc: TMenuProc);
begin
  inherited Create;
  FProc := AProc;
end;

procedure TMenuActionWrapper.HandleClick(Sender: TObject);
begin
  if Assigned(FProc) then
    FProc(Sender);
end;

{ ---- notification handler ---- }

type
  TDiagEntry = record
    FileName: string;
    Msg: string;
    Rule: string;
    Line: Integer;
    Col: Integer;
  end;

procedure HandleNotification(const AMethod: string; AParams: TJSONValue);
var
  Diags: TJSONArray;
  UriStr: string;
  FileName: string;
  i: Integer;
  DiagObj: TJSONObject;
  RangeObj, StartObj: TJSONObject;
  Entries: TArray<TDiagEntry>;
  E: TDiagEntry;
begin
  if AMethod <> 'textDocument/publishDiagnostics' then Exit;
  if not (AParams is TJSONObject) then Exit;

  if not (AParams as TJSONObject).TryGetValue<string>('uri', UriStr) then Exit;
  if not (AParams as TJSONObject).TryGetValue<TJSONArray>('diagnostics', Diags) then Exit;

  { Convert file URI to local Windows path }
  FileName := UriStr;
  if (Length(FileName) > 8) and
     (LowerCase(Copy(FileName, 1, 8)) = 'file:///') then
    FileName := StringReplace(Copy(FileName, 9, MaxInt), '/', '\',
      [rfReplaceAll]);

  { v0.29: update the visual diagnostic cache (runs on the LSP reader thread;
    Cache.Update is thread-safe). }
  Cache.Update(FileName, AParams);

  { Collect diagnostic entries before queuing (Diags is owned by AMsg which
    will be freed after this call returns) }
  SetLength(Entries, Diags.Count);
  for i := 0 to Diags.Count - 1 do
  begin
    E.FileName := FileName;
    E.Msg      := '';
    E.Rule     := 'drag-lint';
    E.Line     := 1;
    E.Col      := 1;

    if not (Diags.Items[i] is TJSONObject) then
    begin
      Entries[i] := E;
      Continue;
    end;
    DiagObj := Diags.Items[i] as TJSONObject;

    DiagObj.TryGetValue<string>('message', E.Msg);
    DiagObj.TryGetValue<string>('code',    E.Rule);

    if DiagObj.TryGetValue<TJSONObject>('range', RangeObj) then
      if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
      begin
        { LSP 0-based -> IOTAMessageServices 1-based }
        StartObj.TryGetValue<Integer>('line',      E.Line);
        StartObj.TryGetValue<Integer>('character', E.Col);
        Inc(E.Line);
        Inc(E.Col);
      end;

    Entries[i] := E;
  end;

  { Post everything to the main thread for the IDE message pane }
  TThread.Queue(nil,
    procedure
    var
      MS: IOTAMessageServices;
      j: Integer;
    begin
      if not Supports(BorlandIDEServices, IOTAMessageServices, MS) then Exit;

      if Length(Entries) = 0 then
      begin
        MS.AddTitleMessage(
          Format('drag-lint: no diagnostics for %s', [FileName]));
        Exit;
      end;

      MS.AddTitleMessage(
        Format('drag-lint: %d diagnostic(s) for %s',
          [Length(Entries), FileName]));

      for j := 0 to High(Entries) do
        MS.AddToolMessage(
          Entries[j].FileName,
          Entries[j].Msg,
          Entries[j].Rule,
          Entries[j].Line,
          Entries[j].Col);
    end);
end;

{ ---- shared LSP client ---- }

var
  GLspClient:   TDragLintLspClient = nil;
  GMenuItems:   TObjectList<TMenuItem> = nil;
  GWrappers:    TObjectList<TMenuActionWrapper> = nil;

function EnsureLspClient: TDragLintLspClient;
var
  ExePath: string;
begin
  if GLspClient = nil then
  begin
    GLspClient := TDragLintLspClient.Create;
    GLspClient.OnNotification := HandleNotification;

    { Look for drag-lint.exe next to the BPL first, then fall back to PATH }
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(ExePath) then
      ExePath := 'drag-lint.exe';

    if not GLspClient.Start(ExePath) then
    begin
      ShowMessage(
        'drag-lint: LSP server failed to start.'#13#10 +
        'Ensure drag-lint.exe is on PATH or next to the BPL.');
      FreeAndNil(GLspClient);
      Exit(nil);
    end;

    if not GLspClient.Initialize then
    begin
      ShowMessage('drag-lint: LSP initialize handshake failed.');
      GLspClient.Stop;
      FreeAndNil(GLspClient);
      Exit(nil);
    end;
  end;
  Result := GLspClient;
end;

{ ---- OTAPI helpers ---- }

function GetActiveEditorInfo(out AUri: string;
  out ALine, ACol: Integer): Boolean;
var
  ESS: IOTAEditorServices;
  EditView: IOTAEditView;
  FileName: string;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView := ESS.TopView;
  if EditView = nil then Exit;

  FileName := EditView.Buffer.FileName;
  if FileName = '' then Exit;

  { Convert Windows path to LSP file URI }
  AUri := 'file:///' +
    StringReplace(FileName, '\', '/', [rfReplaceAll]);

  { IOTAEditView.Position is 1-based; LSP is 0-based }
  ALine := EditView.Position.Row    - 1;
  ACol  := EditView.Position.Column - 1;
  if ALine < 0 then ALine := 0;
  if ACol  < 0 then ACol  := 0;

  Result := True;
end;

function MakeTextDocumentPositionParams(const AUri: string;
  ALine, ACol: Integer): TJSONObject;
var
  TextDoc, Pos: TJSONObject;
begin
  Result  := TJSONObject.Create;
  TextDoc := TJSONObject.Create;
  TextDoc.AddPair('uri', AUri);
  Result.AddPair('textDocument', TextDoc);
  Pos := TJSONObject.Create;
  Pos.AddPair('line',      TJSONNumber.Create(ALine));
  Pos.AddPair('character', TJSONNumber.Create(ACol));
  Result.AddPair('position', Pos);
end;

{ ---- menu action procedures ---- }

procedure InvokeHover(Sender: TObject);
var
  Client:      TDragLintLspClient;
  Uri:         string;
  Line, Col:   Integer;
  Params:      TJSONObject;
  Resp:        TJSONValue;
  HoverText:   string;
  ContentsVal: TJSONValue;
  P:           TPoint;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/hover', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint hover: request timed out or no result.');
    Exit;
  end;

  try
    // Extract text from LSP hover response.
    // Supported shapes:
    //   contents: object with "value" field (MarkupContent)
    //   contents: plain string
    // Falls back to formatted JSON if extraction fails.
    HoverText := '';
    if (Resp is TJSONObject) and
       (Resp as TJSONObject).TryGetValue<TJSONValue>('contents', ContentsVal) then
    begin
      if ContentsVal is TJSONObject then
        (ContentsVal as TJSONObject).TryGetValue<string>('value', HoverText)
      else if ContentsVal is TJSONString then
        HoverText := (ContentsVal as TJSONString).Value;
    end;

    if HoverText = '' then
      HoverText := Resp.Format(2);

    GetCursorPos(P);
    ShowDragLintHover(HoverText, P.X, P.Y + 20);
  finally
    Resp.Free;
  end;
end;

procedure InvokeCompletion(Sender: TObject);
var
  Client:   TDragLintLspClient;
  Uri:      string;
  Line, Col: Integer;
  Params:   TJSONObject;
  Resp:     TJSONValue;
  RespObj:  TJSONObject;
  Items:    TJSONArray;
  ResultV:  TJSONValue;
  P:        TPoint;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/completion', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint completion: request timed out or no result.');
    Exit;
  end;
  try
    Items := nil;

    // Shape 1: top-level array
    // Shape 2: { items:[...] } or { result:{ items:[...] } }
    if Resp is TJSONArray then
      Items := Resp as TJSONArray
    else if Resp is TJSONObject then
    begin
      RespObj := Resp as TJSONObject;
      if not RespObj.TryGetValue<TJSONArray>('items', Items) then
      begin
        if RespObj.TryGetValue<TJSONValue>('result', ResultV) then
        begin
          if ResultV is TJSONArray then
            Items := ResultV as TJSONArray
          else if ResultV is TJSONObject then
            (ResultV as TJSONObject).TryGetValue<TJSONArray>('items', Items);
        end;
      end;
    end;

    if Items = nil then
    begin
      ShowMessage('drag-lint completion:'#13#10 + Resp.Format(2));
      Exit;
    end;

    GetCursorPos(P);
    ShowDragLintCompletion(
      Items,
      P.X, P.Y + 20,
      procedure(const ATxt: string)
      var
        ESS: IOTAEditorServices;
        EV:  IOTAEditView;
        EW:  IOTAEditWriter;
      begin
        if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
        EV := ESS.TopView;
        if EV = nil then Exit;
        EW := EV.Buffer.CreateUndoableWriter;
        EW.Insert(PAnsiChar(AnsiString(ATxt)));
      end);
  finally
    Resp.Free;
  end;
end;

procedure InvokeSignatureHelp(Sender: TObject);
var
  Client:      TDragLintLspClient;
  Uri:         string;
  Line, Col:   Integer;
  Params:      TJSONObject;
  Resp:        TJSONValue;
  RespObj:     TJSONObject;
  SigsArr:     TJSONArray;
  ActiveSig:   Integer;
  ActiveParam: Integer;
  SigObj:      TJSONObject;
  SigLabel:    string;
  P:           TPoint;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/signatureHelp', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint signatureHelp: request timed out or no result.');
    Exit;
  end;
  try
    SigLabel    := '';
    ActiveParam := 0;

    if Resp is TJSONObject then
    begin
      RespObj    := Resp as TJSONObject;
      ActiveSig  := 0;
      RespObj.TryGetValue<Integer>('activeSignature', ActiveSig);
      RespObj.TryGetValue<Integer>('activeParameter',  ActiveParam);

      if RespObj.TryGetValue<TJSONArray>('signatures', SigsArr) and
         (SigsArr.Count > 0) then
      begin
        if ActiveSig >= SigsArr.Count then
          ActiveSig := 0;
        if SigsArr.Items[ActiveSig] is TJSONObject then
        begin
          SigObj := SigsArr.Items[ActiveSig] as TJSONObject;
          SigObj.TryGetValue<string>('label', SigLabel);
          { Per-signature activeParameter overrides the top-level one }
          SigObj.TryGetValue<Integer>('activeParameter', ActiveParam);
        end;
      end;
    end;

    if SigLabel = '' then
    begin
      ShowMessage('drag-lint signatureHelp:'#13#10 + Resp.Format(2));
      Exit;
    end;

    GetCursorPos(P);
    ShowDragLintSignature(SigLabel, ActiveParam, P.X, P.Y + 20);
  finally
    Resp.Free;
  end;
end;

procedure InvokeDiagnostics(Sender: TObject);
var
  Client: TDragLintLspClient;
  Uri: string;
  Line, Col: Integer;
  Params: TJSONObject;
  TextDoc: TJSONObject;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  { textDocument/didSave triggers publishDiagnostics notification }
  Params  := TJSONObject.Create;
  TextDoc := TJSONObject.Create;
  TextDoc.AddPair('uri', Uri);
  Params.AddPair('textDocument', TextDoc);
  try
    Client.Notify('textDocument/didSave', Params);
  finally
    Params.Free;
  end;

  ShowMessage(
    'drag-lint: diagnostics requested for'#13#10 + Uri + #13#10 +
    'Results will appear in the Messages pane.');
end;

{ ---- v0.26: synchronous process helper ---- }

// Spawns ACmdLine via CreateProcessW with merged stdout+stderr capture.
// Returns the process exit code (-1 on spawn failure).
// AOutput receives the full text output. ATimeoutMs = 0 means INFINITE.
function RunAndCaptureStdout(const ACmdLine: string;
  out AOutput: string; ATimeoutMs: Integer = 60000): Integer;
var
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  Buf: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  ExitCode: DWORD;
  WideCmd: string;
  SB: TStringBuilder;
  TimeoutValue: DWORD;
begin
  Result := -1;
  AOutput := '';
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then
    Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb        := SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
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
        if BytesRead = 0 then
          Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then
      TimeoutValue := INFINITE
    else
      TimeoutValue := DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TimeoutValue);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---- helpers to resolve project db path and active project file ---- }

// Returns the active project file path (.dproj), or '' if not available.
function GetActiveProjectFile: string;
var
  MS: IOTAModuleServices;
  ProjGroup: IOTAProjectGroup;
  ActiveProj: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  if MS = nil then Exit;
  ProjGroup := MS.MainProjectGroup;
  if ProjGroup = nil then Exit;
  ActiveProj := ProjGroup.ActiveProject;
  if ActiveProj = nil then Exit;
  Result := ActiveProj.FileName;
end;

// Returns the database path for the active project: same dir as .dproj with
// name <ProjectName>.sqlite.  Falls back to '' when no project is open.
function GetActiveProjectDb: string;
var
  ProjFile: string;
begin
  ProjFile := GetActiveProjectFile;
  if ProjFile = '' then
    Result := ''
  else
    Result := ChangeFileExt(ProjFile, '.sqlite');
end;

procedure InvokeRename(Sender: TObject);
var
  Uri:             string;
  Line, Col:       Integer;
  ProjDb, ExePath: string;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;

  { Resolve project DB and exe path }
  ProjDb  := GetActiveProjectDb;
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  { Open the refactor preview form.
    For v0.27 simplicity the qname field starts empty; the user fills it in.
    Future v0.28+ can extract the identifier at cursor via TTypeAtResolver. }
  ShowRefactorDialog('', ProjDb, ExePath);
end;

procedure InvokeFormatYadf(Sender: TObject);
var
  ESS:      IOTAEditorServices;
  EditView: IOTAEditView;
  FilePath: string;
  ExePath:  string;
  CmdLine:  string;
  Output:   string;
  ExitCode: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    ShowMessage('drag-lint: no editor services available');
    Exit;
  end;
  EditView := ESS.TopView;
  if EditView = nil then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;
  FilePath := EditView.Buffer.FileName;
  if FilePath = '' then
  begin
    ShowMessage('drag-lint: active buffer has no file name');
    Exit;
  end;

  { Resolve drag-lint.exe }
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  { For v0.27: do not auto-save; spawn YADF against the current on-disk file.
    The user should save the file before invoking this command. }
  CmdLine  := Format('"%s" format "%s"', [ExePath, FilePath]);
  ExitCode := RunAndCaptureStdout(CmdLine, Output, 60000);

  if ExitCode = 2 then
  begin
    ShowMessage(
      'drag-lint: failed to spawn format command.'#13#10 +
      'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  { The IDE will auto-detect the file change on next focus switch. }
  ShowMessage(
    Format('drag-lint Format with YADF:'#13#10 + '%s',
      [Trim(Output)]));
end;

// Broadcasts textDocument/didSave for every .pas file mentioned in AOutput
// (lines of the form  "path.pas(N,...)" — same format as dcc64/msbuild output).
// This makes the LSP server re-publish diagnostics for the affected files.
procedure BroadcastDidSaveForAffectedFiles(const AOutput: string);
var
  Client: TDragLintLspClient;
  Lines: TStringList;
  Line, FilePath, Uri: string;
  P: Integer;
  Params, TextDoc: TJSONObject;
begin
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for Line in Lines do
    begin
      // Lines look like:  C:\path\File.pas(N) Warning: ...
      P := Pos('.pas(', LowerCase(Line));
      if P <= 0 then
        P := Pos('.dpr(', LowerCase(Line));
      if P <= 0 then Continue;
      FilePath := Copy(Line, 1, P + 3); // up to and including '.pas' or '.dpr'
      if not FileExists(FilePath) then Continue;
      Uri := 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
      Params  := TJSONObject.Create;
      TextDoc := TJSONObject.Create;
      TextDoc.AddPair('uri', Uri);
      Params.AddPair('textDocument', TextDoc);
      try
        Client.Notify('textDocument/didSave', Params);
      finally
        Params.Free;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- v0.26 menu actions ---- }

procedure InvokeCompileDiagnose(Sender: TObject);
var
  ProjFile, DbPath, ExePath: string;
  CmdLine, Output: string;
  ExitCode: Integer;
  ErrCount, WarnCount, HintCount: Integer;
  Lines: TStringList;
  Line: string;
  LLine: string;
begin
  ProjFile := GetActiveProjectFile;
  if ProjFile = '' then
  begin
    ShowMessage('drag-lint Compile & Diagnose: no active project found.');
    Exit;
  end;

  DbPath := GetActiveProjectDb;

  ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  // Build the CLI command line.
  if DbPath <> '' then
    CmdLine := Format('"%s" compile-check "%s" --db "%s" --format text',
      [ExePath, ProjFile, DbPath])
  else
    CmdLine := Format('"%s" compile-check "%s" --format text',
      [ExePath, ProjFile]);

  // Run synchronously (msbuild can take up to several minutes; use 10 min).
  ExitCode := RunAndCaptureStdout(CmdLine, Output, 600000);

  if ExitCode = 2 then
  begin
    ShowMessage('drag-lint: failed to spawn compile-check.'#13#10 +
      'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  // Count by severity from the CLI text output lines.
  ErrCount  := 0;
  WarnCount := 0;
  HintCount := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
    begin
      LLine := LowerCase(Line);
      if (Pos(') error:', LLine) > 0) or (Pos(') fatal:', LLine) > 0) then
        Inc(ErrCount)
      else if Pos(') warning:', LLine) > 0 then
        Inc(WarnCount)
      else if (Pos(') hint:', LLine) > 0) or
              (Pos(') information:', LLine) > 0) then
        Inc(HintCount);
    end;
  finally
    Lines.Free;
  end;

  // If findings were stored in the DB, trigger LSP publishDiagnostics.
  if DbPath <> '' then
    BroadcastDidSaveForAffectedFiles(Output);

  ShowMessage(Format(
    'drag-lint Compile & Diagnose complete.'#13#10 +
    '%d error(s), %d warning(s), %d hint(s) found.'#13#10 +
    'Check the Messages pane for details.',
    [ErrCount, WarnCount, HintCount]));
end;

procedure InvokeImportLog(Sender: TObject);
var
  Dlg: TOpenDialog;
  LogFile, DbPath, ExePath: string;
  CmdLine, Output: string;
  ExitCode: Integer;
  ErrCount, WarnCount, HintCount: Integer;
  Lines: TStringList;
  Line, LLine: string;
begin
  DbPath := GetActiveProjectDb;

  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title  := 'drag-lint: Import Build Log';
    Dlg.Filter := 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*';
    Dlg.Options := [ofFileMustExist, ofPathMustExist];
    if not Dlg.Execute then Exit;
    LogFile := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  if DbPath <> '' then
    CmdLine := Format('"%s" import-log "%s" --db "%s"',
      [ExePath, LogFile, DbPath])
  else
    CmdLine := Format('"%s" import-log "%s"',
      [ExePath, LogFile]);

  ExitCode := RunAndCaptureStdout(CmdLine, Output, 60000);

  if ExitCode = 2 then
  begin
    ShowMessage('drag-lint: failed to spawn import-log.'#13#10 +
      'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  // Count imported findings from output.
  ErrCount  := 0;
  WarnCount := 0;
  HintCount := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
    begin
      LLine := LowerCase(Line);
      if (Pos(') error:', LLine) > 0) or (Pos(') fatal:', LLine) > 0) then
        Inc(ErrCount)
      else if Pos(') warning:', LLine) > 0 then
        Inc(WarnCount)
      else if (Pos(') hint:', LLine) > 0) or
              (Pos(') information:', LLine) > 0) then
        Inc(HintCount);
    end;
  finally
    Lines.Free;
  end;

  // Trigger LSP refresh for affected files.
  if DbPath <> '' then
    BroadcastDidSaveForAffectedFiles(Output);

  ShowMessage(Format(
    'drag-lint Import Build Log complete.'#13#10 +
    'Imported: %d error(s), %d warning(s), %d hint(s).'#13#10 +
    'Check the Messages pane for details.',
    [ErrCount, WarnCount, HintCount]));
end;

procedure InvokeSettings(Sender: TObject);
begin
  ShowSettingsDialog;
end;

{ v0.30: show structure form }
procedure InvokeShowStructure(Sender: TObject);
begin
  ShowDragLintStructure;
end;

{ v0.31: Run AST Checks on the active file (no compiler required) }
procedure InvokeRunAstChecks(Sender: TObject);
var
  ESS:     IOTAEditorServices;
  EditView: IOTAEditView;
  FilePath: string;
  ExePath, DbPath: string;
  CmdLine, Output: string;
  ExitCode: Integer;
  Client: TDragLintLspClient;
  Params, TextDoc: TJSONObject;
  Uri: string;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    ShowMessage('drag-lint: no editor services available');
    Exit;
  end;
  EditView := ESS.TopView;
  if EditView = nil then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;
  FilePath := EditView.Buffer.FileName;
  if FilePath = '' then
  begin
    ShowMessage('drag-lint: active buffer has no file name');
    Exit;
  end;

  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  DbPath := GetActiveProjectDb;

  if DbPath <> '' then
    CmdLine := Format('"%s" check-ast "%s" --db "%s"',
      [ExePath, FilePath, DbPath])
  else
    CmdLine := Format('"%s" check-ast "%s"', [ExePath, FilePath]);

  ExitCode := RunAndCaptureStdout(CmdLine, Output, 30000);

  if ExitCode = 2 then
  begin
    ShowMessage('drag-lint: failed to spawn check-ast.'#13#10 +
      'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  Uri := 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
  Client := EnsureLspClient;
  if Client <> nil then
  begin
    Params  := TJSONObject.Create;
    TextDoc := TJSONObject.Create;
    TextDoc.AddPair('uri', Uri);
    Params.AddPair('textDocument', TextDoc);
    try
      Client.Notify('textDocument/didSave', Params);
    finally
      Params.Free;
    end;
  end;

  ShowMessage(Format('drag-lint AST Checks:'#13#10'%s', [Trim(Output)]));
end;

{ v0.33: Find Usages }
procedure InvokeFindUsages(Sender: TObject);
var
  ExePath, ProjDb: string;
  SymName: string;
begin
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  ProjDb := GetActiveProjectDb;

  SymName := InputBox('drag-lint Find Usages', 'Symbol name:', '');
  if Trim(SymName) = '' then Exit;

  ShowFindUsages(SymName, ExePath, ProjDb);
end;

{ v0.33: Symbol Search }
procedure InvokeSymbolSearch(Sender: TObject);
var
  ExePath, ProjDb: string;
  Selected:        string;
  ColonPos:        Integer;
  FilePath:        string;
  LineNum:         Integer;
  ESS:             IOTAEditorServices;
  AS_:             IOTAActionServices;
  EV:              IOTAEditView;
  Pos:             IOTAEditPosition;
begin
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  ProjDb   := GetActiveProjectDb;
  Selected := ShowSymbolSearch(ExePath, ProjDb);
  if Selected = '' then Exit;

  { Parse "file:line" from the returned location }
  ColonPos := 0;
  var k: Integer;
  for k := Length(Selected) downto 1 do
    if Selected[k] = ':' then
    begin
      ColonPos := k;
      Break;
    end;

  if ColonPos > 0 then
  begin
    FilePath := Copy(Selected, 1, ColonPos - 1);
    LineNum  := StrToIntDef(Copy(Selected, ColonPos + 1, MaxInt), 0);
  end
  else
  begin
    FilePath := Selected;
    LineNum  := 0;
  end;

  if FilePath = '' then Exit;

  if Supports(BorlandIDEServices, IOTAActionServices, AS_) then
    AS_.OpenFile(FilePath);

  if (LineNum > 0) and
     Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV := ESS.TopView;
    if EV <> nil then
    begin
      Pos := EV.Position;
      if Pos <> nil then
      begin
        Pos.GotoLine(LineNum);
        EV.Paint;
      end;
    end;
  end;
end;

{ ---- menu registration ---- }

function AddWrappedItem(AParent: TMenuItem; const ACaption: string;
  AProc: TMenuProc): TMenuItem;
var
  W: TMenuActionWrapper;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := ACaption;
  W := TMenuActionWrapper.Create(AProc);
  GWrappers.Add(W);
  Result.OnClick := W.HandleClick;
  AParent.Add(Result);
end;

procedure RegisterDragLintMenu;
var
  Services: INTAServices;
  RootMenu: TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) then Exit;

  GMenuItems := TObjectList<TMenuItem>.Create(True);
  GWrappers  := TObjectList<TMenuActionWrapper>.Create(True);

  RootMenu := TMenuItem.Create(nil);
  RootMenu.Caption := 'drag-lint';
  Services.AddActionMenu('ToolsMenu', nil, RootMenu, True, True);
  GMenuItems.Add(RootMenu);

  AddWrappedItem(RootMenu, 'Hover at Cursor',           InvokeHover);
  AddWrappedItem(RootMenu, 'Show Completion',            InvokeCompletion);
  AddWrappedItem(RootMenu, 'Show Signature Help',        InvokeSignatureHelp);
  AddWrappedItem(RootMenu, 'Run Diagnostics (didSave)',  InvokeDiagnostics);
  AddWrappedItem(RootMenu, 'Rename Symbol...',           InvokeRename);
  // v0.26: compiler diagnostics entries
  AddWrappedItem(RootMenu, 'Compile && Diagnose',        InvokeCompileDiagnose);
  AddWrappedItem(RootMenu, 'Import Build Log...',        InvokeImportLog);
  // v0.27: YADF format integration
  AddWrappedItem(RootMenu, 'Format with YADF',           InvokeFormatYadf);
  // v0.30: structure form + settings
  AddWrappedItem(RootMenu, 'Show Structure',             InvokeShowStructure);
  // v0.31: AST diagnostics (no compiler required)
  AddWrappedItem(RootMenu, 'Run AST Checks',             InvokeRunAstChecks);
  // v0.33: find usages + symbol search
  AddWrappedItem(RootMenu, 'Find Usages...',             InvokeFindUsages);
  AddWrappedItem(RootMenu, 'Symbol Search...',           InvokeSymbolSearch);
  AddWrappedItem(RootMenu, 'Settings...',                InvokeSettings);

  RegisterProjectNotifier;
  RegisterDragLintKeystrokes;
  RegisterDragLintEditViewNotifier;
  StartHoverTracker;
end;

procedure UnregisterDragLintMenu;
begin
  StopHoverTracker;
  UnregisterDragLintEditViewNotifier;
  UnregisterDragLintKeystrokes;
  UnregisterProjectNotifier;

  { Close the structure form and usages form if still open }
  HideDragLintStructure;
  HideFindUsages;

  { Stop LSP client first }
  if GLspClient <> nil then
  begin
    GLspClient.Stop;
    FreeAndNil(GLspClient);
  end;
  { Wrappers hold the OnClick method pointers; free them before the menu items }
  FreeAndNil(GWrappers);
  FreeAndNil(GMenuItems);
end;

initialization

finalization
  UnregisterDragLintMenu;

end.
