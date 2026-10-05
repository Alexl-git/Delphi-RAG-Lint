program ReportTextTests;

{ DUnitX console runner for DragLint.Plugin.ReportText, the IDE-free half of
  the drag-lint > Reports submenu (catalog, DocInsight formatter, argument and
  output parsers). Build and run through tests\plugin\run_reports_text.ps1.

  `ReportTextTests --ids` prints the catalog's question ids, one per line, and
  runs no tests: the runner script compares that list two-way against the
  ValidateSet of charts\src\New-DiagramArtifact.ps1, so a question added to the
  chart pipeline without a menu item fails the run. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils
  , DUnitX.TestFramework
  , DUnitX.Loggers.Console
  , DragLint.Plugin.ReportText in '..\..\src\delphi-plugin\DragLint.Plugin.ReportText.pas'
  , ReportTextTests.Cases in 'ReportTextTests.Cases.pas'
  ;

const
  EXIT_FAILED = 1;
  EXIT_CRASHED = 2;

var
  Runner : ITestRunner;
  Results: IRunResults;
begin
  if (ParamCount > 0) and SameText(ParamStr(1), '--ids') then
  begin
    for var Q: TReportQuestion in REPORT_QUESTIONS do Writeln(Q.Id);
    Exit;
  end;
  try
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
