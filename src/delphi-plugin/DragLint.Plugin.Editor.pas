unit DragLint.Plugin.Editor;

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , Vcl.Menus
  , Vcl.Dialogs
  , ToolsAPI
  , DragLint.Plugin.LspClient
  , DragLint.Plugin.ProjectNotifier
  , DragLint.Plugin.Settings
  , DragLint.Plugin.HoverForm
  , DragLint.Plugin.CompletionForm
  , DragLint.Plugin.SignatureForm
  , DragLint.Plugin.RefactorForm
  , DragLint.Plugin.StructureForm
  , DragLint.Plugin.UsagesForm
  , DragLint.Plugin.SymbolSearchForm
  ;

const (* v0.40.1: hardcoded version; build stamp resolved at runtime from the
     loaded BPL's file modtime (see PluginBuildTag). Compiler intrinsics
     like the dollar-I DATE/TIME macros emit unquoted strings in Delphi 13
     and don't fit in a const expression. *)
  PLUGIN_VERSION = 'v1.1.0-alpha';

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
function QueryHoverText(const AUri: string; ALine, ACol: Integer; ATimeoutMs: Integer = 500): string;

{ v0.40.8c: exposed for the dwell tracker so it can produce the same
  "kind   name   --   unit.pas (line)" header that menu InvokeHover does. }
function ExtractHoverHeader  (const AMarkdown: string): string;
function StripFirstHeaderLine(const AMarkdown: string): string;

{ v0.94.1: exposed for the dwell tracker so a MOUSE hover shows the same
  structured Help-Insight model (colored signature + Parameters + Returns +
  Called-from) as the menu InvokeHover -- not just the plain string popup. Given
  the RAW LSP hover markdown, mine the qualified name, fetch `hover --json`, and
  fetch the callers. Returns True + fills AModel/ACallers on success; False
  (caller shows the string popup) on any miss. }
function TryBuildHoverModel(const ARawMarkdown: string; out AModel: TDragLintHoverModel; out ACallers: TArray<TDragLintCallerInfo>): Boolean;

/// <summary>Spawns ACmdLine via CreateProcessW with merged stdout+stderr
/// capture and blocks until the child exits (or ATimeoutMs elapses).</summary>
/// <param name="ACmdLine">Full command line (exe path already quoted by the caller).</param>
/// <param name="AOutput">Receives the full captured text output.</param>
/// <param name="ATimeoutMs">Wait budget in ms; 0 means INFINITE.</param>
/// <returns>The process exit code, or -1 on spawn failure.</returns>
/// <remarks>v0.88: exposed so the Structure form's AutoFix menu can reuse the
/// one shared spawn helper instead of duplicating CreateProcess plumbing.
/// Synchronous -- call from a context where a brief block is acceptable.</remarks>
function RunAndCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer = 60000): Integer;

procedure RegisterDragLintMenu;
procedure UnregisterDragLintMenu;

{ Invoke* procedures are also called by the keyboard binding unit }
procedure InvokeHover     (Sender: TObject);
procedure InvokeCompletion(Sender: TObject);
{ v0.46: silent auto-trigger (typed '.') -- no dialogs, only pops if items. }
procedure InvokeCompletionAuto;
{ v0.46: quick-fix -- add the unit for the undeclared identifier at the cursor
  (bound to Ctrl+Alt+U). }
procedure InvokeQuickFixUses (Sender: TObject);
procedure InvokeQuickFixInlineHintUses(Sender: TObject);
procedure InvokeConvertFieldToProperty(Sender: TObject);
procedure InvokeSignatureHelp(Sender: TObject);
procedure InvokeDiagnostics  (Sender: TObject);
procedure InvokeRename       (Sender: TObject);
{ Batch E Task 3: reverse call tree (Messages window), exposed to the
  keyboard binding unit (Ctrl+Alt+K) the same way InvokeRename etc. are --
  must be forward-declared here in the interface section, since Keyboard.pas
  can only see identifiers Editor.pas exports from its interface, not ones
  declared only in its implementation section (mutual implementation-uses
  does not itself grant visibility). }
procedure InvokeReverseCallTreeMessages(Sender: TObject);
/// <summary>Builds the butterfly call graph (callers + callees) for the symbol
/// under the caret (prompts for a qname) and shows it in the dock's Call Graph
/// tab. Shells drag-lint reverse-calltree --format json twice (callers, then
/// --direction callees) on a background thread, then marshals both JSON docs to
/// the dock via TThread.Queue. Bound to Ctrl+Alt+B and a Uses &amp; Dependencies
/// menu item.</summary>
procedure InvokeButterfly(Sender: TObject);
/// <summary>Shells reverse-calltree --format json twice (callers, then --direction
/// callees) for AQName against ADb on a background thread, slices each stdout to
/// its JSON object, then marshals onto the main thread via TThread.Queue to show
/// the dock and call GDockFrame.PopulateButterfly with both slices. Factored out
/// of InvokeButterfly so other entry points (e.g. the Structure form's context
/// menu) can jump straight to the butterfly view without re-prompting for a
/// qname. Safe with a nil GDockFrame (no-op) or empty/failed CLI output
/// (PopulateButterfly renders "(0)" roots rather than erroring).</summary>
procedure ShowButterflyForQName(const AQName, ADb: string);
{ v0.26: compiler diagnostics }
procedure InvokeCompileDiagnose(Sender: TObject);
procedure InvokeGhostCheck     (Sender: TObject);
procedure InvokeGhostRecover   (Sender: TObject);
{ v0.47: non-interactive recovery for a SPECIFIC project; the project-open
  notifier calls this once a .dproj is actually loaded (the BPL-load startup
  pass runs before any project exists and would otherwise miss the crash). }
procedure RunGhostRecoverForProject(const AProjFile: string);
{ v0.48: silent plain compile of a SPECIFIC project, for the project-open
  notifier's startup compile (AutoCompileOnStartup). }
procedure TriggerProjectCompile(const AProjFile: string);
procedure InvokeImportLog(Sender: TObject);
{ v0.27: YADF format integration }
procedure InvokeFormatYadf(Sender: TObject);
{ v0.30: structure form }
procedure InvokeShowStructure(Sender: TObject);
{ v0.31: AST checks }
procedure InvokeRunAstChecks(Sender: TObject);
{ v0.33: find usages + symbol search }
procedure InvokeFindUsages  (Sender: TObject);
procedure InvokeSymbolSearch(Sender: TObject);
procedure InvokeOpenLog       (Sender: TObject);

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
  System.Generics.Collections
  , System.Generics.Defaults
  , System.IOUtils
  , System.StrUtils
  , System.UITypes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.Clipbrd
  , Winapi.Windows
  , Winapi.ShellAPI
  , DragLint.Plugin.Keyboard
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.EditViewNotifier
  , DragLint.Plugin.HoverTracker
  , DragLint.Plugin.DockForm
  , DragLint.Plugin.GraphWindow
  , DragLint.Plugin.SaveNotifier
  , DragLint.Plugin.LiveDiagnostics
  , DragLint.Plugin.AutoComplete
  , DragLint.Plugin.Telemetry
  , { TEMP debug telemetry }
    DragLint.Plugin.DbResolver
  , DRagLint.Index.Manifest   { TProjectDbMatch: pdmUnique / pdmAmbiguous / pdmNone }
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.JobQueue
  , DragLint.Plugin.ExeResolver
  ;

{ ---- PluginBuildTag ---- }

function PluginBuildTag: string;
var
  ModName: string   ;
  Age    : TDateTime;
begin
  ModName:= GetModuleName(HInstance);
  if (ModName <> '') and FileAge(ModName, Age) then Result:= 'drag-lint plugin ' + PLUGIN_VERSION + ' (BPL built ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Age) + ')'
  else Result:= 'drag-lint plugin ' + PLUGIN_VERSION + ' (BPL build time unknown)';
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
  FProc:= AProc;
end;

procedure TMenuActionWrapper.HandleClick(Sender: TObject);
begin
  if Assigned(FProc) then FProc(Sender);
end;

{ ---- notification handler ---- }

type
  TDiagEntry = record
    FileName: string ;
    Msg     : string ;
    Rule    : string ;
    Line    : Integer;
    Col     : Integer;
  end;

procedure HandleNotification(const AMethod: string; AParams: TJSONValue);
var
  Diags   : TJSONArray        ;
  UriStr  : string            ;
  FileName: string            ;
  i       : Integer           ;
  DiagObj : TJSONObject       ;
  RangeObj: TJSONObject       ;
  StartObj: TJSONObject       ;
  Entries : TArray<TDiagEntry>;
  E       : TDiagEntry        ;
begin
  if AMethod <> 'textDocument/publishDiagnostics' then Exit;
  if not (AParams is TJSONObject) then Exit;

  if not (AParams as TJSONObject).TryGetValue<string>('uri', UriStr) then Exit;
  if not (AParams as TJSONObject).TryGetValue<TJSONArray>('diagnostics', Diags) then Exit;

  { Convert file URI to local Windows path }
  FileName:= UriStr;
  if (Length(FileName) > 8) and (LowerCase(Copy(FileName, 1, 8)) = 'file:///') then FileName:= StringReplace(Copy(FileName, 9, MaxInt), '/', '\', [rfReplaceAll]);

  { v0.29: update the visual diagnostic cache (runs on the LSP reader thread;
    Cache.Update is thread-safe). }
  Cache.Update(FileName, AParams);
  DebugLog(Format('LSP publishDiagnostics: %s -> %d diag(s) (overwrites live cache)', [ExtractFileName(FileName), Diags.Count]));

  { Collect diagnostic entries before queuing (Diags is owned by AMsg which
    will be freed after this call returns) }
  SetLength(Entries, Diags.Count);
  for i:= 0 to Diags.Count - 1 do
  begin
    E.FileName:= FileName;
    E.Msg     := '';
    E.Rule    := 'drag-lint';
    E.Line    := 1;
    E.Col     := 1;

    if not (Diags.Items[i] is TJSONObject) then
    begin
      Entries[i]:= E;
      Continue;
    end;
    DiagObj:= Diags.Items[i] as TJSONObject;

    DiagObj.TryGetValue<string>('message', E.Msg );
    DiagObj.TryGetValue<string>('code'   , E.Rule);

    if DiagObj .TryGetValue<TJSONObject>('range', RangeObj) then
    if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
      begin
        { LSP 0-based -> IOTAMessageServices 1-based }
        StartObj.TryGetValue<Integer>('line'     , E.Line);
        StartObj.TryGetValue<Integer>('character', E.Col );
        Inc(E.Line);
        Inc(E.Col );
      end;

    Entries[i]:= E;
  end; // for

  { Post everything to the main thread for the IDE message pane }
  TThread.Queue(
    nil,
    procedure var MS: IOTAMessageServices; j: Integer; begin { v0.47: force the gutter to repaint so its glyphs match the cache we just
        updated (an LSP publish that clears/changes findings must not leave stale
        dots behind). } ForceGutterRepaint; if not Supports(BorlandIDEServices, IOTAMessageServices,
        MS) then Exit; if Length(Entries) = 0 then begin MS.AddTitleMessage( Format('drag-lint: no diagnostics for %s',
            [FileName])); Exit; end; MS.AddTitleMessage( Format('drag-lint: %d diagnostic(s) for %s', [Length(Entries),
            FileName])); for j:= 0 to High(Entries) do MS.AddToolMessage( Entries[j].FileName, Entries[j].Msg, Entries[j].Rule, Entries[j].Line, Entries[j].Col); end
  );
end; // procedure

{ ---- shared LSP client ---- }

var
  GLspClient: TDragLintLspClient              = nil             ;
  GMenuItems: TObjectList<TMenuItem>          = nil         ;
  GWrappers : TObjectList<TMenuActionWrapper> = nil;
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
  BplDir : string;
  LogPath: string;
begin
  if GLspClient = nil then
  begin
    GLspClient:= TDragLintLspClient.Create;
    GLspClient.OnNotification:= HandleNotification;

    BplDir:= ExtractFilePath(GetModuleName(HInstance));
    DebugLog('EnsureLspClient: BPL dir = ' + BplDir);
    DebugLog('EnsureLspClient: BPL fullpath = ' + GetModuleName(HInstance));

    { Prefer the Win64 exe in the sibling dll-win64\ folder -- a 32-bit BPL can
      spawn a 64-bit child via CreateProcess, and the Win64 build carries its own
      correct x64 tree-sitter DLLs. Fall back to an exe next to the BPL (for
      non-standard layouts), then to PATH as last resort. }
    var Win64Dir: string := ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\';
    if FileExists(Win64Dir + 'drag-lint.exe') then
    begin
      ExePath:= Win64Dir + 'drag-lint.exe';
      DebugLog('EnsureLspClient: using Win64 exe = ' + ExePath);
    end
    else if FileExists(BplDir + 'drag-lint.exe') then
    begin
      ExePath:= BplDir + 'drag-lint.exe';
      DebugLog('EnsureLspClient: Win64 sibling not found, using local exe = ' + ExePath);
    end
    else
    begin
      ExePath:= 'drag-lint.exe';
      DebugLog('EnsureLspClient: falling back to PATH lookup of drag-lint.exe');
    end;

    LogPath:= GetPluginLogPath;

    { v0.40.3: resolve all index DBs for the currently-active editor file
      and pass them as --db flags. Plugin Settings + auto-discovery + the
      exe-relative library DB are all merged inside ResolveActiveIndexDbs. }
    var DbList: TArray<string>;
    try
      DbList:= ResolveActiveIndexDbs(LoadSettings);
    except
      SetLength(DbList, 0);
    end;

    if not GLspClient.Start(ExePath, DbList) then
    begin
      ShowMessage(
        PluginBuildTag + #13#10#13#10 + 'drag-lint: LSP server failed to start.'#13#10 + 'Ensure drag-lint.exe is on PATH or next to the BPL.'#13#10#13#10 +
        'BPL dir:        ' + BplDir + #13#10 + 'Resolved exe:   ' + ExePath + #13#10 + Format('DBs:            %d resolved', [Length(DbList)]) + #13#10 +
        'Debug log:      ' + LogPath);
      FreeAndNil(GLspClient);
      Exit(nil);
    end;

    if not GLspClient.Initialize then
    begin
      ShowMessage(
        PluginBuildTag + #13#10#13#10 + 'drag-lint: LSP initialize handshake failed.'#13#10#13#10 + 'BPL dir:        ' + BplDir + #13#10 + 'Resolved exe:   ' + ExePath + #13#10 +
        'Debug log:      ' + LogPath);
      GLspClient.Stop;
      FreeAndNil(GLspClient);
      Exit(nil);
    end;
  end; // if
  Result:= GLspClient;
end; // function

{ ---- OTAPI helpers ---- }

function GetActiveEditorInfo(out AUri: string; out ALine, ACol: Integer): Boolean;
var
  ESS     : IOTAEditorServices;
  EditView: IOTAEditView      ;
  FileName: string            ;
begin
  Result:= False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView:= ESS.TopView;
  if EditView = nil then Exit;

  FileName:= EditView.Buffer.FileName;
  if FileName = '' then Exit;

  { Convert Windows path to LSP file URI }
  AUri:= 'file:///' + StringReplace(FileName, '\', '/', [rfReplaceAll]);

  { IOTAEditView.Position is 1-based; LSP is 0-based }
  ALine:= EditView.Position.Row    - 1;
  ACol := EditView.Position.Column - 1;
  if ALine < 0 then ALine:= 0;
  if ACol  < 0 then ACol := 0;

  Result:= True;
end; // function

function MakeTextDocumentPositionParams(const AUri: string; ALine, ACol: Integer): TJSONObject;
var
  TextDoc: TJSONObject;
  Pos    : TJSONObject;
begin
  Result := TJSONObject.Create;
  TextDoc:= TJSONObject.Create;
  TextDoc.AddPair('uri'         , AUri   );
  Result .AddPair('textDocument', TextDoc);
  Pos:= TJSONObject.Create;
  Pos.AddPair('line'     , TJSONNumber.Create(ALine));
  Pos.AddPair('character', TJSONNumber.Create(ACol ));
  Result.AddPair('position', Pos);
end;

{ ---- menu action procedures ---- }

function QueryHoverText(const AUri: string; ALine, ACol: Integer; ATimeoutMs: Integer): string;
(* v0.40.3: shared hover-text extraction used by both InvokeHover (manual
   Ctrl+Alt+H invocation) and the HoverTracker dwell trigger. Returns
   empty string on any failure -- caller decides whether to show a popup
   or fall back to diagnostic-only.

   v0.40.5: TDragLintLspClient.Request returns the FULL JSON-RPC envelope
   (jsonrpc, id, result, error), not just the inner result. Earlier
   versions of this function looked for 'contents' at the top level and
   always missed -- the markdown body was inside .result.contents.value. *)
var
  Client     : TDragLintLspClient;
  Params     : TJSONObject       ;
  Resp       : TJSONValue        ;
  ResultVal  : TJSONValue        ;
  ContentsVal: TJSONValue        ;
begin
  Result:= '';
  try
    Client:= EnsureLspClient;
    if Client = nil then Exit;
    Params:= MakeTextDocumentPositionParams(AUri, ALine, ACol);
    try
      Resp:= Client.Request('textDocument/hover', Params, ATimeoutMs);
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
      if ContentsVal is TJSONObject then (ContentsVal as TJSONObject).TryGetValue<string>('value', Result)
      else if ContentsVal is TJSONString then Result:= (ContentsVal as TJSONString).Value;
    finally
      Resp.Free;
    end;
  except
    { Silent -- fires from dwell timer; AVs here would break IDE }
    Result:= '';
  end; // try
end; // function

{ v0.40.7: forward decls so FetchHoverCallers / InvokeHover compose can call
  helpers defined later in this unit. RunAndCaptureStdout is now declared in the
  interface (v0.88: exposed for the Structure form's AutoFix menu), so its
  implementation-section forward is no longer needed -- the interface decl serves
  as the forward for ordering. }
function IdentifierAtCursor: string; forward;
{ v0.64.1: forward so all heavy-command handlers above can call DLExe64
  before its implementation appears later in this unit. }
function DLExe64: string; forward;
{ Same reason: InvokeRename (and every other handler declared before the
  implementation below) resolves its DB through ResolvePrimaryIndexDb. }
function ResolvePrimaryIndexDb: string; forward;
{ Same reason: InvokeFormatProjectYadf opens its job report with DLOpenInEditor,
  and UnsavedProjectUnits reads editor buffers with ReadSourceEditorText; both
  implementations appear further down. }
procedure DLOpenInEditor(const AFilePath: string); forward;
function ReadSourceEditorText(const ASrc: IOTASourceEditor): string; forward;

function SliceJsonBracket(const AText: string; AOpen, AClose: Char): string;
// v0.94.1: extract the first balanced AOpen..AClose region from AText, ignoring
// anything before/after. RunAndCaptureStdout merges the CLI's stderr banners in
// with the JSON, and Delphi's TJSONObject.ParseJSONValue is a STRICT parser that
// returns nil on any trailing non-JSON. Walking the brackets (string-aware, so a
// bracket inside a "quoted string" is ignored) yields just the JSON to parse.
// Returns empty when no balanced region is found. Pass the object or array
// delimiters as AOpen/AClose.
var
  Start, Depth, i: Integer;
  InStr, Esc     : Boolean;
  Ch             : Char   ;
begin
  Result:= '';
  Start:= Pos(AOpen, AText);
  if Start = 0 then Exit;
  Depth:= 0; InStr:= False; Esc:= False;
  for i:= Start to Length(AText) do
  begin
    Ch:= AText[i];
    if Esc then
      Esc:= False
    else if InStr then
    begin
      if Ch = #92 then Esc:= True          { #92 = backslash: escapes the next char }
      else if Ch = '"' then InStr:= False;
    end
    else if Ch = '"' then InStr:= True
    else if Ch = AOpen then Inc(Depth)
    else if Ch = AClose then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(Copy(AText, Start, i - Start + 1));
    end;
  end;
end;

function FetchHoverCallers(const AExe, AQName: string; const ADbList: TArray<string>): TArray<TDragLintCallerInfo>;
// v(hover-callers fix v2): show the real USE SITES of the SPECIFIC symbol, fast.
// The old `find-callers --name <bare>` had two problems: (1) it name-matched
// EVERY same-named routine (every `Create`) -> 200+ callers of UNRELATED symbols;
// (2) it scanned the huge library index by name -> ~20 s freeze on the main
// thread. The resolved call_edges (reverse-calltree) are too lossy here -- they
// miss qualified-constructor call sites and mis-resolve generic
// `TFoo<T>.Create` -- so we stay on the NAME index but:
//   * DROP the library DBs from the search (callers of project code live in the
//     project; this is what makes it fast -- ~0.5 s vs ~20 s);
//   * keep only rows whose source line is qualified by the target's OWN class
//     ("TGroup.Create"), which drops the other-class Creates AND the mis-resolved
//     TObjectList<TGroup>.Create;
//   * de-duplicate by (file,line) -- a call site emits 2 refs (call + member).
// Falls back to the unfiltered project rows when the class-qualified filter finds
// nothing (a free function, or instance-variable calls), so it never hides all.
var
  CmdLine  : string             ;
  Output   : string             ;
  DbArgs   : string             ;
  ExitCode : Integer            ;
  i        : Integer            ;
  JV       : TJSONValue         ;
  JArr     : TJSONArray         ;
  JItem    : TJSONObject        ;
  Info     : TDragLintCallerInfo;
  Ctx      : string             ;
  CtxLines : TArray<string>     ;
  L        : string             ;
  LineNumStr: string            ;
  Trimmed  : string             ;
  BareName : string             ;
  ClassQual: string             ;
  Head     : string             ;
  DotP     : Integer            ;
  ProjDbs  : TArray<string>     ;
  Raw      : TArray<TDragLintCallerInfo>;
  Filtered : TArray<TDragLintCallerInfo>;
  function AlreadyHave(const AArr: TArray<TDragLintCallerInfo>; const AItem: TDragLintCallerInfo): Boolean;
  var k: Integer;
  begin
    Result:= False;
    for k:= 0 to High(AArr) do
      if (AArr[k].Line = AItem.Line) and SameText(AArr[k].FilePath, AItem.FilePath) then Exit(True);
  end;
begin
  SetLength(Result, 0);
  if (AExe = '') or not FileExists(AExe) then Exit;
  if Trim(AQName) = '' then Exit;

  // bare last segment for --name; "Class.Method" (last two segments) for the
  // qualified-context filter.
  BareName:= AQName;
  DotP:= LastDelimiter('.', BareName);
  if DotP > 0 then BareName:= Copy(BareName, DotP + 1, MaxInt);
  ClassQual:= AQName;
  if DotP > 1 then
  begin
    Head:= Copy(AQName, 1, DotP - 1);
    var Dot2: Integer:= LastDelimiter('.', Head);
    if Dot2 > 0 then ClassQual:= Copy(AQName, Dot2 + 1, MaxInt);
  end;

  // project-only DB list (exclude library-*): the library scan is the freeze,
  // and project symbols are not called from the library. Keep the library DBs
  // only if there is nothing else (a pure-library hover).
  SetLength(ProjDbs, 0);
  for i:= 0 to High(ADbList) do
    if Pos('library-', LowerCase(ExtractFileName(ADbList[i]))) = 0 then
    begin SetLength(ProjDbs, Length(ProjDbs) + 1); ProjDbs[High(ProjDbs)]:= ADbList[i]; end;
  if Length(ProjDbs) = 0 then ProjDbs:= ADbList;

  DbArgs:= '';
  for i:= 0 to High(ProjDbs) do DbArgs:= DbArgs + Format(' --db "%s"', [ProjDbs[i]]);

  CmdLine:= Format('"%s" query find-callers --name "%s"%s --json --context 1', [AExe, BareName, DbArgs]);

  ExitCode:= RunAndCaptureStdout(CmdLine, Output, 8000);
  if (ExitCode <> 0) or (Trim(Output) = '') then Exit;

  // Slice the balanced [...] array first (RunAndCaptureStdout appends stderr
  // banners after the JSON, which would break the strict parser).
  Output:= SliceJsonBracket(Output, '[', ']');
  if Output = '' then Exit;

  JV:= nil;
  try
    JV:= TJSONObject.ParseJSONValue(Output);
  except
    JV:= nil;
  end;
  if (JV = nil) or not (JV is TJSONArray) then
  begin
    if JV <> nil then JV.Free;
    Exit;
  end;

  try
    JArr:= JV as TJSONArray;
    SetLength(Raw, 0);
    for i:= 0 to JArr.Count - 1 do
    begin
      if not (JArr.Items[i] is TJSONObject) then Continue;
      JItem:= JArr.Items[i] as TJSONObject;
      Info.FilePath:= JItem.GetValue<string> ('file_path' , '');
      Info.Line    := JItem.GetValue<Integer>('start_line', 0 );
      Ctx:= JItem.GetValue<string>('context', '');
      Info.CodeText:= '';
      LineNumStr:= IntToStr(Info.Line) + ':';
      CtxLines:= Ctx.Split([#10]);
      for L in CtxLines do
      begin
        Trimmed:= Trim(L);
        if Pos(LineNumStr, Trimmed) = 1 then
        begin
          Info.CodeText:= Trim(Copy(Trimmed, Length(LineNumStr) + 1, MaxInt));
          Break;
        end;
      end;
      if Info.FilePath = '' then Continue;
      SetLength(Raw, Length(Raw) + 1);
      Raw[High(Raw)]:= Info;
    end; // for
  finally
    JV.Free;
  end; // try

  // Keep only rows whose source line is qualified by the target's own class
  // (e.g. "TGroup.Create"), de-duplicated by (file,line). Fall back to the
  // unfiltered rows if that finds nothing (free function / instance-var calls).
  SetLength(Filtered, 0);
  for i:= 0 to High(Raw) do
    if (Pos(ClassQual, Raw[i].CodeText) > 0) and not AlreadyHave(Filtered, Raw[i]) then
    begin SetLength(Filtered, Length(Filtered) + 1); Filtered[High(Filtered)]:= Raw[i]; end;
  if Length(Filtered) = 0 then
    for i:= 0 to High(Raw) do
      if not AlreadyHave(Filtered, Raw[i]) then
      begin SetLength(Filtered, Length(Filtered) + 1); Filtered[High(Filtered)]:= Raw[i]; end;

  if Length(Filtered) > 200 then SetLength(Filtered, 200);
  Result:= Filtered;
end; // function

function ExtractHoverHeader(const AMarkdown: string): string;
{ Extract a single-line summary mirroring Delphi's own Code Insight popup:
    "<kind>   <name>   -   <unit>.pas (<line>)"
  Source: LSP hover markdown's first line "**name** `kind`" gives kind+name;
  the first subsequent "`<qname>` - line N" gives the unit and line. The
  unit is everything in the qname except the last 1-2 dotted segments
  (member, optionally class/record). Pas extension is appended. }
var
  Lines    : TArray<string>;
  L        : string        ;
  FirstLine: string        ;
  Name     : string        ;
  Kind     : string        ;
  Qname    : string        ;
  LineStr  : string        ;
  UnitName : string        ;
  P1       : Integer       ;
  P2       : Integer       ;
  P3       : Integer       ;
  DashAt   : Integer       ;
  i        : Integer       ;
  DotCount : Integer       ;
begin
  Result:= '';
  if Trim(AMarkdown) = '' then Exit;
  Lines:= AMarkdown.Split([#13, #10], TStringSplitOptions.ExcludeEmpty);
  if Length(Lines) = 0 then Exit;

  { Parse "**name** `kind`" header line. }
  FirstLine:= Trim(Lines[0]);
  if (Length(FirstLine) >= 4) and (Copy(FirstLine, 1, 2) = '**') then
  begin
    P1:= Pos('**', Copy(FirstLine, 3, MaxInt));
    if P1 > 0 then
    begin
      Name:= Copy(FirstLine, 3, P1 - 1);
      L:= Trim(Copy(FirstLine, P1 + 4, MaxInt));
      if (L <> '') and (L[1] = '`') then
      begin
        P2:= Pos('`', Copy(L, 2, MaxInt));
        if P2 > 0 then Kind:= Copy(L, 2, P2 - 1);
      end;
    end;
  end
  else
  begin
    Result:= FirstLine;
    Exit;
  end;

  { Walk subsequent lines for first "`qname` - line N" entry. }
  Qname  := '';
  LineStr:= '';
  for i:= 1 to High(Lines) do
  begin
    L:= Trim(Lines[i]);
    { Optional bullet "- " prefix. }
    if (Length(L) >= 2) and (Copy(L, 1, 2) = '- ') then L:= Trim(Copy(L, 3, MaxInt));
    if (L = '') or (L[1] <> '`') then Continue;
    P1:= Pos('`', Copy(L, 2, MaxInt));
    if P1 <= 0 then Continue;
    Qname:= Copy(L, 2, P1 - 1);
    L:= Trim(Copy(L, P1 + 2, MaxInt));
    DashAt:= Pos('line ', L);
    if DashAt > 0 then LineStr:= Trim(Copy(L, DashAt + 5, MaxInt));
    Break;
  end;

  { Derive unit name from qname: drop the last 1-2 dotted segments. If the
    last-but-one starts with T/I/E and has another segment after it, that's
    a class/interface so drop two. Otherwise drop one. }
  UnitName:= '';
  if Qname <> '' then
  begin
    DotCount:= 0;
    for i:= 1 to Length(Qname) do
      if Qname[i] = '.' then Inc(DotCount);
    UnitName:= Qname;
    if DotCount >= 2 then
    begin
      P2:= 0;
      for i:= Length(UnitName) downto 1 do
        if UnitName[i] = '.' then
        begin
          P2:= i;
          Break;
        end;
      { Check the segment immediately before P2 starts with T/I/E (class kind). }
      P3:= 0;
      for i:= P2 - 1 downto 1 do
        if UnitName[i] = '.' then
        begin
          P3:= i;
          Break;
        end;
      if (P3 > 0) and (P3 + 1 <= Length(UnitName)) and (CharInSet(UnitName[P3 + 1], ['T','I','E'])) then UnitName:= Copy(UnitName, 1, P3 - 1)
      else UnitName:= Copy(UnitName, 1, P2 - 1);
    end // if
    else if DotCount = 1 then
    begin
      P2:= Pos('.', UnitName);
      UnitName:= Copy(UnitName, 1, P2 - 1);
    end;
  end; // if

  { Compose the header. }
  Result:= '';
  if Kind <> '' then Result:= Kind + '   ';
  Result:= Result + Name;
  if UnitName <> '' then
  begin
    Result:= Result + '   --   ' + UnitName + '.pas';
    if LineStr <> '' then Result:= Result + ' (' + LineStr + ')';
  end;
end; // function

function StripFirstHeaderLine(const AMarkdown: string): string;
{ Drop the first "**name** `kind`" line so the body memo doesn't duplicate
  what's already on the header label. Keep the blank separator line so
  the definitions list reads naturally. }
var
  Lines   : TArray<string>;
  SB      : TStringBuilder;
  StartIdx: Integer       ;
  i       : Integer       ;
begin
  Result:= AMarkdown;
  if Trim(AMarkdown) = '' then Exit;
  Lines:= AMarkdown.Split([#10]);
  if (Length(Lines) = 0) then Exit;
  if Trim(Lines[0]).StartsWith('**') then StartIdx:= 1
  else Exit;
  SB:= TStringBuilder.Create;
  try
    for i:= StartIdx to High(Lines) do
    begin
      SB.Append(Lines[i]);
      if i < High(Lines) then SB.Append(#10);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

function ExtractHoverQname(const AMarkdown: string): string;
{ v0.95 (Task 8): pull the FIRST fully-qualified name out of the LSP hover
  markdown -- the "`<qname>` - line N" body entry that ExtractHoverHeader also
  parses. This qname is exactly what the index stored, so it is the correct
  argument for `hover --qname` (whose CLI resolver matches qualified_name
  EXACTLY -- a bare IdentifierAtCursor name will NOT resolve). Returns '' when
  the markdown carries no such entry (e.g. a plain string hover), so the caller
  falls back to the legacy string popup.
  Task 9 (final-review fix): a DOCUMENTED symbol's markdown opens with a
  "# <QualifiedName>" H1 heading (RenderHoverMarkdown, no leading backtick)
  instead of the "**name** `kind`" header used for undocumented symbols. If
  present, that heading line already IS the full qname -- use it directly, so
  the backtick-line scan below (which would otherwise land on the first
  parameter bullet) is only reached as the undocumented-symbol fallback. }
var
  Lines: TArray<string>;
  L    : string        ;
  P1   : Integer       ;
  i    : Integer       ;
begin
  Result:= '';
  if Trim(AMarkdown) = '' then Exit;
  Lines:= AMarkdown.Split([#13, #10], TStringSplitOptions.ExcludeEmpty);
  for i:= 0 to High(Lines) do
  begin
    L:= Trim(Lines[i]);
    if (Length(L) >= 2) and (Copy(L, 1, 2) = '# ') then
    begin
      Result:= Trim(Copy(L, 3, MaxInt));
      Exit;
    end;
  end;
  { The header line 0 is "**name** `kind`"; the qname lives on a later
    "`<qname>` - line N" line (optionally prefixed by a "- " bullet). }
  for i:= 0 to High(Lines) do
  begin
    L:= Trim(Lines[i]);
    if (Length(L) >= 2) and (Copy(L, 1, 2) = '- ') then L:= Trim(Copy(L, 3, MaxInt));
    if (L = '') or (L[1] <> '`') then Continue;
    P1:= Pos('`', Copy(L, 2, MaxInt));
    if P1 <= 0 then Continue;
    Result:= Copy(L, 2, P1 - 1);
    Exit;
  end;
end; // function

function BuildHoverSignature(const AModel: TDragLintHoverModel): string;
{ v0.95 (Task 8): the `hover --json` payload carries the parts (qname, params,
  return_type) but NOT a flat signature string, while the form's RenderModel /
  EmitSignatureHeader render AModel.Signature. Reconstruct a one-line display
  signature "qname(mod name: type; ...): rettype" from the parts so the header
  is never blank. Procedures (empty ReturnType) omit the ": rettype" tail. }
var
  SB: TStringBuilder     ;
  i : Integer            ;
  P : TDragLintHoverParam;
begin
  SB:= TStringBuilder.Create;
  try
    { FB #3: lead with the friendly kind qualifier (function/local var/property/
      ...) so the header reads e.g. "function Unit.Foo(...)". EmitSignatureHeader
      colors the keyword automatically. Omitted when the CLI supplied no kind. }
    if AModel.Kind <> '' then SB.Append(AModel.Kind).Append(' ');
    SB.Append(AModel.QualifiedName);
    if Length(AModel.Params) > 0 then
    begin
      SB.Append('(');
      for i:= 0 to High(AModel.Params) do
      begin
        P:= AModel.Params[i];
        if i > 0 then SB.Append('; ');
        if P.Modifier <> '' then SB.Append(P.Modifier).Append(' ');
        SB.Append(P.Name);
        if P.TypeText <> '' then SB.Append(': ').Append(P.TypeText);
      end;
      SB.Append(')');
    end;
    if AModel.ReturnType <> '' then SB.Append(': ').Append(AModel.ReturnType);
    { v(enum-value): show the ordinal like the IDE ("... ptObject = 128"). The
      CLI puts the value in the raw signature for enum-value symbols. }
    if (AModel.Kind = 'enum value') and (AModel.RawSignature <> '') then SB.Append(' = ').Append(AModel.RawSignature);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

/// <summary>Runs `"&lt;exe&gt;" hover --qname "&lt;qname&gt;" &lt;--db ...&gt; --format json`,
/// captures stdout, and parses the structured Help-Insight model (qname, unit,
/// def_line, params[], return_type, returns[], returns_more) into AModel. Also
/// reconstructs AModel.Signature from the parts (the CLI json omits it) so the
/// form's RenderModel header is never blank.</summary>
/// <param name="AExe">Full path to drag-lint.exe; must exist.</param>
/// <param name="AQName">The FULLY-QUALIFIED name to look up (the CLI matches
/// qualified_name exactly -- a bare identifier will not resolve).</param>
/// <param name="ADbList">Index DBs to search, passed as repeated --db flags.</param>
/// <param name="AModel">Receives the parsed model on success.</param>
/// <returns>True when the model was fetched + parsed; False (AModel left
/// zeroed) on any failure -- missing exe, empty qname, non-zero exit, empty or
/// non-object output, or a JSON parse error -- so the caller falls back to the
/// legacy string hover path.</returns>
/// <remarks>Mirrors FetchHoverCallers' spawn+parse plumbing; guarded end to end
/// so a hover can never surface an exception. Main thread only (spawns a child
/// synchronously with a short timeout).</remarks>
function FetchHoverModel(const AExe, AQName: string; const ADbList: TArray<string>; out AModel: TDragLintHoverModel): Boolean;
var
  CmdLine : string           ;
  Output  : string           ;
  DbArgs  : string           ;
  ExitCode: Integer          ;
  i       : Integer          ;
  JV      : TJSONValue       ;
  JObj    : TJSONObject      ;
  JParams : TJSONArray       ;
  JReturns: TJSONArray       ;
  JFacts  : TJSONArray       ;
  PItem   : TJSONObject      ;
  Param   : TDragLintHoverParam;
  RetStr  : string           ;
begin
  Result:= False;
  { Zero the out-param so a False return leaves a clean, empty model. }
  AModel:= Default(TDragLintHoverModel);
  if (AExe = '') or not FileExists(AExe) then Exit;
  if Trim(AQName) = '' then Exit;

  DbArgs:= '';
  for i:= 0 to High(ADbList) do DbArgs:= DbArgs + Format(' --db "%s"', [ADbList[i]]);

  CmdLine:= Format('"%s" hover --qname "%s"%s --format json', [AExe, AQName, DbArgs]);

  ExitCode:= RunAndCaptureStdout(CmdLine, Output, 5000);
  { Guard: non-zero exit (e.g. "No symbol matched qname" -> exit 1) or empty
    output falls back to the string path. }
  if (ExitCode <> 0) or (Trim(Output) = '') then Exit;

  // v0.94.1 BUGFIX: RunAndCaptureStdout merges the CLI's stderr banners into
  // Output around the JSON; TJSONObject.ParseJSONValue is strict and returns nil
  // on trailing non-JSON, so the structured view fell back to the string popup
  // for EVERY symbol. Slice the balanced {...} object (shared helper) first.
  Output:= SliceJsonBracket(Output, '{', '}');
  if Output = '' then Exit;

  JV:= nil;
  try
    JV:= TJSONObject.ParseJSONValue(Output);
  except
    on E: Exception do JV:= nil;
  end;
  if (JV = nil) or not (JV is TJSONObject) then
  begin
    if JV <> nil then JV.Free;
    Exit;
  end;

  try
    JObj:= JV as TJSONObject;
    AModel.QualifiedName:= JObj.GetValue<string> ('qname'      , '');
    AModel.Kind         := JObj.GetValue<string> ('kind'       , '');   // FB #3
    AModel.RawSignature := JObj.GetValue<string> ('signature'  , '');   // enum-value ordinal etc.
    AModel.UnitFile     := JObj.GetValue<string> ('unit'       , '');
    AModel.DefLine      := JObj.GetValue<Integer>('def_line'   , 0 );
    AModel.ReturnType   := JObj.GetValue<string> ('return_type', '');
    AModel.ReturnsMore  := JObj.GetValue<Integer>('returns_more', 0);

    { params: array of param objects (modifier, name, type). }
    SetLength(AModel.Params, 0);
    if JObj.TryGetValue<TJSONArray>('params', JParams) then
    begin
      SetLength(AModel.Params, JParams.Count);
      for i:= 0 to JParams.Count - 1 do
      begin
        Param.Modifier:= '';
        Param.Name    := '';
        Param.TypeText:= '';
        if JParams.Items[i] is TJSONObject then
        begin
          PItem:= JParams.Items[i] as TJSONObject;
          Param.Modifier:= PItem.GetValue<string>('modifier', '');
          Param.Name    := PItem.GetValue<string>('name'    , '');
          Param.TypeText:= PItem.GetValue<string>('type'    , '');
        end;
        AModel.Params[i]:= Param;
      end;
    end;

    { returns: array of expression strings. }
    SetLength(AModel.Returns, 0);
    if JObj.TryGetValue<TJSONArray>('returns', JReturns) then
    begin
      SetLength(AModel.Returns, JReturns.Count);
      for i:= 0 to JReturns.Count - 1 do
      begin
        RetStr:= '';
        if JReturns.Items[i] is TJSONString then RetStr:= (JReturns.Items[i] as TJSONString).Value
        else RetStr:= JReturns.Items[i].Value;
        AModel.Returns[i]:= RetStr;
      end;
    end;

    { FB3: returns_lines -- parallel array of absolute source lines (0 = unknown),
      so the popup can jump to each return value's line. Zipped by index with
      Returns; entries beyond its length default to 0. }
    SetLength(AModel.ReturnLines, Length(AModel.Returns));
    var JReturnLines: TJSONArray;
    if JObj.TryGetValue<TJSONArray>('returns_lines', JReturnLines) then
      for i:= 0 to High(AModel.Returns) do
        if i < JReturnLines.Count then
          AModel.ReturnLines[i]:= StrToIntDef(JReturnLines.Items[i].Value, 0);

    { v(hover facts fix): the Phase-2 analysis fact lines (Complexity / Reads /
      Writes / SQL / Handles / Owns returned / Covered by) -- one string each,
      rendered as a FACTS section by RenderModel. Absent/empty on symbols with no
      facts (or an older exe whose json omits the key), which just hides the
      section. }
    SetLength(AModel.Facts, 0);
    if JObj.TryGetValue<TJSONArray>('facts', JFacts) then
    begin
      SetLength(AModel.Facts, JFacts.Count);
      for i:= 0 to JFacts.Count - 1 do
      begin
        if JFacts.Items[i] is TJSONString then AModel.Facts[i]:= (JFacts.Items[i] as TJSONString).Value
        else AModel.Facts[i]:= JFacts.Items[i].Value;
      end;
    end;

    { The json omits a flat signature; RenderModel/EmitSignatureHeader render
      AModel.Signature, so build it from the parts (else the header is blank). }
    AModel.Signature:= BuildHoverSignature(AModel);
    Result:= True;
  finally
    JV.Free;
  end; // try
end; // function

function TryBuildHoverModel(const ARawMarkdown: string; out AModel: TDragLintHoverModel; out ACallers: TArray<TDragLintCallerInfo>): Boolean;
{ v0.94.1: shared by the menu InvokeHover AND the dwell HoverTracker so a MOUSE
  hover shows the same colored structured model + Called-from grid. Mine the
  qname from the raw LSP markdown, resolve the exe + active DBs (guarded), fetch
  `hover --json`, then fetch callers by the qname's last segment. }
var
  QName  : string          ;
  ExePath: string          ;
  DbList : TArray<string>  ;
begin
  Result:= False;
  AModel:= Default(TDragLintHoverModel);
  SetLength(ACallers, 0);
  QName:= ExtractHoverQname(ARawMarkdown);
  if QName = '' then Exit;
  ExePath:= DLExe64;
  try
    DbList:= ResolveActiveIndexDbs(LoadSettings);
  except
    SetLength(DbList, 0);
  end;
  Result:= FetchHoverModel(ExePath, QName, DbList, AModel);
  if not Result then Exit;

  { Called-from: resolved callers of THIS specific symbol, by its FULL qualified
    name (not the bare last segment -- that matched every same-named routine and
    scanned the library index by name). Guarded inside FetchHoverCallers; empty
    on any miss so the grid just hides. }
  ACallers:= FetchHoverCallers(ExePath, QName, DbList);
end;

procedure InvokeHover(Sender: TObject);
var
  Client     : TDragLintLspClient         ;
  Uri        : string                     ;
  Line       : Integer                    ;
  Col        : Integer                    ;
  Params     : TJSONObject                ;
  Resp       : TJSONValue                 ;
  HoverText  : string                     ;
  RawMarkdown: string                     ;
  QName      : string                     ;
  Model      : TDragLintHoverModel        ;
  ContentsVal: TJSONValue                 ;
  P          : TPoint                     ;
  SymName    : string                     ;
  Header     : string                     ;
  Callers    : TArray<TDragLintCallerInfo>;
  Settings   : TDragLintSettings          ;
  ExePath    : string                     ;
  DbList     : TArray<string>             ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client:= EnsureLspClient;
  if Client = nil then Exit;

  Params:= MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp:= Client.Request('textDocument/hover', Params, 5000);
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
    HoverText:= '';
    var ResultVal: TJSONValue;
    if (Resp is TJSONObject) and (Resp as TJSONObject).TryGetValue<TJSONValue>('result', ResultVal) and (ResultVal is TJSONObject) and
    (ResultVal as TJSONObject).TryGetValue<TJSONValue>('contents', ContentsVal) then
    begin
      if ContentsVal is TJSONObject then (ContentsVal as TJSONObject).TryGetValue<string>('value', HoverText)
      else if ContentsVal is TJSONString then HoverText:= (ContentsVal as TJSONString).Value;
    end;

    if HoverText = '' then HoverText:= '(no hover info: ' + Resp.Format(2) + ')';

    { v0.95 (Task 8): keep the RAW markdown (before StripFirstHeaderLine mutates
      HoverText below) so we can mine the fully-qualified name for hover --json. }
    RawMarkdown:= HoverText;

    { v0.40.5: dump every hover invocation to the debug log + copy the
      rendered text to the clipboard so users can paste it back when the
      popup is too transient to screenshot. Logging happens BEFORE the
      popup shows; clipboard is set unconditionally so even a Hover that
      immediately closes leaves the text behind. }
    try
      Vcl.Clipbrd.Clipboard.AsText:= HoverText;
    except
      { clipboard update failure -- silently ignore }
    end;

    { v0.40.7: compose the three-section popup.
      v0.40.8c: header includes unit.pas (line); body drops the dup'd first line. }
    Header   := ExtractHoverHeader  (HoverText);
    HoverText:= StripFirstHeaderLine(HoverText);
    SymName := IdentifierAtCursor;
    Settings:= LoadSettings;
    ExePath:= DLExe64;
    try
      DbList:= ResolveActiveIndexDbs(Settings);
    except
      SetLength(DbList, 0);
    end;
    Callers:= FetchHoverCallers(ExePath, SymName, DbList);
    DLT('hover', Format('sym="%s" dbs=%d callers=%d hdr="%s" bodyLen=%d', [SymName, Length(DbList), Length(Callers), Header, Length(HoverText)]));

    { v0.40.6: menu invocation is explicit -- replace any current popup. }
    CloseDragLintHover;
    GetCursorPos(P);

    { v0.95 (Task 8): PREFER the structured Help-Insight popup. Mine the
      fully-qualified name from the raw LSP markdown, then fetch the structured
      `hover --json` model. On success show the colored signature + Parameters +
      Returns view; on ANY miss (no qname parsed, exe missing, non-zero exit,
      unparseable output) fall back to the EXACT legacy string popup below so
      the manual hover always shows something. }
    QName:= ExtractHoverQname(RawMarkdown);
    if (QName <> '') and FetchHoverModel(ExePath, QName, DbList, Model) then
    begin
      DLT('hover', Format('structured qname="%s" params=%d returns=%d ret="%s"', [Model.QualifiedName, Length(Model.Params), Length(Model.Returns), Model.ReturnType]));
      ShowDragLintHover(Model, Callers, P.X, P.Y + 20);
    end
    else
    begin
      DLT('hover', Format('string-fallback qname="%s"', [QName]));
      ShowDragLintHover(Header, HoverText, Callers, P.X, P.Y + 20);
    end;
  finally
    Resp.Free;
  end; // try
end; // procedure

{ v0.46: ASilent = auto-trigger (typed '.') -- suppress every dialog and only
  pop the list when there are items, with a short timeout so a slow/stuck engine
  never blocks typing. ASilent = False = manual invoke (menu/shortcut), keeps the
  informative dialogs. }
procedure DoCompletion(ASilent: Boolean);
var
  Client : TDragLintLspClient;
  Uri    : string            ;
  Line   : Integer           ;
  Col    : Integer           ;
  Params : TJSONObject       ;
  Resp   : TJSONValue        ;
  RespObj: TJSONObject       ;
  Items  : TJSONArray        ;
  ResultV: TJSONValue        ;
  P      : TPoint            ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    if not ASilent then ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client:= EnsureLspClient;
  if Client = nil then Exit;

  Params:= MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp:= Client.Request('textDocument/completion', Params, (if ASilent then 1200 else 5000));
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    if not ASilent then ShowMessage('drag-lint completion: request timed out or no result.');
    Exit;
  end;
  try
    Items:= nil;

    // Shape 1: top-level array
    // Shape 2: { items:[...] } or { result:{ items:[...] } }
    if Resp is TJSONArray then Items:= Resp as TJSONArray
    else if Resp is TJSONObject then
    begin
      RespObj:= Resp as TJSONObject;
      if not RespObj.TryGetValue<TJSONArray>('items', Items) then
      begin
        if RespObj.TryGetValue<TJSONValue>('result', ResultV) then
        begin
          if ResultV is TJSONArray then Items:= ResultV as TJSONArray
          else if ResultV is TJSONObject then (ResultV as TJSONObject).TryGetValue<TJSONArray>('items', Items);
        end;
      end;
    end;

    if Items = nil then
    begin
      DLT('completion', Format('silent=%s -> NO items array', [BoolToStr(ASilent, True)]));
      if not ASilent then ShowMessage('drag-lint completion:'#13#10 + Resp.Format(2));
      Exit;
    end;
    DLT('completion', Format('silent=%s -> %d item(s)', [BoolToStr(ASilent, True), Items.Count]));
    { auto-trigger: never pop an empty list. }
    if ASilent and (Items.Count = 0) then Exit;

    GetCursorPos(P);
    ShowDragLintCompletion(
      Items, P.X, P.Y + 20,
      procedure(const ATxt: string) var ESS: IOTAEditorServices; EV: IOTAEditView; EW: IOTAEditWriter; begin if not Supports(BorlandIDEServices, IOTAEditorServices,
          ESS) then Exit; EV:= ESS.TopView; if EV = nil then Exit; EW:= EV.Buffer.CreateUndoableWriter; EW.Insert(PAnsiChar(AnsiString(ATxt))); end
    );
  finally
    Resp.Free;
  end; // try
end; // procedure

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
  Client     : TDragLintLspClient;
  Uri        : string            ;
  Line       : Integer           ;
  Col        : Integer           ;
  Params     : TJSONObject       ;
  Resp       : TJSONValue        ;
  RespObj    : TJSONObject       ;
  SigsArr    : TJSONArray        ;
  ActiveSig  : Integer           ;
  ActiveParam: Integer           ;
  SigObj     : TJSONObject       ;
  SigLabel   : string            ;
  P          : TPoint            ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client:= EnsureLspClient;
  if Client = nil then Exit;

  Params:= MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp:= Client.Request('textDocument/signatureHelp', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint signatureHelp: request timed out or no result.');
    Exit;
  end;
  try
    SigLabel   := '';
    ActiveParam:= 0;

    if Resp is TJSONObject then
    begin
      RespObj:= Resp as TJSONObject;
      ActiveSig:= 0;
      RespObj.TryGetValue<Integer>('activeSignature', ActiveSig  );
      RespObj.TryGetValue<Integer>('activeParameter', ActiveParam);

      if RespObj.TryGetValue<TJSONArray>('signatures', SigsArr) and (SigsArr.Count > 0) then
      begin
        if ActiveSig >= SigsArr.Count then ActiveSig:= 0;
        if SigsArr.Items[ActiveSig] is TJSONObject then
        begin
          SigObj:= SigsArr.Items[ActiveSig] as TJSONObject;
          SigObj.TryGetValue<string>('label', SigLabel);
          { Per-signature activeParameter overrides the top-level one }
          SigObj.TryGetValue<Integer>('activeParameter', ActiveParam);
        end;
      end;
    end; // if

    if SigLabel = '' then
    begin
      ShowMessage('drag-lint signatureHelp:'#13#10 + Resp.Format(2));
      Exit;
    end;

    GetCursorPos(P);
    ShowDragLintSignature(SigLabel, ActiveParam, P.X, P.Y + 20);
  finally
    Resp.Free;
  end; // try
end; // procedure

procedure InvokeDiagnostics(Sender: TObject);
var
  Client : TDragLintLspClient;
  Uri    : string            ;
  Line   : Integer           ;
  Col    : Integer           ;
  Params : TJSONObject       ;
  TextDoc: TJSONObject       ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client:= EnsureLspClient;
  if Client = nil then Exit;

  { textDocument/didSave triggers publishDiagnostics notification }
  Params := TJSONObject.Create;
  TextDoc:= TJSONObject.Create;
  TextDoc.AddPair('uri'         , Uri    );
  Params .AddPair('textDocument', TextDoc);
  try
    Client.Notify('textDocument/didSave', Params);
  finally
    Params.Free;
  end;

  ShowMessage( 'drag-lint: diagnostics requested for'#13#10 + Uri + #13#10 + 'Results will appear in the Messages pane.');
end; // procedure

procedure TriggerDiagnosticsOnSave(const AFile: string);
{ v0.42: hook installed into SaveNotifier.GAfterSaveDiagHook. Republishes
  diagnostics for a just-saved .pas by sending textDocument/didSave to the
  RUNNING LSP (the server replies with publishDiagnostics -> HandleNotification
  -> cache -> markers). We never force-start the LSP here -- if it isn't up yet
  we silently skip, so the save path is never blocked by a slow LSP init. }
var
  Params : TJSONObject;
  TextDoc: TJSONObject;
  Uri    : string     ;
begin
  if GLspClient = nil then Exit;
  if (AFile = '') or not SameText(ExtractFileExt(AFile), '.pas') then Exit;
  Uri:= 'file:///' + StringReplace(AFile, '\', '/', [rfReplaceAll]);
  Params := TJSONObject.Create;
  TextDoc:= TJSONObject.Create;
  TextDoc.AddPair('uri'         , Uri    );
  Params .AddPair('textDocument', TextDoc);
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
function RunAndCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer = 60000): Integer;
var
  SA          : TSecurityAttributes       ;
  ReadPipe    : THandle                   ;
  WritePipe   : THandle                   ;
  SI          : TStartupInfoW             ;
  PI          : TProcessInformation       ;
  Buf         : array[0..4095] of AnsiChar;
  BytesRead   : DWORD                     ;
  ExitCode    : DWORD                     ;
  WideCmd     : string                    ;
  SB          : TStringBuilder            ;
  TimeoutValue: DWORD                     ;
begin
  Result:= -1;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput:= GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB:= TStringBuilder.Create;
    try
      repeat
        BytesRead:= 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead]:= #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then TimeoutValue:= INFINITE
    else TimeoutValue:= DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TimeoutValue);
    GetExitCodeProcess (PI.hProcess, ExitCode    );
    Result:= Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    CloseHandle(ReadPipe);
  end; // try
end; // function

{ ---- helpers to resolve project db path and active project file ---- }

// Returns the active project file path (.dproj), or '' if not available.
function GetActiveProjectFile: string;
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
begin
  Result:= '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  if MS = nil then Exit;
  ProjGroup:= MS.MainProjectGroup;
  if ProjGroup = nil then Exit;
  ActiveProj:= ProjGroup.ActiveProject;
  if ActiveProj = nil then Exit;
  Result:= ActiveProj.FileName;
end;

// Returns the database path for the active project: same dir as .dproj with
// name <ProjectName>.sqlite.  Falls back to '' when no project is open.
function GetActiveProjectDb: string;
var
  ProjFile: string;
begin
  ProjFile:= GetActiveProjectFile;
  if ProjFile = '' then Result:= ''
  else Result:= ChangeFileExt(ProjFile, '.sqlite');
end;

{ v0.47: the active project's platform (Win32/Win64). ghost-check needs it to
  locate the unit's .dcu to delete (to force a recompile). Defaults to Win64. }
function GetActiveProjectPlatform: string;
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
begin
  Result:= 'Win64';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    ProjGroup:= MS.MainProjectGroup;
    if ProjGroup = nil then Exit;
    ActiveProj:= ProjGroup.ActiveProject;
    if ActiveProj = nil then Exit;
    var P: string:= ActiveProj.CurrentPlatform;
    if P <> '' then Result:= P;
  except
  end;
end;

procedure InvokeRename(Sender: TObject);
var
  Uri    : string ;
  Line   : Integer;
  Col    : Integer;
  ProjDb : string ;
  ExePath: string ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;

  { Resolve project DB and exe path }
  ProjDb:= ResolvePrimaryIndexDb;
  ExePath:= DLExe64;

  { Open the refactor preview form.
    For v0.27 simplicity the qname field starts empty; the user fills it in.
    Future v0.28+ can extract the identifier at cursor via TTypeAtResolver. }
  ShowRefactorDialog('', ProjDb, ExePath);
end; // procedure

procedure InvokeFormatYadf(Sender: TObject);
var
  ESS     : IOTAEditorServices;
  EditView: IOTAEditView      ;
  FilePath: string            ;
  ExePath : string            ;
  CmdLine : string            ;
  Output  : string            ;
  ExitCode: Integer           ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    ShowMessage('drag-lint: no editor services available');
    Exit;
  end;
  EditView:= ESS.TopView;
  if EditView = nil then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;
  FilePath:= EditView.Buffer.FileName;
  if FilePath = '' then
  begin
    ShowMessage('drag-lint: active buffer has no file name');
    Exit;
  end;

  { Resolve drag-lint.exe }
  ExePath:= DLExe64;

  { For v0.27: do not auto-save; spawn YADF against the current on-disk file.
    The user should save the file before invoking this command. }
  CmdLine:= Format('"%s" format "%s"', [ExePath, FilePath]);
  ExitCode:= RunAndCaptureStdout(CmdLine, Output, 60000);

  if ExitCode = 2 then
  begin
    ShowMessage( 'drag-lint: failed to spawn format command.'#13#10 + 'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  { The IDE will auto-detect the file change on next focus switch. }
  ShowMessage( Format('drag-lint Format with YADF:'#13#10 + '%s', [Trim(Output)]));
end; // procedure

/// <summary>The active project's `.pas` members that exist on disk.</summary>
/// <param name="AUnits">Absolute paths, project-member order; [] when False.</param>
/// <returns>False when there is no active project or it has no .pas member.</returns>
/// <remarks>Project MEMBERS, not the project folder: a loose unit sitting beside
/// the .dproj is deliberately not reformatted, because nothing in the project
/// compiles it and the user may be keeping it as scratch.</remarks>
function ActiveProjectUnits(out AUnits: TArray<string>): Boolean;
var
  MS  : IOTAModuleServices;
  PG  : IOTAProjectGroup  ;
  Proj: IOTAProject       ;
  i   : Integer           ;
  FN  : string            ;
  L   : TList<string>     ;
begin
  Result:= False;
  SetLength(AUnits, 0);
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  if MS = nil then Exit;
  PG:= MS.MainProjectGroup;
  if PG = nil then Exit;
  Proj:= PG.ActiveProject;
  if Proj = nil then Exit;

  L:= TList<string>.Create;
  try
    for i:= 0 to Proj.GetModuleCount - 1 do
    begin
      FN:= Proj.GetModule(i).FileName;
      if FN = '' then Continue;
      if not SameText(ExtractFileExt(FN), '.pas') then Continue;
      { Absolute form: UnsavedProjectUnits matches these against IOTASourceEditor
        FileNames by string, so a member returned relative would silently fail to
        match its own open editor -- and a dirty unit would be reported clean,
        which is the one failure this guard must not have. }
      try FN:= TPath.GetFullPath(FN); except Continue; end;
      if not FileExists(FN) then Continue;   // a member that was deleted on disk
      L.Add(FN);
    end;
    AUnits:= L.ToArray;
    Result:= Length(AUnits) > 0;
  finally
    L.Free;
  end;
end; // function

/// <summary>Which of AUnits have an open editor buffer that differs from
/// disk -- i.e. unsaved edits YADF would silently overwrite.</summary>
/// <param name="AUnits">Candidate paths (the project's members).</param>
/// <returns>The subset with unsaved changes, in AUnits order. [] when all clean.</returns>
/// <remarks>The test is a BYTE DIFF against the file on disk, not an IOTAModule
/// Modified flag -- that flag is not exposed on this OTA interface version. The
/// same technique, and the same reason, as CollectUnsavedOverlays above.</remarks>
/// <remarks>A member with no open editor cannot be dirty, so it is clean by
/// construction and never appears here.</remarks>
function UnsavedProjectUnits(const AUnits: TArray<string>): TArray<string>;
var
  MS       : IOTAModuleServices     ;
  M, FE    : Integer                ;
  Modu     : IOTAModule             ;
  Src      : IOTASourceEditor       ;
  Path     : string                 ;
  BufText  : string                 ;
  BufBytes : TBytes                 ;
  DiskBytes: TBytes                 ;
  Members  : TDictionary<string, Boolean>;
  Dirty    : TList<string>          ;
  U        : string                 ;
begin
  SetLength(Result, 0);
  if Length(AUnits) = 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  if MS = nil then Exit;

  Members:= TDictionary<string, Boolean>.Create;
  Dirty  := TList<string>.Create;
  try
    for U in AUnits do Members.AddOrSetValue(LowerCase(U), False);

    for M:= 0 to MS.ModuleCount - 1 do
    begin
      Modu:= MS.Modules[M];
      if Modu = nil then Continue;
      for FE:= 0 to Modu.GetModuleFileCount - 1 do
      begin
        if not Supports(Modu.GetModuleFileEditor(FE), IOTASourceEditor, Src) then Continue;
        Path:= Src.FileName;
        if Path = '' then Continue;
        try Path:= TPath.GetFullPath(Path); except Continue; end;  // match ActiveProjectUnits' form
        if not Members.ContainsKey(LowerCase(Path)) then Continue;
        BufText:= ReadSourceEditorText(Src);
        if BufText = '' then Continue;          // unreadable buffer -- assume clean
        BufBytes:= TEncoding.ANSI.GetBytes(BufText);
        try DiskBytes:= TFile.ReadAllBytes(Path); except SetLength(DiskBytes, 0); end;
        if (Length(BufBytes) = Length(DiskBytes)) and
           ((Length(BufBytes) = 0) or CompareMem(@BufBytes[0], @DiskBytes[0], Length(BufBytes))) then Continue;
        Members[LowerCase(Path)]:= True;
      end;
    end;

    { Report in AUnits order, so the message reads in project order rather than
      in whatever order the IDE happens to hold its open modules. }
    for U in AUnits do
      if Members[LowerCase(U)] then Dirty.Add(U);
    Result:= Dirty.ToArray;
  finally
    Dirty.Free;
    Members.Free;
  end;
end; // function

{ Format EVERY .pas member of the active project with YADF.

  WHY THIS REFUSES TO RUN ON UNSAVED WORK, rather than saving for the user:
  `drag-lint format` rewrites the file ON DISK, and the IDE then reloads it. An
  editor buffer holding unsaved edits would be silently discarded on that reload
  -- so a SaveAll here would quietly commit edits the user never chose to commit,
  and NOT saving would destroy them. Neither is ours to decide across a whole
  project, so the command stops and names the units. (The single-file
  InvokeFormatYadf has the same hazard and merely documents it; whole-project
  scope makes the same silent loss far larger, hence the hard stop.)

  Formatting shifts every line number in the project, so the index is stale the
  moment this finishes -- the batch therefore re-indexes at the end, for the same
  reason InvokeAutoDocumentProject's third step does, and into the DB the LSP
  actually reads. }
procedure InvokeFormatProjectYadf(Sender: TObject);
var
  Proj   : string          ;
  Db     : string          ;
  ProjDir: string          ;
  Plat   : string          ;
  Units  : TArray<string>  ;
  Unsaved: TArray<string>  ;
  Bat    : string          ;
  BatPath: string          ;
  OutPath: string          ;
  Msg    : string          ;
  i      : Integer         ;
  Shown  : Integer         ;
const
  MAX_LISTED = 15;   // a 300-unit project must not produce an unreadable dialog
begin
  Proj:= GetActiveProjectFile;
  if Proj = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;

  if not ActiveProjectUnits(Units) then
  begin
    ShowMessage('drag-lint: the active project has no .pas members to format.');
    Exit;
  end;

  Unsaved:= UnsavedProjectUnits(Units);
  if Length(Unsaved) > 0 then
  begin
    Shown:= Length(Unsaved);
    if Shown > MAX_LISTED then Shown:= MAX_LISTED;
    Msg:= Format('drag-lint: %d project unit(s) have unsaved changes.'#13#10#13#10 +
                 'YADF rewrites files on disk, so those edits would be lost when ' +
                 'the IDE reloads them.'#13#10#13#10 +
                 'Save these first, then run this command again:'#13#10#13#10,
                 [Length(Unsaved)]);
    for i:= 0 to Shown - 1 do
      Msg:= Msg + '    ' + ExtractFileName(Unsaved[i]) + #13#10;
    if Length(Unsaved) > Shown then
      Msg:= Msg + Format('    ... and %d more'#13#10, [Length(Unsaved) - Shown]);
    ShowMessage(Msg);
    Exit;
  end;

  if MessageDlg(Format('Format all %d unit(s) of %s with YADF?'#13#10#13#10 +
                       'Every file is rewritten in place. The project index is ' +
                       'refreshed afterwards.',
                       [Length(Units), ExtractFileName(Proj)]),
                mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  Db:= ResolvePrimaryIndexDb;
  ProjDir:= ExcludeTrailingPathDelimiter(ExtractFilePath(Proj));
  Plat   := GetActiveProjectPlatform;

  { One `format` per unit: the verb takes a single <file> (verified -- handing it
    a directory answers 'File not found', exit 2). Deliberately NO '|| exit /b 1'
    between the format lines: one unit YADF cannot parse must not abandon the
    remaining units half-formatted. The trailing reindex is separate and always
    runs, so the index matches whatever ended up on disk. }
  Bat:= '@echo off'#13#10;
  for i:= 0 to High(Units) do
    Bat:= Bat + Format('"%s" format "%s"'#13#10, [DLExe64, Units[i]]);
  if Db <> '' then
    Bat:= Bat + Format('"%s" index "%s" --db "%s" --platform %s'#13#10, [DLExe64, ProjDir, Db, Plat]);

  BatPath:= TPath.Combine(TPath.GetTempPath, 'drag-lint-yadf-project.bat');
  try TFile.WriteAllText(BatPath, Bat, TEncoding.ANSI); except end;
  OutPath:= TPath.Combine(TPath.GetTempPath, 'drag-lint-yadf-project.txt');

  DLT('menu', Format('enqueue(yadf-project): %d unit(s) -> %s', [Length(Units), BatPath]));

  var FJob: TDragLintJob:= TDragLintJob.Create;
  FJob.Kind       := jkReindex;   { same queue slot as reindex -- it ends in one }
  FJob.Title      := Format('YADF %s (%d units)', [ChangeFileExt(ExtractFileName(Proj), ''), Length(Units)]);
  FJob.CoalesceKey:= 'yadfproject:' + LowerCase(Proj);
  FJob.CmdLine    := Format('cmd.exe /c "%s"', [BatPath]);
  FJob.TimeoutMs  := 600000;
  FJob.OnPreRun   :=
    procedure
    begin
      { The trailing index needs the exclusive WAL lock; a live LSP connection
        blocks it. Same precondition as InvokeReindexProject. }
      if GLspClient <> nil then begin GLspClient.Stop; FreeAndNil(GLspClient); end;
    end;
  FJob.OnDone     :=
    procedure(AExit: Integer; AOut: string)
    var S: string;
    begin
      S:= AOut;
      if Trim(S) = '' then S:= '(no output)';
      try TFile.WriteAllText(OutPath, S); except end;
      DLOpenInEditor(OutPath);
    end;
  JobQueue.Enqueue(FJob);
end; // procedure

// Broadcasts textDocument/didSave for every .pas file mentioned in AOutput
// (lines of the form  "path.pas(N,...)" -- same format as dcc64/msbuild output).
// This makes the LSP server re-publish diagnostics for the affected files.
procedure BroadcastDidSaveForAffectedFiles(const AOutput: string);
var
  Client  : TDragLintLspClient;
  Lines   : TStringList       ;
  Line    : string            ;
  FilePath: string            ;
  Uri     : string            ;
  P       : Integer           ;
  Params  : TJSONObject       ;
  TextDoc : TJSONObject       ;
begin
  Client:= EnsureLspClient;
  if Client = nil then Exit;

  Lines:= TStringList.Create;
  try
    Lines.Text:= AOutput;
    for Line in Lines do
    begin
      // Lines look like:  C:\path\File.pas(N) Warning: ...
      P:= Pos('.pas(', LowerCase(Line));
      if P <= 0 then P:= Pos('.dpr(', LowerCase(Line));
      if P <= 0 then Continue;
      FilePath:= Copy(Line, 1, P + 3); // up to and including '.pas' or '.dpr'
      if not FileExists(FilePath) then Continue;
      Uri:= 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
      Params := TJSONObject.Create;
      TextDoc:= TJSONObject.Create;
      TextDoc.AddPair('uri'         , Uri    );
      Params .AddPair('textDocument', TextDoc);
      try
        Client.Notify('textDocument/didSave', Params);
      finally
        Params.Free;
      end;
    end; // for
  finally
    Lines.Free;
  end; // try
end; // procedure

{ ---- v0.26 menu actions ---- }

{ Read an int field that may arrive as a JSON number or a quoted string. }
function JsonIntField(AObj: TJSONObject; const AName: string): Integer;
var
  S: string;
begin
  if AObj.TryGetValue<Integer>(AName, Result) then Exit;
  if AObj.TryGetValue<string>(AName, S) then Exit(StrToIntDef(S, 0));
  Result:= 0;
end;

{ Force the active edit view to repaint so gutter diagnostic marks appear now;
  the dock's Diagnostics tab auto-refreshes on its own watch timer. }
procedure RepaintActiveView;
begin
  { v0.47: robust gutter repaint (via the edit-window form handle + RDW_ALLCHILDREN)
    lives in EditViewNotifier.ForceGutterRepaint. }
  ForceGutterRepaint;
end;

{ Parse compile-check --format json output and REPLACE the compiler overlay.
  Thread-safe (the DiagnosticCache has its own lock) -- safe to call from a
  background thread. Returns False if the output held no parseable JSON array. }
{ APushOverlay: when True, the parsed compiler findings are pushed into the
  DiagnosticCache compiler overlay (FCompilerByFile). Pass True ONLY for the
  ghost-check / UNSAVED-buffer path, which has no LSP publishDiagnostics for the
  in-memory content -- the overlay is its only way onto the gutter. Pass False
  for SAVED-file compiles (compile-on-save, Compile & Diagnose): the LSP already
  merges compiler_findings from the DB into its publishDiagnostics for saved
  files (refresh-findings keeps that DB fresh), so also pushing the overlay
  DOUBLE-COUNTS the same findings -- GetForFile concatenates FByFile + the
  overlay without dedup, so the count briefly balloons (e.g. 197) then settles
  as the overlay clears: the visible flicker. Counting still returns via
  nErr/nWarn/nHint regardless of APushOverlay. }
function ParseAndPushCompileOutput(const AOutput: string; out nErr, nWarn, nHint: Integer; APushOverlay: Boolean = True): Boolean;
var
  JSON    : string                                         ;
  FilePath: string                                         ;
  Sev     : string                                         ;
  P1      : Integer                                        ;
  P2      : Integer                                        ;
  K       : Integer                                        ;
  LineNo  : Integer                                        ;
  ColNo   : Integer                                        ;
  JV      : TJSONValue                                     ;
  JArr    : TJSONArray                                     ;
  JItem   : TJSONObject                                    ;
  ByFile  : TDictionary<string, TList<TDragLintDiagnostic>>;
  Pair    : TPair<string, TList<TDragLintDiagnostic>>      ;
  L       : TList<TDragLintDiagnostic>                     ;
  D       : TDragLintDiagnostic                            ;
begin
  nErr:= 0; nWarn:= 0; nHint:= 0;
  Result:= False;
  P1:= Pos('[', AOutput);
  P2:= 0;
  for K:= Length(AOutput) downto 1 do
    if AOutput[K] = ']' then begin P2:= K; Break; end;
  if (P1 = 0) or (P2 < P1) then Exit;
  JSON:= Copy(AOutput, P1, P2 - P1 + 1);

  ByFile:= TDictionary<string, TList<TDragLintDiagnostic>>.Create;
  try
    JV:= TJSONObject.ParseJSONValue(JSON);
    try
      if JV is TJSONArray then
      begin
        JArr:= JV as TJSONArray;
        for K:= 0 to JArr.Count - 1 do
        begin
          if not (JArr.Items[K] is TJSONObject) then Continue;
          JItem:= JArr.Items[K] as TJSONObject;

          FilePath:= '';
          JItem.TryGetValue<string>('file', FilePath);
          if FilePath = '' then Continue;

          LineNo:= JsonIntField(JItem, 'line');
          ColNo := JsonIntField(JItem, 'col' );
          Sev:= '';
          JItem.TryGetValue<string>('severity', Sev);

          D:= Default(TDragLintDiagnostic);
          D.Line    := LineNo - 1; if D.Line     < 0 then D.Line    := 0;
          D.StartCol:= ColNo  - 1; if D.StartCol < 0 then D.StartCol:= 0;
          D.EndCol:= D.StartCol + 1;
          D.Source:= 'compiler';
          JItem.TryGetValue<string>('code'   , D.Code   );
          JItem.TryGetValue<string>('message', D.Message);

          if SameText(Sev, 'Error') or SameText(Sev, 'Fatal') then
          begin D.Severity:= dlsError; Inc(nErr); end
          else if SameText(Sev, 'Warning') then
          begin D.Severity:= dlsWarning; Inc(nWarn); end
          else if SameText(Sev, 'Hint') then
          begin D.Severity:= dlsHint; Inc(nHint); end
          else D.Severity:= dlsInfo;

          if not ByFile.TryGetValue(FilePath, L) then
          begin
            L:= TList<TDragLintDiagnostic>.Create;
            ByFile.Add(FilePath, L);
          end;
          L.Add(D);
        end; // for
      end; // if
    finally
      JV.Free;
    end; // try

    { Per-file replace ONLY the files THIS compile reported on -- NOT a global
      wipe. The old ClearAllCompilerFindings cleared every file's overlay, so an
      INCREMENTAL compile (which recompiles only changed units and emits nothing
      for clean/untouched units) erased the findings of units it never looked at
      -- e.g. a full-sweep-populated H2219 on a clean uMain vanished on the next
      unrelated save. refresh-findings owns the persistent per-unit DB (clear +
      insert scoped to stale units); here we only refresh the overlay for the
      units actually in this compile's output, leaving every other unit's overlay
      intact. SetCompilerFindings replaces per file (empty -> remove), so a file
      that recompiled clean and reported nothing is not in ByFile and keeps its
      prior overlay until the DB-backed LSP path or the next sweep refreshes it. }
    if APushOverlay then
      for Pair in ByFile do Cache.SetCompilerFindings(Pair.Key, Pair.Value.ToArray);
    Result:= True;
  finally
    for L in ByFile.Values do L.Free;
    ByFile.Free;
  end; // try
end; // function

var { v0.47: ONE guard shared by Compile&Diagnose, compile-on-save AND ghost-check.
    They all run msbuild on the SAME project; ghost-check additionally overlays
    the unsaved buffer on the real .pas, so a concurrent compile would build that
    overlay and mis-attribute its findings to the saved file. Mutually exclusive. }
  GProjectBuildBusy: Integer = 0;

  { Task 6 auto-refresh: single-flight guard for the Full Compile Sweep. Separate
    from GProjectBuildBusy -- the sweep spawns `drag-lint refresh-findings`, which
    runs its OWN out-of-process msbuild (not the plugin's compile-check), so the
    two guards protect different resources and a sweep may legitimately run while
    a compile-check has already released GProjectBuildBusy. Prevents two full
    sweeps from stomping the same project DB at once. }
  GSweepBusy: Integer = 0;

  /// <summary>Compiles AProjFile OUT-OF-PROCESS on a background thread (the real
  /// msbuild incremental compile) and pushes compiler findings -- including
  /// semantic errors like E2003 that the tree-sitter lint cannot see -- into the
  /// Diagnostics pane's compiler overlay. Never blocks the IDE (cannot freeze it
  /// like in-process Error Insight). When AInteractive, shows a completion dialog;
  /// the on-save trigger runs silently. Single-flight: a second call while one is
  /// running is ignored.</summary>
procedure RunCompileDiagnoseAsync(const AProjFile: string; AInteractive: Boolean);
var
  ExePath: string;
begin
  if AProjFile = '' then
  begin
    if AInteractive then ShowMessage('drag-lint Compile & Diagnose: no active project found.');
    Exit;
  end;
  if AtomicCmpExchange(GProjectBuildBusy, 1, 0) <> 0 then
  begin
    if AInteractive then ShowMessage('drag-lint: a compile is already running -- please wait.');
    Exit;
  end;
  ExePath:= DLExe64;

  TThread.CreateAnonymousThread(
    procedure var CmdLine, Output: string; ExitCode, nErr, nWarn,
    nHint: Integer; Parsed: Boolean; begin nErr:= 0; nWarn:= 0; nHint:= 0; Parsed:= False; try CmdLine:= Format('"%s" compile-check "%s" --format json', [ExePath,
            AProjFile]); DebugLog('CompileDiagnose(async): START '
      + CmdLine); ExitCode:= RunAndCaptureStdout(CmdLine, Output, 600000); DebugLog(Format('CompileDiagnose(async): exit=%d outLen=%d', [ExitCode,
              Length(Output)])); if ExitCode <> 2 then Parsed:= ParseAndPushCompileOutput(Output, nErr, nWarn, nHint, {APushOverlay=}False); DebugLog(Format('CompileDiagnose(async): parsed=%s E=%d W=%d H=%d', [BoolToStr(Parsed,
                True), nErr, nWarn, nHint])); except on E: Exception do DebugLog('CompileDiagnose(async): EXC '
      + E.Message); end; TThread.Queue(nil, procedure begin try RepaintActiveView; except end; { v0.48: tell the dock watch timer to jump to the Diagnostics section. } if Parsed then DragLint.Plugin.StructureForm.GScrollStructureToDiagPending:= True; if AInteractive then begin if Parsed then ShowMessage(Format( 'drag-lint Compile & Diagnose complete.'#13#10
      + '%d error(s), %d warning(s), %d hint(s).'#13#10 + 'See the drag-lint Diagnostics pane.', [nErr, nWarn,
                  nHint])) else ShowMessage('drag-lint Compile & Diagnose: no parseable compiler '
      + 'output (build-configuration or msbuild error).'); end; end); AtomicExchange(GProjectBuildBusy, 0); end
  ).Start;
end; // procedure

procedure InvokeCompileDiagnose(Sender: TObject);
begin
  RunCompileDiagnoseAsync(GetActiveProjectFile, True);
end;

{ v0.48: silent plain compile of a SPECIFIC project (used by the project-open
  notifier for the startup compile -- at startup nothing is unsaved, so a plain
  compile of the saved project surfaces the initial compiler errors). }
procedure TriggerProjectCompile(const AProjFile: string);
begin
  RunCompileDiagnoseAsync(AProjFile, False);
end;

{ Task 6 fix: the DB a wizard command WRITES must be the same PRIMARY DB the LSP
  READS -- otherwise the command refreshes a DB the IDE never displays from. The
  LSP resolves its active DBs via ResolveActiveIndexDbs (manifest-first: an
  ORM3-root manifest DB shadows a stale per-project <projname>.sqlite), and its
  Result[0] is the primary writable DB. So resolve the write target the identical
  way; fall back to GetActiveProjectDb only if the resolver yields nothing (no
  manifest, no indexed DB). Using GetActiveProjectDb directly (the old behaviour)
  wrote <projdir>\<projname>.sqlite, which for a manifest-covered file is exactly
  the DB the LSP deliberately ignores -- so the work never appeared.

  RENAMED from ResolveRefreshFindingsDb on 2026-08-03. It was never specific to
  refresh-findings, and the misleading name is why InvokeReindexProject kept
  calling GetActiveProjectDb instead: on C:\Projects\DataCopy the Reindex Project
  menu item spent over an hour building DataCopy.sqlite while the LSP and the
  graph viewer were both querying DataCopy\drag-lint.sqlite, so the reindex could
  not have changed a single answer the IDE gave. Same defect as Task 6, different
  call site. Anything that writes an index from the wizard must call THIS. }
function ResolvePrimaryIndexDb: string;
var
  DbList: string;
  Dir   : string;
begin
  Result:= '';
  { B2 -- THE WRITE TARGET MAY NOT EXIST YET. That is the entire point of a
    reindex, and it is why asking ResolveActiveIndexDbs was not enough.

    That function gates its manifest branch on TFile.Exists(ManifestDb), which is
    correct for a READER -- a consumer must not be pointed at a DB that is not
    there -- but self-defeating for the WRITER. A manifest section whose DB has
    never been built fails the existence test, so the resolver falls through to
    the per-.dproj convention and the reindex creates <projdir>\drag-lint.sqlite
    instead. The manifest DB then still does not exist, so the next reindex makes
    the same choice: the section can sit in drag-lint.json indefinitely and
    nothing ever builds it. Measured on DataCopy -- its section had been in the
    manifest since 6e66279 and C:\Projects\.drag-lint\DataCopy.sqlite did not
    exist at all, while the IDE happily maintained a project-local DB holding 17
    files that were gone from disk. One `index --all --only DataCopy` built the
    real one in 4.1s, so nothing about the section was ever malformed.

    So the writer asks the MANIFEST directly and accepts a path that is not there
    yet. ManifestDbForFile does no existence check of its own -- it answers "which
    section covers this file", which is exactly the question a writer wants. Only
    when no section covers the file does this fall back to the reader's answer and
    then to the per-project convention, so a project outside the manifest behaves
    exactly as before.

    The manifest's outDir may be missing too, on a first ever build. Create it
    here rather than letting the engine fail on a path it was told to write. }
  try
    Result:= ManifestDbForFile(GetActiveEditorFilePath);
    if Result = '' then Result:= ManifestDbForFile(GetActiveProjectFile);
  except
    Result:= '';
  end;
  if Result <> '' then
  begin
    Dir:= ExtractFilePath(Result);
    if (Dir <> '') and (not DirectoryExists(Dir)) then ForceDirectories(Dir);
    Exit;
  end;

  { No manifest section covers this file -- resolve exactly as the readers do, so
    a wizard command still writes the DB the LSP displays from. }
  try
    for DbList in ResolveActiveIndexDbs(LoadSettings) do
    begin
      Result:= DbList;
      Break;
    end;
  except
    Result:= '';
  end;
  if Result = '' then Result:= GetActiveProjectDb;
end;

{ Task 6 (fresh compiler findings): fire-and-forget spawn of the
  refresh-findings CLI verb, which recompiles STALE units (or ALL units when
  AFull) and refreshes the persistent compiler_findings table in the project
  DB (freshness-tracked via files.last_compiled_unix). This is a SEPARATE,
  non-blocking spawn ADDED ALONGSIDE the existing compile-check path above --
  it does not replace it. compile-check publishes findings to the live
  Diagnostics pane for the CURRENT save; refresh-findings keeps the on-disk
  DB fresh (including clean units) for any tool/query that reads
  compiler_findings later. Uses the same detached CreateProcessW pattern as
  InvokeLintBuffer (no wait, no captured output -- unlike RunAndCaptureStdout,
  which blocks). Silently no-ops if no project/db is resolvable. }
procedure SpawnRefreshFindings(const AProj, ADb: string; AFull: Boolean);
var
  ExePath : string             ;
  CmdLine : string             ;
  CmdLineW: array of WideChar  ;
  SI      : TStartupInfoW      ;
  PI      : TProcessInformation;
begin
  if (AProj = '') or (ADb = '') then
  begin
    DebugLog(Format('SpawnRefreshFindings: SKIP (proj="%s" db="%s")', [AProj, ADb]));
    Exit;
  end;
  ExePath:= DLExe64;

  FillChar(SI, SizeOf(SI), 0);
  SI.cb:= SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  CmdLine:= Format('"%s" refresh-findings --project "%s" --db "%s"%s',
    [ExePath, AProj, ADb, IfThen(AFull, ' --full', '')]);
  { Task 6 fix: log the spawn so it is VISIBLE in the plugin log which DB the
    sweep targets (previously invisible -- a wrong-DB sweep looked like no sweep). }
  DebugLog('SpawnRefreshFindings: ' + CmdLine);
  SetLength(CmdLineW, Length(CmdLine) + 1);
  Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));
  if CreateProcessW(nil, @CmdLineW[0], nil, nil, False, CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  end;
end; // procedure

{ v0.47: assigned to the SaveNotifier's compile hook. After a .pas is saved and
  AutoCompileOnSave is on, run a SILENT async compile of the active project so
  compiler errors (E2003 etc.) appear in the pane a few seconds later -- without
  blocking the IDE and without the user running the menu by hand. }
procedure TriggerCompileOnSave(const AFile: string);
begin
  if not SameText(ExtractFileExt(AFile), '.pas') then Exit;
  RunCompileDiagnoseAsync(GetActiveProjectFile, False);
  { Task 6: ADD-alongside spawn -- keeps the persistent compiler_findings DB
    fresh on every save, independent of (and in addition to) the pane-publish
    compile-check above. Fire-and-forget; does not block the save. }
  SpawnRefreshFindings(GetActiveProjectFile, ResolvePrimaryIndexDb, False);
end;

function DLActivePas(out APath: string): Boolean; forward;

{ Task 6 auto-refresh: run the Full Compile Sweep on a background thread, WAIT
  for the refresh-findings child to exit, then re-publish diagnostics for the
  currently-open .pas so the freshly-swept findings appear WITHOUT the user
  re-opening or re-saving the file.

  Why a dedicated waiter instead of the fire-and-forget SpawnRefreshFindings:
  auto-refresh needs to know WHEN the sweep is done. SpawnRefreshFindings
  detaches and returns immediately (correct for the per-save spawn -- the save
  itself already re-reads the DB). The sweep touches every unit, so nothing
  re-reads the DB afterwards on its own; we must wait, then poke the LSP.

  The poke is TriggerDiagnosticsOnSave(activePas): it sends textDocument/didSave
  to the running LSP, which re-queries compiler_findings from the just-swept DB
  and republishes -> HandleNotification -> cache -> gutter. This is the SAME
  DB-reread path a real save uses, so the display ends up identical to what the
  user would see after a manual save -- only now it is automatic.

  Never blocks the IDE: the spawn+wait live on an anonymous thread; only the
  final poke + repaint are queued to the main thread. Single-flight via
  GSweepBusy so a second menu click while a sweep runs is a no-op. }
procedure RunFullCompileSweepAsync(const AProjFile, ADb: string);
var
  ExePath: string;
begin
  if AtomicCmpExchange(GSweepBusy, 1, 0) <> 0 then
  begin
    ShowMessage('drag-lint: a Full Compile Sweep is already running -- please wait.');
    Exit;
  end;
  ExePath:= DLExe64;

  TThread.CreateAnonymousThread(
    procedure
    var
      CmdLine : string             ;
      CmdLineW: array of WideChar  ;
      SI      : TStartupInfoW      ;
      PI      : TProcessInformation;
      ActPas  : string             ;
    begin
      try
        CmdLine:= Format('"%s" refresh-findings --project "%s" --db "%s" --full',
          [ExePath, AProjFile, ADb]);
        DebugLog('FullCompileSweep(async): START ' + CmdLine);
        FillChar(SI, SizeOf(SI), 0); SI.cb:= SizeOf(SI);
        FillChar(PI, SizeOf(PI), 0);
        SetLength(CmdLineW, Length(CmdLine) + 1);
        Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));
        if CreateProcessW(nil, @CmdLineW[0], nil, nil, False,
             CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
        begin
          { Wait for the sweep to finish (a full rebuild can take minutes on a
            large project; INFINITE is fine -- we are on a worker thread). }
          WaitForSingleObject(PI.hProcess, INFINITE);
          CloseHandle(PI.hProcess);
          CloseHandle(PI.hThread );
          DebugLog('FullCompileSweep(async): DONE -- refreshing IDE display');
          { Grab the active .pas on the worker thread (read-only OTA query is
            fine), then poke the LSP + repaint on the MAIN thread. }
          TThread.Queue(nil,
            procedure
            begin
              try
                if DLActivePas(ActPas) then
                begin
                  { re-read the just-swept DB into the pane for the open file }
                  TriggerDiagnosticsOnSave(ActPas);
                  DebugLog('FullCompileSweep(async): re-published diagnostics for ' + ActPas);
                end;
                RepaintActiveView;
              except
                on E: Exception do
                  DebugLog('FullCompileSweep(async): refresh EXC ' + E.Message);
              end;
            end);
        end
        else
          DebugLog('FullCompileSweep(async): CreateProcessW FAILED');
      except
        on E: Exception do
          DebugLog('FullCompileSweep(async): EXC ' + E.Message);
      end;
      AtomicExchange(GSweepBusy, 0);
    end
  ).Start;
end; // procedure

{ Task 6: menu handler for "Full Compile Sweep" -- forces a full rebuild of
  ALL units (not just stale ones) so compiler_findings is refreshed even for
  units nothing has touched. Mirrors InvokeCompileDiagnose's no-project guard.
  Task 6 auto-refresh: delegates to RunFullCompileSweepAsync, which waits for
  the sweep and then repaints the open file -- no manual re-save needed. }
procedure InvokeFullCompileSweep(Sender: TObject);
var
  ProjFile: string;
  ProjDb  : string;
begin
  ProjFile:= GetActiveProjectFile;
  ProjDb  := ResolvePrimaryIndexDb; { the DB the LSP displays from -- not <projname>.sqlite }
  if (ProjFile = '') or (ProjDb = '') then
  begin
    ShowMessage('drag-lint Full Compile Sweep: no active project found.');
    Exit;
  end;
  RunFullCompileSweepAsync(ProjFile, ProjDb);
  ShowMessage('drag-lint: Full Compile Sweep started in the background -- '
    + 'the open file will refresh automatically once it completes.');
end;

{ v0.47: read the active editor's UNSAVED buffer (in-memory text) + its file path
  so ghost-check can compile exactly what the user is typing. }
function GetActiveBuffer(out APath, AText: string): Boolean;
var
  ES    : IOTAEditorServices        ;
  Buf   : IOTAEditBuffer            ;
  Reader: IOTAEditReader            ;
  Pos   : Integer                   ;
  Got   : Integer                   ;
  Chunk : array[0..8191] of AnsiChar;
  SB    : TStringBuilder            ;
begin
  Result:= False; APath:= ''; AText:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  Buf:= ES.TopBuffer;
  if Buf = nil then Exit;
  APath := Buf.FileName;
  Reader:= Buf.CreateReader;
  if Reader = nil then Exit;
  SB:= TStringBuilder.Create;
  try
    Pos:= 0;
    repeat
      Got:= Reader.GetText(Pos, @Chunk[0], SizeOf(Chunk) - 1);
      if Got <= 0 then Break;
      Chunk[Got]:= #0;
      SB.Append(string(AnsiString(Chunk)));
      Inc(Pos, Got);
    until False;
    AText:= SB.ToString;
    Result:= APath <> '';
  finally
    SB.Free;
  end;
end; // function

{ v0.48: read one source editor's full in-memory buffer via its reader (to EOF). }
function ReadSourceEditorText(const ASrc: IOTASourceEditor): string;
var
  Reader: IOTAEditReader            ;
  Pos   : Integer                   ;
  Got   : Integer                   ;
  Chunk : array[0..8191] of AnsiChar;
  SB    : TStringBuilder            ;
begin
  Result:= '';
  if ASrc = nil then Exit;
  Reader:= ASrc.CreateReader;
  if Reader = nil then Exit;
  SB:= TStringBuilder.Create;
  try
    Pos:= 0;
    repeat
      Got:= Reader.GetText(Pos, @Chunk[0], SizeOf(Chunk) - 1);
      if Got <= 0 then Break;
      Chunk[Got]:= #0;
      SB.Append(string(AnsiString(Chunk)));
      Inc(Pos, Got);
    until False;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

{ v0.48: enumerate EVERY open, MODIFIED module's .pas whose in-memory buffer
  actually differs from disk, stage each to a temp .pas (strict ANSI), and build a
  ghost-check overlay manifest ('realpath'<TAB>'temppath' per line). So when you
  edit several units and switch between them, the compile sees ALL the unsaved
  content at once -- not just the active tab. Returns the overlay count;
  AManifestPath = '' when none. ATempFiles lists every temp (incl. the manifest)
  to delete afterwards. MUST be called on the main thread (OTAPI access). }
function CollectUnsavedOverlays(out AManifestPath: string; out ATempFiles: TArray<string>): Integer;
var
  MS          : IOTAModuleServices;
  M           : Integer           ;
  FE          : Integer           ;
  Modu        : IOTAModule        ;
  Src         : IOTASourceEditor  ;
  Path        : string            ;
  BufText     : string            ;
  Tmp         : string            ;
  ManifestText: string            ;
  BufBytes    : TBytes            ;
  DiskBytes   : TBytes            ;
  Temps       : TList<string>     ;
begin
  Result:= 0; AManifestPath:= ''; SetLength(ATempFiles, 0);
  if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
  ManifestText:= '';
  Temps:= TList<string>.Create;
  try
    for M:= 0 to MS.ModuleCount - 1 do
    begin
      Modu:= MS.Modules[M];
      if Modu = nil then Continue;
      { the byte-diff below is the real 'is this unsaved?' test -- no IOTAModule
        Modified flag needed (and it isn't exposed on this interface version). }
      for FE:= 0 to Modu.GetModuleFileCount - 1 do
      begin
        if not Supports(Modu.GetModuleFileEditor(FE), IOTASourceEditor, Src) then Continue;
        Path:= Src.FileName;
        if (not SameText(ExtractFileExt(Path), '.pas')) or (not FileExists(Path)) then Continue;
        BufText:= ReadSourceEditorText(Src);
        if BufText = '' then Continue;
        BufBytes:= TEncoding.ANSI.GetBytes(BufText);
        { skip if this .pas buffer equals disk (e.g. only the form/.dfm changed) }
        try DiskBytes:= TFile.ReadAllBytes(Path); except SetLength(DiskBytes, 0); end;
        if (Length(BufBytes) = Length(DiskBytes)) and ((Length(BufBytes) = 0) or CompareMem(@BufBytes[0], @DiskBytes[0], Length(BufBytes))) then Continue;
        Tmp:= TPath.Combine(TPath.GetTempPath, Format('draglint-ov-%d-%d.pas', [GetTickCount, Temps.Count]));
        try TFile.WriteAllBytes(Tmp, BufBytes); except Continue; end;
        Temps.Add(Tmp);
        ManifestText:= ManifestText + Path + #9 + Tmp + sLineBreak;
        Inc(Result);
      end; // for
    end; // for
    if Result > 0 then
    begin
      AManifestPath:= TPath.Combine(TPath.GetTempPath, Format('draglint-ov-manifest-%d.txt', [GetTickCount]));
      try TFile.WriteAllText(AManifestPath, ManifestText, TEncoding.ASCII);
      except AManifestPath:= ''; end;
      if AManifestPath <> '' then Temps.Add(AManifestPath);
    end;
    ATempFiles:= Temps.ToArray;
  finally
    Temps.Free;
  end; // try
end; // function

/// <summary>Compiles the project in its CURRENT state and pushes compiler errors
/// into the Diagnostics overlay: if any units are unsaved it overlays ALL of their
/// buffers (engine 'ghost-check', guaranteed per-file restore) so errors in unsaved
/// code across every edited unit appear without saving; if nothing is unsaved it
/// runs a plain compile of the saved project (so the startup / tab-switch triggers
/// still surface errors). Out-of-process, async, single-flight; no file is
/// permanently changed.</summary>
/// <returns>True if a compile started; False only if one was already running -- so
/// the idle / switch auto-triggers can retry.</returns>
function RunGhostCheckAsync(AInteractive: Boolean): Boolean;
var
  ProjFile : string        ;
  ExePath  : string        ;
  Plat     : string        ;
  Manifest : string        ;
  Temps    : TArray<string>;
  nOverlays: Integer       ;
begin
  Result  := True; { 'consumed' on no-op; only 'busy' returns False to retry }
  ProjFile:= GetActiveProjectFile;
  if ProjFile = '' then
  begin if AInteractive then ShowMessage('drag-lint: no active project.'); Exit; end;

  { snapshot every unsaved unit (main thread, OTAPI) BEFORE taking the guard;
    0 overlays -> a plain compile of the saved project below. }
  nOverlays:= CollectUnsavedOverlays(Manifest, Temps);

  if AtomicCmpExchange(GProjectBuildBusy, 1, 0) <> 0 then
  begin
    for var T in Temps do try TFile.Delete(T); except end; { drop staged temps }
    if AInteractive then ShowMessage('drag-lint: a compile is already running -- please wait.');
    Exit(False); { retry later }
  end;

  ExePath:= DLExe64;
  Plat:= GetActiveProjectPlatform;

  TThread.CreateAnonymousThread(
    procedure var CmdLine, Output: string; ExitCode, nErr, nWarn,
    nHint: Integer; Parsed: Boolean; begin nErr:= 0; nWarn:= 0; nHint:= 0; Parsed:= False; try if nOverlays > 0 then CmdLine:= Format('"%s" ghost-check "%s" --overlays "%s" --platform %s --format json',
          [ExePath, ProjFile, Manifest, Plat]) else { nothing unsaved -> a plain compile of the saved project (same errors,
            no overlay) so startup / tab-switch triggers still show diagnostics. } CmdLine:= Format('"%s" compile-check "%s" --format json', [ExePath,
            ProjFile]); DebugLog(Format('Compile(state): %d overlay(s) START %s', [nOverlays,
              CmdLine])); ExitCode:= RunAndCaptureStdout(CmdLine, Output, 600000); DebugLog(Format('Compile(state): exit=%d outLen=%d', [ExitCode, Length(Output)])); if ExitCode <> 2 then Parsed:= ParseAndPushCompileOutput(Output, nErr, nWarn, nHint, {APushOverlay=}True); except on E: Exception do DebugLog('Compile(state): EXC '
      + E.Message); end; for var T in Temps do try TFile.Delete(T); except end; TThread.Queue(nil, procedure begin try RepaintActiveView; except end; { v0.48: tell the dock watch timer to jump to the Diagnostics section. } if Parsed then DragLint.Plugin.StructureForm.GScrollStructureToDiagPending:= True; if AInteractive then begin if Parsed then begin if nOverlays > 0 then ShowMessage(Format('drag-lint compile (%d unsaved unit(s)):'#13#10
      + '%d error(s), %d warning(s), %d hint(s).'#13#10 + 'Your files on disk were not changed.', [nOverlays, nErr, nWarn,
                    nHint])) else ShowMessage(Format('drag-lint compile (saved project):'#13#10 + '%d error(s), %d warning(s), %d hint(s).', [nErr, nWarn,
                    nHint])); end else ShowMessage('drag-lint compile: no parseable compiler output.'); end; end); AtomicExchange(GProjectBuildBusy, 0); end
  ).Start;
end; // function

procedure InvokeGhostCheck(Sender: TObject);
begin
  RunGhostCheckAsync(True);
end;

{ v0.47: restore any file left overlaid by a CRASHED ghost-check (engine writes a
  journal to the project's hidden _D-RAG before overlaying; a hard kill leaves it).
  Async; when AInteractive shows a dialog, otherwise (startup auto-run) it only
  posts to the IDE Messages pane IF something was recovered -- no prompt. The
  engine restores the saved original and keeps the crash-time content in
  _D-RAG\<unit>.crash-buffer, so nothing is ever lost. }
procedure RunGhostRecoverFor(const AProjFile: string; AInteractive: Boolean);
var
  ProjFile: string;
  ExePath : string;
begin
  ProjFile:= AProjFile;
  if ProjFile = '' then
  begin if AInteractive then ShowMessage('drag-lint: no active project.'); Exit; end;
  ExePath:= DLExe64;
  TThread.CreateAnonymousThread(
    procedure var CmdLine, Output: string; ExitCode: Integer; DidRecover: Boolean; begin DidRecover:= False; try CmdLine:= Format('"%s" ghost-recover "%s"', [ExePath,
            ProjFile]); ExitCode:= RunAndCaptureStdout(CmdLine, Output, 60000); DidRecover:= Pos('Recovered ', Output) > 0; DebugLog(Format('GhostRecover: exit=%d recovered=%s', [ExitCode,
              BoolToStr(DidRecover, True)])); except on E: Exception do DebugLog('GhostRecover: EXC ' + E.Message); end; if DidRecover
      or AInteractive then TThread.Queue(nil, procedure var MS: IOTAMessageServices; begin if DidRecover and Supports(BorlandIDEServices, IOTAMessageServices,
            MS) then MS.AddTitleMessage('drag-lint: recovered file(s) left by an ' + 'interrupted buffer-compile -- originals restored; crash-time '
      + 'content kept in the project _D-RAG folder.'); if AInteractive then begin if DidRecover then ShowMessage('drag-lint: recovered file(s) from an interrupted '
      + 'buffer-compile.'#13#10 + '(Originals restored; crash-time content saved in _D-RAG.)') else ShowMessage('drag-lint: nothing to recover.'); end; end); end
  ).Start;
end;

{ menu/interactive path: recover the currently-active project }
procedure RunGhostRecover(AInteractive: Boolean);
begin
  RunGhostRecoverFor(GetActiveProjectFile, AInteractive);
end;

{ v0.47: recover a SPECIFIC project (called from the project-open notifier, which
  fires AFTER the project is loaded -- the BPL-load startup pass runs too early,
  before any project exists, so on its own it would miss the just-crashed one). }
procedure RunGhostRecoverForProject(const AProjFile: string);
begin
  RunGhostRecoverFor(AProjFile, False);
end;

procedure InvokeGhostRecover(Sender: TObject);
begin
  RunGhostRecover(True);
end;

procedure InvokeImportLog(Sender: TObject);
var
  Dlg      : TOpenDialog;
  LogFile  : string     ;
  DbPath   : string     ;
  ExePath  : string     ;
  CmdLine  : string     ;
  Output   : string     ;
  ExitCode : Integer    ;
  ErrCount : Integer    ;
  WarnCount: Integer    ;
  HintCount: Integer    ;
  Lines    : TStringList;
  Line     : string     ;
  LLine    : string     ;
begin
  DbPath:= ResolvePrimaryIndexDb;

  Dlg:= TOpenDialog.Create(nil);
  try
    Dlg.Title := 'drag-lint: Import Build Log';
    Dlg.Filter:= 'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*';
    Dlg.Options:= [ofFileMustExist, ofPathMustExist];
    if not Dlg.Execute then Exit;
    LogFile:= Dlg.FileName;
  finally
    Dlg.Free;
  end;

  ExePath:= DLExe64;

  if DbPath <> '' then CmdLine:= Format('"%s" import-log "%s" --db "%s"', [ExePath, LogFile, DbPath])
  else CmdLine:= Format('"%s" import-log "%s"', [ExePath, LogFile]);

  ExitCode:= RunAndCaptureStdout(CmdLine, Output, 60000);

  if ExitCode = 2 then
  begin
    ShowMessage('drag-lint: failed to spawn import-log.'#13#10 + 'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  // Count imported findings from output.
  ErrCount := 0;
  WarnCount:= 0;
  HintCount:= 0;
  Lines:= TStringList.Create;
  try
    Lines.Text:= Output;
    for Line in Lines do
    begin
      LLine:= LowerCase(Line);
      if (Pos(') error:', LLine) > 0) or (Pos(') fatal:', LLine) > 0) then Inc(ErrCount)
      else if Pos(') warning:', LLine) > 0 then Inc(WarnCount)
      else if (Pos(') hint:', LLine) > 0) or (Pos(') information:', LLine) > 0) then Inc(HintCount);
    end;
  finally
    Lines.Free;
  end; // try

  // Trigger LSP refresh for affected files.
  if DbPath <> '' then BroadcastDidSaveForAffectedFiles(Output);

  ShowMessage(Format(
      'drag-lint Import Build Log complete.'#13#10 + 'Imported: %d error(s), %d warning(s), %d hint(s).'#13#10 + 'Check the Messages pane for details.',
      [ErrCount, WarnCount, HintCount]));
end; // procedure

/// <summary>Opens the IDE Tools->Options dialog (drag-lint pages live under
/// Third Party > drag-lint). Replaces the retired hand-coded settings modal.</summary>
procedure InvokeOptionsDialog(Sender: TObject);
var
  EnvOptions: IOTAEnvironmentOptions140;
begin
  { IOTAEnvironmentOptions140.EditOptions is the OTA-native focused-open call:
    Area='' resolves to the "Third Party" tree node; PageCaption matches the
    dotted caption registered in DragLint.Plugin.Options (RegisterDragLintOptions),
    e.g. 'drag-lint.General', which also nests the Indexer/Linter/Editor siblings
    under the same 'drag-lint' node. }
  if Supports(BorlandIDEServices, IOTAEnvironmentOptions140, EnvOptions) then
    EnvOptions.EditOptions('', 'drag-lint.General')
  else
    ShowMessage('drag-lint settings are under Tools > Options > Third Party > drag-lint.');
end;

{ v0.30: show structure form }
procedure InvokeShowStructure(Sender: TObject);
begin
  ShowDragLintStructure;
end;

{ v0.31: Run AST Checks on the active file (no compiler required) }
procedure InvokeRunAstChecks(Sender: TObject);
var
  ESS     : IOTAEditorServices;
  EditView: IOTAEditView      ;
  FilePath: string            ;
  ExePath : string            ;
  DbPath  : string            ;
  CmdLine : string            ;
  Output  : string            ;
  ExitCode: Integer           ;
  Client  : TDragLintLspClient;
  Params  : TJSONObject       ;
  TextDoc : TJSONObject       ;
  Uri     : string            ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    ShowMessage('drag-lint: no editor services available');
    Exit;
  end;
  EditView:= ESS.TopView;
  if EditView = nil then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;
  FilePath:= EditView.Buffer.FileName;
  if FilePath = '' then
  begin
    ShowMessage('drag-lint: active buffer has no file name');
    Exit;
  end;

  ExePath:= DLExe64;

  DbPath:= ResolvePrimaryIndexDb;

  if DbPath <> '' then CmdLine:= Format('"%s" check-ast "%s" --db "%s"', [ExePath, FilePath, DbPath])
  else CmdLine:= Format('"%s" check-ast "%s"', [ExePath, FilePath]);

  ExitCode:= RunAndCaptureStdout(CmdLine, Output, 30000);

  if ExitCode = 2 then
  begin
    ShowMessage('drag-lint: failed to spawn check-ast.'#13#10 + 'Ensure drag-lint.exe is on PATH or next to the BPL.');
    Exit;
  end;

  Uri:= 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
  Client:= EnsureLspClient;
  if Client <> nil then
  begin
    Params := TJSONObject.Create;
    TextDoc:= TJSONObject.Create;
    TextDoc.AddPair('uri'         , Uri    );
    Params .AddPair('textDocument', TextDoc);
    try
      Client.Notify('textDocument/didSave', Params);
    finally
      Params.Free;
    end;
  end;

  ShowMessage(Format('drag-lint AST Checks:'#13#10'%s', [Trim(Output)]));
end; // procedure

{ v0.33: Find Usages }
function IdentifierAtCursor: string;
{ v0.40.3: read the active editor's caret line and return the identifier
  spanning the cursor column. Identifier = run of [A-Za-z0-9_] containing
  the cursor position. Empty string if no identifier under cursor. }
var
  ESS         : IOTAEditorServices        ;
  EV          : IOTAEditView              ;
  Reader      : IOTAEditReader            ;
  CaretRow    : Integer                   ;
  CaretCol    : Integer                   ;
  LineStartPos: Integer                   ;
  Buf         : array[0..1023] of AnsiChar;
  Read        : Integer                   ;
  LineText    : string                    ;
  Lo          : Integer                   ;
  Hi          : Integer                   ;

  function IsIdentChar(C: Char): Boolean;
  begin
    Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;

begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EV:= ESS.TopView;
    if (EV = nil) or (EV.Buffer = nil) then Exit;
    Reader:= EV.Buffer.CreateReader;
    if Reader = nil then Exit;
    CaretRow:= EV.Position.Row;
    CaretCol:= EV.Position.Column;
    if (CaretRow <= 0) or (CaretCol <= 0) then Exit;

    { Buffer is character-addressed; we don't have a direct line offset,
      so walk the file scanning for newlines until we hit (CaretRow - 1).
      Lines are typically <1KB so this is cheap even for long files. }
    LineStartPos:= 0;
    var CurRow:= 1;
    var Pos   := 0;
    while CurRow < CaretRow do
    begin
      Read:= Reader.GetText(Pos, Buf, SizeOf(Buf));
      if Read <= 0 then Exit;
      for var i:= 0 to Read - 1 do
      begin
        if Buf[i] = #10 then
        begin
          Inc(CurRow);
          if CurRow = CaretRow then
          begin
            LineStartPos:= Pos + i + 1;
            Break;
          end;
        end;
      end;
      if CurRow >= CaretRow then Break;
      Inc(Pos, Read);
    end; // while

    Read:= Reader.GetText(LineStartPos, Buf, SizeOf(Buf));
    if Read <= 0 then Exit;
    var EolIdx:= 0;
    while (EolIdx < Read) and not (Buf[EolIdx] in [#10, #13]) do Inc(EolIdx);
    SetString(LineText, PAnsiChar(@Buf[0]), EolIdx);

    if CaretCol > Length(LineText) then Exit;
    if (CaretCol > 0) and (CaretCol <= Length(LineText)) and not IsIdentChar(LineText[CaretCol]) then
    begin
      { Try one column to the left -- caret can sit just past an identifier. }
      if (CaretCol > 1) and IsIdentChar(LineText[CaretCol - 1]) then Dec(CaretCol)
      else Exit;
    end;
    if (CaretCol < 1) or (CaretCol > Length(LineText)) then Exit;
    if not IsIdentChar(LineText[CaretCol]) then Exit;

    Lo:= CaretCol;
    while (Lo > 1) and IsIdentChar(LineText[Lo - 1]) do Dec(Lo);
    Hi:= CaretCol;
    while (Hi < Length(LineText)) and IsIdentChar(LineText[Hi + 1]) do Inc(Hi);
    Result:= Copy(LineText, Lo, Hi - Lo + 1);
  except
    Result:= '';
  end; // try
end; // begin

procedure InvokeFindUsages(Sender: TObject);
var
  ExePath : string           ;
  DbList  : TArray<string>   ;
  SymName : string           ;
  Settings: TDragLintSettings;
begin
  Settings:= LoadSettings;
  ExePath:= DLExe64;

  { v0.40.3: resolve every relevant DB (project + sibling subprojects +
    explicit list + library) instead of the broken single-project lookup. }
  try
    DbList:= ResolveActiveIndexDbs(Settings);
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
  SymName:= IdentifierAtCursor;
  if (SymName = '') or ((GetKeyState(VK_SHIFT) and $8000) <> 0) then
  begin
    SymName:= InputBox( 'drag-lint Find Usages', 'Symbol name (Shift+menu forces this prompt; otherwise auto-picked from cursor):', SymName);
  end;
  if Trim(SymName) = '' then Exit;

  if Length(DbList) > 0 then ShowFindUsages(SymName, ExePath, DbList)
  else { No DBs resolved -- fall back to legacy single-arg path so the form
      still surfaces a meaningful error. }
    ShowFindUsages(SymName, ExePath, '');
end; // procedure

{ v0.33: Symbol Search }
procedure InvokeSymbolSearch(Sender: TObject);
var
  ExePath : string            ;
  ProjDb  : string            ;
  Selected: string            ;
  ColonPos: Integer           ;
  FilePath: string            ;
  LineNum : Integer           ;
  ESS     : IOTAEditorServices;
  AS_     : IOTAActionServices;
  EV      : IOTAEditView      ;
  Pos     : IOTAEditPosition  ;
begin
  ExePath:= DLExe64;

  ProjDb:= ResolvePrimaryIndexDb;
  Selected:= ShowSymbolSearch(ExePath, ProjDb);
  if Selected = '' then Exit;

  { Parse "file:line" from the returned location }
  ColonPos:= 0;
  var K: Integer;
  for K:= Length(Selected) downto 1 do
    if Selected[K] = ':' then
    begin
      ColonPos:= K;
      Break;
    end;

  if ColonPos > 0 then
  begin
    FilePath:= Copy(Selected, 1, ColonPos - 1);
    LineNum:= StrToIntDef(Copy(Selected, ColonPos + 1, MaxInt), 0);
  end
  else
  begin
    FilePath:= Selected;
    LineNum := 0;
  end;

  if FilePath = '' then Exit;

  if Supports(BorlandIDEServices, IOTAActionServices, AS_) then AS_.OpenFile(FilePath);

  if (LineNum > 0) and Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV:= ESS.TopView;
    if EV <> nil then
    begin
      Pos:= EV.Position;
      if Pos <> nil then
      begin
        Pos.GotoLine(LineNum);
        EV.Paint;
      end;
    end;
  end;
end; // procedure

{ ---- forms-csv IDE menu action ---- }

/// <summary>Warns (log + message box) when the just-generated forms CSV's
/// provenance footer reports a "forms-csv algorithm v&lt;N&gt;" that differs from
/// the version this plugin build expects, i.e. the deployed drag-lint.exe is
/// stale relative to the plugin. Best-effort: any parse failure or missing
/// footer is silently ignored and this never blocks opening the file.</summary>
/// <param name="ACsvPath">Path to the forms CSV just written by drag-lint.exe.</param>
/// <remarks>The footer line is emitted by DRagLint.FormsMap (FORMS_CSV_ALGORITHM)
/// as `# forms-csv algorithm v&lt;N> | db: &lt;path> | schema v&lt;n> | &lt;timestamp>` in
/// the 7th (Notes) CSV column of the last row -- there is no KEY=VALUE pair,
/// so the version is parsed as the digit run right after the literal
/// "algorithm v". Reads the file as ANSI to match the engine's output encoding.</remarks>
const
  EXPECTED_FORMS_CSV_ALGO = '4'; // keep in lockstep with FormsMap.FORMS_CSV_ALGORITHM
procedure WarnIfStaleFormsCsv(const ACsvPath: string);
var
  Lines   : TArray<string>;
  L       : string       ;
  FoundVer: string       ;
  Marker  : string       ;
  P, I    : Integer      ;
begin
  FoundVer:= '';
  try
    if not TFile.Exists(ACsvPath) then Exit;
    Lines:= TFile.ReadAllLines(ACsvPath, TEncoding.ANSI);
    Marker:= 'forms-csv algorithm v';
    for L in Lines do
    begin
      P:= Pos(Marker, L);
      if P > 0 then
      begin
        I:= P + Length(Marker);
        while (I <= Length(L)) and (L[I] >= '0') and (L[I] <= '9') do
        begin
          FoundVer:= FoundVer + L[I];
          Inc(I);
        end;
        Break;
      end;
    end;
  except
    Exit; // best-effort only; never let a parse failure block opening the CSV
  end;
  if (FoundVer <> '') and (FoundVer <> EXPECTED_FORMS_CSV_ALGO) then
  begin
    DLT('menu', Format('forms-csv: STALE EXE? csv algo=v%s expected=v%s', [FoundVer, EXPECTED_FORMS_CSV_ALGO]));
    ShowMessage(Format('drag-lint: the forms CSV was produced by a drag-lint.exe whose format (v%s) differs from this plugin''s expected v%s. The deployed exe may be stale.', [FoundVer, EXPECTED_FORMS_CSV_ALGO]));
  end;
end; // procedure

procedure InvokeGenerateFormsCsv(Sender: TObject);
{ Saves all modified modules, resolves the active project .dproj + drag-lint
  index, prompts for a CSV output path, runs forms-csv, then opens the
  resulting file in the IDE editor. }
var
  ProjFile: string            ;
  ProjDb  : string            ;
  ExePath : string            ;
  OutPath : string            ;
  CmdLine : string            ;
  Output  : string            ;
  ExitCode: Integer           ;
  Dlg     : TSaveDialog       ;
  MS      : IOTAModuleServices;
  AS_     : IOTAActionServices;
begin
  { Save all so on-disk DFMs match the editor; the engine reads saved files. }
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;

  ProjFile:= GetActiveProjectFile;
  ProjDb  := ResolvePrimaryIndexDb;
  if (ProjFile = '') or (ProjDb = '') then
  begin
    ShowMessage('drag-lint: no active project or index found.');
    Exit;
  end;

  { Resolve drag-lint.exe -- prefer Win64 build for heavy jobs. }
  ExePath:= DLExe64;

  { Prompt for the output CSV path. }
  Dlg:= TSaveDialog.Create(nil);
  try
    Dlg.Filter    := 'CSV files (*.csv)|*.csv';
    Dlg.DefaultExt:= 'csv';
    Dlg.FileName:= ChangeFileExt(ExtractFileName(ProjFile), '') + '-forms.csv';
    Dlg.InitialDir:= ExtractFilePath(ProjFile);
    if not Dlg.Execute then Exit;
    OutPath:= Dlg.FileName;
  finally
    Dlg.Free;
  end;

  { Multi-DB: project DB is FIRST (authoritative for form enumeration); any
    other active-scope DBs (e.g. a shared/library index) widen the caller-
    search scope so cross-DB launch chains are not misreported as dead. }
  var DbList: TArray<string>;
  try
    DbList:= ResolveActiveIndexDbs(LoadSettings);
  except
    SetLength(DbList, 0);
  end;
  var DbArgs: string:= '';
  if ProjDb <> '' then DbArgs:= Format(' --db "%s"', [ProjDb]);
  for var D in DbList do
    if not SameText(D, ProjDb) then DbArgs:= DbArgs + Format(' --db "%s"', [D]);

  CmdLine:= Format('"%s" forms-csv --project "%s"%s --out "%s"', [ExePath, ProjFile, DbArgs, OutPath]);
  { v0.65.1: enqueue on the R2 job queue instead of RunAndCaptureStdout on the UI
    thread (which froze the IDE for up to 2 minutes). Serialized with reindex /
    lint-all so they cannot collide on the project DB. }
  DLT('menu', 'enqueue(forms-csv): ' + CmdLine);
  var FJob: TDragLintJob:= TDragLintJob.Create;
  FJob.Kind     := jkFormsCsv;
  FJob.Title    := 'Forms CSV ' + ChangeFileExt(ExtractFileName(ProjFile), '');
  FJob.CmdLine  := CmdLine; { no coalesce: each run targets a distinct output path }
  FJob.TimeoutMs:= 120000;
  FJob.OnDone   :=
    procedure(AExit: Integer; AOut: string)
    var
      AS2: IOTAActionServices;
    begin
      if AExit <> 0 then
      begin
        ShowMessage('drag-lint: forms-csv failed. See plugin log.');
        Exit;
      end;
      WarnIfStaleFormsCsv(OutPath);
      if Supports(BorlandIDEServices, IOTAActionServices, AS2) then AS2.OpenFile(OutPath);
    end;
  JobQueue.Enqueue(FJob);
end; // procedure

{ ---- menu registration ---- }

function AddWrappedItem(AParent: TMenuItem; const ACaption: string; AProc: TMenuProc): TMenuItem;
var
  W: TMenuActionWrapper;
begin
  Result:= TMenuItem.Create(AParent);
  Result.Caption:= ACaption;
  W:= TMenuActionWrapper.Create(AProc);
  GWrappers.Add(W);
  Result.OnClick:= W.HandleClick;
  AParent.Add(Result);
end;

{ v0.42: menu separator line. }
function AddSeparator(AParent: TMenuItem): TMenuItem;
begin
  Result:= TMenuItem.Create(AParent);
  Result.Caption:= '-';
  AParent.Add(Result);
end;

{ v0.42: a non-clickable section header (disabled caption) used to label the
  diagnostics/test block at the bottom of the menu. }
function AddSectionHeader(AParent: TMenuItem; const ACaption: string): TMenuItem;
begin
  Result:= TMenuItem.Create(AParent);
  Result.Caption:= ACaption;
  Result.Enabled:= False;
  AParent.Add(Result);
end;

{ v0.42: recursively find a menu item by Name anywhere under AParent. Used to
  remove a stale dock entry left by a prior install/reinstall before we add a
  fresh one, so View > Tool Windows never accumulates duplicates. }
function FindMenuItemByName(AParent: TMenuItem; const AName: string): TMenuItem;
var
  i: Integer;
begin
  Result:= nil;
  if AParent = nil then Exit;
  for i:= 0 to AParent.Count - 1 do
  begin
    if SameText(AParent.Items[i].Name, AName) then Exit(AParent.Items[i]);
    Result:= FindMenuItemByName(AParent.Items[i], AName);
    if Result <> nil then Exit;
  end;
end;

{ v0.42: free every direct child of AParent whose (ampersand-stripped) caption
  equals ACaption. Used to purge any stale 'drag-lint' dock entries left under
  View > Tool Windows by a prior install that didn't (or couldn't) clean up,
  regardless of whether they had a Name set. }
procedure RemoveChildrenByCaption(AParent: TMenuItem; const ACaption: string);
var
  i: Integer;
  C: string ;
begin
  if AParent = nil then Exit;
  for i:= AParent.Count - 1 downto 0 do
  begin
    C:= StringReplace(AParent.Items[i].Caption, '&', '', [rfReplaceAll]);
    if SameText(Trim(C), ACaption) then AParent.Items[i].Free;
  end;
end;

{ v0.42: find a direct child menu item by its (ampersand-stripped) caption. }
function FindMenuChildByCaption(AParent: TMenuItem; const ACaption: string): TMenuItem;
var
  i: Integer;
  C: string ;
begin
  Result:= nil;
  if AParent = nil then Exit;
  for i:= 0 to AParent.Count - 1 do
  begin
    C:= StringReplace(AParent.Items[i].Caption, '&', '', [rfReplaceAll]);
    if SameText(Trim(C), ACaption) then Exit(AParent.Items[i]);
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
  Result:= nil;
  if Services = nil then Exit;
  MainMenu:= Services.MainMenu;
  if MainMenu = nil then Exit;
  ViewItem:= FindMenuChildByCaption(MainMenu.Items, 'View');
  if ViewItem = nil then Exit;
  Result:= FindMenuChildByCaption(ViewItem, 'Tool Windows');
  if Result = nil then Result:= ViewItem; { fall back to View itself }
end;

{ ---- v0.40.3: lint unsaved buffer -------------------------------------- }

function ReadActiveBufferText(out AFileName: string): string;
{ Snapshot the in-memory text of the active editor view via IOTAEditReader.
  Returns '' if no active view or buffer. Output is UTF-8 friendly because
  the IDE buffer is already AnsiString in the source charset; we read raw
  bytes and let drag-lint's parser handle encoding the same way it does
  for on-disk files. }
var
  ESS   : IOTAEditorServices         ;
  EV    : IOTAEditView               ;
  Reader: IOTAEditReader             ;
  Buf   : TBytes                     ;
  Pos   : Integer                    ;
  N     : Integer                    ;
  Tmp   : array[0..16383] of AnsiChar;
const
  Chunk = SizeOf(Tmp);
begin
  Result   := '';
  AFileName:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if EV        = nil then Exit;
  if EV.Buffer = nil then Exit;
  AFileName:= EV.Buffer.FileName;
  Reader   := EV.Buffer.CreateReader;
  if Reader = nil then Exit;

  SetLength(Buf, 0);
  Pos:= 0;
  { v0.46: read to true EOF -- GetText can short-read mid-buffer, so the old
    `until N < CHUNK` truncated the snapshot (see LiveDiagnostics.ActiveBufferText). }
  repeat
    N:= Reader.GetText(Pos, Tmp, Chunk);
    if N <= 0 then Break;
    SetLength(Buf, Length(Buf) + N);
    Move(Tmp[0], Buf[Length(Buf) - N], N);
    Inc(Pos, N);
  until False;

  if Length(Buf) > 0 then Result:= TEncoding.ANSI.GetString(Buf);
end; // function

procedure InvokeLintBuffer(Sender: TObject);
var
  FilePath : string             ;
  BufText  : string             ;
  Ext      : string             ;
  TmpPath  : string             ;
  Cfg      : TDragLintSettings  ;
  ExePath  : string             ;
  CmdLine  : string             ;
  TmpStream: TFileStream        ;
  Bytes    : TBytes             ;
  SI       : TStartupInfoW      ;
  PI       : TProcessInformation;
  CmdLineW : array of WideChar  ;
begin
  BufText:= ReadActiveBufferText(FilePath);
  if BufText = '' then
  begin
    ShowMessage(PluginBuildTag + #13#10#13#10 + 'drag-lint: no active editor buffer to lint.');
    Exit;
  end;

  Ext:= ExtractFileExt(FilePath);
  if Ext = '' then Ext:= '.pas';
  TmpPath:= TPath.Combine(TPath.GetTempPath, Format('drag-lint-buffer-%d%s', [GetTickCount, Ext]));

  Bytes:= TEncoding.UTF8.GetBytes(BufText);
  try
    TmpStream:= TFileStream.Create(TmpPath, fmCreate);
    try
      if Length(Bytes) > 0 then TmpStream.WriteBuffer(Bytes[0], Length(Bytes));
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

  Cfg:= LoadSettings;
  ExePath:= DLExe64;

  { Spawn detached: drag-lint lint <tmp> --json. We don't capture stdout
    in v0.40.3a -- the diagnostic-publish path will be wired in v0.40.4
    after we add a one-shot --output <jsonfile> flag to drag-lint. Today
    the user sees results in the Messages pane via the spawn fall-through. }
  FillChar(SI, SizeOf(SI), 0);
  SI.cb:= SizeOf(SI);
  FillChar(PI, SizeOf(PI), 0);
  CmdLine:= Format('"%s" lint "%s"', [ExePath, TmpPath]);
  SetLength(CmdLineW, Length(CmdLine) + 1);
  Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));
  if CreateProcessW(nil, @CmdLineW[0], nil, nil, False, CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI) then
  begin
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  end;

  TThread.Queue(
    nil,
    procedure var MS: IOTAMessageServices; begin if Supports(BorlandIDEServices, IOTAMessageServices,
        MS) then MS.AddTitleMessage(Format( 'drag-lint: linted buffer snapshot of %s (-> %s)', [ExtractFileName(FilePath), ExtractFileName(TmpPath)])); end
  );
end; // procedure

type
  { A single parsed finding, retained so the clipboard text can be sorted by
    source position -- the raw `drag-lint lint` output is grouped by RULE, not by
    line, so pasting it verbatim did not match the line-ordered Diagnostics pane. }
  TCopyDiagRow = record
    LineNo: Integer;
    ColNo : Integer;
    Text  : string ; { the pre-formatted "file(l,c): tag rule: msg" clipboard line }
  end;

procedure InvokeCopyDiagnostics(Sender: TObject);
{ v0.46: lint the active SAVED file ON DEMAND (synchronous), copy the findings to
  the clipboard (for pasting to an AI) AND publish them to the cache + repaint so
  the gutter/inline markers light up. This is independent of the background
  live-diagnostics runner -- it always reflects the file on disk right now.
  Clipboard rows are SORTED by (line, column) so the pasted list reads top-to-
  bottom like the file / the Diagnostics pane (the engine emits them grouped by
  rule). The gutter cache is keyed by range, so it needs no ordering. }
var
  ES      : IOTAEditorServices ;
  EV      : IOTAEditView       ;
  FilePath: string             ;
  Exe     : string             ;
  CmdLine : string             ;
  Output  : string             ;
  Line    : string             ;
  Loc     : string             ;
  Loc2    : string             ;
  ColStr  : string             ;
  LineStr : string             ;
  Tag     : string             ;
  Rest    : string             ;
  Rule    : string             ;
  Msg     : string             ;
  ClipText: string             ;
  Lines   : TStringList        ;
  SB      : TStringBuilder     ;
  Rows    : TList<TCopyDiagRow>;
  Row     : TCopyDiagRow       ;
  i       : Integer            ;
  lb      : Integer            ;
  rb      : Integer            ;
  c1      : Integer            ;
  c2      : Integer            ;
  P       : Integer            ;
  LineNo  : Integer            ;
  ColNo   : Integer            ;
  Count   : Integer            ;
  SevInt  : Integer            ;
  Params  : TJSONObject        ;
  DObj    : TJSONObject        ;
  RangeObj: TJSONObject        ;
  StartObj: TJSONObject        ;
  EndObj  : TJSONObject        ;
  Arr     : TJSONArray         ;
begin
  FilePath:= '';
  if Supports(BorlandIDEServices, IOTAEditorServices, ES) and (ES <> nil) then
  begin
    EV:= ES.TopView;
    if (EV <> nil) and (EV.Buffer <> nil) then FilePath:= EV.Buffer.FileName;
  end;
  if (FilePath = '') or not FileExists(FilePath) then
  begin
    ShowMessage('drag-lint: no active SAVED file to lint. Save the file (Ctrl+S) first.');
    Exit;
  end;

  { Prefer the Win64 engine (avoids 32-bit OOM on large indexes). }
  Exe:= DLExe64;

  CmdLine:= Format('"%s" lint "%s"', [Exe, FilePath]);
  Output:= '';
  RunAndCaptureStdout(CmdLine, Output, 20000);

  Lines := TStringList        .Create;
  SB    := TStringBuilder     .Create;
  Rows  := TList<TCopyDiagRow>.Create;
  Params:= TJSONObject        .Create;
  Arr   := TJSONArray         .Create;
  try
    Lines.Text:= Output;
    Count:= 0;
    for i:= 0 to Lines.Count - 1 do
    begin
      Line:= Lines[i];
      lb:= Pos('[', Line); rb:= Pos(']', Line);
      if (lb = 0) or (rb = 0) or (rb < lb) then Continue; { not a finding line }
      Loc:= Trim(Copy(Line, 1, lb - 1));
      c2:= LastDelimiter(':', Loc); if c2 <= 1 then Continue;
      ColStr:= Copy(Loc, c2 + 1, MaxInt);
      Loc2:= Copy(Loc, 1, c2 - 1);
      c1:= LastDelimiter(':', Loc2); if c1 <= 1 then Continue;
      LineStr:= Copy(Loc2, c1 + 1, MaxInt);
      Tag:= LowerCase(Copy(Line, lb + 1, rb - lb - 1));
      Rest:= Trim(Copy(Line, rb + 1, MaxInt));
      P:= Pos(':', Rest);
      if P > 0 then
      begin Rule:= Trim(Copy(Rest, 1, P - 1)); Msg:= Trim(Copy(Rest, P + 1, MaxInt)); end
      else
      begin Rule:= ''; Msg:= Rest; end;
      LineNo:= StrToIntDef(Trim(LineStr), 1);
      ColNo := StrToIntDef(Trim(ColStr ), 1);

      { Collect the clipboard row; sorted by (line, col) after the loop so the
        pasted list is in file order, not the engine's rule-grouped order. }
      Row.LineNo:= LineNo;
      Row.ColNo := ColNo ;
      Row.Text  := Format('%s(%d,%d): %s %s: %s', [FilePath, LineNo, ColNo, Tag, Rule, Msg]);
      Rows.Add(Row);
      Inc(Count);

      { cache entry (LSP-style, 0-based) so EditViewNotifier paints it }
      if Pos('error', Tag) > 0 then SevInt:= 1
      else if Pos('warn', Tag) > 0 then SevInt:= 2
      else if Pos('hint', Tag) > 0 then SevInt:= 4
      else SevInt:= 3;
      StartObj:= TJSONObject.Create;
      StartObj.AddPair('line'     , TJSONNumber.Create(LineNo - 1));
      StartObj.AddPair('character', TJSONNumber.Create(ColNo  - 1));
      EndObj:= TJSONObject.Create;
      EndObj.AddPair('line', TJSONNumber.Create(LineNo - 1));
      EndObj.AddPair('character', TJSONNumber.Create(ColNo + 1));
      RangeObj:= TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end'  , EndObj  );
      DObj:= TJSONObject.Create;
      DObj.AddPair('range', RangeObj);
      DObj.AddPair('severity', TJSONNumber.Create(SevInt));
      DObj.AddPair('source' , 'lint');
      DObj.AddPair('code'   , Rule  );
      DObj.AddPair('message', Msg   );
      Arr.AddElement(DObj);
    end; // for

    { Sort the clipboard rows by (line, column) -- stable enough for the pane to
      match -- then emit them in file order. }
    Rows.Sort(TComparer<TCopyDiagRow>.Construct(
      function(const L, R: TCopyDiagRow): Integer
      begin
        Result:= L.LineNo - R.LineNo;
        if Result = 0 then Result:= L.ColNo - R.ColNo;
      end));
    for i:= 0 to Rows.Count - 1 do
      SB.AppendLine(Rows[i].Text);

    Params.AddPair('diagnostics', Arr   ); { Arr ownership -> Params }
    Cache .Update (FilePath     , Params);
    if (ES <> nil) and (ES.TopView <> nil) then
    try ES.TopView.Paint; except end;

    if Count = 0 then ShowMessage(Format('drag-lint: no diagnostics for %s.', [ExtractFileName(FilePath)]))
    else
    begin
      ClipText:= Format('drag-lint diagnostics for %s (%d):'#13#10'%s', [ExtractFileName(FilePath), Count, SB.ToString]);
      Vcl.Clipbrd.Clipboard.AsText:= ClipText;
      ShowMessage(Format( 'drag-lint: %d diagnostic(s) copied to the clipboard and shown in the gutter.', [Count]));
    end;
  finally
    SB.Free;
    Rows.Free;
    Lines.Free;
    Params.Free; { frees Arr + child objects }
  end; // try
end; // procedure

procedure InvokeOpenLog(Sender: TObject);
var
  LogPath: string;
begin
  LogPath:= GetPluginLogPath;
  if not FileExists(LogPath) then
  begin
    ShowMessage(PluginBuildTag + #13#10#13#10 + 'No log yet at:'#13#10 + LogPath + #13#10#13#10 + 'The log is created on first plugin LSP invocation.');
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
  DeployDir   : string   ;
  DeployedExe : string   ;
  StagedTime  : TDateTime;
  DeployedTime: TDateTime;
begin
  try
    if not FileExists(STAGING_PATH) then Exit;
    DeployDir:= ExtractFilePath(GetModuleName(HInstance));
    DeployedExe:= DeployDir + 'drag-lint.exe';
    StagedTime:= 0;
    if FileAge(STAGING_PATH, StagedTime) then
    begin
      if FileExists(DeployedExe) and FileAge(DeployedExe, DeployedTime) then
      begin
        if StagedTime <= DeployedTime then Exit;
      end;
      { Copy staged -> deployed. Give the kernel a beat in case Stop's
        TerminateProcess hasn't fully released the file yet. }
      Sleep(500);
      if Winapi.Windows.CopyFile(PChar(STAGING_PATH), PChar(DeployedExe), False) then DebugLog(Format('AutoPullStagedExe: copied %s -> %s', [STAGING_PATH, DeployedExe]))
      else DebugLog(Format('AutoPullStagedExe: CopyFile FAILED (Win32 err %d) for %s', [GetLastError, DeployedExe]));
    end;
  except
    on E: Exception do DebugLog('AutoPullStagedExe: ' + E.ClassName + ': ' + E.Message);
  end; // try
end; // procedure

procedure InvokeDockPanel(Sender: TObject);
begin
  ShowDragLintDock;
end;

procedure InvokeGraphWindow(Sender: TObject);
begin
  ShowDragLintGraph;
end;

{ ============================================================================
  v0.46: surface the analysis/refactor/export CLI commands on the menu.
  Shared helpers keep each handler tiny: resolve the engine, run a command,
  open its text/CSV output in the IDE editor.
  ============================================================================ }

function DLExe: string;
begin
  Result:= DragLintExe;
end;

{ Like DLExe but prefers the Win64 build (..\dll-win64\drag-lint.exe) for heavy,
  long-running jobs (lint-all). The 32-bit IDE design package spawns drag-lint
  as a SEPARATE child process over a pipe, so the child's bitness is independent
  of the IDE; the Win64 exe is faster and does not OOM on large indexes, and it
  carries its own correct x64 tree-sitter DLLs. v0.86: delegates to the shared
  resolver (single Win64-first policy for every spawn site); kept as a distinct
  function name so callers don't churn. }
function DLExe64: string;
begin
  Result:= DragLintExe;
end;

procedure DLOpenInEditor(const AFilePath: string);
var
  AS_: IOTAActionServices;
begin
  if (AFilePath <> '') and FileExists(AFilePath) and Supports(BorlandIDEServices, IOTAActionServices, AS_) then AS_.OpenFile(AFilePath);
end;

{ Run "exe <tail>", capture stdout, write to %TEMP%\<base>, open it in the IDE. }
procedure DLRunReport(const ACmdTail, ABaseName: string);
var
  Cmd    : string;
  OutPath: string;
begin
  { v0.46 review (M): run the engine OFF the main thread so a slow/hung command
    (cap 180s) does not freeze the IDE. The worker only runs the subprocess +
    writes a temp file (both thread-safe, no OTAPI); the editor open (OTAPI) is
    marshalled back to the main thread via TThread.Queue -- same pattern as
    LiveDiagnostics.TLiveRunner. Cmd/OutPath are locals captured (heap-promoted)
    by the closure, so they outlive this procedure's return. }
  Cmd:= Format('"%s" %s', [DLExe64, ACmdTail]);
  OutPath:= TPath.Combine(TPath.GetTempPath, ABaseName);
  DLT('menu', 'run(async): ' + Cmd);
  TThread.CreateAnonymousThread(
    procedure
    var Output: string;
    begin
      Output:= '';
      try
        RunAndCaptureStdout(Cmd, Output, 180000);
      except
        on E: Exception do Output:= 'drag-lint: command failed: ' + E.ClassName + ': ' + E.Message;
      end;
      if Trim(Output) = '' then Output:= '(no output -- the command produced nothing)';
      try TFile.WriteAllText(OutPath, Output); except end;
      TThread.Queue(nil, procedure begin DLOpenInEditor(OutPath); end);
    end).Start;
end; // procedure

function DLActivePas(out APath: string): Boolean;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
begin
  Result:= False; APath:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  APath:= EV.Buffer.FileName;
  Result:= (APath <> '') and SameText(ExtractFileExt(APath), '.pas');
end;

{ Prompt for a qualified name, pre-filled with the identifier at the cursor. }
function DLAskQName(out AQ: string): Boolean;
begin
  AQ:= IdentifierAtCursor;
  Result:= InputQuery('drag-lint', 'Qualified name (Unit.Type.Member):', AQ) and (Trim(AQ) <> '');
  { v0.46 review (security/robustness): a double-quote would break the
    "%s"-quoted engine argument. Reject it rather than mis-parse the command. }
  if Result and (Pos('"', AQ) > 0) then
  begin
    ShowMessage('drag-lint: the name must not contain a double-quote (").');
    Result:= False;
  end;
end;

function DLUriToPath(const AUri: string): string;
begin
  Result:= AUri;
  if Result.StartsWith('file:///') then Result:= Copy(Result, 9, MaxInt)
  else if Result.StartsWith('file://') then Result:= Copy(Result, 8, MaxInt);
  Result:= StringReplace(Result, '/'  , '\', [rfReplaceAll]);
  Result:= StringReplace(Result, '%20', ' ', [rfReplaceAll]);
end;

{ Open the SOURCE (code) view of AFile and jump to ALine (mirrors the
  Find-Usages nav fix so a form unit lands on the .pas, not the designer). }
procedure DLNavigateToSource(const AFile: string; ALine: Integer);
var
  MS  : IOTAModuleServices;
  Mod_: IOTAModule        ;
  Ed  : IOTAEditor        ;
  Src : IOTASourceEditor  ;
  ESS : IOTAEditorServices;
  EV  : IOTAEditView      ;
  i   : Integer           ;
begin
  if (AFile = '') or not FileExists(AFile) then Exit;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then
  begin
    Mod_:= MS.OpenModule(AFile);
    if Mod_ <> nil then
      for i:= 0 to Mod_.GetModuleFileCount - 1 do
      begin
        Ed:= Mod_.GetModuleFileEditor(i);
        if Supports(Ed, IOTASourceEditor, Src) then begin Src.Show; Break; end;
      end;
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV:= ESS.TopView;
    if (EV <> nil) and (ALine > 0) then
    begin
      EV.Position.GotoLine(ALine);
      EV.Paint;
    end;
  end;
end; // procedure

{ v8: resolve a qualified name to its absolute source path via the index -- the
  query JSON now carries "file". '' if not found in ADb. Used by the hover
  def-row click so it navigates for project AND library defs while the popup
  display stays clean (the path is resolved on click, never shown). }
function DLResolveQnameFile(const AQName, ADb: string): string;
var
  Cmd   : string     ;
  Output: string     ;
  V     : TJSONValue ;
  Arr   : TJSONArray ;
  Obj   : TJSONObject;
  P     : Integer    ;
begin
  Result:= '';
  if (AQName = '') or (ADb = '') or not FileExists(ADb) then Exit;
  Cmd:= Format('"%s" query --qname "%s" --db "%s" --json', [DLExe64, AQName, ADb]);
  Output:= '';
  RunAndCaptureStdout(Cmd, Output, 15000);
  P:= Pos('[', Output); { skip any "(loaded defaults...)" banner prefix }
  if P <= 0 then Exit;
  Output:= Copy(Output, P, MaxInt);
  V:= nil;
  try V:= TJSONObject.ParseJSONValue(Output); except V:= nil; end;
  try
    if (V is TJSONArray) then
    begin
      Arr:= V as TJSONArray;
      if Arr.Count > 0 then
      begin
        Obj:= Arr.Items[0] as TJSONObject;
        Obj.TryGetValue<string>('file', Result);
      end;
    end;
  finally
    V.Free;
  end;
end; // function

{ ---- Uses & Dependencies ---- }

procedure InvokeCircularUses(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no active project index (DB) found.'); Exit; end;
  DLRunReport(Format('cycles --db "%s" --plan --edges --causes --format text', [Db]), 'drag-lint-circular-uses.txt');
end;

procedure InvokeUsesAudit(Sender: TObject);
var
  Pas, Db: string; MS: IOTAModuleServices;
begin
  if not DLActivePas(Pas) then begin ShowMessage('drag-lint: open a .pas unit first.'); Exit; end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index (DB).'); Exit; end;
  DLRunReport(Format('uses-audit "%s" --db "%s" --format text', [Pas, Db]), 'drag-lint-uses-audit.txt');
end;

procedure InvokeUsesFix(Sender: TObject);
var
  Pas, Db, Proj: string; MS: IOTAModuleServices;
begin
  if not DLActivePas(Pas) then begin ShowMessage('drag-lint: open a .pas unit first.'); Exit; end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  Db:= ResolvePrimaryIndexDb; Proj:= GetActiveProjectFile;
  if (Db = '') or (Proj = '') then begin ShowMessage('drag-lint: no project/index found.'); Exit; end;
  { report-only preview (no --apply): compiler-verified moves + removals. }
  DLRunReport(Format('uses-fix "%s" --project "%s" --db "%s"', [Pas, Proj, Db]), 'drag-lint-uses-fix-preview.txt');
end;

procedure InvokeReconcileProject(Sender: TObject);
var
  Proj: string; MS: IOTAModuleServices;
begin
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  Proj:= GetActiveProjectFile;
  if Proj = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;
  DLRunReport(Format('reconcile-project "%s"', [Proj]), 'drag-lint-reconcile.txt');
end;

procedure InvokeUsesReportCsv(Sender: TObject);
var
  Db    : string;
  OutCsv: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  OutCsv:= TPath.Combine(TPath.GetTempPath, 'drag-lint-uses-report.csv');
  DLRunReport(Format('uses-report --output "%s" --db "%s"', [OutCsv, Db]), 'drag-lint-uses-report-log.txt');
  DLOpenInEditor(OutCsv);
end;

procedure InvokeImpact(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('impact --qname "%s" --db "%s" --depth 3 --format text', [Q, Db]), 'drag-lint-impact.txt');
end;

{ v8: Spring4D DI + DFM event wiring for the symbol under the cursor. For an
  interface name: implementations (+lifetime) + resolve-sites. For a form/class:
  its methods bound to component events. Put the caret on the interface or form
  name before invoking. }
procedure InvokeWiring(Sender: TObject);
var
  Q    : string;
  Db   : string;
  DbArg: string;
begin
  if not DLAskQName(Q) then Exit;
  { Pass --db only when the conventional <Project>.sqlite exists; otherwise omit
    it and let the engine resolve the index from the manifest (like hover/find-
    usages), which handles projects whose index lives elsewhere (e.g. ORM3 ->
    ...\ORM3\drag-lint.sqlite, not ...\CLIENT\Micronite2027.sqlite). }
  Db:= ResolvePrimaryIndexDb;
  if (Db <> '') and FileExists(Db) then DbArg:= Format(' --db "%s"', [Db])
  else DbArg:= '';
  DLRunReport(Format('wiring --qname "%s"%s --format text', [Q, DbArg]), 'drag-lint-wiring.txt');
end;

/// <summary>Reverse call tree for the symbol under the cursor: who calls X, and who
/// calls them, N-deep, with call sites and cycle markers. Text into an editor buffer
/// (graphical in-dock rendering is a filed TODO).</summary>
procedure InvokeReverseCallTree(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('reverse-calltree --qname "%s" --db "%s" --depth 3 --format text', [Q, Db]), 'drag-lint-reverse-calltree.txt');
end;

/// <summary>Reverse call tree for the symbol under the cursor, emitted to the IDE
/// Messages window: each node is a clickable AddToolMessage (double-click jumps to
/// the call site). Runs reverse-calltree --format json off-thread (mirrors
/// DLRunReport's async discipline: background CreateProcess + capture, then
/// TThread.Queue marshals the OTA IOTAMessageServices calls back onto the main
/// thread, since OTA is not thread-safe), then posts the tree on the main thread.
/// Complements InvokeReverseCallTree (which writes text to an editor buffer).
/// Text convention: each row reads "&lt;node.qname> calls &lt;parent.qname>" (a node in
/// "callers" is a caller of its parent), indented 2 spaces per tree depth; the
/// clickable target (file/line) is the NODE's own call site -- where its call into
/// the parent lives. Robust to a missing/empty file (still posts the row, just
/// non-navigable), a nil parse (posts a friendly title message), and an empty
/// callers list (root has no callers -- posts "no callers found").</summary>
procedure InvokeReverseCallTreeMessages(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;

  var Cmd: string:= Format('"%s" reverse-calltree --qname "%s" --db "%s" --depth 3 --format json', [DLExe64, Q, Db]);
  DLT('menu', 'run(async): ' + Cmd);
  TThread.CreateAnonymousThread(
    procedure
    var
      Output: string;
    begin
      Output:= '';
      try
        RunAndCaptureStdout(Cmd, Output, 180000);
      except
        on E: Exception do Output:= '';
      end;

      var Slice: string:= SliceJsonBracket(Output, '{', '}');
      var V: TJSONValue:= nil;
      if Slice <> '' then
        try V:= TJSONObject.ParseJSONValue(Slice); except V:= nil; end;

      { v.b: capture the parsed value (or nil) and marshal the OTA Messages calls
        onto the main thread. V is freed inside the queued procedure -- it must
        stay alive until then (anonymous-method closure keeps the reference). }
      TThread.Queue(nil,
        procedure
        var
          MS: IOTAMessageServices;

          { Recursively walk a "callers" array, posting one clickable row per
            node. AParentQName is the caller's callee (the node it calls into);
            ADepth drives the 2-space indent. }
          procedure WalkCallers(const AArr: TJSONArray; const AParentQName: string; ADepth: Integer; var APosted: Integer);
          var
            i        : Integer;
            NodeObj  : TJSONObject;
            NodeQName: string;
            NodeFile : string;
            NodeLine : Integer;
            NodeCycle: Boolean;
            Indent   : string;
            Text     : string;
            Kids     : TJSONArray;
          begin
            if AArr = nil then Exit;
            Indent:= StringOfChar(' ', ADepth * 2);
            for i:= 0 to AArr.Count - 1 do
            begin
              if not (AArr.Items[i] is TJSONObject) then Continue;
              NodeObj:= AArr.Items[i] as TJSONObject;
              NodeQName:= NodeObj.GetValue<string> ('qname', '');
              NodeFile := NodeObj.GetValue<string> ('file' , '');
              NodeLine := NodeObj.GetValue<Integer>('line' , 0 );
              NodeCycle:= False;
              NodeObj.TryGetValue<Boolean>('cycle', NodeCycle);
              Text:= Format('%s%s calls %s', [Indent, NodeQName, AParentQName]);
              if NodeCycle then Text:= Text + ' (cycle)';
              { Guard: an empty/missing file still gets a row (non-navigable)
                rather than being silently dropped -- the tree stays complete. }
              MS.AddToolMessage(NodeFile, Text, 'drag-lint', NodeLine, 0);
              Inc(APosted);
              if NodeCycle then Continue; // cycle marker only -- already expanded elsewhere
              if NodeObj.TryGetValue<TJSONArray>('callers', Kids) then
                WalkCallers(Kids, NodeQName, ADepth + 1, APosted);
            end;
          end;

        begin
          try
            if not Supports(BorlandIDEServices, IOTAMessageServices, MS) then Exit;
            try
              if V = nil then
              begin
                MS.AddTitleMessage(Format('drag-lint: reverse call tree for %s -- no result (symbol not found or command failed).', [Q]));
                Exit;
              end;
              if not (V is TJSONObject) then
              begin
                MS.AddTitleMessage(Format('drag-lint: reverse call tree for %s -- unexpected response.', [Q]));
                Exit;
              end;
              var Root: TJSONObject;
              if not (V as TJSONObject).TryGetValue<TJSONObject>('root', Root) then
              begin
                MS.AddTitleMessage(Format('drag-lint: reverse call tree for %s -- no result.', [Q]));
                Exit;
              end;
              var RootQName: string:= Root.GetValue<string>('qname', Q);
              MS.AddTitleMessage(Format('drag-lint: reverse call tree for %s -- double-click a row to jump to the call site.', [RootQName]));
              var Posted: Integer:= 0;
              var Callers: TJSONArray;
              if Root.TryGetValue<TJSONArray>('callers', Callers) then
                WalkCallers(Callers, RootQName, 1, Posted);
              if Posted = 0 then
                MS.AddTitleMessage(Format('drag-lint: no callers found for %s.', [RootQName]));
            except
              on E: Exception do MS.AddTitleMessage('drag-lint: reverse call tree failed: ' + E.ClassName + ': ' + E.Message);
            end;
          finally
            V.Free;
          end;
        end);
    end).Start;
end;

/// <summary>Shells reverse-calltree --format json twice (callers, then --direction
/// callees) for AQName against ADb on a background thread, slices each stdout to
/// its JSON object, then marshals onto the main thread via TThread.Queue to show
/// the dock and call GDockFrame.PopulateButterfly with both slices. Factored out
/// of InvokeButterfly so other entry points (e.g. the Structure form's context
/// menu) can jump straight to the butterfly view without re-prompting for a
/// qname. Safe with a nil GDockFrame (no-op) or empty/failed CLI output
/// (PopulateButterfly renders "(0)" roots rather than erroring).</summary>
procedure ShowButterflyForQName(const AQName, ADb: string);
var
  CmdC, CmdF: string;
begin
  CmdC:= Format('"%s" reverse-calltree --qname "%s" --db "%s" --depth 3 --format json', [DLExe64, AQName, ADb]);
  CmdF:= Format('"%s" reverse-calltree --qname "%s" --db "%s" --depth 3 --format json --direction callees', [DLExe64, AQName, ADb]);
  DLT('menu', 'butterfly(async): ' + CmdC + ' | ' + CmdF);
  TThread.CreateAnonymousThread(
    procedure
    var
      CallersOut, CalleesOut: string;
    begin
      CallersOut:= ''; CalleesOut:= '';
      try RunAndCaptureStdout(CmdC, CallersOut, 180000); except on E: Exception do CallersOut:= ''; end;
      try RunAndCaptureStdout(CmdF, CalleesOut, 180000); except on E: Exception do CalleesOut:= ''; end;

      var SC: string:= SliceJsonBracket(CallersOut, '{', '}');
      var SF: string:= SliceJsonBracket(CalleesOut, '{', '}');
      TThread.Queue(nil,
        procedure
        begin
          { TDragLintDockFrame/GDockFrame live in DockForm.pas's implementation
            section and are not visible here -- ShowDragLintDockButterfly is the
            interface-exported wrapper (mirrors ShowDragLintDockLintOptions) that
            shows the dock and calls GDockFrame.PopulateButterfly internally. }
          ShowDragLintDockButterfly(AQName, SC, SF);
        end);
    end).Start;
end;

/// <summary>Builds the butterfly call graph (callers + callees) for the symbol
/// under the caret (prompts for a qname) and shows it in the dock's Call Graph
/// tab. Shells drag-lint reverse-calltree --format json twice (callers, then
/// --direction callees) on a background thread, then marshals both JSON docs to
/// the dock via TThread.Queue. Bound to Ctrl+Alt+B and a Uses &amp; Dependencies
/// menu item.</summary>
procedure InvokeButterfly(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  ShowButterflyForQName(Q, Db);
end;

{ Resolve the library index beside the plugin (where RTL/VCL/DevExpress units are
  indexed) -- needed to map an undeclared identifier to the unit that defines it. }
function DLLibraryDb: string;
var
  Dir: string;
begin
  Dir:= ExtractFilePath(GetModuleName(HInstance));
  Result:= Dir + 'library-Win32.sqlite';
  if not FileExists(Result) then Result:= Dir + 'library-Win64.sqlite';
  if not FileExists(Result) then Result:= Dir + 'drag-lint-library.sqlite';
end;

{ Pull the unit name out of a diagnostic message like
  "...Undeclared identifier 'Foo' -- add unit Bar to the uses clause". }
function DLExtractAddUnit(const AMsg: string): string;
var
  P   : Integer;
  Q   : Integer;
  Tail: string ;
const
  MARK = 'add unit ';
begin
  Result:= '';
  P:= Pos(MARK, LowerCase(AMsg));
  if P = 0 then Exit;
  Tail:= Copy(AMsg, P + Length(MARK), MaxInt);
  Q:= 1;
  while (Q <= Length(Tail)) and CharInSet(Tail[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(Q);
  Result:= Copy(Tail, 1, Q - 1);
end;

{ Shared: insert AUnits into the IMPLEMENTATION uses clause (append to an
  existing one before its ';', else create "uses ...;" after 'implementation').
  Returns the inserted, comma-joined list in AInserted. Undoable. }
function DLAddUnitsToImplUses(const AUnits: array of string; out AInserted: string): Boolean;
var
  Src     : string            ;
  FileName: string            ;
  T       : string            ;
  Combined: string            ;
  Lines   : TArray<string>    ;
  ImplIdx : Integer           ;
  UsesIdx : Integer           ;
  SemiIdx : Integer           ;
  ColN    : Integer           ;
  i       : Integer           ;
  ESS     : IOTAEditorServices;
  EV      : IOTAEditView      ;
  EPos    : IOTAEditPosition  ;

  function CleanLine(const ALn: string): string;
  begin
    Result:= StringReplace(ALn, #13, '', [rfReplaceAll]);
  end;

{ v0.46 review (L): replace the content of line comments, brace comments, and
    paren-star comments with spaces (same length, so column positions are
    preserved), so a semicolon inside a comment is not mistaken for the
    uses-clause terminator. Single-line scope, which covers the realistic cases. }
  function BlankComments(const ALn: string): string;
  var
    K: Integer;
    N: Integer;
  begin
    Result:= ALn;
    N:= Length(Result);
    K:= 1;
    while K <= N do
    begin
      if (K < N) and (Result[K] = '/') and (Result[K + 1] = '/') then
      begin
        while K <= N do begin Result[K]:= ' '; Inc(K); end;
      end
      else if Result[K] = '{' then
      begin
        while (K <= N) and (Result[K] <> '}') do begin Result[K]:= ' '; Inc(K); end;
        if K <= N then begin Result[K]:= ' '; Inc(K); end;
      end
      else if (K < N) and (Result[K] = '(') and (Result[K + 1] = '*') then
      begin
        Result[K]:= ' '; Result[K + 1]:= ' '; Inc(K, 2);
        while K <= N do
        begin
          if (K < N) and (Result[K] = '*') and (Result[K + 1] = ')') then
          begin Result[K]:= ' '; Result[K + 1]:= ' '; Inc(K, 2); Break; end;
          Result[K]:= ' '; Inc(K);
        end;
      end
      else Inc(K);
    end; // while
  end; // function

begin
  Result:= False; AInserted:= '';
  Combined:= '';
  for i:= 0 to High(AUnits) do
    if Trim(AUnits[i]) <> '' then
    begin
      if Combined <> '' then Combined:= Combined + ', ';
      Combined:= Combined + Trim(AUnits[i]);
    end;
  if Combined = '' then Exit;

  Src:= ReadActiveBufferText(FileName);
  Lines:= Src.Split([#10]);
  ImplIdx:= -1;
  for i:= 0 to High(Lines) do
    if SameText(Trim(CleanLine(Lines[i])), 'implementation') then
    begin ImplIdx:= i; Break; end;
  if ImplIdx < 0 then Exit;

  UsesIdx:= -1;
  for i:= ImplIdx + 1 to High(Lines) do
  begin
    T:= LowerCase(Trim(CleanLine(Lines[i])));
    if T = '' then Continue;
    if (T = 'uses') or (Copy(T, 1, 5) = 'uses ') or (Copy(T, 1, 5) = 'uses,') then UsesIdx:= i;
    Break;
  end;

  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if EV = nil then Exit;
  EPos:= EV.Position;

  if UsesIdx >= 0 then
  begin
    SemiIdx:= -1;
    for i:= UsesIdx to High(Lines) do
      if System.Pos(';', BlankComments(CleanLine(Lines[i]))) > 0 then begin SemiIdx:= i; Break; end;
    if SemiIdx < 0 then Exit;
    ColN:= System.Pos(';', BlankComments(CleanLine(Lines[SemiIdx])));
    EPos.Move(SemiIdx + 1, ColN);
    EPos.InsertText(', ' + Combined);
  end
  else
  begin
    EPos.Move(ImplIdx + 2, 1);
    EPos.InsertText('uses ' + Combined + ';' + sLineBreak);
  end;
  AInserted:= Combined;
  Result   := True;
end; // begin

{ v0.46: resolve & (optionally) insert the units that fix undeclared-identifier
  errors. Runs check-unit --resolve-uses against the LIBRARY index, collects the
  suggested units, and on confirmation inserts them into the implementation uses
  clause via an undoable editor write. }
procedure InvokeSuggestUses(Sender: TObject);
var
  Pas     : string            ;
  Proj    : string            ;
  LibDb   : string            ;
  Cmd     : string            ;
  Output  : string            ;
  MS      : IOTAModuleServices;
  V       : TJSONValue        ;
  Arr     : TJSONArray        ;
  Obj     : TJSONObject       ;
  i       : Integer           ;
  U       : string            ;
  Combined: string            ;
  MsgList : string            ;
  Units   : TStringList       ;
begin
  if not DLActivePas(Pas) then begin ShowMessage('drag-lint: open a .pas unit first.'); Exit; end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  Proj := GetActiveProjectFile;
  LibDb:= DLLibraryDb;
  if not FileExists(LibDb) then
  begin
    ShowMessage('drag-lint: library index not found beside the plugin '#13#10 + '(needed to resolve which unit defines a symbol).');
    Exit;
  end;

  Cmd:= Format('"%s" check-unit "%s" --resolve-uses --db "%s" --format json', [DLExe64, Pas, LibDb]);
  if Proj <> '' then Cmd:= Cmd + Format(' --project "%s"', [Proj]);
  DLT('uses', 'suggest-missing: ' + Cmd);
  Output:= '';
  RunAndCaptureStdout(Cmd, Output, 90000);

  Units:= TStringList.Create;
  try
    Units.Sorted    := True;
    Units.Duplicates:= dupIgnore;
    V:= nil;
    try V:= TJSONObject.ParseJSONValue(Output); except V:= nil; end;
    try
      if V is TJSONArray then
      begin
        Arr:= V as TJSONArray;
        for i:= 0 to Arr.Count - 1 do
          if Arr.Items[i] is TJSONObject then
          begin
            Obj:= Arr.Items[i] as TJSONObject;
            U:= '';
            if Obj.TryGetValue<string>('addUnit', U) and (Trim(U) <> '') then Units.Add(Trim(U));
          end;
      end;
    finally
      V.Free;
    end; // try

    DLT('uses', Format('suggest-missing: %d unit(s) [%s]', [Units.Count, Units.CommaText]));
    if Units.Count = 0 then
    begin
      ShowMessage('drag-lint: no missing units to add.'#13#10 + '(No undeclared-identifier errors, or the symbols could not be resolved '#13#10 +
        'from the library index. Tip: build the project first so dependencies '#13#10 + 'resolve from DCUs.)');
      Exit;
    end;

    MsgList:= Units.CommaText;
    if MessageDlg(
      Format('drag-lint resolved %d missing unit(s):'#13#10#13#10'%s'#13#10#13#10 + 'Add them to the IMPLEMENTATION uses clause?', [Units.Count, MsgList]), mtConfirmation,
      [mbYes, mbNo], 0) <> mrYes then Exit;

    if DLAddUnitsToImplUses(Units.ToStringArray, Combined) then
    begin
      DLT('uses', 'inserted: ' + Combined);
      ShowMessage('drag-lint: added to the implementation uses clause:'#13#10 + Combined);
    end
    else ShowMessage('drag-lint: could not locate the implementation uses clause.'#13#10 + 'Add manually: ' + MsgList);
  finally
    Units.Free;
  end; // try
end; // procedure

{ Find the unit that fixes the undeclared identifier on the caret line: first
  from a cached diagnostic message ("add unit X"), else by running check-unit
  --resolve-uses now and matching the caret line. }
function DLCursorUndeclaredUnit(out AUnit: string): Boolean;
var
  ESS      : IOTAEditorServices         ;
  EV       : IOTAEditView               ;
  FileName : string                     ;
  Pas      : string                     ;
  Proj     : string                     ;
  LibDb    : string                     ;
  Cmd      : string                     ;
  Output   : string                     ;
  U        : string                     ;
  CaretRow0: Integer                    ;
  i        : Integer                    ;
  FLine    : Integer                    ;
  Diags    : TArray<TDragLintDiagnostic>;
  D        : TDragLintDiagnostic        ;
  MS       : IOTAModuleServices         ;
  V        : TJSONValue                 ;
  Arr      : TJSONArray                 ;
  Obj      : TJSONObject                ;
begin
  Result:= False; AUnit:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  FileName:= EV.Buffer.FileName;
  CaretRow0:= EV.Position.Row - 1; { cache is 0-based }
  if CaretRow0 < 0 then CaretRow0:= 0;

  { 1) fast path: a cached diagnostic on the caret line already carries the
       "add unit X" suggestion (the live semantic check produced it). }
  Diags:= Cache.GetForLine(FileName, CaretRow0);
  for D in Diags do
  begin
    U:= DLExtractAddUnit(D.Message);
    if U <> '' then begin AUnit:= U; DLT('uses', 'quickfix: cache -> ' + U); Exit(True); end;
  end;

  { 2) fallback: run check-unit --resolve-uses now and match the caret line. }
  if not SameText(ExtractFileExt(FileName), '.pas') then Exit;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  Pas:= FileName; Proj:= GetActiveProjectFile; LibDb:= DLLibraryDb;
  if not FileExists(LibDb) then Exit;
  Cmd:= Format('"%s" check-unit "%s" --resolve-uses --db "%s" --format json', [DLExe64, Pas, LibDb]);
  if Proj <> '' then Cmd:= Cmd + Format(' --project "%s"', [Proj]);
  Output:= '';
  RunAndCaptureStdout(Cmd, Output, 90000);
  V:= nil;
  try V:= TJSONObject.ParseJSONValue(Output); except V:= nil; end;
  try
    if V is TJSONArray then
    begin
      Arr:= V as TJSONArray;
      { prefer the finding on the caret line }
      for i:= 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
        begin
          Obj:= Arr.Items[i] as TJSONObject; U:= ''; FLine:= -1;
          Obj.TryGetValue<string>('addUnit', U);
          Obj.TryGetValue<Integer>('line', FLine);
          if (Trim(U) <> '') and (FLine = CaretRow0 + 1) then
          begin AUnit:= Trim(U); DLT('uses', 'quickfix: engine(line) -> ' + AUnit); Exit(True); end;
        end;
      { v0.46 review (M): NO "first resolvable in the unit" fallback for the
        CURSOR quick-fix -- it could insert a unit unrelated to the symbol under
        the caret (especially when an uncompiled project yields many spurious
        undeclared ids). If nothing matches the caret line, return False and let
        InvokeQuickFixUses tell the user to put the caret on the offending line.
        The whole-unit InvokeSuggestUses keeps its own broader behaviour. }
    end;
  finally
    V.Free;
  end; // try
end; // function

{ Quick-fix: add the unit for the undeclared identifier on the caret line. }
procedure InvokeQuickFixUses(Sender: TObject);
var
  U  : string;
  Ins: string;
begin
  if not DLCursorUndeclaredUnit(U) then
  begin
    ShowMessage('drag-lint: no missing-unit suggestion for the line at the cursor.'#13#10 +
      '(Put the caret on the line with the undeclared identifier; build the project first so deps resolve.)');
    Exit;
  end;
  if DLAddUnitsToImplUses([U], Ins) then ShowMessage('drag-lint: added unit to the implementation uses clause: ' + Ins)
  else ShowMessage('drag-lint: could not locate the implementation uses clause. Add manually: ' + U);
end;

{ Pull the unit name out of a compiler H2443 message like
  "Inline function 'MessageDlg' has not been expanded because unit 'System.UITypes'
  is not specified in USES list" -- the unit is the SECOND single-quoted token. }
function DLExtractInlineHintUnit(const AMsg: string): string;
var
  q1a, q1b, q2a, q2b: Integer;
begin
  Result:= '';
  { only act on the H2443 shape to avoid mis-parsing unrelated quoted messages }
  if (Pos('H2443', AMsg) = 0) and (Pos('not been expanded', LowerCase(AMsg)) = 0) then Exit;
  q1a:= Pos('''', AMsg);                       if q1a = 0 then Exit;
  q1b:= PosEx('''', AMsg, q1a + 1);            if q1b = 0 then Exit;
  q2a:= PosEx('''', AMsg, q1b + 1);            if q2a = 0 then Exit;
  q2b:= PosEx('''', AMsg, q2a + 1);            if q2b = 0 then Exit;
  Result:= Trim(Copy(AMsg, q2a + 1, q2b - q2a - 1));
end;

{ Quick-fix for compiler hint H2443 ("inline function not expanded because unit U
  not in USES"): find the H2443 diagnostic on the caret line, pull the unit U out
  of its message, and add U to the implementation uses clause -- reusing the same
  undoable insertion as the undeclared-identifier quick-fix. Requires the caret to
  be on the flagged line and the H2443 finding to be cached (compile-check must
  have run -- e.g. after a save or Compile & Diagnose). }
procedure InvokeQuickFixInlineHintUses(Sender: TObject);
var
  ESS      : IOTAEditorServices         ;
  EV       : IOTAEditView               ;
  FileName : string                     ;
  CaretRow0: Integer                    ;
  Diags    : TArray<TDragLintDiagnostic>;
  D        : TDragLintDiagnostic        ;
  U        : string                     ;
  Ins      : string                     ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then begin ShowMessage('drag-lint: no active editor view.'); Exit; end;
  FileName := EV.Buffer.FileName;
  CaretRow0:= EV.Position.Row - 1; { cache is 0-based }
  if CaretRow0 < 0 then CaretRow0:= 0;

  U:= '';
  Diags:= Cache.GetForLine(FileName, CaretRow0);
  for D in Diags do
  begin
    U:= DLExtractInlineHintUnit(D.Message);
    if U <> '' then Break;
  end;

  if U = '' then
  begin
    ShowMessage('drag-lint: no H2443 inline-hint on the line at the cursor.'#13#10 +
      '(Put the caret on the flagged line; compile the unit first so the H2443 hint is cached.)');
    Exit;
  end;
  DLT('uses', 'quickfix-H2443: ' + U);
  if DLAddUnitsToImplUses([U], Ins) then ShowMessage('drag-lint: added inline-hint unit to the implementation uses clause: ' + Ins)
  else ShowMessage('drag-lint: could not locate the implementation uses clause. Add manually: ' + U);
end;

{ Parse a single-field declaration line "  Name: TType;" into its parts. Returns
  False for anything that is not exactly one field (e.g. "A, B: T" multi-name
  lists, records with '=', or lines with trailing directives) -- those are left
  for the user so we never mangle a declaration we do not fully understand. }
function DLParseSingleFieldLine(const ALine: string; out AIndent, AName, AType: string): Boolean;
var
  S      : string ;
  ColonP : Integer;
  SemiP  : Integer;
  i      : Integer;
begin
  Result:= False; AIndent:= ''; AName:= ''; AType:= '';
  S:= ALine;
  { capture leading whitespace verbatim so the rewrite keeps the indentation }
  i:= 1;
  while (i <= Length(S)) and CharInSet(S[i], [' ', #9]) do Inc(i);
  AIndent:= Copy(S, 1, i - 1);
  S:= Copy(S, i, MaxInt);
  { reject comment lines and non-field shapes early }
  if (S = '') or S.StartsWith('//') or S.StartsWith('{') then Exit;
  ColonP:= Pos(':', S);
  if ColonP = 0 then Exit;
  AName:= Trim(Copy(S, 1, ColonP - 1));
  { a multi-name list, an '=' const/typed-const, or a non-identifier name -> bail }
  if (AName = '') or (Pos(',', AName) > 0) or (Pos('=', S) > 0) then Exit;
  for i:= 1 to Length(AName) do
    if not CharInSet(AName[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  S:= Copy(S, ColonP + 1, MaxInt);
  SemiP:= Pos(';', S);
  if SemiP = 0 then Exit;
  AType:= Trim(Copy(S, 1, SemiP - 1));
  { reject array/record/anonymous inline types (would need a backing decl we
    cannot safely synthesise) and anything after the ';' }
  if (AType = '') or (Pos(' ', AType) > 0) then Exit;
  Result:= True;
end;

/// <summary>Quick-fix for the 'public-field' lint: convert the single public data
/// field on the caret line into a read/write property backed by a new private
/// field. "Name: TType;" becomes "FName: TType;" + "property Name: TType read
/// FName write FName;". Same-named property means NO call sites need editing --
/// existing reads/writes transparently route through it. Undoable (single editor
/// write). Conservative: only a lone "Name: TType;" is converted; multi-name
/// lists, inline array/record types, or already-property lines are refused with a
/// message. The backing FName stays in the current section -- move it to a
/// 'private'/'strict private' block if you want the field hidden too.</summary>
procedure InvokeConvertFieldToProperty(Sender: TObject);
var
  ESS   : IOTAEditorServices;
  EV    : IOTAEditView      ;
  EPos  : IOTAEditPosition  ;
  Src   : string            ;
  FileName: string          ;
  Lines : TArray<string>    ;
  Row0  : Integer           ;
  RawLn : string            ;
  Indent, Name, Typ: string ;
  NewText: string           ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then begin ShowMessage('drag-lint: no active editor view.'); Exit; end;
  FileName:= EV.Buffer.FileName;
  Row0:= EV.Position.Row - 1;
  if Row0 < 0 then Row0:= 0;

  Src:= ReadActiveBufferText(FileName);
  Lines:= Src.Replace(#13, '').Split([#10]);
  if (Row0 < 0) or (Row0 > High(Lines)) then begin ShowMessage('drag-lint: caret line out of range.'); Exit; end;
  RawLn:= Lines[Row0];

  if not DLParseSingleFieldLine(RawLn, Indent, Name, Typ) then
  begin
    ShowMessage('drag-lint: the caret line is not a simple "Name: TType;" field.'#13#10 +
      '(Put the caret on the public field line. Multi-name lists and inline '#13#10 +
      'array/record types are not auto-converted.)');
    Exit;
  end;
  NewText:=
    Format('%sF%s: %s;', [Indent, Name, Typ]) + sLineBreak +
    Format('%sproperty %s: %s read F%s write F%s;', [Indent, Name, Typ, Name, Name]);

  EPos:= EV.Position;
  { replace the whole caret line: go to col 1, select to end of line, overwrite }
  EPos.Move(Row0 + 1, 1);
  EPos.MoveEOL;
  { column count of the original line (may include trailing spaces) }
  var EndCol: Integer:= EPos.Column;
  EPos.Move(Row0 + 1, 1);
  EPos.Delete(EndCol - 1);          { remove the old field text, keep the line }
  EPos.InsertText(NewText);
  DLT('field2prop', Format('%s: %s -> property (F%s)', [Name, Typ, Name]));
  ShowMessage(Format('drag-lint: converted "%s" to a property backed by F%s.'#13#10 +
    '(Move F%s into a private/strict-private section to fully hide it.)', [Name, Name, Name]));
end;

{ Modal single-choice picker built at runtime (no .dfm -- avoids the design-time
  EResNotFound trap). Shows AItems in a listbox; returns the chosen 0-based index
  or -1 if cancelled. Double-click or OK confirms. Used by Go-to-Definition when a
  symbol has more than one definition (e.g. the string helper ToUpper vs the
  System.Character overloads). }
function DLPickFromList(const ACaption, APrompt: string; const AItems: array of string): Integer;
var
  Frm  : TForm    ;
  Lbl  : TLabel   ;
  Lst  : TListBox ;
  BtnOK: TButton  ;
  BtnNo: TButton  ;
  i    : Integer  ;
begin
  Result:= -1;
  Frm:= TForm.CreateNew(nil);
  try
    Frm.Caption   := ACaption;
    Frm.Position  := poScreenCenter;
    Frm.BorderStyle:= bsDialog;
    Frm.ClientWidth := 640;
    Frm.ClientHeight:= 320;

    Lbl:= TLabel.Create(Frm);
    Lbl.Parent  := Frm;
    Lbl.Left    := 12;
    Lbl.Top     := 10;
    Lbl.Caption := APrompt;

    Lst:= TListBox.Create(Frm);
    Lst.Parent  := Frm;
    Lst.Left    := 12;
    Lst.Top     := 32;
    Lst.Width   := Frm.ClientWidth  - 24;
    Lst.Height  := Frm.ClientHeight - 32 - 48;
    Lst.Anchors := [akLeft, akTop, akRight, akBottom];
    for i:= 0 to High(AItems) do Lst.Items.Add(AItems[i]);
    if Lst.Items.Count > 0 then Lst.ItemIndex:= 0;

    BtnOK:= TButton.Create(Frm);
    BtnOK.Parent  := Frm;
    BtnOK.Caption := 'Go To';
    BtnOK.Default := True;
    BtnOK.ModalResult:= mrOk;
    BtnOK.Width   := 90;
    BtnOK.Top     := Frm.ClientHeight - 38;
    BtnOK.Left    := Frm.ClientWidth  - 2 * 90 - 24;
    BtnOK.Anchors := [akRight, akBottom];

    BtnNo:= TButton.Create(Frm);
    BtnNo.Parent  := Frm;
    BtnNo.Caption := 'Cancel';
    BtnNo.Cancel  := True;
    BtnNo.ModalResult:= mrCancel;
    BtnNo.Width   := 90;
    BtnNo.Top     := Frm.ClientHeight - 38;
    BtnNo.Left    := Frm.ClientWidth  - 90 - 12;
    BtnNo.Anchors := [akRight, akBottom];

    if (Frm.ShowModal = mrOk) and (Lst.ItemIndex >= 0) then Result:= Lst.ItemIndex;
  finally
    Frm.Free;
  end;
end;

{ Navigate to one LSP Location (uri + range/start) from the definition array. }
procedure DLGotoLocation(const ALoc: TJSONObject);
var
  Rng    : TJSONObject;
  St     : TJSONObject;
  DefPath: string     ;
  DefLine: Integer    ;
begin
  DefPath:= ''; DefLine:= 1;
  ALoc.TryGetValue<string>('uri', DefPath);
  DefPath:= DLUriToPath(DefPath);
  if ALoc.TryGetValue<TJSONObject>('range', Rng) and Rng.TryGetValue<TJSONObject>('start', St) then DefLine:= St.GetValue<Integer>('line') + 1;
  DLNavigateToSource(DefPath, DefLine);
end;

procedure InvokeGoToDefinition(Sender: TObject);
var
  Uri    : string; Line, Col: Integer;
  Client : TDragLintLspClient        ;
  Params : TJSONObject               ;
  Resp   : TJSONValue                ;
  ResVal : TJSONValue                ;
  Arr    : TJSONArray                ;
  Loc    : TJSONObject               ;
  Rng    : TJSONObject               ;
  St     : TJSONObject               ;
  i      : Integer                   ;
  DefPath: string; DefLn: Integer    ;
  Labels : TArray<string>            ;
  Chosen : Integer                   ;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then begin ShowMessage('drag-lint: no active editor view.'); Exit; end;
  Client:= EnsureLspClient;
  if Client = nil then Exit;
  Params:= MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp:= Client.Request('textDocument/definition', Params, 5000);
  finally
    Params.Free;
  end;
  if Resp = nil then begin ShowMessage('drag-lint: definition lookup timed out.'); Exit; end;
  try
    Arr:= nil;
    if Resp is TJSONArray then Arr:= Resp as TJSONArray
    else if (Resp is TJSONObject) and (Resp as TJSONObject).TryGetValue<TJSONValue>('result', ResVal) and (ResVal is TJSONArray) then Arr:= ResVal as TJSONArray;
    if (Arr = nil) or (Arr.Count = 0) then begin ShowMessage('drag-lint: definition not found.'); Exit; end;

    { One definition -> jump straight there (unchanged behaviour). More than one
      (e.g. ToUpper: TStringHelper + TCharHelper + TCharacter + ...) -> let the
      user pick which, instead of silently taking the first. The LSP Location only
      carries uri+range, so each row is labelled "unit(line,col)". }
    if Arr.Count = 1 then
    begin
      DLGotoLocation(Arr.Items[0] as TJSONObject);
      Exit;
    end;

    SetLength(Labels, Arr.Count);
    for i:= 0 to Arr.Count - 1 do
    begin
      Loc:= Arr.Items[i] as TJSONObject;
      DefPath:= ''; DefLn:= 1;
      Loc.TryGetValue<string>('uri', DefPath);
      DefPath:= DLUriToPath(DefPath);
      if Loc.TryGetValue<TJSONObject>('range', Rng) and Rng.TryGetValue<TJSONObject>('start', St) then DefLn:= St.GetValue<Integer>('line') + 1;
      Labels[i]:= Format('%s  (line %d)', [ExtractFileName(DefPath), DefLn]);
    end;

    Chosen:= DLPickFromList('drag-lint: Go To Definition',
      Format('%d definitions found -- choose one:', [Arr.Count]), Labels);
    if Chosen >= 0 then DLGotoLocation(Arr.Items[Chosen] as TJSONObject);
  finally
    Resp.Free;
  end; // try
end; // procedure

{ ---- Inspect / Quality / Generate / Export ---- }

procedure InvokeClassSurface(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('surface --qname "%s" --db "%s" --format text', [Q, Db]), 'drag-lint-surface.txt');
end;

procedure InvokeSymbolSlice(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('slice --qname "%s" --db "%s" --format text', [Q, Db]), 'drag-lint-slice.txt');
end;

procedure InvokeTypeAtCursor(Sender: TObject);
var
  ESS: IOTAEditorServices; EV: IOTAEditView; Db, Pas: string; Row, ColN: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then begin ShowMessage('drag-lint: no active editor.'); Exit; end;
  Pas:= EV.Buffer.FileName;
  Row:= EV.Position.Row; ColN:= EV.Position.Column;
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('typeat "%s:%d:%d" --db "%s" --format text', [Pas, Row, ColN, Db]), 'drag-lint-typeat.txt');
end;

procedure InvokeFindDeadCode(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('find-deadcode --db "%s"', [Db]), 'drag-lint-deadcode.txt');
end;

procedure InvokeScanTodos(Sender: TObject);
var
  Proj: string;
  Dir : string;
begin
  Proj:= GetActiveProjectFile;
  if Proj <> '' then Dir:= ExtractFilePath(Proj) else Dir:= '';
  if Dir = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;
  DLRunReport(Format('todos "%s"', [ExcludeTrailingPathDelimiter(Dir)]), 'drag-lint-todos.txt');
end;

procedure InvokeCompilerHints(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('query hints --db "%s"', [Db]), 'drag-lint-hints.txt');
end;

procedure InvokeGenerateDocs(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('generate-docs --qname "%s" --format xmldoc --db "%s"', [Q, Db]), 'drag-lint-docstub.txt');
end;

{ v1.2: whole-project auto-document -- writes managed DocInsight into every
  public decl of the active project's compile closure (facts-only, --apply with a
  .bak per modified file). No preview/confirm dialog: apply-directly-with-backup is
  the deliberate design (git + .bak are the safety net).
  SELF-FRESHENING + LSP-SAFE: runs THROUGH THE JOB QUEUE (LSP stopped in OnPreRun so
  the reindex can take the DB's WAL lock -- a live LSP connection would silently
  corrupt it) a 3-step batch: (1) index the project INCREMENTALLY -- index is
  mtime/sha-based, so it auto-detects stale/absent files, re-parses only those, and
  CREATES the DB if missing (no prompts) -> document then applies on CURRENT line
  numbers; (2) document --apply, which writes the comments and SHIFTS lines; (3)
  index AGAIN -- the apply modified the files, so the index is now stale, and
  re-freshening it keeps hover / lint / LSP correct afterward. A temp .bat sequences
  the three (avoids inline cmd-quoting hazards); '|| exit /b 1' stops on failure. }
procedure InvokeAutoDocumentProject(Sender: TObject);
var
  Proj, Db, ProjDir, Plat, Bat, BatPath, OutPath: string;
  MS: IOTAModuleServices;
begin
  Proj:= GetActiveProjectFile;
  if Proj = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;
  { ResolvePrimaryIndexDb, NOT GetActiveProjectDb -- same defect as
    InvokeReindexProject, and as Task 6's refresh-findings before it. This
    batch's THIRD step re-indexes precisely so hover/lint/LSP stay correct after
    --apply shifts line numbers; aimed at <projname>.sqlite that re-freshening
    lands in a DB no consumer reads, leaving the LSP stale on exactly the files
    just rewritten -- the one outcome the third step exists to prevent. }
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  ProjDir:= ExcludeTrailingPathDelimiter(ExtractFilePath(Proj));
  Plat   := GetActiveProjectPlatform; // Win32/Win64 -> correct conditional-define resolution

  Bat:=
    '@echo off'#13#10 +
    Format('"%s" index "%s" --db "%s" --platform %s || exit /b 1'#13#10, [DLExe64, ProjDir, Db, Plat]) +
    Format('"%s" document --project "%s" --apply --db "%s" || exit /b 1'#13#10, [DLExe64, Proj, Db]) +
    Format('"%s" index "%s" --db "%s" --platform %s'#13#10, [DLExe64, ProjDir, Db, Plat]);
  BatPath:= TPath.Combine(TPath.GetTempPath, 'drag-lint-autodocument.bat');
  try TFile.WriteAllText(BatPath, Bat, TEncoding.ANSI); except end;
  OutPath:= TPath.Combine(TPath.GetTempPath, 'drag-lint-autodocument.txt');

  DLT('menu', 'enqueue(autodoc: reindex->document->reindex): ' + BatPath);
  var Job: TDragLintJob:= TDragLintJob.Create;
  Job.Kind       := jkReindex;
  Job.Title      := 'Auto-Document ' + ChangeFileExt(ExtractFileName(Proj), '');
  Job.CoalesceKey:= 'autodoc:' + LowerCase(Db);
  Job.CmdLine    := Format('cmd.exe /c "%s"', [BatPath]);
  Job.TimeoutMs  := 600000;
  Job.OnPreRun   :=
    procedure
    begin
      if GLspClient <> nil then begin GLspClient.Stop; FreeAndNil(GLspClient); end;
    end;
  Job.OnDone     :=
    procedure(AExit: Integer; AOut: string)
    var S: string;
    begin
      S:= AOut;
      if Trim(S) = '' then S:= '(no output)';
      if AExit <> 0 then S:= Format('[auto-document exited %d]'#13#10, [AExit]) + S;
      try TFile.WriteAllText(OutPath, S); except end;
      DLOpenInEditor(OutPath);
    end;
  JobQueue.Enqueue(Job);
end;

procedure InvokeGenerateTest(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  DLRunReport(Format('generate-test --qname "%s" --framework dunitx --db "%s"', [Q, Db]), 'drag-lint-teststub.txt');
end;

procedure InvokeExportEnums(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('export enums --db "%s" --format delphi-const', [Db]), 'drag-lint-enums.txt');
end;

procedure InvokeTopSymbols(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('top --db "%s" --by fanin --limit 50', [Db]), 'drag-lint-top.txt');
end;

procedure InvokeFindUndocumented(Sender: TObject);
var
  Db: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  DLRunReport(Format('query find --no-docs --public --db "%s"', [Db]), 'drag-lint-undocumented.txt');
end;

procedure InvokeExportGraphDot(Sender: TObject);
var
  Db  : string;
  Outp: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  Outp:= TPath.Combine(TPath.GetTempPath, 'drag-lint-graph.dot');
  DLRunReport(Format('graph --db "%s" --format dot --output "%s"', [Db, Outp]), 'drag-lint-graph-log.txt');
  DLOpenInEditor(Outp);
end;

procedure InvokeExportObsidian(Sender: TObject);
var
  Db    : string;
  Dir   : string;
  Cmd   : string;
  Output: string;
begin
  Db:= ResolvePrimaryIndexDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  Dir:= TPath.Combine(TPath.GetTempPath, 'drag-lint-obsidian');
  try TDirectory.CreateDirectory(Dir); except end;
  Cmd:= Format('"%s" export obsidian --db "%s" --output-dir "%s"', [DLExe64, Db, Dir]);
  DLT('menu', 'run: ' + Cmd);
  Output:= '';
  RunAndCaptureStdout(Cmd, Output, 180000);
  ShellExecute(0, 'open', PChar(Dir), nil, nil, SW_SHOWNORMAL);
  ShowMessage('drag-lint: exported Obsidian notes to'#13#10 + Dir);
end;

procedure InvokeReindexProject(Sender: TObject);
var
  Cmd    : string;
  OutPath: string;
  Db, Proj: string; MS: IOTAModuleServices;
begin
  { The write target is resolved from the ACTIVE PROJECT FILE, exactly -- NOT via
    ResolvePrimaryIndexDb, and NOT via GetActiveProjectDb.

    GetActiveProjectDb (ChangeFileExt(proj, '.sqlite')) was the original defect:
    on C:\Projects\DataCopy this item built DataCopy.sqlite while every consumer
    queried DataCopy\drag-lint.sqlite -- an hour of indexing that could not change
    one answer the IDE gave.

    ResolvePrimaryIndexDb fixed that but resolves by FOLDER prefix, which cannot
    tell sibling projects apart. Since the manifest was converted to per-project
    closure sections, several folders hold more than one (ORM3\PACKAGE:
    Interfaces + TestMicroniteObjects; DataCopy: DataCopy + SortTest; also
    TableTools, YADF, DragLintGraph\src\pkg). All of them fold to one identical
    key and the first section silently wins. Harmless while indexing was additive
    -- DATA LOSS now that this command passes --rebuild, which clears the whole
    DB: the wrong index is emptied and refilled with another project's closure,
    and the right one is never written.

    So: exact match, and REFUSE on anything less than one unambiguous owner. A
    wrong DB under --rebuild destroys an index; refusing costs a click. }
  Proj:= GetActiveProjectFile;
  if Proj = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;

  Db:= '';
  var Claimants: TArray<string>:= nil;
  case ManifestDbForProject(Proj, Db, Claimants) of
    pdmUnique: ; { fall through to the rebuild }
    pdmAmbiguous:
      begin
        var Names: string:= '';
        for var C: string in Claimants do Names:= Names + #13#10 + '    ' + C;
        ShowMessage(Format(
          'drag-lint: %d index sections claim this project, so there is no single'#13#10 +
          'index to rebuild:'#13#10 + '%s'#13#10#13#10 +
          'Project: %s'#13#10#13#10 +
          'Nothing was changed. Rebuilding would have cleared one of these indexes'#13#10 +
          'and refilled it with the wrong project. Edit drag-lint.json so exactly'#13#10 +
          'one section includes this project file, then run this again.',
          [Length(Claimants), Names, Proj]));
        Exit;
      end;
    else
      begin
        ShowMessage(Format(
          'drag-lint: no index section owns this project, so there is nothing to'#13#10 +
          'rebuild.'#13#10#13#10 +
          'Project: %s'#13#10 +
          'Manifest: %s'#13#10#13#10 +
          'Nothing was changed -- deliberately: rebuilding a nearby index instead'#13#10 +
          'would clear source that belongs to a different project. Add a section'#13#10 +
          'for this project to the manifest (or check the manifest parses), then'#13#10 +
          'run this again.',
          [Proj, ManifestPathBesideEngine]));
        Exit;
      end;
  end; // case

  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  { ONE pass, both axes stated explicitly: SCOPE = the active project's .dproj
    COMPILE CLOSURE (--project), MODE = full REBUILD (--rebuild: the engine calls
    ClearAllFiles, so every indexed file is dropped before the walk, and
    --force-reparse is implied).

    This REPLACES the old two-pass folder+closure .bat, and the replacement is not
    optional: --rebuild clears the WHOLE DB, so a second --rebuild pass would
    discard the first pass's work, and a folder pass followed by a closure pass
    would leave the DB holding strictly more than the section it belongs to.
    Producing exactly what `index --all --only <section>` produces is the point --
    the manifest section for a .dproj include is a CLOSURE section, so a menu
    reindex that also swept the project FOLDER made the IDE-built DB diverge from
    the manifest-built one for the same section.

    The cost is deliberate and worth naming: loose Demo/Test units that sit in the
    project folder but are NOT in the compile closure are no longer indexed by this
    action (the old '(a) project FOLDER' pass covered them). That is what
    project-scoped means; a folder walk is still available as `index <dir>`.

    --rebuild is also the ONLY mechanism that drops rows for source that has left
    the SCOPE (a unit removed from the .dproj). --prune only knows about source
    that has left the DISK -- which is why the incremental 'refresh' sibling of
    this item is deliberately NOT offered until out-of-scope eviction lands. }
  var Plat: string:= GetActiveProjectPlatform;
  Cmd:= Format('"%s" index --project "%s" --db "%s" --platform %s --rebuild',
               [DLExe64, Proj, Db, Plat]);
  OutPath:= TPath.Combine(TPath.GetTempPath, 'drag-lint-reindex.txt');
  DLT('menu', 'enqueue(rebuild+lsp-restart): ' + Cmd);
  { v0.65.1: run through the R2 job queue so a reindex never collides with a
    concurrent lint-all / forms-csv on the project DB. The LSP must be stopped on
    the UI thread BEFORE the indexer takes the exclusive WAL lock to drop the FTS5
    sync triggers (a live LSP connection blocks that lock -> DROP TRIGGER fails
    silently and later string_literal inserts crash) -- so it is the job's
    OnPreRun (the queue runs it via TThread.Synchronize). LSP restarts lazily on
    the next hover/completion query. }
  var RJob: TDragLintJob:= TDragLintJob.Create;
  RJob.Kind       := jkReindex;
  RJob.Title      := 'Rebuild Index ' + ChangeFileExt(ExtractFileName(Proj), '');
  RJob.CoalesceKey:= 'reindex:' + LowerCase(Db);
  RJob.CmdLine    := Cmd;
  RJob.TimeoutMs  := 600000;   { --rebuild force-reparses the whole closure, so EVERY
                                 run costs what only the first run used to. NOTE: for
                                 a non-streaming job this value is advisory -- ProcRun
                                 .RunCaptureStdout drains the pipe to EOF (which blocks
                                 until the child exits) BEFORE it waits, and never
                                 terminates the child. }
  RJob.OnPreRun   :=
    procedure
    begin
      if GLspClient <> nil then begin GLspClient.Stop; FreeAndNil(GLspClient); end;
    end;
  RJob.OnDone     :=
    procedure(AExit: Integer; AOut: string)
    var S: string;
    begin
      S:= AOut;
      if Trim(S) = '' then S:= '(no output)';
      try TFile.WriteAllText(OutPath, S); except end;
      DLOpenInEditor(OutPath);
    end;
  JobQueue.Enqueue(RJob);
end;

procedure InvokeResolveDbs(Sender: TObject);
begin
  DLRunReport('resolve-dbs --platform win64', 'drag-lint-resolve-dbs.txt');
end;

procedure InvokeLibraryDrift(Sender: TObject);
begin
  DLRunReport('library-drift', 'drag-lint-library-drift.txt');
end;

const
  LINTALL_MSG_CAP = 2000; { max clickable findings posted per run (avoid flooding the pane) }

{ v0.65.1: parse the lint-all report and post each finding to the IDE Messages
  view as a CLICKABLE tool message -- double-click jumps to file:line. Capped so a
  huge run (ORM3 saw 30k findings) cannot flood/freeze the pane; the full list
  stays in the opened report. Report line format (CLI DoLintAll):
    <fullpath>:<line>:<col>  [<severity>] <rule-id>: <message>
  Parsed right-to-left by ':' so the drive-letter colon in 'C:\...' is safe. }
procedure PostLintReportToMessages(const AReportPath: string);
var
  MS   : IOTAMessageServices;
  Lines: TArray<string>;
  Ln, Loc, Loc2, Rest, FName: string;
  P, C1, C2, Line, Col, Posted, Total: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, MS) then Exit;
  if not FileExists(AReportPath) then Exit;
  try Lines:= TFile.ReadAllLines(AReportPath); except Exit; end;
  Posted:= 0;
  Total := 0;
  for Ln in Lines do
  begin
    P:= Pos('  [', Ln); { two spaces before "[severity]" separate location from the rest }
    if P < 2 then Continue;
    Inc(Total);
    if Posted >= LINTALL_MSG_CAP then Continue;
    Loc := Copy(Ln, 1, P - 1);
    Rest:= Copy(Ln, P + 2, MaxInt);
    C2:= LastDelimiter(':', Loc);
    if C2 < 2 then Continue;
    Col := StrToIntDef(Copy(Loc, C2 + 1, MaxInt), 0);
    Loc2:= Copy(Loc, 1, C2 - 1);
    C1:= LastDelimiter(':', Loc2);
    if C1 < 2 then Continue;
    Line := StrToIntDef(Copy(Loc2, C1 + 1, MaxInt), 0);
    FName:= Copy(Loc2, 1, C1 - 1);
    if (FName = '') or (Line <= 0) then Continue;
    MS.AddToolMessage(FName, Rest, 'drag-lint', Line, Col);
    Inc(Posted);
  end;
  if Total > Posted then
    MS.AddTitleMessage(Format('drag-lint: %d of %d findings posted as clickable messages (capped) -- full list in %s', [Posted, Total, AReportPath]))
  else if Posted > 0 then
    MS.AddTitleMessage(Format('drag-lint: %d clickable finding(s) -- double-click a line to jump to source.', [Posted]))
  else
    MS.AddTitleMessage('drag-lint: no findings.');
end;

{ v0.63: run lint-all on the active project in the background, then open the
  generated report and post a one-line summary to the Messages view. Mirrors
  InvokeReindexProject (async thread + capture + TThread.Queue marshal-back).
  lint-all exit codes: 0 = no findings, 1 = findings (both success), 2 = error. }
procedure InvokeLintAll(Sender: TObject);
var
  Proj, Db, LibDb, OutPath, Cmd: string;
  MS: IOTAModuleServices;
begin
  Proj:= GetActiveProjectFile;
  if Proj = '' then begin ShowMessage('drag-lint: no active project.'); Exit; end;
  { Resolve the index DB the manifest-aware way -- the index often lives in a
    manifest outDir (e.g. ...\DB\ORM3\CLIENT\Micronite2027.sqlite), NOT next to
    the .dproj, so the simple <dproj>.sqlite path misses it (false "no index"). }
  Db:= '';
  try
    for var Dbc in ResolveActiveIndexDbs(LoadSettings) do
      if FileExists(Dbc) then begin Db:= Dbc; Break; end;
  except
    Db:= '';
  end;
  if (Db = '') or not FileExists(Db) then Db:= ManifestDbForFile(Proj);
  if (Db = '') or not FileExists(Db) then Db:= GetActiveProjectDb;
  if (Db = '') or not FileExists(Db) then
  begin
    ShowMessage('drag-lint: no index found for this project. ' +
      'Run drag-lint > Index && Maintenance > Rebuild Index for This Project first.');
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
  OutPath:= TPath.Combine(ExtractFilePath(Proj), 'lint-report-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt');
  { lint-all takes the FIRST existing --db as the project index and the SECOND as
    the platform library index. Passing only the project DB left the library
    source empty, so used-unit-not-resolvable flagged every third-party and RTL
    unit the project legitimately uses -- 420 of 1871 findings on DataCopy, 333 of
    them pure noise. Append library-<active platform>.sqlite so the rule can tell
    "unit the compiler resolves from the library path" from "unit that resolves
    nowhere". Omitted silently when the library DB has not been built. }
  LibDb:= '';
  try LibDb:= GetPlatformAwareLibraryDbPath(LoadSettings); except LibDb:= ''; end;
  if (LibDb <> '') and FileExists(LibDb) then
    Cmd:= Format('"%s" lint-all --db "%s" --db "%s" --project "%s" --out "%s"', [DLExe64, Db, LibDb, Proj, OutPath])
  else
    Cmd:= Format('"%s" lint-all --db "%s" --project "%s" --out "%s"', [DLExe64, Db, Proj, OutPath]);
  DLT('menu', 'enqueue(lint-all): ' + Cmd);
  { v0.65.1: enqueue on the R2 job queue (serialized with reindex / forms-csv);
    the drag-lint dock status bar shows live % while it runs. The queue parses
    the "lint-all: [i/N] NN% file" progress lines internally to drive the bar, so
    the per-percent Messages spam is gone -- only the start line + final summary
    are posted (still useful when the dock is closed). }
  var MsgStart: IOTAMessageServices;
  if Supports(BorlandIDEServices, IOTAMessageServices, MsgStart) then
    MsgStart.AddTitleMessage('drag-lint: lint-all queued -- live progress in the drag-lint dock status bar; the report opens here when done.');
  var LJob: TDragLintJob:= TDragLintJob.Create;
  LJob.Kind       := jkLintAll;
  LJob.Title      := 'Lint All ' + ChangeFileExt(ExtractFileName(Proj), '');
  LJob.CoalesceKey:= 'lint-all:' + LowerCase(Db);
  LJob.CmdLine    := Cmd;
  LJob.Streaming  := True;
  LJob.OnDone     :=
    procedure(AExit: Integer; AOut: string)
    var
      MsgSvc : IOTAMessageServices;
      Summary: string;
    begin
      if AExit = 2 then begin ShowMessage('drag-lint: lint-all failed (no index?). See plugin log.'); Exit; end;
      if FileExists(OutPath) then
      begin
        PostLintReportToMessages(OutPath); { post each finding as a clickable Messages entry }
        DLOpenInEditor(OutPath);           { + open the full report }
      end;
      Summary:= Trim(AOut);
      if Summary <> '' then Summary:= Trim(Copy(Summary, LastDelimiter(#10, Summary) + 1, MaxInt));
      if Supports(BorlandIDEServices, IOTAMessageServices, MsgSvc) then
        MsgSvc.AddTitleMessage('drag-lint ' + Summary);
    end;
  JobQueue.Enqueue(LJob);
end;

procedure RegisterDragLintMenu;
var
  Services: INTAServices;
  RootMenu: TMenuItem   ;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) then Exit;

  AutoPullStagedExe;

  GMenuItems:= TObjectList<TMenuItem         >.Create(True);
  GWrappers := TObjectList<TMenuActionWrapper>.Create(True);

  RootMenu:= TMenuItem.Create(nil);
  RootMenu.Caption:= 'drag-lint';
  { Top-level IDE menu (like TableTools): insert directly into the main menu bar
    instead of nesting under Tools.  RootMenu has NO component owner (Create(nil))
    and is added only as a menu CHILD here; GMenuItems is its sole owner and frees
    it on unload, at which point TMenuItem.Destroy removes it from the menu bar --
    so teardown stays single-owner (no double-free).  Falls back to the Tools
    submenu if the IDE main menu is unavailable. }
  if Services.MainMenu <> nil then Services.MainMenu.Items.Add(RootMenu)
  else Services.AddActionMenu('ToolsMenu', nil, RootMenu, True, True);
  GMenuItems.Add(RootMenu);

  { Full Compile Sweep pinned at the very top -- the most-used action (recompile
    all units + refresh compiler_findings, then auto-refresh the open file). }
  AddWrappedItem(RootMenu, 'Full Compile Sweep'         , InvokeFullCompileSweep);
  AddSeparator(RootMenu);
  { v0.42: daily-use actions on top; diagnostics & test harness bunched below
    a separator so the everyday items aren't lost among them. }
  AddWrappedItem(RootMenu, 'drag-lint Panel (dockable)', InvokeDockPanel  );
  AddWrappedItem(RootMenu, 'drag-lint Graph (dockable)', InvokeGraphWindow);
  AddSeparator(RootMenu);
  AddWrappedItem(RootMenu, 'Hover at Cursor'            , InvokeHover           );
  AddWrappedItem(RootMenu, 'Go to Definition'           , InvokeGoToDefinition  );
  AddWrappedItem(RootMenu, 'Show Completion'            , InvokeCompletion      );
  AddWrappedItem(RootMenu, 'Show Signature Help'        , InvokeSignatureHelp   );
  AddWrappedItem(RootMenu, 'Find Usages...'             , InvokeFindUsages      );
  AddWrappedItem(RootMenu, 'Symbol Search...'           , InvokeSymbolSearch    );
  AddWrappedItem(RootMenu, 'Show Structure'             , InvokeShowStructure   );
  AddWrappedItem(RootMenu, 'Rename Symbol...'           , InvokeRename          );
  AddWrappedItem(RootMenu, 'Format with YADF'           , InvokeFormatYadf      );
  AddWrappedItem(RootMenu, 'Format Whole Project with YADF...', InvokeFormatProjectYadf);
  AddWrappedItem(RootMenu, 'Generate Test Helper CSV...', InvokeGenerateFormsCsv);
  AddWrappedItem(RootMenu, 'drag-lint Options...'       , InvokeOptionsDialog   );

  { v0.46: Uses & Dependencies submenu }
  AddSeparator(RootMenu);
  var SubUses: TMenuItem:= TMenuItem.Create(RootMenu);
  SubUses.Caption:= 'Uses && Dependencies';
  RootMenu.Add(SubUses);
  AddWrappedItem(SubUses, 'Circular Uses Report (cycles + fix plan)...'                , InvokeCircularUses    );
  AddWrappedItem(SubUses, 'Uses Audit -- interface->impl moves + unused (this unit)...', InvokeUsesAudit       );
  AddWrappedItem(SubUses, 'Uses Cleanup Preview (compiler-verified, this unit)...'     , InvokeUsesFix         );
  AddWrappedItem(SubUses, 'Reconcile Project Members (.dpr/.dproj)...'                 , InvokeReconcileProject);
  AddWrappedItem(SubUses, 'Uses Report (CSV)...'                                       , InvokeUsesReportCsv   );
  AddWrappedItem(SubUses, 'Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)'  , InvokeQuickFixUses    );
  AddWrappedItem(SubUses, 'Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor'      , InvokeQuickFixInlineHintUses);
  AddWrappedItem(SubUses, 'Quick-Fix: Convert Public Field to Property at Cursor'      , InvokeConvertFieldToProperty);
  AddWrappedItem(SubUses, 'Add Missing Units to uses (whole unit)...'                  , InvokeSuggestUses     );
  AddWrappedItem(SubUses, 'Impact / Blast Radius (symbol)...'                          , InvokeImpact          );
  AddWrappedItem(SubUses, 'Show Wiring (Spring4D DI + DFM events)...'                  , InvokeWiring          );
  AddWrappedItem(SubUses, 'Reverse Call Tree (who calls this, N-deep)...'              , InvokeReverseCallTree );
  AddWrappedItem(SubUses, 'Reverse Call Tree (clickable, Messages window)...'          , InvokeReverseCallTreeMessages);
  AddWrappedItem(SubUses, 'Call Graph (Butterfly)...'                                  , InvokeButterfly       );

  { v0.46: Inspect Symbol submenu }
  var SubInspect: TMenuItem:= TMenuItem.Create(RootMenu);
  SubInspect.Caption:= 'Inspect Symbol';
  RootMenu.Add(SubInspect);
  AddWrappedItem(SubInspect, 'Class Surface...', InvokeClassSurface);
  AddWrappedItem(SubInspect, 'Symbol Slice...' , InvokeSymbolSlice );
  AddWrappedItem(SubInspect, 'Type at Cursor'  , InvokeTypeAtCursor);

  { v0.46: Code Quality submenu }
  var SubQuality: TMenuItem:= TMenuItem.Create(RootMenu);
  SubQuality.Caption:= 'Code Quality';
  RootMenu.Add(SubQuality);
  AddWrappedItem(SubQuality, 'Run Lint All (Full Report)...', InvokeLintAll         );
  AddWrappedItem(SubQuality, 'Find Dead Code...'            , InvokeFindDeadCode    );
  AddWrappedItem(SubQuality, 'Find Undocumented (public)...', InvokeFindUndocumented);
  AddWrappedItem(SubQuality, 'Scan TODOs / FIXMEs...'       , InvokeScanTodos       );
  AddWrappedItem(SubQuality, 'Compiler Hints...'            , InvokeCompilerHints   );
  AddWrappedItem(SubQuality, 'Top Symbols (fan-in)...'      , InvokeTopSymbols      );

  { v0.46: Generate / Export submenu }
  var SubGen: TMenuItem:= TMenuItem.Create(RootMenu);
  SubGen.Caption:= 'Generate && Export';
  RootMenu.Add(SubGen);
  AddWrappedItem(SubGen, 'Doc Comment Stub (symbol)...'  , InvokeGenerateDocs  );
  AddWrappedItem(SubGen, 'Auto-Document Whole Project...', InvokeAutoDocumentProject);
  AddWrappedItem(SubGen, 'Unit Test Stub (symbol)...'    , InvokeGenerateTest  );
  AddWrappedItem(SubGen, 'Export Enums (Delphi const)...', InvokeExportEnums   );
  AddWrappedItem(SubGen, 'Export Graph (DOT)...'         , InvokeExportGraphDot);
  AddWrappedItem(SubGen, 'Export to Obsidian...'         , InvokeExportObsidian);

  { v0.46: Index && Maintenance submenu }
  var SubMaint: TMenuItem:= TMenuItem.Create(RootMenu);
  SubMaint.Caption:= 'Index && Maintenance';
  RootMenu.Add(SubMaint);
  { Named "Rebuild Index", not "Reindex": the action CLEARS the project's index
    and re-parses its whole compile closure. A "Refresh Index" (incremental
    recompile) item is expected to join it once out-of-scope eviction lands, so
    the two need names a user can tell apart BEFORE clicking the destructive one. }
  AddWrappedItem(SubMaint, 'Rebuild Index for This Project', InvokeReindexProject);
  AddWrappedItem(SubMaint, 'Show Resolved DBs (debug)...', InvokeResolveDbs    );
  AddWrappedItem(SubMaint, 'Library Drift Check...'      , InvokeLibraryDrift  );

  { ---- Diagnostics & Tests (alpha) ---- }
  AddSeparator(RootMenu);
  AddSectionHeader(RootMenu, 'Diagnostics && Tests');
  AddWrappedItem(RootMenu, 'Run Diagnostics (didSave)'      , InvokeDiagnostics    );
  AddWrappedItem(RootMenu, 'Run AST Checks'                 , InvokeRunAstChecks   );
  AddWrappedItem(RootMenu, 'Lint Buffer (Unsaved)'          , InvokeLintBuffer     );
  AddWrappedItem(RootMenu, 'Copy Diagnostics (Current File)', InvokeCopyDiagnostics);
  AddWrappedItem(RootMenu, 'Compile && Diagnose'            , InvokeCompileDiagnose);
  { Full Compile Sweep lives at the very TOP of the menu now (pinned); not repeated
    here to avoid a duplicate entry. }
  AddWrappedItem(RootMenu, 'Compile Buffer (unsaved)'       , InvokeGhostCheck     );
  AddWrappedItem(RootMenu, 'Recover Buffer-Compile Files'   , InvokeGhostRecover   );
  AddWrappedItem(RootMenu, 'Import Build Log...'            , InvokeImportLog      );
  AddWrappedItem(RootMenu, 'Open Plugin Log'                , InvokeOpenLog        );

  { v0.42: also surface the dockable panel under View > Tool Windows. This item
    can NOT go through AddWrappedItem/GMenuItems: its Owner ends up being the
    IDE's Tool Windows menu item, so our GMenuItems teardown never frees it and
    it lingers after uninstall (-> duplicate + a stale entry that calls into the
    unloaded BPL). Instead: purge ANY pre-existing 'drag-lint' child first
    (catches stale entries from earlier installs, named or not), create one
    tracked item in GDockToolWinItem, and free it explicitly on teardown. }
  var ToolWin: TMenuItem:= FindViewToolWindowsMenu(Services);
  if ToolWin <> nil then
  begin
    RemoveChildrenByCaption(ToolWin, 'drag-lint'      );
    RemoveChildrenByCaption(ToolWin, 'drag-lint Graph');
    GDockToolWinItem:= TMenuItem.Create(ToolWin);
    GDockToolWinItem.Caption:= 'drag-lint';
    var DockWrap: TMenuActionWrapper:= TMenuActionWrapper.Create(InvokeDockPanel);
    GWrappers.Add(DockWrap);
    GDockToolWinItem.OnClick:= DockWrap.HandleClick;
    ToolWin.Add(GDockToolWinItem);

    { v0.43: second entry for the dedicated Graph window. }
    GGraphToolWinItem:= TMenuItem.Create(ToolWin);
    GGraphToolWinItem.Caption:= 'drag-lint Graph';
    var GraphWrap: TMenuActionWrapper:= TMenuActionWrapper.Create(InvokeGraphWindow);
    GWrappers.Add(GraphWrap);
    GGraphToolWinItem.OnClick:= GraphWrap.HandleClick;
    ToolWin.Add(GGraphToolWinItem);
  end; // if

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
  DragLint.Plugin.SaveNotifier.GAfterSaveDiagHook:= TriggerDiagnosticsOnSave;
  { v0.47: out-of-process compile-on-save -> surfaces compiler errors in the pane. }
  DragLint.Plugin.SaveNotifier.GAfterSaveCompileHook:= TriggerCompileOnSave;
  { Batch E Task 3: butterfly Call Graph tab double-click nav -- DockForm cannot
    uses-import Editor (Editor already uses DockForm) and DLNavigateToSource is
    implementation-private here, so wire it through the same hook pattern as
    the SaveNotifier hooks above. }
  DragLint.Plugin.DockForm.GButterflyNav:= DLNavigateToSource;
  { v0.47: auto-compile the UNSAVED buffer when editing goes idle (AutoCompileBuffer),
    so compiler errors on unsaved code appear without saving or the menu. The runner
    calls this on the main thread; RunGhostCheckAsync is single-flight + restores. }
  DragLint.Plugin.LiveDiagnostics.GIdleGhostCheckHook:=
  function: Boolean
    begin
      Result:= False;
      try Result:= RunGhostCheckAsync(False); except end;
      { Task 6: ADD-alongside spawn on the SAME idle trigger (debounced by
        GHOST_IDLE_MS in LiveDiagnostics.pas -- no new timer here) -- keeps
        compiler_findings fresh as the user edits, not just on save. Detached
        + fire-and-forget, so it cannot slow down or block the ghost-check
        above. '' guards inside SpawnRefreshFindings make this a silent no-op
        when no project is open. }
      try SpawnRefreshFindings(GetActiveProjectFile, ResolvePrimaryIndexDb, False); except end;
    end;
    { v0.47: best-effort crash recovery on startup -- if a project is already open,
    restore any file left overlaid by a crashed ghost-check (no prompt; only posts
    to the Messages pane if it actually recovered something). The "Recover
    Buffer-Compile Files" menu is the reliable manual fallback. }
    try RunGhostRecover(False); except end;

    { v0.42: live edit-time diagnostics (debounced buffer lint via the provider
    registry). }
    StartLiveDiagnostics;

    { v0.46: automatic completion trigger (pops on a typed '.'; debounced). }
    StartAutoComplete;

    { v0.46 lightbulb: clicking "... add unit X to the uses clause" in a diagnostic
    hover popup inserts the unit. }
    DragLint.Plugin.HoverForm.GOnAddUnit:=
    procedure(U: string)
      var Ins: string;
      begin
        if DLAddUnitsToImplUses([U], Ins) then ShowMessage('drag-lint: added unit to the implementation uses clause: ' + Ins)
        else ShowMessage('drag-lint: could not add ' + U + '. Open the .pas and place the caret in it, then retry.');
      end;

      { v8: clicking a definition row in the hover popup navigates to the def's .pas.
    The popup knows only the qname + line; resolve it to an absolute path via the
    index ("file" in query JSON) -- project DB first, then the library DB so
    RTL/VCL/DevExpress defs resolve too -- then open the SOURCE (code) view. The
    popup display stays clean; the path is resolved here, on click. }
      DragLint.Plugin.HoverForm.GOnNavigateToQname:=
      procedure(AQName: string; ALine: Integer)
        var F: string;
        begin
          F:= DLResolveQnameFile(AQName, ResolvePrimaryIndexDb);
          if F = '' then F:= DLResolveQnameFile(AQName, DLLibraryDb);
          if (F <> '') and FileExists(F) then DLNavigateToSource(F, ALine)
          else ShowMessage('drag-lint: could not locate ' + AQName + ' in the project or library index; open it manually.');
        end;

        { TEMP debug telemetry: fresh log per session + record the resolved engine. }
        DLTReset;
        DLT('startup', 'plugin registered; BPL=' + GetModuleName(HInstance));
        DLT(
          'startup',
          'engine beside BPL=' + ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe' + ' (exists=' + BoolToStr(FileExists(ExtractFilePath(GetModuleName(HInstance))
            + 'drag-lint.exe'), True) + ')');
      end; // procedure

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
        FreeAndNil(GDockToolWinItem );
        FreeAndNil(GGraphToolWinItem);
        { Wrappers hold the OnClick method pointers; free them before the menu items }
        FreeAndNil(GWrappers );
        FreeAndNil(GMenuItems);
      end; // procedure

    initialization

finalization
UnregisterDragLintMenu;

end.
