unit DRagLint.Charts.Render;

{ The renderers of `drag-lint compare` (spec O1-O3, D7, F4): one TCompareResult becomes
  the text the terminal prints (O1), the JSON the IDE reads (O2, schema 'compare/1'), or a
  self-contained light/dark HTML page (O3) that also marks the added and removed nodes and
  edges of a chart (D7); RenderReportHtml makes the same page of ONE report, snapshot or
  fresh run (F4).

  Every renderer is pure string work on a result that is already complete: nothing here
  runs a producer or writes a file. The one side effect is OpenInBrowser.

  PS trap handled: PowerShell reads a JSON property that is missing as $null, so
  RenderCompareJson writes EVERY key on every result ('' / [] / 0 / false, never omitted).
  The chart marking compares identities ORDINALLY (PowerShell -eq would not tell
  'TFoo.Bar' from 'tfoo.bar'), exactly as DRagLint.Charts.Adapter.Graph keys them.

  The pages are Delphi strings and declare <meta charset="utf-8">: write them as UTF-8. }

interface

uses
  DRagLint.Charts.Adapters, DRagLint.Charts.Compare; // dl:unit DRagLint.Charts.Compare accepted -- the COMPARE_EXIT_* codes travel with the TCompareResult they classify

/// <summary>The terminal text of a compare (spec O1).</summary>
/// <param name="pR">The result of RunCompare.</param>
/// <returns>'WARNING: ' lines first; then (exit 0/1) the OLD and NEW header lines, the
/// '--- before / +++ after / = K unchanged, - D removed, + I added' counts and the delta in
/// unified form ('@@ -a,b +c,d @@', then '= ' unchanged, '- ' removed, '+ ' added rows;
/// for a chart the four lists 'nodes removed (n): ...'), then 'result: ... (exit N)'.
/// Exit 2 and 3 return the warnings and 'ERROR: ' plus the message, no diff. CRLF line
/// ends, a final CRLF.</returns>
/// <remarks>Nothing is printed to a stream; the CLI sends this to stdout and the ERROR
/// line to stderr. Pure; thread-safe.</remarks>
function RenderCompareText(const pR: TCompareResult): string;

/// <summary>The JSON of a compare (spec O2, schema 'compare/1').</summary>
/// <param name="pR">The result of RunCompare.</param>
/// <returns>One line: {schema, exit_code, format, warnings, old{source, path, form,
/// question, target, asked_on, engine, command}, new{asked_on, engine, command,
/// indexes[{db, stale, stale_files, indexed_at}]}, counts{equal, removed, added},
/// hunks[{old_start, old_count, new_start, new_count, lines[{op, old, new}]}],
/// graph{nodes_added, nodes_removed, edges_added, edges_removed}, snapshot, updated_file,
/// message}. Every key is always present; a line carries 'old' for '=' and '-', 'new' for
/// '=' and '+'.</returns>
/// <remarks>Built with TJSONObject, written with ToJSON. The CLI prints it after stderr is
/// flushed. Pure; thread-safe.</remarks>
function RenderCompareJson(const pR: TCompareResult): string;

/// <summary>The side-by-side HTML page of a compare (spec O3, D7).</summary>
/// <param name="pR">The result of RunCompare.</param>
/// <returns>A complete page: no script, no external resource (the inlined SVG loses its
/// xmlns URLs), CSS variables --bg --fg --del --ins --eq --muted with a
/// prefers-color-scheme: dark override, warnings, both header lines, a
/// '&lt;table class="sxs"&gt;' with one row per edit and a separator row per hunk, all
/// text HTML-escaped. For a chart the NEW graph.svg is inlined with class="dl-added" on
/// every added node anchor and edge group, the OLD one sits in a collapsed
/// '&lt;details&gt;' with class="dl-removed" (faded) on every removed one, and the four
/// lists of changes follow.</returns>
/// <remarks>Only READS pR.OldSvgPath / pR.NewSvgPath: for a rerun compare OldSvgPath may be
/// a temp copy that the caller (the CLI) deletes afterwards, so it is never deleted here.
/// An SVG that cannot be read is left out of the page, not an error. Pure apart from
/// reading those two files.</remarks>
function RenderCompareHtml(const pR: TCompareResult): string;

/// <summary>One report, CSV or chart as the same page the compare view uses (spec F4).</summary>
/// <param name="pTitle">The page title and heading (escaped).</param>
/// <param name="pText">The report's text (cfReportText), the CSV (cfFormsCsv) or the DOT text
/// (cfGraph).</param>
/// <param name="pFormat">Which of the three; cfUnknown is shown as a report.</param>
/// <param name="pSvgPath">cfGraph: the chart's SVG to inline; '' or unreadable shows the
/// node and edge list only. Ignored for the other formats.</param>
/// <returns>cfReportText: a single-column '&lt;pre class="report"&gt;' of the logical lines;
/// cfFormsCsv: a '&lt;table class="csv"&gt;' (first row is the header); cfGraph: the SVG in
/// '&lt;section class="chart"&gt;' (not marked) plus the node and edge rows. Same
/// self-contained, light/dark template as RenderCompareHtml.</returns>
/// <remarks>Pure apart from reading pSvgPath.</remarks>
function RenderReportHtml(const pTitle, pText: string; pFormat: TChartsFormat; const pSvgPath: string): string;

/// <summary>Opens a file in the default browser.</summary>
/// <param name="pPath">The HTML file to open.</param>
/// <remarks>ShellExecute with the verb 'open'; returns at once, the result is not checked
/// (a missing association shows Windows' own dialog). Never called by a test.</remarks>
procedure OpenInBrowser(const pPath: string);

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, System.RegularExpressions, System.Generics.Collections,
  System.Generics.Defaults, System.Character,
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapter.Graph, // dl:unit DRagLint.Charts.Diff accepted -- DIFF_NO_INDEX is the diff core's own no-counterpart sentinel
  DRagLint.Charts.Adapter.Text;

const
  CRLF = #13#10;
  SCHEMA_ID = 'compare/1';
  KEY_SEP = #1;
  NBSP = #160;
  EDGE_ARROW = ' -> ';
  SVG_EDGE_ARROW = '->';
  TITLE_SEP = ' -- ';
  PORT_SEP = ':';
  UNKNOWN_TEXT = '(unknown)';
  NO_TIME_TEXT = ' (no time)';
  DATE_ONLY_LEN = 10;
  NONE_TEXT = '(none)';
  A_OPEN = '<a ';
  SVG_OPEN = '<svg';
  CLASS_ADDED = 'dl-added';
  CLASS_REMOVED = 'dl-removed';
  OP_EQUAL = '=';
  OP_DELETE = '-';
  OP_INSERT = '+';
  MAX_CODE_POINT = $10FFFF;
  SURROGATE_FIRST = $D800;
  SURROGATE_LAST = $DFFF;
  HEX_BASE = '$';
  ENT_KIND_AT = 2;
  ENT_HEX_FROM = 3;
  RE_ENTITY = '&(#[xX][0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);';
  RE_MARKER = '\{\{(\w+)\}\}';
  RE_XMLNS = '\s+xmlns(:\w+)?="[^"]*"';
  // SVG defusing (O3): the page runs no script, so none may arrive inside a graph.svg either
  RE_SVG_CLOSE = '</svg\s*>';
  RE_ACTIVE_ELEMENT = '<(script|foreignObject)\b[^>]*>.*?</\1\s*>';
  RE_ACTIVE_TAG = '</?(script|foreignObject)\b[^>]*>';
  RE_QUOTED_TAG = '<(?:[^>"'']|"[^"]*"|''[^'']*'')*>';
  RE_ATTR = '\s+([\w:.-]+)\s*=\s*("[^"]*"|''[^'']*''|[^\s"''>]+)';
  RE_BLANKS = '[\s\x00-\x1F]+';
  HANDLER_PREFIX = 'on';
  SCRIPT_SCHEME = 'javascript:';
  RE_TAG = '<[^>]*>';
  RE_XLINK_TITLE = 'xlink:title="([^"]*)"';
  RE_FIRST_TEXT = '<text[^>]*>(.*?)</text>';
  // 1 = node title, 2 = anchor attributes, 3 = anchor content, 4 = edge title
  RE_SVG_PARTS = '<g id="[^"]*" class="node">\s*<title>([^<]*)</title>' +
    '|<a ([^>]*)>(.*?)</a>' +
    '|<g id="[^"]*" class="edge">\s*<title>([^<]*)</title>';
  G_NODE_TITLE = 1;
  G_ANCHOR_ATTRS = 2;
  G_ANCHOR_BODY = 3;
  G_EDGE_TITLE = 4;
  EDGE_CLASS_PLAIN = 'class="edge"';

  HTML_CHART_CSS =
    '<style>' + CRLF +
    '.dl-added text{font-weight:bold} .dl-added polygon,.dl-added path,.dl-added ellipse{stroke:#0a7d2a;stroke-width:3px}' + CRLF +
    '.dl-removed{opacity:.35}' + CRLF +
    '</style>';

  HTML_TEMPLATE =
    '<!DOCTYPE html>' + CRLF +
    '<html lang="en">' + CRLF +
    '<head>' + CRLF +
    '<meta charset="utf-8">' + CRLF +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' + CRLF +
    '<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; img-src data:">' + CRLF +
    '<title>{{TITLE}}</title>' + CRLF +
    '<style>' + CRLF +
    ':root{--bg:#ffffff;--fg:#1f2933;--del:#ffe3e3;--ins:#d8f5dc;--eq:#f5f7fa;--muted:#6b7280}' + CRLF +
    '@media (prefers-color-scheme: dark){:root{--bg:#14181c;--fg:#e6e9ec;--del:#4a1f24;--ins:#1c4023;--eq:#1b2026;--muted:#9aa5b1}}' + CRLF +
    'body{background:var(--bg);color:var(--fg);font-family:"Segoe UI",sans-serif;margin:16px;line-height:1.4}' + CRLF +
    'h1{font-size:1.3em;margin:0 0 .6em} h2{font-size:1.05em;margin:1em 0 .3em} h3{font-size:.95em;margin:.8em 0 .2em}' + CRLF +
    '.muted{color:var(--muted)} .meta p{margin:.15em 0;font-family:Consolas,monospace;font-size:.9em}' + CRLF +
    '.warnings{background:var(--del);padding:.5em 1.5em;border-radius:4px} .error{background:var(--del);padding:.5em 1em;border-radius:4px}' + CRLF +
    '.result{font-weight:bold}' + CRLF +
    'table{border-collapse:collapse;width:100%} td,th{vertical-align:top;padding:1px 6px;font-family:Consolas,monospace;font-size:.9em;white-space:pre-wrap;word-break:break-word}' + CRLF +
    'th{text-align:left;color:var(--muted);border-bottom:1px solid var(--muted)}' + CRLF +
    'td.ln{color:var(--muted);text-align:right;width:3em;white-space:nowrap}' + CRLF +
    'td.eq{background:var(--eq)} td.del{background:var(--del)} td.ins{background:var(--ins)}' + CRLF +
    'table.sxs td.old,table.sxs td.new{width:48%}' + CRLF +
    'tr.hunk td{color:var(--muted);border-top:1px solid var(--muted);padding-top:4px}' + CRLF +
    'pre.report{font-family:Consolas,monospace;font-size:.9em;white-space:pre-wrap;word-break:break-word;margin:0}' + CRLF +
    '.chartbox{background:#ffffff;overflow:auto;border:1px solid var(--muted);border-radius:4px} .chartbox svg{max-width:100%;height:auto}' + CRLF +
    'details{margin:.8em 0} summary{cursor:pointer;color:var(--muted)}' + CRLF +
    '</style>' + CRLF +
    '{{HEAD}}' + CRLF +
    '</head>' + CRLF +
    '<body>' + CRLF +
    '{{WARNINGS}}' + CRLF +
    '{{BODY}}' + CRLF +
    '</body>' + CRLF +
    '</html>' + CRLF;

type
  TEndIdFunc = reference to function(const pToken: string): string;

  { Nodes and edges that differ between the old and the new chart, in the order the model
    lists them. Empty for a result that is not a chart. }
  TGraphDelta = record
    NodesAdded  : TArray<string>;
    NodesRemoved: TArray<string>;
    EdgesAdded  : TArray<TGraphEdge>;
    EdgesRemoved: TArray<TGraphEdge>;
  end;

{ ---------- shared helpers ---------- }

function HtmlEscape(const pText: string): string;
begin
  Result:= pText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function EntityText(const pMatch: TMatch): string;
begin
  var Name:= pMatch.Groups[1].Value;
  if Name = 'amp' then Exit('&');
  if Name = 'lt' then Exit('<');
  if Name = 'gt' then Exit('>');
  if Name = 'quot' then Exit('"');
  if Name = 'apos' then Exit('''');
  var Code: Integer;
  if CharInSet(Name[ENT_KIND_AT], ['x', 'X']) then Code:= StrToIntDef(HEX_BASE + Copy(Name, ENT_HEX_FROM, MaxInt), -1)
  else Code:= StrToIntDef(Copy(Name, ENT_KIND_AT, MaxInt), -1);
  // a lone surrogate is not a character, and ConvertFromUtf32 raises on one: keep it as written
  if (Code > 0) and (Code <= MAX_CODE_POINT) and ((Code < SURROGATE_FIRST) or (Code > SURROGATE_LAST)) then
    Result:= Char.ConvertFromUtf32(Code)
  else Result:= pMatch.Value;
end;

{ TRegEx.Replace takes a method pointer, not an anonymous method: this is the same loop with a closure. }
function ReplaceMatches(const pText, pPattern: string; pOptions: TRegExOptions; const pFn: TFunc<TMatch, string>): string;
begin
  var SB:= TStringBuilder.Create;
  try
    var Last:= 1;
    for var M in TRegEx.Matches(pText, pPattern, pOptions) do
    begin
      SB.Append(Copy(pText, Last, M.Index - Last)).Append(pFn(M));
      Last:= M.Index + M.Length;
    end;
    SB.Append(Copy(pText, Last, MaxInt));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Decodes the XML entities of an SVG title (graphviz writes '-' as &#45;). }
function DecodeXml(const pText: string): string;
begin
  Result:= ReplaceMatches(pText, RE_ENTITY, [],
    function(pM: TMatch): string
    begin
      Result:= EntityText(pM);
    end);
end;

function EdgeKeyOf(const pFrom, pTo: string): string;
begin
  Result:= pFrom + KEY_SEP + pTo;
end;

function EdgeText(const pEdge: TGraphEdge): string;
begin
  Result:= pEdge.FromId + EDGE_ARROW + pEdge.ToId;
end;

function EdgeTexts(const pEdges: TArray<TGraphEdge>): TArray<string>;
begin
  SetLength(Result, Length(pEdges));
  for var I:= 0 to High(pEdges) do
    Result[I]:= EdgeText(pEdges[I]);
end;

function ComputeDelta(const pR: TCompareResult): TGraphDelta;
begin
  Result:= Default(TGraphDelta);
  if pR.Format <> cfGraph then
    Exit;
  var OldNodes:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var NewNodes:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var OldEdges:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var NewEdges:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  try
    for var N in pR.OldGraph.Nodes do OldNodes.AddOrSetValue(N.Id, True);
    for var N in pR.NewGraph.Nodes do NewNodes.AddOrSetValue(N.Id, True);
    for var E in pR.OldGraph.Edges do OldEdges.AddOrSetValue(EdgeKeyOf(E.FromId, E.ToId), True);
    for var E in pR.NewGraph.Edges do NewEdges.AddOrSetValue(EdgeKeyOf(E.FromId, E.ToId), True);
    for var N in pR.NewGraph.Nodes do
      if not OldNodes.ContainsKey(N.Id) then Result.NodesAdded:= Result.NodesAdded + [N.Id];
    for var N in pR.OldGraph.Nodes do
      if not NewNodes.ContainsKey(N.Id) then Result.NodesRemoved:= Result.NodesRemoved + [N.Id];
    for var E in pR.NewGraph.Edges do
      if not OldEdges.ContainsKey(EdgeKeyOf(E.FromId, E.ToId)) then Result.EdgesAdded:= Result.EdgesAdded + [E];
    for var E in pR.OldGraph.Edges do
      if not NewEdges.ContainsKey(EdgeKeyOf(E.FromId, E.ToId)) then Result.EdgesRemoved:= Result.EdgesRemoved + [E];
  finally
    NewEdges.Free;
    OldEdges.Free;
    NewNodes.Free;
    OldNodes.Free;
  end;
end;

function AskedText(const pAskedOn: string): string;
begin
  if pAskedOn = '' then Exit(UNKNOWN_TEXT);
  Result:= if Length(pAskedOn) <= DATE_ONLY_LEN then pAskedOn + NO_TIME_TEXT else pAskedOn;
end;

function OrUnknown(const pText: string): string;
begin
  Result:= if pText = '' then UNKNOWN_TEXT else pText;
end;

function LabelOf(const pHeader: TReportHeader; pFormat: TChartsFormat): string;
begin
  if pHeader.QuestionId = '' then Exit(FormatName(pFormat));
  Result:= if pHeader.Target = '' then pHeader.QuestionId else pHeader.QuestionId + ' ' + pHeader.Target;
end;

function SourceKind(pSource: TCompareSource): string;
begin
  case pSource of
    csRemarks     : Result:= 'remarks';
    csAutoSnapshot: Result:= 'auto';
    csOldIndex    : Result:= 'old-index';
  else
    Result:= 'file';
  end;
end;

function OldSourceText(const pR: TCompareResult): string;
begin
  case pR.OldSource of
    csRemarks     : Result:= Format('remarks block at %s:%d', [pR.OldPath, pR.OldLine]);
    csAutoSnapshot: Result:= 'auto snapshot ' + pR.OldPath;
    csOldIndex    : Result:= 'old index ' + pR.OldPath;
  else
    Result:= pR.OldPath;
  end;
end;

function IndexText(const pFact: TIndexFact): string;
begin
  var State:= if pFact.Stale then Format('stale: %d files changed', [pFact.StaleFiles]) else 'fresh';
  Result:= Format('index %s indexed %s (%s)', [ExtractFileName(pFact.Db), OrUnknown(pFact.IndexedAt), State]);
end;

{ OLD header facts, as the text and the HTML page both print them (after 'OLD  '). }
function OldFacts(const pR: TCompareResult): string;
begin
  Result := Format('%s  asked %s  engine %s  source %s', [LabelOf(pR.OldHeader, pR.Format),
    AskedText(pR.OldHeader.AskedOn), OrUnknown(pR.OldHeader.EngineVersion), OldSourceText(pR)]);
end;

{ NEW header facts and one index clause per index the new run read (after 'NEW  '). }
function NewFacts(const pR: TCompareResult): string;
begin
  Result := Format('%s  asked %s  engine %s', [LabelOf(pR.NewHeader, pR.Format),
    AskedText(pR.NewHeader.AskedOn), OrUnknown(pR.NewHeader.EngineVersion)]);
  for var Fact in pR.NewIndexes do
    Result:= Result + '  ' + IndexText(Fact);
end;

{ Whether the result holds a diff to show: always for exit 0 and 1, and for an exit 2 that
  came after the diff was made (update-doc failed). }
function HasBody(const pR: TCompareResult): Boolean;
begin
  Result:= (pR.ExitCode < COMPARE_EXIT_SETUP) or (Length(pR.Edits) > 0);
end;

function ResultText(const pR: TCompareResult): string;
begin
  case pR.ExitCode of
    COMPARE_EXIT_SAME     : Result:= 'no differences';
    COMPARE_EXIT_DIFFERENT: Result:= 'differences found';
  else
    Result:= 'failed';
  end;
  Result:= Format('%s (exit %d)', [Result, pR.ExitCode]);
end;

function HunkHeader(const pHunk: TDiffHunk): string;
begin
  Result:= Format('@@ -%d,%d +%d,%d @@', [pHunk.OldStart, pHunk.OldCount, pHunk.NewStart, pHunk.NewCount]);
end;

function UnitWord(pFormat: TChartsFormat): string;
begin
  Result:= if pFormat = cfGraph then 'items' else 'lines';
end;

{ ---------- text (O1) ---------- }

{ Continuation lines of a wrapped item are indented under its marker. }
function IndentContinuation(const pText: string): string;
begin
  Result:= pText.Replace(CRLF, CRLF + '  ');
end;

procedure AddHunkLines(const pLines: TList<string>; const pR: TCompareResult);
begin
  for var Hunk in pR.Hunks do
  begin
    pLines.Add(HunkHeader(Hunk));
    for var Edit in Hunk.Edits do
      case Edit.Op of
        doEqual : pLines.Add(OP_EQUAL + ' ' + IndentContinuation(pR.OldItems[Edit.OldIndex].Text));
        doDelete: pLines.Add(OP_DELETE + ' ' + IndentContinuation(pR.OldItems[Edit.OldIndex].Text));
        doInsert: pLines.Add(OP_INSERT + ' ' + IndentContinuation(pR.NewItems[Edit.NewIndex].Text));
      end;
  end;
end;

function ListLine(const pCaption: string; const pItems: TArray<string>; const pSep: string): string;
begin
  Result:= Format('%s (%d): %s', [pCaption, Length(pItems), if Length(pItems) = 0 then NONE_TEXT else string.Join(pSep, pItems)]);
end;

procedure AddDeltaLines(const pLines: TList<string>; const pDelta: TGraphDelta);
begin
  pLines.Add(ListLine('nodes removed', pDelta.NodesRemoved, ', '));
  pLines.Add(ListLine('nodes added', pDelta.NodesAdded, ', '));
  pLines.Add(ListLine('edges removed', EdgeTexts(pDelta.EdgesRemoved), '; '));
  pLines.Add(ListLine('edges added', EdgeTexts(pDelta.EdgesAdded), '; '));
end;

procedure AddBodyLines(const pLines: TList<string>; const pR: TCompareResult);
begin
  pLines.Add('OLD  ' + OldFacts(pR));
  pLines.Add('NEW  ' + NewFacts(pR));
  var Eq, Del, Ins: Integer;
  CountEdits(pR.Edits, Eq, Del, Ins);
  pLines.Add(Format('--- before (%d %s)', [Length(pR.OldItems), UnitWord(pR.Format)]));
  pLines.Add(Format('+++ after (%d %s)', [Length(pR.NewItems), UnitWord(pR.Format)]));
  pLines.Add(Format('= %d unchanged, - %d removed, + %d added', [Eq, Del, Ins]));
  if pR.Format = cfGraph then AddDeltaLines(pLines, ComputeDelta(pR))
  else AddHunkLines(pLines, pR);
  if pR.SnapshotPath <> '' then pLines.Add('snapshot: ' + pR.SnapshotPath);
  if pR.UpdatedFile <> '' then pLines.Add('updated: ' + pR.UpdatedFile);
  pLines.Add('result: ' + ResultText(pR));
end;

function RenderCompareText(const pR: TCompareResult): string;
begin
  var Lines:= TList<string>.Create;
  try
    for var W in pR.Warnings do
      Lines.Add('WARNING: ' + W);
    if pR.ExitCode >= COMPARE_EXIT_SETUP then
      Lines.Add('ERROR: ' + pR.Message);
    if HasBody(pR) then
      AddBodyLines(Lines, pR);
    Result:= string.Join(CRLF, Lines.ToArray) + CRLF;
  finally
    Lines.Free;
  end;
end;

{ ---------- JSON (O2) ---------- }

function FormName(pForm: TReportForm): string;
begin
  case pForm of
    rfPlain     : Result:= 'plain';
    rfDocInsight: Result:= 'docinsight';
  else
    Result:= '';
  end;
end;

function CommandText(const pCommand: TReportCommand): string;
begin
  Result:= if pCommand.IsEmpty then '' else BuildCommandLine(pCommand);
end;

function StringArray(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var Item in pItems do
    Result.Add(Item);
end;

function OldObject(const pR: TCompareResult): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('source', SourceKind(pR.OldSource));
  Result.AddPair('path', pR.OldPath);
  Result.AddPair('form', FormName(pR.OldHeader.Form));
  Result.AddPair('question', pR.OldHeader.QuestionId);
  Result.AddPair('target', pR.OldHeader.Target);
  Result.AddPair('asked_on', pR.OldHeader.AskedOn);
  Result.AddPair('engine', pR.OldHeader.EngineVersion);
  Result.AddPair('command', CommandText(pR.OldHeader.Command));
end;

function NewObject(const pR: TCompareResult): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('asked_on', pR.NewHeader.AskedOn);
  Result.AddPair('engine', pR.NewHeader.EngineVersion);
  Result.AddPair('command', CommandText(pR.NewHeader.Command));
  var Indexes:= TJSONArray.Create;
  Result.AddPair('indexes', Indexes);
  for var Fact in pR.NewIndexes do
  begin
    var O:= TJSONObject.Create;
    O.AddPair('db', Fact.Db);
    O.AddPair('stale', TJSONBool.Create(Fact.Stale));
    O.AddPair('stale_files', TJSONNumber.Create(Fact.StaleFiles));
    O.AddPair('indexed_at', Fact.IndexedAt);
    Indexes.AddElement(O);
  end;
end;

function CountsObject(const pR: TCompareResult): TJSONObject;
begin
  var Eq, Del, Ins: Integer;
  CountEdits(pR.Edits, Eq, Del, Ins);
  Result:= TJSONObject.Create;
  Result.AddPair('equal', TJSONNumber.Create(Eq));
  Result.AddPair('removed', TJSONNumber.Create(Del));
  Result.AddPair('added', TJSONNumber.Create(Ins));
end;

function LineObject(const pR: TCompareResult; const pEdit: TDiffEdit): TJSONObject;
begin
  Result:= TJSONObject.Create;
  case pEdit.Op of
    doEqual:
      begin
        Result.AddPair('op', OP_EQUAL);
        Result.AddPair('old', pR.OldItems[pEdit.OldIndex].Text);
        Result.AddPair('new', pR.NewItems[pEdit.NewIndex].Text);
      end;
    doDelete:
      begin
        Result.AddPair('op', OP_DELETE);
        Result.AddPair('old', pR.OldItems[pEdit.OldIndex].Text);
      end;
    doInsert:
      begin
        Result.AddPair('op', OP_INSERT);
        Result.AddPair('new', pR.NewItems[pEdit.NewIndex].Text);
      end;
  end;
end;

function HunksArray(const pR: TCompareResult): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var Hunk in pR.Hunks do
  begin
    var H:= TJSONObject.Create;
    H.AddPair('old_start', TJSONNumber.Create(Hunk.OldStart));
    H.AddPair('old_count', TJSONNumber.Create(Hunk.OldCount));
    H.AddPair('new_start', TJSONNumber.Create(Hunk.NewStart));
    H.AddPair('new_count', TJSONNumber.Create(Hunk.NewCount));
    var Lines:= TJSONArray.Create;
    H.AddPair('lines', Lines);
    for var Edit in Hunk.Edits do
      Lines.AddElement(LineObject(pR, Edit));
    Result.AddElement(H);
  end;
end;

function GraphObject(const pR: TCompareResult): TJSONObject;
begin
  var Delta:= ComputeDelta(pR);
  Result:= TJSONObject.Create;
  Result.AddPair('nodes_added', StringArray(Delta.NodesAdded));
  Result.AddPair('nodes_removed', StringArray(Delta.NodesRemoved));
  Result.AddPair('edges_added', StringArray(EdgeTexts(Delta.EdgesAdded)));
  Result.AddPair('edges_removed', StringArray(EdgeTexts(Delta.EdgesRemoved)));
end;

function RenderCompareJson(const pR: TCompareResult): string;
begin
  var Root:= TJSONObject.Create;
  try
    Root.AddPair('schema', SCHEMA_ID);
    Root.AddPair('exit_code', TJSONNumber.Create(pR.ExitCode));
    Root.AddPair('format', FormatName(pR.Format));
    Root.AddPair('warnings', StringArray(pR.Warnings));
    Root.AddPair('old', OldObject(pR));
    Root.AddPair('new', NewObject(pR));
    Root.AddPair('counts', CountsObject(pR));
    Root.AddPair('hunks', HunksArray(pR));
    Root.AddPair('graph', GraphObject(pR));
    Root.AddPair('snapshot', pR.SnapshotPath);
    Root.AddPair('updated_file', pR.UpdatedFile);
    Root.AddPair('message', pR.Message);
    Result:= Root.ToJSON;
  finally
    Root.Free;
  end;
end;

{ ---------- SVG (D7) ---------- }

{ Whether one attribute of an SVG tag could run script: an on* event handler, or a value that
  is a javascript: URL once entities, blanks and control characters are taken out. }
function IsActiveAttr(const pName, pValue: string): Boolean;
begin
  if LowerCase(pName).StartsWith(HANDLER_PREFIX) then Exit(True);
  var Plain:= LowerCase(TRegEx.Replace(DecodeXml(pValue), RE_BLANKS, ''));
  Result:= Pos(SCRIPT_SCHEME, Plain) > 0;
end;

{ The SVG with nothing that could run: cut after the LAST '</svg>' (whatever follows is not the
  chart), script and foreignObject elements removed, and every on* handler and javascript: URL
  attribute removed from every tag. A graphviz SVG carries none of these, so it is unchanged. }
function DefuseSvg(const pSvg: string): string;
begin
  Result:= pSvg;
  var CloseAt:= 0;
  var CloseLen:= 0;
  for var M in TRegEx.Matches(Result, RE_SVG_CLOSE, [roIgnoreCase]) do
  begin
    CloseAt:= M.Index;
    CloseLen:= M.Length;
  end;
  if CloseAt > 0 then
    Result:= Copy(Result, 1, CloseAt + CloseLen - 1);
  Result:= TRegEx.Replace(Result, RE_ACTIVE_ELEMENT, '', [roIgnoreCase, roSingleLine]);
  Result:= TRegEx.Replace(Result, RE_ACTIVE_TAG, '', [roIgnoreCase]);
  Result:= ReplaceMatches(Result, RE_QUOTED_TAG, [],
    function(pTag: TMatch): string
    begin
      Result:= ReplaceMatches(pTag.Value, RE_ATTR, [],
        function(pAttr: TMatch): string
        begin
          var Value:= pAttr.Groups[2].Value;
          if CharInSet(Value[1], ['"', '''']) then Value:= Copy(Value, 2, Length(Value) - 2);
          Result:= if IsActiveAttr(pAttr.Groups[1].Value, Value) then '' else pAttr.Value;
        end);
    end);
end;

{ The SVG as page markup: read as UTF-8, everything before '<svg' (prolog, DOCTYPE,
  generator comments) dropped, defused (DefuseSvg), and the xmlns attributes of the root
  removed -- inline SVG in HTML needs none, and the page then holds no URL at all. '' when
  there is no file. }
function SvgMarkup(const pPath: string): string;
begin
  Result:= '';
  if (pPath = '') or not TFile.Exists(pPath) then
    Exit;
  try
    var Text:= TFile.ReadAllText(pPath, TEncoding.UTF8);
    var Start:= Pos(SVG_OPEN, Text);
    if Start = 0 then Exit;
    Text:= DefuseSvg(Copy(Text, Start, MaxInt));
    var TagEnd:= Pos('>', Text);
    if TagEnd = 0 then Exit;
    Result:= TRegEx.Replace(Copy(Text, 1, TagEnd), RE_XMLNS, '') + Copy(Text, TagEnd + 1, MaxInt);
  except
    on Exception do
      Result:= '';
  end;
end;

{ The identity of a node anchor, by the rule of DRagLint.Charts.Adapter.Graph: the part of the
  title before ' -- ', else the whole title when it has no space, else the first text. }
function AnchorIdentity(const pAttrs, pBody: string): string;
begin
  var TitleMatch:= TRegEx.Match(pAttrs, RE_XLINK_TITLE);
  // graphviz turns the second space of '  --  ' into &#160;: the DOT title had plain spaces.
  var Title:= if TitleMatch.Success then DecodeXml(TitleMatch.Groups[1].Value).Replace(NBSP, ' ') else '';
  var SepAt:= Pos(TITLE_SEP, Title);
  if SepAt > 0 then Exit(Trim(Copy(Title, 1, SepAt - 1)));
  if (Title <> '') and (Pos(' ', Title) = 0) then Exit(Title);
  var First:= TRegEx.Match(pBody, RE_FIRST_TEXT, [roSingleLine]);
  Result:= if First.Success then Trim(DecodeXml(TRegEx.Replace(First.Groups[1].Value, RE_TAG, ''))) else '';
end;

{ Whether group pIndex took part in the match: a group after the last one that did is absent from
  Groups, and one before it is empty (Delphi's TRegEx does not tell the two apart by Success). }
function GroupHas(const pMatch: TMatch; pIndex: Integer): Boolean;
begin
  Result:= (pIndex < pMatch.Groups.Count) and (pMatch.Groups[pIndex].Value <> '');
end;

{ Marks nodes and edges of one chart's SVG with a CSS class. A node anchor is matched by its
  identity; an edge group by the identities of its two ends, taken from the chart's port map
  ('nw:p3') or, for an end without a port, from the first anchor of that node's own group. }
function MarkSvg(const pSvg: string; const pModel: TGraphModel; const pNodeIds: TArray<string>;
  const pEdges: TArray<TGraphEdge>; const pClass: string): string;
begin
  Result:= pSvg;
  if (pSvg = '') or ((Length(pNodeIds) = 0) and (Length(pEdges) = 0)) then
    Exit;
  var NodeSet:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var EdgeSet:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var Ports:= TDictionary<string, string>.Create(TStringComparer.Ordinal);
  var Defaults:= TDictionary<string, string>.Create(TStringComparer.Ordinal);
  try
    for var Id in pNodeIds do NodeSet.AddOrSetValue(Id, True);
    for var E in pEdges do EdgeSet.AddOrSetValue(EdgeKeyOf(E.FromId, E.ToId), True);
    for var P in pModel.PortToId do Ports.AddOrSetValue(P.Key, P.Value);
    var CurNid:= '';
    for var M in TRegEx.Matches(pSvg, RE_SVG_PARTS, [roSingleLine]) do
      if GroupHas(M, G_NODE_TITLE) then
        CurNid:= DecodeXml(M.Groups[G_NODE_TITLE].Value)
      else if GroupHas(M, G_ANCHOR_ATTRS) and (CurNid <> '') and not Defaults.ContainsKey(CurNid) then
        Defaults.Add(CurNid, AnchorIdentity(M.Groups[G_ANCHOR_ATTRS].Value, M.Groups[G_ANCHOR_BODY].Value));
    var EndId: TEndIdFunc;
    EndId:=
      function(const pToken: string): string
      begin
        if Ports.TryGetValue(pToken, Result) then Exit;
        var PortAt:= Pos(PORT_SEP, pToken);
        var Nid:= if PortAt > 0 then Copy(pToken, 1, PortAt - 1) else pToken;
        if not Defaults.TryGetValue(Nid, Result) then Result:= pToken;
      end;
    Result:= ReplaceMatches(pSvg, RE_SVG_PARTS, [roSingleLine],
      function(pM: TMatch): string
      begin
        Result:= pM.Value;
        if GroupHas(pM, G_NODE_TITLE) then
          Exit;
        if GroupHas(pM, G_ANCHOR_ATTRS) then
        begin
          if NodeSet.ContainsKey(AnchorIdentity(pM.Groups[G_ANCHOR_ATTRS].Value, pM.Groups[G_ANCHOR_BODY].Value)) then
            Result:= A_OPEN + 'class="' + pClass + '" ' + Copy(pM.Value, Length(A_OPEN) + 1, MaxInt);
          Exit;
        end;
        var Title:= DecodeXml(pM.Groups[G_EDGE_TITLE].Value);
        var ArrowAt:= Pos(SVG_EDGE_ARROW, Title);
        if (ArrowAt > 0) and EdgeSet.ContainsKey(EdgeKeyOf(EndId(Copy(Title, 1, ArrowAt - 1)),
          EndId(Copy(Title, ArrowAt + Length(SVG_EDGE_ARROW), MaxInt)))) then
          Result:= pM.Value.Replace(EDGE_CLASS_PLAIN, 'class="edge ' + pClass + '"');
      end);
  finally
    Defaults.Free;
    Ports.Free;
    EdgeSet.Free;
    NodeSet.Free;
  end;
end;

{ ---------- HTML (O3, F4) ---------- }

function FillTemplate(const pTitle, pHead, pWarnings, pBody: string): string;
begin
  // One pass over the TEMPLATE only: a value that holds '{{BODY}}' is never substituted again.
  Result:= ReplaceMatches(HTML_TEMPLATE, RE_MARKER, [],
    function(pM: TMatch): string
    begin
      var Name:= pM.Groups[1].Value;
      if Name = 'TITLE' then Result:= HtmlEscape(pTitle)
      else if Name = 'HEAD' then Result:= pHead
      else if Name = 'WARNINGS' then Result:= pWarnings
      else if Name = 'BODY' then Result:= pBody
      else Result:= pM.Value;
    end);
end;

function WarningsHtml(const pWarnings: TArray<string>): string;
begin
  Result:= '';
  if Length(pWarnings) = 0 then Exit;
  Result:= '<ul class="warnings">' + CRLF;
  for var W in pWarnings do
    Result:= Result + '<li>' + HtmlEscape(W) + '</li>' + CRLF;
  Result:= Result + '</ul>';
end;

function LineNo(pIndex: Integer): string;
begin
  Result:= if pIndex = DIFF_NO_INDEX then '' else IntToStr(pIndex + 1);
end;

function EditRowHtml(const pR: TCompareResult; const pEdit: TDiffEdit): string;
begin
  var OldText:= '';
  var NewText:= '';
  var OldClass:= 'old';
  var NewClass:= 'new';
  if pEdit.OldIndex <> DIFF_NO_INDEX then OldText:= HtmlEscape(pR.OldItems[pEdit.OldIndex].Text);
  if pEdit.NewIndex <> DIFF_NO_INDEX then NewText:= HtmlEscape(pR.NewItems[pEdit.NewIndex].Text);
  case pEdit.Op of
    doEqual:
      begin
        OldClass:= 'old eq';
        NewClass:= 'new eq';
      end;
    doDelete: OldClass:= 'old del';
    doInsert: NewClass:= 'new ins';
  end;
  Result:= Format('<tr><td class="ln">%s</td><td class="%s">%s</td><td class="ln">%s</td><td class="%s">%s</td></tr>',
    [LineNo(pEdit.OldIndex), OldClass, OldText, LineNo(pEdit.NewIndex), NewClass, NewText]);
end;

function SideBySideHtml(const pR: TCompareResult): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append('<table class="sxs">').Append(CRLF);
    SB.Append('<thead><tr><th class="ln">#</th><th>Before</th><th class="ln">#</th><th>After</th></tr></thead>').Append(CRLF);
    SB.Append('<tbody>').Append(CRLF);
    for var Hunk in pR.Hunks do
    begin
      SB.Append('<tr class="hunk"><td colspan="4">').Append(HtmlEscape(HunkHeader(Hunk))).Append('</td></tr>').Append(CRLF);
      for var Edit in Hunk.Edits do
        SB.Append(EditRowHtml(pR, Edit)).Append(CRLF);
    end;
    SB.Append('</tbody>').Append(CRLF).Append('</table>');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function HtmlList(const pCaption: string; const pItems: TArray<string>): string;
begin
  Result:= Format('<h3>%s (%d)</h3>', [HtmlEscape(pCaption), Length(pItems)]) + CRLF;
  if Length(pItems) = 0 then
    Exit(Result + '<p class="muted">' + NONE_TEXT + '</p>' + CRLF);
  Result:= Result + '<ul>' + CRLF;
  for var Item in pItems do
    Result:= Result + '<li>' + HtmlEscape(Item) + '</li>' + CRLF;
  Result:= Result + '</ul>' + CRLF;
end;

function DeltaHtml(const pDelta: TGraphDelta): string;
begin
  Result:= '<section class="delta">' + CRLF + '<h2>Changes</h2>' + CRLF +
    HtmlList('Nodes removed', pDelta.NodesRemoved) +
    HtmlList('Nodes added', pDelta.NodesAdded) +
    HtmlList('Edges removed', EdgeTexts(pDelta.EdgesRemoved)) +
    HtmlList('Edges added', EdgeTexts(pDelta.EdgesAdded)) +
    '</section>';
end;

function ChartHtml(const pHeading, pSvg: string): string;
begin
  Result:= '<section class="chart">' + CRLF + '<h2>' + HtmlEscape(pHeading) + '</h2>' + CRLF +
    '<div class="chartbox">' + pSvg + '</div>' + CRLF + '</section>';
end;

function OldChartHtml(const pSvg: string): string;
begin
  Result:= '<details><summary>Before (removed shown faded)</summary>' + CRLF +
    '<div class="chartbox">' + pSvg + '</div>' + CRLF + '</details>';
end;

function CompareChartsHtml(const pR: TCompareResult; const pDelta: TGraphDelta): string;
begin
  Result:= '';
  var NewSvg:= SvgMarkup(pR.NewSvgPath);
  if NewSvg <> '' then
    Result:= Result + ChartHtml('After (added marked)',
      MarkSvg(NewSvg, pR.NewGraph, pDelta.NodesAdded, pDelta.EdgesAdded, CLASS_ADDED)) + CRLF;
  var OldSvg:= SvgMarkup(pR.OldSvgPath);
  if OldSvg <> '' then
    Result:= Result + OldChartHtml(MarkSvg(OldSvg, pR.OldGraph, pDelta.NodesRemoved, pDelta.EdgesRemoved, CLASS_REMOVED)) + CRLF;
end;

function CompareBodyHtml(const pR: TCompareResult): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append('<h1>').Append(HtmlEscape('Compare ' + LabelOf(pR.OldHeader, pR.Format))).Append('</h1>').Append(CRLF);
    if pR.ExitCode >= COMPARE_EXIT_SETUP then
      SB.Append('<p class="error">ERROR: ').Append(HtmlEscape(pR.Message)).Append('</p>').Append(CRLF);
    if HasBody(pR) then
    begin
      SB.Append('<section class="meta">').Append(CRLF);
      SB.Append('<p><b>OLD</b>  ').Append(HtmlEscape(OldFacts(pR))).Append('</p>').Append(CRLF);
      SB.Append('<p><b>NEW</b>  ').Append(HtmlEscape(NewFacts(pR))).Append('</p>').Append(CRLF);
      SB.Append('</section>').Append(CRLF);
      SB.Append('<p class="result">').Append(HtmlEscape(ResultText(pR))).Append('</p>').Append(CRLF);
      if pR.Format = cfGraph then
      begin
        var Delta:= ComputeDelta(pR);
        SB.Append(CompareChartsHtml(pR, Delta));
        SB.Append(DeltaHtml(Delta)).Append(CRLF);
      end;
      if Length(pR.Hunks) > 0 then SB.Append(SideBySideHtml(pR)).Append(CRLF)
      else SB.Append('<p class="muted">No differences.</p>').Append(CRLF);
      if pR.SnapshotPath <> '' then
        SB.Append('<p class="muted">Snapshot: ').Append(HtmlEscape(pR.SnapshotPath)).Append('</p>').Append(CRLF);
      if pR.UpdatedFile <> '' then
        SB.Append('<p class="muted">Updated: ').Append(HtmlEscape(pR.UpdatedFile)).Append('</p>').Append(CRLF);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderCompareHtml(const pR: TCompareResult): string;
begin
  Result:= FillTemplate('Compare ' + LabelOf(pR.OldHeader, pR.Format), if pR.Format = cfGraph then HTML_CHART_CSS else '',
    WarningsHtml(pR.Warnings), CompareBodyHtml(pR));
end;

{ A CSV text as rows of cells: a quote toggles quoted mode, a doubled quote inside quotes is one
  quote, commas and line ends split only outside quotes. Empty rows are dropped. }
function CsvRows(const pText: string): TArray<TArray<string>>;
begin
  var Rows:= TList<TArray<string>>.Create;
  var Cells:= TList<string>.Create;
  var Cell:= TStringBuilder.Create;
  try
    var Quoted:= False;
    var EndRow: TProc;
    EndRow:=
      procedure
      begin
        Cells.Add(Cell.ToString);
        Cell.Clear;
        if (Cells.Count > 1) or (Cells[0] <> '') then
          Rows.Add(Cells.ToArray);
        Cells.Clear;
      end;
    var I:= 1;
    while I <= Length(pText) do
    begin
      var C:= pText[I];
      if Quoted then
      begin
        if (C = '"') and (I < Length(pText)) and (pText[I + 1] = '"') then
        begin
          Cell.Append('"');
          Inc(I);
        end
        else if C = '"' then Quoted:= False
        else Cell.Append(C);
      end
      else if C = '"' then Quoted:= True
      else if C = ',' then
      begin
        Cells.Add(Cell.ToString);
        Cell.Clear;
      end
      else if C = #13 then
      begin
        if (I < Length(pText)) and (pText[I + 1] = #10) then Inc(I);
        EndRow();
      end
      else if C = #10 then EndRow()
      else Cell.Append(C);
      Inc(I);
    end;
    if (Cell.Length > 0) or (Cells.Count > 0) then EndRow();
    Result:= Rows.ToArray;
  finally
    Cell.Free;
    Cells.Free;
    Rows.Free;
  end;
end;

function CsvTableHtml(const pText: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append('<table class="csv">').Append(CRLF);
    var Rows:= CsvRows(pText);
    for var R:= 0 to High(Rows) do
    begin
      var Tag:= if R = 0 then 'th' else 'td';
      SB.Append('<tr>');
      for var Cell in Rows[R] do
        SB.Append('<').Append(Tag).Append('>').Append(HtmlEscape(Cell)).Append('</').Append(Tag).Append('>');
      SB.Append('</tr>').Append(CRLF);
    end;
    SB.Append('</table>');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ReportPreHtml(const pText: string): string;
begin
  var Form: TReportForm;
  Result:= '<pre class="report">' + HtmlEscape(string.Join(#10, ReportLogicalLines(pText, Form))) + '</pre>';
end;

function GraphRowsHtml(const pDotText: string): string;
begin
  Result:= '<table class="items">' + CRLF;
  for var Item in GraphItems(ParseDot(pDotText)) do
    Result:= Result + '<tr><td>' + HtmlEscape(Item.Text) + '</td></tr>' + CRLF;
  Result:= Result + '</table>';
end;

function RenderReportHtml(const pTitle, pText: string; pFormat: TChartsFormat; const pSvgPath: string): string;
begin
  var Head:= '';
  var Body: string;
  case pFormat of
    cfFormsCsv: Body:= CsvTableHtml(pText);
    cfGraph:
      begin
        Head:= HTML_CHART_CSS;
        var Svg:= SvgMarkup(pSvgPath);
        Body:= (if Svg = '' then '' else ChartHtml('Chart', Svg) + CRLF) + GraphRowsHtml(pText);
      end;
  else
    Body:= ReportPreHtml(pText);
  end;
  Result:= FillTemplate(pTitle, Head, '', '<h1>' + HtmlEscape(pTitle) + '</h1>' + CRLF + Body);
end;

procedure OpenInBrowser(const pPath: string);
begin
  ShellExecute(0, 'open', PChar(pPath), nil, nil, SW_SHOWNORMAL);
end;

end.
