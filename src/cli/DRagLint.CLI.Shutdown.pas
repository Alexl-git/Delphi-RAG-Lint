unit DRagLint.CLI.Shutdown;

// ---------------------------------------------------------------------------
// The `ide-release` and `stop-now` verbs (lane v1511 SPLIT T07): hold the IDE plugin's respawn, stand
// running engines down over their control channel. Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint ide-release: writes the engine-hold sentinel so a running
/// IDE plugin declines to (re)spawn drag-lint.exe until the hold expires, and
/// stops its LSP child on its next request. Frees nothing by itself. With
/// --resume, clears the hold instead.</summary>
/// <param name="AArgs">Parsed CLI args. Limit doubles as the hold length in
/// seconds when given (--seconds is its alias); Resume selects the clear
/// operation; AsJson or Format='json' selects JSON output.</param>
/// <returns>0 on success; 1 when the sentinel could not be written or removed.</returns>
/// <remarks>
/// Touches no index and needs no --db. The sentinel lives in the
/// current user's TEMP directory -- the IDE and the build run as the same
/// user.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.EngineHold.EngineHoldFilePath, DRagLint.Core.EngineHold.EngineIsHeld, DRagLint.Core.EngineHold.HoldEngine, DRagLint.Core.EngineHold.ReleaseEngineHold, SameText, Writeln</para>
/// <para>Returns: 0; 1</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 93 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.EngineHold.EngineHoldFilePath"/>
/// <seealso cref="DRagLint.Core.EngineHold.EngineIsHeld"/>
/// <seealso cref="DRagLint.Core.EngineHold.HoldEngine"/>
/// <seealso cref="DRagLint.Core.EngineHold.ReleaseEngineHold"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoIdeRelease(const AArgs: TArgs): Integer;

/// <summary>drag-lint stop-now: asks every reachable engine of THIS user and
/// session that exposes a maintenance control channel (lsp, index, lint-all,
/// cycles --fix, warm-rule-cache) to stand down -- close every store and exit --
/// and reports which did. Each engine is listed with its role (`status role`,
/// 1.39.1); an engine older than 1.39.1 is listed as "engine".</summary>
/// <param name="AArgs">DbPaths keeps only engines holding one of those
/// indexes; DryRun lists and changes nothing; WaitSeconds bounds the graceful
/// wait per engine (default 5); ForceKill escalates to TerminateProcess ONLY
/// for an engine that refused (busy) or did not answer, and says so.</param>
/// <returns>0 when every engine asked exited (or none was reachable); 1 when
/// at least one refused, did not answer, or did not exit in time.</returns>
/// <remarks>
/// Discovery is the pipe namespace itself -- a control pipe vanishes
/// with its process, so there is no instance file to go stale. The graceful
/// path is ALWAYS attempted first, --force or not. The engine writes the
/// audit line, not this verb: the record is kept by the side that acted.
/// docs\PLAN-maintenance-shutdown-channel.md.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Cardinal, CloseHandle, Copy, DRagLint.CLI.Shutdown.DoShutdown.DbList, DRagLint.CLI.Shutdown.DoShutdown.WaitGone, DRagLint.Core.ControlChannel.BeatDisplayText, DRagLint.Core.ControlChannel.ControlRequest, DRagLint.Core.ControlChannel.CurrentSessionId, DRagLint.Core.ControlChannel.CurrentUserSidString, DRagLint.Core.ControlChannel.ListControlPipesForThisUser (+13 more)</para>
/// <para>Returns: 0; if Failed then 1</para>
/// <para>Complexity: 32 (cyclomatic, outer body), 192 lines (full implementation)</para>
/// <seealso cref="DRagLint.CLI.Shutdown.DoShutdown.DbList"/>
/// <seealso cref="DRagLint.CLI.Shutdown.DoShutdown.WaitGone"/>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatDisplayText"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlRequest"/>
/// <seealso cref="DRagLint.Core.ControlChannel.CurrentSessionId"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoShutdown(const AArgs: TArgs): Integer;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.NetEncoding, System.JSON, System.StrUtils,
  System.DateUtils, System.Generics.Collections, System.SyncObjs, FireDAC.Stan.Async, FireDAC.DApt,
  TreeSitter, DRagLint.Core.EngineHold, DRagLint.Core.ControlChannel;

{ ---------------------------------------------------------------------------
  drag-lint ide-release -- ask a running IDE plugin to let go of the engine.

  WHY IT EXISTS
    The Delphi plugin spawns `drag-lint.exe lsp --stdio` as a long-lived child,
    and a running process holds an execute lock on its own image. So an OPEN
    IDE makes build\build_draglint_win64.bat fail to stage the file it just
    compiled -- the compile succeeds, the deploy does not, and the message
    names the file rather than the holder.

    Verified before this was designed: the BPL contains no parser, linter or
    SQLite units, so the IDE loads no tree-sitter or sqlite DLL in-process.
    Every lock on third_party\dll-win64\ is a spawned child. Stop the children
    and the entire folder becomes writable.

  IT ASKS FOR A WINDOW, NOT AN EVENT
    "Stop now" does not work: the client respawns within about a second and the
    build loses the race again. Measured against VS Code the hard way on
    2026-08-27 -- it took a kill-loop running for the DURATION of the build to
    stage cleanly. So this writes a DEADLINE, and the plugin stays stopped
    until it passes.

  RUNNING THIS DOES NOT ITSELF FREE THE FILE
    It writes a sentinel; the plugin observes it on the next request that wants
    the client. The status strip only ANNOUNCES the hold -- it stops nothing,
    and it is not what acts. A caller that needs the lock actually gone must
    wait and retry -- which build_draglint_win64.bat does, through
    stage-engine.ps1, which is what kills the holder. Said plainly here because
    a verb named "release" that returns instantly invites the assumption that
    it finished.
  --------------------------------------------------------------------------- }

function DoIdeRelease(const AArgs: TArgs): Integer;
var
  Err     : string ;
  Secs    : Integer;
  Left    : Integer;
  Held    : Boolean;
  UseJson : Boolean;
  JRoot   : TJSONObject;
begin
  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');

  if AArgs.StatusOnly then
  begin
    { READ-ONLY. This exists so the fail-open promise is TESTABLE from outside:
      a corrupt or expired sentinel must report NOT held, and without a read
      path that is the one property nobody could check. }
    Held:= EngineIsHeld(Left);
    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('schema'      , 'ide-release/1');
        JRoot.AddPair('held'        , TJSONBool.Create(Held));
        JRoot.AddPair('seconds_left', TJSONNumber.Create(Left));
        JRoot.AddPair('sentinel'    , EngineHoldFilePath);
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end;
    end
    else if Held then
      Writeln(System.SysUtils.Format('engine hold ACTIVE, %d second(s) left.', [Left]))
    else
      Writeln('no engine hold; the IDE plugin may run its engine.');
    Exit(0);
  end;

  if AArgs.Resume then
  begin
    if not ReleaseEngineHold(Err) then
    begin
      Writeln(ErrOutput, 'ERROR: could not clear the engine hold: ', Err);
      Exit(1);
    end;
    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('schema', 'ide-release/1');
        JRoot.AddPair('held'  , TJSONBool.Create(False));
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end;
    end
    else
      Writeln('engine hold cleared; the IDE plugin may respawn its engine.');
    Exit(0);
  end;

  Secs:= AArgs.HoldSeconds;
  if Secs <= 0 then Secs:= ENGINE_HOLD_DEFAULT_SECONDS;
  if not HoldEngine(Secs, Err) then
  begin
    Writeln(ErrOutput, 'ERROR: could not write the engine hold: ', Err);
    Exit(1);
  end;
  Held:= EngineIsHeld(Left);

  if UseJson then
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'      , 'ide-release/1');
      JRoot.AddPair('held'        , TJSONBool.Create(Held));
      JRoot.AddPair('seconds_left', TJSONNumber.Create(Left));
      JRoot.AddPair('sentinel'    , EngineHoldFilePath);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Writeln(System.SysUtils.Format('engine hold set for %d second(s).', [Left]));
    { Do NOT let this read as "the file is free now". It is not, yet. }
    Writeln('The IDE plugin will not respawn its engine while the hold lasts, and');
    Writeln('stops its LSP child on its next request.');
    Writeln('This verb kills nothing -- build\stage-engine.ps1 does that. Clear early with:');
    Writeln('  drag-lint ide-release --resume');
    Writeln('sentinel: ' + EngineHoldFilePath);
  end;
  Result:= 0;
end; // function

function DoShutdown(const AArgs: TArgs): Integer;  // dl:ok cyclomatic-complexity@da65 -- REVIEWED 2026-11-22 SLZ-S02: cyclomatic-complexity measured cyclomatic complexity 32 (max 30), pre-existing shape; splitting it is a refactor of its own, out of scope for a lint pass (Q10 a)
const
  CONNECT_TIMEOUT_MS = 2000; { WaitNamedPipe: the engine serves one connection at a time }
  KILL_WAIT_MS       = 5000; { after TerminateProcess, how long to wait for the handle to signal }
  MS_PER_SECOND      = 1000;
  STATUS_FIXED_FIELDS= 4;    { status<TAB>pid<TAB>version<TAB>extractor, then the databases }
  FORCED_EXIT_CODE   = 3;    { the code a --force'd engine dies with: distinguishable from 0 and from a crash }
type
  TEngineRow = record
    Pipe   : string        ;
    Pid    : Cardinal      ;
    Version: string        ;
    Role   : string        ;
    Dbs    : TArray<string>;
  end;
var
  Pipes   : TArray<string>    ;
  Rows    : TArray<TEngineRow>;
  Row     : TEngineRow        ;
  Wanted  : TArray<string>    ;
  Pipe    : string            ;
  Reply   : string            ;
  Err     : string            ;
  Fields  : TArray<string>    ;
  WaitMs  : Integer           ;
  I       : Integer           ;
  Holds   : Boolean           ;
  H       : THandle           ;
  Code    : DWORD             ;
  T0      : UInt64            ;
  Gone    : Boolean           ;
  Failed  : Boolean           ;

  function DbList(const ADbs: TArray<string>): string;
  begin
    Result:= string.Join('; ', ADbs);
    if Result = '' then Result:= '(no store open)';
  end;

  function WaitGone(APid: Cardinal; AMs: Integer): Boolean;
  var
    HP: THandle;
  begin
    HP:= OpenProcess(SYNCHRONIZE, False, APid);
    if HP = 0 then Exit(True); { already gone, or not ours to see -- treat as gone }
    try
      Result:= WaitForSingleObject(HP, Cardinal(AMs)) = WAIT_OBJECT_0;
    finally
      CloseHandle(HP);
    end;
  end;

begin
  WaitMs:= AArgs.WaitSeconds * MS_PER_SECOND;
  if AArgs.WaitSeconds <= 0 then WaitMs:= CONTROL_DEFAULT_WAIT_MS;
  if WaitMs > CONTROL_MAX_WAIT_MS then WaitMs:= CONTROL_MAX_WAIT_MS;
  SetLength(Wanted, Length(AArgs.DbPaths));
  for I:= 0 to High(AArgs.DbPaths) do Wanted[I]:= ExpandFileName(AArgs.DbPaths[I]);

  Pipes:= ListControlPipesForThisUser;
  SetLength(Rows, 0);
  for Pipe in Pipes do
  begin
    if not ControlRequest(Pipe, CONTROL_MSG_STATUS + #9 + CONTROL_STATUS_ARG_ROLE, CONNECT_TIMEOUT_MS, Reply, Err) then
    begin
      Writeln(ErrOutput, 'WARN: ', Pipe, ': no status reply (', Err, ') -- skipped');
      Continue;
    end;
    Fields:= Reply.Split([#9]);
    if (Length(Fields) < STATUS_FIXED_FIELDS) or not SameText(Fields[0], CONTROL_REPLY_STATUS) then
    begin
      Writeln(ErrOutput, 'WARN: ', Pipe, ': unexpected status reply -- skipped: ', Reply);
      Continue;
    end;
    Row.Pipe   := Pipe;
    Row.Pid    := StrToIntDef(Fields[1], 0);
    Row.Version:= Fields[2];
    Row.Dbs    := Copy(Fields, STATUS_FIXED_FIELDS, Length(Fields) - STATUS_FIXED_FIELDS);
    { 1.39.1: the engine's role (index, warm-rule-cache, lsp ...); every engine used to be
      listed as "lsp". An engine older than 1.39.1 sends none -- shown as "engine". }
    Row.Role   := 'engine';
    if (Length(Row.Dbs) > 0) and StartsText(CONTROL_ROLE_FIELD_PREFIX, Row.Dbs[0]) then
    begin
      Row.Role:= Copy(Row.Dbs[0], Length(CONTROL_ROLE_FIELD_PREFIX) + 1, MaxInt);
      Row.Dbs := Copy(Row.Dbs, 1, Length(Row.Dbs) - 1);
    end;
    if Length(Wanted) > 0 then
    begin
      Holds:= False;
      for I:= 0 to High(Row.Dbs) do
        if not Holds then
          for var W in Wanted do
            if SameText(ExpandFileName(Row.Dbs[I]), W) then
            begin
              Holds:= True;
              Break;
            end;
      if not Holds then Continue;
    end;
    SetLength(Rows, Length(Rows) + 1);  // dl:ok setlength-in-loop@c117 -- REVIEWED 2026-11-22 SLZ-S02: setlength-in-loop grows an array over a small bounded set of CLI rows; reallocation cost is immaterial at that size
    Rows[High(Rows)]:= Row;
  end;

  if Length(Rows) = 0 then
  begin
    if Length(Wanted) > 0 then
      Writeln('no running drag-lint engine of this user/session holds the named database(s) (', Length(Pipes), ' engine(s) reachable).')
    else
      Writeln('no running drag-lint engine exposes a control channel for this user/session.');
    Exit(0);
  end;

  Writeln(Format('%d engine(s) with a control channel (user %s, session %d):', [Length(Rows), CurrentUserSidString, CurrentSessionId]));
  for Row in Rows do Writeln(Format('  pid %d  %s  %s  %s', [Row.Pid, Row.Role, Row.Version, DbList(Row.Dbs)]));
  if AArgs.DryRun then
  begin
    { The outside view of a long run: the same record the IDE plugin polls. }
    for Row in Rows do
    begin
      var RowBeat: TEngineBeat;
      if RequestEngineBeat(Row.Pid, CONNECT_TIMEOUT_MS, RowBeat) then
        Writeln(Format('    pid %d beat: %s (seq %d, last report %d s ago)',
          [Row.Pid, BeatDisplayText(RowBeat), RowBeat.Seq, RowBeat.AgeMs div MS_PER_SECOND]));
    end;
    Writeln('dry run: nothing asked, nothing changed.');
    Exit(0);
  end;

  Failed:= False;
  for Row in Rows do
  begin
    T0:= GetTickCount64;
    { The graceful path first, ALWAYS -- --force changes only what happens
      after a refusal. }
    if ControlRequest(Row.Pipe, CONTROL_MSG_SHUTDOWN + #9 + IntToStr(WaitMs), CONNECT_TIMEOUT_MS, Reply, Err) then
    begin
      Fields:= Reply.Split([#9]);
      if (Length(Fields) > 0) and SameText(Fields[0], CONTROL_REPLY_EXITING) then
      begin
        Gone:= WaitGone(Row.Pid, WaitMs);
        if Gone then
          Writeln(Format('  pid %d: exiting (stores closed); exited after %.2f s', [Row.Pid, (GetTickCount64 - T0) / MS_PER_SECOND]))  // dl:ok locale-sensitive-conversion@eeea -- REVIEWED 2026-11-22 SLZ-S02: locale-sensitive-conversion human-facing console text; the user locale decimal separator is acceptable for display
        else
        begin
          Writeln(Format('  pid %d: said exiting but is STILL RUNNING after %d ms', [Row.Pid, WaitMs]));
          Failed:= True;
        end;
        Continue;
      end;
      if (Length(Fields) > 0) and SameText(Fields[0], CONTROL_REPLY_BUSY) then  // dl:ok ifthen-to-if-expression@a49b -- REVIEWED 2026-11-22 SLZ-S02: ifthen-to-if-expression the else-branch already holds an if-expression; folding both into one nested if-expression assignment reads worse
        Err:= 'BUSY -- ' + (if Length(Fields) > 2 then Fields[2] else 'not idle')
      else
        Err:= 'unexpected reply: ' + Reply;
    end
    else
      Err:= 'no reply (' + Err + ')';

    { Refused, or silent. Without --force that is the answer and it is loud. }
    Writeln(Format('  pid %d: %s; left running', [Row.Pid, Err]));
    if not AArgs.ForceKill then
    begin
      Failed:= True;
      Continue;
    end;
    Writeln(Format('  pid %d: ESCALATING to TerminateProcess -- the graceful request was refused or unanswered (--force)', [Row.Pid]));
    { QUERY_LIMITED too: without it GetExitCodeProcess fails and reports 0 --
      measured by the guard's F2, which printed "TERMINATED (code 0)" for a
      TerminateProcess(H, 3). }
    H:= OpenProcess(PROCESS_TERMINATE or SYNCHRONIZE or PROCESS_QUERY_LIMITED_INFORMATION_ACCESS, False, Row.Pid);
    if H = 0 then
    begin
      Writeln(Format('  pid %d: cannot open for termination: %s', [Row.Pid, SysErrorMessage(GetLastError)]));
      Failed:= True;
      Continue;
    end;
    try
      Code:= 0;
      if TerminateProcess(H, FORCED_EXIT_CODE) and (WaitForSingleObject(H, KILL_WAIT_MS) = WAIT_OBJECT_0) then
      begin
        GetExitCodeProcess(H, Code);
        Writeln(Format('  pid %d: TERMINATED (code %d) -- sidecar files may remain beside its databases', [Row.Pid, Code]));
      end
      else
      begin
        Writeln(Format('  pid %d: TerminateProcess failed: %s', [Row.Pid, SysErrorMessage(GetLastError)]));
        Failed:= True;
      end;
    finally
      CloseHandle(H);
    end;
  end;
  Result:= if Failed then 1 else 0;
end; // function

end.
