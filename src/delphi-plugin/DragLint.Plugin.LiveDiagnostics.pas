unit DragLint.Plugin.LiveDiagnostics;

{ v0.42: live, edit-time diagnostics that can never hang the IDE.

  Pipeline:
    editor Modified -> NotifyEdit (debounce) -> on idle: snapshot the UNSAVED
    buffer to a temp file -> AggregateDiagnostics() over every registered
    provider (the lint provider below now; an LLM/compiler provider later) ->
    rebuild the file's entry in the DiagnosticCache -> repaint edit views so the
    squiggle painter (EditViewNotifier.PaintLine) shows them.

  Everything runs out-of-process (drag-lint.exe), debounced, and try/except
  guarded, so a slow or failing run only delays a result -- it never freezes the
  editor (the core reliability win over the IDE's in-process Error Insight).

  Status: GLiveStatus reflects what's happening ('Analyzing...', 'N errors,
  M warnings', 'idle') for a Diagnostics status line. }

interface

uses
  System.SysUtils
  ;

procedure StartLiveDiagnostics;
procedure StopLiveDiagnostics;
{ Called from the edit-view notifier's Modified hook. }
procedure NotifyEditDirty;

/// <summary>Reports the surface fingerprint the engine returned for a fan-out
/// run, so a repeated answer can stop the same shape being asked twice.</summary>
/// <param name="AFingerprint">The engine's fingerprint for the last launch.</param>
/// <remarks>Safe to call from the fan-out worker thread -- it marshals to the
/// main thread itself, because the gate is driven from the runner's timer and
/// is deliberately not thread-safe.</remarks>
procedure NotifyFanOutFingerprint(const AFingerprint: string);

/// <summary>The active .pas editor buffer, unsaved text included.</summary>
/// <param name="AFilePath">Receives the buffer's path; '' if there is none.</param>
/// <returns>The buffer text, or '' when no .pas view is active.</returns>
/// <remarks>MAIN THREAD ONLY -- it goes through IOTAEditReader. Exposed because
/// tier 3 must re-read the CURRENT buffer rather than compile the snapshot tier
/// 2 staged minutes earlier.</remarks>
function ActiveBufferSnapshot(out AFilePath: string): string;

var
  GLiveStatus: string = ''; { shown in the dock Diagnostics status line }
  { v0.47: assigned by the Editor unit to RunGhostCheckAsync(False). The runner
    calls it after the buffer has been idle a few seconds (auto-compile the
    UNSAVED buffer so compiler errors like E2003 appear without saving). Returns
    True if the compile actually STARTED, False if one was already running (so the
    runner can retry). nil-safe; kept here (not in Editor) to avoid a uses cycle.
    Called on the MAIN thread. }
  GIdleGhostCheckHook: TFunc<Boolean> = nil;

  { PLAN-lint-tree P2: assigned by the FanOut unit. Called on the MAIN thread
    when the INTERFACE half of the active buffer has changed and then held
    still for FANOUT_IDLE_MS -- i.e. "this edit could break a dependent, go
    and look". The generation is the supersession token: a result arriving for
    anything but the newest generation is stale and must be discarded, which is
    why it is issued HERE, at the launch decision, rather than counted
    independently by the worker.

    Returns True if the fan-out actually started. nil-safe, and nil is the
    normal state until the FanOut unit is wired in -- a plugin without it
    simply never fans out. }
  GFanOutHook: TFunc<string, string, Integer, Boolean> = nil;

implementation

uses
  System.Classes
  , System.JSON
  , System.IOUtils
  , System.Generics.Collections
  , Vcl.ExtCtrls
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.Providers
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.Telemetry
  , { TEMP debug telemetry }
    DragLint.Plugin.EditViewNotifier
  , { v0.47: GGutterAnchorHwnd for forced repaint }
    DragLint.Plugin.Settings
  , DragLint.Plugin.ExeResolver
  , { pure line parser -- split out so a console harness can test it; see
      tests\lintoutputparse\ }
    DragLint.Plugin.LintOutputParse
  , { PLAN-lint-tree P2: the interface/implementation split and the launch
      gate. Pure -- no OTA, no VCL -- so tests\SurfaceSplitTests.dpr exercises
      the whole decision headless. }
    DragLint.Plugin.SurfaceSplit
  ;

const
  DEBOUNCE_MS          = 700; { keystroke->lint (instant feedback) }
  SEMANTIC_DEBOUNCE_MS = 5000; { keystroke->semantic check (compiler; slower) }
  GHOST_IDLE_MS        = 3500; { keystroke->auto ghost-check (full-project compile of the unsaved buffer; heavy, so a longer pause) }
  SWITCH_COMPILE_MS    = 1200; { tab-switch->compile-current-state (debounce so flipping through tabs doesn't spam) }
  { PLAN-lint-tree P2, MEASURED AND BOUNDED by B0(b) 2026-09-10 -- keystroke->
    fan-out. Parse+extract+store runs at ~26 s/MB, so with a ~0.5 s engine spawn
    an ORM3 CLIENT unit costs ~0.75 s at the median, ~1.15 s at p90, ~6.2 s at
    p99 and ~24 s at the largest (VARINSP.PAS, 914 KB). 2000 ms therefore holds
    for ~90% of units, and for the top ~1% supersession is the NORMAL path --
    which is what P1's cancellable spawn is for. Do not raise this to "fix"
    supersession; superseding is the design. }
  FANOUT_IDLE_MS       = 2000;

  { v0.46: append-only diagnostic trace so a "nothing shows" report is conclusive.
  Open via drag-lint > Open Plugin Log is the editor log; THIS file is dedicated
  to the live-diagnostics path: %TEMP%\drag-lint-livediag.log. }
procedure LiveLog(const AMsg: string);
begin
  DLT('livediag', AMsg); { TEMP: route to the shared telemetry log }
end;

{ v0.46: cheap active-editor file name (no buffer read) -- used to auto-lint on
  tab/view switch. }
function ActiveEditorFileName: string;
var
  ES : IOTAEditorServices;
  Buf: IOTAEditBuffer    ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
    if ES = nil then Exit;
    Buf:= ES.TopBuffer;
    if Buf <> nil then Result:= Buf.FileName;
  except
    Result:= '';
  end;
end;

var
  GLastSemanticCheck: Cardinal = 0; { v0.43: throttle semantic to 5s apart }

  { ---------- small process-capture helper ---------- }

function RunCapture(const ACmdLine: string; out AOutput: string; ATimeoutMs: Cardinal): Boolean;
var
  SA       : TSecurityAttributes       ;
  ReadPipe : THandle                   ;
  WritePipe: THandle                   ;
  SI       : TStartupInfoW             ;
  PI       : TProcessInformation       ;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD                     ;
  WideCmd  : string                    ;
  SB       : TStringBuilder            ;
begin
  Result:= False; AOutput:= '';
  SA.nLength:= SizeOf(SA); SA.bInheritHandle:= True; SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags:= STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe; SI.hStdError:= WritePipe;
    SI.hStdInput:= GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine; UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe); Exit;
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
    WaitForSingleObject(PI.hProcess, ATimeoutMs);
    CloseHandle(PI.hProcess); CloseHandle(PI.hThread);
    Result:= True;
  finally
    CloseHandle(ReadPipe);
  end; // try
end; // function

{ ---------- the lint diagnostic provider ---------- }
{ Parses `drag-lint lint <buffer>`'s text output:
    <path>:<line>:<col>  [<severity>] <rule>: <message>             }

type
  TLintDiagnosticProvider = class(TInterfacedObject, IDragLintDiagnosticProvider)
    public
      function Name: string                                                        ;
      function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

  { ---------- the semantic diagnostic provider (compiler-based) ---------- }
  { Runs `drag-lint check-unit <file.pas> --shadow <tempdir> --resolve-uses --db <lib>`
  to report real compiler errors (E2003 Undeclared, F2048, etc.) with suggested units.
  Parsed from JSON output. }

type
  TSemanticDiagnosticProvider = class(TInterfacedObject, IDragLintDiagnosticProvider)
    public
      function Name: string                                                        ;
      function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

function TLintDiagnosticProvider.Name: string;
begin
  Result:= 'lint';
end;

function TLintDiagnosticProvider.GetDiagnostics( const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Cmd    : string                  ;
  Output : string                  ;
  Line   : string                  ;
  Rest   : string                  ;
  Tag    : string                  ;
  Rule   : string                  ;
  Msg    : string                  ;
  Lines  : TStringList             ;
  Acc    : TList<TDragLintDiagItem>;
  D      : TDragLintDiagItem       ;
  i      : Integer                 ;
  p       : Integer                ;
  LineNo  : Integer                ;
  ColNo   : Integer                ;
  Rejected: Integer                ; { non-blank lines that were not findings }
begin
  SetLength(Result, 0);
  if ACtx.ExePath = '' then Exit;
  { v0.46: lint the UNSAVED buffer snapshot when available, so live diagnostics
    (incl. syntax errors typed but not yet saved) match the IDE's Error Insight.
    The earlier GetText short-read that truncated the snapshot is fixed
    (ActiveBufferText reads to EOF), so the buffer is now reliable. Fall back to
    the saved file on disk. }
  var LintTarget: string:= ACtx.BufferPath;
  if (LintTarget = '') or not FileExists(LintTarget) then LintTarget:= ACtx.FilePath;
  if LintTarget = '' then Exit;
  Cmd:= Format('"%s" lint "%s"', [ACtx.ExePath, LintTarget]);
  { THE SNAPSHOT MUST STAND IN FOR THE REAL FILE, AND THE RUN MUST HAVE A DB.

    Both halves of this were missing and together they are why the gutter and
    `lint-all` disagree. The engine decides which index covers a file by asking
    whether the DB CONTAINS that path; LintTarget above is usually
    %TEMP%\drag-lint-live-<tick>.pas, which no index contains, so the store was
    dropped and every store-backed check silently degraded -- measured
    `[flowdb] ... db= store=False fid=0`. On this project's own source that
    manufactured 20 of 23 red used-before-assignment marks, because a record
    local defined by its own Init call cannot be told from a nil dereference
    without the index.

    ManifestDbForFile is asked about ACtx.FilePath, the REAL file: the snapshot
    is in no manifest section, so asking about it would answer '' every time. An
    unresolved DB degrades to exactly the previous behaviour rather than
    failing -- an editor buffer in an unindexed folder must still be linted. }
  if (ACtx.FilePath <> '') and not SameText(LintTarget, ACtx.FilePath) then
    Cmd:= Cmd + Format(' --stand-in-for "%s"', [ACtx.FilePath]);
  var LiveDb: string := '';
  if ACtx.FilePath <> '' then LiveDb:= ManifestDbForFile(ACtx.FilePath);
  if LiveDb <> '' then Cmd:= Cmd + Format(' --db "%s"', [LiveDb]);
  LiveLog(Format('lint: exe=%s target=%s standin=%s db=%s',
    [ACtx.ExePath, LintTarget, ACtx.FilePath, LiveDb]));
  if not RunCapture(Cmd, Output, 8000) then
  begin
    LiveLog('lint: RunCapture FAILED (engine not found / timeout?)');
    Exit;
  end;
  LiveLog(Format('lint: output=%d bytes', [Length(Output)]));

  Rejected:= 0;
  Acc:= TList<TDragLintDiagItem>.Create;
  Lines:= TStringList.Create;
  try
    Lines.Text:= Output;
    for i:= 0 to Lines.Count - 1 do
    begin
      Line:= Lines[i];
      { A line that does not yield a real location is NOT a finding. It used to
        become one, on line 1 of the user's file. }
      if not TryParseFindingLine(Line, LineNo, ColNo, Tag, Rest) then
      begin
        if Trim(Line) <> '' then Inc(Rejected);
        Continue;
      end;
      p:= Pos(':', Rest);
      if p > 0 then
      begin
        Rule:= Trim(Copy(Rest, 1, p - 1));
        Msg:= Trim(Copy(Rest, p + 1, MaxInt));
      end
      else
      begin
        Rule:= ''; Msg:= Rest;
      end;

      D:= Default(TDragLintDiagItem);
      D.FilePath:= ACtx.FilePath; { map back to the real (saved) path }
      D.Line:= LineNo;
      D.Col := ColNo;
      D.EndLine:= D.Line;
      D.EndCol:= D.Col + 1;
      D.Severity:= SeverityFromTag(Tag);
      D.Message:= Msg;
      D.Rule   := Rule;
      D.Source := 'lint';
      Acc.Add(D);
    end; // for
    { Report rejects. The engine prints a note banner and an "N finding(s)"
      summary, so a small non-zero count is normal; a count that TRACKS the
      finding count means the parser is dropping real findings, and that is only
      visible if it is printed. }
    LiveLog(Format('lint: parsed %d finding(s), %d non-finding line(s) rejected',
      [Acc.Count, Rejected]));
    Result:= Acc.ToArray;
  finally
    Lines.Free;
    Acc.Free;
  end; // try
end; // function

{ Semantic diagnostic provider: runs compiler, parses JSON, merges undeclared-id
  suggestions. Uses `check-unit` with shadow + resolve-uses. }
function TSemanticDiagnosticProvider.Name: string;
begin
  Result:= 'semantic';
end;

function TSemanticDiagnosticProvider.GetDiagnostics( const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Cmd      : string                  ;
  Output   : string                  ;
  ShadowDir: string                  ;
  DcuDir   : string                  ;
  JSON     : string                  ;
  JArr     : TJSONArray              ;
  JObj     : TJSONValue              ;
  DObj     : TJSONValue              ;
  D        : TDragLintDiagItem       ;
  Acc      : TList<TDragLintDiagItem>;
  i        : Integer                 ;
begin
  SetLength(Result, 0);
  if (ACtx.BufferPath = '') or (ACtx.ExePath = '') then Exit;

  { v0.43: shadow-overlay semantic check on unsaved buffer (throttled to 5s+).
    Creates a shadow dir with just that one unit, runs check-unit with shadow,
    and parses the JSON result to merge into the diagnostics.
    Requires --db (a project or library db to resolve undeclared symbols).
    Throttled so we don't compile on every keystroke. }

  { skip if less than 5 seconds since last semantic check }
  if (GetTickCount - GLastSemanticCheck < SEMANTIC_DEBOUNCE_MS) then Exit;
  GLastSemanticCheck:= GetTickCount;

  { v0.43: use library DB for resolving undeclared identifiers in semantic checks.
    The project DB is heavier (includes full source) and best left for manual
    queries. The library DB (1.5M symbols, RTL/VCL/Spring4D/DevExpress) gives us
    everything we need for "add unit X to uses" suggestions. }
  JSON:= TPath.Combine(ExtractFilePath(ACtx.ExePath), 'drag-lint-library.sqlite');
  if not FileExists(JSON) then Exit; { no semantic checks without the library db }

  try
    { Create shadow dir with the unsaved file }
    ShadowDir:= TPath.Combine(TPath.GetTempPath, Format('draglint_semantic_%d', [GetTickCount]));
    DcuDir:= TPath.Combine(ShadowDir, 'dcu');
    try
      TDirectory.CreateDirectory(DcuDir);
      TFile.Copy(ACtx.BufferPath, TPath.Combine(ShadowDir, ExtractFileName(ACtx.BufferPath)), True);

      { run check-unit with shadow + resolve-uses + json output }
      Cmd:= Format('"%s" check-unit "%s" --shadow "%s" --resolve-uses ' + '--db "%s" --format json', [ACtx.ExePath, ACtx.FilePath, ShadowDir, JSON]);
      if not RunCapture(Cmd, Output, 12000) then Exit;

      { parse JSON findings array }
      try
        JArr:= TJSONObject.ParseJSONValue(Output) as TJSONArray;
        if JArr = nil then Exit;
        Acc:= TList<TDragLintDiagItem>.Create;
        try
          for i:= 0 to JArr.Count - 1 do
          begin
            JObj:= JArr.Items[i];
            if not (JObj is TJSONObject) then Continue;
            DObj:= TJSONObject(JObj);

            D:= Default(TDragLintDiagItem);
            D.FilePath:= ACtx.FilePath; { map shadow back to real path }
            D.Line:= StrToIntDef(DObj.GetValue<string>('line'), 1);
            D.Col := StrToIntDef(DObj.GetValue<string>('col' ), 1);
            D.EndLine:= D.Line;
            D.EndCol:= D.Col + 1;
            D.Message:= DObj.GetValue<string>('message');
            D.Rule   := DObj.GetValue<string>('code'   );
            D.Severity:= 1; { all compiler findings are treated as errors }
            D.Source  := 'semantic';
            Acc.Add(D);
          end; // for
          Result:= Acc.ToArray;
        finally
          Acc.Free;
        end; // try
      except
        { json parse failed or malformed -- just skip semantic tier for this run }
      end; // try
    finally
      try TDirectory.Delete(ShadowDir, True); except end;
    end; // try
  except
    { never block the editor on a semantic check failure }
  end; // try
end; // function

{ ---------- the runner ---------- }

type
  TLiveRunner = class
    private
      FTimer         : TTimer  ;
      FDirty         : Boolean ;
      FLastEdit      : Cardinal;
      FBusy          : Boolean ;
      FLastActiveFile: string  ; { v0.46: auto-lint on tab/view switch }
      { v0.47: content-change poll -- catches edits the per-view Modified notifier
      misses (it only fires on the clean->dirty transition). }
      FLastHashCheck  : Cardinal;
      FLastContentHash: Cardinal;
      FLastHashFile   : string  ;
      { Last reason the fan-out gate gave, so it is logged on change only. }
      FLastFanWhy     : string  ;
      { PLAN-lint-tree P2: the fan-out launch decision. Everything that decides
        WHETHER to fan out lives in the record; this class only feeds it the
        buffer and calls the hook. }
      FFanOut         : TFanOutGate;
      { v0.47: auto ghost-check (compile the unsaved buffer on idle). FGhostPending
      is armed on every edit (NotifyEditDirty / the content poll) and cleared when
      the compile starts -- so it fires once per edit-burst. }
      FGhostPending: Boolean;
      { v0.48: compile-on-switch -- when you move to a different .pas, compile the
      current state once (even if unchanged) so its compiler errors show. Armed on
      a file change (baseline-only on the first file seen, since the project-open
      startup compile covers that one). }
      FSwitchPending: Boolean ;
      FSwitchFile   : string  ;
      FSwitchArm    : Cardinal;
      procedure OnTick(Sender: TObject);
    public
      constructor Create;
      destructor Destroy; override;
  end;

var
  GRunner          : TLiveRunner                 = nil                ;
  GLintProvider    : IDragLintDiagnosticProvider = nil;
  GSemanticProvider: IDragLintDiagnosticProvider = nil;
  GHeartbeat       : Cardinal                    = 0                     ; { v0.47: OnTick heartbeat (diagnosis) }

function ActiveBufferText(out AFilePath: string): string;
var
  ES    : IOTAEditorServices        ;
  Buf   : IOTAEditBuffer            ;
  Reader: IOTAEditReader            ;
  Read  : Integer                   ;
  Pos   : Integer                   ;
  Chunk : array[0..8191] of AnsiChar;
  SB    : TStringBuilder            ;
begin
  Result:= ''; AFilePath:= '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  Buf:= ES.TopBuffer;
  if Buf = nil then Exit;
  AFilePath:= Buf.FileName;
  Reader   := Buf.CreateReader;
  if Reader = nil then Exit;
  SB:= TStringBuilder.Create;
  try
    { v0.46 BUG FIX: read to true EOF (GetText returns 0), NOT until the first
      short read. IOTAEditReader.GetText may return fewer bytes than requested
      mid-buffer (block boundaries), so the old `until Read < Chunk-1` truncated
      the snapshot -- diagnostics past the cut (e.g. unused locals at line 1331)
      silently vanished while earlier ones (line 979) showed. }
    Pos:= 0;
    repeat
      Read:= Reader.GetText(Pos, @Chunk[0], SizeOf(Chunk) - 1);
      if Read <= 0 then Break;
      Chunk[Read]:= #0;
      SB.Append(string(AnsiString(Chunk)));
      Inc(Pos, Read);
    until False;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

procedure RepaintEditViews;
begin
  { v0.47: robust gutter repaint lives in EditViewNotifier.ForceGutterRepaint
    (repaints via the edit-window form handle -- survives double-buffered paints
    where the per-paint DC has no window). }
  ForceGutterRepaint;
end;

procedure PublishToCache(const AFile: string; const ADiags: TDragLintDiagItems);
var
  Params: TJSONObject      ;
  DObj  : TJSONObject      ;
  Range : TJSONObject      ;
  S     : TJSONObject      ;
  E     : TJSONObject      ;
  Arr   : TJSONArray       ;
  D     : TDragLintDiagItem;
  Uri   : string           ;
begin
  Params:= TJSONObject.Create;
  try
    Uri:= 'file:///' + StringReplace(AFile, '\', '/', [rfReplaceAll]);
    Params.AddPair('uri', Uri);
    Arr:= TJSONArray.Create;
    for D in ADiags do
    begin
      DObj:= TJSONObject.Create;
      S   := TJSONObject.Create;
      S.AddPair('line'     , TJSONNumber.Create(D.Line - 1));
      S.AddPair('character', TJSONNumber.Create(D.Col  - 1));
      E:= TJSONObject.Create;
      E.AddPair('line'     , TJSONNumber.Create(D.EndLine - 1));
      E.AddPair('character', TJSONNumber.Create(D.EndCol  - 1));
      Range:= TJSONObject.Create;
      Range.AddPair('start', S    );
      Range.AddPair('end'  , E    );
      DObj .AddPair('range', Range);
      DObj.AddPair('severity', TJSONNumber.Create(D.Severity));
      DObj.AddPair('source' , D.Source );
      DObj.AddPair('code'   , D.Rule   );
      DObj.AddPair('message', D.Message);
      Arr.AddElement(DObj);
    end; // for
    Params.AddPair('diagnostics', Arr   );
    { dlpLive stated explicitly rather than left to the default: this is the
      producer that OWNS the gutter's lint content, and a silent default is a
      poor place for that to be recorded. }
    Cache .Update (AFile        , Params, dlpLive);
    LiveLog(Format('PublishToCache: %s -> %d diag(s)', [ExtractFileName(AFile), Length(ADiags)]));
  finally
    Params.Free;
  end; // try
end; // procedure

{ v0.47: cheap rolling hash of the buffer for the runner's change-detection
  poll -- avoids re-linting when nothing actually changed. }
{ WRAPAROUND IS THE ALGORITHM, so overflow checking must be OFF here -- and
  ONLY here. The design-time package compiles with -$Q+ (see the dcc32 line in
  build_plugin_win32.bat), so this multiply raised EIntOverflow after about
  seven characters, EVERY TIME. It was invisible for two reasons at once: the
  caller ended in a bare `except` with an empty body, and the console test
  harness builds with plain dcc64, where overflow checking is OFF -- so
  run_surface_split.ps1 passed 35/35 against a function that could not survive
  a single call inside the shipped BPL.

  MEASURED 2026-09-11: 105 EIntOverflow in one session; the fan-out had never
  once run. }
{$OVERFLOWCHECKS OFF}
function CheapHash(const S: string): Cardinal;
var
  i: Integer;
begin
  Result:= Cardinal(Length(S));
  for i:= 1 to Length(S) do Result:= (Result * 31) + Cardinal(Ord(S[i]));
end;
{$IFOPT Q+}{$MESSAGE ERROR 'overflow checks must be off for the hash above'}{$ENDIF}
{$OVERFLOWCHECKS ON}

constructor TLiveRunner.Create;
begin
  inherited Create;
  { Explicit, though a class instance arrives zero-filled: the gate's own
    contract is that Reset establishes its start state, and relying on the
    allocator to satisfy it makes the next field added to the record a silent
    bug. }
  FFanOut.Reset;
  FTimer:= TTimer.Create(nil);
  FTimer.Interval:= 250;
  FTimer.OnTimer := OnTick;
  FTimer.Enabled := True;
  LiveLog('TLiveRunner.Create: timer enabled (250ms) -- runner is live');
end;

destructor TLiveRunner.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TLiveRunner.OnTick(Sender: TObject);
var
  Settings: TDragLintSettings;
  BufText : string           ;
  FilePath: string           ;
  Tmp     : string           ;
  Exe     : string           ;
  Bytes   : TBytes           ;
begin
  try
    { v0.47 diagnosis: prove the timer fires. Log the first 3 ticks, then every
      ~5s, with the gating state -- so a silent runner is visible in the log. }
    Inc(GHeartbeat);
    if (GHeartbeat <= 3) or (GHeartbeat mod 20 = 0) then
      LiveLog(Format('runner: tick #%d busy=%s dirty=%s active=%s', [GHeartbeat, BoolToStr(FBusy, True), BoolToStr(FDirty, True), ExtractFileName(FLastActiveFile)]));

    Settings:= LoadSettings;
    if not Settings.AutoDiagnosticsOnSave then
    begin
      if (GHeartbeat <= 3) or (GHeartbeat mod 20 = 0) then LiveLog('runner: SKIP -- AutoDiagnosticsOnSave is OFF');
      FDirty:= False;
      Exit;
    end;

    { v0.46: AUTO-lint on tab/view switch. Detect an active-file change cheaply
      (no buffer read) and arm a lint -- so diagnostics appear automatically when
      you switch code tabs, without depending on open/edit events. }
    var ActiveFile: string:= ActiveEditorFileName;
    if (ActiveFile <> '') and SameText(ExtractFileExt(ActiveFile), '.pas') and not SameText(ActiveFile, FLastActiveFile) then
    begin
      FLastActiveFile:= ActiveFile;
      FDirty         := True;
      FLastEdit:= GetTickCount - DEBOUNCE_MS; { lint on the next tick }
      LiveLog('runner: tab/view switch -> ' + ExtractFileName(ActiveFile));
    end;

    { v0.48: compile-on-switch -- compile the current state when you move to a
      DIFFERENT .pas (even if unchanged). Baseline-only on the first file seen (the
      project-open startup compile covers that one); arm a compile on later changes. }
    if (ActiveFile <> '') and SameText(ExtractFileExt(ActiveFile), '.pas') and not SameText(ActiveFile, FSwitchFile) then
    begin
      if FSwitchFile = '' then FSwitchFile:= ActiveFile { baseline only -- no compile }
      else if Settings.AutoCompileOnSwitch then
      begin
        FSwitchFile   := ActiveFile;
        FSwitchPending:= True;
        FSwitchArm    := GetTickCount;
        LiveLog('runner: tab switch -> arm compile ' + ExtractFileName(ActiveFile));
      end
      else FSwitchFile:= ActiveFile;
    end;

    { v0.47: content-change poll (~1.5s). The per-view Modified notifier only
      fires on the clean->dirty transition (once per save-cycle), so CONTINUED
      editing never re-armed the runner. This reads the active .pas buffer and
      compares a cheap hash -- catching every edit regardless of notifier flakiness
      (EditorViewModified covers the snappy case; this is the guarantee). }
    if GetTickCount - FLastHashCheck >= 1500 then
    begin
      FLastHashCheck:= GetTickCount;
      var PollFile: string                         ;
      var Snap: string:= ActiveBufferText(PollFile);
      { WHY THE POLL DECLINED, throttled to once every ~20 polls. Both skip
        conditions were silent, so "the fan-out never fired" was
        indistinguishable from "the poll never looked" -- and that is exactly
        the question a failed T1 asks. }
      if (PollFile = '') or not SameText(ExtractFileExt(PollFile), '.pas') then
      begin
        if GHeartbeat mod 20 = 0 then
          LiveLog(Format('poll: SKIP -- top buffer is [%s] (need a .pas)', [PollFile]));
      end
      else
      begin
        var HashNow: Cardinal:= CheapHash(Snap);
        if not SameText(PollFile, FLastHashFile) then
        begin
          { new file: set the baseline only -- the tab/view switch above already
            armed a lint for it. }
          FLastHashFile   := PollFile;
          FLastContentHash:= HashNow;
        end
        else if HashNow <> FLastContentHash then
        begin
          FLastContentHash:= HashNow;
          FDirty          := True;
          FGhostPending   := True; { arm the auto ghost-check too }
          FLastEdit       := GetTickCount; { debounce 700ms after the detected change }
          LiveLog('runner: content changed (poll) -> dirty');
        end;

        { PLAN-lint-tree P2: the interface-change fan-out, fed from the SAME
          snapshot the lint poll just used. A second buffer read here could pick
          up a later keystroke and leave the two tiers disagreeing about which
          text they were looking at. Everything that DECIDES lives in the gate
          (tests\SurfaceSplitTests.dpr); this is only the wiring. }
        var FanGen: Integer:= 0;
        var FanFired: Boolean:= FFanOut.Consider(PollFile, Snap, GetTickCount64, FANOUT_IDLE_MS, FanGen);
        { THE GATE'S REASONING, logged on CHANGE only. Consider returns a bare
          Boolean and every one of its five refusals looked identical from out
          here, so a fan-out that never fired gave no clue WHICH gate held it.
          Logging on change rather than per poll keeps a 250 ms timer from
          filling the log. }
        if FFanOut.LastWhy <> FLastFanWhy then
        begin
          FLastFanWhy:= FFanOut.LastWhy;
          LiveLog('fanout gate: ' + FLastFanWhy + ' [' + ExtractFileName(PollFile) + ']');
        end;
        if FanFired then
        begin
          if not Assigned(GFanOutHook) then
            LiveLog('fanout: interface change settled but no hook is assigned -- skipped')
          else
          begin
            LiveLog(Format('fanout: interface change settled -> launch gen %d for %s',
                           [FanGen, ExtractFileName(PollFile)]));
            var FanStarted: Boolean:= False;
            try
              FanStarted:= GFanOutHook(PollFile, Snap, FanGen);
            except
              on E: Exception do LiveLog('fanout: hook raised ' + E.ClassName + ': ' + E.Message);
            end;
            if not FanStarted then LiveLog('fanout: the hook declined to start (already running?)');
          end;
        end;
      end; // if
    end; // if

    { v0.48: auto-compile the UNSAVED buffer once it has been idle a few seconds,
      so real compiler errors (E2003 etc.) on code you have not saved appear
      without the manual menu or a save. Fires ONCE per edit-burst (FGhostPending
      is set on every edit by NotifyEditDirty/the poll, and cleared here on a
      successful start). NO content-hash gate -- the old gate could wedge the
      trigger permanently OFF when a transient empty buffer-read left
      FLastContentHash = FGhostLastHash = 0. Logs WHY it skips, so a 'no compile'
      report is conclusive. Independent of the lint tier below. }
    if FGhostPending and (GetTickCount - FLastEdit >= GHOST_IDLE_MS) then
    begin
      if not Settings.AutoCompileBuffer then
      begin
        FGhostPending:= False;
        LiveLog('runner: auto-ghost SKIP -- AutoCompileBuffer is OFF');
      end
      else if not Assigned(GIdleGhostCheckHook) then LiveLog('runner: auto-ghost SKIP -- compile hook not assigned (retry)')
      else
      begin
        LiveLog('runner: idle -> auto ghost-check (compile unsaved buffer)');
        var Started: Boolean:= False;
        try Started:= GIdleGhostCheckHook(); except end;
        if Started then FGhostPending:= False { started; re-armed on the next edit }
        else LiveLog('runner: auto-ghost busy -- will retry next tick');
        { else a compile is already running -> keep pending, retry next tick }
      end;
    end; // if

    { v0.48: fire the compile-on-switch once the switch has settled. Same single-
      flight compile hook (compiles current state: ghost if unsaved, else plain);
      if a compile is already running, keep pending and retry next tick. }
    if FSwitchPending and Settings.AutoCompileOnSwitch and Assigned(GIdleGhostCheckHook) and (GetTickCount - FSwitchArm >= SWITCH_COMPILE_MS) then
    begin
      LiveLog('runner: switch settled -> compile current state');
      if GIdleGhostCheckHook() then FSwitchPending:= False;
      { else busy -> keep pending, retry next tick }
    end;

    if FBusy or not FDirty then Exit;
    if GetTickCount - FLastEdit < DEBOUNCE_MS then Exit;

    { Snapshot the buffer on the MAIN thread (OTAPI access), then hand the
      analysis to a BACKGROUND thread so a slow lint can never block the editor.
      Results are marshalled back with TThread.Queue. }
    BufText:= ActiveBufferText(FilePath);
    if (FilePath = '') or not SameText(ExtractFileExt(FilePath), '.pas') then
    begin
      FDirty:= False;
      Exit;
    end;

    { v0.86: shared resolver -- Win64 build beside the BPL by default (kept
      current with the plugin, like the LSP client), Settings.ExePath override
      still wins if the user set one, PATH as last resort. }
    Exe:= DragLintExe;

    Tmp:= TPath.Combine(TPath.GetTempPath, Format('drag-lint-live-%d.pas', [GetTickCount]));
    Bytes:= TEncoding.UTF8.GetBytes(BufText);
    try
      TFile.WriteAllBytes(Tmp, Bytes);
    except
      Exit;
    end;

    FBusy := True;
    FDirty:= False;
    GLiveStatus:= 'Analyzing ' + ExtractFileName(FilePath) + '...';
    LiveLog(Format('runner: FIRE file=%s exe=%s bufLen=%d', [FilePath, Exe, Length(BufText)]));

    TThread.CreateAnonymousThread(
      procedure
      var Ctx: TDragLintDiagContext;
      Diags: TDragLintDiagItems;
      begin
        try
          Ctx:= Default(TDragLintDiagContext);
          Ctx.FilePath  := FilePath;
          Ctx.BufferPath:= Tmp;
          Ctx.ExePath   := Exe;
          Diags:= AggregateDiagnostics(Ctx); { runs the lint -- background }
          LiveLog(Format('runner: aggregated %d diag(s)', [Length(Diags)]));
        except
          on E: Exception do
          begin
            LiveLog('runner: AggregateDiagnostics EXC: ' + E.Message);
            SetLength(Diags, 0);
          end;
        end;
        try TFile.Delete(Tmp); except end;

        TThread.Queue(
          nil,
          procedure var nErr, nWarn, j: Integer; begin try PublishToCache(FilePath,
                Diags); RepaintEditViews; nErr:= 0; nWarn:= 0; for j:= 0 to High(Diags) do if Diags[j].Severity = 1 then Inc(nErr) else if Diags[j].Severity = 2 then Inc(nWarn); GLiveStatus:= Format('%d error(s), %d warning(s)', [nErr,
                  nWarn]); except end; FBusy:= False; end
        );
      end).Start; // procedure
  except
    on E: Exception do
    begin
      FBusy:= False;
      { NEVER PROPAGATE into the IDE message loop -- but never swallow SILENTLY
        either. This handler used to have an empty body, so anything raised
        between the heartbeat and the content poll skipped the rest of the tick
        FOREVER while the heartbeat kept logging happily: the runner looked
        alive and did nothing, which is the most expensive shape a bug can
        take. The tick number is included because a fault that repeats every
        tick and one that fired once look identical without it. }
      LiveLog(Format('runner: tick #%d EXC %s: %s', [GHeartbeat, E.ClassName, E.Message]));
    end;
  end; // try
end; // procedure

procedure NotifyEditDirty;
begin
  if GRunner <> nil then
  begin
    { v0.47 diagnosis: log only the not-dirty -> dirty transition (one line per
      edit burst, not per keystroke) so we can see edits reaching the runner. }
    if not GRunner.FDirty then LiveLog('NotifyEditDirty: edit detected -> FDirty set');
    GRunner.FDirty       := True;
    GRunner.FGhostPending:= True; { arm the auto ghost-check }
    GRunner.FLastEdit    := GetTickCount;
  end
  else LiveLog('NotifyEditDirty: GRunner=nil -- live runner NOT started!');
end;

function ActiveBufferSnapshot(out AFilePath: string): string;
begin
  Result:= ActiveBufferText(AFilePath);
end;

procedure NotifyFanOutFingerprint(const AFingerprint: string);
begin
  { QUEUED, NOT CALLED. This arrives on the fan-out worker thread, and the gate
    is a plain record driven from the timer -- so touching it here would be a
    data race on the very state that decides whether the IDE spawns a process. }
  TThread.Queue(nil,
    procedure
    begin
      if GRunner = nil then Exit;
      GRunner.FFanOut.NoteFingerprint(AFingerprint);
      LiveLog('fanout: engine fingerprint ' + Copy(AFingerprint, 1, 12) + ' recorded');
    end);
end;

procedure StartLiveDiagnostics;
begin
  LiveLog('StartLiveDiagnostics: ENTER');
  { Register lint provider (syntax/style rules) }
  if GLintProvider = nil then
  begin
    GLintProvider:= TLintDiagnosticProvider.Create;
    RegisterDiagnosticProvider(GLintProvider);
  end;
  { Register semantic provider (real compiler errors on unsaved buffer) }
  if GSemanticProvider = nil then
  begin
    GSemanticProvider:= TSemanticDiagnosticProvider.Create;
    RegisterDiagnosticProvider(GSemanticProvider);
  end;
  { Start the live runner (timer debounce loop) }
  if GRunner = nil then GRunner:= TLiveRunner.Create
  else LiveLog('StartLiveDiagnostics: GRunner already exists');
end; // procedure

procedure StopLiveDiagnostics;
begin
  { 2026-08-26: freeing the runner destroys a timer and can block. Log each
    stage so a hang here is distinguishable from a hang in the caller. }
  LiveLog('StopLiveDiagnostics: ENTER');
  if GLintProvider <> nil then
  begin
    UnregisterDiagnosticProvider(GLintProvider);
    GLintProvider:= nil;
  end;
  if GSemanticProvider <> nil then
  begin
    UnregisterDiagnosticProvider(GSemanticProvider);
    GSemanticProvider:= nil;
  end;
  LiveLog('StopLiveDiagnostics: providers unregistered; freeing runner');
  FreeAndNil(GRunner);
  LiveLog('StopLiveDiagnostics: DONE');
end;

initialization

finalization
{ TEARDOWN BRACKETING. An access violation while the IDE closes leaves NOTHING
  in the log -- the process is going away and the handler that would have said
  so is part of what is being torn down. Bracketing every finalization that
  holds an IDE notifier or interface turns that into a NAMED unit: the last
  'begin' with no matching 'end' is where it died. Cheap, and it is the only
  thing that makes a shutdown AV diagnosable after the fact. }
  DLT('teardown', 'LiveDiagnostics: finalization BEGIN');
{ 2026-08-26: this unit's OWN finalization also stops the runner, so a runner
  that goes quiet does NOT prove UnregisterDragLintMenu reached its
  StopLiveDiagnostics step -- that ambiguity cost a diagnosis today. Record
  which path actually did it. }
try LiveLog('finalization: entering StopLiveDiagnostics (UNIT finalization, not the menu teardown)'); except end;
try StopLiveDiagnostics; except end;

  DLT('teardown', 'LiveDiagnostics: finalization END');

end.
