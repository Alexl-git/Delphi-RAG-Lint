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

/// <summary>The HTML section that draws and lists the text nodes and what each links to.</summary>
/// <param name="ANodes">From LoadGraphTextNodes.</param>
/// <param name="AEdges">From LoadGraphTextNodes.</param>
/// <returns>'' when there are no nodes (no layer, no toggle). Otherwise one section:
/// a checkbox `dl-tn-toggle` (checked) that shows / hides the layer; a legend
/// (note box = Markdown text node, dashed line = mentions by name, box = unit);
/// an inline SVG `dl-tn-svg` with one note box per node (`dl-tn-note`,
/// data-id = the node id), one box per linked unit (`dl-tn-unit`, data-unit) and
/// one dashed path per edge (`dl-tn-edge`, data-from / data-to); then the h2 and
/// the list of every node. Everything is HTML-encoded; no script is needed.</returns>
/// <remarks>The toggle is pure CSS (`:checked ~`), so the page works with
/// scripts off. A note box shows the id, the section and the first characters of
/// the text; its SVG title carries the full text.</remarks>
function GraphTextNodesHtml(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;

implementation

uses
  System.SysUtils
  , System.Math
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

const
  { Text-layer drawing (wave 148 TN): notes in a left column, linked units in a right one. }
  TN_PAD     = 10 ; { outer margin, px }
  TN_NOTE_W  = 380; { note box width }
  TN_NOTE_H  = 40 ; { note box height: two text lines }
  TN_ROW     = 52 ; { vertical step of one row (box + gap) }
  TN_UNIT_X  = 520; { left edge of the unit column }
  TN_UNIT_W  = 200; { unit box width }
  TN_UNIT_H  = 26 ; { unit box height }
  TN_LINE1_Y = 16 ; { baseline of a note's first line, from the box top }
  TN_LINE2_Y = 32 ; { baseline of its second line }
  TN_TEXT_X  = 6  ; { text inset from a box's left edge }
  TN_CLIP    = 58 ; { characters shown per note line }
  TN_DASH    = '6 4'; { stroke-dasharray of a text edge }

{ AText cut to at most AMax characters, '...' marking a cut. }
function ClipText(const AText: string; AMax: Integer): string;
begin
  Result:= if Length(AText) <= AMax then AText else Copy(AText, 1, AMax - Length('...')) + '...';
end;

{ The legend above the text layer: one sample of each mark. }
function TextLayerLegend: string;
begin
  Result:= '<div class="dl-tn-legend">' +
    '<svg width="34" height="14"><g class="dl-tn-note"><rect x="1" y="1" width="32" height="12"/></g></svg> Markdown text node ' +
    '<svg width="34" height="14"><path class="dl-tn-edge" stroke-dasharray="' + TN_DASH + '" d="M0 7H34"/></svg> mentions by name ' +
    '<svg width="34" height="14"><g class="dl-tn-unit"><rect x="1" y="1" width="32" height="12"/></g></svg> unit declaring the name' +
    '</div>' + sLineBreak;
end;

{ The inline SVG of the text layer: a note box per node, a box per linked unit
  (first-mention order), a dashed cubic path per edge from the note's right
  edge to the unit's left edge. }
function TextLayerSvg(const ANodes: TArray<TGraphTextNode>; const AEdges: TArray<TGraphTextEdge>): string;
var
  Sb     : TStringBuilder              ;
  NoteY  : TDictionary<string, Integer>;
  UnitY  : TDictionary<string, Integer>;
  Units  : TList<string>               ;
  N      : TGraphTextNode              ;
  E      : TGraphTextEdge              ;
  U      : string                      ;
  Y      : Integer                     ;
  Y1     : Integer                     ;
  Y2     : Integer                     ;
  X1     : Integer                     ;
  XMid   : Integer                     ;
  Rows   : Integer                     ;
  Head   : string                      ;
begin
  Sb:= TStringBuilder.Create;
  NoteY:= TDictionary<string, Integer>.Create;
  UnitY:= TDictionary<string, Integer>.Create;
  Units:= TList<string>.Create;
  try
    for E in AEdges do
      if not UnitY.ContainsKey(E.ToUnit) then
      begin
        UnitY.Add(E.ToUnit, TN_PAD + Units.Count * TN_ROW);
        Units.Add(E.ToUnit);
      end;
    Rows:= Max(Length(ANodes), Units.Count);
    Sb.AppendFormat('<svg id="dl-tn-svg" xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" role="img" ' +
      'aria-label="Markdown text nodes and the units they mention">', [TN_UNIT_X + TN_UNIT_W + TN_PAD, 2 * TN_PAD + Rows * TN_ROW]).AppendLine;
    Y:= TN_PAD;
    for N in ANodes do
    begin
      NoteY.AddOrSetValue(N.Id, Y);
      Head:= N.Id + IfThen(N.Section <> '', ' [' + N.Section + ']');
      Sb.Append('<g class="dl-tn-note" data-id="').Append(TNetEncoding.HTML.Encode(N.Id)).Append('"><title>')
        .Append(TNetEncoding.HTML.Encode(N.Text)).Append('</title>')
        .AppendFormat('<rect x="%d" y="%d" width="%d" height="%d" rx="3"/>', [TN_PAD, Y, TN_NOTE_W, TN_NOTE_H])
        .AppendFormat('<text x="%d" y="%d">', [TN_PAD + TN_TEXT_X, Y + TN_LINE1_Y]).Append(TNetEncoding.HTML.Encode(ClipText(Head, TN_CLIP)))
        .AppendFormat('</text><text x="%d" y="%d">', [TN_PAD + TN_TEXT_X, Y + TN_LINE2_Y]).Append(TNetEncoding.HTML.Encode(ClipText(N.Text, TN_CLIP)))
        .AppendLine('</text></g>');
      Inc(Y, TN_ROW);
    end;
    for U in Units do
      Sb.Append('<g class="dl-tn-unit" data-unit="').Append(TNetEncoding.HTML.Encode(U)).Append('">')
        .AppendFormat('<rect x="%d" y="%d" width="%d" height="%d"/>', [TN_UNIT_X, UnitY[U], TN_UNIT_W, TN_UNIT_H])
        .AppendFormat('<text x="%d" y="%d">', [TN_UNIT_X + TN_TEXT_X, UnitY[U] + TN_LINE1_Y + 1])
        .Append(TNetEncoding.HTML.Encode(ClipText(U, TN_CLIP))).AppendLine('</text></g>');
    X1:= TN_PAD + TN_NOTE_W;
    XMid:= (X1 + TN_UNIT_X) div 2;
    for E in AEdges do
    begin
      if not NoteY.TryGetValue(E.FromId, Y1) then Continue;
      Y1:= Y1 + TN_NOTE_H div 2;
      Y2:= UnitY[E.ToUnit] + TN_UNIT_H div 2;
      Sb.Append('<path class="dl-tn-edge" data-from="').Append(TNetEncoding.HTML.Encode(E.FromId)).Append('" data-to="')
        .Append(TNetEncoding.HTML.Encode(E.ToUnit)).Append('" stroke-dasharray="').Append(TN_DASH)
        .AppendFormat('" d="M%d %d C%d %d %d %d %d %d"><title>', [X1, Y1, XMid, Y1, XMid, Y2, TN_UNIT_X, Y2])
        .Append(TNetEncoding.HTML.Encode(E.Name)).AppendLine('</title></path>');
    end;
    Sb.AppendLine('</svg>');
    Result:= Sb.ToString;
  finally
    Units.Free;
    UnitY.Free;
    NoteY.Free;
    Sb.Free;
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
    Sb.AppendLine('<section class="dl-tn">');
    Sb.AppendLine('<style>.dl-tn-layer{margin:8px 0}#dl-tn-toggle:not(:checked)~.dl-tn-layer{display:none}' +
      '.dl-tn-note rect{fill:#fff8c5;stroke:#9a6700}.dl-tn-unit rect{fill:#ddf4ff;stroke:#0969da}' +
      '.dl-tn-edge{fill:none;stroke:#6e7781;stroke-width:1.5}.dl-tn text{font:12px sans-serif;fill:#1f2328}' +
      '.dl-tn-legend{font:12px sans-serif}</style>');
    Sb.AppendLine('<input type="checkbox" id="dl-tn-toggle" checked><label for="dl-tn-toggle"> Show text nodes</label>');
    Sb.AppendLine('<div class="dl-tn-layer">');
    Sb.Append(TextLayerLegend);
    Sb.Append(TextLayerSvg(ANodes, AEdges));
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
    Sb.AppendLine('</div></section>');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
