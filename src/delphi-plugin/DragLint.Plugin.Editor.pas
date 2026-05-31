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

const
  (* v0.40.1: hardcoded version; build stamp resolved at runtime from the
     loaded BPL's file modtime (see PluginBuildTag). Compiler intrinsics
     like the dollar-I DATE/TIME macros emit unquoted strings in Delphi 13
     and don't fit in a const expression. *)
  PLUGIN_VERSION = 'v0.40.5-alpha';

{ Stamp every user-visible plugin dialog with the version + the actual
  build time of the BPL the IDE has loaded so the user can verify at a
  glance that they are testing the latest build. }
function PluginBuildTag: string;

{ v0.40.3: exposed so HoverTracker can reuse the shared LSP client for
  dwell-triggered textDocument/hover queries. Returns nil if startup or
  initialize failed. Called only from main thread. }
function EnsureLspClient: TDragLintLspClient;

{ v0.40.3: dwell-fire helper used by HoverTracker. Queries LSP hover at
  the given URI/line/col and returns the extracted hover text, or '' on
  timeout / no-result / any failure. Safe to call from main thread only.
  ATimeoutMs is the per-query budget; default 500ms keeps the UI snappy. }
function QueryHoverText(const AUri: string; ALine, ACol: Integer;
  ATimeoutMs: Integer = 500): string;

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
{ v0.39: diagnostic menu — shows path resolution, subprocess spawn, LSP handshake details }
procedure InvokeTestConnection(Sender: TObject);
procedure InvokeOpenLog(Sender: TObject);

{ v0.40.3: lint the active editor BUFFER (unsaved changes included).
  Snapshots the in-memory text to %TEMP%\drag-lint-buffer-<n>.pas and
  runs drag-lint lint <tempfile> --json. Findings are merged into the
  diagnostic cache so inline markers update without saving the file. }
procedure InvokeLintBuffer(Sender: TObject);

implementation

uses
  System.Generics.Collections, System.IOUtils,
  Vcl.Forms, Vcl.Clipbrd,
  Winapi.Windows,
  Winapi.ShellAPI,
  DragLint.Plugin.Keyboard,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.EditViewNotifier,
  DragLint.Plugin.HoverTracker,
  DragLint.Plugin.DbResolver;

{ ---- PluginBuildTag ---- }

function PluginBuildTag: string;
var
  ModName: string;
  Age: TDateTime;
begin
  ModName := GetModuleName(HInstance);
  if (ModName <> '') and FileAge(ModName, Age) then
    Result := 'drag-lint plugin ' + PLUGIN_VERSION +
              ' (BPL built ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Age) + ')'
  else
    Result := 'drag-lint plugin ' + PLUGIN_VERSION +
              ' (BPL build time unknown)';
end;

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
  BplDir: string;
  LogPath: string;
begin
  if GLspClient = nil then
  begin
    GLspClient := TDragLintLspClient.Create;
    GLspClient.OnNotification := HandleNotification;

    BplDir := ExtractFilePath(GetModuleName(HInstance));
    DebugLog('EnsureLspClient: BPL dir = ' + BplDir);
    DebugLog('EnsureLspClient: BPL fullpath = ' + GetModuleName(HInstance));

    { Look for drag-lint.exe next to the BPL first, then fall back to PATH }
    ExePath := BplDir + 'drag-lint.exe';
    DebugLog('EnsureLspClient: candidate = ' + ExePath +
      ' (exists=' + BoolToStr(FileExists(ExePath), True) + ')');
    if not FileExists(ExePath) then
    begin
      ExePath := 'drag-lint.exe';
      DebugLog('EnsureLspClient: falling back to PATH lookup of drag-lint.exe');
    end;

    LogPath := GetPluginLogPath;

    { v0.40.3: resolve all index DBs for the currently-active editor file
      and pass them as --db flags. Plugin Settings + auto-discovery + the
      exe-relative library DB are all merged inside ResolveActiveIndexDbs. }
    var DbList: TArray<string>;
    try
      DbList := ResolveActiveIndexDbs(LoadSettings);
    except
      SetLength(DbList, 0);
    end;

    if not GLspClient.Start(ExePath, DbList) then
    begin
      ShowMessage(
        PluginBuildTag + #13#10#13#10 +
        'drag-lint: LSP server failed to start.'#13#10 +
        'Ensure drag-lint.exe is on PATH or next to the BPL.'#13#10#13#10 +
        'BPL dir:        ' + BplDir + #13#10 +
        'Resolved exe:   ' + ExePath + #13#10 +
        Format('DBs:            %d resolved', [Length(DbList)]) + #13#10 +
        'Debug log:      ' + LogPath);
      FreeAndNil(GLspClient);
      Exit(nil);
    end;

    if not GLspClient.Initialize then
    begin
      ShowMessage(
        PluginBuildTag + #13#10#13#10 +
        'drag-lint: LSP initialize handshake failed.'#13#10#13#10 +
        'BPL dir:        ' + BplDir + #13#10 +
        'Resolved exe:   ' + ExePath + #13#10 +
        'Debug log:      ' + LogPath);
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

function QueryHoverText(const AUri: string; ALine, ACol: Integer;
  ATimeoutMs: Integer): string;
(* v0.40.3: shared hover-text extraction used by both InvokeHover (manual
   Ctrl+Alt+H invocation) and the HoverTracker dwell trigger. Returns
   empty string on any failure — caller decides whether to show a popup
   or fall back to diagnostic-only.

   v0.40.5: TDragLintLspClient.Request returns the FULL JSON-RPC envelope
   (jsonrpc, id, result, error), not just the inner result. Earlier
   versions of this function looked for 'contents' at the top level and
   always missed -- the markdown body was inside .result.contents.value. *)
var
  Client:      TDragLintLspClient;
  Params:      TJSONObject;
  Resp:        TJSONValue;
  ResultVal:   TJSONValue;
  ContentsVal: TJSONValue;
begin
  Result := '';
  try
    Client := EnsureLspClient;
    if Client = nil then Exit;
    Params := MakeTextDocumentPositionParams(AUri, ALine, ACol);
    try
      Resp := Client.Request('textDocument/hover', Params, ATimeoutMs);
    finally
      Params.Free;
    end;
    if Resp = nil then Exit;
    try
      if not (Resp is TJSONObject) then Exit;
      if not (Resp as TJSONObject).TryGetValue<TJSONValue>('result', ResultVal) then Exit;
      if ResultVal is TJSONNull then Exit;
      if not (ResultVal is TJSONObject) then Exit;
      if not (ResultVal as TJSONObject).TryGetValue<TJSONValue>('contents', ContentsVal) then Exit;
      if ContentsVal is TJSONObject then
        (ContentsVal as TJSONObject).TryGetValue<string>('value', Result)
      else if ContentsVal is TJSONString then
        Result := (ContentsVal as TJSONString).Value;
    finally
      Resp.Free;
    end;
  except
    { Silent — fires from dwell timer; AVs here would break IDE }
    Result := '';
  end;
end;

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
    { v0.40.5: walk the FULL JSON-RPC envelope: .result.contents.value
      Earlier code stopped at .contents and always missed, so the
      Resp.Format(2) raw-JSON fallback was always what users saw.
      Now: extract markdown body or string; only fall back when extraction
      genuinely fails (server returned an error, etc.). }
    HoverText := '';
    var ResultVal: TJSONValue;
    if (Resp is TJSONObject) and
       (Resp as TJSONObject).TryGetValue<TJSONValue>('result', ResultVal) and
       (ResultVal is TJSONObject) and
       (ResultVal as TJSONObject).TryGetValue<TJSONValue>('contents', ContentsVal) then
    begin
      if ContentsVal is TJSONObject then
        (ContentsVal as TJSONObject).TryGetValue<string>('value', HoverText)
      else if ContentsVal is TJSONString then
        HoverText := (ContentsVal as TJSONString).Value;
    end;

    if HoverText = '' then
      HoverText := '(no hover info: ' + Resp.Format(2) + ')';

    { v0.40.5: dump every hover invocation to the debug log + copy the
      rendered text to the clipboard so users can paste it back when the
      popup is too transient to screenshot. Logging happens BEFORE the
      popup shows; clipboard is set unconditionally so even a Hover that
      immediately closes leaves the text behind. }
    DebugLog('InvokeHover: raw response (' + IntToStr(Length(Resp.ToString)) +
      ' chars): ' + Resp.ToString);
    DebugLog('InvokeHover: extracted HoverText (' +
      IntToStr(Length(HoverText)) + ' chars):' + sLineBreak + HoverText);
    try
      Vcl.Clipbrd.Clipboard.AsText := HoverText;
      DebugLog('InvokeHover: clipboard updated');
    except
      on E: Exception do
        DebugLog('InvokeHover: clipboard FAILED: ' + E.Message);
    end;

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
function IdentifierAtCursor: string;
{ v0.40.3: read the active editor's caret line and return the identifier
  spanning the cursor column. Identifier = run of [A-Za-z0-9_] containing
  the cursor position. Empty string if no identifier under cursor. }
var
  ESS:  IOTAEditorServices;
  EV:   IOTAEditView;
  Reader: IOTAEditReader;
  CaretRow, CaretCol: Integer;
  LineStartPos: Integer;
  Buf:  array[0..1023] of AnsiChar;
  Read: Integer;
  LineText: string;
  Lo, Hi:   Integer;

  function IsIdentChar(C: Char): Boolean;
  begin
    Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;

begin
  Result := '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EV := ESS.TopView;
    if (EV = nil) or (EV.Buffer = nil) then Exit;
    Reader := EV.Buffer.CreateReader;
    if Reader = nil then Exit;
    CaretRow := EV.Position.Row;
    CaretCol := EV.Position.Column;
    if (CaretRow <= 0) or (CaretCol <= 0) then Exit;

    { Buffer is character-addressed; we don't have a direct line offset,
      so walk the file scanning for newlines until we hit (CaretRow - 1).
      Lines are typically <1KB so this is cheap even for long files. }
    LineStartPos := 0;
    var CurRow := 1;
    var Pos := 0;
    while CurRow < CaretRow do
    begin
      Read := Reader.GetText(Pos, Buf, SizeOf(Buf));
      if Read <= 0 then Exit;
      for var I := 0 to Read - 1 do
      begin
        if Buf[I] = #10 then
        begin
          Inc(CurRow);
          if CurRow = CaretRow then
          begin
            LineStartPos := Pos + I + 1;
            Break;
          end;
        end;
      end;
      if CurRow >= CaretRow then Break;
      Inc(Pos, Read);
    end;

    Read := Reader.GetText(LineStartPos, Buf, SizeOf(Buf));
    if Read <= 0 then Exit;
    var EolIdx := 0;
    while (EolIdx < Read) and not (Buf[EolIdx] in [#10, #13]) do Inc(EolIdx);
    SetString(LineText, PAnsiChar(@Buf[0]), EolIdx);

    if CaretCol > Length(LineText) then Exit;
    if (CaretCol > 0) and (CaretCol <= Length(LineText)) and
       not IsIdentChar(LineText[CaretCol]) then
    begin
      { Try one column to the left — caret can sit just past an identifier. }
      if (CaretCol > 1) and IsIdentChar(LineText[CaretCol - 1]) then
        Dec(CaretCol)
      else
        Exit;
    end;
    if (CaretCol < 1) or (CaretCol > Length(LineText)) then Exit;
    if not IsIdentChar(LineText[CaretCol]) then Exit;

    Lo := CaretCol;
    while (Lo > 1) and IsIdentChar(LineText[Lo - 1]) do Dec(Lo);
    Hi := CaretCol;
    while (Hi < Length(LineText)) and IsIdentChar(LineText[Hi + 1]) do Inc(Hi);
    Result := Copy(LineText, Lo, Hi - Lo + 1);
  except
    Result := '';
  end;
end;

procedure InvokeFindUsages(Sender: TObject);
var
  ExePath: string;
  DbList:  TArray<string>;
  SymName: string;
  Settings: TDragLintSettings;
begin
  Settings := LoadSettings;
  ExePath := Settings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  { v0.40.3: resolve every relevant DB (project + sibling subprojects +
    explicit list + library) instead of the broken single-project lookup. }
  try
    DbList := ResolveActiveIndexDbs(Settings);
  except
    SetLength(DbList, 0);
  end;

  { v0.40.5: if the cursor is on an identifier, use it directly with no
    prompt -- one keystroke / one menu pick to run the query. Only fall
    back to the InputBox when there is nothing under the cursor (e.g. the
    menu was invoked from the Project Manager or some other non-editor
    focus where IdentifierAtCursor returns ''). The Shift modifier on
    the menu pick still forces the InputBox so users can override the
    auto-pick when they want to search for something else. }
  SymName := IdentifierAtCursor;
  if (SymName = '') or
     ((GetKeyState(VK_SHIFT) and $8000) <> 0) then
  begin
    SymName := InputBox(
      'drag-lint Find Usages',
      'Symbol name (Shift+menu forces this prompt; otherwise auto-picked from cursor):',
      SymName);
  end;
  if Trim(SymName) = '' then Exit;

  if Length(DbList) > 0 then
    ShowFindUsages(SymName, ExePath, DbList)
  else
    { No DBs resolved — fall back to legacy single-arg path so the form
      still surfaces a meaningful error. }
    ShowFindUsages(SymName, ExePath, '');
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

{ ---- v0.39 diagnostic helpers ---- }

procedure InvokeTestConnection(Sender: TObject);
{ v0.40.2: previously ran Start + Initialize + Stop on the UI thread.
  Initialize blocks up to 10s; Stop could hang forever on a sticky
  WaitFor; either freezes the IDE. Now we capture the up-front
  resolution synchronously, then spin a background TThread for the
  subprocess work and post the final ShowMessage back via TThread.Queue
  so the UI remains responsive. }
var
  BplPath, BplDir: string;
  ExePathBpl, ExePath: string;
  HasNextToBpl:       Boolean;
  Header:             string;
begin
  BplPath := GetModuleName(HInstance);
  BplDir  := ExtractFilePath(BplPath);
  ExePathBpl   := BplDir + 'drag-lint.exe';
  HasNextToBpl := FileExists(ExePathBpl);
  if HasNextToBpl then
    ExePath := ExePathBpl
  else
    ExePath := 'drag-lint.exe';

  Header :=
    '=== drag-lint plugin self-test ===' + sLineBreak +
    PluginBuildTag + sLineBreak + sLineBreak +
    'BPL path: ' + BplPath + sLineBreak +
    'BPL dir:  ' + BplDir + sLineBreak +
    Format('drag-lint.exe next to BPL: %s  (exists=%s)',
      [ExePathBpl, BoolToStr(HasNextToBpl, True)]) + sLineBreak;
  if not HasNextToBpl then
    Header := Header + 'Will fall back to PATH lookup of "drag-lint.exe"' +
              sLineBreak;
  Header := Header + sLineBreak + 'Spawning drag-lint.exe lsp ...' + sLineBreak;

  { Show "running" immediately so the user knows the click registered.
    The background thread then assembles and posts the full report. }
  TThread.CreateAnonymousThread(
    procedure
    var
      Client:          TDragLintLspClient;
      Started, InitOk: Boolean;
      Body:            string;
      FinalText:       string;
    begin
      Client := TDragLintLspClient.Create;
      try
        Started := Client.Start(ExePath);
        Body := Format('Start result: %s', [BoolToStr(Started, True)]) +
                sLineBreak;
        if Started then
        begin
          Body := Body + 'Sending initialize request ...' + sLineBreak;
          InitOk := Client.Initialize;
          Body := Body + Format('Initialize result: %s',
            [BoolToStr(InitOk, True)]) + sLineBreak;
          if InitOk then
            Body := Body + 'SUCCESS: subprocess + handshake working' +
                    sLineBreak
          else
            Body := Body + 'FAILED: initialize did not return within timeout' +
                    sLineBreak;
          Client.Stop;
        end
        else
          Body := Body + 'FAILED: CreateProcessW failed (see log)' + sLineBreak;
      finally
        Client.Free;
      end;

      FinalText := Header + Body + sLineBreak +
                   'Detailed log: ' + GetPluginLogPath;
      TThread.Queue(nil,
        procedure
        begin
          ShowMessage(FinalText);
        end);
    end).Start;
end;

{ ---- v0.40.3: lint unsaved buffer -------------------------------------- }

function ReadActiveBufferText(out AFileName: string): string;
{ Snapshot the in-memory text of the active editor view via IOTAEditReader.
  Returns '' if no active view or buffer. Output is UTF-8 friendly because
  the IDE buffer is already AnsiString in the source charset; we read raw
  bytes and let drag-lint's parser handle encoding the same way it does
  for on-disk files. }
var
  ESS:    IOTAEditorServices;
  EV:     IOTAEditView;
  Reader: IOTAEditReader;
  Buf:    TBytes;
  Pos, N: Integer;
  Tmp:    array[0..16383] of AnsiChar;
const
  CHUNK = SizeOf(Tmp);
begin
  Result    := '';
  AFileName := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV := ESS.TopView;
  if EV = nil then Exit;
  if EV.Buffer = nil then Exit;
  AFileName := EV.Buffer.FileName;
  Reader := EV.Buffer.CreateReader;
  if Reader = nil then Exit;

  SetLength(Buf, 0);
  Pos := 0;
  repeat
    N := Reader.GetText(Pos, Tmp, CHUNK);
    if N <= 0 then Break;
    SetLength(Buf, Length(Buf) + N);
    Move(Tmp[0], Buf[Length(Buf) - N], N);
    Inc(Pos, N);
  until N < CHUNK;

  if Length(Buf) > 0 then
    Result := TEncoding.ANSI.GetString(Buf);
end;

procedure InvokeLintBuffer(Sender: TObject);
var
  FilePath:  string;
  BufText:   string;
  Ext:       string;
  TmpPath:   string;
  Cfg:       TDragLintSettings;
  ExePath:   string;
  CmdLine:   string;
  TmpStream: TFileStream;
  Bytes:     TBytes;
  SI:        TStartupInfoW;
  PI:        TProcessInformation;
  CmdLineW:  array of WideChar;
begin
  BufText := ReadActiveBufferText(FilePath);
  if BufText = '' then
  begin
    ShowMessage(PluginBuildTag + #13#10#13#10 +
      'drag-lint: no active editor buffer to lint.');
    Exit;
  end;

  Ext := ExtractFileExt(FilePath);
  if Ext = '' then Ext := '.pas';
  TmpPath := TPath.Combine(TPath.GetTempPath,
    Format('drag-lint-buffer-%d%s', [GetTickCount, Ext]));

  Bytes := TEncoding.UTF8.GetBytes(BufText);
  try
    TmpStream := TFileStream.Create(TmpPath, fmCreate);
    try
      if Length(Bytes) > 0 then
        TmpStream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      TmpStream.Free;
    end;
  except
    on E: Exception do
    begin
      ShowMessage('drag-lint: could not write buffer snapshot: ' + E.Message);
      Exit;
    end;
  end;

  Cfg := LoadSettings;
  ExePath := Cfg.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
  begin
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(ExePath) then ExePath := 'drag-lint.exe';
  end;

  { Spawn detached: drag-lint lint <tmp> --json. We don't capture stdout
    in v0.40.3a — the diagnostic-publish path will be wired in v0.40.4
    after we add a one-shot --output <jsonfile> flag to drag-lint. Today
    the user sees results in the Messages pane via the spawn fall-through. }
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  CmdLine := Format('"%s" lint "%s"', [ExePath, TmpPath]);
  SetLength(CmdLineW, Length(CmdLine) + 1);
  Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));
  if CreateProcessW(nil, @CmdLineW[0], nil, nil, False,
    CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;

  TThread.Queue(nil,
    procedure
    var
      MS: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, MS) then
        MS.AddTitleMessage(Format(
          'drag-lint: linted buffer snapshot of %s (-> %s)',
          [ExtractFileName(FilePath), ExtractFileName(TmpPath)]));
    end);
end;

procedure InvokeOpenLog(Sender: TObject);
var
  LogPath: string;
begin
  LogPath := GetPluginLogPath;
  if not FileExists(LogPath) then
  begin
    ShowMessage(PluginBuildTag + #13#10#13#10 +
      'No log yet at:'#13#10 + LogPath +
      #13#10#13#10 +
      'The log is created on first plugin LSP invocation.');
    Exit;
  end;
  ShellExecute(0, 'open', PChar(LogPath), nil, nil, SW_SHOWNORMAL);
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
  // v0.39: diagnostic submenu
  AddWrappedItem(RootMenu, 'Lint Buffer (Unsaved)',      InvokeLintBuffer);
  AddWrappedItem(RootMenu, 'Test Connection...',         InvokeTestConnection);
  AddWrappedItem(RootMenu, 'Open Plugin Log',            InvokeOpenLog);

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
