program LintOutputParseTests;
{$APPTYPE CONSOLE}
{ Pins INBOX-livediag-parser-line1-fallback.md: a line that is not a finding
  must be REJECTED, never turned into a finding on line 1 of the user's file.

  THE POSITIVE CONTROLS ARE THE POINT. Rejecting everything would satisfy every
  "must not parse" assertion here, so the ordinary-finding cases must pass in
  the same run or the suite proves nothing. }
uses
  System.SysUtils,
  DragLint.Plugin.LintOutputParse in '..\..\src\delphi-plugin\DragLint.Plugin.LintOutputParse.pas';

var
  GFail: Integer = 0;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then Writeln('PASS ', AName)
  else begin Writeln('FAIL ', AName); Inc(GFail); end;
end;

const
  { An ordinary finding, exactly as the engine prints it. }
  GOOD =
    'C:\Projects\X\uFoo.pas:147:9  [info] case-magic-numbers: Case label is a literal';

  { The engine's stderr note, verbatim. Contains colons and no location. Under
    the old parser this cleared both guards and landed on LINE 1. }
  NOTE =
    'drag-lint: note: `lint <file>` runs per-file rules only. Whole-run rules ' +
    'need `lint-all` and are NOT reported here.';

  { THE OBSERVED INTERLEAVE: the note cut mid-word with a whole finding spliced
    in, because stdout and stderr share one pipe. The finding must survive. }
  SPLICED =
    'drag-lint: note: ... a 0 above does not mean they are cle' +
    'C:\Projects\X\uFoo.pas:147:9  [info] case-magic-numbers: Case label is a literal';

  { A note carrying its own brackets BEFORE the real finding. This is the case
    the old "first [" scan got wrong by luck rather than by construction. }
  BRACKETY =
    'drag-lint: note: see [lint-all] for whole-run rules ' +
    'C:\Projects\X\uFoo.pas:12:3  [warning] bare-except: Bare except';

  SUMMARY  = '5 finding(s)';
  DEFAULTS = '(loaded defaults from C:\Projects\.drag-lint.json)';
  TAILWORD = 'an.';
  NOCOLON  = 'something entirely unrelated';
  BADNUM   = 'C:\Projects\X\uFoo.pas:abc:9  [info] rule: msg';
  BADCOL   = 'C:\Projects\X\uFoo.pas:147:xyz  [info] rule: msg';
  UNCLOSED = 'C:\Projects\X\uFoo.pas:147:9  [info rule: msg';
  REALLY1  = 'C:\Projects\X\uFoo.pas:1:1  [error] syntax: broken';

var
  L, C: Integer;
  T, R: string;
  { SelectPaneRows fixture state }
  Rep       : TArray<string> ;
  Rows      : TArray<TPaneRow>;
  Total     : Integer        ;
  RulesShown: Integer        ;
  I, J      : Integer        ;
  Dupes     : Integer        ;
  Found     : Boolean        ;

begin
  Writeln('-- findings must parse (positive controls) --');
  Check('GOOD parses', TryParseFindingLine(GOOD, L, C, T, R));
  Check('GOOD line=147', L = 147);
  Check('GOOD col=9', C = 9);
  Check('GOOD tag=info', T = 'info');
  Check('GOOD rest starts with rule', R.StartsWith('case-magic-numbers:'));

  Check('SPLICED still parses', TryParseFindingLine(SPLICED, L, C, T, R));
  Check('SPLICED line=147 (not 1)', L = 147);
  Check('SPLICED col=9', C = 9);

  Check('BRACKETY parses past the note bracket', TryParseFindingLine(BRACKETY, L, C, T, R));
  Check('BRACKETY line=12', L = 12);
  Check('BRACKETY tag=warning', T = 'warning');

  Check('a genuine line-1 finding still parses', TryParseFindingLine(REALLY1, L, C, T, R));
  Check('  and reports line 1', L = 1);

  Writeln;
  Writeln('-- non-findings must be REJECTED, not defaulted to line 1 --');
  Check('NOTE rejected',     not TryParseFindingLine(NOTE,     L, C, T, R));
  Check('  and leaves L=0',  L = 0);
  Check('SUMMARY rejected',  not TryParseFindingLine(SUMMARY,  L, C, T, R));
  Check('DEFAULTS rejected', not TryParseFindingLine(DEFAULTS, L, C, T, R));
  Check('TAILWORD rejected', not TryParseFindingLine(TAILWORD, L, C, T, R));
  Check('NOCOLON rejected',  not TryParseFindingLine(NOCOLON,  L, C, T, R));
  Check('BADNUM rejected',   not TryParseFindingLine(BADNUM,   L, C, T, R));
  Check('BADCOL rejected',   not TryParseFindingLine(BADCOL,   L, C, T, R));
  Check('  BADCOL leaves L=0 (no half-set out-param)', L = 0);
  Check('UNCLOSED rejected', not TryParseFindingLine(UNCLOSED, L, C, T, R));
  Check('empty rejected',    not TryParseFindingLine('',       L, C, T, R));

  Writeln;
  Writeln('-- Messages-pane allocation (SelectPaneRows) --');
  { THE DEFECT: the pane took the report's FIRST N lines. The report is ordered
    by file and most of a real run is [info], so on ORM3 the 2000 slots filled
    with hints from the earliest files and `circular-uses` -- 2 warnings at
    report line 29457 of 49242 -- never appeared. Owner, 2026-09-13: "Messages
    window doesn't have the circular dependency report at all."

    The fixture reproduces that SHAPE in miniature: a pile of info rows first,
    the rare warning last, and a cap smaller than the pile. }
  SetLength(Rep, 0);
  for I := 1 to 12 do
    Rep := Rep + [Format('C:\P\uNoise.pas:%d:1  [info] public-field: Public field', [I])];
  Rep := Rep + ['C:\P\uLate.pas:9:1  [warning] circular-uses: Circular unit dependency among 2 units'];
  Rep := Rep + ['C:\P\uLate.pas:11:1  [error] syntax-error: broken'];

  Rows := SelectPaneRows(Rep, 3, Total, RulesShown);

  Check('counts every parseable finding, not just the posted ones', Total = 14);
  Check('respects the cap', Length(Rows) = 3);

  { THE ASSERTION THAT WOULD HAVE CAUGHT THE ORIGINAL DEFECT. Under first-N,
    a cap of 3 returns three public-field rows and nothing else. }
  Found := False;
  for I := 0 to High(Rows) do
    if Pos('circular-uses', Rows[I].Text) > 0 then Found := True;
  Check('the RARE rule survives a cap smaller than the noise (the actual bug)', Found);

  Found := False;
  for I := 0 to High(Rows) do
    if Pos('syntax-error', Rows[I].Text) > 0 then Found := True;
  Check('so does the error', Found);

  Check('every distinct rule got a row', RulesShown = 3);
  Check('worst severity is presented first', Pos('[error]', Rows[0].Text) > 0);

  { NARROWNESS -- a row must never be posted twice. Pass 1 and pass 2 walk the
    same list in different orders, so identity has to survive the reordering. }
  Dupes := 0;
  for I := 0 to High(Rows) do
    for J := I + 1 to High(Rows) do
      if (Rows[I].Order = Rows[J].Order) then Inc(Dupes);
  Check('no row is posted twice', Dupes = 0);

  { POSITIVE CONTROL for the cap itself: given room, everything is returned.
    Without this, "respects the cap" is satisfied by a function that returns
    nothing at all. }
  Rows := SelectPaneRows(Rep, 100, Total, RulesShown);
  Check('positive control: a cap above the total returns everything', Length(Rows) = 14);
  Check('positive control: unparseable lines are still rejected',
        Length(SelectPaneRows([NOTE, 'plain text'], 10, Total, RulesShown)) = 0);

  Writeln;
  Writeln('-- severity mapping --');
  Check('error -> 1',   SeverityFromTag('error')   = 1);
  Check('warning -> 2', SeverityFromTag('warning') = 2);
  Check('warn -> 2',    SeverityFromTag('warn')    = 2);
  Check('info -> 3',    SeverityFromTag('info')    = 3);
  Check('hint -> 4',    SeverityFromTag('hint')    = 4);
  Check('unknown -> 3 (info, the least alarming)', SeverityFromTag('zzz') = 3);

  Writeln;
  if GFail > 0 then
  begin
    Writeln(Format('FAIL (%d)', [GFail]));
    ExitCode := 1;
  end
  else
  begin
    Writeln('PASS');
    ExitCode := 0;
  end;
end.
