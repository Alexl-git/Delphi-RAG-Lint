unit DRagLint.Charts.Adapters;

{ The format dispatcher of `drag-lint compare` (spec 6a, D5-D8): decides which adapter a
  file or a text belongs to and hands the text to it, so the one diff core never learns a
  format. Compare refuses when old and new are different formats (D8); the refusal
  message is the command's, the format name it prints comes from FormatName.

  PS trap handled: file extensions and the 'digraph' keyword are matched
  case-INSENSITIVELY on purpose (a Windows path is case-blind), whereas the item keys the
  adapters produce stay ordinal.

  Pure apart from DirectoryExists / FileExists on a folder path. }

interface

uses
  DRagLint.Charts.Diff;

type
  /// <summary>The comparable formats.</summary>
  TChartsFormat = (cfUnknown, cfReportText, cfFormsCsv, cfGraph);

/// <summary>Which adapter a path or a text belongs to.</summary>
/// <param name="pPathOrText">A path (pIsPath True) or the file's text (False).</param>
/// <param name="pIsPath">True when pPathOrText is a path: the folder or extension decides
/// -- a folder holding graph.dot or a .dot file is cfGraph, .csv is cfFormsCsv, .txt .md
/// .pas .log .text or no extension is cfReportText, anything else cfUnknown. False when it
/// is the text: IsFormsCsv is cfFormsCsv, a text whose first non-blank line starts with
/// 'digraph' or 'graph' (any case) AND carries a '{' on that line is cfGraph, everything else -- an empty text too, an
/// empty report being a legitimate answer -- is cfReportText.</param>
/// <returns>The format; cfUnknown only for a path.</returns>
function DetectFormat(const pPathOrText: string; pIsPath: Boolean): TChartsFormat;

/// <summary>The diff items of a text in a given format.</summary>
/// <param name="pFormat">The format DetectFormat found.</param>
/// <param name="pText">The file's text (for cfGraph the DOT text).</param>
/// <returns>cfReportText: ReportItems; cfFormsCsv: FormsCsvItems; cfGraph:
/// GraphItems(ParseDot); cfUnknown: an empty array.</returns>
function ItemsFor(pFormat: TChartsFormat; const pText: string): TArray<TDiffItem>;

/// <summary>The name a refusal or a header prints for a format.</summary>
/// <param name="pFormat">A format.</param>
/// <returns>'report', 'forms-csv', 'chart-graph'; 'unknown' for cfUnknown.</returns>
function FormatName(pFormat: TChartsFormat): string;

implementation

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Charts.Adapter.Text, DRagLint.Charts.Adapter.FormsCsv, DRagLint.Charts.Adapter.Graph;

const
  BOM = #$FEFF;
  EXT_DOT = '.dot';
  EXT_CSV = '.csv';
  BUNDLE_DOT = 'graph.dot';
  GRAPH_WORDS: array[0..1] of string = ('digraph', 'graph');
  REPORT_EXTS: array[0..5] of string = ('', '.txt', '.md', '.pas', '.log', '.text');
  NAME_REPORT = 'report';
  NAME_FORMS = 'forms-csv';
  NAME_GRAPH = 'chart-graph';
  NAME_UNKNOWN = 'unknown';

function FirstWordIsGraph(const pText: string): Boolean;
begin
  var Start:= 1;
  if (pText <> '') and (pText[1] = BOM) then Start:= 2;
  while (Start <= Length(pText)) and CharInSet(pText[Start], [#9, #10, #13, ' ']) do
    Inc(Start);
  Result:= False;
  for var Word in GRAPH_WORDS do
    if SameText(Copy(pText, Start, Length(Word)), Word) and
       ((Start + Length(Word) > Length(pText)) or CharInSet(pText[Start + Length(Word)], [#9, #10, #13, ' ', '{'])) then
    begin
      // a DOT opens its body with '{' on that same line; prose that starts with 'Graph of ...' does not
      var LineEnd:= Start;
      while (LineEnd <= Length(pText)) and (pText[LineEnd] <> #10) and (pText[LineEnd] <> #13) do
        Inc(LineEnd);
      if Pos('{', Copy(pText, Start, LineEnd - Start)) > 0 then Exit(True);
    end;
end;

function DetectByPath(const pPath: string): TChartsFormat;
begin
  if TDirectory.Exists(pPath) then
  begin
    if TFile.Exists(TPath.Combine(pPath, BUNDLE_DOT)) then Exit(cfGraph);
    Exit(cfUnknown);
  end;
  var Ext:= ExtractFileExt(pPath);
  if SameText(Ext, EXT_DOT) then Exit(cfGraph);
  if SameText(Ext, EXT_CSV) then Exit(cfFormsCsv);
  for var Known in REPORT_EXTS do
    if SameText(Ext, Known) then Exit(cfReportText);
  Result:= cfUnknown;
end;

function DetectFormat(const pPathOrText: string; pIsPath: Boolean): TChartsFormat;
begin
  if pIsPath then Exit(DetectByPath(pPathOrText));
  if IsFormsCsv(pPathOrText) then Exit(cfFormsCsv);
  if FirstWordIsGraph(pPathOrText) then Exit(cfGraph);
  Result:= cfReportText;
end;

function ItemsFor(pFormat: TChartsFormat; const pText: string): TArray<TDiffItem>;
begin
  case pFormat of
    cfReportText: Result:= ReportItems(pText);
    cfFormsCsv  : Result:= FormsCsvItems(pText);
    cfGraph     : Result:= GraphItems(ParseDot(pText));
  else
    Result:= nil;
  end;
end;

function FormatName(pFormat: TChartsFormat): string;
begin
  case pFormat of
    cfReportText: Result:= NAME_REPORT;
    cfFormsCsv  : Result:= NAME_FORMS;
    cfGraph     : Result:= NAME_GRAPH;
  else
    Result:= NAME_UNKNOWN;
  end;
end;

end.
