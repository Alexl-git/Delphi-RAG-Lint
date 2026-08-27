unit DRagLint.Core.EngineHold;

{ ---------------------------------------------------------------------------
  THE ENGINE HOLD -- a way to ask the IDE plugin to let go of drag-lint.exe.

  THE PROBLEM IT SOLVES
    A running Windows process holds an EXECUTE LOCK on its own image. The
    Delphi plugin spawns `drag-lint.exe lsp --stdio` as a long-lived child, so
    while the IDE is open that child locks the very file
    build\build_draglint_win64.bat is trying to stage. The compile succeeds and
    the deploy fails, one line later, with a message that names the FILE and
    not the HOLDER.

    Verified for this design: the BPL itself contains no parser, linter or
    SQLite units, so the IDE loads NO tree-sitter or sqlite DLL in-process.
    Every lock on third_party\dll-win64\ comes from a spawned child. Stop the
    children and the whole folder becomes writable.

  WHY A FILE AND NOT A SOCKET OR A NAMED EVENT
    * The plugin's ghost-text socket server is OFF by default, so it cannot be
      relied on as a control channel -- a control path that only works when an
      unrelated feature is enabled is not a control path.
    * A named event carries no payload, so it cannot express "for how long",
      and a bare "stop now" is exactly the thing that does not work (see
      below).
    * A file carries the deadline, survives an IDE restart, can be set BEFORE
      the IDE is even running, and can be read with `type` when something looks
      wrong. Nothing about this needs to be fast.

  A BARE "STOP" IS NOT ENOUGH, AND THAT IS THE WHOLE POINT
    Killing the server loses a race: the client restarts it within about a
    second and the build fails again. Measured the hard way against VS Code on
    2026-08-27 -- it took a kill-loop running for the DURATION of the build to
    stage cleanly. So the sentinel expresses a WINDOW, not an event: stop, and
    then stay stopped until the deadline passes.

  IT FAILS OPEN, DELIBERATELY
    A missing, empty, unparseable or expired sentinel means NOT HELD. The two
    failure directions are not symmetric: failing open costs a blocked build,
    which is visible, retryable and understood; failing closed would leave the
    IDE silently without hovers, completion or diagnostics with no error
    anywhere and no obvious way back. A corrupt file must never be able to mute
    the IDE.
  --------------------------------------------------------------------------- }

interface

const
  /// <summary>Default hold, in seconds, when a caller does not name one.
  /// Comfortably longer than a full engine build (~12 s compile plus staging)
  /// and short enough that a crashed build cannot leave the IDE mute for
  /// long.</summary>
  ENGINE_HOLD_DEFAULT_SECONDS = 120;

  /// <summary>Longest hold that will be written. A typo in a script must not
  /// be able to silence the IDE for a week.</summary>
  ENGINE_HOLD_MAX_SECONDS = 3600;

/// <summary>Absolute path of the sentinel file the hold is expressed in.</summary>
/// <returns><c>%LOCALAPPDATA%\drag-lint\engine-hold</c>. Per-user on purpose:
/// the IDE and the build run as the same user, and a machine-wide file would
/// need permissions this does not deserve.</returns>
/// <remarks>
/// NOT TPath.GetTempPath, and that is not a style preference -- it was tried
/// and it does not work. TEMP is per-PROCESS: this machine's shell has
/// TEMP=C:\TEMP while the IDE resolves it to %LOCALAPPDATA%\Temp, so the
/// writer and the reader looked in two different directories and the hold
/// silently never arrived. A rendezvous between two processes cannot be built
/// on a variable either of them may have inherited differently. Caught by
/// running it, not by reading it.
/// </remarks>
function EngineHoldFilePath: string;

/// <summary>Asks any running drag-lint IDE plugin to stop its engine child
/// processes and not respawn them until the hold expires.</summary>
/// <param name="ASeconds">How long to hold, clamped to 1 ..
/// ENGINE_HOLD_MAX_SECONDS. Values below 1 become
/// ENGINE_HOLD_DEFAULT_SECONDS.</param>
/// <param name="AError">Set to the failure reason when the result is False;
/// set to '' otherwise.</param>
/// <returns>True when the sentinel was written.</returns>
/// <remarks>Writing the sentinel does NOT itself stop anything -- the plugin
/// observes it on its status timer. A caller that needs the lock gone must
/// still wait for it.</remarks>
function HoldEngine(ASeconds: Integer; out AError: string): Boolean;

/// <summary>Ends any hold immediately, so the plugin may respawn its engine.</summary>
/// <param name="AError">Set to the failure reason when the result is False.</param>
/// <returns>True when no hold remains -- INCLUDING when there was none to
/// begin with, which is a success, not an error.</returns>
function ReleaseEngineHold(out AError: string): Boolean;

/// <summary>True while a hold is live.</summary>
/// <param name="ASecondsLeft">Whole seconds remaining, or 0 when not held.</param>
/// <returns>False for a missing, empty, unparseable or expired sentinel -- see
/// the unit header on why this fails open.</returns>
/// <remarks>Cheap enough to call from a 1 s UI timer: one stat and one short
/// read. Never raises.</remarks>
function EngineIsHeld(out ASecondsLeft: Integer): Boolean;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.DateUtils
  ;

const
  HOLD_DIR_NAME  = 'drag-lint' ;
  HOLD_FILE_NAME = 'engine-hold';

function EngineHoldDir: string;
var
  Base: string;
begin
  { LOCALAPPDATA first: it is the one per-user location both a shell and the
    IDE agree on. TPath.GetCachePath resolves to the same place and is the
    fallback for a stripped environment; TEMP is the last resort ONLY because
    something is better than an empty path -- see EngineHoldFilePath's remarks
    for why it is not the primary. }
  Base:= GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Base:= TPath.GetCachePath;
  if Base = '' then Base:= TPath.GetTempPath;
  Result:= TPath.Combine(Base, HOLD_DIR_NAME);
end;

function EngineHoldFilePath: string;
begin
  Result:= TPath.Combine(EngineHoldDir, HOLD_FILE_NAME);
end;

{ UTC epoch seconds, not a local TDateTime string. A local timestamp would be
  ambiguous for one hour every autumn and an hour wrong every spring, and this
  file is read by a different process than the one that wrote it. }
function NowEpochUtc: Int64;
begin
  Result:= DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now), {AInputIsUTC=}True);
end;

function HoldEngine(ASeconds: Integer; out AError: string): Boolean;
var
  Secs: Integer;
begin
  AError:= '';
  Secs:= ASeconds;
  if Secs < 1 then Secs:= ENGINE_HOLD_DEFAULT_SECONDS;
  if Secs > ENGINE_HOLD_MAX_SECONDS then Secs:= ENGINE_HOLD_MAX_SECONDS;
  try
    { The directory is ours and may not exist yet on a fresh machine. }
    if not TDirectory.Exists(EngineHoldDir) then TDirectory.CreateDirectory(EngineHoldDir);
    { Deadline, not duration: the reader must not have to know when this was
      written, and a reader that starts later must reach the same answer. }
    TFile.WriteAllText(EngineHoldFilePath, IntToStr(NowEpochUtc + Secs), TEncoding.ASCII);
    Result:= True;
  except
    on E: Exception do
    begin
      AError:= E.Message;
      Result:= False;
    end;
  end; // try
end;

function ReleaseEngineHold(out AError: string): Boolean;
begin
  AError:= '';
  try
    { "Nothing to release" is the desired end state, so it is a success. A
      caller scripting this should not have to special-case the common case. }
    if TFile.Exists(EngineHoldFilePath) then TFile.Delete(EngineHoldFilePath);
    Result:= True;
  except
    on E: Exception do
    begin
      AError:= E.Message;
      Result:= False;
    end;
  end; // try
end;

function EngineIsHeld(out ASecondsLeft: Integer): Boolean;
var
  Raw     : string;
  Deadline: Int64 ;
  Left    : Int64 ;
begin
  ASecondsLeft:= 0;
  Result      := False;
  try
    if not TFile.Exists(EngineHoldFilePath) then Exit;
    Raw:= Trim(TFile.ReadAllText(EngineHoldFilePath, TEncoding.ASCII));
    if Raw = '' then Exit;
    if not TryStrToInt64(Raw, Deadline) then Exit; { unparseable -> not held }
    Left:= Deadline - NowEpochUtc;
    if Left <= 0 then
    begin
      { Expired. Tidy it away so the next reader does not have to parse it
        again, but a failure to delete is irrelevant -- the deadline already
        answered the question. }
      try TFile.Delete(EngineHoldFilePath); except { best effort } end;
      Exit;
    end;
    if Left > ENGINE_HOLD_MAX_SECONDS then Left:= ENGINE_HOLD_MAX_SECONDS;
    ASecondsLeft:= Integer(Left);
    Result      := True;
  except
    { A locked or unreadable sentinel is NOT a hold -- see the unit header. }
    ASecondsLeft:= 0;
    Result      := False;
  end; // try
end;

end.
