unit DRagLint.Charts.Q.Path;

(* The `path` question in-process: a port of charts\src\Emit-Path.ps1 (spec s11; the PS output is
  the reference, P3). Every SHORTEST call path from routine A (-Target) to routine B (-To), each
  call labelled with its call site and grade.

  DATA ROUTE (decision G7). The PS spawns `call-path --from A --to B --max-depth 20 --json` to
  decide found / not found and the length L. This unit carries a private mirror of that verb's
  BFS (EnginePath, a mirror of DRagLint.CLI.pas DoCallPath; spec P5 forbids starting
  drag-lint.exe from a ported emitter): multi-source seed in FromIds order with the trivial
  length-0 hit, BFS over GetCallEdgesFromSymbol in edge order, the first hit wins, the path is
  rebuilt by walking Parent. The mirror is an engine-move candidate; it is not moved here.
  The max depth is the constant PATH_MAX_DEPTH (Emit-Path's own default).

  EVERY shortest path (G8, G9). One recursive query over the same call_edges gives the distance
  from A forward and to B backward, bounded by L; a call u -> v is on a shortest path exactly
  when dist(A,u) + 1 + dist(v,B) = L. The same rows carry each call's SITE and GRADE. The
  engine's own path must be one of them, and SQL's own shortest distance must be L, or nothing
  is drawn (an engine-defect refusal, never a chart to trust). The count of paths is exact
  (dynamic programming over the shortest-path graph); the cap is exact and disclosed.

  REFUSALS (G6). A blank -To; A = B; a routine not in the index; an overload (each end must be
  exactly ONE routine); no path within 20 calls; the three engine-defect texts.

  PS traps closed: -eq and -ne are case-blind (SameText); `[ordered]@{}` insertion order is
  mirrored by key lists; `Sort-Object { $name[$_] }, { $_ }` is CompareGroupKeys then id;
  `if ($r.impl_start_line)` is false for NULL and for 0; `$shown.Count -ge $Cap` is checked on
  ENTRY, before the add; a NULL MIN(d) is told apart from a real 0; Write-Host lines are not
  output (no host stream here). *)

interface

const
  /// <summary>The registered question id of the path chart.</summary>
  PATH_ID = 'path';
  /// <summary>The longest call path searched, in calls (Emit-Path's own -MaxDepth default).</summary>
  /// <remarks>Not a parameter: New-DiagramArtifact never passes -MaxDepth.</remarks>
  PATH_MAX_DEPTH = 20;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  System.RegularExpressions, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Charts.Question,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- the SQL text escaper, the name sort and the multi-row query travel with TChartsIndex, so the refusal texts and the sort order cannot drift from the other questions
  DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.PsSort;

const
  END_BORDER = '#0F766E';
  END_FILL = '#E2F1EF';
  END_HDR = '#0F766E';
  END_INK = '#0B3F39';
  MID_BORDER = '#B45309';
  MID_FILL = '#FEF6EC';
  MID_HDR = '#B45309';
  PEN_END = 3;
  PEN_MID = 2;
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  AMB_INK = '#9A5408';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  CAND_LIMIT = 12;

type
  // one call site of a pair: where the call is and the index's own grade for it
  TPathSite = record
    FilePath: string;
    Line: Integer;
    Grade: string;
  end;

  // where a drawn routine is: its BODY line when it has one
  TPathLoc = record
    Path: string;
    Line: Integer;
  end;

  // one distinct (Src, Dst) call, its sites in row order
  TPathPair = class
  private
    FSrc: Int64;
    FDst: Int64;
    FSites: TList<TPathSite>;
  public
    constructor Create(pSrc, pDst: Int64);
    destructor Destroy; override;
    property Src: Int64 read FSrc;
    property Dst: Int64 read FDst;
    property Sites: TList<TPathSite> read FSites;
  end;

  // the shortest-path graph of Emit-Path.ps1 steps 2-3: nodes are symbol ids
  TPathGraph = class
  private
    FL: Integer;
    FCap: Integer;
    FWays: TDictionary<Int64, Int64>;
    FName: TDictionary<Int64, string>;
    FHopOf: TDictionary<Int64, Integer>;
    FPairKeys: TList<string>;
    FPairs: TObjectDictionary<string, TPathPair>;
    FNext: TObjectDictionary<Int64, TList<Int64>>;
    FShown: TList<TArray<Int64>>;
    FTotal: Int64;
    function SortedByName(const pIds: TArray<Int64>): TArray<Int64>;
    procedure AddPaths(pId: Int64; const pPrefix: TArray<Int64>);
  public
    constructor Create(pL, pCap: Integer);
    destructor Destroy; override;
    class function PairKey(pSrc, pDst: Int64): string; static;
    procedure AddRow(const pRow: TIndexRow);
    function Starts: TArray<Int64>;
    function IsEnd(pId: Int64): Boolean;
    function Ways(pId: Int64): Int64;
    procedure CheckEnginePath(const pEnginePath: TArray<string>);
    procedure Enumerate;
    property Name: TDictionary<Int64, string> read FName;
    property HopOf: TDictionary<Int64, Integer> read FHopOf;
    property PairKeys: TList<string> read FPairKeys;
    property Pairs: TObjectDictionary<string, TPathPair> read FPairs;
    property Next: TObjectDictionary<Int64, TList<Int64>> read FNext;
    property Shown: TList<TArray<Int64>> read FShown;
    property Total: Int64 read FTotal;
  end;

constructor TPathPair.Create(pSrc, pDst: Int64);
begin
  inherited Create;
  FSrc:= pSrc;
  FDst:= pDst;
  FSites:= TList<TPathSite>.Create;
end;

destructor TPathPair.Destroy;
begin
  FSites.Free;
  inherited Destroy;
end;

constructor TPathGraph.Create(pL, pCap: Integer);
begin
  inherited Create;
  FL:= pL;
  FCap:= pCap;
  FWays:= TDictionary<Int64, Int64>.Create;
  FName:= TDictionary<Int64, string>.Create;
  FHopOf:= TDictionary<Int64, Integer>.Create;
  FPairKeys:= TList<string>.Create;
  FPairs:= TObjectDictionary<string, TPathPair>.Create([doOwnsValues]);
  FNext:= TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  FShown:= TList<TArray<Int64>>.Create;
end;

destructor TPathGraph.Destroy;
begin
  FShown.Free;
  FNext.Free;
  FPairs.Free;
  FPairKeys.Free;
  FHopOf.Free;
  FName.Free;
  FWays.Free;
  inherited Destroy;
end;

class function TPathGraph.PairKey(pSrc, pDst: Int64): string;
begin
  Result:= IntToStr(pSrc) + '>' + IntToStr(pDst);
end;

// one site row (PS 118-129): later rows overwrite name and hop, as a hashtable does
procedure TPathGraph.AddRow(const pRow: TIndexRow);
begin
  var Si:= StrToInt64Def(pRow.S('src_id'), 0);
  var Di:= StrToInt64Def(pRow.S('dst_id'), 0);
  Name.AddOrSetValue(Si, pRow.S('src'));
  Name.AddOrSetValue(Di, pRow.S('dst'));
  HopOf.AddOrSetValue(Si, pRow.I('hop'));
  HopOf.AddOrSetValue(Di, pRow.I('hop') + 1);
  var Key:= PairKey(Si, Di);
  var Pr: TPathPair;
  if not Pairs.TryGetValue(Key, Pr) then
  begin
    Pr:= TPathPair.Create(Si, Di);
    Pairs.Add(Key, Pr);
    PairKeys.Add(Key);
    var Succ: TList<Int64>;
    if not Next.TryGetValue(Si, Succ) then
    begin
      Succ:= TList<Int64>.Create;
      Next.Add(Si, Succ);
    end;
    Succ.Add(Di);
  end;
  var Site: TPathSite;
  Site.FilePath:= pRow.S('path');
  Site.Line:= pRow.I('line');
  Site.Grade:= pRow.S('grade');
  Pr.Sites.Add(Site);
end;

// Sort-Object { $name[$_] }, { $_ }: the name by CompareGroupKeys, then the id
function TPathGraph.SortedByName(const pIds: TArray<Int64>): TArray<Int64>;
begin
  Result:= Copy(pIds);
  TPsSort<Int64>.Sort(Result,
    function(const pA, pB: Int64): Integer
    begin
      Result:= CompareGroupKeys(Name[pA], Name[pB]);
      if Result = 0 then
        Result:= if pA < pB then -1 else if pA > pB then 1 else 0;
    end);
end;

function TPathGraph.Starts: TArray<Int64>;
begin
  Result:= [];
  for var P in HopOf do
    if P.Value = 0 then
      Result:= Result + [P.Key];
  Result:= SortedByName(Result);
end;

function TPathGraph.IsEnd(pId: Int64): Boolean;
begin
  Result:= HopOf[pId] = FL;
end;

// paths from a node to B: 1 at an end, else the sum over its successors (memoised)
function TPathGraph.Ways(pId: Int64): Int64;
begin
  if FWays.TryGetValue(pId, Result) then
    Exit;
  Result:= 0;
  var Succ: TList<Int64>;
  if IsEnd(pId) then
    Result:= 1
  else if Next.TryGetValue(pId, Succ) then
    for var D in Succ do
      Result:= Result + Ways(D);
  FWays.AddOrSetValue(pId, Result);
end;

// call-path's own path must be a route through this graph, by name, hop by hop (PS 133-137)
procedure TPathGraph.CheckEnginePath(const pEnginePath: TArray<string>);
begin
  for var I:= 0 to FL - 1 do
  begin
    var Hit:= False;
    for var Key in PairKeys do
    begin
      var Pr:= Pairs[Key];
      if SameText(Name[Pr.Src], pEnginePath[I]) and SameText(Name[Pr.Dst], pEnginePath[I + 1]) and (HopOf[Pr.Src] = I) then
      begin
        Hit:= True;
        Break;
      end;
    end;
    if not Hit then
      raise EChartsQuestion.CreateFmt('call-path''s path (%s) is not among the shortest paths over call_edges at hop %d -- ' +
        'the two disagree (engine defect; nothing drawn)', [string.Join(' -> ', pEnginePath), I]);
  end;
end;

// the first Cap paths in name order; the cap is checked on ENTRY, before the add (PS 152-158)
procedure TPathGraph.AddPaths(pId: Int64; const pPrefix: TArray<Int64>);
begin
  if Shown.Count >= FCap then
    Exit;
  var P:= pPrefix + [pId];
  if IsEnd(pId) then
  begin
    Shown.Add(P);
    Exit;
  end;
  var Succ: TList<Int64>;
  if not Next.TryGetValue(pId, Succ) then
    Exit;
  for var D in SortedByName(Succ.ToArray) do
    AddPaths(D, P);
end;

// the exact count over every start, then the shown paths (PS 148-159)
procedure TPathGraph.Enumerate;
begin
  var St:= Starts;
  FTotal:= 0;
  for var S in St do
    FTotal:= FTotal + Ways(S);
  for var S in St do
    AddPaths(S, []);
end;

// Mirror of DRagLint.CLI.pas ResolveEndpointIds (private to the CLI unit, decision G7; a third copy after Q.WhoCalls and Q.Butterfly): exact name, else qualified name.
function ResolveEndpointIds(const pStore: ISymbolStore; const pName: string): TArray<Int64>;
begin
  Result:= [];
  var Syms:= pStore.FindSymbolsByExactName(pName);
  if Length(Syms) = 0 then
    Syms:= pStore.FindSymbolsByQualifiedName(pName);
  for var S in Syms do
    if not TArray.Contains<Int64>(Result, S.Id) then
      Result:= Result + [S.Id];
end;

/// <summary>The engine's call-path walk, in-process: ONE shortest path from A to B over the resolved call_edges.</summary>
/// <param name="pStore">An open read-only symbol store.</param>
/// <param name="pFrom">Routine A (exact name, else qualified name).</param>
/// <param name="pTo">Routine B.</param>
/// <param name="pMaxDepth">The depth cap: nodes at this depth are not expanded.</param>
/// <returns>The qualified names from A to B; empty when no path exists within pMaxDepth.</returns>
/// <remarks>Mirror of DRagLint.CLI.pas DoCallPath, line for line: multi-source seed in FromIds
/// order, a source that is itself a target is the length-0 path, BFS in edge order skipping
/// unresolved targets and visited ids, the FIRST hit ends the walk.</remarks>
function EnginePath(const pStore: ISymbolStore; const pFrom, pTo: string; pMaxDepth: Integer): TArray<string>;
begin
  Result:= [];
  var FromIds:= ResolveEndpointIds(pStore, pFrom);
  var ToIds:= ResolveEndpointIds(pStore, pTo);
  if (Length(FromIds) = 0) or (Length(ToIds) = 0) then
    Exit;
  var ToSet:= TDictionary<Int64, Boolean>.Create;
  var Visited:= TDictionary<Int64, Boolean>.Create;
  var Parent:= TDictionary<Int64, Int64>.Create;
  var Depths:= TDictionary<Int64, Integer>.Create;
  var Frontier:= TQueue<Int64>.Create;
  try
    for var T in ToIds do
      ToSet.AddOrSetValue(T, True);
    var Found:= False;
    var Hit: Int64:= 0;
    for var Cur in FromIds do
      if not Visited.ContainsKey(Cur) then
      begin
        Visited.Add(Cur, True);
        Depths.AddOrSetValue(Cur, 0);
        Frontier.Enqueue(Cur);
        if ToSet.ContainsKey(Cur) and not Found then
        begin
          Found:= True;
          Hit:= Cur;
        end;
      end;
    while (not Found) and (Frontier.Count > 0) do
    begin
      var Cur:= Frontier.Dequeue;
      var D:= Depths[Cur];
      if D >= pMaxDepth then
        Continue;
      for var E in pStore.GetCallEdgesFromSymbol(Cur) do
      begin
        if (E.TargetSymbolId <= 0) or Visited.ContainsKey(E.TargetSymbolId) then
          Continue;
        Visited.Add(E.TargetSymbolId, True);
        Parent.AddOrSetValue(E.TargetSymbolId, Cur);
        Depths.AddOrSetValue(E.TargetSymbolId, D + 1);
        if ToSet.ContainsKey(E.TargetSymbolId) then
        begin
          Found:= True;
          Hit:= E.TargetSymbolId;
          Break;
        end;
        Frontier.Enqueue(E.TargetSymbolId);
      end;
    end;
    if not Found then
      Exit;
    { walk the parent links from the hit back to a seed, then flip to source -> target }
    var Ids:= TList<Int64>.Create;
    try
      var Walk:= Hit;
      repeat
        Ids.Add(Walk);
      until not Parent.TryGetValue(Walk, Walk);
      Ids.Reverse;
      for var Id in Ids do
        Result:= Result + [pStore.GetSymbolById(Id).QualifiedName];
    finally
      Ids.Free;
    end;
  finally
    Frontier.Free;
    Depths.Free;
    Parent.Free;
    Visited.Free;
    ToSet.Free;
  end;
end;

// Get-FileSize: the size in bytes, 0 when the file is missing.
function FileSizeOf(const pPath: string): Integer;
begin
  if TFile.Exists(pPath) then
    Result:= Integer(TFile.GetSize(pPath))
  else
    Result:= 0;
end;

// one end of the path must be exactly ONE routine: refuse none and several (PS 62-74)
procedure CheckEnd(const pIndex: TChartsIndex; const pQ: string);
begin
  var Cand:= pIndex.Query('SELECT s.kind AS kind, s.start_line AS line, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.qualified_name = ''' + TChartsIndex.SqlText(pQ) + ''' ORDER BY f.path, s.start_line LIMIT ' + IntToStr(CAND_LIMIT));
  try
    if Cand.Count = 0 then
      raise EChartsQuestion.CreateFmt('%s is not in this index (give the qualified name, Unit.Class.Method)', [pQ]);
    if Cand.Count > 1 then
    begin
      var Parts: TArray<string>:= [];
      for var R in Cand do
        Parts:= Parts + [Format('%s @%s:%d', [R.S('kind'), FileNameOf(R.S('path')), R.I('line')])];
      var More:= if Cand.Count >= CAND_LIMIT then '+' else '';
      raise EChartsQuestion.Create(Format('%s names %d%s symbols (an overload or a duplicate declaration): %s. ', [pQ, Cand.Count, More, string.Join(', ', Parts)]) +
        'path needs each end to be exactly ONE routine, and overloads share their qualified name, so no spelling picks one -- ' +
        Format('ask butterfly or who-calls on %s instead, or start / end the path at a routine next to it.', [pQ]));
    end;
  finally
    Cand.Free;
  end;
end;

// the WITH RECURSIVE prefix of PS 90-96, ending in a line break (the PS here-string)
function CtePrefix(const pFrom, pTo: string; pL: Integer): string;
begin
  var Fq:= TChartsIndex.SqlText(pFrom);
  var Tq:= TChartsIndex.SqlText(pTo);
  Result:= 'WITH RECURSIVE' + sLineBreak +
    ' e(src, dst) AS (SELECT DISTINCT r.enclosing_symbol_id, ce.target_symbol_id FROM call_edges ce JOIN refs r ON r.id = ce.ref_id WHERE r.enclosing_symbol_id IS NOT NULL),' + sLineBreak +
    Format(' fw(id, d) AS (SELECT id, 0 FROM symbols WHERE qualified_name = ''%s'' UNION SELECT e.dst, fw.d + 1 FROM fw JOIN e ON e.src = fw.id WHERE fw.d < %d),', [Fq, pL]) + sLineBreak +
    Format(' bw(id, d) AS (SELECT id, 0 FROM symbols WHERE qualified_name = ''%s'' UNION SELECT e.src, bw.d + 1 FROM bw JOIN e ON e.dst = bw.id WHERE bw.d < %d),', [Tq, pL]) + sLineBreak +
    ' da(id, d) AS (SELECT id, MIN(d) FROM fw GROUP BY id),' + sLineBreak +
    ' db(id, d) AS (SELECT id, MIN(d) FROM bw GROUP BY id)' + sLineBreak;
end;

// the SELECT of PS 97-103 (no ORDER BY: AllRows appends the total order)
function SiteSelect(pL: Integer): string;
begin
  Result := 'SELECT da.d AS hop, s.id AS src_id, s.qualified_name AS src, t.id AS dst_id, t.qualified_name AS dst,' + sLineBreak +
    '       f.path AS path, r.start_line AS line, ce.confidence AS grade, r.id AS ref_id' + sLineBreak +
    '  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id' + sLineBreak +
    '  JOIN da ON da.id = r.enclosing_symbol_id JOIN db ON db.id = ce.target_symbol_id' + sLineBreak +
    '  JOIN symbols s ON s.id = r.enclosing_symbol_id JOIN symbols t ON t.id = ce.target_symbol_id' + sLineBreak +
    '  JOIN files f ON f.id = r.file_id' + sLineBreak +
    Format(' WHERE da.d + 1 + db.d = %d', [pL]);
end;

// SQL's own shortest distance A -> B must be call-path's L (PS 107-114)
procedure CheckDistance(const pIndex: TChartsIndex; const pFrom, pTo: string; pL: Integer);
begin
  var Rows:= pIndex.Query(CtePrefix(pFrom, pTo, pL) +
    'SELECT MIN(fw.d) AS dmin FROM fw WHERE fw.id IN (SELECT id FROM symbols WHERE qualified_name = ''' + TChartsIndex.SqlText(pTo) + ''')');
  try
    var IsNull:= (Rows.Count = 0) or (Rows[0].S('dmin') = '');
    if IsNull or (Rows[0].I('dmin') <> pL) then
    begin
      var Got:= if IsNull then Format('none within %d', [pL]) else IntToStr(Rows[0].I('dmin'));
      raise EChartsQuestion.CreateFmt('call-path says the shortest path is %d call(s), but call_edges give %s -- ' +
        'the two disagree (engine defect; nothing drawn)', [pL, Got]);
    end;
  finally
    Rows.Free;
  end;
end;

// the routines and pairs of the shown paths only, in walk order (PS 163-170)
procedure CollectDrawn(pGraph: TPathGraph; pIds: TList<Int64>; pPairKeys: TList<string>);
begin
  var SeenId:= TDictionary<Int64, Boolean>.Create;
  var SeenPair:= TDictionary<string, Boolean>.Create;
  try
    for var P in pGraph.Shown do
      for var I:= 0 to High(P) do
      begin
        if not SeenId.ContainsKey(P[I]) then
        begin
          SeenId.Add(P[I], True);
          pIds.Add(P[I]);
        end;
        if I < High(P) then
        begin
          var Key:= TPathGraph.PairKey(P[I], P[I + 1]);
          if not SeenPair.ContainsKey(Key) then
          begin
            SeenPair.Add(Key, True);
            pPairKeys.Add(Key);
          end;
        end;
      end;
  finally
    SeenPair.Free;
    SeenId.Free;
  end;
end;

// where each drawn routine is: its BODY line when it has one (PS 172-176; NULL and 0 both read as none)
function LocateRoutines(const pIndex: TChartsIndex; pIds: TList<Int64>): TDictionary<Int64, TPathLoc>;
begin
  Result:= TDictionary<Int64, TPathLoc>.Create;
  var Parts: TArray<string>:= [];
  for var Id in pIds do
    Parts:= Parts + [IntToStr(Id)];
  var Rows:= pIndex.AllRows('SELECT s.id AS id, s.start_line AS start_line, s.impl_start_line AS impl_start_line, f.path AS path ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id IN (' + string.Join(',', Parts) + ')', 's.id');
  try
    for var R in Rows do
    begin
      var Loc: TPathLoc;
      Loc.Path:= R.S('path');
      Loc.Line:= if R.I('impl_start_line') <> 0 then R.I('impl_start_line') else R.I('start_line');
      Result.AddOrSetValue(StrToInt64Def(R.S('id'), 0), Loc);
    end;
  finally
    Rows.Free;
  end;
end;

// one routine's HTML-label table, in ONE line (PS 199-203 concatenate without breaks)
function NodeTable(const pQ, pRole: string; const pAt: TPathLoc; pIsEp: Boolean): string;
begin
  var UnitTxt:= UnitNameOf(pAt.Path);
  var Hdr:= if pIsEp then END_HDR else MID_HDR;
  var Ink:= if pIsEp then END_INK else ROW_INK;
  var BoldOn:= if pIsEp then '<B>' else '';
  var BoldOff:= if pIsEp then '</B>' else '';
  Result:= '<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="6">' +
    Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; %s </B></FONT></TD></TR>',
      [Hdr, FONT_SANS, XmlText(UnitTxt), pRole]) +
    Format('<TR><TD ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(pAt.Path, pAt.Line),
      XmlText(Format('%s  --  %s:%d', [pQ, FileNameOf(pAt.Path), pAt.Line]))]) +
    Format('<FONT COLOR="%s">%s%s%s</FONT>', [Ink, BoldOn, XmlText(ShortName(pQ, UnitTxt)), BoldOff]) +
    Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR></TABLE>', [LINE_INK, pAt.Line]);
end;

// the routines as clusters, in DrawnIds order (PS 188-212); no rank=same, it would pull a node out of its cluster
procedure AppendNodes(pSb: TStringBuilder; pGraph: TPathGraph; pIds: TList<Int64>; pLoc: TDictionary<Int64, TPathLoc>;
  pL: Integer; pNodeOf: TDictionary<Int64, string>; var pClicks: Integer);
begin
  var Nid:= 0;
  for var Id in pIds do
  begin
    Inc(Nid);
    pNodeOf.AddOrSetValue(Id, 'r' + IntToStr(Nid));
    var H:= pGraph.HopOf[Id];
    var IsEp:= (H = 0) or (H = pL);
    var Border:= if IsEp then END_BORDER else MID_BORDER;
    var Fill:= if IsEp then END_FILL else MID_FILL;
    var Role:= if H = 0 then 'from' else if H = pL then 'to' else 'hop ' + IntToStr(H);
    var Cl:= if H = 0 then 'cluster_focus_from' else if H = pL then 'cluster_focus_to' else 'cluster_hop_' + IntToStr(Nid);
    var Pen:= if IsEp then PEN_END else PEN_MID;
    Inc(pClicks);
    pSb.AppendLine(Format('  subgraph %s {', [Cl]));
    pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=%d;', [Border, Fill, Pen]));
    pSb.AppendLine('    label=""; margin=10;');
    pSb.AppendLine(Format('    r%d [label=<%s>];', [Nid, NodeTable(pGraph.Name[Id], Role, pLoc[Id], IsEp)]));
    pSb.AppendLine('  }');
  end;
end;

// the Legend: how many, what the grades mean, what was left out (PS 216-227)
function LegendTable(pTotal: Int64; pL, pSiteRows, pHidden: Integer): string;
begin
  var Leg:= TStringBuilder.Create;
  try
    Leg.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="2" CELLPADDING="4">');
    Leg.Append(Format('<TR><TD ALIGN="LEFT"><FONT FACE="%s" POINT-SIZE="13"><B>Legend</B></FONT></TD></TR>', [FONT_SANS]));
    AddDisclosureRow(Leg, Format('%d shortest path(s) of %d call(s) each, %d call site(s) on them -- found by engine call-path, ' +
      'every route enumerated over the same resolved call_edges', [pTotal, pL, pSiteRows]));
    AddDisclosureRow(Leg, 'each arrow: one call, labelled with every call site (file:line) and its grade -- certain = bound to this routine; ' +
      'ambiguous = bound, more than one candidate on the type chain');
    AddDisclosureRow(Leg, 'a call the index matched by name alone has no call_edges row, so call-path never walks it');
    var Noun:= if pHidden = 1 then 'shortest path' else 'shortest paths';
    var Disc:= DisclosureText(pHidden, 0, Noun);
    if Disc <> '' then
      AddDisclosureRow(Leg, Disc, AMB_INK);
    Leg.Append('</TABLE>');
    Result:= Leg.ToString;
  finally
    Leg.Free;
  end;
end;

// one arrow per drawn pair, labelled with every call site and its grade (PS 230-246)
procedure AppendEdges(pSb: TStringBuilder; pGraph: TPathGraph; pPairKeys: TList<string>;
  pNodeOf: TDictionary<Int64, string>; var pSiteCount, pAmbCount, pClicks: Integer);
begin
  for var Key in pPairKeys do
  begin
    var Pr:= pGraph.Pairs[Key];
    var Et:= TStringBuilder.Create;
    try
      Et.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="2" BGCOLOR="#FFFFFF">');
      var AnyCertain:= False;
      for var S in Pr.Sites do
      begin
        Inc(pSiteCount);
        var Amb:= not SameText(S.Grade, 'certain');
        if Amb then
          Inc(pAmbCount)
        else
          AnyCertain:= True;
        var Leaf:= FileNameOf(S.FilePath);
        var Tip:= XmlText(Format('%s -> %s (%s)  --  %s:%d', [pGraph.Name[Pr.Src], pGraph.Name[Pr.Dst], S.Grade, Leaf, S.Line]));
        var Ink:= if Amb then AMB_INK else ROW_INK;
        Et.Append(Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s">%s &#183; %s</FONT></TD></TR>',
          [RowHref(S.FilePath, S.Line), Tip, Ink, XmlText(Format('%s:%d', [Leaf, S.Line])), XmlText(S.Grade)]));
        Inc(pClicks);
      end;
      Et.Append('</TABLE>');
      var Style:= if AnyCertain then '' else ', style=dashed';
      pSb.AppendLine(Format('  %s -> %s [label=<%s>%s];', [pNodeOf[Pr.Src], pNodeOf[Pr.Dst], Et.ToString, Style]));
    finally
      Et.Free;
    end;
  end;
end;

// the METHOD name only: the last '.'-segment (PS 253)
function LastSegment(const pQ: string): string;
begin
  Result:= pQ.Substring(pQ.LastIndexOf('.') + 1);
end;

/// <summary>Answers `path` for pArgs.Target -> the -To routine (Emit-Path.ps1).</summary>
/// <param name="pArgs">The question; Target is routine A, Command.Get('To') routine B, Cap the number of shortest paths drawn.</param>
/// <param name="pOutDir">The bundle folder the layout files go to.</param>
/// <returns>The chart: LeftCount the number of shortest paths, RightCount the calls on each; the
/// fields are Paths, PathsShown, Hops, Routines, Edges, Sites, Ambiguous, EnginePath, ClickTargets,
/// Expected, AllClickable and the three export sizes.</returns>
/// <exception cref="EChartsQuestion">-To is blank; A = B; an end is not in the index or names several symbols;
/// no path within PATH_MAX_DEPTH calls; the engine's path and the recursive query disagree.</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one
/// file). The cap is exact: every path left out is counted and disclosed in the Legend.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var ToQ:= pArgs.Command.Get('To');
  if ToQ = '' then
    raise EChartsQuestion.Create('path needs -To: the routine the path ends at (-Target is where it starts), both qualified (Unit.Class.Method)');
  var From:= pArgs.Target;
  if SameText(From, ToQ) then
    raise EChartsQuestion.CreateFmt('path: name two different routines -- -From and -To are both %s', [From]);
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Graph: TPathGraph:= nil;
  var Ids:= TList<Int64>.Create;
  var PairKeys:= TList<string>.Create;
  var NodeOf:= TDictionary<Int64, string>.Create;
  var Loc: TDictionary<Int64, TPathLoc>:= nil;
  var Sb:= TStringBuilder.Create;
  try
    { ---- 0. the selection ---- }
    CheckEnd(Index, From);
    CheckEnd(Index, ToQ);

    { ---- 1. the engine decides: found, and how long ---- }
    var EnginePathNames:= EnginePath(Store, From, ToQ, PATH_MAX_DEPTH);
    if Length(EnginePathNames) = 0 then
      raise EChartsQuestion.CreateFmt('no call path from %s to %s within %d calls (engine call-path, found:false). ' +
        'call-path walks the resolved call_edges only, so a call the index matched by name alone is not followed.', [From, ToQ, PATH_MAX_DEPTH]);
    var L:= Length(EnginePathNames) - 1;
    if L < 1 then
      raise EChartsQuestion.CreateFmt('call-path returned a path of %d routine(s) for two different routines -- engine defect', [Length(EnginePathNames)]);

    { ---- 2. every shortest path, over the same call_edges ---- }
    var SiteRows:= Index.AllRows(CtePrefix(From, ToQ, L) + SiteSelect(L), 'hop, src, dst, src_id, dst_id, line, ref_id');
    try
      if SiteRows.Count = 0 then
        raise EChartsQuestion.CreateFmt('call-path found a %d-call path but call_edges hold no call on any shortest path -- ' +
          'the two disagree (engine defect; nothing drawn)', [L]);
      CheckDistance(Index, From, ToQ, L);
      Graph:= TPathGraph.Create(L, pArgs.Cap);
      for var R in SiteRows do
        Graph.AddRow(R);
      Graph.CheckEnginePath(EnginePathNames);
      Graph.Enumerate;
      CollectDrawn(Graph, Ids, PairKeys);
      Loc:= LocateRoutines(Index, Ids);

      { ---- 4. dot ---- }
      Sb.AppendLine('digraph path {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.45; ranksep=1.3; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');
      var Clicks:= 0;
      AppendNodes(Sb, Graph, Ids, Loc, L, NodeOf, Clicks);
      var Hidden:= Integer(Graph.Total - Graph.Shown.Count);
      Sb.AppendLine(Format('  legend [label=<%s>];', [LegendTable(Graph.Total, L, SiteRows.Count, Hidden)]));
      Sb.AppendLine('');
      var SiteCount:= 0;
      var AmbCount:= 0;
      AppendEdges(Sb, Graph, PairKeys, NodeOf, SiteCount, AmbCount, Clicks);
      Sb.AppendLine('}');

      { ---- 5. lay out ---- }
      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace('path_' + LastSegment(From) + '__' + LastSegment(ToQ), '[^A-Za-z0-9_]', '_');
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
      Result.LeftCount:= Graph.Total;
      Result.RightCount:= L;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Clicks;
      Result.Fields:= [TMetaField.Int('Paths', Graph.Total), TMetaField.Int('PathsShown', Graph.Shown.Count),
        TMetaField.Int('Hops', L), TMetaField.Int('Routines', Ids.Count), TMetaField.Int('Edges', PairKeys.Count),
        TMetaField.Int('Sites', SiteCount), TMetaField.Int('Ambiguous', AmbCount),
        TMetaField.Str('EnginePath', string.Join(' -> ', EnginePathNames)),
        TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Clicks),
        TMetaField.Bool('AllClickable', Result.AllClickable),
        TMetaField.Int('ExportSvg', FileSizeOf(Result.Layout.Svg)),
        TMetaField.Int('ExportPng', FileSizeOf(Result.Layout.Png)),
        TMetaField.Int('ExportPdf', FileSizeOf(Result.Layout.Pdf))];
    finally
      SiteRows.Free;
    end;
  finally
    Sb.Free;
    Loc.Free;
    NodeOf.Free;
    PairKeys.Free;
    Ids.Free;
    Graph.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(PATH_ID, Emit);

end.
