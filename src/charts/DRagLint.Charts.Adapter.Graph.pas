unit DRagLint.Charts.Adapter.Graph;

{ The chart-graph adapter of `drag-lint compare` (spec 6a, D5-D8): the graph.dot a
  dl-charts bundle holds (an HTML-table DOT the report emitters write, one node
  statement per box, one `<TD>` cell per routine) becomes a SET of nodes and edges
  keyed by identity -- never by drawing position, row order or the :line suffix.

  DOT node identity. For each
    <TD ... PORT="pN" ... HREF="draglint://open?file=F&amp;line=L" TITLE="T">...</TD>
  the identity is the part of T before ' -- ' when T has one, else T itself when it has
  no space, else the text of the FIRST <FONT> in the cell (entities decoded, tags
  stripped, trimmed). Only a cell with an HREF is a node; a header cell or a
  '+6 more routines' cell is not. The node statement's id (`nw`, `focus`) maps each
  port `nid:pN` to that identity; a node statement whose label has HREF cells but no
  PORT (the focus box) maps `nid` to its first such identity; a node with no HREF
  cells maps to its id. Edge statements `A[:pN] -> B[:pM] [...]` resolve through that
  map (an unknown port or a bare id with no single identity falls back to the id
  itself, so a hand-written edge is still compared, just under its DOT name).

  Item keys are ordinal: the emitter prints qualified names exactly as the index stores
  them. PS trap handled: PowerShell hashtable keys, -eq and Sort-Object are
  case-insensitive; every dictionary here uses TStringComparer.Ordinal and every sort
  string.CompareOrdinal, so two routines differing only by case stay two nodes.

  Pure string work apart from LoadGraphSource, which reads two files. }

interface

uses
  System.Generics.Collections, DRagLint.Charts.Diff;

type
  /// <summary>One node of the chart: a routine, a field, a table...</summary>
  TGraphNode = record
    /// <summary>The identity key (see the unit header); equal Ids are one node.</summary>
    Id   : string;
    /// <summary>The decoded TITLE of the cell the node came from; '' for a bare DOT id.</summary>
    Title: string;
    /// <summary>The decoded HREF of the cell the node came from; '' for a bare DOT id.</summary>
    Href : string;
  end;

  /// <summary>One edge, as the identities of its ends.</summary>
  TGraphEdge = record
    /// <summary>Identity of the edge's source.</summary>
    FromId: string;
    /// <summary>Identity of the edge's target.</summary>
    ToId  : string;
  end;

  /// <summary>A parsed chart.</summary>
  TGraphModel = record
    /// <summary>Distinct nodes, in order of first appearance.</summary>
    Nodes   : TArray<TGraphNode>;
    /// <summary>Distinct edges, in order of first appearance.</summary>
    Edges   : TArray<TGraphEdge>;
    /// <summary>'nw:p3' -> identity, for marking the chart's SVG (spec D7).</summary>
    PortToId: TArray<TPair<string, string>>;
  end;

/// <summary>Parses a chart's DOT text into nodes, edges and the port map.</summary>
/// <param name="pDotText">The whole graph.dot; single-line HTML labels as the emitters
/// write them; CRLF or LF line ends.</param>
/// <returns>The model. Text that is not such a DOT gives an empty model, never an
/// exception.</returns>
/// <remarks>Duplicate nodes and edges (same identity) collapse into one: a chart is a
/// set. Pure; thread-safe.</remarks>
function ParseDot(const pDotText: string): TGraphModel;

/// <summary>A chart as diff items.</summary>
/// <param name="pModel">A parsed chart.</param>
/// <returns>'N &lt;id&gt;' for every node and 'E &lt;from&gt; -&gt; &lt;to&gt;' for every
/// edge; Key = Text; sorted by Key ordinally, so the drawing order never matters.</returns>
function GraphItems(const pModel: TGraphModel): TArray<TDiffItem>;

/// <summary>Finds a chart's DOT text and its SVG.</summary>
/// <param name="pPath">A .dot file, or a bundle folder holding graph.dot (and graph.svg).</param>
/// <param name="pDotText">Receives the DOT text; '' when not found.</param>
/// <param name="pSvgPath">Receives the SVG that goes with the DOT (the folder's graph.svg,
/// or the .dot's sibling with the extension .svg); '' when there is none.</param>
/// <returns>True when the DOT text was read.</returns>
function LoadGraphSource(const pPath: string; out pDotText, pSvgPath: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Defaults, System.Character;

const
  NODE_PREFIX = 'N ';
  EDGE_PREFIX = 'E ';
  EDGE_ARROW = ' -> ';
  TITLE_SEP = ' -- ';
  PORT_SEP = ':';
  BUNDLE_DOT = 'graph.dot';
  BUNDLE_SVG = 'graph.svg';
  EXT_DOT = '.dot';
  EXT_SVG = '.svg';
  RE_NODE = '^\s*(\w+)\s*\[label=<(.*)>\];';
  RE_CELL = '<TD([^>]*)>(.*?)</TD>';
  RE_PORT = '\bPORT="([^"]*)"';
  RE_HREF = '\bHREF="([^"]*)"';
  RE_TITLE = '\bTITLE="([^"]*)"';
  RE_FONT = '<FONT[^>]*>(.*?)</FONT>';
  RE_TAG = '<[^>]*>';
  RE_EDGE = '^\s*(\w+)(?::(\w+))?\s*->\s*(\w+)(?::(\w+))?';
  RE_ENTITY = '&(#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);';
  HEX_BASE = '$';
  ENT_HEX = 'x';
  ENT_KIND_AT = 2;
  ENT_HEX_FROM = 3;
  MAX_CODE_POINT = $10FFFF;
  G_FROM_PORT = 2;
  G_TO_ID = 3;
  G_TO_PORT = 4;

type
  TAddNodeProc = reference to procedure(const pId, pTitle, pHref: string);
  TResolveFunc = reference to function(const pNid, pPort: string): string;

function AttrOf(const pAttrs, pPattern: string): string;
begin
  var M:= TRegEx.Match(pAttrs, pPattern);
  if M.Success then Result:= M.Groups[1].Value
  else Result:= '';
end;

{ A trailing optional group that did not take part is absent from Groups, not empty. }
function GroupOf(const pMatch: TMatch; pIndex: Integer): string;
begin
  if pIndex < pMatch.Groups.Count then Result:= pMatch.Groups[pIndex].Value
  else Result:= '';
end;

function EntityValue(const pMatch: TMatch): string;
begin
  var Name:= pMatch.Groups[1].Value;
  if Name = 'amp' then Exit('&');
  if Name = 'lt' then Exit('<');
  if Name = 'gt' then Exit('>');
  if Name = 'quot' then Exit('"');
  if Name = 'apos' then Exit('''');
  var Code: Integer;
  if (Length(Name) > 1) and (Name[ENT_KIND_AT] = ENT_HEX) then Code:= StrToIntDef(HEX_BASE + Copy(Name, ENT_HEX_FROM, MaxInt), -1)
  else Code:= StrToIntDef(Copy(Name, 2, MaxInt), -1);
  if (Code > 0) and (Code <= MAX_CODE_POINT) then Result:= Char.ConvertFromUtf32(Code)
  else Result:= pMatch.Value;
end;

function DecodeEntities(const pText: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    var Last:= 1;
    for var M in TRegEx.Matches(pText, RE_ENTITY) do
    begin
      SB.Append(Copy(pText, Last, M.Index - Last)).Append(EntityValue(M));
      Last:= M.Index + M.Length;
    end;
    SB.Append(Copy(pText, Last, MaxInt));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function PlainText(const pMarkup: string): string;
begin
  Result:= Trim(DecodeEntities(TRegEx.Replace(pMarkup, RE_TAG, '')));
end;

{ The identity rule of the unit header. }
function IdentityOf(const pTitle, pCellMarkup: string): string;
begin
  var SepAt:= Pos(TITLE_SEP, pTitle);
  if SepAt > 0 then Exit(Trim(Copy(pTitle, 1, SepAt - 1)));
  if (pTitle <> '') and (Pos(' ', pTitle) = 0) then Exit(pTitle);
  var Font:= TRegEx.Match(pCellMarkup, RE_FONT, [roSingleLine]);
  if Font.Success then Result:= PlainText(Font.Groups[1].Value)
  else Result:= PlainText(pCellMarkup);
end;

function ParseDot(const pDotText: string): TGraphModel;
begin
  var NodeIds:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var EdgeIds:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var Defaults:= TDictionary<string, string>.Create(TStringComparer.Ordinal);
  var Ports:= TList<TPair<string, string>>.Create;
  var PortSeen:= TDictionary<string, Boolean>.Create(TStringComparer.Ordinal);
  var Nodes:= TList<TGraphNode>.Create;
  var Edges:= TList<TGraphEdge>.Create;
  try
    var AddNode: TAddNodeProc;
    AddNode:=
      procedure(const pId, pTitle, pHref: string)
      begin
        if NodeIds.ContainsKey(pId) then Exit;
        NodeIds.Add(pId, True);
        var N: TGraphNode;
        N.Id:= pId;
        N.Title:= pTitle;
        N.Href:= pHref;
        Nodes.Add(N);
      end;
    var Lines:= pDotText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    // pass 1: node statements, so an edge that comes before its node still resolves
    for var Line in Lines do
    begin
      var NM:= TRegEx.Match(Line, RE_NODE);
      if not NM.Success then Continue;
      var Nid:= NM.Groups[1].Value;
      var HrefCells:= 0;
      for var CM in TRegEx.Matches(NM.Groups[2].Value, RE_CELL, [roSingleLine]) do
      begin
        var Href:= AttrOf(CM.Groups[1].Value, RE_HREF);
        if Href = '' then Continue;
        Inc(HrefCells);
        var Title:= DecodeEntities(AttrOf(CM.Groups[1].Value, RE_TITLE));
        var Id:= IdentityOf(Title, CM.Groups[2].Value);
        AddNode(Id, Title, DecodeEntities(Href));
        var Port:= AttrOf(CM.Groups[1].Value, RE_PORT);
        if Port <> '' then
        begin
          var Key:= Nid + PORT_SEP + Port;
          if not PortSeen.ContainsKey(Key) then
          begin
            PortSeen.Add(Key, True);
            Ports.Add(TPair<string, string>.Create(Key, Id));
          end;
        end
        else if not Defaults.ContainsKey(Nid) then
          Defaults.Add(Nid, Id);
      end;
      if HrefCells = 0 then
        AddNode(Nid, '', '');
    end;
    // pass 2: edges
    var Resolve: TResolveFunc;
    Resolve:=
      function(const pNid, pPort: string): string
      begin
        if pPort <> '' then
          for var P in Ports do
            if (string.CompareOrdinal(P.Key, pNid + PORT_SEP + pPort) = 0) then Exit(P.Value);
        if not Defaults.TryGetValue(pNid, Result) then Result:= pNid;
      end;
    for var Line in Lines do
    begin
      if TRegEx.IsMatch(Line, RE_NODE) then Continue;
      var EM:= TRegEx.Match(Line, RE_EDGE);
      if not EM.Success then Continue;
      var FromId:= Resolve(EM.Groups[1].Value, GroupOf(EM, G_FROM_PORT));
      var ToId:= Resolve(EM.Groups[G_TO_ID].Value, GroupOf(EM, G_TO_PORT));
      var Key:= FromId + EDGE_ARROW + ToId;
      if EdgeIds.ContainsKey(Key) then Continue;
      EdgeIds.Add(Key, True);
      AddNode(FromId, '', '');
      AddNode(ToId, '', '');
      var E: TGraphEdge;
      E.FromId:= FromId;
      E.ToId:= ToId;
      Edges.Add(E);
    end;
    Result.Nodes:= Nodes.ToArray;
    Result.Edges:= Edges.ToArray;
    Result.PortToId:= Ports.ToArray;
  finally
    Edges.Free;
    Nodes.Free;
    PortSeen.Free;
    Ports.Free;
    Defaults.Free;
    EdgeIds.Free;
    NodeIds.Free;
  end;
end;

function GraphItems(const pModel: TGraphModel): TArray<TDiffItem>;
begin
  var Items:= TList<TDiffItem>.Create;
  try
    for var N in pModel.Nodes do
    begin
      var Text:= NODE_PREFIX + N.Id;
      Items.Add(TDiffItem.Make(Text, Text));
    end;
    for var E in pModel.Edges do
    begin
      var Text:= EDGE_PREFIX + E.FromId + EDGE_ARROW + E.ToId;
      Items.Add(TDiffItem.Make(Text, Text));
    end;
    Items.Sort(TComparer<TDiffItem>.Construct(
      function(const pLeft, pRight: TDiffItem): Integer
      begin
        Result:= string.CompareOrdinal(pLeft.Key, pRight.Key);
      end));
    Result:= Items.ToArray;
  finally
    Items.Free;
  end;
end;

function LoadGraphSource(const pPath: string; out pDotText, pSvgPath: string): Boolean;
begin
  pDotText:= '';
  pSvgPath:= '';
  var DotPath:= '';
  var SvgPath:= '';
  if TDirectory.Exists(pPath) then
  begin
    DotPath:= TPath.Combine(pPath, BUNDLE_DOT);
    SvgPath:= TPath.Combine(pPath, BUNDLE_SVG);
  end
  else if TFile.Exists(pPath) and SameText(ExtractFileExt(pPath), EXT_DOT) then
  begin
    DotPath:= pPath;
    SvgPath:= ChangeFileExt(pPath, EXT_SVG);
  end;
  Result:= (DotPath <> '') and TFile.Exists(DotPath);
  if not Result then Exit;
  pDotText:= TFile.ReadAllText(DotPath);
  if TFile.Exists(SvgPath) then pSvgPath:= SvgPath;
end;

end.
