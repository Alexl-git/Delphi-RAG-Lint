unit DRagLint.Charts.Q.ClassDiagram;

{ drag-lint 1.56 -- lane CHB-1: the chart question `class-diagram` (`ask class-diagram`).
  G-43: one type with its ancestors, its descendants and the classes of its fields.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT).

  Data (single index, read-only, all through TChartsIndex.Query):
    ancestors   type_ancestors rows walked upward from the focus (a resolved ancestor is drawn as a class, an
                unresolved one as a node outside the index); each row is ONE ancestor edge.
    descendants type_ancestors rows whose ancestor_symbol_id is a drawn type, walked downward; one edge each.
    fields      the focus's field symbols; the field's type is the resolved type_use ref on the field's line.
                One field edge per (field, type) pair; the type must be a class, interface or record.
  Not drawn: fields of the ancestors and descendants (has-a links are one type deep), fields whose type is not
  an indexed class (Integer, string, RTL types). Both walks stop at Depth levels / Cap nodes. }

interface

const
  /// <summary>The registered question id.</summary>
  CLASS_DIAGRAM_ID = 'class-diagram';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  FOCUS_FILL = '#E2F1EF';
  ANC_FILL = '#EDF2FF';
  DESC_FILL = '#FEF6EC';
  FIELD_FILL = '#F5F5F5';
  LINE_INK = '#8A94A6';
  DEFAULT_DEPTH = 4;
  DEFAULT_CAP = 20;
  FOCUS_PEN = 3;

type
  /// <summary>One drawn type: display data and where it is declared (Id 0 = outside the index).</summary>
  TTypeNode = record
    Id: Integer;
    Name: string;
    Kind: string;
    Path: string;
    Line: Integer;
    Fill: string;
  end;

  /// <summary>The nodes and edges collected for one diagram.</summary>
  TDiagram = class
  private
    FNodes: TList<TTypeNode>;
    FAncEdges: TList<string>;
    FDescEdges: TList<string>;
    FFieldEdges: TList<string>;
    FKeys: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    function Has(const pNode: TTypeNode): Boolean;
    procedure Add(const pNode: TTypeNode);
    property Nodes: TList<TTypeNode> read FNodes;
    property AncEdges: TList<string> read FAncEdges;
    property DescEdges: TList<string> read FDescEdges;
    property FieldEdges: TList<string> read FFieldEdges;
  end;

function NodeKey(const pNode: TTypeNode): string;
begin
  Result:= if pNode.Id > 0 then 'n' + pNode.Id.ToString else 'u_' + TRegEx.Replace(LowerCase(pNode.Name), '[^a-z0-9]', '_');
end;

constructor TDiagram.Create;
begin
  inherited Create;
  FNodes:= TList<TTypeNode>.Create;
  FAncEdges:= TList<string>.Create;
  FDescEdges:= TList<string>.Create;
  FFieldEdges:= TList<string>.Create;
  FKeys:= TDictionary<string, Boolean>.Create;
end;

destructor TDiagram.Destroy;
begin
  FKeys.Free;
  FFieldEdges.Free;
  FDescEdges.Free;
  FAncEdges.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TDiagram.Has(const pNode: TTypeNode): Boolean;
begin
  Result:= FKeys.ContainsKey(NodeKey(pNode));
end;

procedure TDiagram.Add(const pNode: TTypeNode);
begin
  if not Has(pNode) then
  begin
    FKeys.Add(NodeKey(pNode), True);
    FNodes.Add(pNode);
  end;
end;

function TypeNodeOf(const pRow: TIndexRow; const pFill: string): TTypeNode;
begin
  Result.Id:= pRow.I('id');
  Result.Name:= pRow.S('name');
  Result.Kind:= pRow.S('kind');
  Result.Path:= pRow.S('path');
  Result.Line:= pRow.I('start_line');
  Result.Fill:= pFill;
end;

function LoadType(const pIndex: TChartsIndex; pId: Integer; const pFill: string; out pNode: TTypeNode): Boolean;
begin
  pNode:= Default(TTypeNode);
  var Rows:= pIndex.Query(
    'SELECT s.id AS id, s.name AS name, s.kind AS kind, s.start_line AS start_line, f.path AS path' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = ' + pId.ToString);
  try
    Result:= Rows.Count > 0;
    if Result then
      pNode:= TypeNodeOf(Rows[0], pFill);
  finally
    Rows.Free;
  end;
end;

function EdgeText(const pFrom, pTo, pAttrs: string): string;
begin
  Result:= Format('  %s -> %s [%s];', [pFrom, pTo, pAttrs]);
end;

// Upward walk: every type_ancestors row of the type is one ancestor edge; a resolved ancestor is walked on.
procedure WalkAncestors(const pIndex: TChartsIndex; const pDia: TDiagram; const pFrom: TTypeNode; pDepth, pCap: Integer);
begin
  if (pDepth <= 0) or (pDia.Nodes.Count >= pCap) then
    Exit;
  var Rows:= pIndex.Query(
    'SELECT ancestor_name AS aname, ancestor_symbol_id AS aid FROM type_ancestors' + sLineBreak +  // dl:ok sql-injection-concat@8830 -- REVIEWED 2026-11-27 CHB-1: the only concatenated value is an integer symbol id from symbols.id, rendered by Integer.ToString
    ' WHERE symbol_id = ' + pFrom.Id.ToString + ' ORDER BY ordinal');
  try
    for var R in Rows do
    begin
      var Anc: TTypeNode;
      if not ((R.I('aid') > 0) and LoadType(pIndex, R.I('aid'), ANC_FILL, Anc)) then
      begin
        Anc:= Default(TTypeNode);
        Anc.Name:= R.S('aname');
        Anc.Kind:= 'outside this index';
        Anc.Fill:= ANC_FILL;
      end;
      var Fresh:= not pDia.Has(Anc);
      pDia.Add(Anc);
      pDia.AncEdges.Add(EdgeText(NodeKey(pFrom), NodeKey(Anc), 'arrowhead=empty, color="#3B5BDB"'));
      if Fresh and (Anc.Id > 0) then
        WalkAncestors(pIndex, pDia, Anc, pDepth - 1, pCap);
    end;
  finally
    Rows.Free;
  end;
end;

// Downward walk: types whose type_ancestors row points at pFrom.
procedure WalkDescendants(const pIndex: TChartsIndex; const pDia: TDiagram; const pFrom: TTypeNode; pDepth, pCap: Integer);
begin
  if (pDepth <= 0) or (pDia.Nodes.Count >= pCap) then
    Exit;
  var Rows:= pIndex.Query(
    'SELECT s.id AS id, s.name AS name, s.kind AS kind, s.start_line AS start_line, f.path AS path' + sLineBreak +
    '  FROM type_ancestors ta JOIN symbols s ON s.id = ta.symbol_id JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE ta.ancestor_symbol_id = ' + pFrom.Id.ToString + ' ORDER BY s.name, s.id');
  try
    for var R in Rows do
    begin
      var Desc:= TypeNodeOf(R, DESC_FILL);
      var Fresh:= not pDia.Has(Desc);
      pDia.Add(Desc);
      pDia.DescEdges.Add(EdgeText(NodeKey(Desc), NodeKey(pFrom), 'arrowhead=empty, color="#B45309"'));
      if Fresh then
        WalkDescendants(pIndex, pDia, Desc, pDepth - 1, pCap);
    end;
  finally
    Rows.Free;
  end;
end;

// The focus's has-a links: one edge per (field, type) pair where the type is an indexed class, interface or record.
procedure CollectFields(const pIndex: TChartsIndex; const pDia: TDiagram; const pFocus: TTypeNode; pCap: Integer);
begin
  var Rows:= pIndex.Query(
    'SELECT DISTINCT fl.name AS fname, fl.start_line AS fline, fl.start_col AS fcol, t.id AS id, t.name AS name,' + sLineBreak +
    '       t.kind AS kind, t.start_line AS start_line, tf.path AS path' + sLineBreak +
    '  FROM symbols fl' + sLineBreak +
    '  JOIN refs r ON r.file_id = fl.file_id AND r.kind = ''type_use'' AND r.start_line = fl.start_line' + sLineBreak +
    '              AND r.symbol_id IS NOT NULL' + sLineBreak +
    '  JOIN symbols t ON t.id = r.symbol_id AND t.kind IN (''class'', ''interface'', ''record'')' + sLineBreak +
    '  JOIN files tf ON tf.id = t.file_id' + sLineBreak +
    ' WHERE fl.parent_id = ' + pFocus.Id.ToString + ' AND fl.kind = ''field''' + sLineBreak +
    ' ORDER BY fl.start_line, fl.start_col, fl.name, t.id');
  try
    for var R in Rows do
    begin
      var Typ:= TypeNodeOf(R, FIELD_FILL);
      if pDia.Has(Typ) or (pDia.Nodes.Count < pCap) then
      begin
        pDia.Add(Typ);
        pDia.FieldEdges.Add(EdgeText(NodeKey(pFocus), NodeKey(Typ),
          Format('dir=both, arrowtail=odiamond, arrowhead=vee, color="%s", label="%s", fontsize=11',
            [LINE_INK, XmlText(R.S('fname'))])));
      end;
    end;
  finally
    Rows.Free;
  end;
end;

procedure AppendNode(const pSb: TStringBuilder; const pNode: TTypeNode; pFocus: Boolean);
begin
  var Pen:= if pFocus then FOCUS_PEN else 1;
  var Url:= '';
  if pNode.Path <> '' then
    Url:= Format(', URL="%s", tooltip="%s:%d"', [RowHref(pNode.Path, pNode.Line), XmlText(FileNameOf(pNode.Path)), pNode.Line]);
  pSb.AppendLine(Format('  %s [shape=box, style="rounded,filled", fillcolor="%s", penwidth=%d, label="%s\n(%s)"%s];',
    [NodeKey(pNode), pNode.Fill, Pen, XmlText(pNode.Name), XmlText(pNode.Kind), Url]));
end;

/// <summary>Answers `class-diagram` for pArgs.Target: the type, its ancestors, descendants and field-type classes.</summary>
/// <param name="pArgs">The question arguments; Target is a class, interface or record name (qualified or bare); Cap bounds the node count, Depth the two walks.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = classes drawn, RightCount = relations drawn.</returns>
/// <exception cref="EChartsIndex">The name is not in the index, ambiguous, or not a class, interface or record.</exception>
/// <remarks>Read-only. Meta fields: Resolved, Classes, AncestorEdges, DescendantEdges, FieldEdges, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Dia:= TDiagram.Create;
  try
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['class', 'interface', 'record'], False,
      'name a class, interface or record', Found);
    var Focus:= Default(TTypeNode);
    Focus.Id:= Sel.Id;
    Focus.Name:= Sel.Name;
    Focus.Kind:= Sel.Kind;
    Focus.Path:= Sel.Path;
    Focus.Line:= Sel.DeclLine;
    Focus.Fill:= FOCUS_FILL;
    Dia.Add(Focus);
    var MaxDepth:= if pArgs.Depth > 0 then pArgs.Depth else DEFAULT_DEPTH;
    var MaxNodes:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    WalkAncestors(Index, Dia, Focus, MaxDepth, MaxNodes);
    WalkDescendants(Index, Dia, Focus, MaxDepth, MaxNodes);
    CollectFields(Index, Dia, Focus, MaxNodes);

    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph class_diagram {');
      Sb.AppendLine('  rankdir=BT; bgcolor="transparent"; nodesep=0.5; ranksep=0.9;');
      Sb.AppendLine('  node [fontname="Consolas", fontsize=13];');
      Sb.AppendLine('  edge [fontname="Consolas", arrowsize=0.8];');
      for var N in Dia.Nodes do
        AppendNode(Sb, N, N.Id = Focus.Id);
      for var E in Dia.AncEdges do
        Sb.AppendLine(E);
      for var E in Dia.DescEdges do
        Sb.AppendLine(E);
      for var E in Dia.FieldEdges do
        Sb.AppendLine(E);
      Sb.AppendLine('}');
      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_') + '_class_diagram';
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
    finally
      Sb.Free;
    end;

    var Expected:= 0;
    for var N in Dia.Nodes do
      if N.Path <> '' then
        Inc(Expected);
    Result.LeftCount:= Dia.Nodes.Count;
    Result.RightCount:= Dia.AncEdges.Count + Dia.DescEdges.Count + Dia.FieldEdges.Count;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Str('Resolved', Sel.QName), TMetaField.Int('Classes', Dia.Nodes.Count),
      TMetaField.Int('AncestorEdges', Dia.AncEdges.Count), TMetaField.Int('DescendantEdges', Dia.DescEdges.Count),
      TMetaField.Int('FieldEdges', Dia.FieldEdges.Count), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Dia.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CLASS_DIAGRAM_ID, Emit);

end.
