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
  , ChartsTests.Process in 'ChartsTests.Process.pas'
  , DRagLint.Charts.Remarks in '..\..\src\charts\DRagLint.Charts.Remarks.pas'
  , DRagLint.Charts.Snapshot in '..\..\src\charts\DRagLint.Charts.Snapshot.pas'
  , ChartsTests.RemarksSnapshot in 'ChartsTests.RemarksSnapshot.pas'
  , DRagLint.Charts.Compare in '..\..\src\charts\DRagLint.Charts.Compare.pas'
  , ChartsTests.Compare in 'ChartsTests.Compare.pas'
  , DRagLint.Charts.Render in '..\..\src\charts\DRagLint.Charts.Render.pas'
  , ChartsTests.Render in 'ChartsTests.Render.pas'
  , DRagLint.Charts.Text in '..\..\src\charts\DRagLint.Charts.Text.pas'
  , ChartsTests.CoreText in 'ChartsTests.CoreText.pas'
  , DRagLint.Charts.Index in '..\..\src\charts\DRagLint.Charts.Index.pas'
  , ChartsTests.CoreIndex in 'ChartsTests.CoreIndex.pas'
  , DRagLint.Charts.Source in '..\..\src\charts\DRagLint.Charts.Source.pas'
  , ChartsTests.CoreSource in 'ChartsTests.CoreSource.pas'
  , DRagLint.Charts.Tools in '..\..\src\charts\DRagLint.Charts.Tools.pas'
  , ChartsTests.CoreTools in 'ChartsTests.CoreTools.pas'
  , DRagLint.Charts.Dot in '..\..\src\charts\DRagLint.Charts.Dot.pas'
  , ChartsTests.CoreDot in 'ChartsTests.CoreDot.pas'
  , DRagLint.Charts.Checks in '..\..\src\charts\DRagLint.Charts.Checks.pas'
  , ChartsTests.CoreChecks in 'ChartsTests.CoreChecks.pas'
  , ChartsTests.CoreMemberAccess in 'ChartsTests.CoreMemberAccess.pas'
  , ChartsTests.CoreTraceFormA in 'ChartsTests.CoreTraceFormA.pas'
  , ChartsTests.CoreTraceShim in 'ChartsTests.CoreTraceShim.pas'
  , ChartsTests.CoreTraceAnchor in 'ChartsTests.CoreTraceAnchor.pas'
  , ChartsTests.CoreTraceWalk in 'ChartsTests.CoreTraceWalk.pas'
  , DRagLint.Charts.Sql in '..\..\src\charts\DRagLint.Charts.Sql.pas'
  , ChartsTests.CoreSql in 'ChartsTests.CoreSql.pas'
  , DRagLint.Charts.Columns in '..\..\src\charts\DRagLint.Charts.Columns.pas'
  , ChartsTests.CoreColumns in 'ChartsTests.CoreColumns.pas'
  , DRagLint.Charts.Chain in '..\..\src\charts\DRagLint.Charts.Chain.pas'
  , ChartsTests.CoreChain in 'ChartsTests.CoreChain.pas'
  , DRagLint.Charts.Exceptions in '..\..\src\charts\DRagLint.Charts.Exceptions.pas'
  , ChartsTests.CoreExceptions in 'ChartsTests.CoreExceptions.pas'
  , DRagLint.Charts.PsSort in '..\..\src\charts\DRagLint.Charts.PsSort.pas'
  , ChartsTests.PsSort in 'ChartsTests.PsSort.pas'
  , DRagLint.Charts.Question in '..\..\src\charts\DRagLint.Charts.Question.pas'
  , DRagLint.Charts.Ask in '..\..\src\charts\DRagLint.Charts.Ask.pas'
  , ChartsTests.Question in 'ChartsTests.Question.pas'
  , DRagLint.Charts.Q.TouchesTables in '..\..\src\charts\DRagLint.Charts.Q.TouchesTables.pas'
  , DRagLint.Charts.Q.ShownWhere in '..\..\src\charts\DRagLint.Charts.Q.ShownWhere.pas'
  , DRagLint.Charts.Q.Deps in '..\..\src\charts\DRagLint.Charts.Q.Deps.pas'
  , DRagLint.Charts.Q.ClassSurface in '..\..\src\charts\DRagLint.Charts.Q.ClassSurface.pas'
  , DRagLint.Charts.Q.EventWiring in '..\..\src\charts\DRagLint.Charts.Q.EventWiring.pas'
  , DRagLint.Charts.Q.TestedBy in '..\..\src\charts\DRagLint.Charts.Q.TestedBy.pas'
  , DRagLint.Charts.Q.ChangeImpact in '..\..\src\charts\DRagLint.Charts.Q.ChangeImpact.pas'
  , DRagLint.Charts.Q.CrossesBoundary in '..\..\src\charts\DRagLint.Charts.Q.CrossesBoundary.pas'
  , DRagLint.Charts.Q.ProtocolTrace in '..\..\src\charts\DRagLint.Charts.Q.ProtocolTrace.pas'
  , DRagLint.Charts.Q.Lifecycle in '..\..\src\charts\DRagLint.Charts.Q.Lifecycle.pas'
  , DRagLint.Charts.Q.Effects in '..\..\src\charts\DRagLint.Charts.Q.Effects.pas'
  , DRagLint.Charts.Q.FeedsFrom in '..\..\src\charts\DRagLint.Charts.Q.FeedsFrom.pas'
  , DRagLint.Charts.Q.LandsWhere in '..\..\src\charts\DRagLint.Charts.Q.LandsWhere.pas'
  , DRagLint.Charts.Q.Consumers in '..\..\src\charts\DRagLint.Charts.Q.Consumers.pas'
  , DRagLint.Charts.Q.ExceptionPaths in '..\..\src\charts\DRagLint.Charts.Q.ExceptionPaths.pas'
  , DRagLint.Charts.Q.WhoCalls in '..\..\src\charts\DRagLint.Charts.Q.WhoCalls.pas'
  , DRagLint.Charts.Q.Butterfly in '..\..\src\charts\DRagLint.Charts.Q.Butterfly.pas'
  , DRagLint.Charts.Q.Hierarchy in '..\..\src\charts\DRagLint.Charts.Q.Hierarchy.pas'
  , DRagLint.Charts.Q.Wiring in '..\..\src\charts\DRagLint.Charts.Q.Wiring.pas'
  , DRagLint.Charts.Q.Path in '..\..\src\charts\DRagLint.Charts.Q.Path.pas'
  , DRagLint.Charts.Q.Architecture in '..\..\src\charts\DRagLint.Charts.Q.Architecture.pas'
  , DRagLint.Charts.Q.Cycles in '..\..\src\charts\DRagLint.Charts.Q.Cycles.pas'
  , DRagLint.Charts.MemberAccess in '..\..\src\charts\DRagLint.Charts.MemberAccess.pas'
  , DRagLint.Charts.Q.MemberAccess in '..\..\src\charts\DRagLint.Charts.Q.MemberAccess.pas'
  , DRagLint.Charts.Trace.FormA in '..\..\src\charts\DRagLint.Charts.Trace.FormA.pas'
  , DRagLint.Charts.Trace.Shim in '..\..\src\charts\DRagLint.Charts.Trace.Shim.pas'
  , DRagLint.Charts.Trace.Anchor in '..\..\src\charts\DRagLint.Charts.Trace.Anchor.pas'
  , DRagLint.Charts.Trace.Calc in '..\..\src\charts\DRagLint.Charts.Trace.Calc.pas'
  , DRagLint.Charts.Trace.Walk in '..\..\src\charts\DRagLint.Charts.Trace.Walk.pas'
  , DRagLint.Charts.Trace.Chart in '..\..\src\charts\DRagLint.Charts.Trace.Chart.pas'
  , DRagLint.Charts.Q.RoundTrip in '..\..\src\charts\DRagLint.Charts.Q.RoundTrip.pas'
  , ChartsTests.CoreTraceChart in 'ChartsTests.CoreTraceChart.pas'
  , ChartsTests.Questions in 'ChartsTests.Questions.pas'
  , DRagLint.Charts.Pairs in '..\..\src\charts\DRagLint.Charts.Pairs.pas'
  , DRagLint.Charts.Producer.Delphi in '..\..\src\charts\DRagLint.Charts.Producer.Delphi.pas'
  , ChartsTests.ProducerDelphi in 'ChartsTests.ProducerDelphi.pas'
  , DRagLint.Charts.AskVerb in '..\..\src\charts\DRagLint.Charts.AskVerb.pas'
  , ChartsTests.AskVerb in 'ChartsTests.AskVerb.pas'
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
