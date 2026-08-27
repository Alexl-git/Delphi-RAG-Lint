unit DRagLint.Report.Deps;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Interfaces;

type
  /// <summary>Display bucket for an external (non-project) unit dependency.
  /// dgUnknown = unresolved/not-indexed unit whose name matched no known
  /// group; dgOther = resolved to a library file that matched no known
  /// group.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoDepsReport.RenderText (DRagLint.CLI.pas), declaration (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.BuildDepsReport (DRagLint.Report.Deps.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsGroup = (dgRTL, dgDevExpress, dgSpring4D, dgFireDAC, dgOther, dgUnknown);

  /// <summary>Per-external-unit rollup: which project units import it, in
  /// which sections, whether the index resolved it to an actual library
  /// file, and the shortest import chain from any project source.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.BuildDepsReport (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsExternal = record
    /// <summary>Verbatim external unit name as it appears in the uses clause.</summary>
    UnitName: string;
    /// <summary>Display group this unit was classified into.</summary>
    Group: TDepsGroup;
    /// <summary>True when the index resolved this unit to a library file;
    /// False when it is unresolved/not indexed.</summary>
    Resolved: Boolean;
    /// <summary>Full distinct-project-unit count that imports this external,
    /// NOT capped by AMaxList (unlike UsedBy).</summary>
    UsedByCount: Integer;
    /// <summary>Importing project units, sorted ascending, capped at
    /// AOpts.MaxList entries.</summary>
    UsedBy: TArray<string>;
    /// <summary>Count of importing project units beyond the UsedBy cap;
    /// 0 when UsedByCount &lt;= AOpts.MaxList.</summary>
    UsedByMore: Integer;
    /// <summary>Shortest BFS chain from a project source to this external
    /// unit, '&gt;'-joined (e.g. 'ProjUnit&gt;Mid&gt;ExternalUnit').</summary>
    ShortestPath: string;
    /// <summary>Distinct uses-clause sections this external is imported in
    /// ('interface'/'implementation'/'program'/'package').</summary>
    Sections: TArray<string>;
  end;

  /// <summary>One project-unit -&gt; external-unit uses edge.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.NoteEdgeIfExternal (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.BuildDepsReport (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsEdge = record
    /// <summary>Importing project unit (verbatim uses-clause name of the
    /// source file's own unit, i.e. the file's stem).</summary>
    SourceUnit: string;
    /// <summary>Verbatim external unit name being imported.</summary>
    ExternalUnit: string;
    /// <summary>Display group of ExternalUnit.</summary>
    Group: TDepsGroup;
    /// <summary>Uses-clause section this edge occurs in.</summary>
    Section: string;
    /// <summary>True when the index resolved ExternalUnit to a library file.</summary>
    Resolved: Boolean;
  end;

  /// <summary>Per-group rollup: total distinct external units in the group,
  /// and how many distinct project units depend on at least one of them.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsGroupCount = record
    Group: TDepsGroup;
    UnitCount: Integer;
    ProjectUnitCount: Integer;
  end;

  /// <summary>Whole-report totals.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsSummary = record
    /// <summary>Distinct external units across the whole report.</summary>
    ExternalUnitCount: Integer;
    /// <summary>Distinct (project unit -&gt; external unit) edges.</summary>
    ExternalEdgeCount: Integer;
    /// <summary>External units NOT resolved to a library file in the index.</summary>
    UnresolvedCount: Integer;
    /// <summary>Per-group counts, one entry per TDepsGroup value present.</summary>
    GroupCounts: TArray<TDepsGroupCount>;
  end;

  /// <summary>Full third-party dependency report: summary totals, the
  /// per-external rollup, and the flat edge list.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoDepsReport (DRagLint.CLI.pas), declaration (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsReport = record
    Summary: TDepsSummary;
    /// <summary>Sorted: group ascending, then UsedByCount descending, then
    /// name ascending.</summary>
    Externals: TArray<TDepsExternal>;
    /// <summary>Sorted: source unit ascending, then external unit ascending.</summary>
    Edges: TArray<TDepsEdge>;
  end;

  /// <summary>Tuning knobs for BuildDepsReport.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoDepsReport (DRagLint.CLI.pas), declaration (DRagLint.Report.Deps.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Report.Deps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDepsOptions = record
    /// <summary>BFS depth cap for shortest-path computation. Default 3.</summary>
    Depth: Integer;
    /// <summary>When True, every store's files are eligible project sources;
    /// when False (default), only the first store (AStores[0]) is.</summary>
    AllSources: Boolean;
    /// <summary>Case-insensitive substring filter on the project source's
    /// file stem; '' (default) means no filtering.</summary>
    NamePattern: string;
    /// <summary>Cap for each external's UsedBy list. Default 20.</summary>
    MaxList: Integer;
  end;

/// <summary>True when APath is a Delphi library/RTL/3rd-party path (lowercased
/// path contains '\embarcadero\', '\program files', or '\dcc\'). The canonical
/// project-vs-library path test; shared with find-unit.</summary>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: (Pos('\embarcadero\', L) &gt; 0)
/// or (Pos('\program files', L) &gt; 0) or (Pos('\dcc\', L) &gt; 0).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.Deps.BuildDepsReport (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.NoteEdgeIfExternal (DRagLint.Report.Deps.pas), DRagLint.Report.Deps.WalkBfs (DRagLint.Report.Deps.pas)</para>
/// <para>Calls: LowerCase, Pos</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsLibraryPath(const APath: string): Boolean;

/// <summary>Classifies an external unit into a display group by resolved library
/// path root first, then unit-name prefix (cx*/dx*/dxBar*->DevExpress; Spring.*->
/// Spring4D; FireDAC.*->FireDAC; System/Winapi/Vcl/FMX/Data/Soap/Xml->RTL).</summary>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <param name="AResolvedPath"><!-- drag-lint:auto type -->const string</param>
/// <param name="AResolved"><!-- drag-lint:auto type -->Boolean</param>
/// <returns><!-- drag-lint:auto -->TDepsGroup -- Observed: dgUnknown; dgRTL;
/// dgDevExpress; dgSpring4D; ClassifyByName(AUnitName); dgOther.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.Deps.NoteEdgeIfExternal (DRagLint.Report.Deps.pas)</para>
/// <para>Calls: DRagLint.Report.Deps.ClassifyByName, LowerCase, Pos</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 17 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Report.Deps.ClassifyByName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ClassifyDepsGroup(const AUnitName, AResolvedPath: string; AResolved: Boolean): TDepsGroup;

/// <summary>Lowercase group label for output ('RTL','DevExpress','Spring4D',
/// 'FireDAC','other','unknown').</summary>
/// <param name="AGroup"><!-- drag-lint:auto type -->TDepsGroup</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: 'RTL'; 'DevExpress'; 'Spring4D';
/// 'FireDAC'; 'other'; 'unknown'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoDepsReport.RenderCsv (DRagLint.CLI.pas), DRagLint.CLI.DoDepsReport.RenderJson (DRagLint.CLI.pas), DRagLint.CLI.DoDepsReport.RenderText (DRagLint.CLI.pas)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DepsGroupStr(AGroup: TDepsGroup): string;

/// <summary>Builds the third-party dependency report from the index's uses-graph.
/// Borrows AStores (does not open/free them). Classifies each used unit as project
/// vs external (unresolved OR library-path), groups externals, and computes the
/// per-external rollup + the flat edge list + summary. No I/O.</summary>
/// <param name="AStores"><!-- drag-lint:auto type -->const TArray&lt;ISymbolStore&gt;</param>
/// <param name="AOpts"><!-- drag-lint:auto type -->const TDepsOptions</param>
/// <returns><!-- drag-lint:auto type -->TDepsReport</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoDepsReport (DRagLint.CLI.pas)</para>
/// <para>Calls: CompareText, Copy, DRagLint.Report.Deps.GroupOrd, DRagLint.Report.Deps.IsLibraryPath, DRagLint.Report.Deps.LoadFilesAndEdges, DRagLint.Report.Deps.WalkBfs, LowerCase, Pos</para>
/// <para>Complexity: 30 (cyclomatic, outer body), 181 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Report.Deps.GroupOrd"/>
/// <seealso cref="DRagLint.Report.Deps.IsLibraryPath"/>
/// <seealso cref="DRagLint.Report.Deps.LoadFilesAndEdges"/>
/// <seealso cref="DRagLint.Report.Deps.WalkBfs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildDepsReport(const AStores: TArray<ISymbolStore>;
  const AOpts: TDepsOptions): TDepsReport;

implementation

uses
  Data.DB, FireDAC.Comp.Client,
  DRagLint.Storage.SQLite;

const
  DEFAULT_DEPTH   = 3;
  DEFAULT_MAXLIST = 20;

type
  { Mirrors DoUsesReport's TUsesEdge (CLI.pas:5434): one raw unit_uses row,
    resolved to a global file index (or -1 for external/unresolved). }
  TDepsUsesEdge = record
    UnitName    : string; { verbatim }
    UnitNameNorm: string; { lowercase trailing segment }
    TargetFileId: Int64 ; { -1 = external/unresolved; else index into AllFiles }
    Section     : string; { 'interface'|'implementation'|'program'|'package' }
  end;

  { Mirrors DoUsesReport's TFileMeta (CLI.pas:5441): one file across all
    borrowed stores, keyed globally so cross-store edges can be resolved. }
  TDepsFileMeta = record
    Path      : string ; { as stored }
    Stem      : string ; { lowercase basename without extension }
    StoreIndex: Integer; { which AStores[i] this file came from }
    FileId    : Int64  ; { id INSIDE that store }
  end;

  { Mirrors DoUsesReport's TBfsQueueItem (CLI.pas:5448). }
  TDepsBfsItem = record
    FileId      : Int64  ;
    Depth       : Integer;
    UsedUnit    : string ;
    UnitNameNorm: string ;
    Via         : string ; { chain so far, '>' separated, excludes self }
    External    : Boolean;
  end;

  { Accumulator for one external unit while walking edges. }
  TDepsExtAcc = class
  public
    UnitName   : string;
    Resolved   : Boolean;
    Group      : TDepsGroup;
    UsedBySet  : TDictionary<string, Boolean>; { project unit stem -> True }
    SectionsSet: TDictionary<string, Boolean>;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDepsExtAcc.Create;
begin
  inherited Create;
  UsedBySet  := TDictionary<string, Boolean>.Create;
  SectionsSet:= TDictionary<string, Boolean>.Create;
end;

destructor TDepsExtAcc.Destroy;
begin
  UsedBySet.Free;
  SectionsSet.Free;
  inherited;
end;

function IsLibraryPath(const APath: string): Boolean;
var
  L: string;
begin
  L:= LowerCase(APath);
  Result:= (Pos('\embarcadero\', L) > 0) or (Pos('\program files', L) > 0) or (Pos('\dcc\', L) > 0);
end;

{ Classifies by unit-NAME prefix only (used both as the primary signal for
  unresolved units and as the fallback for resolved-but-path-unmatched units). }
function ClassifyByName(const AUnitName: string): TDepsGroup;
var
  N: string;
begin
  N:= LowerCase(AUnitName);
  if (Pos('cx', N) = 1) or (Pos('dx', N) = 1) then Result:= dgDevExpress
  else if Pos('spring.', N) = 1 then Result:= dgSpring4D
  else if Pos('firedac.', N) = 1 then Result:= dgFireDAC
  else if (Pos('system.', N) = 1) or (Pos('winapi.', N) = 1) or (Pos('vcl.', N) = 1) or
          (Pos('fmx.', N) = 1) or (Pos('data.', N) = 1) or (Pos('soap.', N) = 1) or
          (Pos('xml.', N) = 1) or (Pos('web.', N) = 1) then Result:= dgRTL
  else Result:= dgUnknown; { caller downgrades to dgOther when AResolved }
end;

function ClassifyDepsGroup(const AUnitName, AResolvedPath: string; AResolved: Boolean): TDepsGroup;
var
  L: string;
begin
  Result:= dgUnknown;
  if AResolved and (AResolvedPath <> '') then
  begin
    L:= LowerCase(AResolvedPath);
    if (Pos('\embarcadero\', L) > 0) or (Pos('\dcc\', L) > 0) then Result:= dgRTL
    else if (Pos('devexpress', L) > 0) or (Pos('dev express', L) > 0) or (Pos('\cxlib', L) > 0) then Result:= dgDevExpress
    else if Pos('spring', L) > 0 then Result:= dgSpring4D;
  end;

  if Result = dgUnknown then Result:= ClassifyByName(AUnitName);

  { Resolved-but-unmatched -> dgOther; unresolved-unmatched stays dgUnknown. }
  if (Result = dgUnknown) and AResolved then Result:= dgOther;
end;

function DepsGroupStr(AGroup: TDepsGroup): string;
begin
  case AGroup of
    dgRTL      : Result:= 'RTL';
    dgDevExpress: Result:= 'DevExpress';
    dgSpring4D : Result:= 'Spring4D';
    dgFireDAC  : Result:= 'FireDAC';
    dgOther    : Result:= 'other';
  else
    Result:= 'unknown';
  end;
end;

function GroupOrd(AGroup: TDepsGroup): Integer;
begin
  Result:= Ord(AGroup);
end;

{ Mirrors DoUsesReport's ComputeStem (CLI.pas:5486): lowercase basename
  without extension, used both as the file-map key and as the fallback
  cross-store unit_name_norm -> file resolution. }
function ComputeStem(const APath: string): string;
var
  Dot: Integer;
begin
  Result:= LowerCase(ExtractFileName(APath));
  Dot:= System.SysUtils.LastDelimiter('.', Result);
  if Dot > 0 then Result:= Copy(Result, 1, Dot - 1);
end;

{ Loads every non-DFM/JSON/text file across AStores into AllFiles, building
  StemToGlobal (first-store-wins) and the per-source-file unit_uses edge
  lists. Mirrors DoUsesReport's OpenStores-adjacent LoadFilesAndEdges
  (CLI.pas:5502), except it borrows AStores instead of opening them, and
  queries unit_uses/files directly via each store's GetConnection -- the
  same raw-SQL access DoUsesReport uses, since ISymbolStore's
  GetUnitUsesForFile does not carry target_file_id/unit_name_norm. }
procedure LoadFilesAndEdges(const AStores: TArray<ISymbolStore>;
  out AAllFiles: TList<TDepsFileMeta>;
  out AStemToGlobal: TDictionary<string, Integer>;
  out AEdges: TDictionary<Integer, TArray<TDepsUsesEdge>>);
var
  StoreIdx      : Integer                                   ;
  QFiles        : TFDQuery                                  ;
  QUses         : TFDQuery                                  ;
  SQLiteStore   : TSQLiteSymbolStore                        ;
  Meta          : TDepsFileMeta                             ;
  PathStr       : string                                    ;
  LocalFileId   : Int64                                     ;
  GlobalIdx     : Integer                                   ;
  FileIdToGlobal: TDictionary<Int64, Integer>               ;
  PerStore      : TDictionary<Integer, TList<TDepsUsesEdge>>;
  TargetFid     : Int64                                     ;
  TargetGlobal  : Integer                                   ;
  Edge          : TDepsUsesEdge                             ;
  Kv            : TPair<Integer, TList<TDepsUsesEdge>>      ;
begin
  AAllFiles    := TList<TDepsFileMeta>.Create;
  AStemToGlobal:= TDictionary<string, Integer>.Create;
  AEdges       := TDictionary<Integer, TArray<TDepsUsesEdge>>.Create;
  PerStore     := TDictionary<Integer, TList<TDepsUsesEdge>>.Create;
  try
    { Step 1: gather every file across every store, build stem -> global index. }
    for StoreIdx:= 0 to High(AStores) do
    begin
      SQLiteStore:= TSQLiteSymbolStore(AStores[StoreIdx]);
      QFiles:= TFDQuery.Create(nil);
      try
        QFiles.Connection:= SQLiteStore.GetConnection;
        QFiles.Sql.Text:= 'SELECT id, path FROM files WHERE language NOT IN (''dfm'', ''json'', ''text'')';
        QFiles.Open;
        while not QFiles.Eof do
        begin
          PathStr:= QFiles.FieldByName('path').AsString;
          Meta.Path:= PathStr;
          Meta.Stem:= ComputeStem(PathStr);
          Meta.StoreIndex:= StoreIdx;
          Meta.FileId:= QFiles.FieldByName('id').AsLargeInt;
          AAllFiles.Add(Meta);
          { First-write-wins: first --db takes priority, matching DoUsesReport. }
          if not AStemToGlobal.ContainsKey(Meta.Stem) then AStemToGlobal.Add(Meta.Stem, AAllFiles.Count - 1);
          QFiles.Next;
        end;
      finally
        QFiles.Free;
      end;
    end;

    { Step 2: gather every unit_uses edge, group by global source file index. }
    FileIdToGlobal:= TDictionary<Int64, Integer>.Create;
    try
      for GlobalIdx:= 0 to AAllFiles.Count - 1 do
        FileIdToGlobal.AddOrSetValue(
          (Int64(AAllFiles[GlobalIdx].StoreIndex) shl 40) or Int64(AAllFiles[GlobalIdx].FileId), GlobalIdx);

      for StoreIdx:= 0 to High(AStores) do
      begin
        SQLiteStore:= TSQLiteSymbolStore(AStores[StoreIdx]);
        QUses:= TFDQuery.Create(nil);
        try
          QUses.Connection:= SQLiteStore.GetConnection;
          QUses.Sql.Text:= 'SELECT file_id, unit_name, unit_name_norm, section, target_file_id FROM unit_uses';
          QUses.Open;
          while not QUses.Eof do
          begin
            LocalFileId:= QUses.FieldByName('file_id').AsLargeInt;
            if not FileIdToGlobal.TryGetValue((Int64(StoreIdx) shl 40) or LocalFileId, GlobalIdx) then
            begin
              QUses.Next;
              Continue;
            end;

            Edge.UnitName    := QUses.FieldByName('unit_name'     ).AsString;
            Edge.UnitNameNorm:= QUses.FieldByName('unit_name_norm').AsString;
            Edge.Section     := QUses.FieldByName('section'       ).AsString;
            { Resolve target: prefer the in-DB target_file_id; fall back to
              cross-DB lookup by stem -- same precedence as DoUsesReport. }
            Edge.TargetFileId:= -1;
            if not QUses.FieldByName('target_file_id').IsNull then
            begin
              TargetFid:= QUses.FieldByName('target_file_id').AsLargeInt;
              if FileIdToGlobal.TryGetValue((Int64(StoreIdx) shl 40) or TargetFid, TargetGlobal) then
                Edge.TargetFileId:= TargetGlobal;
            end;
            { v(ADP3 T4f, register K39): full stem first, dotted tail second --
              the same two-pass order ResolveUnitUseTargets uses, and the same
              fix as DoUsesReport's copy of this fallback. AStemToGlobal is keyed
              on the FULL lowercased basename stem, so looking it up with
              UnitNameNorm (the dotted TAIL) could never hit for a dotted unit:
              the tail-vs-stem mismatch T4d fixed in the live path, surviving in
              the cross-DB fallback that runs exactly when target_file_id is NULL. }
            if Edge.TargetFileId = -1 then
              if AStemToGlobal.TryGetValue(LowerCase(Edge.UnitName), TargetGlobal) then Edge.TargetFileId:= TargetGlobal
              else if AStemToGlobal.TryGetValue(Edge.UnitNameNorm, TargetGlobal) then Edge.TargetFileId:= TargetGlobal;

            if not PerStore.ContainsKey(GlobalIdx) then PerStore.Add(GlobalIdx, TList<TDepsUsesEdge>.Create);
            PerStore[GlobalIdx].Add(Edge);

            QUses.Next;
          end;
        finally
          QUses.Free;
        end;
      end;
    finally
      FileIdToGlobal.Free;
    end;

    for Kv in PerStore do AEdges.AddOrSetValue(Kv.Key, Kv.Value.ToArray);
  finally
    for Kv in PerStore do Kv.Value.Free;
    PerStore.Free;
  end;
end;

{ Records/updates the shortest '>'-joined chain reaching AUnitNameNorm, keyed
  directly by the external's normalized unit name (hop-count compared via
  the chain's own '>' count, not string length -- so a short unit name at a
  deeper hop never masquerades as "shorter" than a longer one at a shallower
  hop). AChain excludes the final external unit name; AFullChain includes it. }
procedure NoteShortestPath(const AShortestPath: TDictionary<string, string>;
  const AUnitNameNorm, AFullChain: string);
var
  Existing: string;
  NewHops , OldHops: Integer;
  C: Char;
begin
  if AShortestPath.TryGetValue(AUnitNameNorm, Existing) then
  begin
    NewHops:= 0;
    for C in AFullChain do if C = '>' then Inc(NewHops);
    OldHops:= 0;
    for C in Existing do if C = '>' then Inc(OldHops);
    if NewHops < OldHops then AShortestPath[AUnitNameNorm]:= AFullChain;
  end
  else AShortestPath.Add(AUnitNameNorm, AFullChain);
end;

{ Classifies one uses-edge, accumulating into AExternals/AEdgeList/
  AShortestPath when it is an external dependency (skips project-to-project
  edges). Shared by both the depth-1 seed loop and the BFS continuation in
  WalkBfs below. }
procedure NoteEdgeIfExternal(const AAllFiles: TList<TDepsFileMeta>;
  const AExternals: TObjectDictionary<string, TDepsExtAcc>;
  const AEdgeList: TList<TDepsEdge>;
  const AShortestPath: TDictionary<string, string>;
  const ASourceStem: string; const AEdge: TDepsUsesEdge; const AFullChain: string);
var
  Acc         : TDepsExtAcc;
  DepsEdge    : TDepsEdge;
  Resolved    : Boolean;
  ResolvedPath: string;
begin
  Resolved    := AEdge.TargetFileId >= 0;
  ResolvedPath:= '';
  if Resolved then ResolvedPath:= AAllFiles[AEdge.TargetFileId].Path;

  { Skip project-to-project edges entirely (not external deps). A resolved
    target is "project" when it is NOT a library path. }
  if Resolved and (not IsLibraryPath(ResolvedPath)) then Exit;

  if not AExternals.TryGetValue(AEdge.UnitNameNorm, Acc) then
  begin
    Acc:= TDepsExtAcc.Create;
    Acc.UnitName:= AEdge.UnitName;
    Acc.Resolved:= Resolved;
    Acc.Group   := ClassifyDepsGroup(AEdge.UnitName, ResolvedPath, Resolved);
    AExternals.Add(AEdge.UnitNameNorm, Acc);
  end;
  Acc.UsedBySet.AddOrSetValue(ASourceStem, True);
  Acc.SectionsSet.AddOrSetValue(LowerCase(AEdge.Section), True);

  DepsEdge.SourceUnit  := ASourceStem;
  DepsEdge.ExternalUnit:= AEdge.UnitName;
  DepsEdge.Group       := Acc.Group;
  DepsEdge.Section     := LowerCase(AEdge.Section);
  DepsEdge.Resolved    := Resolved;
  AEdgeList.Add(DepsEdge);

  NoteShortestPath(AShortestPath, AEdge.UnitNameNorm, AFullChain);
end;

{ BFS from ASourceIdx over AEdges up to AMaxDepth, recording the shortest
  '>'-joined chain to each externally-classified unit reached (keyed by
  UnitNameNorm in AShortestPath) and feeding accumulator state (UsedBy/
  Sections/edges) into AExternals/AEdgeList. Mirrors DoUsesReport's WalkBfs
  (CLI.pas:5621); the direct edge is always depth 1 since the unit only
  appears when imported. }
procedure WalkBfs(const AAllFiles: TList<TDepsFileMeta>;
  const AEdges: TDictionary<Integer, TArray<TDepsUsesEdge>>;
  ASourceIdx: Integer; AMaxDepth: Integer;
  const AExternals: TObjectDictionary<string, TDepsExtAcc>;
  const AEdgeList: TList<TDepsEdge>;
  const AShortestPath: TDictionary<string, string>);
var
  Queue     : TQueue<TDepsBfsItem>;
  Visited   : TDictionary<string, Boolean>;
  Item      : TDepsBfsItem;
  Nx        : TDepsBfsItem;
  Edge      : TDepsUsesEdge;
  EdgeList  : TArray<TDepsUsesEdge>;
  SourceMeta: TDepsFileMeta;
  NextVia   : string;
  IsProjSrc : Boolean;
begin
  Queue  := TQueue<TDepsBfsItem>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  try
    SourceMeta:= AAllFiles[ASourceIdx];

    if AEdges.TryGetValue(ASourceIdx, EdgeList) then
      for Edge in EdgeList do
      begin
        if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
        Item.FileId      := Edge.TargetFileId;
        Item.Depth       := 1;
        Item.UsedUnit    := Edge.UnitName;
        Item.UnitNameNorm:= Edge.UnitNameNorm;
        Item.Via         := '';
        Item.External    := (Edge.TargetFileId < 0);
        Queue.Enqueue(Item);

        { The direct edge is always a project-source-file emission point:
          classify + accumulate it here regardless of whether BFS continues
          past it, mirroring how DoUsesReport emits the depth-1 row. }
        NoteEdgeIfExternal(AAllFiles, AExternals, AEdgeList, AShortestPath,
          SourceMeta.Stem, Edge, SourceMeta.Stem + '>' + Edge.UnitName);
      end;

    while Queue.Count > 0 do
    begin
      Item:= Queue.Dequeue;
      if Visited.ContainsKey(Item.UnitNameNorm) then Continue;
      Visited.Add(Item.UnitNameNorm, True);

      if Item.External then Continue; { external units are not walked further }
      if Item.Depth >= AMaxDepth then Continue;

      { Only continue BFS through project files (external/library targets
        are dead ends for further transitive discovery here). }
      IsProjSrc:= (Item.FileId >= 0) and (Item.FileId < AAllFiles.Count) and
        (not IsLibraryPath(AAllFiles[Item.FileId].Path));
      if not IsProjSrc then Continue;
      if not AEdges.TryGetValue(Integer(Item.FileId), EdgeList) then Continue;

      if Item.Via = '' then NextVia:= SourceMeta.Stem + '>' + Item.UsedUnit
      else NextVia:= Item.Via + '>' + Item.UsedUnit;

      for Edge in EdgeList do
      begin
        if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
        Nx.FileId      := Edge.TargetFileId;
        Nx.Depth       := Item.Depth + 1;
        Nx.UsedUnit    := Edge.UnitName;
        Nx.UnitNameNorm:= Edge.UnitNameNorm;
        Nx.Via         := NextVia;
        Nx.External    := (Edge.TargetFileId < 0);
        Queue.Enqueue(Nx);

        NoteEdgeIfExternal(AAllFiles, AExternals, AEdgeList, AShortestPath,
          SourceMeta.Stem, Edge, NextVia + '>' + Edge.UnitName);
      end;
    end;
  finally
    Visited.Free;
    Queue.Free;
  end;
end;

function BuildDepsReport(const AStores: TArray<ISymbolStore>;
  const AOpts: TDepsOptions): TDepsReport;
var
  AllFiles    : TList<TDepsFileMeta>;
  StemToGlobal: TDictionary<string, Integer>;
  Edges       : TDictionary<Integer, TArray<TDepsUsesEdge>>;
  Externals   : TObjectDictionary<string, TDepsExtAcc>;
  EdgeList    : TList<TDepsEdge>;
  ShortestPath: TDictionary<string, string>;
  MaxDepth    : Integer;
  MaxList     : Integer;
  NamePatLower: string;
  GlobalIdx   : Integer;
  SourceMeta  : TDepsFileMeta;
  ExtNorm     : string;
  Acc         : TDepsExtAcc;
  ExtOut      : TArray<TDepsExternal>;
  ExtRec      : TDepsExternal;
  ExtCount    : Integer;
  UsedByArr   : TArray<string>;
  GroupTally  : array[TDepsGroup] of TDepsGroupCount;
  G           : TDepsGroup;
  ProjUnitsPerGroup: array[TDepsGroup] of TDictionary<string, Boolean>;
  EdgeArr     : TArray<TDepsEdge>;
  i           : Integer;
begin
  MaxDepth:= AOpts.Depth;
  if MaxDepth <= 0 then MaxDepth:= DEFAULT_DEPTH;
  MaxList:= AOpts.MaxList;
  if MaxList <= 0 then MaxList:= DEFAULT_MAXLIST;
  NamePatLower:= LowerCase(AOpts.NamePattern);

  Result.Summary.ExternalUnitCount:= 0;
  Result.Summary.ExternalEdgeCount:= 0;
  Result.Summary.UnresolvedCount  := 0;
  Result.Summary.GroupCounts      := nil;
  Result.Externals:= nil;
  Result.Edges    := nil;

  if Length(AStores) = 0 then Exit;

  AllFiles    := nil;
  StemToGlobal:= nil;
  Edges       := nil;
  Externals   := nil;
  EdgeList    := nil;
  ShortestPath:= nil;
  for G:= Low(TDepsGroup) to High(TDepsGroup) do ProjUnitsPerGroup[G]:= nil;
  try
    LoadFilesAndEdges(AStores, AllFiles, StemToGlobal, Edges);

    Externals   := TObjectDictionary<string, TDepsExtAcc>.Create([doOwnsValues]);
    EdgeList    := TList<TDepsEdge>.Create;
    ShortestPath:= TDictionary<string, string>.Create;

    for GlobalIdx:= 0 to AllFiles.Count - 1 do
    begin
      SourceMeta:= AllFiles[GlobalIdx];
      { Project source = first store (or any store when AllSources), NOT a
        library path, matching NamePattern if set. }
      if (not AOpts.AllSources) and (SourceMeta.StoreIndex <> 0) then Continue;
      if IsLibraryPath(SourceMeta.Path) then Continue;
      if (NamePatLower <> '') and (Pos(NamePatLower, SourceMeta.Stem) = 0) then Continue;
      WalkBfs(AllFiles, Edges, GlobalIdx, MaxDepth, Externals, EdgeList, ShortestPath);
    end;

    { Build Externals output array from the accumulator. }
    SetLength(ExtOut, Externals.Count);
    ExtCount:= 0;
    for G:= Low(TDepsGroup) to High(TDepsGroup) do ProjUnitsPerGroup[G]:= TDictionary<string, Boolean>.Create;
    for G:= Low(TDepsGroup) to High(TDepsGroup) do
    begin
      GroupTally[G].Group           := G;
      GroupTally[G].UnitCount       := 0;
      GroupTally[G].ProjectUnitCount:= 0;
    end;

    for ExtNorm in Externals.Keys do
    begin
      Acc:= Externals[ExtNorm];

      SetLength(UsedByArr, Acc.UsedBySet.Count);
      i:= 0;
      var UsedByKey: string;
      for UsedByKey in Acc.UsedBySet.Keys do
      begin
        UsedByArr[i]:= UsedByKey;
        Inc(i);
        ProjUnitsPerGroup[Acc.Group].AddOrSetValue(UsedByKey, True);
      end;
      TArray.Sort<string>(UsedByArr, TComparer<string>.Construct(
        function(const L, R: string): Integer
        begin
          Result:= CompareText(L, R);
        end));

      ExtRec.UnitName    := Acc.UnitName;
      ExtRec.Group       := Acc.Group;
      ExtRec.Resolved    := Acc.Resolved;
      ExtRec.UsedByCount := Length(UsedByArr);
      if Length(UsedByArr) > MaxList then
      begin
        ExtRec.UsedBy    := Copy(UsedByArr, 0, MaxList);
        ExtRec.UsedByMore:= Length(UsedByArr) - MaxList;
      end
      else
      begin
        ExtRec.UsedBy    := UsedByArr;
        ExtRec.UsedByMore:= 0;
      end;

      SetLength(ExtRec.Sections, Acc.SectionsSet.Count);
      i:= 0;
      var SectionKey: string;
      for SectionKey in Acc.SectionsSet.Keys do
      begin
        ExtRec.Sections[i]:= SectionKey;
        Inc(i);
      end;
      TArray.Sort<string>(ExtRec.Sections, TComparer<string>.Construct(
        function(const L, R: string): Integer
        begin
          Result:= CompareText(L, R);
        end));

      { ShortestPath is keyed directly by the external's normalized unit
        name; NoteShortestPath already kept the fewest-hops chain across
        every project source that reached it. }
      if not ShortestPath.TryGetValue(ExtNorm, ExtRec.ShortestPath) then ExtRec.ShortestPath:= '';

      ExtOut[ExtCount]:= ExtRec;
      Inc(ExtCount);

      Inc(GroupTally[Acc.Group].UnitCount);
      if not Acc.Resolved then Inc(Result.Summary.UnresolvedCount);
    end;
    SetLength(ExtOut, ExtCount);

    for G:= Low(TDepsGroup) to High(TDepsGroup) do
      GroupTally[G].ProjectUnitCount:= ProjUnitsPerGroup[G].Count;

    { Sort Externals: group asc, then UsedByCount desc, then name asc. }
    TArray.Sort<TDepsExternal>(ExtOut, TComparer<TDepsExternal>.Construct(
      function(const L, R: TDepsExternal): Integer
      begin
        Result:= GroupOrd(L.Group) - GroupOrd(R.Group);
        if Result = 0 then Result:= R.UsedByCount - L.UsedByCount;
        if Result = 0 then Result:= CompareText(L.UnitName, R.UnitName);
      end));

    { Sort Edges: source asc, then external asc. }
    EdgeArr:= EdgeList.ToArray;
    TArray.Sort<TDepsEdge>(EdgeArr, TComparer<TDepsEdge>.Construct(
      function(const L, R: TDepsEdge): Integer
      begin
        Result:= CompareText(L.SourceUnit, R.SourceUnit);
        if Result = 0 then Result:= CompareText(L.ExternalUnit, R.ExternalUnit);
      end));

    Result.Externals:= ExtOut;
    Result.Edges    := EdgeArr;
    Result.Summary.ExternalUnitCount:= Length(ExtOut);
    Result.Summary.ExternalEdgeCount:= Length(EdgeArr);

    SetLength(Result.Summary.GroupCounts, 0);
    for G:= Low(TDepsGroup) to High(TDepsGroup) do
      if GroupTally[G].UnitCount > 0 then
      begin
        SetLength(Result.Summary.GroupCounts, Length(Result.Summary.GroupCounts) + 1);
        Result.Summary.GroupCounts[High(Result.Summary.GroupCounts)]:= GroupTally[G];
      end;
  finally
    for G:= Low(TDepsGroup) to High(TDepsGroup) do
      if ProjUnitsPerGroup[G] <> nil then ProjUnitsPerGroup[G].Free;
    if ShortestPath <> nil then ShortestPath.Free;
    if EdgeList     <> nil then EdgeList    .Free;
    if Externals    <> nil then Externals   .Free;
    if Edges        <> nil then Edges       .Free;
    if StemToGlobal <> nil then StemToGlobal.Free;
    if AllFiles     <> nil then AllFiles    .Free;
  end;
end;

end.
