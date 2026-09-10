unit DragLint.Plugin.FanOutState;

{ Everything the fan-out DECIDES, with no ToolsAPI in it.

  WHY THE SPLIT. PLAN-lint-tree P3 is a background worker that spawns an engine
  while you type, kills it when you type again, and paints rows into an IDE
  message group. The painting needs an IDE; none of the deciding does -- which
  generation is current, whether a result is stale, how long to wait after a
  discard, when an edit episode is over, what the command line says. Put those
  in the same unit as the OTA calls and they can only be checked by a person
  watching a running IDE, which is exactly the kind of verification that does
  not happen twice.

  THE FOUR THINGS THAT LIVE HERE, and why each is a decision rather than a
  detail:

    GENERATION. A result is answering a question about text that may no longer
      exist. The generation is issued at the LAUNCH (by TFanOutGate in
      SurfaceSplit), travels with the run, and anything but the newest is
      discarded. Counting generations in the worker instead would let two
      sources of truth drift, and the symptom -- rows pointing at lines that
      have moved -- looks like a navigation bug rather than a race.

    THE EPISODE. The interesting question is not "did this keystroke break a
      dependent" but "does anything still point at what I removed", and that
      spans many keystrokes and at least one save. So the OLD side of the diff
      is a baseline captured ONCE, at the start of the episode, and A SAVE DOES
      NOT END IT. Re-baselining on save would answer "did the last five seconds
      break anything", which is never the question being asked.

    RECONCILIATION. An edit to the subject discards the whole result; an edit
      to one dependent discards only that dependent's rows. Consecutive
      discards double the wait, because a continuously-edited file otherwise
      loops discard -> re-arm -> discard and spends the whole session spawning
      engines it then kills.

    THE TIER-3 QUIET PERIOD. Compiling the dependents is minutes of dcc, so it
      waits for a real pause, backs off when interrupted, and treats a save as
      a forcing trigger -- a save is the one moment the user has said "this is
      the state I mean".

  All of it is tested by tests\FanOutStateTests.dpr. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

const
  /// <summary>Base wait after an interface change; the same value the launch
  /// gate uses, so a discard's first back-off step equals a normal wait.</summary>
  FANOUT_BASE_DEBOUNCE_MS = 2000;

  /// <summary>Ceiling on the doubling back-off. VALIDATED by B0(b): the worst
  /// ORM3 CLIENT unit (VARINSP.PAS, 914 KB) parses in 23.5 s, inside this, so
  /// the cap can never be shorter than the work it is pacing.</summary>
  FANOUT_MAX_DEBOUNCE_MS = 30000;

  /// <summary>Quiet period before tier 3 compiles the dependents. A PREDICTION
  /// (PLAN-lint-tree 3.3), not a measurement -- tier 3 is minutes of dcc, so
  /// this is set to a length a person would recognise as "stopped working"
  /// rather than to a number anything was clocked at.</summary>
  TREE_COMPILE_QUIET_MS = 15000;

  /// <summary>Ceiling on the tier-3 back-off.</summary>
  TREE_COMPILE_MAX_QUIET_MS = 60000;

type
  /// <summary>Where an engine run is pointed: the executable, the unit under
  /// edit, and the index and project context to resolve it in.</summary>
  /// <remarks>A record rather than five more parameters because BOTH builders
  /// need exactly this set, and the caller (FanOut) was independently keeping
  /// its own copy of the same five fields. One shape, defined once.</remarks>
  TEngineTarget = record
    /// <summary>Full path to drag-lint.exe.</summary>
    Exe     : string;
    /// <summary>The unit being edited.</summary>
    UnitPath: string;
    /// <summary>That unit's project index database.</summary>
    Db      : string;
    /// <summary>The .dproj, or '' to let the engine resolve it.</summary>
    Project : string;
    /// <summary>Win32/Win64, or '' to omit the flag entirely.</summary>
    Platform: string;
  end;

  /// <summary>One reportable place a dependent still refers to something the
  /// edit removed or changed.</summary>
  TFanOutFinding = record
    FilePath : string ;
    Line     : Integer;
    Col      : Integer;
    Rule     : string ;
    Severity : string ;
    Message  : string ;
    RefKind  : string ;
    /// <summary>The dependent was edited after it was indexed, so the LINE may
    /// have moved. Reported rather than hidden: a row the user can see is
    /// approximate is worth more than a row silently withheld.</summary>
    Unchecked: Boolean;
  end;

  /// <summary>A parsed `lint-tree --format json` result.</summary>
  TFanOutResult = record
    Ok         : Boolean;   { the JSON parsed at all }
    Changed    : Boolean;
    ParseError : Boolean;   { the BUFFER did not parse -- findings are absent }
    Reason     : string ;
    NewFp      : string ;
    OldFp      : string ;
    Findings   : TArray<TFanOutFinding>;
    Suppressed : Integer;   { ambiguous name-joins deliberately not reported }
    Compiled   : Boolean;
    DirectCnt  : Integer;
    TotalCnt   : Integer;
    ClosureMs  : Integer;
    /// <summary>Distinct dependent files across Findings.</summary>
    /// <returns>Each affected file once, in first-seen order and compared
    /// case-insensitively -- the same file reached through two findings is one
    /// entry, or the "in N units" count would exaggerate the blast radius.</returns>
    function UnitPaths: TArray<string>;
  end;

  /// <summary>How a result was disposed of, for the telemetry line and for the
  /// tests -- "it did not appear" is true of far too many different bugs to be
  /// a useful observation on its own.</summary>
  TFanOutDisposition = (fdAccepted, fdStaleGeneration, fdSubjectChanged, fdParseError);

  /// <summary>The edit episode: the baseline, the worklist, the discard
  /// back-off and the generation bookkeeping.</summary>
  /// <remarks>Main thread only. The worker hands results back through the
  /// owning unit's TThread.Queue, not by touching this.</remarks>
  TFanOutEpisode = class
    private
      FSubject       : string ;
      FBaselineFile  : string ;
      FActive        : Boolean;
      FLaunchedGen   : Integer;
      FAcceptedGen   : Integer;
      FDiscards      : Integer;
      FWorklist      : TList<string>;
      FBaselineFp    : string ;
    public
      constructor Create;
      destructor Destroy; override;

      /// <summary>Begins an episode for AUnitPath, or does nothing if one is
      /// already running for it.</summary>
      /// <param name="AUnitPath">The unit being edited.</param>
      /// <param name="ABaselineFile">Where the engine will write the baseline.</param>
      /// <returns>True if a baseline still has to be captured.</returns>
      /// <remarks>The baseline is the OLD side for every diff in the episode;
      /// capturing it per run would compare the buffer against itself.</remarks>
      function BeginEpisode(const AUnitPath, ABaselineFile: string): Boolean;

      /// <summary>Records the fingerprint the baseline capture reported, so a
      /// later return to that exact shape can end the episode.</summary>
      /// <param name="AFingerprint">The baseline's own fingerprint.</param>
      procedure NoteBaselineFingerprint(const AFingerprint: string);

      /// <summary>Records that generation AGeneration has been launched.</summary>
      /// <param name="AGeneration">The launch token from TFanOutGate.</param>
      procedure NoteLaunch(AGeneration: Integer);

      /// <summary>Decides what to do with a result that has come back.</summary>
      /// <param name="AGeneration">The generation the result was launched with.</param>
      /// <param name="AResult">The parsed result.</param>
      /// <returns>fdAccepted only when this is the newest generation and the
      /// buffer parsed; every other value means the rows are not shown.</returns>
      function Dispose(AGeneration: Integer; const AResult: TFanOutResult): TFanOutDisposition;

      /// <summary>Accepts a result: replaces the worklist and clears the
      /// back-off.</summary>
      /// <param name="AResult">The result whose rows are being shown.</param>
      procedure Accept(const AResult: TFanOutResult);

      /// <summary>Drops one dependent's rows because that dependent was edited.</summary>
      /// <param name="AFile">The dependent that changed.</param>
      /// <returns>True if it had rows to drop.</returns>
      /// <remarks>Only that file's rows go. Discarding the whole result for an
      /// edit to one dependent would make the tab flicker empty every time you
      /// touched any file it named.</remarks>
      function DropDependent(const AFile: string): Boolean;

      /// <summary>Ends the episode and forgets the baseline.</summary>
      procedure EndEpisode;

      /// <summary>Whether the episode should end because the interface came
      /// back to where it started.</summary>
      /// <param name="AFingerprint">The buffer's current fingerprint.</param>
      /// <returns>True when it equals the baseline's.</returns>
      /// <remarks>An undo back to the starting shape means there is nothing
      /// left to answer; ending here is what stops an empty tab lingering.</remarks>
      function ShouldEndOnFingerprint(const AFingerprint: string): Boolean;

      /// <summary>The wait before the next launch, doubled per consecutive
      /// discard and capped.</summary>
      /// <returns>Milliseconds, between the base and the cap.</returns>
      function CurrentDebounceMs: Integer;

      /// <summary>A save resets the back-off: the user has stopped and said
      /// what they mean.</summary>
      procedure NoteSave;

      property Active      : Boolean read FActive;
      property Subject     : string  read FSubject;
      property BaselineFile: string  read FBaselineFile;
      property Discards    : Integer read FDiscards;
      /// <summary>The newest generation launched in this episode -- what the
      /// manual Compile dependents menu item compiles against.</summary>
      property LaunchedGeneration: Integer read FLaunchedGen;
      /// <summary>Dependents that currently have rows on screen.</summary>
      property Worklist    : TList<string> read FWorklist;
  end;

  /// <summary>When tier 3 (compile the dependents) may run.</summary>
  /// <remarks>Main thread only; ticks are passed in so the quiet period is
  /// testable without waiting fifteen seconds.</remarks>
  TTreeCompileTrigger = record
    private
      FArmed     : Boolean;
      FArmedAt   : UInt64 ;
      FQuietMs   : Integer;
      FGeneration: Integer;
      FForced    : Boolean;
    public
      /// <summary>Forgets any armed trigger and resets the back-off.</summary>
      procedure Reset;

      /// <summary>Arms the trigger because tier 2 finished for AGeneration.</summary>
      /// <param name="AGeneration">The generation tier 2 answered.</param>
      /// <param name="ANowTick">GetTickCount64.</param>
      procedure ArmAfterTier2(AGeneration: Integer; ANowTick: UInt64);

      /// <summary>An edit landed, so the quiet period restarts and lengthens.</summary>
      /// <param name="ANowTick">GetTickCount64.</param>
      /// <remarks>Backs off 15/30/60 s capped, because a compile interrupted
      /// twice is a session where compiling on every pause is the wrong idea.</remarks>
      procedure NoteEdit(ANowTick: UInt64);

      /// <summary>A save: force the compile at the next check and reset the
      /// back-off.</summary>
      /// <remarks>The one moment the user has declared the state final, so it
      /// overrides the quiet period rather than restarting it.</remarks>
      procedure NoteSave;

      /// <summary>Whether tier 3 should start now.</summary>
      /// <param name="ANowTick">GetTickCount64.</param>
      /// <param name="AGeneration">Receives the generation to compile.</param>
      /// <returns>True at most once per arming.</returns>
      function ShouldFire(ANowTick: UInt64; out AGeneration: Integer): Boolean;

      /// <summary>Current quiet period, after any back-off.</summary>
      property QuietMs: Integer read FQuietMs;
  end;

/// <summary>The command line that captures an episode baseline.</summary>
/// <param name="ATarget">Where the run is pointed.</param>
/// <param name="ABaselineFile">Where to write the baseline JSON.</param>
/// <returns>A quoted command line. NO --buffer: the baseline is the state on
/// DISK at the start of the episode.</returns>
function BuildBaselineCmdLine(const ATarget: TEngineTarget;
                              const ABaselineFile: string): string;

/// <summary>The command line for one fan-out run.</summary>
/// <param name="ATarget">Where the run is pointed.</param>
/// <param name="ABaselineFile">The episode baseline -- MANDATORY from the
/// plugin. A launch without one diffs the buffer against the live index, which
/// the save has already updated, so it would report nothing.</param>
/// <param name="ABufferFile">The unsaved buffer, snapshotted to a temp file.</param>
/// <param name="ACompile">True for tier 3 (shadow-compile the dependents).</param>
/// <returns>A quoted command line ending in --format json.</returns>
function BuildFanOutCmdLine(const ATarget: TEngineTarget;
                            const ABaselineFile, ABufferFile: string;
                            ACompile: Boolean): string;

/// <summary>Parses `lint-tree --format json` output.</summary>
/// <param name="AJson">The engine's stdout.</param>
/// <param name="AResult">Receives the parsed result; Ok is False if the text
/// was not JSON at all.</param>
/// <returns>AResult.Ok.</returns>
/// <remarks>Never raises: the engine's stdout can be a usage banner, a stack
/// trace or nothing, and a background feature that raises on that is a
/// background feature that takes the IDE with it.</remarks>
function ParseFanOutJson(const AJson: string; out AResult: TFanOutResult): Boolean;

/// <summary>The message-group row text for one finding.</summary>
/// <param name="AFinding">The finding.</param>
/// <returns>Rule, message, and an explicit UNCHECKED marker when the line may
/// have moved.</returns>
function FindingRowText(const AFinding: TFanOutFinding): string;

/// <summary>The title row: what was found, in how many units, for which
/// generation.</summary>
/// <param name="AResult">The accepted result.</param>
/// <param name="AGeneration">The generation being shown.</param>
/// <returns>A single line, including the count of suppressed ambiguous joins
/// when there were any -- an uncounted suppression is the all-clear this
/// feature exists to prevent.</returns>
function FanOutTitleText(const AResult: TFanOutResult; AGeneration: Integer): string;

implementation

uses
  System.JSON;

const
  { How much of a non-JSON engine reply to quote back in Reason. Enough to
    recognise a usage banner or an exception message, short enough that a
    300-line help dump does not become the log line. }
  REASON_ECHO_CHARS = 120;

{ ---- TFanOutResult -------------------------------------------------------- }

function TFanOutResult.UnitPaths: TArray<string>;
var
  Seen: TStringList;
  F   : TFanOutFinding;
begin
  Seen:= TStringList.Create;
  try
    Seen.CaseSensitive:= False;
    Seen.Duplicates   := dupIgnore;
    for F in Findings do
      if Seen.IndexOf(F.FilePath) < 0 then Seen.Add(F.FilePath);
    Result:= Seen.ToStringArray;
  finally
    Seen.Free;
  end;
end;

{ ---- command lines -------------------------------------------------------- }

{ The optional half both builders share. Kept in one place because a flag
  emitted with an empty value does not fail -- it swallows the NEXT argument,
  and the run then does something subtly different rather than erroring. }
function OptionalArgs(const AProject, APlatform: string): string;
begin
  Result:= '';
  if AProject  <> '' then Result:= Result + Format(' --project "%s"', [AProject]);
  if APlatform <> '' then Result:= Result + Format(' --platform %s', [APlatform]);
end;

function BuildBaselineCmdLine(const ATarget: TEngineTarget;
                              const ABaselineFile: string): string;
begin
  Result:= Format('"%s" lint-tree --unit "%s" --db "%s" --write-baseline "%s"',
                  [ATarget.Exe, ATarget.UnitPath, ATarget.Db, ABaselineFile])
         + OptionalArgs(ATarget.Project, ATarget.Platform)
         + ' --format json';
end;

function BuildFanOutCmdLine(const ATarget: TEngineTarget;
                            const ABaselineFile, ABufferFile: string;
                            ACompile: Boolean): string;
begin
  Result:= Format('"%s" lint-tree --unit "%s" --db "%s" --buffer "%s" --baseline "%s"',
                  [ATarget.Exe, ATarget.UnitPath, ATarget.Db, ABufferFile, ABaselineFile])
         + OptionalArgs(ATarget.Project, ATarget.Platform);
  if ACompile then Result:= Result + ' --compile';
  Result:= Result + ' --format json';
end;

{ ---- parsing -------------------------------------------------------------- }

function ParseFanOutJson(const AJson: string; out AResult: TFanOutResult): Boolean;
var
  Root   : TJSONObject;
  Val    : TJSONValue ;
  Arr    : TJSONArray ;
  Obj    : TJSONObject;
  Fp, Cl : TJSONObject;
  i      : Integer    ;
  F      : TFanOutFinding;
  List   : TList<TFanOutFinding>;
begin
  AResult:= Default(TFanOutResult);
  Result := False;
  if Trim(AJson) = '' then Exit;

  { The engine's stdout is not guaranteed to be JSON -- an unknown verb prints a
    banner, a crash prints a stack. Parsing defensively here is what keeps a bad
    engine build from surfacing as an IDE exception. The failure is carried out
    in Reason rather than swallowed: a background feature that goes quiet AND
    says nothing about why is one nobody can diagnose. }
  try
    Val:= TJSONObject.ParseJSONValue(AJson);
  except
    on E: Exception do
    begin
      Val:= nil;
      AResult.Reason:= Format('engine output did not parse as JSON (%s: %s)',
                              [E.ClassName, E.Message]);
    end;
  end;
  if not (Val is TJSONObject) then
  begin
    Val.Free;
    if AResult.Reason = '' then
      AResult.Reason:= 'engine output was not a JSON object: ' + Copy(Trim(AJson), 1, REASON_ECHO_CHARS);
    Exit;
  end;

  Root:= TJSONObject(Val);
  try
    AResult.Ok        := True;
    AResult.Changed   := Root.GetValue<Boolean>('changed', False);
    AResult.ParseError:= Root.GetValue<Boolean>('parse_error', False);
    AResult.Reason    := Root.GetValue<string>('reason', '');
    AResult.Suppressed:= Root.GetValue<Integer>('suppressed_ambiguous', 0);
    AResult.Compiled  := Root.GetValue<Boolean>('compiled', False);

    Fp:= Root.GetValue('fingerprint') as TJSONObject;
    if Fp <> nil then
    begin
      AResult.NewFp:= Fp.GetValue<string>('new', '');
      AResult.OldFp:= Fp.GetValue<string>('old', '');
    end;

    Cl:= Root.GetValue('closure') as TJSONObject;
    if Cl <> nil then
    begin
      AResult.DirectCnt:= Cl.GetValue<Integer>('direct', 0);
      AResult.TotalCnt := Cl.GetValue<Integer>('total', 0);
      AResult.ClosureMs:= Cl.GetValue<Integer>('ms', 0);
    end;

    Arr:= Root.GetValue('findings') as TJSONArray;
    if Arr <> nil then
    begin
      List:= TList<TFanOutFinding>.Create;
      try
        for i:= 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[i] is TJSONObject) then Continue;
          Obj:= TJSONObject(Arr.Items[i]);
          F.FilePath := Obj.GetValue<string>('file', '');
          F.Line     := Obj.GetValue<Integer>('line', 0);
          F.Col      := Obj.GetValue<Integer>('col', 0);
          F.Rule     := Obj.GetValue<string>('rule', '');
          F.Severity := Obj.GetValue<string>('severity', '');
          F.Message  := Obj.GetValue<string>('message', '');
          F.RefKind  := Obj.GetValue<string>('ref_kind', '');
          F.Unchecked:= Obj.GetValue<Boolean>('unchecked', False);
          List.Add(F);
        end;
        AResult.Findings:= List.ToArray;
      finally
        List.Free;
      end;
    end;
    Result:= True;
  finally
    Root.Free;
  end;
end;

{ ---- row text ------------------------------------------------------------- }

function FindingRowText(const AFinding: TFanOutFinding): string;
begin
  Result:= AFinding.Message;
  if AFinding.RefKind <> '' then
    Result:= Format('%s (%s)', [Result, AFinding.RefKind]);
  { SAID, not implied. An unchecked row's line number came from an index older
    than the file, so double-click can land near rather than on it. A user who
    is told that reads a near miss as expected; a user who is not reads it as
    the feature being broken. }
  if AFinding.Unchecked then Result:= Result + ' [UNCHECKED -- dependent edited since it was indexed]';
end;

function FanOutTitleText(const AResult: TFanOutResult; AGeneration: Integer): string;
var
  UnitCount: Integer;
begin
  UnitCount:= Length(AResult.UnitPaths);
  Result:= Format('drag-lint impact: %d place(s) in %d unit(s) [gen %d]',
                  [Length(AResult.Findings), UnitCount, AGeneration]);
  { Counted, never dropped: a name-join refused because more than one unit
    declares the name is a place this run DID NOT check, and reporting silence
    without it would be the all-clear the whole verb exists to prevent. }
  if AResult.Suppressed > 0 then
    Result:= Result + Format(' -- %d ambiguous name(s) not checked', [AResult.Suppressed]);
  if AResult.Compiled then Result:= Result + ' -- dependents compiled';
end;

{ ---- TFanOutEpisode ------------------------------------------------------- }

constructor TFanOutEpisode.Create;
begin
  inherited Create;
  FWorklist:= TList<string>.Create;
end;

destructor TFanOutEpisode.Destroy;
begin
  FWorklist.Free;
  inherited Destroy;
end;

function TFanOutEpisode.BeginEpisode(const AUnitPath, ABaselineFile: string): Boolean;
begin
  if FActive and SameText(FSubject, AUnitPath) then Exit(False);
  { A different unit is a different question: end the old episode rather than
    diffing unit B's buffer against unit A's baseline. }
  FSubject     := AUnitPath;
  FBaselineFile:= ABaselineFile;
  FActive      := True;
  FDiscards    := 0;
  FLaunchedGen := 0;
  FAcceptedGen := 0;
  FBaselineFp  := '';
  FWorklist.Clear;
  Result:= True;
end;

procedure TFanOutEpisode.NoteBaselineFingerprint(const AFingerprint: string);
begin
  FBaselineFp:= AFingerprint;
end;

procedure TFanOutEpisode.NoteLaunch(AGeneration: Integer);
begin
  if AGeneration > FLaunchedGen then FLaunchedGen:= AGeneration;
end;

function TFanOutEpisode.Dispose(AGeneration: Integer;
                                const AResult: TFanOutResult): TFanOutDisposition;
begin
  { ORDER MATTERS. Staleness is checked FIRST: a stale result may also be a
    parse error, and reporting it as a parse error would put a message about
    text the user has already fixed in front of them. }
  if AGeneration < FLaunchedGen then Result:= fdStaleGeneration
  else if not FActive           then Result:= fdSubjectChanged
  else if AResult.ParseError    then Result:= fdParseError
  else                               Result:= fdAccepted;

  { A discard is a launch whose answer was thrown away -- an engine spawned,
    run and abandoned for nothing. Counting it HERE, rather than leaving the
    caller to remember, is what makes the back-off impossible to wire up
    wrongly: there is exactly one place a result is judged. }
  if Result <> fdAccepted then Inc(FDiscards);
end;

procedure TFanOutEpisode.Accept(const AResult: TFanOutResult);
var
  P: string;
begin
  FWorklist.Clear;
  for P in AResult.UnitPaths do FWorklist.Add(P);
  FAcceptedGen:= FLaunchedGen;
  FDiscards   := 0;   { a result that landed proves the pace is workable }
end;

function TFanOutEpisode.DropDependent(const AFile: string): Boolean;
var
  i: Integer;
begin
  Result:= False;
  for i:= FWorklist.Count - 1 downto 0 do
    if SameText(FWorklist[i], AFile) then
    begin
      FWorklist.Delete(i);
      Result:= True;
    end;
  { The episode is over when nothing still points at what was removed. }
  if Result and (FWorklist.Count = 0) then EndEpisode;
end;

procedure TFanOutEpisode.EndEpisode;
begin
  FActive      := False;
  FSubject     := '';
  FBaselineFile:= '';
  FBaselineFp  := '';
  FDiscards    := 0;
  FWorklist.Clear;
end;

function TFanOutEpisode.ShouldEndOnFingerprint(const AFingerprint: string): Boolean;
begin
  Result:= FActive and (FBaselineFp <> '') and (AFingerprint = FBaselineFp);
end;

function TFanOutEpisode.CurrentDebounceMs: Integer;
var
  i: Integer;
begin
  Result:= FANOUT_BASE_DEBOUNCE_MS;
  for i:= 1 to FDiscards do
  begin
    if Result >= FANOUT_MAX_DEBOUNCE_MS then Break;
    Result:= Result * 2;
  end;
  if Result > FANOUT_MAX_DEBOUNCE_MS then Result:= FANOUT_MAX_DEBOUNCE_MS;
end;

procedure TFanOutEpisode.NoteSave;
begin
  { A save resets the PACE but NOT the episode. The question being asked spans
    saves -- "does anything still point at what I removed" -- so re-baselining
    here would silently replace it with "did the last few seconds break
    anything", which nobody asked. }
  FDiscards:= 0;
end;

{ ---- TTreeCompileTrigger -------------------------------------------------- }

procedure TTreeCompileTrigger.Reset;
begin
  FArmed     := False;
  FArmedAt   := 0;
  FQuietMs   := TREE_COMPILE_QUIET_MS;
  FGeneration := 0;
  FForced    := False;
end;

procedure TTreeCompileTrigger.ArmAfterTier2(AGeneration: Integer; ANowTick: UInt64);
begin
  if FQuietMs <= 0 then FQuietMs:= TREE_COMPILE_QUIET_MS;
  FArmed     := True;
  FArmedAt   := ANowTick;
  FGeneration:= AGeneration;
end;

procedure TTreeCompileTrigger.NoteEdit(ANowTick: UInt64);
begin
  if not FArmed then Exit;
  FArmedAt:= ANowTick;
  if FQuietMs < TREE_COMPILE_MAX_QUIET_MS then
  begin
    FQuietMs:= FQuietMs * 2;
    if FQuietMs > TREE_COMPILE_MAX_QUIET_MS then FQuietMs:= TREE_COMPILE_MAX_QUIET_MS;
  end;
end;

procedure TTreeCompileTrigger.NoteSave;
begin
  FQuietMs:= TREE_COMPILE_QUIET_MS;
  if FArmed then FForced:= True;
end;

function TTreeCompileTrigger.ShouldFire(ANowTick: UInt64; out AGeneration: Integer): Boolean;
begin
  AGeneration:= 0;
  Result:= False;
  if not FArmed then Exit;
  if (not FForced) and (ANowTick - FArmedAt < UInt64(FQuietMs)) then Exit;
  AGeneration:= FGeneration;
  FArmed := False;   { at most once per arming }
  FForced:= False;
  Result := True;
end;

end.
