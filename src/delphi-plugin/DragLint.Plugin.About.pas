unit DragLint.Plugin.About;

{ Batch G Task 3: IDE startup splash + Help->About entry for drag-lint, with
  a backgrounded LIVE self-info fetch from drag-lint.exe (via `info --json`)
  swapped into the About memo once it completes, or a structured error block
  if the exe call fails. Startup itself is 100% static -- RegisterDragLintAbout
  never spawns the exe on the calling (main) thread; see the DocInsight on
  RegisterDragLintAbout below. }

interface

/// <summary>Registers the drag-lint IDE startup splash entry (icon + MIT +
/// PLUGIN_VERSION) and a static Help-&gt;About entry, then kicks a one-shot
/// background fetch of the engine's own `info --json` self-info that swaps
/// the About memo's description to a live block (or a structured error
/// block on failure) once it completes.</summary>
/// <remarks>Call once from Wizard.Register, at IDE startup. Startup-safe:
/// every step here is either a Win32 resource load or an OTA registration
/// call -- NO drag-lint.exe process is spawned on this (the calling/main)
/// thread. The exe call happens only inside the background thread started
/// at the end of this procedure; its result is marshalled back to the main
/// thread via TThread.Queue. Idempotent against double-registration is NOT
/// guarded here (mirrors the other Register* procs in this plugin, which
/// rely on Wizard.Register running exactly once); every OTA step is wrapped
/// in try/except so a missing service (e.g. SplashScreenServices nil under
/// a headless/older IDE host) never breaks the rest of Register.</remarks>
procedure RegisterDragLintAbout;

/// <summary>Removes the drag-lint About-box entry and frees the retained
/// icon bitmap.</summary>
/// <remarks>Call from Wizard.Destroyed and from this unit's finalization
/// (mirrors UnregisterDragLintOptions/UnregisterProjectMenu elsewhere in
/// the plugin). Idempotent -- safe to call multiple times or when
/// RegisterDragLintAbout never ran (guarded on GAboutIndex &gt;= 0). Splash
/// entries cannot be removed via the OTA API; that is fine, they are
/// startup-only and vanish with the IDE process.</remarks>
procedure UnregisterDragLintAbout;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , Winapi.Windows
  , Vcl.Graphics
  , ToolsAPI
  , DesignIntf
  , DragLint.Plugin.Editor
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.LspClient
  ;

var
  { Index handed back by IOTAAboutBoxServices.AddPluginInfo; -1 = not
    registered (or already unregistered). Guards idempotency. }
  GAboutIndex: Integer = -1;
  { Retained so the icon bitmap handle stays valid for the lifetime of the
    splash + About entries; both surfaces only store the HBITMAP, not a
    reference to the TBitmap, so we must keep it alive ourselves. Freed in
    UnregisterDragLintAbout. }
  GIconBmp: TBitmap = nil;

{ Builds the static About description block. When ALiveOrErrorBlock = '' the
  seed "Engine info: querying..." line is used (the pre-fetch state); once
  the background fetch completes, the caller passes the formatted live/error
  block instead and that line is replaced with it. }
function StaticDescription(const ALiveOrErrorBlock: string = ''): string;
var
  ModName: string;
  Age    : TDateTime;
  BuiltAt: string;
  EngineLine: string;
begin
  ModName:= GetModuleName(HInstance);
  if (ModName <> '') and FileAge(ModName, Age) then
    BuiltAt:= FormatDateTime('yyyy-mm-dd hh:nn:ss', Age)
  else
    BuiltAt:= 'unknown';

  if ALiveOrErrorBlock = '' then EngineLine:= 'Engine info: querying...'
  else EngineLine:= ALiveOrErrorBlock;

  Result:=
    'drag-lint -- symbol-aware index + RAG + lint for Delphi/Pascal' + sLineBreak +
    'License: MIT' + sLineBreak +
    'Plugin: ' + PLUGIN_VERSION + ' (BPL built ' + BuiltAt + ')' + sLineBreak +
    EngineLine;
end;

{ Minimal brace-slice: returns the substring from the first open-brace to the
  matching last close-brace (inclusive), or '' if no open-brace is found.
  RunAndCaptureStdout merges stdout+stderr, so the JSON object may be
  preceded/followed by banner text; this mirrors Editor.pas's (impl-only)
  SliceJsonBracket without depending on it. Deliberately simple: takes the
  LAST close-brace in the string, which is correct for a single top-level
  JSON object emitted last. }
function SliceJsonObject(const AText: string): string;
var
  OpenPos, ClosePos: Integer;
begin
  Result:= '';
  OpenPos:= Pos('{', AText);
  if OpenPos = 0 then Exit;
  ClosePos:= LastDelimiter('}', AText);
  if (ClosePos = 0) or (ClosePos < OpenPos) then Exit;
  Result:= Copy(AText, OpenPos, ClosePos - OpenPos + 1);
end;

{ Formats the live engine block from a parsed info/1 JSON object. Reads each
  field defensively (GetValue with a default) since the JSON shape is an
  external contract (the CLI's DoInfo). }
function FormatLiveBlock(AInfo: TJSONObject): string;
var
  Ver, BuildDate, ExePath, Platform: string;
  TsObj, CapObj: TJSONObject;
  TsDelphi, TsDfm: string;
  Fts5: Boolean;
  Fts5Str: string;
  CliVerbs: Integer;
begin
  Ver      := AInfo.GetValue<string>('version'   , 'unknown');
  BuildDate:= AInfo.GetValue<string>('build_date', 'unknown');
  ExePath  := AInfo.GetValue<string>('exe_path'  , '');
  Platform := AInfo.GetValue<string>('platform'  , 'unknown');

  TsDelphi:= 'unknown';
  TsDfm   := 'unknown';
  if AInfo.TryGetValue<TJSONObject>('tree_sitter', TsObj) and (TsObj <> nil) then
  begin
    TsDelphi:= TsObj.GetValue<string>('delphi13', 'unknown');
    TsDfm   := TsObj.GetValue<string>('dfm'     , 'unknown');
  end;

  Fts5    := False;
  CliVerbs:= 0;
  if AInfo.TryGetValue<TJSONObject>('capabilities', CapObj) and (CapObj <> nil) then
  begin
    CapObj.TryGetValue<Boolean>('fts5', Fts5);
    CapObj.TryGetValue<Integer>('cli_verbs', CliVerbs);
  end;
  if Fts5 then Fts5Str:= 'yes' else Fts5Str:= 'no';

  Result:=
    'Engine (drag-lint.exe): ' + Ver + '  (built ' + BuildDate + ')' + sLineBreak +
    '  exe: ' + ExePath + '   platform: ' + Platform + sLineBreak +
    '  tree-sitter: delphi13 ' + TsDelphi + ' / dfm ' + TsDfm + sLineBreak +
    '  capabilities: FTS5=' + Fts5Str + ', CLI verbs=' + IntToStr(CliVerbs) + sLineBreak +
    'Plugin log: ' + GetPluginLogPath;
end;

{ Formats the structured diagnostic block shown when the live fetch fails for
  any reason: exe missing, spawn/non-zero exit, empty output (timeout), or
  unparseable JSON. AReason is one of the fixed phrases described in the
  task brief. }
function FormatErrorBlock(const AResolvedExe, AReason: string): string;
begin
  Result:=
    'Engine self-info UNAVAILABLE -- diagnostic:' + sLineBreak +
    '  resolved exe path: ' + AResolvedExe + sLineBreak +
    '  ' + AReason + sLineBreak +
    'Plugin log: ' + GetPluginLogPath;
end;

{ Swaps the About entry's description on the main thread. Resolves ABS fresh
  here (never captures an OTA interface reference across the thread
  boundary). No-op if the About entry was never registered or has since been
  unregistered (GAboutIndex < 0), or if IOTAAboutBoxServices is unavailable. }
procedure SwapAboutDescription(const ANewDescription: string);
var
  ABS: IOTAAboutBoxServices;
begin
  try
    if (GAboutIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) then
    begin
      ABS.RemovePluginInfo(GAboutIndex);
      if Assigned(GIconBmp) then
        GAboutIndex:= ABS.AddPluginInfo('drag-lint', ANewDescription, GIconBmp.Handle, False, 'MIT', PLUGIN_VERSION)
      else
        GAboutIndex:= ABS.AddPluginInfo('drag-lint', ANewDescription, 0, False, 'MIT', PLUGIN_VERSION);
    end;
  except
    { Swallow: a failed swap must never propagate into TThread.Queue's
      caller (the main-thread message loop). The About entry simply keeps
      showing "Engine info: querying..." if this fails. }
  end;
end;

{ Runs `drag-lint.exe info --json` on a background thread (started by
  RegisterDragLintAbout) and marshals the resulting live/error block back to
  the main thread. Never touches any OTA interface off the main thread. }
procedure StartBackgroundSelfInfoFetch;
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      ResolvedExe: string;
      Cmd        : string;
      Output     : string;
      ExitCode   : Integer;
      Slice      : string;
      JVal       : TJSONValue;
      JObj       : TJSONObject;
      Block      : string;
      Reason     : string;
    begin
      ResolvedExe:= DragLintExe;
      Output:= '';
      ExitCode:= -1;
      try
        if not FileExists(ResolvedExe) then
        begin
          Block:= FormatErrorBlock(ResolvedExe, 'exe not found at resolved path');
        end
        else
        begin
          Cmd:= '"' + ResolvedExe + '" info --json';
          try
            ExitCode:= RunAndCaptureStdout(Cmd, Output, 8000);
          except
            on E: Exception do
            begin
              ExitCode:= -1;
              Output:= '';
            end;
          end;

          if ExitCode <> 0 then
          begin
            Reason:= Format('spawn/exit code %d', [ExitCode]);
            Block:= FormatErrorBlock(ResolvedExe, Reason);
          end
          else if Trim(Output) = '' then
          begin
            Block:= FormatErrorBlock(ResolvedExe, 'empty response (timeout or no output)');
          end
          else
          begin
            Slice:= SliceJsonObject(Output);
            JVal:= nil;
            if Slice <> '' then
              try JVal:= TJSONObject.ParseJSONValue(Slice); except JVal:= nil; end;
            try
              if (JVal = nil) or not (JVal is TJSONObject) then
              begin
                var Snippet: string:= Copy(Output, 1, 120);
                Block:= FormatErrorBlock(ResolvedExe, 'unparseable response: ' + Snippet);
              end
              else
              begin
                JObj:= JVal as TJSONObject;
                try
                  Block:= FormatLiveBlock(JObj);
                except
                  on E: Exception do
                    Block:= FormatErrorBlock(ResolvedExe, 'unparseable response: ' + Copy(Output, 1, 120));
                end;
              end;
            finally
              JVal.Free;
            end;
          end;
        end;
      except
        on E: Exception do
          Block:= FormatErrorBlock(ResolvedExe, 'spawn/exit code -1 (' + E.ClassName + ': ' + E.Message + ')');
      end;

      { Capture Block (an immutable local string) into the queued anonymous
        method's closure; no OTA/interface state crosses the thread boundary
        except through this string. }
      TThread.Queue(nil,
        procedure
        begin
          try
            SwapAboutDescription(StaticDescription(Block));
          except
            { Never let a main-thread exception escape TThread.Queue's
              dispatch. }
          end;
        end);
    end).Start;
end;

procedure RegisterDragLintAbout;
var
  HIco: HICON;
  Icon: TIcon;
  ABS : IOTAAboutBoxServices;
begin
  { Step 1: load the icon (Win32 resource load only -- no exe call). }
  try
    HIco:= LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
    if HIco <> 0 then
    begin
      Icon:= TIcon.Create;
      try
        Icon.Handle:= HIco;
        GIconBmp:= TBitmap.Create;
        GIconBmp.Assign(Icon);
      finally
        Icon.Free;
      end;
    end
    else
      OutputDebugString('drag-lint: SPLASH_ICON_1 resource not found -- splash/About will show without an icon.');
  except
    on E: Exception do
      OutputDebugString(PChar('drag-lint: icon load failed: ' + E.ClassName + ': ' + E.Message));
  end;

  { Step 2: splash entry (startup-only, static). }
  try
    if Assigned(SplashScreenServices) and Assigned(GIconBmp) then
      SplashScreenServices.AddPluginBitmap('drag-lint', GIconBmp.Handle, False, 'MIT', PLUGIN_VERSION);
  except
    on E: Exception do
      OutputDebugString(PChar('drag-lint: splash registration failed: ' + E.ClassName + ': ' + E.Message));
  end;

  { Step 3: About entry (static seed block; "Engine info: querying..."). }
  try
    if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) then
    begin
      if Assigned(GIconBmp) then
        GAboutIndex:= ABS.AddPluginInfo('drag-lint', StaticDescription, GIconBmp.Handle, False, 'MIT', PLUGIN_VERSION)
      else
        GAboutIndex:= ABS.AddPluginInfo('drag-lint', StaticDescription, 0, False, 'MIT', PLUGIN_VERSION);
    end;
  except
    on E: Exception do
      OutputDebugString(PChar('drag-lint: About registration failed: ' + E.ClassName + ': ' + E.Message));
  end;

  { Step 4: ensure Register (and therefore this splash entry) runs at every
    IDE startup rather than only on first demand-load. }
  try
    ForceDemandLoadState(dlDisable);
  except
    on E: Exception do
      OutputDebugString(PChar('drag-lint: ForceDemandLoadState failed: ' + E.ClassName + ': ' + E.Message));
  end;

  { Step 5: kick the background live-info fetch. This is the ONLY place
    drag-lint.exe is invoked, and it runs off a background thread -- this
    procedure returns to the IDE startup sequence immediately without
    waiting on it. }
  try
    StartBackgroundSelfInfoFetch;
  except
    on E: Exception do
      OutputDebugString(PChar('drag-lint: background self-info fetch failed to start: ' + E.ClassName + ': ' + E.Message));
  end;
end;

procedure UnregisterDragLintAbout;
var
  ABS: IOTAAboutBoxServices;
begin
  try
    if (GAboutIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) then
      ABS.RemovePluginInfo(GAboutIndex);
  except
    { Best-effort teardown; never raise during IDE shutdown / package
      unload (mirrors the other Unregister* procs in Wizard.Destroyed). }
  end;
  GAboutIndex:= -1;
  FreeAndNil(GIconBmp);
end;

initialization

finalization
  UnregisterDragLintAbout;

end.
