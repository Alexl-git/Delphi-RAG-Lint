program FanOutStateTests;
{$APPTYPE CONSOLE}
{ Everything the fan-out decides, decided without an IDE.

  WHAT THIS PINS. PLAN-lint-tree P3/P5: a background worker spawns an engine
  while you type, abandons it when you type again, and paints rows into a
  message group. The painting needs an IDE. None of the deciding does, and it
  is the deciding that goes wrong quietly:

    a STALE result is shown -> rows point at lines that have moved, which reads
      as a navigation bug rather than as a race, and gets the wrong thing fixed.
    the BASELINE is recaptured on save -> the diff silently becomes "did the
      last few seconds break anything" instead of "does anything still point at
      what I removed", and the tab goes empty at the exact moment the answer
      was about to matter.
    the DISCARD back-off never engages -> a continuously-edited file loops
      discard, re-arm, discard, spawning engines it then kills for the whole
      session.
    the QUIET PERIOD is not reset by an edit -> tier 3 starts dcc while you are
      still typing.

  None of those raises anything. Each one just makes the feature quietly worse,
  which is why they are asserted here rather than left to the O-block: a person
  watching an IDE can see that rows appeared, and cannot see that the ones
  shown were the previous generation's.

  TICKS ARE PARAMETERS, not GetTickCount64 calls, so the 15 s quiet period is
  tested in microseconds and the assertions are exact instead of tolerant. }
uses
  System.SysUtils,
  System.StrUtils,
  DragLint.Plugin.FanOutState in '..\src\delphi-plugin\DragLint.Plugin.FanOutState.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

{ The five engine-target fields, as one value. }
function T(const AProject, APlatform: string): TEngineTarget; forward;

const
  EXE  = 'C:\dl\drag-lint.exe';
  UNIT_= 'C:\p\uB.pas';
  DB   = 'C:\p\_D-RAG\P.sqlite';
  PROJ = 'C:\p\P.dproj';
  BASE = 'C:\tmp\uB.baseline.json';
  BUF  = 'C:\tmp\uB.buffer.pas';

function T(const AProject, APlatform: string): TEngineTarget;
begin
  Result.Exe     := EXE;
  Result.UnitPath:= UNIT_;
  Result.Db      := DB;
  Result.Project := AProject;
  Result.Platform:= APlatform;
end;

{ ---- 1..3: the command lines ---------------------------------------------- }

procedure TestBaselineCmd;
var
  C: string;
begin
  C:= BuildBaselineCmdLine(T(PROJ, 'Win32'), BASE);
  Check('1a the baseline run writes a baseline',
        ContainsText(C, '--write-baseline "' + BASE + '"'), C);
  { The baseline is the state on DISK at the start of the episode. Pass the
    buffer here and the OLD side becomes the text being edited, so every diff
    compares the buffer against itself and finds nothing, forever. }
  Check('1b and it does NOT read the buffer',
        not ContainsText(C, '--buffer'),
        'the baseline would be the edited text, so every diff would be empty: ' + C);
  Check('1c POSITIVE CONTROL: it is a lint-tree run at all',
        ContainsText(C, 'lint-tree') and ContainsText(C, '--unit') and
        ContainsText(C, '--db'), C);
end;

procedure TestFanOutCmd;
var
  C: string;
begin
  C:= BuildFanOutCmdLine(T(PROJ, 'Win32'), BASE, BUF, False);
  Check('2a a run diffs the BUFFER against the episode baseline',
        ContainsText(C, '--buffer "' + BUF + '"') and
        ContainsText(C, '--baseline "' + BASE + '"'), C);
  Check('2b it asks for json', ContainsText(C, '--format json'), C);
  Check('2c tier 2 does NOT compile',
        not ContainsText(C, '--compile'),
        'every keystroke pause would start dcc: ' + C);

  C:= BuildFanOutCmdLine(T(PROJ, 'Win32'), BASE, BUF, True);
  Check('2d tier 3 does', ContainsText(C, '--compile'), C);
end;

procedure TestOptionalArgs;
var
  C: string;
begin
  C:= BuildFanOutCmdLine(T('', ''), BASE, BUF, False);
  Check('3a an unknown project is omitted, not passed empty',
        not ContainsText(C, '--project'),
        'a flag with no value swallows the next argument: ' + C);
  Check('3b so is an unknown platform', not ContainsText(C, '--platform'), C);
  Check('3c POSITIVE CONTROL: the rest survives',
        ContainsText(C, '--buffer') and ContainsText(C, '--baseline'), C);
end;

{ ---- 4..6: parsing -------------------------------------------------------- }

const
  JSON_TWO_FINDINGS =
    '{"schema":"lint-tree/1","unit":"uB.pas","changed":true,"parse_error":false,' +
    '"fingerprint":{"new":"aaa","old":"bbb"},' +
    '"removed_symbols":["uB.FreeProc"],"changed_symbols":[],"added_symbols":[],' +
    '"closure":{"direct":1,"total":3,"ms":2},' +
    '"findings":[' +
    '{"file":"C:\\p\\uA.pas","line":20,"col":8,"rule":"stale-reference",' +
    '"severity":"error","message":"uB.TWidget.Value no longer exists",' +
    '"ref_kind":"member-access","unchecked":false},' +
    '{"file":"C:\\p\\uC.pas","line":9,"col":3,"rule":"stale-reference",' +
    '"severity":"error","message":"uB.FreeProc no longer exists",' +
    '"ref_kind":"call","unchecked":true}],' +
    '"suppressed_ambiguous":2,"compiled":false,"not_reportable":["property","field"]}';

procedure TestParse;
var
  R: TFanOutResult;
begin
  Check('4a it parses', ParseFanOutJson(JSON_TWO_FINDINGS, R) and R.Ok);
  Check('4b changed is read', R.Changed);
  Check('4c both findings survive', Length(R.Findings) = 2,
        Format('%d finding(s)', [Length(R.Findings)]));
  { The member-access row is the one a `kind=call` filter would have dropped --
    a parenless call resolves as member-access, so it is half the findings on
    the engine's own fixture. Asserted BY KIND here too, so a plugin-side
    filter cannot quietly reintroduce what the engine already refused. }
  Check('4d the member-access row is present, by kind',
        (R.Findings[0].RefKind = 'member-access'), R.Findings[0].RefKind);
  Check('4e the unchecked flag survives', R.Findings[1].Unchecked);
  Check('4f the suppression count survives', R.Suppressed = 2,
        Format('suppressed=%d', [R.Suppressed]));
  Check('4g the closure counts survive',
        (R.DirectCnt = 1) and (R.TotalCnt = 3), Format('%d/%d', [R.DirectCnt, R.TotalCnt]));
  Check('4h two distinct dependents', Length(R.UnitPaths) = 2,
        string.Join('|', R.UnitPaths));
end;

procedure TestParseGarbage;
var
  R: TFanOutResult;
begin
  { An unknown verb prints a 300-line usage banner to stdout. A background
    worker that raises on that takes the IDE with it. }
  Check('5a a usage banner does not parse and does not raise',
        not ParseFanOutJson('ERROR: unknown command: lint-tree'#13#10'Usage: ...', R));
  Check('5b and it says why', R.Reason <> '', 'a silent failure cannot be diagnosed');
  Check('5c empty output is handled', not ParseFanOutJson('', R));
  Check('5d truncated json is handled', not ParseFanOutJson('{"changed":tr', R));
end;

procedure TestParseError;
var
  R: TFanOutResult;
begin
  Check('6a a buffer that does not parse is reported as such',
        ParseFanOutJson('{"changed":false,"parse_error":true,"reason":"missing ;",' +
                        '"findings":[]}', R) and R.ParseError);
  Check('6b with the engine''s reason', R.Reason = 'missing ;', R.Reason);
end;

{ ---- 7..11: the episode --------------------------------------------------- }

function MakeResult(const AFiles: array of string): TFanOutResult;
var
  i: Integer;
begin
  Result:= Default(TFanOutResult);
  Result.Ok:= True;
  SetLength(Result.Findings, Length(AFiles));
  for i:= 0 to High(AFiles) do
  begin
    Result.Findings[i].FilePath:= AFiles[i];
    Result.Findings[i].Line    := 10 + i;
    Result.Findings[i].Message := 'gone';
  end;
end;

procedure TestEpisodeBaseline;
var
  E: TFanOutEpisode;
begin
  E:= TFanOutEpisode.Create;
  try
    Check('7a starting an episode asks for a baseline', E.BeginEpisode(UNIT_, BASE));
    { THE ONE THAT MATTERS. The question spans keystrokes and saves: "does
      anything still point at what I removed". Re-baselining mid-episode
      replaces it with "did the last few seconds break anything". }
    Check('7b a second call for the SAME unit does not re-baseline',
          not E.BeginEpisode(UNIT_, BASE),
          'the OLD side would move to the edited text and the answer would vanish');
    Check('7c a DIFFERENT unit does re-baseline',
          E.BeginEpisode('C:\p\uZ.pas', BASE),
          'unit Z''s buffer would be diffed against unit B''s baseline');
  finally
    E.Free;
  end;
end;

procedure TestEpisodeSurvivesSave;
var
  E: TFanOutEpisode;
begin
  E:= TFanOutEpisode.Create;
  try
    E.BeginEpisode(UNIT_, BASE);
    E.NoteSave;
    Check('8a a save does NOT end the episode', E.Active,
          'the baseline would be recaptured from the just-saved text');
    Check('8b and the baseline is still the same file', E.BaselineFile = BASE);
    Check('8c a second BeginEpisode after a save still does not re-baseline',
          not E.BeginEpisode(UNIT_, BASE));
  finally
    E.Free;
  end;
end;

procedure TestGenerations;
var
  E  : TFanOutEpisode;
  Res: TFanOutResult ;
begin
  E:= TFanOutEpisode.Create;
  try
    E.BeginEpisode(UNIT_, BASE);
    Res:= MakeResult(['C:\p\uA.pas']);

    E.NoteLaunch(1);
    Check('9a the current generation is accepted',
          E.Dispose(1, Res) = fdAccepted);

    E.NoteLaunch(2);
    { The whole point of P1's kill: a superseded run STILL RETURNS, because the
      pipe closes. Its answer is about text that no longer exists. }
    Check('9b a superseded generation is discarded',
          E.Dispose(1, Res) = fdStaleGeneration,
          'a late result would paint rows for an edit already undone');
    Check('9c POSITIVE CONTROL: the newest is still accepted',
          E.Dispose(2, Res) = fdAccepted,
          'the check is rejecting everything, which passes 9b for the wrong reason');

    Res.ParseError:= True;
    Check('9d a buffer that did not parse is not shown as an all-clear',
          E.Dispose(2, Res) = fdParseError);
  finally
    E.Free;
  end;
end;

{ 10 -- THE DISCARD BACK-OFF. Without it a continuously-edited file loops
  discard -> re-arm -> discard, spawning an engine every two seconds for as
  long as someone keeps typing, and killing each one. The doubling is what
  turns that from a spin into a retreat, and the cap is what stops the retreat
  outlasting the work: B0(b) measured the worst ORM3 CLIENT unit at 23.5 s, so
  a 30 s cap is always longer than the run it is pacing. }
procedure TestBackOff;
var
  E   : TFanOutEpisode;
  Res : TFanOutResult ;
  Seen: TArray<Integer>;
  Gen : Integer       ;
begin
  E:= TFanOutEpisode.Create;
  try
    E.BeginEpisode(UNIT_, BASE);
    Res:= MakeResult(['C:\p\uA.pas']);

    Check('10a the first wait is the base wait',
          E.CurrentDebounceMs = FANOUT_BASE_DEBOUNCE_MS,
          Format('%d', [E.CurrentDebounceMs]));

    { Supersede five times in a row: launch N+1 while N is still out, then let
      N come back to nothing. }
    SetLength(Seen, 0);
    for Gen:= 1 to 5 do
    begin
      E.NoteLaunch(Gen);
      E.NoteLaunch(Gen + 1);
      E.Dispose(Gen, Res);
      Seen:= Seen + [E.CurrentDebounceMs];
    end;

    Check('10b each consecutive discard doubles the wait',
          (Seen[0] = 4000) and (Seen[1] = 8000) and (Seen[2] = 16000),
          Format('%d, %d, %d', [Seen[0], Seen[1], Seen[2]]));
    Check('10c and it is capped',
          (Seen[3] = FANOUT_MAX_DEBOUNCE_MS) and (Seen[4] = FANOUT_MAX_DEBOUNCE_MS),
          Format('%d, %d', [Seen[3], Seen[4]]));

    { A save is the user stopping. Whatever the pace had backed off to, the
      next question deserves a prompt answer. }
    E.NoteSave;
    Check('10d a save resets the wait',
          E.CurrentDebounceMs = FANOUT_BASE_DEBOUNCE_MS,
          Format('%d', [E.CurrentDebounceMs]));

    { POSITIVE CONTROL for 10d: an ACCEPTED result must reset it too, or the
      pace only ever recovers when someone happens to save. }
    E.NoteLaunch(9); E.NoteLaunch(10); E.Dispose(9, Res);
    Check('10e a discard after the reset backs off again',
          E.CurrentDebounceMs = 4000, Format('%d', [E.CurrentDebounceMs]));
    E.NoteLaunch(11);
    E.Dispose(11, Res);
    E.Accept(Res);
    Check('10f an accepted result resets the wait',
          E.CurrentDebounceMs = FANOUT_BASE_DEBOUNCE_MS,
          Format('%d -- the pace would only recover on a save', [E.CurrentDebounceMs]));
  finally
    E.Free;
  end;
end;

procedure TestWorklist;
var
  E  : TFanOutEpisode;
  Res: TFanOutResult ;
begin
  E:= TFanOutEpisode.Create;
  try
    E.BeginEpisode(UNIT_, BASE);
    E.NoteLaunch(1);
    Res:= MakeResult(['C:\p\uA.pas', 'C:\p\uC.pas', 'C:\p\uA.pas']);
    E.Accept(Res);
    Check('11a the worklist is the DISTINCT dependents', E.Worklist.Count = 2,
          Format('%d', [E.Worklist.Count]));

    { An edit to ONE dependent drops ONLY its rows. Discarding the whole result
      would blank the tab every time you touched any file it named -- which is
      exactly what you do next, because it just told you to. }
    Check('11b editing one dependent drops only its rows',
          E.DropDependent('C:\p\uA.pas') and (E.Worklist.Count = 1),
          Format('%d left', [E.Worklist.Count]));
    Check('11c and the episode is still alive', E.Active);

    Check('11d editing the last one ends the episode',
          E.DropDependent('C:\p\uC.pas') and not E.Active,
          'an empty tab would linger with nothing left to answer');
  finally
    E.Free;
  end;
end;

procedure TestFingerprintEnd;
var
  E: TFanOutEpisode;
begin
  E:= TFanOutEpisode.Create;
  try
    E.BeginEpisode(UNIT_, BASE);
    E.NoteBaselineFingerprint('abc');
    Check('12a a different shape keeps the episode open',
          not E.ShouldEndOnFingerprint('def'));
    Check('12b undoing back to the baseline shape ends it',
          E.ShouldEndOnFingerprint('abc'),
          'the tab would keep showing an impact the user has already undone');
  finally
    E.Free;
  end;
end;

{ ---- 13..15: the tier-3 trigger ------------------------------------------- }

procedure TestTreeCompileTrigger;
var
  T  : TTreeCompileTrigger;
  Gen: Integer            ;
begin
  T.Reset;
  Check('13a nothing fires before tier 2 has finished',
        not T.ShouldFire(999999, Gen), 'dcc would start with nothing to compile');

  T.ArmAfterTier2(7, 1000);
  Check('13b nor during the quiet period',
        not T.ShouldFire(1000 + TREE_COMPILE_QUIET_MS - 1, Gen),
        'dcc would start while the user is still typing');
  Check('13c it fires once the pause is long enough',
        T.ShouldFire(1000 + TREE_COMPILE_QUIET_MS + 1, Gen));
  Check('13d for the generation tier 2 answered', Gen = 7, Format('gen=%d', [Gen]));
  Check('13e and only ONCE per arming',
        not T.ShouldFire(9999999, Gen),
        'every tick would start another compile of the same thing');
end;

procedure TestTreeCompileBackOff;
var
  T  : TTreeCompileTrigger;
  Gen: Integer            ;
  Q0 : Integer            ;
begin
  { AN EDIT DOES TWO THINGS -- lengthens the quiet period AND restarts it --
    and they have to be told apart. Measured 2026-09-10: with the restart
    deleted outright the suite stayed 64/64 GREEN, because the check was made
    at an instant the LENGTHENING alone was already enough to refuse. So the
    edit is placed far from the arming, and 14b is asked at a moment that falls
    AFTER the original arming's deadline and BEFORE the edit's. Only an
    implementation that moved the clock can refuse there. }
  T.Reset;
  T.ArmAfterTier2(1, 1000);
  Q0:= T.QuietMs;
  T.NoteEdit(10000);
  Check('14a an edit lengthens the quiet period', T.QuietMs > Q0,
        Format('%d -> %d', [Q0, T.QuietMs]));
  Check('14b and restarts it, measured from the EDIT and not the arming',
        not T.ShouldFire(1000 + UInt64(T.QuietMs) + 1, Gen),
        'the clock kept running from the ORIGINAL arming, so the edit bought nothing');
  Check('14c it still fires once the pause is that long AFTER the edit',
        T.ShouldFire(10000 + UInt64(T.QuietMs) + 1, Gen));

  T.Reset;
  T.ArmAfterTier2(1, 0);
  T.NoteEdit(1); T.NoteEdit(2); T.NoteEdit(3); T.NoteEdit(4); T.NoteEdit(5);
  Check('14d the back-off is capped', T.QuietMs = TREE_COMPILE_MAX_QUIET_MS,
        Format('%d', [T.QuietMs]));
end;

procedure TestSaveForcesCompile;
var
  T  : TTreeCompileTrigger;
  Gen: Integer            ;
begin
  T.Reset;
  T.ArmAfterTier2(4, 1000);
  T.NoteEdit(2000);                 { pushed the quiet period out }
  T.NoteSave;
  { A save is the one moment the user has declared the state final, so it
    overrides the quiet period instead of restarting it. }
  Check('15a a save fires the compile immediately',
        T.ShouldFire(2001, Gen),
        'the user saved and then waited a minute for a compile they asked for');
  Check('15b for the right generation', Gen = 4, Format('gen=%d', [Gen]));
  Check('15c and the back-off is reset', T.QuietMs = TREE_COMPILE_QUIET_MS,
        Format('%d', [T.QuietMs]));

  { NEGATIVE CONTROL: a save with nothing armed must not start a compile. }
  T.Reset;
  T.NoteSave;
  Check('15d a save with nothing armed fires nothing',
        not T.ShouldFire(999999, Gen),
        'every Ctrl+S would start a full dependent compile');
end;

{ ---- 16: the row text ----------------------------------------------------- }

procedure TestRowText;
var
  F: TFanOutFinding;
  R: TFanOutResult ;
begin
  F:= Default(TFanOutFinding);
  F.Message:= 'uB.FreeProc no longer exists';
  F.RefKind:= 'call';
  Check('16a a row names the reference kind',
        ContainsText(FindingRowText(F), 'call'), FindingRowText(F));
  Check('16b a checked row carries no unchecked marker',
        not ContainsText(FindingRowText(F), 'UNCHECKED'), FindingRowText(F));

  F.Unchecked:= True;
  { Said out loud, because the line may have moved: a user told so reads a near
    miss as expected, a user not told reads it as the feature being broken. }
  Check('16c an unchecked row says so',
        ContainsText(FindingRowText(F), 'UNCHECKED'), FindingRowText(F));

  ParseFanOutJson(JSON_TWO_FINDINGS, R);
  Check('16d the title counts places, units and the generation',
        ContainsText(FanOutTitleText(R, 3), '2 place') and
        ContainsText(FanOutTitleText(R, 3), '2 unit') and
        ContainsText(FanOutTitleText(R, 3), 'gen 3'),
        FanOutTitleText(R, 3));
  { An uncounted suppression is the all-clear this whole verb exists to
    prevent, so it has to reach the one line the user actually reads. }
  Check('16e and reports the ambiguous names it did NOT check',
        ContainsText(FanOutTitleText(R, 3), '2 ambiguous'),
        FanOutTitleText(R, 3));

  { 2026-09-14. THE ZERO THAT LOOKED LIKE A BUG. Removing two public properties
    from a class with 207 dependents produced "0 place(s) in 0 unit(s)", which
    is the right answer to "did a REPORTABLE reference break" and the wrong
    answer to what the reader is asking. Property reads are never bound to a
    symbol id (the resolver only walks kind='call' refs), so the engine reports
    the kind in not_reportable -- and the title has to say it, or silence reads
    as an all-clear. }
  ParseFanOutJson(
    '{"schema":"lint-tree/1","changed":true,"findings":[],' +
    '"suppressed_ambiguous":0,"not_reportable":["property"]}', R);
  Check('16f a kind the run could NOT check is named in the title',
        ContainsText(FanOutTitleText(R, 9), 'property') and
        ContainsText(FanOutTitleText(R, 9), 'NOT checked'),
        FanOutTitleText(R, 9));

  { POSITIVE CONTROL. Without it, a builder that appended the phrase
    unconditionally would pass 16f and quietly put "NOT checked" on every clean
    run -- the opposite failure, and just as misleading.

    It gets its OWN json rather than reusing JSON_TWO_FINDINGS, and that is the
    point rather than a convenience: that fixture was captured when the engine
    emitted a HARD-CODED not_reportable of ["property","field"] on every run,
    so reusing it made this check fail the moment it was written. The engine now
    computes the list from the delta, so "nothing unreportable" is an empty list
    -- and this fixture says so explicitly. }
  ParseFanOutJson(
    '{"schema":"lint-tree/1","changed":true,' +
    '"findings":[{"file":"C:\\p\\uA.pas","line":10,"col":3,"rule":"stale-interface-reference",' +
    '"severity":"warning","message":"m"}],' +
    '"suppressed_ambiguous":0,"not_reportable":[]}', R);
  Check('16g a run with nothing unreportable says no such thing',
        not ContainsText(FanOutTitleText(R, 3), 'NOT checked'),
        FanOutTitleText(R, 3));
end;

begin
  GPass:= 0;
  GFail:= 0;
  Writeln('FanOutStateTests');

  try
    TestBaselineCmd;
    TestFanOutCmd;
    TestOptionalArgs;
    TestParse;
    TestParseGarbage;
    TestParseError;
    TestEpisodeBaseline;
    TestEpisodeSurvivesSave;
    TestGenerations;
    TestBackOff;
    TestWorklist;
    TestFingerprintEnd;
    TestTreeCompileTrigger;
    TestTreeCompileBackOff;
    TestSaveForcesCompile;
    TestRowText;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
