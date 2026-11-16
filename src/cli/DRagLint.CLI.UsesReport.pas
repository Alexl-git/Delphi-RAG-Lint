unit DRagLint.CLI.UsesReport;

// ---------------------------------------------------------------------------
// The uses-report and deps-report verbs: transitive uses walks and the dependency report.
// Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint uses-report: the transitive uses closure of the indexed units as CSV (source_unit, used_unit, depth, first_section, via_chain, external).</summary>
/// <param name="AArgs">--db, --depth, --include-external and the output options.</param>
/// <returns>0 on success; nonzero on a usage error or a missing index.</returns>
function DoUsesReport(const AArgs: TArgs): Integer;

/// <summary>drag-lint deps-report: third-party dependency rollup over the index
/// uses-graph. Rollup by default (per-external unit: used-by count, resolved
/// state, shortest import path); --edges switches to the flat
/// (project-unit -&gt; external-unit) list. Formats: text|json|csv. Opens each
/// --db READ-ONLY via OpenReadOnlyStore (multi-DB, first-store-wins for stems),
/// borrows them into BuildDepsReport, and frees them afterward. A stale
/// explicit --db refuses the run (exit 2); a stale manifest-resolved one is
/// skipped. Never migrates -- a report is a read.</summary>
function DoDepsReport(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, DRagLint.Core.FileTime, Winapi.Windows,
  DRagLint.Lint.MarkerUnion, DRagLint.Core.CliError, DRagLint.Core.Encoding, DRagLint.Query.Implementors,
  DRagLint.Query.CrossImpact, DRagLint.Query.SyntaxCountVerb, DRagLint.CLI.UsesRecover,
  DRagLint.Query.IdentWords, DRagLint.Core.OutputEncoding, Winapi.ShellAPI, DRagLint.Lint.MissingUses,
  System.SysUtils, System.Classes, System.Hash, System.IOUtils, DRagLint.CLI.UnitContext,
  DRagLint.CLI.LibraryReady, DRagLint.CLI.LibraryMarker, DRagLint.CLI.HelpText, DRagLint.Core.Versions,
  System.NetEncoding, System.JSON, System.StrUtils, System.DateUtils, System.RegularExpressions,
  System.Generics.Collections, System.Generics.Defaults, System.Diagnostics, System.SyncObjs, System.Math,
  System.Character, Data.DB, FireDAC.Comp.Client, FireDAC.Phys.SQLite, FireDAC.Stan.Async, FireDAC.Stan.Def,
  FireDAC.Stan.Param, FireDAC.Stan.Option, FireDAC.DApt, TreeSitter, DRagLint.Core.DeclText,
  DRagLint.Core.ForwardStub, DRagLint.Lint.RefTypeRules, DRagLint.Lint.RuleCache, DRagLint.Lint.UsesAudit,
  DRagLint.Index.LibraryOracle, DRagLint.Lint.Autofix, DRagLint.Refactor.RedundantCast,
  DRagLint.Refactor.NarrowParam, DRagLint.Refactor.ExtractInterface, DRagLint.Refactor.LazyInit,
  DRagLint.Lint.TargetCompiler, DRagLint.Project.TargetStudio, DRagLint.Core.Interfaces,
  DRagLint.Core.Indexer, DRagLint.Analysis.LintTree, DRagLint.Analysis.PurityStage, DRagLint.Storage.SQLite,
  DRagLint.Storage.Schema, DRagLint.Storage.FileMembership, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM,
  DRagLint.Parser.Sql, DRagLint.Parser.Markdown, DRagLint.Query.TextNodes, DRagLint.Sql.FbSnapshot,
  DRagLint.Sql.OrmLinker, DRagLint.Sql.Guarded, DRagLint.Core.EngineHold, DRagLint.Core.UsageLog,
  DRagLint.Core.ControlChannel, DRagLint.Core.StudioEnv, DRagLint.Lint.Config, DRagLint.Lint.RuleCatalog,
  DRagLint.Lint.Compliance, DRagLint.Lint.Linter, DRagLint.Lint.QueryRules, DRagLint.Lint.ProjectChecks,
  DRagLint.Lint.IfdefUndefined, DRagLint.Lint.PlatformDivergent, DRagLint.Lint.ProjectRules,
  DRagLint.Lint.SharedScope, DRagLint.Lint.ClassMetrics, DRagLint.Lint.TaintRules, DRagLint.Lint.DocRules,
  DRagLint.Lint.SharedUnit, DRagLint.Lint.Bookmarks, DRagLint.CLI.Bookmarks,
  DRagLint.Lint.ExceptionUnitWriter, DRagLint.Project.Resolver, DRagLint.Project.ContextFile,
  DRagLint.Project.Members, DRagLint.Project.Coherence, DRagLint.Project.OwnRoots, DRagLint.Project.Facts,
  DRagLint.Project.DefineProfile, DRagLint.FormsMap, DRagLint.MenuTree, DRagLint.MenuTree.Dfm,
  DRagLint.MenuDrift, DRagLint.MCP.Server, DRagLint.LSP.Server, DRagLint.LSP.Proxy, Vcl.Graphics,
  DRagLint.Hover.Renderer, DRagLint.Hover.Returns, DRagLint.Hover.Contrast, DRagLint.Context.Bundler,
  DRagLint.Resolver.TypeAt, DRagLint.Refactor.Rename, DRagLint.Refactor.RenameProof,
  DRagLint.Refactor.TextEdit, DRagLint.Refactor.NamingFix, DRagLint.Refactor.MultiProjectRename,
  DRagLint.Refactor.DocStub, DRagLint.Doc.Facts, DRagLint.Doc.Regions, DRagLint.Doc.Document,
  DRagLint.Doc.Drift, DRagLint.Doc.Batch, DRagLint.Doc.Strip, DRagLint.Doc.Harvest, DRagLint.Doc.SymbolFacts,
  DRagLint.Doc.SharedFacts, DRagLint.Doc.ProjectTags, DRagLint.Doc.Wiki, DRagLint.Refactor.DeadCode,
  DRagLint.Refactor.TestStub, DRagLint.Refactor.ExtractMethod, DRagLint.CLI.Unwith,
  DRagLint.Query.ExceptionFacts, DRagLint.Charts.ArchDiagram, DRagLint.Refactor.CompileGate,
  DRagLint.Refactor.EnumHelper, DRagLint.Format.Yadf, DRagLint.Diagnostics.CompileCheck,
  DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Diagnostics.DeadCodeChecks,
  DRagLint.Diagnostics.ControlFlowChecks, DRagLint.Diagnostics.ExprChecks, DRagLint.Diagnostics.DeclChecks,
  DRagLint.Diagnostics.SizeChecks, DRagLint.Diagnostics.ConcurrencyChecks,
  DRagLint.Diagnostics.EnumOrdinalCast, DRagLint.Diagnostics.DisallowedChecks,
  DRagLint.Diagnostics.ModernizeChecks, DRagLint.Diagnostics.PpChecks, DRagLint.Index.PPUnitSource,
  DRagLint.Diagnostics.OwnershipChecks, DRagLint.Diagnostics.BoundsNilChecks,
  DRagLint.Diagnostics.ExceptionThreadChecks, DRagLint.Diagnostics.DeclParityChecks,
  DRagLint.Diagnostics.ParityExtChecks, DRagLint.Diagnostics.LifetimeShapeChecks,
  DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.ParseCache, DRagLint.V151.Api,
  DRagLint.V151.Dispatch, DRagLint.Diagnostics.FlowChecks, DRagLint.Analysis.DataFlow,
  DRagLint.Workspace.Config, DRagLint.Index.Manifest, DRagLint.Index.ManifestWrite, DRagLint.Index.Glob,
  DRagLint.Index.IgnoreFiles, DRagLint.Index.Closure, DRagLint.Index.Reconcile, DRagLint.Index.Plan,
  DRagLint.Index.DbSelect, DRagLint.Index.Drift, DRagLint.Index.Freshness, DRagLint.Index.Coverage,
  DRagLint.Index.CallResolver, DRagLint.Wiring, DRagLint.Output.Sarif, DRagLint.Output.ExitCode,
  DRagLint.Lint.Baseline, DRagLint.Lint.ReviewMarker, DRagLint.Preprocess.Types, DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Expr, DRagLint.Preprocess, DRagLint.Preprocess.Profile, DRagLint.Report.Deps,
  DRagLint.Report.RCallTree, DRagLint.Report.Overview, DRagLint.Report.CycleHub,
  DRagLint.Report.CycleHubSurface, DRagLint.Report.CyclePlan, DRagLint.CLI.CycleFix,
  DRagLint.Convert.PropTree, DRagLint.Convert.PropCache, DRagLint.Convert.Rules, DRagLint.Convert.CastLib,
  DRagLint.Convert.GlyphVacuum, DRagLint.Convert.DfmReemit, DRagLint.Convert.Apply, DRagLint.Convert.Backup,
  DRagLint.Convert.UnitRules, DRagLint.Convert.UsesReconcile, DRagLint.Query.Callers,
  DRagLint.Query.HoverModel, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters, DRagLint.Charts.Producer,
  DRagLint.Charts.Producer.Delphi, DRagLint.Charts.AskVerb, DRagLint.Charts.Snapshot, DRagLint.Charts.Compare,
  DRagLint.Charts.Render, DRagLint.Core.ProtocolReg, DRagLint.MCP.ClientConfig;

// v0.40.4: drag-lint uses-report --output <out.csv> [--db ...] [...]
//
// Emits a CSV row per (source_unit, transitively_used_unit) for every unit
// in the project (or, with --all-sources, every unit across every --db).
// BFS with a per-source visited set so each downstream unit appears at most
// once per source. Cycles are broken automatically by the visited set;
// unresolved (external) units terminate the walk at depth 1 unless
// --include-external is passed (in which case they appear in the output
// but still terminate as leaves since we don't have their uses indexed).
//
// CSV columns:
//   source_unit       ? basename stem (no ext, no dir) of the source file
//   used_unit         ? verbatim unit_name as written in the uses clause
//   depth             ? 1 = direct use, 2 = via one hop, ...
//   first_section     ? section the edge was first reached through
//   via_chain         ? '>' separated unit chain from source -> used (excl. self)
//   external          ? 1 when target_file_id couldn't be resolved, else 0
function DoUsesReport(const AArgs: TArgs): Integer;
type
  TUsesEdge = record
    UnitName    : string; { verbatim }
    UnitNameNorm: string; { lowercase trailing segment }
    TargetFileId: Int64 ; { -1 = external/unresolved }
    Section     : string; { 'interface'|'implementation'|'program'|'package' }
  end;

  TFileMeta = record
    Path      : string ;
    Stem      : string ; { lowercase basename without extension }
    StoreIndex: Integer; { which --db this file came from }
    FileId    : Int64  ; { id INSIDE that store; needed for joins }
  end;

  TBfsQueueItem = record
    FileId      : Int64  ;
    Depth       : Integer;
    UsedUnit    : string ;
    UnitNameNorm: string ;
    Section     : string ;
    Via         : string ; { chain so far, '>' separated, excludes self }
    External    : Boolean;
  end;
var
  Stores      : TArray<ISymbolStore>                   ;
  AllFiles    : TList<TFileMeta>                       ;
  StemToGlobal: TDictionary<string, Integer>           ; { stem -> index into AllFiles }
  Edges       : TDictionary<Integer, TArray<TUsesEdge>>; { source = global file index }
  CsvOut      : TStringWriter                          ;
  MaxDepth    : Integer                                ;
  RootPattern : string                                 ;

  procedure OpenStores;
  var
    DbList: TArray<string>;
    i     : Integer       ;
    Path  : string        ;
  begin
    if Length(AArgs.DbPaths) > 0 then DbList:= AArgs.DbPaths
    else if AArgs.DbPath <> '' then DbList:= TArray<string>.Create(AArgs.DbPath)
    else begin Writeln(ErrOutput, 'uses-report: need at least one --db'); Result:= 2; Exit; end;
    SetLength(Stores, 0);
    for i:= 0 to High(DbList) do
    begin
      Path:= DbList[i];
      if not TFile.Exists(Path) then begin Writeln(ErrOutput, 'uses-report: db not found, skipping: ', Path); Continue; end;
      { Read-only, never Migrate: this is a report. The deps-report twin, fixed
        the same day for the same reason (INBOX-read-verbs-migrate-the-db);
        Result:= 2 + Exit is this nested procedure's existing refusal shape. }
      var RoOk: Boolean;
      var S: ISymbolStore:= OpenReadOnlyStore(Path, RoOk);
      if (not RoOk) or (S = nil) then
      begin
        if (not RoOk) and StaleDbRefusesRun(AArgs, 'uses-report', Path) then begin Result:= 2; Exit; end;
        Continue;
      end;
      SetLength(Stores, Length(Stores) + 1);
      Stores[High(Stores)]:= S;
    end;
  end; // procedure

  function ComputeStem(const APath: string): string;
  var
    Base: string ;
    Dot : Integer;
  begin
    Base:= APath;
    while Length(Base) > 0 do
    begin
      if CharInSet(Base[Length(Base)], ['\','/']) then begin Delete(Base, Length(Base), 1); Break; end;
      Break;
    end;
    Result:= LowerCase(ExtractFileName(Base));
    Dot:= LastDelimiter('.', Result);
    if Dot > 0 then Result:= Copy(Result, 1, Dot - 1);
  end;

  procedure LoadFilesAndEdges;
  var
    StoreIdx      : Integer                               ;
    QFiles        : TFDQuery                              ;
    QUses         : TFDQuery                              ;
    SQLiteStore   : TSQLiteSymbolStore                    ;
    Meta          : TFileMeta                             ;
    PathStr       : string                                ;
    LocalFileId   : Int64                                 ;
    GlobalIdx     : Integer                               ;
    FileIdToGlobal: TDictionary<Int64, Integer>           ;
    PerStore      : TDictionary<Integer, TList<TUsesEdge>>;
    TargetFid     : Int64                                 ;
    TargetGlobal  : Integer                               ;
    Edge          : TUsesEdge                             ;
    Kv            : TPair<Integer, TList<TUsesEdge>>      ;
  begin
    AllFiles:= TList<TFileMeta>.Create;
    StemToGlobal:= TDictionary<string, Integer>.Create;
    Edges   := TDictionary<Integer, TArray<TUsesEdge>>.Create;
    PerStore:= TDictionary<Integer, TList <TUsesEdge>>.Create;

    { Step 1: gather every file across every store, build stem -> global index. }
    for StoreIdx:= 0 to High(Stores) do
    begin
      SQLiteStore:= TSQLiteSymbolStore(Stores[StoreIdx]);
      QFiles:= TFDQuery.Create(nil);
      try
        QFiles.Connection:= SQLiteStore.GetConnection;
        { Filter out DFM rows ? uses clauses only exist in pascal sources.
          Language tag is 'delphi13' for .pas/.dpr/.dpk in v0.40.x indexes. }
        QFiles.Sql.Text:= 'SELECT id, path FROM files ' + 'WHERE language NOT IN (''dfm'', ''json'', ''text'', ''markdown'')';
        QFiles.Open;
        while not QFiles.Eof do
        begin
          PathStr:= QFiles.FieldByName('path').AsString;
          Meta.Path:= PathStr;
          Meta.Stem:= ComputeStem(PathStr);
          Meta.StoreIndex:= StoreIdx;
          Meta.FileId:= QFiles.FieldByName('id').AsLargeInt;
          AllFiles.Add(Meta);
          { First-write-wins: project DB (first --db) takes priority. }
          if not StemToGlobal.ContainsKey(Meta.Stem) then StemToGlobal.Add(Meta.Stem, AllFiles.Count - 1);
          QFiles.Next;
        end;
      finally
        QFiles.Free;
      end; // try
    end; // for

    { Step 2: gather every unit_uses edge, group by global source file index. }
    FileIdToGlobal:= TDictionary<Int64, Integer>.Create;
    try
      for GlobalIdx:= 0 to AllFiles.Count - 1 do FileIdToGlobal.AddOrSetValue( (Int64(AllFiles[GlobalIdx].StoreIndex) shl 40) or Int64(AllFiles[GlobalIdx].FileId), GlobalIdx);

      for StoreIdx:= 0 to High(Stores) do
      begin
        SQLiteStore:= TSQLiteSymbolStore(Stores[StoreIdx]);
        QUses:= TFDQuery.Create(nil);
        try
          QUses.Connection:= SQLiteStore.GetConnection;
          QUses.Sql.Text:= 'SELECT file_id, unit_name, unit_name_norm, section, target_file_id ' + 'FROM unit_uses';
          QUses.Open;
          while not QUses.Eof do
          begin
            LocalFileId:= QUses.FieldByName('file_id').AsLargeInt;
            if not FileIdToGlobal.TryGetValue( (Int64(StoreIdx) shl 40) or LocalFileId, GlobalIdx) then begin QUses.Next; Continue; end;

            Edge.UnitName    := QUses.FieldByName('unit_name'     ).AsString;
            Edge.UnitNameNorm:= QUses.FieldByName('unit_name_norm').AsString;
            Edge.Section     := QUses.FieldByName('section'       ).AsString;
            { Resolve target: prefer the in-DB target_file_id; fall back to
              cross-DB lookup by stem. }
            Edge.TargetFileId:= -1;
            if not QUses.FieldByName('target_file_id').IsNull then
            begin
              TargetFid:= QUses.FieldByName('target_file_id').AsLargeInt;
              if FileIdToGlobal.TryGetValue( (Int64(StoreIdx) shl 40) or TargetFid, TargetGlobal) then Edge.TargetFileId:= TargetGlobal;
            end;
            { v(ADP3 T4f, register K39): TWO passes, most specific first, the same
              order ResolveUnitUseTargets uses. StemToGlobal is keyed on the FULL
              lowercased basename stem ('vcl.controls'), and this used to look it
              up with Edge.UnitNameNorm, which is the dotted TAIL ('controls') --
              the exact tail-vs-stem mismatch T4d fixed in the live path, sitting
              in the fallback that only runs when target_file_id is NULL, i.e.
              precisely when it is needed. For a DOTTED unit it could never hit.
              Pass 1 is LOWER(unit_name) against the full stem, matching pass 1 of
              the resolver character for character (no TRIM -- see register K43;
              normalising here would hide a parser defect rather than fix it).
              Pass 2 keeps the tail lookup for the legacy shapes pass 1 cannot
              reach (`uses SysUtils` -> System.SysUtils.pas). }
            if Edge.TargetFileId = -1 then
              if StemToGlobal.TryGetValue(LowerCase(Edge.UnitName), TargetGlobal) then Edge.TargetFileId:= TargetGlobal
              else if StemToGlobal.TryGetValue(Edge.UnitNameNorm, TargetGlobal) then Edge.TargetFileId:= TargetGlobal;

            if not PerStore.ContainsKey(GlobalIdx) then PerStore.Add(GlobalIdx, TList<TUsesEdge>.Create);
            PerStore[GlobalIdx].Add(Edge);

            QUses.Next;
          end; // while
        finally
          QUses.Free;
        end; // try
      end; // for
    finally
      FileIdToGlobal.Free;
    end; // try

    for Kv in PerStore do Edges.AddOrSetValue(Kv.Key, Kv.Value.ToArray);
    for Kv in PerStore do Kv.Value.Free;
    PerStore.Free;
  end; // procedure

  procedure EmitCsvHeader;
  begin
    CsvOut.WriteLine('source_unit,used_unit,depth,first_section,via_chain,external');
  end;

  function CsvEscape(const S: string): string;
  begin
    if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
    else Result:= S;
  end;

  procedure EmitCsvRow(const ASource, AUsed: string; ADepth: Integer; const ASection, AVia: string; AExternal: Boolean);
  begin
    CsvOut.WriteLine( CsvEscape(ASource) + ',' + CsvEscape(AUsed) + ',' + IntToStr(ADepth) + ',' + CsvEscape(ASection) + ',' + CsvEscape(AVia) + ',' + IfThen(AExternal, '1', '0'));
  end;

  procedure WalkBfs(ASourceIdx: Integer; var ARowCount: Integer);
  var
    Queue     : System.Generics.Collections.TQueue<TBfsQueueItem>;
    Visited   : TDictionary<string, Boolean>                     ;
    Item      : TBfsQueueItem                                    ;
    Nx        : TBfsQueueItem                                    ;
    Edge      : TUsesEdge                                        ;
    EdgeList  : TArray<TUsesEdge>                                ;
    SourceMeta: TFileMeta                                        ;
    NextVia   : string                                           ;
  begin
    Queue:= System.Generics.Collections.TQueue<TBfsQueueItem>.Create;
    Visited:= TDictionary<string, Boolean>.Create;
    try
      SourceMeta:= AllFiles[ASourceIdx];

      { Seed: direct uses from the source file. }
      if Edges.TryGetValue(ASourceIdx, EdgeList) then
        for Edge in EdgeList do
        begin
          if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
          Item.FileId:= Edge.TargetFileId;
          Item.Depth:= 1;
          Item.UsedUnit    := Edge.UnitName;
          Item.UnitNameNorm:= Edge.UnitNameNorm;
          Item.Section     := Edge.Section;
          Item.Via:= '';
          Item.External:= (Edge.TargetFileId < 0);
        Queue.Enqueue(Item);
      end;

    while Queue.Count > 0 do
    begin
      Item:= Queue.Dequeue;
      if Visited.ContainsKey(Item.UnitNameNorm) then Continue;
      Visited.Add(Item.UnitNameNorm, True);

      if Item.External and (not AArgs.IncludeExternal) then
      begin
        { Skip external rows when not requested, but DO still mark visited
            so we don't repeat them later via a different chain. }
      end
      else begin EmitCsvRow(SourceMeta.Stem, Item.UsedUnit, Item.Depth, Item.Section, Item.Via, Item.External); Inc(ARowCount); end;

      if Item.External then Continue;
      if Item.Depth >= MaxDepth then Continue;
      if not Edges.TryGetValue(Integer(Item.FileId), EdgeList) then Continue;

      if Item.Via = '' then NextVia:= Item.UsedUnit
      else NextVia:= Item.Via + '>' + Item.UsedUnit;

      for Edge in EdgeList do
      begin
        if Visited.ContainsKey(Edge.UnitNameNorm) then Continue;
        Nx.FileId:= Edge.TargetFileId;
        Nx.Depth:= Item.Depth + 1;
        Nx.UsedUnit    := Edge.UnitName;
        Nx.UnitNameNorm:= Edge.UnitNameNorm;
        Nx.Section     := Edge.Section;
        Nx.Via:= NextVia;
        Nx.External:= (Edge.TargetFileId < 0);
        Queue.Enqueue(Nx);
      end;
    end; // while
  finally
    Visited.Free;
    Queue.Free;
  end; // try
end; // procedure

  { The ONE definition of "is this file a source unit of the report": first
    --db only unless --all-sources, then the --name substring on the stem.
    Both the pre-count and the emit loop go through it, so they cannot drift. }
  function IsSourceCandidate(const AMeta: TFileMeta): Boolean;
  begin
    Result:= (AArgs.AllSources or (AMeta.StoreIndex = 0)) and ((RootPattern = '') or (Pos(RootPattern, AMeta.Stem) > 0));
  end;

var
  GlobalIdx   : Integer  ;
  SourceMeta  : TFileMeta;
  RowCount    : Integer  ;
  SourceCount : Integer  ;
  Candidates  : Integer  ;
begin
  if not ExplicitDbsExist(AArgs, 'uses-report') then Exit(2);
  Result:= 0;

  if AArgs.Output = '' then begin Writeln(ErrOutput, 'uses-report: --output <path.csv> is required'); Exit(2); end;

  MaxDepth:= AArgs.Depth;
  if MaxDepth <= 0 then MaxDepth:= 50;
  RootPattern:= LowerCase(AArgs.Name);

  AllFiles    := nil;
  StemToGlobal:= nil;
  Edges       := nil;
  CsvOut      := nil;
  try
    OpenStores;
    if Result <> 0 then Exit;
    if Length(Stores) = 0 then begin Writeln(ErrOutput, 'uses-report: no usable DB'); Exit(2); end;

    LoadFilesAndEdges;

    { Converter gap 2026-09-16 (stats\draglint-gaps.log, class `wrong`): a
      --name that matches NO source unit used to answer "0 source units, 0 rows
      written" with exit 0 -- a complete-looking report computed against a
      corpus that does not contain the subject, while `outline` on the same
      file and DB refused with exit 2. Count BEFORE the CSV is opened, so a
      refusal creates nothing and leaves an existing --output untouched. }
    Candidates:= 0;
    for GlobalIdx:= 0 to AllFiles.Count - 1 do
      if IsSourceCandidate(AllFiles[GlobalIdx]) then Inc(Candidates);
    if (RootPattern <> '') and (Candidates = 0) then
    begin
      Writeln(ErrOutput, 'ERROR: uses-report: no index passed contains a source unit named ', AArgs.Name);
      Writeln(ErrOutput, '       Tried ', Length(Stores), ' database(s). Index the unit, pass --all-sources, or pass --db <file.sqlite>.');
      Exit(2);
    end;

    CsvOut:= TStringWriter.Create; { ENC-OUT: buffered, written once through WriteOutputFile }
    EmitCsvHeader;

    RowCount    := 0;
    SourceCount := 0;
    for GlobalIdx:= 0 to AllFiles.Count - 1 do
    begin
      SourceMeta:= AllFiles[GlobalIdx];
      if not IsSourceCandidate(SourceMeta) then Continue;
      WalkBfs(GlobalIdx, RowCount);
      Inc(SourceCount);
    end;
    WriteOutputFile(AArgs.Output, CsvOut.ToString);

    Writeln(Format('uses-report: %d source units, %d rows written to %s', [SourceCount, RowCount, AArgs.Output]));
  finally
    if CsvOut       <> nil then CsvOut      .Free;
    if Edges        <> nil then Edges       .Free;
    if StemToGlobal <> nil then StemToGlobal.Free;
    if AllFiles     <> nil then AllFiles    .Free;
  end; // try
end; // begin

function DoDepsReport(const AArgs: TArgs): Integer;
var
  Stores: TArray<ISymbolStore>;

  procedure OpenStores;
  var
    DbList: TArray<string>;
    i     : Integer       ;
    Path  : string        ;
  begin
    if Length(AArgs.DbPaths) > 0 then DbList:= AArgs.DbPaths
    else if AArgs.DbPath <> '' then DbList:= TArray<string>.Create(AArgs.DbPath)
    else begin Writeln(ErrOutput, 'deps-report: need at least one --db'); Result:= 2; Exit; end;
    SetLength(Stores, 0);
    for i:= 0 to High(DbList) do
    begin
      Path:= DbList[i];
      if not TFile.Exists(Path) then begin Writeln(ErrOutput, 'deps-report: db not found, skipping: ', Path); Continue; end;
      { Read-only, never Migrate: this is a report. Same repair and same reason
        as DoUsages (INBOX-read-verbs-migrate-the-db). Result:= 2 + Exit is this
        nested procedure's existing way of refusing; the body checks it. }
      var RoOk: Boolean;
      var S: ISymbolStore:= OpenReadOnlyStore(Path, RoOk);
      if (not RoOk) or (S = nil) then
      begin
        if (not RoOk) and StaleDbRefusesRun(AArgs, 'deps-report', Path) then begin Result:= 2; Exit; end;
        Continue;
      end;
      SetLength(Stores, Length(Stores) + 1);
      Stores[High(Stores)]:= S;
    end;
  end; // procedure

  function CsvEscape(const S: string): string;
  begin
    if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
    else Result:= S;
  end;

  function ResolvedStr(AResolved: Boolean): string;
  begin
    if AResolved then Result:= 'resolved' else Result:= 'not-indexed';
  end;

  function RenderText(const ARep: TDepsReport): string;
  var
    SB       : TStringBuilder;
    G        : TDepsGroup    ;
    Ext      : TDepsExternal ;
    Edge     : TDepsEdge     ;
    GC       : TDepsGroupCount;
    UsedByStr: string        ;
  begin
    SB:= TStringBuilder.Create;
    try
      if AArgs.Edges then
      begin
        for Edge in ARep.Edges do
          SB.AppendLine(Format('%s -> %s  [%s]  [%s]  [%s]',
            [Edge.SourceUnit, Edge.ExternalUnit, DepsGroupStr(Edge.Group), Edge.Section, ResolvedStr(Edge.Resolved)]));
      end
      else
      begin
        for G:= Low(TDepsGroup) to High(TDepsGroup) do
        begin
          var AnyInGroup: Boolean:= False;
          for Ext in ARep.Externals do if Ext.Group = G then begin AnyInGroup:= True; Break; end;
          if not AnyInGroup then Continue;

          SB.AppendLine(Format('== %s ==', [DepsGroupStr(G)]));
          for Ext in ARep.Externals do
          begin
            if Ext.Group <> G then Continue;
            SB.AppendLine(Format('%s  (used by %d)  [%s]', [Ext.UnitName, Ext.UsedByCount, ResolvedStr(Ext.Resolved)]));
            if Ext.ShortestPath <> '' then SB.AppendLine(Format('  path: %s', [Ext.ShortestPath]));
            if Length(Ext.UsedBy) > 0 then
            begin
              UsedByStr:= string.Join(', ', Ext.UsedBy);
              if Ext.UsedByMore > 0 then UsedByStr:= UsedByStr + Format(' (+%d more)', [Ext.UsedByMore]);
              SB.AppendLine(Format('  used by: %s', [UsedByStr]));
            end;
          end;
        end;

        SB.AppendLine(Format('%d external units, %d edges, %d not indexed',
          [ARep.Summary.ExternalUnitCount, ARep.Summary.ExternalEdgeCount, ARep.Summary.UnresolvedCount]));
        for GC in ARep.Summary.GroupCounts do
          SB.AppendLine(Format('%s: %d units / %d project units', [DepsGroupStr(GC.Group), GC.UnitCount, GC.ProjectUnitCount]));
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end; // function

  function RenderJson(const ARep: TDepsReport): string;
  var
    JRoot    : TJSONObject   ;
    JSummary : TJSONObject   ;
    JGroups  : TJSONArray    ;
    JGroup   : TJSONObject   ;
    JExts    : TJSONArray    ;
    JExt     : TJSONObject   ;
    JUsedBy  : TJSONArray    ;
    JSections: TJSONArray    ;
    JEdges   : TJSONArray    ;
    JEdge    : TJSONObject   ;
    GC       : TDepsGroupCount;
    Ext      : TDepsExternal ;
    U        : string        ;
    Sec      : string        ;
    Edge     : TDepsEdge     ;
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema', 'deps-report/1');
      AddStalenessPairs(JRoot, AArgs.DbPath); { ENG-3: the first --db, the project index }

      JSummary:= TJSONObject.Create;
      JSummary.AddPair('external_unit_count', TJSONNumber.Create(ARep.Summary.ExternalUnitCount));
      JSummary.AddPair('external_edge_count', TJSONNumber.Create(ARep.Summary.ExternalEdgeCount));
      JSummary.AddPair('unresolved_count'   , TJSONNumber.Create(ARep.Summary.UnresolvedCount));
      JGroups:= TJSONArray.Create;
      for GC in ARep.Summary.GroupCounts do
      begin
        JGroup:= TJSONObject.Create;
        JGroup.AddPair('group'             , DepsGroupStr(GC.Group));
        JGroup.AddPair('unit_count'        , TJSONNumber.Create(GC.UnitCount));
        JGroup.AddPair('project_unit_count', TJSONNumber.Create(GC.ProjectUnitCount));
        JGroups.AddElement(JGroup);
      end;
      JSummary.AddPair('groups', JGroups);
      JRoot.AddPair('summary', JSummary);

      JExts:= TJSONArray.Create;
      for Ext in ARep.Externals do
      begin
        JExt:= TJSONObject.Create;
        JExt.AddPair('unit'         , Ext.UnitName);
        JExt.AddPair('group'        , DepsGroupStr(Ext.Group));
        JExt.AddPair('resolved'     , TJSONBool.Create(Ext.Resolved));
        JExt.AddPair('used_by_count', TJSONNumber.Create(Ext.UsedByCount));
        JUsedBy:= TJSONArray.Create;
        for U in Ext.UsedBy do JUsedBy.Add(U);
        JExt.AddPair('used_by', JUsedBy);
        JExt.AddPair('used_by_more', TJSONNumber.Create(Ext.UsedByMore));
        JExt.AddPair('shortest_path', Ext.ShortestPath);
        JSections:= TJSONArray.Create;
        for Sec in Ext.Sections do JSections.Add(Sec);
        JExt.AddPair('sections', JSections);
        JExts.AddElement(JExt);
      end;
      JRoot.AddPair('externals', JExts);

      if AArgs.Edges then
      begin
        JEdges:= TJSONArray.Create;
        for Edge in ARep.Edges do
        begin
          JEdge:= TJSONObject.Create;
          JEdge.AddPair('source_unit'  , Edge.SourceUnit);
          JEdge.AddPair('external_unit', Edge.ExternalUnit);
          JEdge.AddPair('group'        , DepsGroupStr(Edge.Group));
          JEdge.AddPair('section'      , Edge.Section);
          JEdge.AddPair('resolved'     , TJSONBool.Create(Edge.Resolved));
          JEdges.AddElement(JEdge);
        end;
        JRoot.AddPair('edges', JEdges);
      end;

      Result:= JRoot.Format(2);
    finally
      JRoot.Free;
    end;
  end; // function

  function RenderCsv(const ARep: TDepsReport): string;
  var
    SB  : TStringBuilder;
    Ext : TDepsExternal ;
    Edge: TDepsEdge      ;
  begin
    SB:= TStringBuilder.Create;
    try
      if AArgs.Edges then
      begin
        SB.AppendLine('source_unit,external_unit,group,section,resolved');
        for Edge in ARep.Edges do
          SB.AppendLine(CsvEscape(Edge.SourceUnit) + ',' + CsvEscape(Edge.ExternalUnit) + ',' +
            CsvEscape(DepsGroupStr(Edge.Group)) + ',' + CsvEscape(Edge.Section) + ',' +
            IfThen(Edge.Resolved, '1', '0'));
      end
      else
      begin
        SB.AppendLine('unit,group,resolved,used_by_count,shortest_path');
        for Ext in ARep.Externals do
          SB.AppendLine(CsvEscape(Ext.UnitName) + ',' + CsvEscape(DepsGroupStr(Ext.Group)) + ',' +
            IfThen(Ext.Resolved, '1', '0') + ',' + IntToStr(Ext.UsedByCount) + ',' +
            CsvEscape(Ext.ShortestPath));
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end; // function

var
  Opts  : TDepsOptions;
  Rep   : TDepsReport ;
  Fmt   : string       ;
  Output: string       ;
  i     : Integer      ;
begin
  if not ExplicitDbsExist(AArgs, 'deps-report') then Exit(2);
  Result:= 0;
  Stores:= nil;
  try
    OpenStores;
    if Result <> 0 then Exit;
    if Length(Stores) = 0 then begin Writeln(ErrOutput, 'deps-report: no usable DB'); Exit(2); end;

    Opts.Depth      := AArgs.Depth;
    Opts.AllSources := AArgs.AllSources;
    Opts.NamePattern:= AArgs.Name;
    Opts.MaxList    := 20;

    Rep:= BuildDepsReport(Stores, Opts);

    Fmt:= LowerCase(AArgs.Format);
    if Fmt = '' then Fmt:= 'text';

    if Fmt = 'json' then Output:= RenderJson(Rep)
    else if Fmt = 'csv' then Output:= RenderCsv(Rep)
    else Output:= RenderText(Rep);

    if AArgs.Output <> '' then WriteOutputFile(AArgs.Output, Output)
    else Writeln(Output);
  finally
    for i:= 0 to High(Stores) do Stores[i]:= nil;
  end; // try
end; // function

end.
