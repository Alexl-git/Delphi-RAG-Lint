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

procedure StartLiveDiagnostics;
procedure StopLiveDiagnostics;
{ Called from the edit-view notifier's Modified hook. }
procedure NotifyEditDirty;

var
  GLiveStatus: string = '';   { shown in the dock Diagnostics status line }

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.StrUtils, System.Generics.Collections,
  Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.Providers,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Telemetry,   { TEMP debug telemetry }
  DragLint.Plugin.EditViewNotifier,   { v0.47: GGutterAnchorHwnd for forced repaint }
  DragLint.Plugin.Settings;

const
  DEBOUNCE_MS = 700;           { keystroke->lint (instant feedback) }
  SEMANTIC_DEBOUNCE_MS = 5000;  { keystroke->semantic check (compiler; slower) }

{ v0.46: append-only diagnostic trace so a "nothing shows" report is conclusive.
  Open via drag-lint > Open Plugin Log is the editor log; THIS file is dedicated
  to the live-diagnostics path: %TEMP%\drag-lint-livediag.log. }
procedure LiveLog(const AMsg: string);
begin
  DLT('livediag', AMsg);   { TEMP: route to the shared telemetry log }
end;

{ v0.46: cheap active-editor file name (no buffer read) -- used to auto-lint on
  tab/view switch. }
function ActiveEditorFileName: string;
var
  ES: IOTAEditorServices;
  Buf: IOTAEditBuffer;
begin
  Result := '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
    if ES = nil then Exit;
    Buf := ES.TopBuffer;
    if Buf <> nil then Result := Buf.FileName;
  except
    Result := '';
  end;
end;

var
  GLastSemanticCheck: Cardinal = 0;  { v0.43: throttle semantic to 5s apart }

{ ---------- small process-capture helper ---------- }

function RunCapture(const ACmdLine: string; out AOutput: string;
  ATimeoutMs: Cardinal): Boolean;
var
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  Buf: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  WideCmd: string;
  SB: TStringBuilder;
begin
  Result := False; AOutput := '';
  SA.nLength := SizeOf(SA); SA.bInheritHandle := True; SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe; SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmdLine; UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True,
       CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe); Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, ATimeoutMs);
    CloseHandle(PI.hProcess); CloseHandle(PI.hThread);
    Result := True;
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---------- the lint diagnostic provider ---------- }
{ Parses `drag-lint lint <buffer>`'s text output:
    <path>:<line>:<col>  [<severity>] <rule>: <message>             }

type
  TLintDiagnosticProvider = class(TInterfacedObject, IDragLintDiagnosticProvider)
  public
    function Name: string;
    function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

{ ---------- the semantic diagnostic provider (compiler-based) ---------- }
{ Runs `drag-lint check-unit <file.pas> --shadow <tempdir> --resolve-uses --db <lib>`
  to report real compiler errors (E2003 Undeclared, F2048, etc.) with suggested units.
  Parsed from JSON output. }

type
  TSemanticDiagnosticProvider = class(TInterfacedObject, IDragLintDiagnosticProvider)
  public
    function Name: string;
    function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

function TLintDiagnosticProvider.Name: string;
begin
  Result := 'lint';
end;

function SeverityFromTag(const ATag: string): Integer;
var L: string;
begin
  L := LowerCase(ATag);
  if Pos('error', L) > 0 then Result := 1
  else if Pos('warn', L) > 0 then Result := 2
  else if Pos('hint', L) > 0 then Result := 4
  else Result := 3;   { info }
end;

function TLintDiagnosticProvider.GetDiagnostics(
  const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Cmd, Output, Line, Rest, Tag, Rule, Msg: string;
  Loc, ColStr, Loc2, LineStr: string;
  Lines: TStringList;
  Acc: TList<TDragLintDiagItem>;
  D: TDragLintDiagItem;
  i, p, lb, rb, c1, c2: Integer;
begin
  SetLength(Result, 0);
  if ACtx.ExePath = '' then Exit;
  { v0.46: lint the UNSAVED buffer snapshot when available, so live diagnostics
    (incl. syntax errors typed but not yet saved) match the IDE's Error Insight.
    The earlier GetText short-read that truncated the snapshot is fixed
    (ActiveBufferText reads to EOF), so the buffer is now reliable. Fall back to
    the saved file on disk. }
  var LintTarget: string := ACtx.BufferPath;
  if (LintTarget = '') or not FileExists(LintTarget) then LintTarget := ACtx.FilePath;
  if LintTarget = '' then Exit;
  Cmd := Format('"%s" lint "%s"', [ACtx.ExePath, LintTarget]);
  LiveLog(Format('lint: exe=%s target=%s', [ACtx.ExePath, LintTarget]));
  if not RunCapture(Cmd, Output, 8000) then
  begin
    LiveLog('lint: RunCapture FAILED (engine not found / timeout?)');
    Exit;
  end;
  LiveLog(Format('lint: output=%d bytes', [Length(Output)]));

  Acc := TList<TDragLintDiagItem>.Create;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      lb := Pos('[', Line);
      rb := Pos(']', Line);
      if (lb = 0) or (rb = 0) or (rb < lb) then Continue;   { not a finding line }
      { left of '[' is  <path>:<line>:<col>   -- col is after the last two ':' }
      Loc := Trim(Copy(Line, 1, lb - 1));
      c2 := LastDelimiter(':', Loc);
      if c2 <= 1 then Continue;
      ColStr := Copy(Loc, c2 + 1, MaxInt);
      Loc2 := Copy(Loc, 1, c2 - 1);
      c1 := LastDelimiter(':', Loc2);
      if c1 <= 1 then Continue;
      LineStr := Copy(Loc2, c1 + 1, MaxInt);
      Tag := Copy(Line, lb + 1, rb - lb - 1);            { severity word }
      Rest := Trim(Copy(Line, rb + 1, MaxInt));          { rule: message }
      p := Pos(':', Rest);
      if p > 0 then
      begin
        Rule := Trim(Copy(Rest, 1, p - 1));
        Msg  := Trim(Copy(Rest, p + 1, MaxInt));
      end
      else
      begin
        Rule := ''; Msg := Rest;
      end;

      D := Default(TDragLintDiagItem);
      D.FilePath := ACtx.FilePath;    { map back to the real (saved) path }
      D.Line     := StrToIntDef(Trim(LineStr), 1);
      D.Col      := StrToIntDef(Trim(ColStr), 1);
      D.EndLine  := D.Line;
      D.EndCol   := D.Col + 1;
      D.Severity := SeverityFromTag(Tag);
      D.Message  := Msg;
      D.Rule     := Rule;
      D.Source   := 'lint';
      Acc.Add(D);
    end;
    LiveLog(Format('lint: parsed %d finding(s)', [Acc.Count]));
    Result := Acc.ToArray;
  finally
    Lines.Free;
    Acc.Free;
  end;
end;

{ Semantic diagnostic provider: runs compiler, parses JSON, merges undeclared-id
  suggestions. Uses `check-unit` with shadow + resolve-uses. }
function TSemanticDiagnosticProvider.Name: string;
begin
  Result := 'semantic';
end;

function TSemanticDiagnosticProvider.GetDiagnostics(
  const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Cmd, Output, ShadowDir, DcuDir, Json: string;
  JArr: TJSONArray;
  JObj, DObj: TJSONValue;
  D: TDragLintDiagItem;
  Acc: TList<TDragLintDiagItem>;
  i: Integer;
begin
  SetLength(Result, 0);
  if (ACtx.BufferPath = '') or (ACtx.ExePath = '') then Exit;

  { v0.43: shadow-overlay semantic check on unsaved buffer (throttled to 5s+).
    Creates a shadow dir with just that one unit, runs check-unit with shadow,
    and parses the JSON result to merge into the diagnostics.
    Requires --db (a project or library db to resolve undeclared symbols).
    Throttled so we don't compile on every keystroke. }

  { skip if less than 5 seconds since last semantic check }
  if (GetTickCount - GLastSemanticCheck < SEMANTIC_DEBOUNCE_MS) then
    Exit;
  GLastSemanticCheck := GetTickCount;

  { v0.43: use library DB for resolving undeclared identifiers in semantic checks.
    The project DB is heavier (includes full source) and best left for manual
    queries. The library DB (1.5M symbols, RTL/VCL/Spring4D/DevExpress) gives us
    everything we need for "add unit X to uses" suggestions. }
  Json := TPath.Combine(ExtractFilePath(ACtx.ExePath), 'drag-lint-library.sqlite');
  if not FileExists(Json) then
    Exit;   { no semantic checks without the library db }

  try
    { Create shadow dir with the unsaved file }
    ShadowDir := TPath.Combine(TPath.GetTempPath,
      Format('draglint_semantic_%d', [GetTickCount]));
    DcuDir := TPath.Combine(ShadowDir, 'dcu');
    try
      TDirectory.CreateDirectory(DcuDir);
      TFile.Copy(ACtx.BufferPath, TPath.Combine(ShadowDir, ExtractFileName(ACtx.BufferPath)), True);

      { run check-unit with shadow + resolve-uses + json output }
      Cmd := Format('"%s" check-unit "%s" --shadow "%s" --resolve-uses ' +
        '--db "%s" --format json', [ACtx.ExePath, ACtx.FilePath, ShadowDir, Json]);
      if not RunCapture(Cmd, Output, 12000) then
        Exit;

      { parse JSON findings array }
      try
        JArr := TJSONObject.ParseJSONValue(Output) as TJSONArray;
        if JArr = nil then Exit;
        Acc := TList<TDragLintDiagItem>.Create;
        try
          for i := 0 to JArr.Count - 1 do
          begin
            JObj := JArr.Items[i];
            if not (JObj is TJSONObject) then Continue;
            DObj := TJSONObject(JObj);

            D := Default(TDragLintDiagItem);
            D.FilePath := ACtx.FilePath;  { map shadow back to real path }
            D.Line     := StrToIntDef(DObj.GetValue<string>('line'), 1);
            D.Col      := StrToIntDef(DObj.GetValue<string>('col'), 1);
            D.EndLine  := D.Line;
            D.EndCol   := D.Col + 1;
            D.Message  := DObj.GetValue<string>('message');
            D.Rule     := DObj.GetValue<string>('code');
            D.Severity := 1;  { all compiler findings are treated as errors }
            D.Source   := 'semantic';
            Acc.Add(D);
          end;
          Result := Acc.ToArray;
        finally
          Acc.Free;
        end;
      except
        { json parse failed or malformed -- just skip semantic tier for this run }
      end;
    finally
      try TDirectory.Delete(ShadowDir, True); except end;
    end;
  except
    { never block the editor on a semantic check failure }
  end;
end;

{ ---------- the runner ---------- }

type
  TLiveRunner = class
  private
    FTimer:     TTimer;
    FDirty:     Boolean;
    FLastEdit:  Cardinal;
    FBusy:      Boolean;
    FLastActiveFile: string;   { v0.46: auto-lint on tab/view switch }
    { v0.47: content-change poll -- catches edits the per-view Modified notifier
      misses (it only fires on the clean->dirty transition). }
    FLastHashCheck:   Cardinal;
    FLastContentHash: Cardinal;
    FLastHashFile:    string;
    procedure OnTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  GRunner:             TLiveRunner = nil;
  GLintProvider:       IDragLintDiagnosticProvider = nil;
  GSemanticProvider:   IDragLintDiagnosticProvider = nil;
  GHeartbeat:          Cardinal = 0;   { v0.47: OnTick heartbeat (diagnosis) }

function ActiveBufferText(out AFilePath: string): string;
var
  ES: IOTAEditorServices;
  Buf: IOTAEditBuffer;
  Reader: IOTAEditReader;
  Read, Pos: Integer;
  Chunk: array[0..8191] of AnsiChar;
  SB: TStringBuilder;
begin
  Result := ''; AFilePath := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  Buf := ES.TopBuffer;
  if Buf = nil then Exit;
  AFilePath := Buf.FileName;
  Reader := Buf.CreateReader;
  if Reader = nil then Exit;
  SB := TStringBuilder.Create;
  try
    { v0.46 BUG FIX: read to true EOF (GetText returns 0), NOT until the first
      short read. IOTAEditReader.GetText may return fewer bytes than requested
      mid-buffer (block boundaries), so the old `until Read < Chunk-1` truncated
      the snapshot -- diagnostics past the cut (e.g. unused locals at line 1331)
      silently vanished while earlier ones (line 979) showed. }
    Pos := 0;
    repeat
      Read := Reader.GetText(Pos, @Chunk[0], SizeOf(Chunk) - 1);
      if Read <= 0 then Break;
      Chunk[Read] := #0;
      SB.Append(string(AnsiString(Chunk)));
      Inc(Pos, Read);
    until False;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure RepaintEditViews;
var
  ES: IOTAEditorServices;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  if ES.TopView <> nil then
    try ES.TopView.Paint; except end;
  { v0.47: force a real WM_PAINT of the edit surface so the gutter glyphs redraw
    NOW -- TopView.Paint alone can leave STALE glyphs (e.g. the unused-var hint
    dots after a syntax error clears them) until the next natural paint, which
    can be minutes when the user is idle. GGutterAnchorHwnd is published by
    PaintLine (the editor surface window). }
  if (GGutterAnchorHwnd <> 0) and IsWindow(GGutterAnchorHwnd) then
    try InvalidateRect(GGutterAnchorHwnd, nil, False);
        UpdateWindow(GGutterAnchorHwnd); except end;
end;

procedure PublishToCache(const AFile: string; const ADiags: TDragLintDiagItems);
var
  Params, DObj, Range, S, E: TJSONObject;
  Arr: TJSONArray;
  D: TDragLintDiagItem;
  Uri: string;
begin
  Params := TJSONObject.Create;
  try
    Uri := 'file:///' + StringReplace(AFile, '\', '/', [rfReplaceAll]);
    Params.AddPair('uri', Uri);
    Arr := TJSONArray.Create;
    for D in ADiags do
    begin
      DObj := TJSONObject.Create;
      S := TJSONObject.Create;
      S.AddPair('line', TJSONNumber.Create(D.Line - 1));
      S.AddPair('character', TJSONNumber.Create(D.Col - 1));
      E := TJSONObject.Create;
      E.AddPair('line', TJSONNumber.Create(D.EndLine - 1));
      E.AddPair('character', TJSONNumber.Create(D.EndCol - 1));
      Range := TJSONObject.Create;
      Range.AddPair('start', S);
      Range.AddPair('end', E);
      DObj.AddPair('range', Range);
      DObj.AddPair('severity', TJSONNumber.Create(D.Severity));
      DObj.AddPair('source', D.Source);
      DObj.AddPair('code', D.Rule);
      DObj.AddPair('message', D.Message);
      Arr.AddElement(DObj);
    end;
    Params.AddPair('diagnostics', Arr);
    Cache.Update(AFile, Params);
    LiveLog(Format('PublishToCache: %s -> %d diag(s)',
      [ExtractFileName(AFile), Length(ADiags)]));
  finally
    Params.Free;
  end;
end;

{ v0.47: cheap rolling hash of the buffer for the runner's change-detection
  poll -- avoids re-linting when nothing actually changed. }
function CheapHash(const S: string): Cardinal;
var
  I: Integer;
begin
  Result := Cardinal(Length(S));
  for I := 1 to Length(S) do
    Result := (Result * 31) + Cardinal(Ord(S[I]));
end;

constructor TLiveRunner.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
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
  BufText, FilePath, Tmp, Exe: string;
  Bytes: TBytes;
begin
  try
    { v0.47 diagnosis: prove the timer fires. Log the first 3 ticks, then every
      ~5s, with the gating state -- so a silent runner is visible in the log. }
    Inc(GHeartbeat);
    if (GHeartbeat <= 3) or (GHeartbeat mod 20 = 0) then
      LiveLog(Format('runner: tick #%d busy=%s dirty=%s active=%s',
        [GHeartbeat, BoolToStr(FBusy, True), BoolToStr(FDirty, True),
         ExtractFileName(FLastActiveFile)]));

    Settings := LoadSettings;
    if not Settings.AutoDiagnosticsOnSave then
    begin
      if (GHeartbeat <= 3) or (GHeartbeat mod 20 = 0) then
        LiveLog('runner: SKIP -- AutoDiagnosticsOnSave is OFF');
      FDirty := False;
      Exit;
    end;

    { v0.46: AUTO-lint on tab/view switch. Detect an active-file change cheaply
      (no buffer read) and arm a lint -- so diagnostics appear automatically when
      you switch code tabs, without depending on open/edit events. }
    var ActiveFile: string := ActiveEditorFileName;
    if (ActiveFile <> '') and SameText(ExtractFileExt(ActiveFile), '.pas') and
       not SameText(ActiveFile, FLastActiveFile) then
    begin
      FLastActiveFile := ActiveFile;
      FDirty    := True;
      FLastEdit := GetTickCount - DEBOUNCE_MS;   { lint on the next tick }
      LiveLog('runner: tab/view switch -> ' + ExtractFileName(ActiveFile));
    end;

    { v0.47: content-change poll (~1.5s). The per-view Modified notifier only
      fires on the clean->dirty transition (once per save-cycle), so CONTINUED
      editing never re-armed the runner. This reads the active .pas buffer and
      compares a cheap hash -- catching every edit regardless of notifier flakiness
      (EditorViewModified covers the snappy case; this is the guarantee). }
    if GetTickCount - FLastHashCheck >= 1500 then
    begin
      FLastHashCheck := GetTickCount;
      var PollFile: string;
      var Snap: string := ActiveBufferText(PollFile);
      if (PollFile <> '') and SameText(ExtractFileExt(PollFile), '.pas') then
      begin
        var HashNow: Cardinal := CheapHash(Snap);
        if not SameText(PollFile, FLastHashFile) then
        begin
          { new file: set the baseline only -- the tab/view switch above already
            armed a lint for it. }
          FLastHashFile    := PollFile;
          FLastContentHash := HashNow;
        end
        else if HashNow <> FLastContentHash then
        begin
          FLastContentHash := HashNow;
          FDirty    := True;
          FLastEdit := GetTickCount;   { debounce 700ms after the detected change }
          LiveLog('runner: content changed (poll) -> dirty');
        end;
      end;
    end;

    if FBusy or not FDirty then Exit;
    if GetTickCount - FLastEdit < DEBOUNCE_MS then Exit;

    { Snapshot the buffer on the MAIN thread (OTAPI access), then hand the
      analysis to a BACKGROUND thread so a slow lint can never block the editor.
      Results are marshalled back with TThread.Queue. }
    BufText := ActiveBufferText(FilePath);
    if (FilePath = '') or not SameText(ExtractFileExt(FilePath), '.pas') then
    begin
      FDirty := False;
      Exit;
    end;

    { v0.46: PREFER the engine bundled beside the BPL (kept current with the
      plugin), like the LSP client does -- otherwise a stale Settings.ExePath
      runs an OLD engine for lint while hover uses the new one, so new rules
      (e.g. unused-local/H2164) silently never appear. Fall back to the
      configured ExePath, then PATH. }
    Exe := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(Exe) then Exe := Settings.ExePath;
    if (Exe = '') or not FileExists(Exe) then Exe := 'drag-lint.exe';

    Tmp := TPath.Combine(TPath.GetTempPath,
      Format('drag-lint-live-%d.pas', [GetTickCount]));
    Bytes := TEncoding.UTF8.GetBytes(BufText);
    try
      TFile.WriteAllBytes(Tmp, Bytes);
    except
      Exit;
    end;

    FBusy := True;
    FDirty := False;
    GLiveStatus := 'Analyzing ' + ExtractFileName(FilePath) + '...';
    LiveLog(Format('runner: FIRE file=%s exe=%s bufLen=%d',
      [FilePath, Exe, Length(BufText)]));

    TThread.CreateAnonymousThread(
      procedure
      var
        Ctx: TDragLintDiagContext;
        Diags: TDragLintDiagItems;
      begin
        try
          Ctx := Default(TDragLintDiagContext);
          Ctx.FilePath   := FilePath;
          Ctx.BufferPath := Tmp;
          Ctx.ExePath    := Exe;
          Diags := AggregateDiagnostics(Ctx);   { runs the lint -- background }
          LiveLog(Format('runner: aggregated %d diag(s)', [Length(Diags)]));
        except
          on E: Exception do
          begin
            LiveLog('runner: AggregateDiagnostics EXC: ' + E.Message);
            SetLength(Diags, 0);
          end;
        end;
        try TFile.Delete(Tmp); except end;

        TThread.Queue(nil,
          procedure
          var
            nErr, nWarn, j: Integer;
          begin
            try
              PublishToCache(FilePath, Diags);
              RepaintEditViews;
              nErr := 0; nWarn := 0;
              for j := 0 to High(Diags) do
                if Diags[j].Severity = 1 then Inc(nErr)
                else if Diags[j].Severity = 2 then Inc(nWarn);
              GLiveStatus := Format('%d error(s), %d warning(s)', [nErr, nWarn]);
            except
            end;
            FBusy := False;
          end);
      end).Start;
  except
    FBusy := False;
    { never propagate into the IDE message loop }
  end;
end;

procedure NotifyEditDirty;
begin
  if GRunner <> nil then
  begin
    { v0.47 diagnosis: log only the not-dirty -> dirty transition (one line per
      edit burst, not per keystroke) so we can see edits reaching the runner. }
    if not GRunner.FDirty then
      LiveLog('NotifyEditDirty: edit detected -> FDirty set');
    GRunner.FDirty := True;
    GRunner.FLastEdit := GetTickCount;
  end
  else
    LiveLog('NotifyEditDirty: GRunner=nil -- live runner NOT started!');
end;

procedure StartLiveDiagnostics;
begin
  LiveLog('StartLiveDiagnostics: ENTER');
  { Register lint provider (syntax/style rules) }
  if GLintProvider = nil then
  begin
    GLintProvider := TLintDiagnosticProvider.Create;
    RegisterDiagnosticProvider(GLintProvider);
  end;
  { Register semantic provider (real compiler errors on unsaved buffer) }
  if GSemanticProvider = nil then
  begin
    GSemanticProvider := TSemanticDiagnosticProvider.Create;
    RegisterDiagnosticProvider(GSemanticProvider);
  end;
  { Start the live runner (timer debounce loop) }
  if GRunner = nil then
    GRunner := TLiveRunner.Create
  else
    LiveLog('StartLiveDiagnostics: GRunner already exists');
end;

procedure StopLiveDiagnostics;
begin
  if GLintProvider <> nil then
  begin
    UnregisterDiagnosticProvider(GLintProvider);
    GLintProvider := nil;
  end;
  if GSemanticProvider <> nil then
  begin
    UnregisterDiagnosticProvider(GSemanticProvider);
    GSemanticProvider := nil;
  end;
  FreeAndNil(GRunner);
end;

initialization

finalization
  try StopLiveDiagnostics; except end;

end.
