program ChartsTests;

{ DUnitX console runner for the engine-side charts units under src\charts (diff
  core, report adapters, compare, renderers). Build and run through
  tests\charts\run_charts_tests.ps1.

  `ChartsTests --filter <prefix>` runs only the fixtures whose full name starts
  with <prefix> (DUnitX TNameFilter), e.g. `--filter ChartsTests.Diff`.

  Each later task appends its src\charts unit and its ChartsTests.<Name> case
  unit to the uses list below, one per line. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils
  , DUnitX.TestFramework
  , DUnitX.Filters
  , DUnitX.Loggers.Console
  , DRagLint.Charts.Diff in '..\..\src\charts\DRagLint.Charts.Diff.pas'
  , ChartsTests.Diff in 'ChartsTests.Diff.pas'
  , DRagLint.Charts.ReportHeader in '..\..\src\charts\DRagLint.Charts.ReportHeader.pas'
  , ChartsTests.ReportHeader in 'ChartsTests.ReportHeader.pas'
  , DRagLint.Charts.DocInsight in '..\..\src\charts\DRagLint.Charts.DocInsight.pas'
  , ChartsTests.DocInsight in 'ChartsTests.DocInsight.pas'
  , DRagLint.Charts.Adapter.Text in '..\..\src\charts\DRagLint.Charts.Adapter.Text.pas'
  , ChartsTests.AdapterText in 'ChartsTests.AdapterText.pas'
  , DRagLint.Charts.Adapter.FormsCsv in '..\..\src\charts\DRagLint.Charts.Adapter.FormsCsv.pas'
  , DRagLint.Charts.Adapter.Graph in '..\..\src\charts\DRagLint.Charts.Adapter.Graph.pas'
  , DRagLint.Charts.Adapters in '..\..\src\charts\DRagLint.Charts.Adapters.pas'
  , ChartsTests.Adapters in 'ChartsTests.Adapters.pas'
  , DRagLint.Charts.Process in '..\..\src\charts\DRagLint.Charts.Process.pas'
  , DRagLint.Charts.Producer in '..\..\src\charts\DRagLint.Charts.Producer.pas'
  , DRagLint.Charts.Producer.PowerShell in '..\..\src\charts\DRagLint.Charts.Producer.PowerShell.pas'
  , ChartsTests.Producer in 'ChartsTests.Producer.pas'
  , DRagLint.Charts.Remarks in '..\..\src\charts\DRagLint.Charts.Remarks.pas'
  , DRagLint.Charts.Snapshot in '..\..\src\charts\DRagLint.Charts.Snapshot.pas'
  , ChartsTests.RemarksSnapshot in 'ChartsTests.RemarksSnapshot.pas'
  ;

const
  EXIT_FAILED = 1;
  EXIT_CRASHED = 2;
  FILTER_SWITCH = '--filter';

var
  Runner : ITestRunner;
  Results: IRunResults;
begin
  try
    if (ParamCount >= 2) and SameText(ParamStr(1), FILTER_SWITCH) then
      TDUnitX.Filter:= TNameFilter.Create(ParamStr(2));
    Runner:= TDUnitX.CreateRunner;
    Runner.UseRTTI:= True;
    Runner.FailsOnNoAsserts:= True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results:= Runner.Execute;
    Writeln(Format('%d passed, %d failed', [Results.PassCount, Results.FailureCount + Results.ErrorCount]));
    if not Results.AllPassed then System.ExitCode:= EXIT_FAILED;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode:= EXIT_CRASHED;
    end;
  end;
end.
