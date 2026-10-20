program CycleFixHarness;

{ E18 T15b: drives the pure cycle-fix helpers of DragLint.Plugin.DiagList (CycleFixSummary,
  CycleFixCanApply, CycleFixConfirmText, CycleFixWrittenFiles) over the captured
  tests\fixtures\cyclefix\outcome-*.json documents and a few inline ones, printing key=value
  lines for run_plugin_cyclefix_summary.ps1. Arg 1: the fixture directory. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DragLint.Plugin.DiagList;

var
  Dir: string;

function Fixture(const AName: string): string;
begin
  Result:= TFile.ReadAllText(TPath.Combine(Dir, AName));
end;

function OneLine(const AText: string): string;
begin
  Result:= StringReplace(AText, #13#10, '|', [rfReplaceAll]);
end;

begin
  Dir:= ParamStr(1);
  try
    Writeln('sum.applied=', CycleFixSummary(Fixture('outcome-applied.json')));
    Writeln('sum.dirty=', CycleFixSummary(Fixture('outcome-refused-dirty-baseline.json')));
    Writeln('sum.dry=', CycleFixSummary(Fixture('outcome-dryrun.json')));
    Writeln('sum.parta=', CycleFixSummary(Fixture('outcome-dryrun-parta.json')));
    Writeln('sum.interleaved=', CycleFixSummary('drag-lint: note: cycles --plan reads no platform library'#13#10 +
      Fixture('outcome-dryrun.json') + #13#10'drag-lint: note: done {x}'));
    Writeln('sum.rolled=', CycleFixSummary('{"schema":"cycle-fix/1","mode":"apply","error":' +
      '"rolled back, project not changed: build error: E2003 Undeclared identifier","ok":false,"exit_code":2}'));
    Writeln('sum.grouprefused=', CycleFixSummary('{"schema":"cycle-fix/1","mode":"dry-run",' +
      '"baseline":{"status":"ok","seconds":1.0,"errors":[]},"refusals":[],"cycles":[{"verdict":"refused",' +
      '"refusals":[{"kind":"receiver-unknown","reason":"Sender has no static class"}]}]}'));
    Writeln('sum.garbage=', CycleFixSummary('ERROR: database not found'));
    Writeln('sum.otherschema=', CycleFixSummary('{"schema":"uses-fix/1"}'));
    Writeln('can.dry=', CycleFixCanApply(Fixture('outcome-dryrun.json')));
    Writeln('can.applied=', CycleFixCanApply(Fixture('outcome-applied.json')));
    Writeln('can.dirty=', CycleFixCanApply(Fixture('outcome-refused-dirty-baseline.json')));
    Writeln('confirm.dry=', OneLine(CycleFixConfirmText(Fixture('outcome-dryrun.json'))));
    Writeln('confirm.parta=', OneLine(CycleFixConfirmText(Fixture('outcome-dryrun-parta.json'))));
    Writeln('confirm.garbage=[', CycleFixConfirmText('nothing'), ']');
    var W: TArray<string>:= CycleFixWrittenFiles(Fixture('outcome-applied.json'));
    Writeln('written.count=', Length(W));
    if Length(W) > 0 then Writeln('written.first=', W[0]);
    Writeln('written.dry=', Length(CycleFixWrittenFiles(Fixture('outcome-dryrun.json'))));
    Writeln('edited.dry=', Length(CycleFixEditedFiles(Fixture('outcome-dryrun.json'))));
    Writeln('edited.garbage=', Length(CycleFixEditedFiles('nothing')));
    Writeln('DONE');
  except
    on E: Exception do Writeln('EXCEPTION=', E.ClassName, ': ', E.Message);
  end;
end.
