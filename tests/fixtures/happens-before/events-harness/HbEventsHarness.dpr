program HbEventsHarness;

{ Console harness for DRagLint.Query.HappensBefore.Events (lane HBEVENTS): runs CollectEvents and
  HbIsNeverSet on one target and prints the check-init JSON shape (HbAnswerJson) of the events:
  `target`, `writers[]` and `uses[]` exactly as the verb will print them, `verdict` NEVER-SET when
  HbIsNeverSet holds else MAY-BE-UNSET, answer-level `reasons` = the NEVER-SET blockers, `limits`
  = ['events-only'] plus 'published' / 'absolute-overlay' when set. Not a verdict engine: the
  solver lane orders the events.
  Usage: HbEventsHarness <db> <QName or -> [<file>:<line>[:<col>]]
  Exit 0 = answered; 2 = EHbUsage (message and candidates on stderr). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Charts.Index,
  DRagLint.Query.HappensBefore.Types,
  DRagLint.Query.HappensBefore.Render,
  DRagLint.Query.HappensBefore.Events in '..\..\..\..\src\query\DRagLint.Query.HappensBefore.Events.pas';

var
  Index: TChartsIndex;
  At: THbSite;
  Target: string;
  Events: THbEvents;
  Answer: THbAnswer;
  Blockers: TArray<THbReason>;
begin
  ExitCode:= 0;
  if ParamCount < 2 then
  begin
    Writeln(ErrOutput, 'usage: HbEventsHarness <db> <QName or -> [<file>:<line>[:<col>]]');
    Halt(2);
  end;
  Target:= if ParamStr(2) = '-' then '' else ParamStr(2);
  At:= Default(THbSite);
  if (ParamCount >= 3) and not HbParseAt(ParamStr(3), At) then
  begin
    Writeln(ErrOutput, 'ERROR: bad --at ', ParamStr(3));
    Halt(2);
  end;
  Index:= TChartsIndex.Create(ParamStr(1));
  try
    try
      Events:= CollectEvents(Index, Target, At);
    except
      on E: EHbUsage do
      begin
        Writeln(ErrOutput, 'ERROR: ', E.Message);
        for var C in E.Candidates do Writeln(ErrOutput, '       candidate: ', C);
        Halt(2);
      end;
    end;
  finally
    Index.Free;
  end;
  Answer:= Default(THbAnswer);
  Answer.Target:= Events.Target;
  Answer.Writers:= Events.Writers;
  Answer.Verdict:= if HbIsNeverSet(Events, Blockers) then hvNeverSet else hvMayBeUnset;
  Answer.Reasons:= Blockers;
  Answer.Limits:= ['events-only'];
  if Events.IsPublished then Answer.Limits:= Answer.Limits + ['published'];
  if Events.AbsoluteOverlay then Answer.Limits:= Answer.Limits + ['absolute-overlay'];
  for var U in Events.UseSites do
  begin
    var J:= Default(THbUseAnswer);
    J.Site:= U.Site;
    J.Verdict:= hvMayBeUnset;
    if U.GuardedTest then J.Reasons:= [hrGuardedTest];
    Answer.JudgedUses:= Answer.JudgedUses + [J];
  end;
  Writeln(HbAnswerJson(Answer));
end.