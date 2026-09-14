unit DragLint.Plugin.FanOut;

{ The interface-change fan-out: tiers 2 and 3 of PLAN-lint-tree.

  You delete a method from a unit's interface. Nothing tells you that three
  other units still call it -- B0 measured exactly that: `lint-all` on the
  fixture after removing three referenced interface symbols produced THREE
  findings, all [info], none about a broken reference, and the count went DOWN,
  because the deleted routine's own empty-body finding went with it. Breaking
  references makes the report QUIETER. This unit is the answer to that.

  WHAT LIVES HERE AND WHAT DOES NOT. Every DECISION -- generations, the edit
  episode, the discard back-off, the tier-3 quiet period, the command lines,
  the row text -- is in DragLint.Plugin.FanOutState, which has no ToolsAPI and
  is covered by tests\FanOutStateTests.dpr. What is left here is the part that
  genuinely needs an IDE: spawning, killing, and painting.

  THE THREE THINGS THIS FILE HAS TO GET RIGHT

  1. SUPERSESSION KILLS A PID, NEVER A NAME. There is always a resident LSP
     drag-lint.exe (LspClient.pas), so any check or kill written against the
     process NAME can neither fail nor be trusted -- and killing by name would
     take the LSP down. The child handle is captured at launch by
     RunCaptureStdoutCancellable and kept under a lock for exactly this.

  2. A SUPERSEDED RUN STILL RETURNS, because killing the child closes the pipe
     and the spawn call comes back normally. Its exit code is meaningless. The
     GENERATION is what decides, and it is issued by the launch gate, not
     counted here -- one source of truth, checked in one place
     (TFanOutEpisode.Dispose).

  3. THE MESSAGE GROUP IS BORROWED. The IDE owns it and can delete it (the user
     closes the tab); holding a stale IOTAMessageGroup across that is an access
     violation in someone else's call stack. IOTAMessageNotifier.
     MessageGroupDeleted is the only warning we get, so it is installed before
     the group is ever used, and the reference is dropped there.

  AND ONE THING IT MUST NOT DO: call ShowMessageView on a result. This runs
  while the user is typing. A background feature that steals focus is a
  background feature that gets switched off, and the whole point of a separate
  tab is that it can be looked at when wanted and ignored otherwise. }

interface

uses
  System.SysUtils;

/// <summary>Creates the message group, installs the notifier that keeps the
/// reference safe, and starts the tier-3 timer.</summary>
/// <remarks>Called once from the wizard's menu registration; safe to call
/// again.</remarks>
procedure StartFanOut;

/// <summary>Tears everything down: kills any running child, drops the message
/// group and removes the notifier.</summary>
/// <remarks>Must run before the BPL unloads, or the IDE is left holding
/// interface pointers whose vtable has gone.</remarks>
procedure ShutdownFanOut;

/// <summary>Launches a fan-out for AUnitPath at AGeneration.</summary>
/// <param name="AUnitPath">The unit whose interface changed.</param>
/// <param name="ABufferText">Its unsaved text, snapshotted by the caller on
/// the main thread.</param>
/// <param name="AGeneration">The launch token from the gate; travels with the
/// run and decides whether its result is still wanted.</param>
/// <returns>True if a run started (or was deliberately skipped); False only if
/// the caller should retry on a later tick.</returns>
/// <remarks>Main thread. Supersedes a run already in flight -- at the measured
/// ~26 s/MB that is the NORMAL path for the largest ~1% of units, not an edge
/// case.</remarks>
function StartFanOutRun(const AUnitPath, ABufferText: string; AGeneration: Integer): Boolean;

/// <summary>A save happened: reset the discard back-off and let the pending
/// tier-3 compile go ahead.</summary>
/// <param name="AFile">The saved file.</param>
/// <remarks>A save does NOT end the edit episode. The question being asked
/// spans saves.</remarks>
procedure NotifyFanOutSave(const AFile: string);

/// <summary>Menu action: compile the dependents now, without waiting for the
/// quiet period.</summary>
/// <param name="Sender">Unused; the TNotifyEvent signature.</param>
procedure InvokeCompileDependents(Sender: TObject);

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  Vcl.ExtCtrls,
  ToolsAPI,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.FanOutState,
  DragLint.Plugin.LiveDiagnostics,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.Settings,
  DragLint.Plugin.StatusBar,
  DragLint.Plugin.Telemetry;

const
  { A fan-out is bounded by the worst unit B0(b) measured (VARINSP.PAS, 914 KB,
    23.5 s) plus room for a cold start. Tier 3 adds a dcc run over the whole
    dependent set, which is a different order of magnitude, hence two ceilings. }
  FANOUT_TIMEOUT_MS  = 120000;
  COMPILE_TIMEOUT_MS = 600000;
  TIER3_TICK_MS      = 1000;

type
  { The IDE can delete our tab. Without this notifier the next repaint would
    call through a freed interface, and the AV would surface inside the IDE's
    own message-view code with nothing pointing back here. }
  TFanOutMessageNotifier = class(TInterfacedObject, IOTANotifier, IOTAMessageNotifier)
    public
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      procedure MessageGroupAdded(const Group: IOTAMessageGroup);
      procedure MessageGroupDeleted(const Group: IOTAMessageGroup);
  end;

  { TTimer.OnTimer is a TNotifyEvent -- a METHOD pointer -- so the tick needs an
    object to hang off. One instance, owned by StartFanOut/ShutdownFanOut. }
  TFanOutTicker = class
    public
      procedure OnTick(Sender: TObject);
  end;

var
  GBusy        : Integer = 0;   { AtomicCmpExchange single-flight guard }
  GChildLock   : TCriticalSection = nil;
  GChildHandle : THandle = 0;
  GChildPid    : DWORD   = 0;
  GEpisode     : TFanOutEpisode = nil;
  GTrigger     : TTreeCompileTrigger;
  GGroup       : IOTAMessageGroup = nil;
  GMsgNotifier : Integer = -1;
  GTier3Timer  : TTimer = nil;
  GTicker      : TFanOutTicker = nil;
  GStarted     : Boolean = False;

procedure Log(const AMsg: string);
begin
  DLT('fanout', AMsg);
end;

{ ---- TFanOutMessageNotifier ----------------------------------------------- }

{ THE dl:ok MARKERS BELOW ARE THE INTERFACE, NOT LAZINESS. IOTAMessageNotifier
  descends from IOTANotifier, so all four of its methods must exist -- and
  ToolsAPI.pas states in its own comment on the interface that "BeforeSave,
  AfterSave, Destroyed, and Modified are currently not called for this
  notifier". There is nothing to put in them, and MessageGroupAdded is passed a
  Group this plugin has no use for: only the DELETED half is load-bearing here.
  Writing something in them to quiet the linter would be worse than the
  finding. }

procedure TFanOutMessageNotifier.AfterSave;  begin end;  // dl:ok empty-procedure-body@e06a
procedure TFanOutMessageNotifier.BeforeSave; begin end;  // dl:ok empty-procedure-body@cbc0
procedure TFanOutMessageNotifier.Destroyed;  begin end;  // dl:ok empty-procedure-body@f061
procedure TFanOutMessageNotifier.Modified;   begin end;  // dl:ok empty-procedure-body@2df4

procedure TFanOutMessageNotifier.MessageGroupAdded(const Group: IOTAMessageGroup);  // dl:ok empty-procedure-body@7430, unused-parameter@7430
begin
end;

procedure TFanOutMessageNotifier.MessageGroupDeleted(const Group: IOTAMessageGroup);
begin
  { The ONLY warning we get that our tab has gone. Drop the reference here or
    the next repaint calls into freed memory. }
  if (GGroup <> nil) and (Group = GGroup) then
  begin
    GGroup:= nil;
    Log('message group deleted by the IDE -- reference dropped');
  end;
end;

{ ---- the message group ---------------------------------------------------- }

function MessageServices: IOTAMessageServices;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Result) then Result:= nil;
end;

{ Lazily (re)creates the tab. It can vanish at any time -- the user closes it,
  or the IDE clears everything -- so every painter asks rather than assuming. }
function EnsureGroup: IOTAMessageGroup;
var
  MS: IOTAMessageServices;
begin
  Result:= GGroup;
  if Result <> nil then Exit;
  MS:= MessageServices;
  if MS = nil then Exit(nil);
  try
    GGroup:= MS.AddMessageGroup('drag-lint impact');
    Result:= GGroup;
  except
    on E: Exception do
    begin
      Log('could not create the message group: ' + E.Message);
      Result:= nil;
    end;
  end;
end;

procedure ClearRows;
var
  MS: IOTAMessageServices;
begin
  MS:= MessageServices;
  if (MS = nil) or (GGroup = nil) then Exit;
  try MS.ClearMessageGroup(GGroup); except on E: Exception do Log('clear failed: ' + E.Message); end;
end;

{ Repaints the tab from scratch. NO ShowMessageView: this fires while the user
  is typing, and a background feature that steals focus is one that gets turned
  off within the hour. }
procedure PaintRows(const AResult: TFanOutResult; AGeneration: Integer);
var
  MS     : IOTAMessageServices;
  Grp    : IOTAMessageGroup   ;
  F      : TFanOutFinding     ;
  LineRef: Pointer            ;
  UnitCount: Integer          ;
begin
  MS := MessageServices;
  Grp:= EnsureGroup;
  if (MS = nil) or (Grp = nil) then Exit;
  try
    MS.ClearMessageGroup(Grp);
    MS.AddTitleMessage(FanOutTitleText(AResult, AGeneration), Grp);
    for F in AResult.Findings do
    begin
      LineRef:= nil;
      MS.AddToolMessage(F.FilePath, FindingRowText(F), 'drag-lint',
                        F.Line, F.Col, nil, LineRef, Grp);
    end;
  except
    on E: Exception do Log('paint failed: ' + E.Message);
  end;

  UnitCount:= Length(AResult.UnitPaths);
  if Length(AResult.Findings) = 0 then SetDragLintNote('drag-lint: impact clear')
  else SetDragLintNote(Format('drag-lint: impact %d in %d unit(s)',
                              [Length(AResult.Findings), UnitCount]));
end;

{ ---- the child --------------------------------------------------------- }

procedure RememberChild(AHandle: THandle; APid: DWORD);
begin
  GChildLock.Enter;
  try
    GChildHandle:= AHandle;
    GChildPid   := APid;
  finally
    GChildLock.Leave;
  end;
end;

{ Kills the engine child of a run that a newer keystroke has superseded.

  BY PID, captured at launch. A `tasklist | find "drag-lint"` check can never
  fail here -- the resident LSP child always exists -- and a kill written that
  way would take the LSP down with it. }
procedure SupersedeChild;
var
  H  : THandle;
  Pid: DWORD  ;
begin
  GChildLock.Enter;
  try
    H  := GChildHandle;
    Pid:= GChildPid;
    GChildHandle:= 0;
    GChildPid   := 0;
  finally
    GChildLock.Leave;
  end;
  if H = 0 then Exit;
  { KillProcess WAITS for the exit. Without that a respawn could put two engine
    runs -- and their dcc grandchildren -- on the cores the IDE is using. }
  if KillProcess(H) then Log(Format('superseded: killed pid %d', [Pid]))
  else Log(Format('superseded: pid %d did NOT die within the budget', [Pid]));
  CloseProcessHandle(H);
end;

{ ---- the run -------------------------------------------------------------- }

type
  { The five engine-target fields live in TEngineTarget, shared with the
    command-line builders, rather than being restated here. }
  TRunContext = record
    Target                  : TEngineTarget;
    BufferFile, BaselineFile: string ;
    NeedBaseline            : Boolean;
    Compile                 : Boolean;
    Generation              : Integer;
  end;

function TempFor(const AUnitPath, ASuffix: string): string;
begin
  Result:= TPath.Combine(TPath.GetTempPath,
                         Format('drag-lint-fanout-%s-%d%s',
                                [TPath.GetFileNameWithoutExtension(AUnitPath),
                                 GetCurrentProcessId, ASuffix]));
end;

{ Resolves everything the worker needs, on the MAIN thread. The OTA calls
  behind GetActiveProjectFilePath are not safe from a worker, and a fan-out
  that read them there would be a rare crash rather than a wrong answer. }
function BuildContext(const AUnitPath: string; AGeneration: Integer;
                      ACompile: Boolean; out ACtx: TRunContext): Boolean;
var
  Dbs: TArray<string>;
begin
  ACtx:= Default(TRunContext);
  Result:= False;
  ACtx.Target.Exe:= DragLintExe;
  if ACtx.Target.Exe = '' then Exit;
  ACtx.Target.UnitPath:= AUnitPath;
  ACtx.Target.Project := GetActiveProjectFilePath;
  ACtx.Target.Platform:= GetActivePlatformForLibrary;
  ACtx.Generation     := AGeneration;
  ACtx.Compile        := ACompile;

  Dbs:= ResolveActiveIndexDbs(LoadSettings);
  if Length(Dbs) = 0 then Exit;
  { The FIRST resolved DB is the project's own. The library DB may also be in
    the list, and it is the wrong authority for "who calls X" -- a name match
    against the RTL is not a caller. }
  ACtx.Target.Db:= Dbs[0];

  ACtx.BufferFile  := TempFor(AUnitPath, '.buffer.pas');
  ACtx.BaselineFile:= TempFor(AUnitPath, '.baseline.json');
  Result:= True;
end;

{ The worker body. Captures the episode baseline first when one is owed -- the
  OLD side of every diff in the episode, taken from DISK, once. }
procedure FanOutWorker(const ACtx: TRunContext);
var
  Output : string        ;
  Cmd    : string        ;
  Res    : TFanOutResult ;
  H      : THandle       ;
  Pid    : DWORD         ;
  Timeout: Integer       ;
begin
  Res:= Default(TFanOutResult);
  try
    if ACtx.NeedBaseline then
    begin
      Cmd:= BuildBaselineCmdLine(ACtx.Target, ACtx.BaselineFile);

      Log('baseline: ' + Cmd);
      H:= 0;
      RunCaptureStdoutCancellable(Cmd, Output, FANOUT_TIMEOUT_MS,
                                  BELOW_NORMAL_PRIORITY_CLASS, H, Pid);
      RememberChild(H, Pid);
      CloseProcessHandle(H);
      RememberChild(0, 0);
      if not TFile.Exists(ACtx.BaselineFile) then
      begin
        Log('baseline was not written -- abandoning this run rather than ' +
            'diffing against the live index, which the save has already updated');
        Exit;
      end;
    end;

    if ACtx.Compile then Timeout:= COMPILE_TIMEOUT_MS else Timeout:= FANOUT_TIMEOUT_MS;
    Cmd:= BuildFanOutCmdLine(ACtx.Target, ACtx.BaselineFile, ACtx.BufferFile,
                             ACtx.Compile);
    Log(Format('gen %d: %s', [ACtx.Generation, Cmd]));

    H:= 0;
    RunCaptureStdoutCancellable(Cmd, Output, Timeout,
                                BELOW_NORMAL_PRIORITY_CLASS, H, Pid);
    { Published the instant the child exists, so a supersede on the main thread
      can reach it while this call is still parked in ReadFile. }
    RememberChild(H, Pid);
    CloseProcessHandle(H);
    RememberChild(0, 0);

    { The exit code is NOT consulted: a killed child returns normally because
      the pipe closed. Only the generation decides, below. }
    if not ParseFanOutJson(Output, Res) then
      Log('gen ' + IntToStr(ACtx.Generation) + ': ' + Res.Reason);
  except
    on E: Exception do Log('worker EXC ' + E.ClassName + ': ' + E.Message);
  end;

  TThread.Queue(nil,
    procedure
    var
      D: TFanOutDisposition;
    begin
      try
        if GEpisode = nil then Exit;
        D:= GEpisode.Dispose(ACtx.Generation, Res);
        case D of
          fdAccepted:
            begin
              GEpisode.Accept(Res);
              GEpisode.NoteBaselineFingerprint(Res.OldFp);
              PaintRows(Res, ACtx.Generation);
              Log(Format('gen %d ACCEPTED: %d finding(s) in %d unit(s), closure %d/%d in %d ms',
                         [ACtx.Generation, Length(Res.Findings),
                          Length(Res.UnitPaths), Res.DirectCnt, Res.TotalCnt,
                          Res.ClosureMs]));
              { Tier 3 only ever follows a tier-2 answer for the same
                generation -- compiling dependents nobody has identified would
                be minutes of dcc for nothing.

                IT NO LONGER REQUIRES TIER 2 TO HAVE FOUND SOMETHING (2026-09-14),
                and the old condition had the logic exactly backwards. Tier 2
                reporting zero does NOT mean nothing broke: it cannot see a
                removed PROPERTY at all, because property reads are never bound
                to a symbol id. Measured that day -- two public properties
                removed from a class with 207 dependents, tier 2 reported
                "0 place(s) in 0 unit(s)", tier 3 never armed, and the save that
                logged "tier 3 forced" was a no-op because FArmed was already
                False. The one case where an actual compile is the only thing
                that can answer was the one case that skipped it.

                The cost argument it was written under is also gone: tier 3 was
                382 s per run when this gate was added and is 30.1 s now. It
                still waits out a 15 s quiet period and still backs off, so a
                typing session does not trigger a compile per keystroke. }
              if (not ACtx.Compile) and Res.Changed then
                GTrigger.ArmAfterTier2(ACtx.Generation, GetTickCount64);
            end;
          fdStaleGeneration:
            Log(Format('gen %d DISCARDED (superseded); back-off now %d ms',
                       [ACtx.Generation, GEpisode.CurrentDebounceMs]));
          fdParseError:
            Log(Format('gen %d: the buffer does not parse (%s) -- rows left as they were',
                       [ACtx.Generation, Res.Reason]));
          fdSubjectChanged:
            Log(Format('gen %d DISCARDED (episode ended)', [ACtx.Generation]));
        end;
        { The engine's own fingerprint goes back to the gate, so a shape it has
          now answered identically twice stops being asked again. }
        if Res.Ok then NotifyFanOutFingerprint(Res.NewFp);
      finally
        AtomicExchange(GBusy, 0);
      end;
    end);
end;

function LaunchRun(const AUnitPath, ABufferText: string; AGeneration: Integer;
                   ACompile: Boolean): Boolean;
var
  Ctx: TRunContext;
begin
  Result:= True;   { 'consumed' -- only a busy guard asks the caller to retry }
  if GEpisode = nil then Exit;

  if not BuildContext(AUnitPath, AGeneration, ACompile, Ctx) then
  begin
    Log('no engine or no index db resolved -- nothing to fan out to');
    Exit;
  end;

  { A run is already in flight and a newer keystroke has arrived. Killing it is
    the NORMAL path for large units, not an exception: at ~26 s/MB the top ~1%
    of ORM3 CLIENT units take 6-24 s, so a developer editing one triggers this
    on nearly every pause. }
  SupersedeChild;

  if AtomicCmpExchange(GBusy, 1, 0) <> 0 then
  begin
    Log('a run is still winding down -- retrying on the next tick');
    Exit(False);
  end;

  Ctx.NeedBaseline:= GEpisode.BeginEpisode(AUnitPath, Ctx.BaselineFile);
  GEpisode.NoteLaunch(AGeneration);

  try
    { UTF-8 with no BOM: the engine reads this as a source buffer, and a BOM
      would arrive as content on the first line. }
    TFile.WriteAllText(Ctx.BufferFile, ABufferText, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Log('could not stage the buffer: ' + E.Message);
      AtomicExchange(GBusy, 0);
      Exit;
    end;
  end;

  TThread.CreateAnonymousThread(
    procedure
    begin
      FanOutWorker(Ctx);
    end).Start;
end;

function StartFanOutRun(const AUnitPath, ABufferText: string; AGeneration: Integer): Boolean;
begin
  { The kill switch. This is the one drag-lint feature that starts a process
    while the user is typing, so it has an off position that needs no rebuild:
    set FanOutOnInterfaceEdit to 0 under the plugin's registry key. Checked
    HERE rather than at startup so flipping it takes effect immediately. }
  if not LoadSettings.FanOutOnInterfaceEdit then
  begin
    Log('skipped -- FanOutOnInterfaceEdit is off');
    Exit(True);
  end;
  Result:= LaunchRun(AUnitPath, ABufferText, AGeneration, {ACompile=}False);
  { Any edit pushes the tier-3 compile further out -- and lengthens the wait,
    because a compile interrupted twice is a session where compiling on every
    pause is the wrong idea. }
  GTrigger.NoteEdit(GetTickCount64);
end;

procedure NotifyFanOutSave(const AFile: string);
begin
  Log('save: ' + ExtractFileName(AFile) + ' -- back-off reset, tier 3 forced');
  if GEpisode <> nil then GEpisode.NoteSave;
  { A save is the one moment the user has declared the state final, so it
    FORCES the pending compile rather than restarting its quiet period. It does
    NOT end the episode: "does anything still point at what I removed" spans
    saves, and re-baselining here would silently replace that question. }
  GTrigger.NoteSave;
end;

{ ---- tier 3 --------------------------------------------------------------- }

procedure RunTreeCompile(AGeneration: Integer);
var
  Text  : string;
  Active: string;
begin
  if (GEpisode = nil) or (not GEpisode.Active) then Exit;
  { The buffer is re-read from the LIVE editor, not from the temp tier 2
    staged: the user may have typed since, and compiling last minute's text
    would report errors they have already fixed. }
  Text:= ActiveBufferSnapshot(Active);
  if (Text = '') or (not SameText(Active, GEpisode.Subject)) then
  begin
    Log('tier 3: the episode''s unit is no longer the active buffer -- skipped');
    Exit;
  end;
  Log(Format('tier 3: compiling dependents for gen %d', [AGeneration]));
  LaunchRun(GEpisode.Subject, Text, AGeneration, {ACompile=}True);
end;

procedure TFanOutTicker.OnTick(Sender: TObject);
var
  Gen: Integer;
begin
  try
    if GTrigger.ShouldFire(GetTickCount64, Gen) then RunTreeCompile(Gen);
  except
    on E: Exception do Log('tier-3 tick EXC ' + E.Message);
  end;
end;

procedure InvokeCompileDependents(Sender: TObject);
begin
  if (GEpisode = nil) or (not GEpisode.Active) then
  begin
    Log('Compile dependents: no edit episode is open -- nothing to compile against');
    SetDragLintNote('drag-lint: no interface edit to compile dependents for');
    Exit;
  end;
  RunTreeCompile(GEpisode.LaunchedGeneration);
end;

{ ---- lifecycle ------------------------------------------------------------ }

procedure StartFanOut;
var
  MS: IOTAMessageServices;
begin
  if GStarted then Exit;
  GStarted := True;
  GChildLock:= TCriticalSection.Create;
  GEpisode  := TFanOutEpisode.Create;
  GTrigger.Reset;

  { The notifier goes in BEFORE the group is ever created, so there is no
    window in which we hold a reference we would not be told about. }
  MS:= MessageServices;
  if MS <> nil then
    try GMsgNotifier:= MS.AddNotifier(TFanOutMessageNotifier.Create);
    except on E: Exception do Log('could not install the message notifier: ' + E.Message); end;

  GTier3Timer:= TTimer.Create(nil);
  GTier3Timer.Interval:= TIER3_TICK_MS;
  GTicker:= TFanOutTicker.Create;
  GTier3Timer.OnTimer := GTicker.OnTick;
  GTier3Timer.Enabled := True;

  DragLint.Plugin.LiveDiagnostics.GFanOutHook:=
    function (AFile, ABufText: string; AGeneration: Integer): Boolean
    begin
      Result:= False;
      try Result:= StartFanOutRun(AFile, ABufText, AGeneration);
      except on E: Exception do Log('hook EXC ' + E.Message); end;
    end;

  Log('fan-out started');
end;

procedure ShutdownFanOut;
var
  MS: IOTAMessageServices;
begin
  if not GStarted then Exit;
  GStarted:= False;
  DragLint.Plugin.LiveDiagnostics.GFanOutHook:= nil;

  if GTier3Timer <> nil then
  begin
    GTier3Timer.Enabled:= False;
    FreeAndNil(GTier3Timer);
  end;
  FreeAndNil(GTicker);

  SupersedeChild;

  MS:= MessageServices;
  if (MS <> nil) and (GMsgNotifier >= 0) then
    try MS.RemoveNotifier(GMsgNotifier); except on E: Exception do Log('remove notifier: ' + E.Message); end;
  GMsgNotifier:= -1;
  { Dropped, never deleted: the tab may hold rows the user is still reading,
    and the reference is what the notifier exists to protect. }
  GGroup:= nil;

  FreeAndNil(GEpisode);
  FreeAndNil(GChildLock);
end;

end.
