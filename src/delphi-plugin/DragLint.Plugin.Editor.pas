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

{ v0.40.8c: exposed for the dwell tracker so it can produce the same
  "kind   name   --   unit.pas (line)" header that menu InvokeHover does. }
function ExtractHoverHeader(const AMarkdown: string): string;
function StripFirstHeaderLine(const AMarkdown: string): string;

procedure RegisterDragLintMenu;
procedure UnregisterDragLintMenu;

{ Invoke* procedures are also called by the keyboard binding unit }
procedure InvokeHover(Sender: TObject);
procedure InvokeCompletion(Sender: TObject);
{ v0.46: silent auto-trigger (typed '.') -- no dialogs, only pops if items. }
procedure InvokeCompletionAuto;
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
{ v0.39: diagnostic menu -- shows path resolution, subprocess spawn, LSP handshake details }
procedure InvokeTestConnection(Sender: TObject);
procedure InvokeOpenLog(Sender: TObject);

{ v0.40.3: lint the active editor BUFFER (unsaved changes included).
  Snapshots the in-memory text to %TEMP%\drag-lint-buffer-<n>.pas and
  runs drag-lint lint <tempfile> --json. Findings are merged into the
  diagnostic cache so inline markers update without saving the file. }
procedure InvokeLintBuffer(Sender: TObject);

/// <summary>Saves all modified modules then shells out to drag-lint
/// forms-csv for the active project and opens the resulting CSV in the
/// IDE editor. Prompts the user for the output path via a save dialog.</summary>
procedure InvokeGenerateFormsCsv(Sender: TObject);

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
  DragLint.Plugin.DockForm,
  DragLint.Plugin.GraphWindow,
  DragLint.Plugin.SaveNotifier,
  DragLint.Plugin.LiveDiagnostics,
  DragLint.Plugin.AutoComplete,
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
  { v0.42: the View > Tool Windows entry lives under the IDE's menu (its Owner
    is the IDE's Tool Windows item, not our GMenuItems), so our normal teardown
    can't free it. Track it explicitly and free it in UnregisterDragLintMenu. }
  GDockToolWinItem: TMenuItem = nil;
  { v0.43: the dedicated Graph dockable window's View > Tool Windows entry --
    same IDE-owned-menu caveat, tracked + freed the same way. }
  GGraphToolWinItem: TMenuItem = nil;

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
   empty string on any failure -- caller decides whether to show a popup
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
    { Silent -- fires from dwell timer; AVs here would break IDE }
    Result := '';
  end;
end;

{ v0.40.7: forward decls so FetchHoverCallers / InvokeHover compose can call
  helpers defined later in this unit. }
function RunAndCaptureStdout(const ACmdLine: string;
  out AOutput: string; ATimeoutMs: Integer = 60000): Integer; forward;
function IdentifierAtCursor: string; forward;

function FetchHoverCallers(const AExe, ASymName: string;
  const ADbList: TArray<string>): TArray<TDragLintCallerInfo>;
var
  CmdLine, Output, DbArgs: string;
  ExitCode, I: Integer;
  JV: TJSONValue;
  JArr: TJSONArray;
  JItem: TJSONObject;
  Info: TDragLintCallerInfo;
  Ctx: string;
  CtxLines: TArray<string>;
  L, LineNumStr, Trimmed: string;
  CapAt: Integer;
begin
  SetLength(Result, 0);
  if (AExe = '') or not FileExists(AExe) then Exit;
  if Trim(ASymName) = '' then Exit;

  DbArgs := '';
  for I := 0 to High(ADbList) do
    DbArgs := DbArgs + Format(' --db "%s"', [ADbList[I]]);

  CmdLine := Format('"%s" query find-callers --name "%s"%s --json --context 1',
    [AExe, ASymName, DbArgs]);

  ExitCode := RunAndCaptureStdout(CmdLine, Output, 5000);
  if (ExitCode <> 0) or (Trim(Output) = '') or (Output[1] <> '[') then Exit;

  JV := nil;
  try
    JV := TJSONObject.ParseJSONValue(Output);
  except
    JV := nil;
  end;
  if (JV = nil) or not (JV is TJSONArray) then
  begin
    if JV <> nil then JV.Free;
    Exit;
  end;

  try
    JArr := JV as TJSONArray;
    { Cap to 200 rows so the popup can never explode on hot symbols. }
    CapAt := JArr.Count;
    if CapAt > 200 then CapAt := 200;
    SetLength(Result, CapAt);
    for I := 0 to CapAt - 1 do
    begin
      if not (JArr.Items[I] is TJSONObject) then Continue;
      JItem := JArr.Items[I] as TJSONObject;
      Info.FilePath := JItem.GetValue<string>('file_path', '');
      Info.Line     := JItem.GetValue<Integer>('start_line', 0);
      Ctx           := JItem.GetValue<string>('context', '');
      Info.CodeText := '';
      LineNumStr    := IntToStr(Info.Line) + ':';
      CtxLines      := Ctx.Split([#10]);
      for L in CtxLines do
      begin
        Trimmed := Trim(L);
        if Pos(LineNumStr, Trimmed) = 1 then
        begin
          Info.CodeText := Trim(Copy(Trimmed, Length(LineNumStr) + 1, MaxInt));
          Break;
        end;
      end;
      Result[I] := Info;
    end;
  finally
    JV.Free;
  end;
end;

function ExtractHoverHeader(const AMarkdown: string): string;
{ Extract a single-line summary mirroring Delphi's own Code Insight popup:
    "<kind>   <name>   -   <unit>.pas (<line>)"
  Source: LSP hover markdown's first line "**name** `kind`" gives kind+name;
  the first subsequent "`<qname>` - line N" gives the unit and line. The
  unit is everything in the qname except the last 1-2 dotted segments
  (member, optionally class/record). Pas extension is appended. }
var
  Lines: TArray<string>;
  L, FirstLine: string;
  Name, Kind, Qname, LineStr, UnitName: string;
  P1, P2, P3, DashAt: Integer;
  I:  Integer;
  DotCount: Integer;
begin
  Result := '';
  if Trim(AMarkdown) = '' then Exit;
  Lines := AMarkdown.Split([#13, #10], TStringSplitOptions.ExcludeEmpty);
  if Length(Lines) = 0 then Exit;

  { Parse "**name** `kind`" header line. }
  FirstLine := Trim(Lines[0]);
  if (Length(FirstLine) >= 4) and (Copy(FirstLine, 1, 2) = '**') then
  begin
    P1 := Pos('**', Copy(FirstLine, 3, MaxInt));
    if P1 > 0 then
    begin
      Name := Copy(FirstLine, 3, P1 - 1);
      L := Trim(Copy(FirstLine, P1 + 4, MaxInt));
      if (L <> '') and (L[1] = '`') then
      begin
        P2 := Pos('`', Copy(L, 2, MaxInt));
        if P2 > 0 then
          Kind := Copy(L, 2, P2 - 1);
      end;
    end;
  end
  else
  begin
    Result := FirstLine;
    Exit;
  end;

  { Walk subsequent lines for first "`qname` - line N" entry. }
  Qname := '';
  LineStr := '';
  for I := 1 to High(Lines) do
  begin
    L := Trim(Lines[I]);
    { Optional bullet "- " prefix. }
    if (Length(L) >= 2) and (Copy(L, 1, 2) = '- ') then
      L := Trim(Copy(L, 3, MaxInt));
    if (L = '') or (L[1] <> '`') then Continue;
    P1 := Pos('`', Copy(L, 2, MaxInt));
    if P1 <= 0 then Continue;
    Qname := Copy(L, 2, P1 - 1);
    L := Trim(Copy(L, P1 + 2, MaxInt));
    DashAt := Pos('line ', L);
    if DashAt > 0 then
      LineStr := Trim(Copy(L, DashAt + 5, MaxInt));
    Break;
  end;

  { Derive unit name from qname: drop the last 1-2 dotted segments. If the
    last-but-one starts with T/I/E and has another segment after it, that's
    a class/interface so drop two. Otherwise drop one. }
  UnitName := '';
  if Qname <> '' then
  begin
    DotCount := 0;
    for I := 1 to Length(Qname) do
      if Qname[I] = '.' then Inc(DotCount);
    UnitName := Qname;
    if DotCount >= 2 then
    begin
      P2 := 0;
      for I := Length(UnitName) downto 1 do
        if UnitName[I] = '.' then
        begin
          P2 := I;
          Break;
        end;
      { Check the segment immediately before P2 starts with T/I/E (class kind). }
      P3 := 0;
      for I := P2 - 1 downto 1 do
        if UnitName[I] = '.' then
        begin
          P3 := I;
          Break;
        end;
      if (P3 > 0) and (P3 + 1 <= Length(UnitName)) and
         (CharInSet(UnitName[P3 + 1], ['T','I','E'])) then
        UnitName := Copy(UnitName, 1, P3 - 1)
      else
        UnitName := Copy(UnitName, 1, P2 - 1);
    end
    else if DotCount = 1 then
    begin
      P2 := Pos('.', UnitName);
      UnitName := Copy(UnitName, 1, P2 - 1);
    end;
  end;

  { Compose the header. }
  Result := '';
  if Kind <> '' then Result := Kind + '   ';
  Result := Result + Name;
  if UnitName <> '' then
  begin
    Result := Result + '   --   ' + UnitName + '.pas';
    if LineStr <> '' then
      Result := Result + ' (' + LineStr + ')';
  end;
end;

function StripFirstHeaderLine(const AMarkdown: string): string;
{ Drop the first "**name** `kind`" line so the body memo doesn't duplicate
  what's already on the header label. Keep the blank separator line so
  the definitions list reads naturally. }
var
  Lines: TArray<string>;
  SB:    TStringBuilder;
  StartIdx, I: Integer;
begin
  Result := AMarkdown;
  if Trim(AMarkdown) = '' then Exit;
  Lines := AMarkdown.Split([#10]);
  if (Length(Lines) = 0) then Exit;
  if Trim(Lines[0]).StartsWith('**') then
    StartIdx := 1
  else
    Exit;
  SB := TStringBuilder.Create;
  try
    for I := StartIdx to High(Lines) do
    begin
      SB.Append(Lines[I]);
      if I < High(Lines) then SB.Append(#10);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
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
  SymName:     string;
  Header:      string;
  Callers:     TArray<TDragLintCallerInfo>;
  Settings:    TDragLintSettings;
  ExePath:     string;
  DbList:      TArray<string>;
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

    { v0.40.7: compose the three-section popup.
      v0.40.8c: header includes unit.pas (line); body drops the dup'd first line. }
    Header := ExtractHoverHeader(HoverText);
    HoverText := StripFirstHeaderLine(HoverText);
    SymName := IdentifierAtCursor;
    Settings := LoadSettings;
    ExePath := Settings.ExePath;
    if (ExePath = '') or not FileExists(ExePath) then
      ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(ExePath) then ExePath := 'drag-lint.exe';
    try
      DbList := ResolveActiveIndexDbs(Settings);
    except
      SetLength(DbList, 0);
    end;
    Callers := FetchHoverCallers(ExePath, SymName, DbList);
    DebugLog(Format('InvokeHover: callers fetched: %d', [Length(Callers)]));

    { v0.40.6: menu invocation is explicit -- replace any current popup. }
    CloseDragLintHover;
    GetCursorPos(P);
    ShowDragLintHover(Header, HoverText, Callers, P.X, P.Y + 20);
  finally
    Resp.Free;
  end;
end;

{ v0.46: ASilent = auto-trigger (typed '.') -- suppress every dialog and only
  pop the list when there are items, with a short timeout so a slow/stuck engine
  never blocks typing. ASilent = False = manual invoke (menu/shortcut), keeps the
  informative dialogs. }
procedure DoCompletion(ASilent: Boolean);
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
    if not ASilent then ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/completion', Params,
      (if ASilent then 1200 else 5000));
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    if not ASilent then
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
      if not ASilent then
        ShowMessage('drag-lint completion:'#13#10 + Resp.Format(2));
      Exit;
    end;
    { auto-trigger: never pop an empty list. }
    if ASilent and (Items.Count = 0) then Exit;

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

procedure InvokeCompletion(Sender: TObject);
begin
  DoCompletion(False);
end;

procedure InvokeCompletionAuto;
begin
  DoCompletion(True);
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

procedure TriggerDiagnosticsOnSave(const AFile: string);
{ v0.42: hook installed into SaveNotifier.GAfterSaveDiagHook. Republishes
  diagnostics for a just-saved .pas by sending textDocument/didSave to the
  RUNNING LSP (the server replies with publishDiagnostics -> HandleNotification
  -> cache -> markers). We never force-start the LSP here -- if it isn't up yet
  we silently skip, so the save path is never blocked by a slow LSP init. }
var
  Params, TextDoc: TJSONObject;
  Uri: string;
begin
  if GLspClient = nil then Exit;
  if (AFile = '') or not SameText(ExtractFileExt(AFile), '.pas') then Exit;
  Uri := 'file:///' + StringReplace(AFile, '\', '/', [rfReplaceAll]);
  Params  := TJSONObject.Create;
  TextDoc := TJSONObject.Create;
  TextDoc.AddPair('uri', Uri);
  Params.AddPair('textDocument', TextDoc);
  try
    GLspClient.Notify('textDocument/didSave', Params);
  finally
    Params.Free;
  end;
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
// (lines of the form  "path.pas(N,...)" -- same format as dcc64/msbuild output).
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
      { Try one column to the left -- caret can sit just past an identifier. }
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
    { No DBs resolved -- fall back to legacy single-arg path so the form
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

{ ---- forms-csv IDE menu action ---- }

procedure InvokeGenerateFormsCsv(Sender: TObject);
{ Saves all modified modules, resolves the active project .dproj + drag-lint
  index, prompts for a CSV output path, runs forms-csv, then opens the
  resulting file in the IDE editor. }
var
  ProjFile, ProjDb, ExePath: string;
  OutPath, CmdLine, Output:  string;
  ExitCode:                  Integer;
  Dlg:                       TSaveDialog;
  MS:                        IOTAModuleServices;
  AS_:                       IOTAActionServices;
begin
  { Save all so on-disk DFMs match the editor; the engine reads saved files. }
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then
    MS.SaveAll;

  ProjFile := GetActiveProjectFile;
  ProjDb   := GetActiveProjectDb;
  if (ProjFile = '') or (ProjDb = '') then
  begin
    ShowMessage('drag-lint: no active project or index found.');
    Exit;
  end;

  { Resolve drag-lint.exe the same way the other handlers do. }
  ExePath := LoadSettings.ExePath;
  if (ExePath = '') or not FileExists(ExePath) then
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(ExePath) then
    ExePath := 'drag-lint.exe';

  { Prompt for the output CSV path. }
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter     := 'CSV files (*.csv)|*.csv';
    Dlg.DefaultExt := 'csv';
    Dlg.FileName   := ChangeFileExt(ExtractFileName(ProjFile), '') + '-forms.csv';
    Dlg.InitialDir := ExtractFilePath(ProjFile);
    if not Dlg.Execute then
      Exit;
    OutPath := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  CmdLine  := Format('"%s" forms-csv --project "%s" --db "%s" --out "%s"',
                [ExePath, ProjFile, ProjDb, OutPath]);
  ExitCode := RunAndCaptureStdout(CmdLine, Output, 120000);

  if ExitCode <> 0 then
  begin
    ShowMessage('drag-lint: forms-csv failed. See plugin log.');
    Exit;
  end;

  { Open the generated CSV in the IDE editor. }
  if Supports(BorlandIDEServices, IOTAActionServices, AS_) then
    AS_.OpenFile(OutPath);
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

{ v0.42: menu separator line. }
function AddSeparator(AParent: TMenuItem): TMenuItem;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := '-';
  AParent.Add(Result);
end;

{ v0.42: a non-clickable section header (disabled caption) used to label the
  diagnostics/test block at the bottom of the menu. }
function AddSectionHeader(AParent: TMenuItem; const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := ACaption;
  Result.Enabled := False;
  AParent.Add(Result);
end;

{ v0.42: recursively find a menu item by Name anywhere under AParent. Used to
  remove a stale dock entry left by a prior install/reinstall before we add a
  fresh one, so View > Tool Windows never accumulates duplicates. }
function FindMenuItemByName(AParent: TMenuItem; const AName: string): TMenuItem;
var
  I: Integer;
begin
  Result := nil;
  if AParent = nil then Exit;
  for I := 0 to AParent.Count - 1 do
  begin
    if SameText(AParent.Items[I].Name, AName) then
      Exit(AParent.Items[I]);
    Result := FindMenuItemByName(AParent.Items[I], AName);
    if Result <> nil then Exit;
  end;
end;

{ v0.42: free every direct child of AParent whose (ampersand-stripped) caption
  equals ACaption. Used to purge any stale 'drag-lint' dock entries left under
  View > Tool Windows by a prior install that didn't (or couldn't) clean up,
  regardless of whether they had a Name set. }
procedure RemoveChildrenByCaption(AParent: TMenuItem; const ACaption: string);
var
  I: Integer;
  C: string;
begin
  if AParent = nil then Exit;
  for I := AParent.Count - 1 downto 0 do
  begin
    C := StringReplace(AParent.Items[I].Caption, '&', '', [rfReplaceAll]);
    if SameText(Trim(C), ACaption) then
      AParent.Items[I].Free;
  end;
end;

{ v0.42: find a direct child menu item by its (ampersand-stripped) caption. }
function FindMenuChildByCaption(AParent: TMenuItem;
  const ACaption: string): TMenuItem;
var
  I: Integer;
  C: string;
begin
  Result := nil;
  if AParent = nil then Exit;
  for I := 0 to AParent.Count - 1 do
  begin
    C := StringReplace(AParent.Items[I].Caption, '&', '', [rfReplaceAll]);
    if SameText(Trim(C), ACaption) then
      Exit(AParent.Items[I]);
  end;
end;

{ v0.42: locate the IDE's "View > Tool Windows" submenu so we can register the
  dock panel there, alongside Structure / Project Manager / Messages -- the
  conventional home for dockable tool windows. Falls back to the View menu
  itself, then nil (caller keeps the top-level drag-lint entry). }
function FindViewToolWindowsMenu(Services: INTAServices): TMenuItem;
var
  MainMenu: TMainMenu;
  ViewItem: TMenuItem;
begin
  Result := nil;
  if Services = nil then Exit;
  MainMenu := Services.MainMenu;
  if MainMenu = nil then Exit;
  ViewItem := FindMenuChildByCaption(MainMenu.Items, 'View');
  if ViewItem = nil then Exit;
  Result := FindMenuChildByCaption(ViewItem, 'Tool Windows');
  if Result = nil then
    Result := ViewItem;   { fall back to View itself }
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
  { v0.46: read to true EOF -- GetText can short-read mid-buffer, so the old
    `until N < CHUNK` truncated the snapshot (see LiveDiagnostics.ActiveBufferText). }
  repeat
    N := Reader.GetText(Pos, Tmp, CHUNK);
    if N <= 0 then Break;
    SetLength(Buf, Length(Buf) + N);
    Move(Tmp[0], Buf[Length(Buf) - N], N);
    Inc(Pos, N);
  until False;

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
    in v0.40.3a -- the diagnostic-publish path will be wired in v0.40.4
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

procedure InvokeCopyDiagnostics(Sender: TObject);
{ v0.46: lint the active SAVED file ON DEMAND (synchronous), copy the findings to
  the clipboard (for pasting to an AI) AND publish them to the cache + repaint so
  the gutter/inline markers light up. This is independent of the background
  live-diagnostics runner -- it always reflects the file on disk right now. }
var
  ES: IOTAEditorServices;
  EV: IOTAEditView;
  FilePath, Exe, CmdLine, Output, Line, Loc, Loc2, ColStr, LineStr: string;
  Tag, Rest, Rule, Msg, ClipText: string;
  Lines: TStringList;
  SB: TStringBuilder;
  I, lb, rb, c1, c2, p, LineNo, ColNo, Count, SevInt: Integer;
  Params, DObj, RangeObj, StartObj, EndObj: TJSONObject;
  Arr: TJSONArray;
begin
  FilePath := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, ES) and (ES <> nil) then
  begin
    EV := ES.TopView;
    if (EV <> nil) and (EV.Buffer <> nil) then
      FilePath := EV.Buffer.FileName;
  end;
  if (FilePath = '') or not FileExists(FilePath) then
  begin
    ShowMessage('drag-lint: no active SAVED file to lint. Save the file (Ctrl+S) first.');
    Exit;
  end;

  { Prefer the engine bundled beside the BPL (current), like the LSP. }
  Exe := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Exe) then
  begin
    Exe := LoadSettings.ExePath;
    if (Exe = '') or not FileExists(Exe) then Exe := 'drag-lint.exe';
  end;

  CmdLine := Format('"%s" lint "%s"', [Exe, FilePath]);
  Output := '';
  RunAndCaptureStdout(CmdLine, Output, 20000);

  Lines  := TStringList.Create;
  SB     := TStringBuilder.Create;
  Params := TJSONObject.Create;
  Arr    := TJSONArray.Create;
  try
    Lines.Text := Output;
    Count := 0;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      lb := Pos('[', Line); rb := Pos(']', Line);
      if (lb = 0) or (rb = 0) or (rb < lb) then Continue;   { not a finding line }
      Loc := Trim(Copy(Line, 1, lb - 1));
      c2 := LastDelimiter(':', Loc); if c2 <= 1 then Continue;
      ColStr := Copy(Loc, c2 + 1, MaxInt);
      Loc2 := Copy(Loc, 1, c2 - 1);
      c1 := LastDelimiter(':', Loc2); if c1 <= 1 then Continue;
      LineStr := Copy(Loc2, c1 + 1, MaxInt);
      Tag := LowerCase(Copy(Line, lb + 1, rb - lb - 1));
      Rest := Trim(Copy(Line, rb + 1, MaxInt));
      p := Pos(':', Rest);
      if p > 0 then
      begin Rule := Trim(Copy(Rest, 1, p - 1)); Msg := Trim(Copy(Rest, p + 1, MaxInt)); end
      else
      begin Rule := ''; Msg := Rest; end;
      LineNo := StrToIntDef(Trim(LineStr), 1);
      ColNo  := StrToIntDef(Trim(ColStr), 1);

      SB.AppendLine(Format('%s(%d,%d): %s %s: %s',
        [FilePath, LineNo, ColNo, Tag, Rule, Msg]));
      Inc(Count);

      { cache entry (LSP-style, 0-based) so EditViewNotifier paints it }
      if Pos('error', Tag) > 0 then SevInt := 1
      else if Pos('warn', Tag) > 0 then SevInt := 2
      else if Pos('hint', Tag) > 0 then SevInt := 4
      else SevInt := 3;
      StartObj := TJSONObject.Create;
      StartObj.AddPair('line', TJSONNumber.Create(LineNo - 1));
      StartObj.AddPair('character', TJSONNumber.Create(ColNo - 1));
      EndObj := TJSONObject.Create;
      EndObj.AddPair('line', TJSONNumber.Create(LineNo - 1));
      EndObj.AddPair('character', TJSONNumber.Create(ColNo + 1));
      RangeObj := TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end', EndObj);
      DObj := TJSONObject.Create;
      DObj.AddPair('range', RangeObj);
      DObj.AddPair('severity', TJSONNumber.Create(SevInt));
      DObj.AddPair('source', 'lint');
      DObj.AddPair('code', Rule);
      DObj.AddPair('message', Msg);
      Arr.AddElement(DObj);
    end;

    Params.AddPair('diagnostics', Arr);   { Arr ownership -> Params }
    Cache.Update(FilePath, Params);
    if (ES <> nil) and (ES.TopView <> nil) then
      try ES.TopView.Paint; except end;

    if Count = 0 then
      ShowMessage(Format('drag-lint: no diagnostics for %s.',
        [ExtractFileName(FilePath)]))
    else
    begin
      ClipText := Format('drag-lint diagnostics for %s (%d):'#13#10'%s',
        [ExtractFileName(FilePath), Count, SB.ToString]);
      Vcl.Clipbrd.Clipboard.AsText := ClipText;
      ShowMessage(Format(
        'drag-lint: %d diagnostic(s) copied to the clipboard and shown in the gutter.',
        [Count]));
    end;
  finally
    SB.Free;
    Lines.Free;
    Params.Free;   { frees Arr + child objects }
  end;
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

procedure AutoPullStagedExe;
{ v0.40.8h: when the user reinstalls the BPL via Component -> Install Packages,
  pull a newer drag-lint.exe from C:\TEMP1\bpl_staging\ into the BPL's
  deployment directory. The previous BPL's UnregisterDragLintMenu killed
  the LSP child process (LspClient.Stop -> TerminateProcess), so the EXE
  file handle is free at this point. No-op if the staged file is missing
  or not newer than the deployed one. Errors are silent: we never want
  package init to fail just because a copy failed. }
const
  STAGING_PATH = 'C:\TEMP1\bpl_staging\drag-lint.exe';
var
  DeployDir, DeployedExe: string;
  StagedTime, DeployedTime: TDateTime;
begin
  try
    if not FileExists(STAGING_PATH) then Exit;
    DeployDir := ExtractFilePath(GetModuleName(HInstance));
    DeployedExe := DeployDir + 'drag-lint.exe';
    StagedTime := 0;
    if FileAge(STAGING_PATH, StagedTime) then
    begin
      if FileExists(DeployedExe) and FileAge(DeployedExe, DeployedTime) then
      begin
        if StagedTime <= DeployedTime then Exit;
      end;
      { Copy staged -> deployed. Give the kernel a beat in case Stop's
        TerminateProcess hasn't fully released the file yet. }
      Sleep(500);
      if Winapi.Windows.CopyFile(PChar(STAGING_PATH), PChar(DeployedExe), False) then
        DebugLog(Format('AutoPullStagedExe: copied %s -> %s',
          [STAGING_PATH, DeployedExe]))
      else
        DebugLog(Format('AutoPullStagedExe: CopyFile FAILED (Win32 err %d) for %s',
          [GetLastError, DeployedExe]));
    end;
  except
    on E: Exception do
      DebugLog('AutoPullStagedExe: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure InvokeDockPanel(Sender: TObject);
begin
  ShowDragLintDock;
end;

procedure InvokeGraphWindow(Sender: TObject);
begin
  ShowDragLintGraph;
end;

procedure RegisterDragLintMenu;
var
  Services: INTAServices;
  RootMenu: TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) then Exit;

  AutoPullStagedExe;

  GMenuItems := TObjectList<TMenuItem>.Create(True);
  GWrappers  := TObjectList<TMenuActionWrapper>.Create(True);

  RootMenu := TMenuItem.Create(nil);
  RootMenu.Caption := 'drag-lint';
  { Top-level IDE menu (like TableTools): insert directly into the main menu bar
    instead of nesting under Tools.  RootMenu has NO component owner (Create(nil))
    and is added only as a menu CHILD here; GMenuItems is its sole owner and frees
    it on unload, at which point TMenuItem.Destroy removes it from the menu bar --
    so teardown stays single-owner (no double-free).  Falls back to the Tools
    submenu if the IDE main menu is unavailable. }
  if Services.MainMenu <> nil then
    Services.MainMenu.Items.Add(RootMenu)
  else
    Services.AddActionMenu('ToolsMenu', nil, RootMenu, True, True);
  GMenuItems.Add(RootMenu);

  { v0.42: daily-use actions on top; diagnostics & test harness bunched below
    a separator so the everyday items aren't lost among them. }
  AddWrappedItem(RootMenu, 'drag-lint Panel (dockable)', InvokeDockPanel);
  AddWrappedItem(RootMenu, 'drag-lint Graph (dockable)', InvokeGraphWindow);
  AddSeparator(RootMenu);
  AddWrappedItem(RootMenu, 'Hover at Cursor',           InvokeHover);
  AddWrappedItem(RootMenu, 'Show Completion',            InvokeCompletion);
  AddWrappedItem(RootMenu, 'Show Signature Help',        InvokeSignatureHelp);
  AddWrappedItem(RootMenu, 'Find Usages...',             InvokeFindUsages);
  AddWrappedItem(RootMenu, 'Symbol Search...',           InvokeSymbolSearch);
  AddWrappedItem(RootMenu, 'Show Structure',             InvokeShowStructure);
  AddWrappedItem(RootMenu, 'Rename Symbol...',           InvokeRename);
  AddWrappedItem(RootMenu, 'Format with YADF',           InvokeFormatYadf);
  AddWrappedItem(RootMenu, 'Generate Test Helper CSV...', InvokeGenerateFormsCsv);
  AddWrappedItem(RootMenu, 'Settings...',                InvokeSettings);

  { ---- Diagnostics & Tests (alpha) ---- }
  AddSeparator(RootMenu);
  AddSectionHeader(RootMenu, 'Diagnostics && Tests');
  AddWrappedItem(RootMenu, 'Run Diagnostics (didSave)',  InvokeDiagnostics);
  AddWrappedItem(RootMenu, 'Run AST Checks',             InvokeRunAstChecks);
  AddWrappedItem(RootMenu, 'Lint Buffer (Unsaved)',      InvokeLintBuffer);
  AddWrappedItem(RootMenu, 'Copy Diagnostics (Current File)', InvokeCopyDiagnostics);
  AddWrappedItem(RootMenu, 'Compile && Diagnose',        InvokeCompileDiagnose);
  AddWrappedItem(RootMenu, 'Import Build Log...',        InvokeImportLog);
  AddWrappedItem(RootMenu, 'Test Connection...',         InvokeTestConnection);
  AddWrappedItem(RootMenu, 'Open Plugin Log',            InvokeOpenLog);

  { v0.42: also surface the dockable panel under View > Tool Windows. This item
    can NOT go through AddWrappedItem/GMenuItems: its Owner ends up being the
    IDE's Tool Windows menu item, so our GMenuItems teardown never frees it and
    it lingers after uninstall (-> duplicate + a stale entry that calls into the
    unloaded BPL). Instead: purge ANY pre-existing 'drag-lint' child first
    (catches stale entries from earlier installs, named or not), create one
    tracked item in GDockToolWinItem, and free it explicitly on teardown. }
  var ToolWin: TMenuItem := FindViewToolWindowsMenu(Services);
  if ToolWin <> nil then
  begin
    RemoveChildrenByCaption(ToolWin, 'drag-lint');
    RemoveChildrenByCaption(ToolWin, 'drag-lint Graph');
    GDockToolWinItem := TMenuItem.Create(ToolWin);
    GDockToolWinItem.Caption := 'drag-lint';
    var DockWrap: TMenuActionWrapper := TMenuActionWrapper.Create(InvokeDockPanel);
    GWrappers.Add(DockWrap);
    GDockToolWinItem.OnClick := DockWrap.HandleClick;
    ToolWin.Add(GDockToolWinItem);

    { v0.43: second entry for the dedicated Graph window. }
    GGraphToolWinItem := TMenuItem.Create(ToolWin);
    GGraphToolWinItem.Caption := 'drag-lint Graph';
    var GraphWrap: TMenuActionWrapper := TMenuActionWrapper.Create(InvokeGraphWindow);
    GWrappers.Add(GraphWrap);
    GGraphToolWinItem.OnClick := GraphWrap.HandleClick;
    ToolWin.Add(GGraphToolWinItem);
  end;

  RegisterProjectNotifier;
  RegisterDragLintKeystrokes;
  RegisterDragLintEditViewNotifier;
  { v0.40.7: dwell tracker re-enabled with the 1600 ms threshold (was 600 ms)
    and the singleton guard, so it fires only on deliberate dwells and never
    competes with an already-visible popup. Menu InvokeHover does the richer
    three-section show with callers; dwell does the short LSP-only summary. }
  StartHoverTracker;

  { v0.42: auto-publish diagnostics on save (syntax errors + lint -> markers +
    the Structure 'Diagnostics' node). The hook is no-op until the LSP is up. }
  DragLint.Plugin.SaveNotifier.GAfterSaveDiagHook := TriggerDiagnosticsOnSave;

  { v0.42: live edit-time diagnostics (debounced buffer lint via the provider
    registry). }
  StartLiveDiagnostics;

  { v0.46: automatic completion trigger (pops on a typed '.'; debounced). }
  StartAutoComplete;
end;

procedure UnregisterDragLintMenu;
begin
  { v0.40.8d: close hover popup before tearing down notifiers, otherwise
    its 150 ms watch timer can fire after the BPL's HoverForm DCU has
    been unloaded -- observed as an IDE crash on Uninstall. }
  try CloseDragLintHover; except end;
  try StopAutoComplete; except end;
  try StopLiveDiagnostics; except end;
  { v0.43: tear down the dedicated Graph window first so its frame dtor
    terminates the embedded drag_lint_graph.exe before the BPL unloads. }
  try UnregisterDragLintGraph; except end;
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
  { v0.42: free the View > Tool Windows entry explicitly (its Owner is the IDE
    menu, so GMenuItems won't reach it). Freeing removes it from the IDE menu --
    this is what stops a duplicate/stale entry surviving an uninstall. Do it
    before GWrappers so its OnClick wrapper isn't dangling. }
  FreeAndNil(GDockToolWinItem);
  FreeAndNil(GGraphToolWinItem);
  { Wrappers hold the OnClick method pointers; free them before the menu items }
  FreeAndNil(GWrappers);
  FreeAndNil(GMenuItems);
end;

initialization

finalization
  UnregisterDragLintMenu;

end.
