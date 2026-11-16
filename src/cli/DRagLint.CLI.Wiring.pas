unit DRagLint.CLI.Wiring;

// ---------------------------------------------------------------------------
// The wiring, implementors, impact and surface verbs. Moved verbatim out of DRagLint.CLI
// (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint wiring --qname Interface | --coverage [--db path] [--format text|json]: the Spring4D DI wiring of an interface (implementations with lifetime, resolve sites), or the registrations not resolved into an interface-to-type edge.</summary>
/// <param name="AArgs">--qname or --coverage, --db, --format.</param>
/// <returns>0 on an answer; 2 on a usage error or a missing / stale --db.</returns>
function DoWiring(const AArgs: TArgs): Integer;

/// <summary>The `implementors` verb: the interface report for --target (spec
/// 2026-11-01-interface-report-design.md).</summary>
/// <param name="AArgs">--target (or --qname), --db, optional --library-db / second --db,
/// --uses, --max-sites N, --include-library, --format text|json|dot|mermaid, --json, --output.</param>
/// <returns>0 answered (also zero implementors), 1 target not found, 2 usage error,
/// ambiguous target or missing/stale db.</returns>
function DoImplementors(const AArgs: TArgs): Integer;

/// <summary>`impact --all-projects`: asks every database the manifest names, one row
/// per section, including the sections that could not answer.</summary>
/// <param name="AArgs">QName, Depth, Format; WorkspaceConfig (--config) names the
/// manifest; CheckPlatform (--platform) narrows the library sections.</param>
/// <returns>0 the target was found somewhere, also with sections unanswered (the
/// report says so); 1 found nowhere, or depth 0; 2 usage error, --db given, or a
/// manifest that did not load.</returns>
/// <remarks>Read-only. --db is refused rather than ignored: it would name one
/// database while the answer came from all of them.</remarks>
function DoImpactAllProjects(const AArgs: TArgs): Integer;

/// <summary>drag-lint impact --qname X [--depth N] [--db path] [--format text|json]: the transitive callers of the last segment of X, up to depth N.</summary>
/// <param name="AArgs">--qname (required), --depth, --db, --format.</param>
/// <returns>0 when callers are found, 1 when none; 2 on a usage error or a missing / stale db.</returns>
function DoImpact(const AArgs: TArgs): Integer;

/// <summary>drag-lint surface --qname Foo.TBar [--db path] [--include-impl] [--all-visibility] [--format text|json]: the interface-section declaration of a class, read from its source lines.</summary>
/// <param name="AArgs">--qname (required), --db, --include-impl, --all-visibility, --format.</param>
/// <returns>0 on success; 1 when the symbol is not found or not a class; 2 on a usage error or a missing / stale db.</returns>
function DoSurface(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, Winapi.Windows, DRagLint.Query.Implementors,
  DRagLint.Query.CrossImpact, DRagLint.Core.OutputEncoding, System.SysUtils, System.IOUtils,
  System.NetEncoding, System.JSON, System.StrUtils, System.DateUtils, System.Generics.Collections,
  System.SyncObjs, Data.DB, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, DRagLint.Core.Interfaces,
  DRagLint.Project.Resolver, DRagLint.Index.Manifest, DRagLint.Index.Plan, DRagLint.Wiring,
  DRagLint.Query.Callers;

// v0.17: drag-lint impact --qname <X> [--depth N] [--db <path>] [--format text|json]
// Walks transitive callers of the last segment of <X> up to depth N.
// Exit 0 if callers found, 1 if none.
// v8: drag-lint wiring --qname <Interface> [--db <path>] [--format text|json]
//     drag-lint wiring --coverage      [--db <path>] [--format text|json]
// Spring4D DI wiring edges: implementations (+lifetime) and resolve-sites of an
// interface; --coverage lists DI registrations not resolved into I->T edges.
function DoWiring(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore         ;
  Impls   : TArray<TDiBindingRow>;
  Sites   : TArray<TReference>   ;
  Unres   : TArray<TReference>   ;
  Handlers: TArray<TReference>   ;
  B       : TDiBindingRow        ;
  R       : TReference           ;
  JRoot   : TJSONObject          ;
  JO      : TJSONObject          ;
  JSites  : TJSONArray           ;
  Dbs     : TArray<string>       ;
  DbToUse : string               ;
begin
  if not ExplicitDbsExist(AArgs, 'wiring') then Exit(2);
  { v8: resolve the DB like query/hover -- explicit --db if given, else
    manifest-driven. Fixes projects whose index is NOT named <Project>.sqlite
    beside the .dproj (e.g. ORM3 -> C:\Projects\DB\ORM3\drag-lint.sqlite). Use the
    first existing resolved DB (the project/primary index). }
  Dbs:= ResolveConsumerDbs(AArgs);
  DbToUse:= FirstProjectDb(AArgs, Dbs); { a project's wiring, never the library's }
  if DbToUse = '' then
  begin
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), System.SysUtils.Format('ERROR: no drag-lint index found (tried %d resolved path(s)). Pass --db <file.sqlite> or build the index first.', [Length(Dbs)]));
    Exit(2);
  end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(DbToUse, RoOk);
  if (not RoOk) and StaleDbRefusesRun(AArgs, 'wiring', DbToUse) then Exit(2);

  if AArgs.WiringCoverage then
  begin
    Unres:= Store.FindDiUnresolved;
    if SameText(AArgs.Format, 'json') then
    begin
      JRoot:= TJSONObject.Create;
      try
        // Adopt JSites into JRoot, and each JO into JSites, before GetFilePath
        // (a DB query that can raise) so a mid-loop exception frees the whole
        // tree via JRoot (review fix).
        JSites:= TJSONArray.Create;
        JRoot.AddPair('unresolved', JSites);
        for R in Unres do
        begin
          JO:= TJSONObject.Create;
          JSites.AddElement(JO);
          JO.AddPair('method', R.NameText);
          JO.AddPair('file', Store      .GetFilePath(R.FileId   ));
          JO.AddPair('line', TJSONNumber.Create     (R.StartLine));
        end;
        Writeln(JRoot.Format(2));
      finally
        JRoot.Free;
      end; // try
    end // if
    else
    begin
      Writeln(Format('DI registrations not resolved into I->T edges (%d):', [Length(Unres)]));
      for R in Unres do Writeln(Format('  %s  %s:%d', [R.NameText, Store.GetFilePath(R.FileId), R.StartLine]));
      if Length(Unres) = 0 then Writeln('  (none)');
    end;
    Exit(0);
  end; // if

  if AArgs.QName = '' then
  begin
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), 'Usage: drag-lint wiring --qname <Interface> [--db <path>] ' + '[--format text|json]');
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), '       drag-lint wiring --coverage [--db <path>] [--format text|json]');
    Exit   (2                                                                      );
  end;

  if SameText(AArgs.Format, 'json') then
  begin
    // Shared builder so CLI json and MCP get_wiring return identical data.
    JRoot:= BuildWiringJson(AArgs.QName, Store);
    try
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Impls   := Store.FindImplementationsOf   (AArgs.QName);
    Sites   := Store.FindDiResolveSites      (AArgs.QName);
    Handlers:= Store.FindEventHandlersForForm(AArgs.QName);
    Writeln(AArgs.QName);
    if Length(Impls) > 0 then
      for B in Impls do Writeln(Format('  impl: %s [%s]  %s:%d', [B.ImplName, B.Lifetime, Store.GetFilePath(B.FileId), B.StartLine]));
    if Length(Sites) > 0 then
    begin
      Writeln(Format('  resolved at %d site(s):', [Length(Sites)]));
      for R in Sites do Writeln(Format('    %s:%d', [Store.GetFilePath(R.FileId), R.StartLine]));
    end;
    if Length(Handlers) > 0 then
    begin
      Writeln('  event handlers:');
      for R in Handlers do Writeln(Format('    %s <- %s:%d', [R.NameText, Store.GetFilePath(R.FileId), R.StartLine]));
    end;
    if (Length(Impls) = 0) and (Length(Sites) = 0) and (Length(Handlers) = 0) then Writeln('  (no DI or DFM wiring found)');
  end; // else
  Result:= 0;
end; // function

function DoImplementors(const AArgs: TArgs): Integer;
const
  USAGE = 'Usage: drag-lint implementors --target <IFoo|IFoo.Bar|TFoo|TFoo.Bar> --db <index.sqlite> [--library-db <lib.sqlite>] '
    + '[--uses] [--max-sites N] [--include-library] [--format text|json|dot|mermaid] [--json] [--output <file>]';
begin
  var Fmt:= if AArgs.AsJson then 'json' else LowerCase(AArgs.Format);
  if Fmt = '' then Fmt:= 'text';
  var IsJson:= Fmt = 'json';
  var Target:= if AArgs.Target <> '' then AArgs.Target else AArgs.QName;
  if (Target = '') or not MatchText(Fmt, ['text', 'json', 'dot', 'mermaid']) or (AArgs.IfrMaxSites < 0) then
  begin
    ReportNotFoundFor(IsJson, USAGE);
    Exit(2);
  end;
  if NoDbResolved(AArgs.DbPath, 'implementors') then Exit(2);
  if not TFile.Exists(AArgs.DbPath) then
  begin
    ReportNotFoundFor(IsJson, 'ERROR: database not found: ' + AArgs.DbPath);
    Exit(2);
  end;
  var RoOk: Boolean;
  var Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if (not RoOk) and StaleDbRefusesRun(AArgs, 'implementors', AArgs.DbPath) then Exit(2);
  var Opts:= TImplementorsOptions.Defaults;
  Opts.WithUses:= AArgs.IfrUses;
  if AArgs.IfrMaxSites > 0 then Opts.MaxSites:= AArgs.IfrMaxSites;
  Opts.IncludeLibrary:= AArgs.IncludeLibrary;
  var LibPath:= if Length(AArgs.LibraryDbs) > 0 then AArgs.LibraryDbs[0]
    else if Length(AArgs.DbPaths) > 1 then AArgs.DbPaths[1] else '';
  if (LibPath <> '') and TFile.Exists(LibPath) then
  begin
    var LibOk: Boolean;
    Opts.LibraryStore:= OpenReadOnlyStore(LibPath, LibOk, True);
  end;
  var Report: TImplementorsReport;
  try
    Report:= BuildImplementorsReport(Store, Target, Opts);
  except
    on E: EImplementorsTarget do
    begin
      ReportNotFoundFor(IsJson, E.Message);
      Exit(if E.Ambiguous then 2 else 1);
    end;
  end;
  var OutText: string;
  if IsJson then
  begin
    var J:= ImplementorsReportToJson(Report);
    try
      OutText:= J.ToJSON;
    finally
      J.Free;
    end;
  end
  else
    OutText:= if Fmt = 'text' then ImplementorsReportToText(Report)
      else ImplementorsReportToChart(Report, Fmt = 'mermaid');
  if AArgs.Output <> '' then
  begin
    WriteOutputFile(AArgs.Output, OutText); { C16: follows --output-encoding, never a BOM (was TFile.WriteAllText UTF8 + BOM) }
    if not IsJson then Writeln('Wrote ', AArgs.Output);
  end
  else if IsJson then Writeln(OutText)
  else Write(OutText);
  Result:= 0;
end;
function DoImpactAllProjects(const AArgs: TArgs): Integer;
var
  Manifest: TIndexManifest;
  Filter  : TArray<string>;
  Plan    : TIndexPlan    ;
begin
  var IsJson:= SameText(AArgs.Format, 'json');
  if AArgs.QName = '' then
  begin
    ReportNotFoundFor(IsJson, 'Usage: drag-lint impact --qname <Qualified.Name> --all-projects [--platform win32|win64] [--config <manifest>] [--depth N] [--format text|json]');
    Exit(2);
  end;
  if Length(AArgs.DbPaths) > 0 then
  begin
    ReportNotFoundFor(IsJson, 'ERROR: impact: --all-projects asks every manifest database; it does not take --db.');
    Exit(2);
  end;
  if AArgs.Depth <= 0 then
  begin
    Writeln(AArgs.QName);
    Writeln('  (depth 0 returns nothing)');
    Exit(1);
  end;
  Manifest:= Default(TIndexManifest);
  var LoadErr:= '';
  try
    if AArgs.WorkspaceConfig <> '' then
      Manifest:= TManifestIO.ParseText(TFile.ReadAllText(AArgs.WorkspaceConfig),
        ExtractFilePath(TPath.GetFullPath(AArgs.WorkspaceConfig)))
    else
    begin
      Manifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
      LoadErr := Manifest.LoadError;
    end;
    if LoadErr = '' then LoadErr:= TManifestIO.Validate(Manifest);
  except
    on E: Exception do LoadErr:= E.Message;
  end; // try
  if LoadErr <> '' then
  begin
    ReportNotFoundFor(IsJson, 'ERROR: impact: the manifest did not load, so the project list is unknown: ' + LoadErr);
    Exit(2);
  end;
  Filter:= nil;
  if AArgs.CheckPlatform <> '' then Filter:= [AArgs.CheckPlatform];
  var Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
  try
    Plan:= ResolvePlan(Manifest, Filter, Resolver);
  finally
    Resolver.Free;
  end; // try
  if Length(Plan.Items) = 0 then
  begin
    ReportNotFoundFor(IsJson, 'ERROR: impact: the manifest names no index section; nothing can answer.');
    Exit(2);
  end;
  var ConfigPath:= AArgs.WorkspaceConfig;
  var Report:= BuildCrossImpact(Plan, AArgs.QName, AArgs.Depth, AArgs.CheckPlatform,
    function(const pItem: TPlanSection): string
    begin
      Result:= IndexSectionCommand(pItem, ConfigPath);
    end);
  if IsJson then
  begin
    var J:= CrossImpactToJson(Report);
    try
      Writeln(J.Format(2));
    finally
      J.Free;
    end; // try
  end
  else Write(CrossImpactToText(Report));
  Result:= if Report.Found then 0 else 1;
end; // function

function DoImpact(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore        ;
  Levels    : TArray<TImpactLevel>;
  L         : TImpactLevel        ;
  Prev      : Integer             ;
  Depth     : Integer             ;
  TargetName: string              ;
  JRoot     : TJSONObject         ;
  JLevel    : TJSONObject         ;
  JArr      : TJSONArray          ;
begin
  if AArgs.QName = '' then begin ReportNotFoundFor(SameText(AArgs.Format, 'json'), 'Usage: drag-lint impact --qname <Qualified.Name> ' + '[--depth N] [--db <path>] [--format text|json]'); Exit(2); end;
  if NoDbResolved(AArgs.DbPath, 'impact') then Exit(2);
  if not TFile.Exists(AArgs.DbPath) then
  begin
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), 'ERROR: database not found: ' + AArgs.DbPath);
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), 'Run "drag-lint index <path>" first.');
    Exit(2);
  end;
  Depth:= AArgs.Depth;
  if Depth <= 0 then begin Writeln(AArgs.QName); Writeln('  (depth 0 returns nothing)'); Exit (1 ); end;
  // Use the bare name (last segment) as the target for the CTE ref lookup,
  // since refs store the bare identifier name, not the qualified name.
  TargetName:= LastSegment(AArgs.QName, '.');
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if (not RoOk) and StaleDbRefusesRun(AArgs, 'impact', AArgs.DbPath) then Exit(2);
  Levels:= Store.FindTransitiveCallers(TargetName, Depth);
  { RB-5 P1: what dispatches to / from this method. An interface method lists
    its implementors; an implementor lists the interface sites that reach it. }
  var DispImpls: TArray<TDispatchLink>:= [];
  var DispVia  : TQueryCallerRows     := [];
  var DispSyms : TArray<TSymbol>      := Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(DispSyms) = 0 then DispSyms:= Store.FindSymbolsByExactName(AArgs.QName);
  for var DS in DispSyms do
    if DS.Kind in [skProcedure, skFunction, skMethod] then
    begin
      for var DL in Store.FindDispatchLinks(DS.Id, False) do
        if DL.Kind = 'implements' then DispImpls:= DispImpls + [DL];
      DispVia:= DispVia + DispatchCallersOf(Store, DS.Id);
    end;
  if SameText(AArgs.Format, 'json') then
  begin
    JRoot:= TJSONObject.Create;
    JArr := TJSONArray .Create;
    try
      JRoot.AddPair('qname', AArgs.QName);
      for L in Levels do
      begin
        JLevel:= TJSONObject.Create;
        JLevel.AddPair('depth'  , TJSONNumber.Create(L.Depth      ));
        JLevel.AddPair('callers', TJSONNumber.Create(L.CallerCount));
        JLevel.AddPair('units'  , TJSONNumber.Create(L.UnitCount  ));
        JArr.AddElement(JLevel);
      end;
      JRoot.AddPair('levels', JArr);
      if Length(DispImpls) > 0 then
      begin
        var JImpls:= TJSONArray.Create;
        for var DL in DispImpls do JImpls.Add(DL.OtherQName);
        JRoot.AddPair('implementors', JImpls);
      end;
      var JVia: TJSONArray:= nil;
      for var VR in DispVia do
        if VR.ViaCount > 0 then
        begin
          if JVia = nil then JVia:= TJSONArray.Create;
          var JV:= TJSONObject.Create;
          JV.AddPair('via'  , VR.Via);
          JV.AddPair('kind' , VR.ViaKind);
          JV.AddPair('sites', TJSONNumber.Create(VR.ViaCount));
          JVia.AddElement(JV);
        end;
      if JVia <> nil then JRoot.AddPair('via_dispatch', JVia);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end // if
  else
  begin
    Writeln(AArgs.QName);
    Prev:= 0;
    for L in Levels do
    begin
      if Prev > 0 then Writeln(Format('  Depth %d: %3d callers in %d units (+%d)', [L.Depth, L.CallerCount, L.UnitCount, L.CallerCount - Prev]))
      else Writeln(Format('  Depth %d: %3d callers in %d units', [L.Depth, L.CallerCount, L.UnitCount]));
      Prev:= L.CallerCount;
    end;
    if Length(DispImpls) > 0 then
    begin
      Writeln('  implementors (interface dispatch):');
      for var DL in DispImpls do
        Writeln(Format('    %s%s', [DL.OtherQName, (if DL.Confidence = 'ambiguous' then ' [ambiguous edge]' else '')]));
    end;
    for var VR in DispVia do
      if VR.ViaCount > 0 then
        Writeln(Format('  via %s dispatch (%s): %d site(s)%s',
          [VR.ViaKind, VR.Via, VR.ViaCount, (if VR.ViaEdge = 'ambiguous' then ' [ambiguous edge]' else '')]));
    if Length(Levels) = 0 then begin Writeln('  (no callers)'); Exit (1 ); end;
  end; // else
  Result:= 0;
end; // function

// v0.17: drag-lint surface --qname <Foo.TBar> [--db <path>]
//   [--include-impl] [--all-visibility] [--format text|json]
// Reads start_line..end_line of the class symbol from the source file and
// prints each line. For a well-formed Delphi unit the class symbol spans only
// the interface-section declaration, so no implementation bodies leak through.
// Exit 2 on usage error or a missing/stale db, 1 if symbol not found or wrong kind, 0 on success.
function DoSurface(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore        ;
  Lines: TArray<TSurfaceLine>;
  L    : TSurfaceLine        ;
  Syms : TArray<TSymbol>     ;
  JArr : TJSONArray          ;
  JObj : TJSONObject         ;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint surface --qname <Foo.TBar> ' + '[--db <path>] [--include-impl] [--all-visibility] ' + '[--format text|json]');
    Exit(2);
  end;
  if NoDbResolved(AArgs.DbPath, 'surface') then Exit(2);
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Writeln('Run "drag-lint index <path>" first.'); Exit (2 ); end;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // stale schema: 2 like every bad --db -- 1 is reserved for an EMPTY answer

  // Validate that the symbol exists and is a class/record/interface.
  Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then
  begin
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;
  { INBOX 2.6: an ENUM's members were indexed but reachable by NO query. They
    exist as separate symbols (kind='enum_value', qualified_name
    '<EnumQName>.<member>'), but `query --qname <Enum>` returned only the enum,
    `hover` did not list them, and `surface` refused outright -- so the team
    had to read the declaration's source range and parse the parenthesised
    identifier list to get data the index already held.

    surface answers "what members does this type have?", which is exactly the
    question, so it now answers it for enums too rather than sending the caller
    back to the source text. Ordinal order is the declaration order, which is
    what an enum's members mean; FindAllChildSymbols returns them by id, and id
    is assigned in parse order. }
  if Syms[0].Kind = skEnum then
  begin
    var Members: TArray<TSymbol>:= Store.FindAllChildSymbols(Syms[0].Id);
    if Length(Members) = 0 then
    begin
      Writeln(System.SysUtils.Format('(enum %s has no indexed members)', [Syms[0].QualifiedName]));
      Exit(1);
    end;
    if SameText(AArgs.Format, 'json') then
    begin
      var JEnum:= TJSONObject.Create;
      try
        JEnum.AddPair('qualified_name', Syms[0].QualifiedName);
        JEnum.AddPair('kind', Syms[0].Kind.ToText);
        var JMembers:= TJSONArray.Create;
        for var Mi:= 0 to High(Members) do
        begin
          var JM:= TJSONObject.Create;
          JM.AddPair('name'          , Members[Mi].Name         );
          JM.AddPair('qualified_name', Members[Mi].QualifiedName);
          JM.AddPair('ordinal'       , TJSONNumber.Create(Mi)   );
          JM.AddPair('start_line'    , TJSONNumber.Create(Members[Mi].StartLine));
          JMembers.AddElement(JM);
        end;
        JEnum.AddPair('members', JMembers);
        Writeln(JEnum.Format(2));
      finally
        JEnum.Free;
      end;
    end
    else
    begin
      Writeln(System.SysUtils.Format('enum %s', [Syms[0].QualifiedName]));
      for var Mi:= 0 to High(Members) do
        Writeln(System.SysUtils.Format('  %d  %s', [Mi, Members[Mi].Name]));
    end;
    Exit(0);
  end;

  if not (Syms[0].Kind in [skClass, skRecord, skInterface]) then
  begin
    Writeln(System.SysUtils.Format( 'Symbol %s has kind "%s"; surface requires a class, record, or interface (or an enum, for its members).', [Syms[0].QualifiedName, Syms[0].Kind.ToText]));
    Exit(2);
  end;

  Lines:= Store.GetClassSurface(AArgs.QName, AArgs.IncludeImpl, AArgs.AllVisibility);
  if Length(Lines) = 0 then begin Writeln('(no surface lines returned)'); Exit (1 ); end;

  if SameText(AArgs.Format, 'json') then
  begin
    JArr:= TJSONArray.Create;
    try
      for L in Lines do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('kind', L.Kind);
        JObj.AddPair('text', L.Text);
        JObj.AddPair('line', TJSONNumber.Create(L.StartLine));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end // if
  else begin for L in Lines do Writeln(L.Text); end;
  Result:= 0;
end; // function

end.
