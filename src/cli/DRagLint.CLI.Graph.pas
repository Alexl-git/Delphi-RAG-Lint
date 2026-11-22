unit DRagLint.CLI.Graph;

// ---------------------------------------------------------------------------
// The graph, arch-diagram, diff and todos verbs.
// Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint graph: the unit-level dependency graph in Graphviz DOT or Mermaid, one edge per referring -> defining file, weighted by reference count.</summary>
/// <param name="AArgs">--db and --format dot|mermaid.</param>
/// <returns>0 on success; nonzero on a usage error or a missing index.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: ChangeFileExt, CharInSet, DRagLint.CLI.Graph.DoGraph.GraphJsonOrHtml, DRagLint.CLI.Graph.DoGraph.SanitizeId, DRagLint.CLI.Graph.DoGraph.UnitName, DRagLint.Core.Model.JsonEscape, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.Storage.FileMembership.ConnectReadOnly, ExtractFileName, GraphTextNodesHtml (+6 more)</para>
/// <para>Returns: 2; 0</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 137 lines (full implementation)</para>
/// <para>SQL: reads FILES, REFS, SYMBOLS</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Graph.DoGraph.GraphJsonOrHtml"/>
/// <seealso cref="DRagLint.CLI.Graph.DoGraph.SanitizeId"/>
/// <seealso cref="DRagLint.CLI.Graph.DoGraph.UnitName"/>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <seealso cref="DRagLint.Core.OutputEncoding.WriteOutputFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoGraph(const AArgs: TArgs): Integer;

/// <summary>drag-lint arch-diagram --db D [--output F] [--json]: one self-contained HTML layer diagram of
/// the project's units by folder, or its model as JSON. Spec 2026-11-06-archify-layer-diagrams.</summary>
/// <param name="AArgs">Parsed CLI args.</param>
/// <returns>0 when written; 2 on a missing or stale DB, or an index with no units.</returns>
/// <remarks>
/// Read-only. Same DB, same bytes: nothing in the output depends on the clock.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Charts.ArchDiagram.ArchDiagramHtml, DRagLint.Charts.ArchDiagram.ArchModelJson, DRagLint.Charts.ArchDiagram.BuildArchModel, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.NoDbResolved, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.StaleDbRefusesRun, DRagLint.Core.OutputEncoding.WriteOutputFile, Writeln</para>
/// <para>Returns: 2; 0</para>
/// <para>Catches: EArchDiagram (swallowed)</para>
/// <seealso cref="DRagLint.Charts.ArchDiagram.ArchDiagramHtml"/>
/// <seealso cref="DRagLint.Charts.ArchDiagram.ArchModelJson"/>
/// <seealso cref="DRagLint.Charts.ArchDiagram.BuildArchModel"/>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.NoDbResolved"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoArchDiagram(const AArgs: TArgs): Integer;

/// <summary>drag-lint diff --db old --db new: symbols added, removed and signature-changed between two indexes, by qualified name.</summary>
/// <param name="AArgs">Two --db paths, old first.</param>
/// <returns>0; 2 without two --db or when one is missing.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.ConnectReadOnly, Format, Writeln</para>
/// <para>Returns: 0</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 104 lines (full implementation)</para>
/// <para>SQL: reads SYMBOLS</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectReadOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoDiff(const AArgs: TArgs): Integer;

/// <summary>`drag-lint todos`: the task-marker comments of the .pas / .dpr / .dpk files (the six tags are listed beside the implementation), with file:line:col and an optional author tag; no index needed.</summary>
/// <param name="AArgs">The path to scan and --json.</param>
/// <returns>0 on success; nonzero on a usage error.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Copy, Default, Format, StringReplace, Trim, UpperCase, Writeln</para>
/// <para>Returns: 0</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 108 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoTodos(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, Winapi.Windows, DRagLint.Core.OutputEncoding, System.SysUtils, System.Classes,
  System.IOUtils, System.NetEncoding, System.JSON, System.StrUtils, System.DateUtils,
  System.RegularExpressions, System.Generics.Collections, System.SyncObjs, FireDAC.Comp.Client,
  FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, TreeSitter, DRagLint.Storage.FileMembership,
  DRagLint.Query.TextNodes, DRagLint.Charts.ArchDiagram;

// --- graph ------------------------------------------------------------------

// v0.10: emit a unit-level dependency graph in Graphviz DOT or Mermaid
// syntax. One node per indexed source file; one edge per (referring-file
// -> defining-file) pair, weighted by reference count. Edge labels and
// node shape adapt to format.
function DoGraph(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  Format     : string        ;
  RootSubstr : string        ;
  WhereClause: string        ;
  Sql        : string        ;
  Buf        : TStringBuilder;
  FromPath   : string        ;
  ToPath     : string        ;
  FromUnit   : string        ;
  ToUnit     : string        ;
  Weight     : Integer       ;
  Output     : string        ;
  JsonEdges  : TStringList   ;

  function GraphJsonOrHtml(AEdges: TStringList; AHtml: Boolean): string;
  var
    Doc      : string                ;
    TextNodes: TArray<TGraphTextNode>;
    TextEdges: TArray<TGraphTextEdge>;
    Row: string;
    Tab: TStringBuilder;
  begin
    { E-PARITY-GRAPHIFY: the Markdown text nodes and their by-name links ride along. }
    LoadGraphTextNodes(Conn, RootSubstr, TextNodes, TextEdges);
    Doc:= '{"schema":"drag-lint.graph/1","edges":[' + string.Join(',', AEdges.ToStringArray) + '],' + GraphTextNodesJson(TextNodes, TextEdges) + '}';
    if not AHtml then Exit(Doc);
    Tab:= TStringBuilder.Create;
    try
      for Row in AEdges do Tab.Append('<li><code>').Append(TNetEncoding.HTML.Encode(Row)).AppendLine('</code></li>');
      Result:= '<!DOCTYPE html>' + sLineBreak + '<html><head><meta charset="utf-8"><title>drag-lint graph</title></head><body>' + sLineBreak
        + '<h1>drag-lint unit graph</h1><p>' + IntToStr(AEdges.Count) + ' edges (from, to, weight).</p><ul>' + sLineBreak
        + Tab.ToString + '</ul>' + sLineBreak + GraphTextNodesHtml(TextNodes, TextEdges) + '<script type="application/json" id="graph">' + Doc.Replace('<', '\u003c') + '</script>' + sLineBreak + '</body></html>';
    finally
      Tab.Free;
    end;
  end;

  function UnitName(const APath: string): string;
  begin
    Result:= ChangeFileExt(ExtractFileName(APath), '');
  end;

  function SanitizeId(const AName: string): string;
  var
    Ch: Char;
  begin
    Result:= '';
    for Ch in AName do
      Result:= if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Result + Ch else Result + '_';
    if (Result = '') or CharInSet(Result[1], ['0'..'9']) then Result:= '_' + Result;
  end;

begin
  JsonEdges:= nil;
  if AArgs.DbPath = '' then begin Writeln('ERROR: graph requires --db');
  Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath);
  Exit(2); end;
  Format:= if AArgs.Format <> '' then LowerCase(AArgs.Format) else 'dot';
  if not MatchText(Format, ['dot', 'mermaid', 'json', 'html']) then
  begin
    Writeln('ERROR: graph supports --format dot|mermaid|json|html (got "', Format, '")');
    Exit(2);
  end;
  RootSubstr:= AArgs.Name;

  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  Buf:= TStringBuilder.Create;
  try
    ConnectReadOnly(Conn, AArgs.DbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
    Q   .Connection := Conn;

    // Resolve refs by name_text -> symbols.name (the indexer leaves
    // symbol_id NULL today; that's a future cleanup but doesn't gate this
    // query). Restrict to symbol kinds worth drawing an arrow at.
    WhereClause:= 'f1.id <> f2.id AND s.kind IN (' + '''class'', ''interface'', ''record'', ''method'', ''procedure'', ' +
    '''function'', ''constructor'', ''destructor'', ''enum'', ''unit'')';
    if RootSubstr <> '' then WhereClause:= WhereClause + ' AND (f1.path LIKE :root OR f2.path LIKE :root)';
    Sql:= 'SELECT f1.path AS from_path, f2.path AS to_path, ' + '       COUNT(DISTINCT r.id) AS weight ' + 'FROM refs r ' + 'JOIN files f1 ON r.file_id = f1.id ' +
    'JOIN symbols s ON LOWER(s.name) = LOWER(r.name_text) ' + 'JOIN files f2 ON s.file_id = f2.id ' + 'WHERE ' + WhereClause + ' ' + 'GROUP BY f1.id, f2.id ' +
    'ORDER BY weight DESC';
    Q.Sql.Text:= Sql;
    if RootSubstr <> '' then Q.ParamByName('root').AsString:= '%' + RootSubstr + '%';
    Q.Open;

    if (Format = 'json') or (Format = 'html') then JsonEdges:= TStringList.Create;
    if JsonEdges <> nil then Buf.Clear { json/html: the document is assembled after the rows }
    else if Format = 'dot' then
    begin
      Buf.AppendLine('// Generated by drag-lint graph'                        );
      Buf.AppendLine('// One node per unit; one edge per A-references-B pair.');
      Buf.AppendLine('digraph DragLintDeps {'                                 );
      Buf.AppendLine('  rankdir=LR;'                                          );
      Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];'    );
      Buf.AppendLine('  edge [color="#888"];'                                 );
    end
    else // mermaid
    begin
      Buf.AppendLine('%% Generated by drag-lint graph');
      Buf.AppendLine('graph LR'                       );
    end;

    while not Q.Eof do
    begin
      FromPath:= Q.FieldByName('from_path').AsString;
      ToPath  := Q.FieldByName('to_path'  ).AsString;
      Weight  := Q.FieldByName('weight'   ).AsInteger;
      FromUnit:= UnitName(FromPath);
      ToUnit  := UnitName(ToPath  );

      if JsonEdges <> nil then JsonEdges.Add(System.SysUtils.Format('{"from":"%s","to":"%s","weight":%d}', [JsonEscape(FromUnit), JsonEscape(ToUnit), Weight]))
      else if Format = 'dot' then Buf.AppendLine(System.SysUtils.Format( '  "%s" -> "%s" [label="%d", weight=%d];', [FromUnit, ToUnit, Weight, Weight]))
      else Buf.AppendLine(System.SysUtils.Format('  %s --|%d|--> %s', [SanitizeId(FromUnit), Weight, SanitizeId(ToUnit)]));

      Q.Next;
    end;

    if JsonEdges <> nil then Buf.Append(GraphJsonOrHtml(JsonEdges, Format = 'html'))
    else if Format = 'dot' then Buf.AppendLine('}');

    Output:= Buf.ToString;
    if AArgs.Output <> '' then
    begin
      WriteOutputFile(AArgs.Output, Output);
      Writeln('Wrote ', AArgs.Output);
    end
    else Writeln(Output);
  finally
    JsonEdges.Free;
    Buf.Free;
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // begin

function DoArchDiagram(const AArgs: TArgs): Integer;
begin
  if not ExplicitDbsExist(AArgs, 'arch-diagram') then Exit(2);
  if NoDbResolved(AArgs.DbPath, 'arch-diagram') then Exit(2);
  var RoOk: Boolean;
  OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then
  begin
    StaleDbRefusesRun(AArgs, 'arch-diagram', AArgs.DbPath);
    Exit(2);
  end;
  var Model: TArchModel;
  try
    Model:= BuildArchModel(AArgs.DbPath);
  except
    on E: EArchDiagram do
    begin
      Writeln(ErrOutput, 'ERROR: ', E.Message);
      Exit(2);
    end;
  end;
  var Text:= if AArgs.AsJson then ArchModelJson(Model) else ArchDiagramHtml(Model);
  if AArgs.Output <> '' then
  begin
    WriteOutputFile(AArgs.Output, Text);
    Writeln('Wrote ', AArgs.Output);
  end
  else Writeln(Text);
  Result:= 0;
end;

// --- diff -------------------------------------------------------------------

// v0.13: diff two indexes by qualified_name. Pass two --db args:
//   drag-lint diff --db old.sqlite --db new.sqlite
// Reports added, removed, and signature-changed symbols. Useful for
// reviewing the API impact of a refactor commit.
function DoDiff(const AArgs: TArgs): Integer;
var
  DbA    : string                     ;
  DbB    : string                     ;
  ConnA  : TFDConnection              ;
  ConnB  : TFDConnection              ;
  QA     : TFDQuery                   ;
  QB     : TFDQuery                   ;
  SetA   : TDictionary<string, string>; // qname -> "kind|signature"
  SetB   : TDictionary<string, string>;
  Pair   : TPair<string, string>      ;
  Added  : Integer                    ;
  Removed: Integer                    ;
  Changed: Integer                    ;
  JArr   : TJSONArray                 ;
  JObj   : TJSONObject                ;
  Tag    : string                     ;
begin
  if Length(AArgs.DbPaths) < 2 then begin Writeln('ERROR: diff requires two --db arguments ' + '(--db <old.sqlite> --db <new.sqlite>)');
  Exit(2); end;
  DbA:= AArgs.DbPaths[0];
  DbB:= AArgs.DbPaths[1];
  if not TFile.Exists(DbA) then begin Writeln('ERROR: --db ', DbA, ' not found');
  Exit(2); end;
  if not TFile.Exists(DbB) then begin Writeln('ERROR: --db ', DbB, ' not found');
  Exit(2); end;

  ConnA:= TFDConnection.Create(nil);
  ConnB:= TFDConnection.Create(nil);
  QA   := TFDQuery     .Create(nil);
  QB   := TFDQuery     .Create(nil);
  SetA:= TDictionary<string, string>.Create;
  SetB:= TDictionary<string, string>.Create;
  try
    ConnectReadOnly(ConnA, DbA); { readers: never FireDAC's Exclusive/Delete defaults }
    ConnectReadOnly(ConnB, DbB);
    QA   .Connection := ConnA;
    QB   .Connection := ConnB;
    QA.Sql.Text:= 'SELECT qualified_name, kind, COALESCE(signature, '''') AS sig ' + 'FROM symbols WHERE qualified_name <> '''' ';
    QB.Sql.Text:= QA.Sql.Text;
    QA.Open;
    while not QA.Eof do begin SetA.AddOrSetValue( QA.FieldByName('qualified_name').AsString, QA.FieldByName('kind').AsString + '|' + QA.FieldByName('sig').AsString);
    QA.Next; end;
    QB.Open;
    while not QB.Eof do begin SetB.AddOrSetValue( QB.FieldByName('qualified_name').AsString, QB.FieldByName('kind').AsString + '|' + QB.FieldByName('sig').AsString);
    QB.Next; end;

    Added  := 0;
    Removed:= 0;
    Changed:= 0;

    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for Pair in SetB do
          if not SetA.ContainsKey(Pair.Key) then
          begin
            JObj:= TJSONObject.Create;
            JObj.AddPair('change', 'added');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Added);
          end
        else if SetA[Pair.Key] <> Pair.Value then
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('change', 'changed');
          JObj.AddPair('qualified_name', Pair.Key);
          JObj.AddPair('from', SetA[Pair.Key]);
          JObj.AddPair('to', Pair.Value);
          JArr.AddElement(JObj);
          Inc(Changed);
        end;
        for Pair in SetA do
          if not SetB.ContainsKey(Pair.Key) then
          begin
            JObj:= TJSONObject.Create;
            JObj.AddPair('change', 'removed');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Removed);
          end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      for Pair in SetB do
        if not SetA.ContainsKey(Pair.Key) then begin Tag:= Pair.Value.Split(['|'])[0];
        Writeln('+ ', Pair.Key, '  [', Tag, ']');
        Inc(Added); end
      else if SetA[Pair.Key] <> Pair.Value then begin Writeln('~ ', Pair.Key);
      Writeln('    from: ', SetA[Pair.Key]);
      Writeln('    to:   ', Pair.Value);
      Inc(Changed); end;
      for Pair in SetA do
        if not SetB.ContainsKey(Pair.Key) then begin Tag:= Pair.Value.Split(['|'])[0];
        Writeln('- ', Pair.Key, '  [', Tag, ']');
        Inc(Removed); end;
      Writeln(Format('Summary: %d added, %d removed, %d changed', [Added, Removed, Changed]));
    end; // else

    Result:= 0;
  finally
    SetA.Free;
    SetB.Free;
    QA.Free;
    QB.Free;
    ConnA.Free;
    ConnB.Free;
  end; // try
end; // function

// --- todos ------------------------------------------------------------------

// v0.12: scan .pas/.dpr/.dpk files for TODO/FIXME/HACK/XXX/REVIEW/NOTE
// comments and report them with file:line:col + optional author tag.
// Standalone - no index needed. Intended workflow: run before commits,
// or pipe into `--json` for CI dashboards.
function DoTodos(const AArgs: TArgs): Integer;
type
  TTodo = record
    FilePath: string ;
    LineNo  : Integer;
    ColNo   : Integer;
    Keyword : string ;
    Author  : string ;
    Body    : string ;
  end;
var
  Path    : string        ;
  Files   : TArray<string>;
  Patterns: TArray<string>;
  Pattern : string        ;
  FileName: string        ;
  Lines   : TArray<string>;
  Line    : string        ;
  Tail    : string        ;
  RE      : TRegEx        ;
  M       : TMatch        ;
  Todos   : TList<TTodo>  ;
  T       : TTodo         ;
  i       : Integer       ;
  JArr    : TJSONArray    ;
  JObj    : TJSONObject   ;
begin
  Path:= if AArgs.Path = '' then GetCurrentDir else AArgs.Path;
  if not (TDirectory.Exists(Path) or TFile.Exists(Path)) then begin Writeln('ERROR: path does not exist: ', Path);
  Exit(2); end;
  // Keyword set is intentionally narrow and word-boundaried so noise like
  // "fixmessage" doesn't false-trip. Author tag accepts @alex or "Alex:"
  // forms, matching common Delphi codebase conventions.
  // Author tag accepts @alex or "Alex:" forms (starts with a letter, to
  // avoid swallowing Delphi's built-in priority digits like `TODO 1`).
  RE:= TRegEx.Create( '//\s*(TODO|FIXME|HACK|XXX|REVIEW|NOTE)\b' + '(?:[@\s]([A-Za-z]\w*))?[\s:]*(.*)$', [roIgnoreCase]);

  Todos:= TList<TTodo>.Create;
  try
    if TFile.Exists(Path) then Files:= [Path]
    else
    begin
      Patterns:= ['*.pas', '*.dpr', '*.dpk', '*.inc'];
      Files:= nil;
      for Pattern in Patterns do Files:= Files + TDirectory.GetFiles(Path, Pattern, TSearchOption.soAllDirectories);
    end;
    for FileName in Files do
    begin
      try
        Lines:= TFile.ReadAllLines(FileName);
      except  // dl:ok try-except-swallowed@69ff, bare-except@69ff -- REVIEWED 2026-11-19 SLZ-MARK: best-effort probe or file read with a documented fallback; the handler assigns that fallback or exits, so no result is lost silently
        Continue;
      end;
      for i:= 0 to High(Lines) do
      begin
        Line:= Lines[i];
        M:= RE.Match(Line);
        if not M.Success then Continue;
        // Skip when `//` lives inside a quoted string by checking the
        // count of `'` chars before the `//` position - odd count means
        // we're inside a string literal.
        Tail:= Copy(Line, 1, M.Index - 1);
        if (Length(Tail) - Length(StringReplace( Tail, '''', '', [rfReplaceAll]))) mod 2 = 1 then Continue;
        T:= Default(TTodo);
        T.FilePath:= FileName;
        T.LineNo:= i + 1;
        T.ColNo:= M.Index;
        T.Keyword:= UpperCase(M.Groups[1].Value);
        T.Author:= if M.Groups[2].Success then M.Groups[2].Value else '';
        T.Body:= Trim(M.Groups[3].Value);
        Todos.Add(T);
      end; // for
    end; // for

    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        for T in Todos do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('file_path', T.FilePath);
          JObj.AddPair('line', TJSONNumber.Create(T.LineNo));
          JObj.AddPair('col' , TJSONNumber.Create(T.ColNo ));
          JObj.AddPair('keyword', T.Keyword);
          JObj.AddPair('author' , T.Author );
          JObj.AddPair('body'   , T.Body   );
          JArr.AddElement(JObj);
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      for T in Todos do
      begin
        if T.Author <> '' then Writeln(Format('%s:%d:%d  [%s @%s] %s', [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Author, T.Body]))
        else Writeln(Format('%s:%d:%d  [%s] %s', [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Body]));
      end;
      Writeln(Format('%d todo(s)', [Todos.Count]));
    end;
  finally
    Todos.Free;
  end; // try
  Result:= 0;
end; // begin

end.
