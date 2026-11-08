unit DRagLint.Charts.ArchDiagram;

(* E-PARITY-ARCHIFY phase 1: `drag-lint arch-diagram`, one self-contained HTML layer diagram of a
  project's units by folder. Design: docs\superpowers\specs\2026-11-06-archify-layer-diagrams.md.

  Zones and edges are those of the `architecture` question (DRagLint.Charts.Q.Architecture): source
  folders below the common root, unit_uses.target_file_id, the smaller direction of a pair is a
  back-edge and is never called a violation. What this unit adds is the ORDER: the index declares no
  layers, so they are measured here, and a drawing that needs no Graphviz.

  No timestamp is written: the same DB gives the same bytes. *)

interface

uses
  System.SysUtils;

const
  /// <summary>The value of the `schema` key of the model, in --json and in the page.</summary>
  ARCH_SCHEMA = 'drag-lint.arch/1';

type
  /// <summary>The index holds nothing to draw.</summary>
  EArchDiagram = class(Exception);

  /// <summary>One unit of a zone.</summary>
  TArchUnit = record
    /// <summary>The unit's qualified name.</summary>
    Name: string;
    /// <summary>The file, relative to the model's Root, with forward slashes.</summary>
    Path: string;
    /// <summary>The line of the unit declaration.</summary>
    Line: Integer;
    /// <summary>How many resolved `uses` entries point at this file.</summary>
    UsedBy: Integer;
  end;

  /// <summary>One source folder, with its measured place in the drawing.</summary>
  TArchZone = record
    /// <summary>The folder below the root, as PathZone gives it.</summary>
    Name: string;
    /// <summary>0 = the foundation, drawn at the bottom. Zones of one tangle share a layer.</summary>
    Layer: Integer;
    /// <summary>The position inside the layer's row, from the left, from 0.</summary>
    Order: Integer;
    /// <summary>`uses` entries between two units of this zone; not drawn.</summary>
    InternalUses: Integer;
    /// <summary>The units, most used first, then by name.</summary>
    Units: TArray<TArchUnit>;
  end;

  /// <summary>What an arrow means. Back: the smaller direction of a pair used both ways. Tangle: inside
  /// a cycle of forward arrows, so both ends share a layer. Forward: everything else.</summary>
  TArchEdgeKind = (aekForward, aekBack, aekTangle);

  /// <summary>One `uses` entry behind an arrow: the evidence.</summary>
  TArchUsesPair = record
    /// <summary>The using unit.</summary>
    FromUnit: string;
    /// <summary>The used unit.</summary>
    ToUnit: string;
    /// <summary>The using file, relative to the model's Root.</summary>
    Path: string;
    /// <summary>The line of the entry in that file.</summary>
    Line: Integer;
    /// <summary>interface, implementation, program or package.</summary>
    Section: string;
  end;

  /// <summary>One arrow: zone FromZone uses zone ToZone, FromZone &lt;&gt; ToZone.</summary>
  TArchEdge = record
    /// <summary>The using zone.</summary>
    FromZone: string;
    /// <summary>The used zone.</summary>
    ToZone: string;
    /// <summary>The number of `uses` entries; always the length of Pairs.</summary>
    Weight: Integer;
    /// <summary>How many of them sit in an interface section.</summary>
    InterfaceUses: Integer;
    /// <summary>What the arrow means.</summary>
    Kind: TArchEdgeKind;
    /// <summary>A forward arrow that a longer forward path also implies. Drawn faint, shown when its folder is picked: it adds no layer information.</summary>
    Implied: Boolean;
    /// <summary>The entries, in id order.</summary>
    Pairs: TArray<TArchUsesPair>;
  end;

  /// <summary>The whole diagram. Same DB, same model; nothing in it depends on the clock.</summary>
  TArchModel = record
    /// <summary>The DB's file name, without its folder.</summary>
    DbName: string;
    /// <summary>The common root of the unit folders; empty when the units share none.</summary>
    Root: string;
    /// <summary>schema_meta.indexer_fingerprint; empty on a DB without one.</summary>
    Fingerprint: string;
    /// <summary>How many unit symbols are drawn.</summary>
    UnitCount: Integer;
    /// <summary>`uses` entries with no target in the index: externals, not drawn.</summary>
    ExternalUses: Integer;
    /// <summary>Highest layer + 1.</summary>
    LayerCount: Integer;
    /// <summary>By layer, highest first, then by Order: reading order of the drawing.</summary>
    Zones: TArray<TArchZone>;
    /// <summary>By zone order of the sort before layering, from then to.</summary>
    Edges: TArray<TArchEdge>;
  end;

/// <summary>Reads the units and their resolved `uses` from an index and measures the layers.</summary>
/// <param name="pDbPath">The index; opened read-only. Must exist: the caller checks.</param>
/// <returns>The model.</returns>
/// <exception cref="EArchDiagram">The index holds no unit symbols.</exception>
/// <remarks>Layer = longest forward path down to a zone that uses nothing, over the strongly connected
/// components of the forward arrows. Inside a row: two barycentre sweeps, ties by name.</remarks>
function BuildArchModel(const pDbPath: string): TArchModel;

/// <summary>The model as JSON, the text the page embeds apart from its `&lt;` escape.</summary>
/// <param name="pModel">The model.</param>
/// <returns>A `drag-lint.arch/1` document. Every edge has `from`, `to` and `weight`, the keys of a
/// `drag-lint.graph/1` edge.</returns>
function ArchModelJson(const pModel: TArchModel): string;

/// <summary>The model as one HTML page: inline CSS, SVG and script, nothing fetched.</summary>
/// <param name="pModel">The model.</param>
/// <returns>The page. All model text is HTML-escaped; the embedded JSON writes `&lt;` as <.</returns>
/// <remarks>Without script the drawing and its tooltips still show; only the click panel needs it.</remarks>
function ArchDiagramHtml(const pModel: TArchModel): string;

implementation

uses
  System.Classes, System.Types, System.Math, System.JSON, System.NetEncoding,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- TChartsIndex is the charts' read-only SQL route; the same zones and edges as the architecture question come from it
  DRagLint.Charts.Text;

const
  CRLF = #13#10;
  META_KEY_FINGERPRINT = 'indexer_fingerprint';
  BARYCENTRE_SWEEPS = 2;
  ROW_CENTRE = 0.5;
  TOP_FIRST = 0;
  KIND_TEXT: array[TArchEdgeKind] of string = ('forward', 'back', 'tangle');

  { geometry of the drawing, in SVG units }
  BOX_W = 260;
  BOX_HEADER = 40;
  BOX_LINE = 15;
  BOX_PAD = 8;
  MAX_UNITS_SHOWN = 6;
  NAME_CHARS = 38;
  ELLIPSIS = '...';
  GAP_X = 36;
  GAP_Y = 96;
  MARGIN_TOP = 16;
  MARGIN_LEFT = 76;
  MARGIN_RIGHT = 24;
  HALF = 2;
  CURVE_SAME_ROW = 64;
  PORT_INSET = 24;
  PORT_SPREAD = 700;
  PORT_REACH = 1.0;
  CURVE_LABEL_DROP = 48;
  STROKE_MIN = 1;
  STROKE_MAX = 6;
  LABEL_DROP = 4;
  LABEL_MIN_ROW = 16;
  LAYER_LABEL_X = 8;
  LAYER_LABEL_DY = 20;
  TEXT_HEADER_DY = 17;
  TEXT_COUNT_DY = 32;
  TEXT_UNIT_DY = 4;
  ARROW_SIZE = 7;

  PAGE_STYLE =
    ':root{--bg:#fff;--ink:#1f2933;--muted:#5b6673;--band:#f6f7f9;--zone:#edf2ff;--zoneb:#3b5bdb;--edge:#8a94a6;--back:#b02a37;--tangle:#b45309}' + CRLF +
    '@media (prefers-color-scheme:dark){:root{--bg:#14171c;--ink:#e6e9ee;--muted:#9aa5b1;--band:#1b1f26;--zone:#1d2740;--zoneb:#7c93f0;--edge:#7b8696;--back:#f0808a;--tangle:#e9a15a}}' + CRLF +
    'body{margin:0;background:var(--bg);color:var(--ink);font:13px "Segoe UI",system-ui,sans-serif}' + CRLF +
    'header{padding:12px 16px;border-bottom:1px solid var(--band)}h1{font-size:17px;margin:0 0 4px}header p{margin:2px 0;color:var(--muted)}' + CRLF +
    '.key span{margin-right:16px;white-space:nowrap}.key svg{vertical-align:middle;margin-right:4px}' + CRLF +
    'main{display:flex;align-items:flex-start}#w{flex:1;overflow:auto;min-width:0}' + CRLF +
    '#panel{width:380px;flex:none;box-sizing:border-box;padding:12px 16px;border-left:1px solid var(--band);max-height:100vh;overflow:auto;position:sticky;top:0}' + CRLF +
    '#panel h2{font-size:15px;margin:0 0 6px;overflow-wrap:anywhere}#panel h3{font-size:13px;margin:12px 0 4px}#panel ul{margin:0;padding:0;list-style:none}' + CRLF +
    '#panel li{padding:2px 0;font:12px Consolas,monospace;overflow-wrap:anywhere}#panel p{color:var(--muted);margin:4px 0}#panel a{color:var(--zoneb);cursor:pointer;text-decoration:underline}' + CRLF +
    '.band{fill:var(--band)}.lay{fill:var(--muted);font-size:11px}' + CRLF +
    '.zone{cursor:pointer}.zone rect{fill:var(--zone);stroke:var(--zoneb);stroke-width:1.5}.zone:hover rect,.zone:focus rect,.zone.sel rect{stroke-width:3}.zone:focus{outline:none}' + CRLF +
    '.zn{fill:var(--ink);font-weight:600;font-size:13px}.zc{fill:var(--muted);font-size:11px}.zu{fill:var(--ink);font:11px Consolas,monospace}' + CRLF +
    '.edge{cursor:pointer}.edge path{fill:none}.edge .hit{stroke:transparent;stroke-width:12}.edge.forward .ln{stroke:var(--edge)}.edge.back .ln{stroke:var(--back);stroke-dasharray:6 4}.edge.tangle .ln{stroke:var(--tangle);stroke-dasharray:2 3}' + CRLF +
    '.edge text{fill:var(--ink);font-size:11px;paint-order:stroke;stroke:var(--bg);stroke-width:3px;text-anchor:middle}.edge:hover .ln{stroke-width:4px}' + CRLF +
    '.edge.implied{opacity:.14}.edge.implied text{display:none}.edge.implied.on,.edge.implied:hover{opacity:1}.edge.implied.on text,.edge.implied:hover text{display:inline}.edge.dim{opacity:.06}' + CRLF +
    '.mk-forward{fill:var(--edge)}.mk-back{fill:var(--back)}.mk-tangle{fill:var(--tangle)}';

  PAGE_SCRIPT =
    'var M=JSON.parse(document.getElementById("graph").textContent);' + CRLF +
    'var P=document.getElementById("panel");var S=P.innerHTML;' + CRLF +
    'function add(p,t,x){var e=document.createElement(t);if(x!==undefined)e.textContent=x;p.appendChild(e);return e;}' + CRLF +
    'function mark(f,g){document.querySelectorAll("#d .edge").forEach(function(n){var h=!!f&&f(M.edges[+n.dataset.e]);n.classList.toggle("dim",!!f&&!h);n.classList.toggle("on",h);});' + CRLF +
    ' document.querySelectorAll("#d .zone").forEach(function(n){n.classList.toggle("sel",g===M.zones[+n.dataset.z].name);});}' + CRLF +
    'function arrows(name,word,list){if(!list.length)return;add(P,"h3",word);var u=add(P,"ul");list.forEach(function(k){var e=M.edges[k];var a=add(add(u,"li"),"a",(name===e.from?e.to:e.from)+" ("+e.weight+(e.kind==="forward"?"":", "+e.kind)+")");a.onclick=function(){edge(k);};});}' + CRLF +
    'function zone(i){var z=M.zones[i],o=[],n=[];M.edges.forEach(function(e,k){if(e.from===z.name)o.push(k);if(e.to===z.name)n.push(k);});P.textContent="";add(P,"h2",z.name);' + CRLF +
    ' add(P,"p",z.units.length+(z.units.length===1?" unit":" units")+", layer "+z.layer+", "+z.internal+" uses inside the folder");arrows(z.name,"Uses",o);arrows(z.name,"Used by",n);add(P,"h3","Units (most used first)");var u=add(P,"ul");' + CRLF +
    ' z.units.forEach(function(x){add(u,"li",x.name+" - "+x.path+":"+x.line+" - used by "+x.usedBy);});mark(function(e){return e.from===z.name||e.to===z.name;},z.name);}' + CRLF +
    'var W={forward:"Forward: the larger direction of its pair, or the only one.",back:"Back-edge: the smaller direction of a pair used both ways. A measurement, not a violation: the index declares no layer order.",tangle:"Tangle: inside a cycle of forward arrows, so both folders share a layer."};' + CRLF +
    'function edge(k){var e=M.edges[k];P.textContent="";add(P,"h2",e.from+" -> "+e.to);add(P,"p",W[e.kind]);add(P,"p",e.weight+" uses entries, "+e.interface+" in an interface section."+(e.implied?" A longer forward path implies this arrow, so it is drawn faint.":""));var u=add(P,"ul");' + CRLF +
    ' e.pairs.forEach(function(x){add(u,"li",x.from+" uses "+x.to+" - "+x.path+":"+x.line+" ("+x.section+")");});mark(function(c){return c===e;},null);}' + CRLF +
    'function pick(t){var g=t.closest("[data-z],[data-e]");if(!g){P.innerHTML=S;mark(null,null);}else if(g.dataset.z!==undefined)zone(+g.dataset.z);else edge(+g.dataset.e);}' + CRLF +
    'var D=document.getElementById("d");D.addEventListener("click",function(v){pick(v.target);});' + CRLF +
    'D.addEventListener("keydown",function(v){if(v.key==="Enter")pick(v.target);});';

type
  { Strongly connected components (Tarjan) of the forward arrows, the layer of each, and the row order.
    Tarjan closes a component only after every component it reaches, so a layer can be computed at
    the close. Zone count is folders, so O(n^2) over the matrix is cheap. }
  TLayering = class
  private
    FN: Integer;
    FWeight: TArray<TArray<Integer>>;
    FBack: TArray<TArray<Boolean>>;
    FDfs: TArray<Integer>;
    FLow: TArray<Integer>;
    FComp: TArray<Integer>;
    FOnStack: TArray<Boolean>;
    FStack: TStack<Integer>;
    FNextDfs: Integer;
    FCompCount: Integer;
    function IsForward(pFrom, pTo: Integer): Boolean;
    procedure MarkBackEdges;
    procedure Visit(pZone: Integer);
    procedure CloseComponent(pRoot: Integer);
    function RowZones(pLayer: Integer): TArray<Integer>;
    procedure SweepRow(pLayer: Integer);
  public
    Layer: TArray<Integer>; // dl:ok public-field@4fc7 -- the class is private to this implementation section; BuildArchModel reads the result once
    Order: TArray<Integer>; // dl:ok public-field@298c -- the class is private to this implementation section; BuildArchModel reads the result once
    LayerCount: Integer; // dl:ok public-field@26ac -- the class is private to this implementation section; BuildArchModel reads the result once
    Names: TArray<string>; // dl:ok public-field@b3bf -- the class is private to this implementation section; BuildArchModel reads the result once
    constructor Create(const pNames: TArray<string>; const pWeight: TArray<TArray<Integer>>);
    destructor Destroy; override;
    procedure Run;
    function KindOf(pFrom, pTo: Integer): TArchEdgeKind;
    function IsImplied(pFrom, pTo: Integer): Boolean;
  end;

constructor TLayering.Create(const pNames: TArray<string>; const pWeight: TArray<TArray<Integer>>);
begin
  inherited Create;
  Names:= pNames;
  FWeight:= pWeight;
  FN:= Length(pNames);
  FStack:= TStack<Integer>.Create;
  SetLength(FBack, FN, FN);
  SetLength(FDfs, FN);
  SetLength(FLow, FN);
  SetLength(FComp, FN);
  SetLength(FOnStack, FN);
  SetLength(Layer, FN);
  SetLength(Order, FN);
  for var I:= 0 to FN - 1 do
    FDfs[I]:= -1;
end;

destructor TLayering.Destroy;
begin
  FStack.Free;
  inherited Destroy;
end;

function TLayering.IsForward(pFrom, pTo: Integer): Boolean;
begin
  Result:= (pFrom <> pTo) and (FWeight[pFrom][pTo] > 0) and not FBack[pFrom][pTo];
end;

// the rule of the architecture question: zones are in (units desc, name) order, so on a tie the
// second zone is the source of the back-edge
procedure TLayering.MarkBackEdges;
begin
  for var I:= 0 to FN - 1 do
    for var J:= I + 1 to FN - 1 do
      if (FWeight[I][J] > 0) and (FWeight[J][I] > 0) then
        if FWeight[I][J] >= FWeight[J][I] then
          FBack[J][I]:= True
        else
          FBack[I][J]:= True;
end;

procedure TLayering.CloseComponent(pRoot: Integer);
begin
  var Members: TArray<Integer>:= [];
  var Member:= -1;
  while Member <> pRoot do
  begin
    Member:= FStack.Pop;
    FOnStack[Member]:= False;
    FComp[Member]:= FCompCount;
    Members:= Members + [Member];
  end;
  var Level:= 0;
  for var M in Members do
    for var T:= 0 to FN - 1 do
      if IsForward(M, T) and (FComp[T] <> FCompCount) then
        Level:= Max(Level, Layer[T] + 1);
  for var M in Members do
    Layer[M]:= Level;
  LayerCount:= Max(LayerCount, Level + 1);
  Inc(FCompCount);
end;

procedure TLayering.Visit(pZone: Integer);
begin
  FDfs[pZone]:= FNextDfs;
  FLow[pZone]:= FNextDfs;
  Inc(FNextDfs);
  FStack.Push(pZone);
  FOnStack[pZone]:= True;
  for var T:= 0 to FN - 1 do
    if IsForward(pZone, T) then
      if FDfs[T] < 0 then
      begin
        Visit(T);
        FLow[pZone]:= Min(FLow[pZone], FLow[T]);
      end
      else if FOnStack[T] then
        FLow[pZone]:= Min(FLow[pZone], FDfs[T]);
  if FLow[pZone] = FDfs[pZone] then
    CloseComponent(pZone);
end;

function TLayering.RowZones(pLayer: Integer): TArray<Integer>;
begin
  Result:= [];
  for var I:= 0 to FN - 1 do
    if Layer[I] = pLayer then
      Result:= Result + [I];
end;

// one barycentre step for a row: each zone moves to the mean position of its neighbours in other rows
procedure TLayering.SweepRow(pLayer: Integer);
begin
  var Row:= RowZones(pLayer);
  var Bary: TArray<Double>;
  SetLength(Bary, FN);
  for var Z in Row do
  begin
    var Sum: Double:= 0;
    var Count:= 0;
    for var T:= 0 to FN - 1 do
      if (Layer[T] <> pLayer) and ((FWeight[Z][T] > 0) or (FWeight[T][Z] > 0)) then
      begin
        Sum:= Sum + (Order[T] + ROW_CENTRE) / Length(RowZones(Layer[T]));
        Inc(Count);
      end;
    Bary[Z]:= if Count > 0 then Sum / Count else (Order[Z] + ROW_CENTRE) / Length(Row);
  end;
  var LocalNames:= Names;
  TArray.Sort<Integer>(Row, TComparer<Integer>.Construct(
    function(const pA, pB: Integer): Integer
    begin
      Result:= CompareValue(Bary[pA], Bary[pB]);
      if Result = 0 then
        Result:= CompareText(LocalNames[pA], LocalNames[pB]);
    end));
  for var I:= 0 to High(Row) do
    Order[Row[I]]:= I;
end;

procedure TLayering.Run;
begin
  MarkBackEdges;
  for var I:= 0 to FN - 1 do
    if FDfs[I] < 0 then
      Visit(I);
  for var L:= 0 to LayerCount - 1 do
  begin
    var Row:= RowZones(L);
    for var I:= 0 to High(Row) do
      Order[Row[I]]:= I;
  end;
  for var Sweep:= 1 to BARYCENTRE_SWEEPS do
    for var L:= 0 to LayerCount - 1 do
      SweepRow(if Odd(Sweep) then LayerCount - 1 - L else L);
end;

function TLayering.KindOf(pFrom, pTo: Integer): TArchEdgeKind;
begin
  Result:= if FBack[pFrom][pTo] then aekBack else if FComp[pFrom] = FComp[pTo] then aekTangle else aekForward;

end;

// is there a forward path pFrom .. pTo other than the arrow itself? Zone count is folders: cheap.
function TLayering.IsImplied(pFrom, pTo: Integer): Boolean;
begin
  var Seen: TArray<Boolean>;
  SetLength(Seen, FN);
  var Todo:= TStack<Integer>.Create;
  try
    for var T:= 0 to FN - 1 do
      if (T <> pTo) and IsForward(pFrom, T) then
        Todo.Push(T);
    while Todo.Count > 0 do
    begin
      var Z:= Todo.Pop;
      if Z = pTo then
        Exit(True);
      if Seen[Z] then
        Continue;
      Seen[Z]:= True;
      for var T:= 0 to FN - 1 do
        if IsForward(Z, T) then
          Todo.Push(T);
    end;
    Result:= False;
  finally
    Todo.Free;
  end;
end;

{ ---------- reading the index ---------- }

function SegmentsFrom(const pPath: string; pFirst: Integer; const pSep: string): string;
begin
  var Parts:= pPath.Replace('/', '\').Split(['\']);
  Result:= string.Join(pSep, Copy(Parts, pFirst, MaxInt));
end;

function DegreeOf(const pDegrees: TDictionary<Integer, Integer>; pFile: Integer): Integer;
begin
  if not pDegrees.TryGetValue(pFile, Result) then
    Result:= 0;
end;

function MetaValue(const pIndex: TChartsIndex; const pKey: string): string;
begin
  Result:= '';
  var Rows:= pIndex.AllRows('SELECT value AS v FROM schema_meta WHERE key = ''' + TChartsIndex.SqlText(pKey) + '''', 'key');
  try
    if Rows.Count > 0 then
      Result:= Rows[0].S('v');
  finally
    Rows.Free;
  end;
end;

function CountOf(const pIndex: TChartsIndex; const pSql: string): Integer;
begin
  var Rows:= pIndex.AllRows('SELECT COUNT(*) AS n ' + pSql, 'n');
  try
    Result:= Rows[0].I('n');
  finally
    Rows.Free;
  end;
end;

function SortedZoneNames(const pZoneUnits: TObjectDictionary<string, TList<TArchUnit>>): TArray<string>;
begin
  Result:= pZoneUnits.Keys.ToArray;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const pA, pB: string): Integer
    begin
      Result:= pZoneUnits[pB].Count - pZoneUnits[pA].Count;
      if Result = 0 then
        Result:= CompareText(pA, pB);
    end));
end;

function SortedUnits(const pList: TList<TArchUnit>): TArray<TArchUnit>;
begin
  Result:= pList.ToArray;
  TArray.Sort<TArchUnit>(Result, TComparer<TArchUnit>.Construct(
    function(const pA, pB: TArchUnit): Integer
    begin
      Result:= pB.UsedBy - pA.UsedBy;
      if Result = 0 then
        Result:= CompareText(pA.Name, pB.Name);
    end));
end;

function CommonRootOf(const pUnits: TEnumerable<TIndexRow>; out pRootText: string): Integer;
begin
  var Dirs: TArray<string>:= [];
  for var U in pUnits do
    Dirs:= Dirs + [ExtractFileDir(U.S('path').Replace('/', '\'))];
  Result:= CommonRootLen(Dirs);
  pRootText:= '';
  if Result > 0 then
    pRootText:= string.Join('\', Copy(Dirs[0].Split(['\']), 0, Result));
end;

function BuildArchModel(const pDbPath: string): TArchModel;
begin
  Result:= Default(TArchModel);
  Result.DbName:= ExtractFileName(pDbPath);
  var Index:= TChartsIndex.Create(pDbPath);
  var UnitRows: TObjectList<TIndexRow>:= nil;
  var UseRows: TObjectList<TIndexRow>:= nil;
  var ZoneUnits:= TObjectDictionary<string, TList<TArchUnit>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  var FileZone:= TDictionary<Integer, Integer>.Create;
  var FileUnit:= TDictionary<Integer, TArchUnit>.Create;
  var UsedBy:= TDictionary<Integer, Integer>.Create;
  var FileZoneName:= TDictionary<Integer, string>.Create;
  var Pairs:= TObjectDictionary<Integer, TList<TArchUsesPair>>.Create([doOwnsValues]);
  var Layering: TLayering:= nil;
  try
    Result.Fingerprint:= MetaValue(Index, META_KEY_FINGERPRINT);
    UnitRows:= Index.AllRows(
      'SELECT s.qualified_name AS q, s.start_line AS line, f.path AS path, f.id AS fid' + CRLF +
      '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''unit''', 's.qualified_name');
    if UnitRows.Count = 0 then
      raise EArchDiagram.Create('arch-diagram: this index holds no unit symbols at all');
    UseRows:= Index.AllRows(
      'SELECT uu.file_id AS src, uu.target_file_id AS dst, uu.section AS section, uu.start_line AS line' + CRLF +
      '  FROM unit_uses uu WHERE uu.target_file_id IS NOT NULL', 'uu.id');
    Result.ExternalUses:= CountOf(Index, 'FROM unit_uses WHERE target_file_id IS NULL');
    Result.UnitCount:= UnitRows.Count;

    for var E in UseRows do
      UsedBy.AddOrSetValue(E.I('dst'), DegreeOf(UsedBy, E.I('dst')) + 1);

    var RootLen:= CommonRootOf(UnitRows, Result.Root);
    for var U in UnitRows do
    begin
      var AUnit: TArchUnit;
      AUnit.Name:= U.S('q');
      AUnit.Path:= SegmentsFrom(U.S('path'), RootLen, '/');
      AUnit.Line:= U.I('line');
      AUnit.UsedBy:= DegreeOf(UsedBy, U.I('fid'));
      var Zone:= PathZone(U.S('path'), RootLen);
      var List: TList<TArchUnit>;
      if not ZoneUnits.TryGetValue(Zone, List) then
      begin
        List:= TList<TArchUnit>.Create;
        ZoneUnits.Add(Zone, List);
      end;
      List.Add(AUnit);
      FileUnit.AddOrSetValue(U.I('fid'), AUnit);
      FileZoneName.AddOrSetValue(U.I('fid'), Zone);
    end;

    var Names:= SortedZoneNames(ZoneUnits);
    var N:= Length(Names);
    SetLength(Result.Zones, N);
    for var I:= 0 to N - 1 do
    begin
      Result.Zones[I].Name:= Names[I];
      Result.Zones[I].Units:= SortedUnits(ZoneUnits[Names[I]]);
    end;
    var ZoneIndex:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
    try
      for var I:= 0 to N - 1 do
        ZoneIndex.Add(Names[I], I);
      for var Pair in FileZoneName do
        FileZone.Add(Pair.Key, ZoneIndex[Pair.Value]);
    finally
      ZoneIndex.Free;
    end;

    var Weight: TArray<TArray<Integer>>;
    SetLength(Weight, N, N);
    for var E in UseRows do
    begin
      var ZA, ZB: Integer;
      if not (FileZone.TryGetValue(E.I('src'), ZA) and FileZone.TryGetValue(E.I('dst'), ZB)) then
        Continue;
      if ZA = ZB then
      begin
        Inc(Result.Zones[ZA].InternalUses);
        Continue;
      end;
      Inc(Weight[ZA][ZB]);
      var Key:= ZA * N + ZB;
      var List: TList<TArchUsesPair>;
      if not Pairs.TryGetValue(Key, List) then
      begin
        List:= TList<TArchUsesPair>.Create;
        Pairs.Add(Key, List);
      end;
      var P: TArchUsesPair;
      P.FromUnit:= FileUnit[E.I('src')].Name;
      P.ToUnit:= FileUnit[E.I('dst')].Name;
      P.Path:= FileUnit[E.I('src')].Path;
      P.Line:= E.I('line');
      P.Section:= E.S('section');
      List.Add(P);
    end;

    Layering:= TLayering.Create(Names, Weight);
    Layering.Run;
    Result.LayerCount:= Layering.LayerCount;
    for var I:= 0 to N - 1 do
    begin
      Result.Zones[I].Layer:= Layering.Layer[I];
      Result.Zones[I].Order:= Layering.Order[I];
    end;
    for var I:= 0 to N - 1 do
      for var J:= 0 to N - 1 do
        if Weight[I][J] > 0 then
        begin
          var Edge: TArchEdge;
          Edge.FromZone:= Names[I];
          Edge.ToZone:= Names[J];
          Edge.Weight:= Weight[I][J];
          Edge.Kind:= Layering.KindOf(I, J);
          Edge.Implied:= (Edge.Kind = aekForward) and Layering.IsImplied(I, J);
          Edge.Pairs:= Pairs[I * N + J].ToArray;
          Edge.InterfaceUses:= 0;
          for var P in Edge.Pairs do
            if SameText(P.Section, 'interface') then
              Inc(Edge.InterfaceUses);
          Result.Edges:= Result.Edges + [Edge];
        end;
    TArray.Sort<TArchZone>(Result.Zones, TComparer<TArchZone>.Construct(
      function(const pA, pB: TArchZone): Integer
      begin
        Result:= pB.Layer - pA.Layer;
        if Result = 0 then
          Result:= pA.Order - pB.Order;
      end));
  finally
    Layering.Free;
    Pairs.Free;
    FileZoneName.Free;
    UsedBy.Free;
    FileUnit.Free;
    FileZone.Free;
    ZoneUnits.Free;
    UseRows.Free;
    UnitRows.Free;
    Index.Free;
  end;
end;

{ ---------- JSON ---------- }

function UnitJson(const pUnit: TArchUnit): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name', pUnit.Name);
  Result.AddPair('path', pUnit.Path);
  Result.AddPair('line', TJSONNumber.Create(pUnit.Line));
  Result.AddPair('usedBy', TJSONNumber.Create(pUnit.UsedBy));
end;

function ZoneJson(const pZone: TArchZone): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name', pZone.Name);
  Result.AddPair('layer', TJSONNumber.Create(pZone.Layer));
  Result.AddPair('order', TJSONNumber.Create(pZone.Order));
  Result.AddPair('internal', TJSONNumber.Create(pZone.InternalUses));
  var Units:= TJSONArray.Create;
  Result.AddPair('units', Units);
  for var U in pZone.Units do
    Units.AddElement(UnitJson(U));
end;

function EdgeJson(const pEdge: TArchEdge): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('from', pEdge.FromZone);
  Result.AddPair('to', pEdge.ToZone);
  Result.AddPair('weight', TJSONNumber.Create(pEdge.Weight));
  Result.AddPair('interface', TJSONNumber.Create(pEdge.InterfaceUses));
  Result.AddPair('kind', KIND_TEXT[pEdge.Kind]);
  Result.AddPair('implied', TJSONBool.Create(pEdge.Implied));
  var Items:= TJSONArray.Create;
  Result.AddPair('pairs', Items);
  for var P in pEdge.Pairs do
  begin
    var Item:= TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('from', P.FromUnit);
    Item.AddPair('to', P.ToUnit);
    Item.AddPair('path', P.Path);
    Item.AddPair('line', TJSONNumber.Create(P.Line));
    Item.AddPair('section', P.Section);
  end;
end;

function ArchModelJson(const pModel: TArchModel): string;
begin
  var Doc:= TJSONObject.Create;
  try
    Doc.AddPair('schema', ARCH_SCHEMA);
    Doc.AddPair('db', pModel.DbName);
    Doc.AddPair('root', pModel.Root);
    Doc.AddPair('fingerprint', pModel.Fingerprint);
    Doc.AddPair('units', TJSONNumber.Create(pModel.UnitCount));
    Doc.AddPair('externalUses', TJSONNumber.Create(pModel.ExternalUses));
    Doc.AddPair('layers', TJSONNumber.Create(pModel.LayerCount));
    var Zones:= TJSONArray.Create;
    Doc.AddPair('zones', Zones);
    for var Z in pModel.Zones do
      Zones.AddElement(ZoneJson(Z));
    var Edges:= TJSONArray.Create;
    Doc.AddPair('edges', Edges);
    for var E in pModel.Edges do
      Edges.AddElement(EdgeJson(E));
    Result:= Doc.ToJSON;
  finally
    Doc.Free;
  end;
end;

{ ---------- the page ---------- }

function Esc(const pText: string): string;
begin
  Result:= TNetEncoding.HTML.Encode(pText);
end;

// keeps the end of a dotted name: that is the part that differs inside a folder
function ShortName(const pName: string): string;
begin
  Result:= pName;
  if Length(pName) > NAME_CHARS then
    Result:= ELLIPSIS + Copy(pName, Length(pName) - NAME_CHARS + Length(ELLIPSIS) + 1, NAME_CHARS);
end;

function RowsInLayer(const pModel: TArchModel; pLayer: Integer): Integer;
begin
  Result:= 0;
  for var Z in pModel.Zones do
    if Z.Layer = pLayer then
      Inc(Result);
end;

function BoxHeight(const pZone: TArchZone): Integer;
begin
  Result:= BOX_HEADER + BOX_PAD + BOX_LINE * Min(Length(pZone.Units), MAX_UNITS_SHOWN + 1);
end;

// where the arrow leaves or enters a box: towards the other end, so arrows of one box do not stack
function PortX(pFrom, pTo: Integer): Integer;
begin
  Result:= pFrom + Round((BOX_W / HALF - PORT_INSET) * EnsureRange((pTo - pFrom) / PORT_SPREAD, -PORT_REACH, PORT_REACH));
end;

procedure AppendEdge(const pSb: TStringBuilder; pIdx: Integer; const pEdge: TArchEdge; const pFrom, pTo: TRect);
begin
  var X1:= PortX(pFrom.CenterPoint.X, pTo.CenterPoint.X);
  var X2:= PortX(pTo.CenterPoint.X, pFrom.CenterPoint.X);
  var Y1, Y2, LabelY: Integer;
  var D: string;
  if pFrom.Top = pTo.Top then
  begin
    Y1:= pFrom.Bottom;
    Y2:= pTo.Bottom;
    LabelY:= Max(Y1, Y2) + CURVE_LABEL_DROP;
    D:= Format('M%d %d C%d %d %d %d %d %d', [X1, Y1, X1, Y1 + CURVE_SAME_ROW, X2, Y2 + CURVE_SAME_ROW, X2, Y2]);
  end
  else
  begin
    if pFrom.Top < pTo.Top then
    begin
      Y1:= pFrom.Bottom;
      Y2:= pTo.Top;
    end
    else
    begin
      Y1:= pFrom.Top;
      Y2:= pTo.Bottom;
    end;
    var MidY:= (Y1 + Y2) div HALF;
    LabelY:= MidY + LABEL_DROP;
    D:= Format('M%d %d C%d %d %d %d %d %d', [X1, Y1, X1, MidY, X2, MidY, X2, Y2]);
  end;
  var Kind:= KIND_TEXT[pEdge.Kind];
  pSb.AppendFormat('<g class="edge %s" data-e="%d" tabindex="0"><title>%s -&gt; %s: %d uses (%s)</title>', [Kind + (if pEdge.Implied then ' implied' else ''), pIdx, Esc(pEdge.FromZone), Esc(pEdge.ToZone), pEdge.Weight, Kind]);
  pSb.AppendFormat('<path class="hit" d="%s"/>', [D]);
  var Width:= EnsureRange(STROKE_MIN + Trunc(Log2(pEdge.Weight)), STROKE_MIN, STROKE_MAX);
  pSb.AppendFormat('<path class="ln" stroke-width="%d" marker-end="url(#mk-%s)" d="%s"/>', [Width, Kind, D]);
  pSb.AppendFormat('<text x="%d" y="%d">%d</text></g>', [(X1 + X2) div HALF, LabelY, pEdge.Weight]);
  pSb.AppendLine;
end;

procedure AppendZone(const pSb: TStringBuilder; pIdx: Integer; const pZone: TArchZone; const pBox: TRect);
begin
  pSb.AppendFormat('<g class="zone" data-z="%d" tabindex="0"><title>%s</title>', [pIdx, Esc(pZone.Name)]);
  pSb.AppendFormat('<rect x="%d" y="%d" width="%d" height="%d" rx="4"/>', [pBox.Left, pBox.Top, pBox.Width, pBox.Height]);
  pSb.AppendFormat('<text class="zn" x="%d" y="%d">%s</text>', [pBox.Left + BOX_PAD, pBox.Top + TEXT_HEADER_DY, Esc(ShortName(pZone.Name))]);
  pSb.AppendFormat('<text class="zc" x="%d" y="%d">%d %s</text>', [pBox.Left + BOX_PAD, pBox.Top + TEXT_COUNT_DY, Length(pZone.Units), if Length(pZone.Units) = 1 then 'unit' else 'units']);
  var Y:= pBox.Top + BOX_HEADER + TEXT_UNIT_DY;
  var Shown:= 0;
  for var U in pZone.Units do
  begin
    if Shown = MAX_UNITS_SHOWN then
    begin
      pSb.AppendFormat('<text class="zc" x="%d" y="%d">+%d more</text>', [pBox.Left + BOX_PAD, Y, Length(pZone.Units) - Shown]);
      Break;
    end;
    pSb.AppendFormat('<text class="zu" x="%d" y="%d">%s</text>', [pBox.Left + BOX_PAD, Y, Esc(ShortName(U.Name))]);
    Inc(Y, BOX_LINE);
    Inc(Shown);
  end;
  pSb.AppendLine('</g>');
end;

function MarkerDef(const pKind: string): string;
begin
  Result:= Format('<marker id="mk-%s" class="mk-%s" markerWidth="%d" markerHeight="%d" refX="%d" refY="%d" orient="auto" markerUnits="userSpaceOnUse"><path d="M0 0L%d %dL0 %dz"/></marker>',
    [pKind, pKind, ARROW_SIZE, ARROW_SIZE, ARROW_SIZE, ARROW_SIZE div HALF, ARROW_SIZE, ARROW_SIZE div HALF, ARROW_SIZE]);
end;

function MarkerDefs: string;
begin
  Result:= '<defs>' + MarkerDef(KIND_TEXT[aekForward]) + MarkerDef(KIND_TEXT[aekBack]) + MarkerDef(KIND_TEXT[aekTangle]) + '</defs>';
end;

function DiagramSvg(const pModel: TArchModel): string;
begin
  var Boxes: TArray<TRect>;
  SetLength(Boxes, Length(pModel.Zones));
  var Widest:= 0;
  for var L:= 0 to pModel.LayerCount - 1 do
    Widest:= Max(Widest, RowsInLayer(pModel, L));
  var Width:= MARGIN_LEFT + MARGIN_RIGHT + Widest * (BOX_W + GAP_X);
  var Bands:= TStringBuilder.Create;
  var Sb:= TStringBuilder.Create;
  try
    var Y:= MARGIN_TOP;
    for var L:= pModel.LayerCount - 1 downto 0 do
    begin
      var RowH:= LABEL_MIN_ROW;
      for var Z in pModel.Zones do
        if Z.Layer = L then
          RowH:= Max(RowH, BoxHeight(Z));
      Bands.AppendFormat('<rect class="band" x="0" y="%d" width="%d" height="%d"/><text class="lay" x="%d" y="%d">layer %d</text>',
        [Y - GAP_Y div (HALF * HALF), Width, RowH + GAP_Y div HALF, LAYER_LABEL_X, Y + LAYER_LABEL_DY, L]);
      Bands.AppendLine;
      var Count:= RowsInLayer(pModel, L);
      var X:= MARGIN_LEFT + (Widest - Count) * (BOX_W + GAP_X) div HALF;
      for var I:= 0 to High(pModel.Zones) do
        if pModel.Zones[I].Layer = L then
        begin
          var BoxX:= X + pModel.Zones[I].Order * (BOX_W + GAP_X);
          Boxes[I]:= TRect.Create(BoxX, Y, BoxX + BOX_W, Y + BoxHeight(pModel.Zones[I]));
        end;
      Inc(Y, RowH + GAP_Y);
    end;
    var Height:= Y;
    Sb.AppendFormat('<svg id="d" xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="Layer diagram of units by folder">', [Width, Height, Width, Height]);
    Sb.AppendLine;
    Sb.AppendLine(MarkerDefs);
    Sb.Append(Bands.ToString);
    var ZoneAt:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
    try
      for var I:= 0 to High(pModel.Zones) do
        ZoneAt.Add(pModel.Zones[I].Name, I);
      for var I:= 0 to High(pModel.Edges) do
        AppendEdge(Sb, I, pModel.Edges[I], Boxes[ZoneAt[pModel.Edges[I].FromZone]], Boxes[ZoneAt[pModel.Edges[I].ToZone]]);
    finally
      ZoneAt.Free;
    end;
    for var I:= 0 to High(pModel.Zones) do
      AppendZone(Sb, I, pModel.Zones[I], Boxes[I]);
    Sb.AppendLine('</svg>');
    Result:= Sb.ToString;
  finally
    Sb.Free;
    Bands.Free;
  end;
end;

function CountKind(const pModel: TArchModel; pKind: TArchEdgeKind): Integer;
begin
  Result:= 0;
  for var E in pModel.Edges do
    if E.Kind = pKind then
      Inc(Result);
end;

function KeySample(const pKind: string; const pText: string): string;
begin
  Result:= Format('<span><svg width="34" height="10"><g class="edge %s"><path class="ln" stroke-width="2" d="M0 5H34"/></g></svg>%s</span>', [pKind, pText]);
end;

function ArchDiagramHtml(const pModel: TArchModel): string;
begin
  var Title:= 'Layers of ' + pModel.DbName;
  var SingleZone:= if Length(pModel.Zones) <= 1 then '<p>Every unit sits in one folder, so there are no layers to draw.</p>' else '';
  Result:=
    '<!DOCTYPE html>' + CRLF + '<html lang="en"><head><meta charset="utf-8"><title>' + Esc(Title) + '</title>' + CRLF +
    '<style>' + CRLF + PAGE_STYLE + CRLF + '</style></head><body>' + CRLF +
    '<header><h1>' + Esc(Title) + '</h1>' + CRLF +
    Format('<p>%d units in %d folders, %d layers, %d arrows: %d back-edges, %d in tangles. %d uses entries to units outside the index are left out.</p>',
      [pModel.UnitCount, Length(pModel.Zones), pModel.LayerCount, Length(pModel.Edges), CountKind(pModel, aekBack), CountKind(pModel, aekTangle), pModel.ExternalUses]) + CRLF +
    '<p>Layers are measured from the <code>uses</code> clauses: a folder sits above what it uses. Root ' + Esc(pModel.Root) +
    ', indexer fingerprint ' + Esc(pModel.Fingerprint) + '. Regenerate after a reindex: <code>drag-lint arch-diagram --db ' + Esc(pModel.DbName) + ' --output ...</code></p>' + CRLF +
    SingleZone +
    '<p class="key">' + KeySample('forward', 'uses (down)') + KeySample('back', 'back-edge: the smaller direction of a pair') + KeySample('tangle', 'inside a cycle') + 'A forward arrow a longer path also implies is faint until its folder is picked. Number on an arrow = <code>uses</code> entries.</p></header>' + CRLF +
    '<main><div id="w">' + CRLF + DiagramSvg(pModel) + '</div>' + CRLF +
    '<aside id="panel"><p>Click a folder for its units and arrows, or an arrow for the <code>uses</code> lines behind it. Click the background to clear.</p></aside></main>' + CRLF +
    '<script type="application/json" id="graph">' + ArchModelJson(pModel).Replace('<', '<') + '</script>' + CRLF +
    '<script>' + CRLF + PAGE_SCRIPT + CRLF + '</script>' + CRLF + '</body></html>' + CRLF;
end;

end.
