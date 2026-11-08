unit DRagLint.Query.TextNodes;

(* E-PARITY-GRAPHIFY (wave 147): the Markdown text nodes of an index, linked to
   code BY NAME, for `graph --format json|html`.

   A text node is one string_literals row with source = 'md' (written by
   TMarkdownParser). A text EDGE runs from a node to the unit that declares a
   name the node mentions in backticks -- `TWidget`, `uMdA`, `TWidget.Run`.
   Only an UNAMBIGUOUS name links: it must resolve to declarations in exactly
   one indexed source file. A name nothing declares, or that several files
   declare, makes no edge. Nothing here writes. *)

interface

uses
  FireDAC.Comp.Client
  ;

type
  /// <summary>One Markdown text node: a heading, paragraph or list item.</summary>
  TGraphTextNode = record
    Id      : string ; { '<file name>:<line>', unique within one graph }
    FileName: string ; { base name of the .md file }
    Path    : string ; { files.path as indexed }
    Kind    : string ; { 'md-heading' | 'md-text' }
    Section : string ; { the enclosing heading; '' before the first }
    Text    : string ;
    Line    : Integer;
  end;

  /// <summary>A text node -> the unit declaring a name it mentions.</summary>
  TGraphTextEdge = record
    FromId: string; { TGraphTextNode.Id }
    ToUnit: string; { the declaring file's base name without extension: the graph's unit node }
    Name  : string; { the backticked name as written }
  end;

/// <summary>Reads every Markdown text node of an index and links each to code by name.</summary>
/// <param name="AConn">An open (read-only) connection to the index.</param>
/// <param name="ARootSubstr">graph --name: when not empty, keeps a node only if its
/// own path, or the path of a unit it links to, contains this text (case-insensitive).</param>
/// <param name="ANodes">The nodes, ordered by path then line.</param>
/// <param name="AEdges">The edges of the kept nodes.</param>
/// <remarks>An index without Markdown (every DB built before 1.47) yields two empty arrays.</remarks>
procedure LoadGraphTextNodes(AConn: TFDConnection; const ARootSubstr: string; out ANodes: TArray<TGraphTextNode>;
  out AEdges: TArray<TGraphTextEdge>);

/// <summary>The JSON members the graph document carries for text nodes.</summary>
/// <param name="ANodes">From LoadGraphTextNodes.</param>
/// <param name="AEdges">From LoadGraphTextNodes.</param>
/// <returns>'"text_nodes":[..],"text_edges":[..]' -- no braces, ready to splice
/// into the drag-lint.graph/1 object.</returns>
function GraphTextNodesJson(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;

/// <summary>The HTML section listing the text nodes and what each links to.</summary>
/// <param name="ANodes">From LoadGraphTextNodes.</param>
/// <param name="AEdges">From LoadGraphTextNodes.</param>
/// <returns>An h2 plus a list, HTML-encoded; '' when there are no nodes.</returns>
function GraphTextNodesHtml(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , System.NetEncoding
  , Data.DB
  , DRagLint.Core.Model
  ;

const
  { The same symbol kinds the unit graph draws an arrow at (DoGraph). }
  LINK_KINDS = '''class'', ''interface'', ''record'', ''method'', ''procedure'', ''function'', ' +
    '''constructor'', ''destructor'', ''enum'', ''unit''';

{ The backticked identifier names in a text, in order of first
  appearance, deduplicated case-insensitively.
  AText is a node's text; the result holds each `span` that is a Pascal identifier or a dotted chain of them
  (a trailing "()" is dropped); every other span is ignored. }
function BacktickNames(const AText: string): TArray<string>;
var
  M   : TMatch                     ;
  Name: string                     ;
  Seen: TDictionary<string, Boolean>;
  Res : TList<string>              ;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Res:= TList<string>.Create;
  try
    for M in TRegEx.Matches(AText, '`([^`]+)`') do
    begin
      Name:= Trim(M.Groups[1].Value);
      if EndsStr('()', Name) then SetLength(Name, Length(Name) - Length('()'));
      if not TRegEx.IsMatch(Name, '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$') then Continue;
      if Seen.ContainsKey(LowerCase(Name)) then Continue;
      Seen.Add(LowerCase(Name), True);
      Res.Add(Name);
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
    Seen.Free;
  end;
end;

procedure LoadGraphTextNodes(AConn: TFDConnection; const ARootSubstr: string; out ANodes: TArray<TGraphTextNode>;
  out AEdges: TArray<TGraphTextEdge>);
var
  Q       : TFDQuery                      ;
  QName   : TFDQuery                      ;
  Nodes   : TList<TGraphTextNode>         ;
  Edges   : TList<TGraphTextEdge>         ;
  Cache   : TDictionary<string, string>   ; { lower(name) -> declaring path, '' = none or ambiguous }
  Node    : TGraphTextNode                ;
  Edge    : TGraphTextEdge                ;
  Name    : string                        ;
  Target  : string                        ;
  Keep    : Boolean                       ;
  Root    : string                        ;
  NodeEdge: TList<TGraphTextEdge>         ;
  FldPath   : TField                        ;
  FldKind   : TField                        ;
  FldSection: TField                        ;
  FldText   : TField                        ;
  FldLine   : TField                        ;

  function Resolve(const AName: string): string;
  var
    Paths: TList<string>;
  begin
    if Cache.TryGetValue(LowerCase(AName), Result) then Exit;
    Result:= '';
    QName.Sql.Text:= if ContainsStr(AName, '.') then
      'SELECT DISTINCT f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id ' +
        'WHERE s.kind IN (' + LINK_KINDS + ') AND (s.qualified_name = :n COLLATE NOCASE ' +
        'OR s.qualified_name LIKE :tail) LIMIT 2'
    else
      'SELECT DISTINCT f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id ' +
        'WHERE s.kind IN (' + LINK_KINDS + ') AND s.name = :n COLLATE NOCASE LIMIT 2';
    QName.ParamByName('n').AsWideString:= AName;
    if QName.FindParam('tail') <> nil then QName.ParamByName('tail').AsWideString:= '%.' + AName;
    QName.Open;
    Paths:= TList<string>.Create;
    try
      while not QName.Eof do
      begin
        Paths.Add(QName.Fields[0].AsString); { the one column: path }
        QName.Next;
      end;
      if Paths.Count = 1 then Result:= Paths[0];
    finally
      Paths.Free;
      QName.Close;
    end;
    Cache.Add(LowerCase(AName), Result);
  end;

begin
  ANodes:= nil;
  AEdges:= nil;
  Root:= LowerCase(ARootSubstr);
  Q:= TFDQuery.Create(nil);
  QName:= TFDQuery.Create(nil);
  Nodes:= TList<TGraphTextNode>.Create;
  Edges:= TList<TGraphTextEdge>.Create;
  NodeEdge:= TList<TGraphTextEdge>.Create;
  Cache:= TDictionary<string, string>.Create;
  try
    Q.Connection:= AConn;
    QName.Connection:= AConn;
    Q.Sql.Text:= 'SELECT f.path AS path, sl.kind AS kind, COALESCE(sl.owner_name, '''') AS section, sl.text AS txt, ' +
      'sl.start_line AS line FROM string_literals sl JOIN files f ON f.id = sl.file_id ' +
      'WHERE sl.source = ''md'' ORDER BY f.path, sl.start_line, sl.start_col';
    Q.Open;
    FldPath   := Q.FieldByName('path'   );
    FldKind   := Q.FieldByName('kind'   );
    FldSection:= Q.FieldByName('section');
    FldText   := Q.FieldByName('txt'    );
    FldLine   := Q.FieldByName('line'   );
    while not Q.Eof do
    begin
      Node:= Default(TGraphTextNode);
      Node.Path    := FldPath.AsString;
      Node.FileName:= ExtractFileName(Node.Path);
      Node.Kind    := FldKind.AsString;
      Node.Section := FldSection.AsString;
      Node.Text    := FldText.AsString;
      Node.Line    := FldLine.AsInteger;
      Node.Id      := Node.FileName + ':' + IntToStr(Node.Line);
      Keep:= (Root = '') or ContainsStr(LowerCase(Node.Path), Root);
      NodeEdge.Clear;
      for Name in BacktickNames(Node.Text) do
      begin
        Target:= Resolve(Name);
        if Target = '' then Continue;
        if (Root <> '') and ContainsStr(LowerCase(Target), Root) then Keep:= True;
        Edge.FromId:= Node.Id;
        Edge.ToUnit:= ChangeFileExt(ExtractFileName(Target), '');
        Edge.Name  := Name;
        NodeEdge.Add(Edge);
      end;
      if Keep then
      begin
        Nodes.Add(Node);
        Edges.AddRange(NodeEdge);
      end;
      Q.Next;
    end;
    ANodes:= Nodes.ToArray;
    AEdges:= Edges.ToArray;
  finally
    Cache.Free;
    NodeEdge.Free;
    Edges.Free;
    Nodes.Free;
    QName.Free;
    Q.Free;
  end;
end;

function GraphTextNodesJson(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;
var
  Parts: TList<string> ;
  N    : TGraphTextNode;
  E    : TGraphTextEdge;
  NJson: string        ;
begin
  Parts:= TList<string>.Create;
  try
    for N in ANodes do
      Parts.Add(Format('{"id":"%s","file":"%s","path":"%s","line":%d,"kind":"%s","section":"%s","text":"%s"}',
        [JsonEscape(N.Id), JsonEscape(N.FileName), JsonEscape(N.Path), N.Line, JsonEscape(N.Kind), JsonEscape(N.Section),
         JsonEscape(N.Text)]));
    NJson:= string.Join(',', Parts.ToArray);
    Parts.Clear;
    for E in AEdges do
      Parts.Add(Format('{"from":"%s","to":"%s","name":"%s"}', [JsonEscape(E.FromId), JsonEscape(E.ToUnit), JsonEscape(E.Name)]));
    Result:= '"text_nodes":[' + NJson + '],"text_edges":[' + string.Join(',', Parts.ToArray) + ']';
  finally
    Parts.Free;
  end;
end;

function GraphTextNodesHtml(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;
var
  Sb   : TStringBuilder;
  N    : TGraphTextNode;
  E    : TGraphTextEdge;
  Links: string        ;
begin
  if Length(ANodes) = 0 then Exit('');
  Sb:= TStringBuilder.Create;
  try
    Sb.Append('<h2>').Append(Length(ANodes)).Append(' text node(s), ').Append(Length(AEdges))
      .AppendLine(' link(s) to code by name</h2><ul>');
    for N in ANodes do
    begin
      Links:= '';
      for E in AEdges do
        if E.FromId = N.Id then
          Links:= Links + IfThen(Links <> '', ', ') + TNetEncoding.HTML.Encode(E.ToUnit + ' (' + E.Name + ')');
      Sb.Append('<li><code>').Append(TNetEncoding.HTML.Encode(N.Id)).Append('</code> ');
      if N.Section <> '' then Sb.Append('[').Append(TNetEncoding.HTML.Encode(N.Section)).Append('] ');
      Sb.Append(TNetEncoding.HTML.Encode(N.Text));
      if Links <> '' then Sb.Append(' &rarr; ').Append(Links);
      Sb.AppendLine('</li>');
    end;
    Sb.AppendLine('</ul>');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
