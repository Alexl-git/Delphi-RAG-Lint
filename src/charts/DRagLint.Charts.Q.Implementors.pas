unit DRagLint.Charts.Q.Implementors;

(* The `implementors` question (1.40, spec docs\superpowers\specs\2026-11-01-interface-report-design.md):
  the interface report as a chart. Delphi-only -- there is no Emit-*.ps1 for it; the engine is
  DRagLint.Query.Implementors, the same one the `implementors` verb, the LSP and the MCP tool use,
  so the chart and `drag-lint implementors --format dot` draw the same picture. *)

interface

const
  /// <summary>The registered question id.</summary>
  IMPLEMENTORS_ID = 'implementors';

implementation

uses
  System.SysUtils, System.RegularExpressions,
  DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Charts.Question, DRagLint.Charts.Dot, DRagLint.Charts.Text,
  DRagLint.Query.Implementors;

/// <summary>Answers `implementors` for pArgs.Target: interface, interface member, class or class method.</summary>
/// <param name="pArgs">The question arguments; Target is the symbol, Cap bounds the listed sites.</param>
/// <param name="pOutDir">Where the layout files are written.</param>
/// <returns>The chart result: LeftCount = implementors, RightCount = sites.</returns>
/// <exception cref="EChartsQuestion">The target matches no reportable symbol, or several.</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore on the guarded DB.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  Result:= Default(TChartResult);
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);
  var Opts:= TImplementorsOptions.Defaults;
  Opts.WithUses:= True;
  if pArgs.Cap > 0 then Opts.MaxSites:= pArgs.Cap;
  var Report: TImplementorsReport;
  try
    Report:= BuildImplementorsReport(Store, pArgs.Target, Opts);
  except
    on E: EImplementorsTarget do
      raise EChartsQuestion.Create(E.Message);
  end;
  var Msgs: TArray<string>;
  var Base:= TRegEx.Replace(Report.TargetQName, '[^A-Za-z0-9]', '_') + '_implementors';
  { RowHref is already XML-escaped, as the HTML-like label's TD HREF needs. }
  Result.Layout:= DotLayout(pArgs.Dot, ImplementorsReportToChart(Report, False,
    function(pFile: string; pLine: Integer): string
    begin
      Result:= RowHref(pFile, pLine);
    end), pOutDir, Base, Msgs);
  Result.LeftCount:= Length(Report.Implementors);
  Result.RightCount:= Report.SitesTotal;
  Result.ClickTargets:= Result.Layout.Anchors;
  Result.AllClickable:= Result.Layout.Anchors > 0;
  Result.Fields:= [TMetaField.Str('Resolved', Report.TargetQName), TMetaField.Str('Kind', Report.TargetKind),
    TMetaField.Int('Implementors', Length(Report.Implementors)), TMetaField.Int('Unanswered', Length(Report.Unanswered)),
    TMetaField.Int('Sites', Report.SitesTotal), TMetaField.Int('ShownSites', Length(Report.Sites)),
    TMetaField.Int('LibraryImplementors', Report.LibraryImplementors)];
end;

initialization
  RegisterChartQuestion(IMPLEMENTORS_ID, Emit);

end.
