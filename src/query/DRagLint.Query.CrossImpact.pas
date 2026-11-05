unit DRagLint.Query.CrossImpact;

{ `impact --all-projects`: the blast radius of one symbol over every database the
  manifest names, with one line for every section that could NOT answer.

  THE AUTHORITY RULE (global, owner 2026-08-13) is what shapes this unit: a project
  database answers "who calls it"; the library answers "which unit declares it" and
  never "who calls it". So a library section yields declarations only, even when its
  own units call the target, and a project that neither holds the declaration nor
  has a library that does has its by-name references COUNTED BUT NOT ADDED: they name
  something else, or that project's closure lacks the unit, and the report cannot
  tell which. The number is printed so the reader can.

  THE COMPLETENESS RULE: the answer is never silently short. A section with no
  database, an old schema or an unreadable file is a row with a state, and the
  report's Complete is False. What it CANNOT see is a project the manifest does not
  name; the report says so in words, because there is nothing to count. }

interface

uses
  System.SysUtils, System.JSON,
  DRagLint.Core.Model, DRagLint.Index.Plan;

type
  /// <summary>How one manifest section answered.</summary>
  /// <remarks>Every value but cisAnswered makes the report incomplete.</remarks>
  TCrossImpactState = (cisAnswered, cisNotIndexed, cisOldSchema, cisUnreadable);

  /// <summary>One place the target is declared, and which section said so.</summary>
  TCrossDeclaration = record
    Section : string ;
    Kind    : string ; // project | folder | library: the kind of the section that answered
    QName   : string ;
    FilePath: string ;
    Line    : Integer;
  end;

  /// <summary>One implementor a project database reports.</summary>
  TCrossImplementor = record
    QName: string;
    /// <summary>certain or ambiguous: a resolved edge in this database. by-name: the
    /// interface is declared in the library, so the class matched on the interface
    /// NAME in its heritage and the method-level answer is not available.</summary>
    Edge : string;
  end;

  /// <summary>Interface sites that reach the target, as the single-database verb reports them.</summary>
  TCrossVia = record
    Via  : string ;
    Kind : string ;
    Edge : string ;
    Sites: Integer;
  end;

  /// <summary>What one manifest section answered, or why it could not.</summary>
  TCrossSection = record
    Name          : string ; // section name; sections sharing one database are joined
    Kind          : string ; // project | folder | library
    DbPath        : string ;
    Platform      : string ; // library sections only
    State         : TCrossImpactState;
    Reason        : string ; // cisOldSchema / cisUnreadable: what was wrong
    Repair        : string ; // the command that makes this section answer; '' when it did
    /// <summary>Files changed on disk since this index was written; above zero the
    /// section answered but the report is not complete.</summary>
    StaleFiles    : Integer;
    /// <summary>The target is declared in THIS database.</summary>
    TargetDeclared: Boolean;
    /// <summary>Caller levels; always empty for a library section (authority rule)
    /// and for a project that cannot see the declaration.</summary>
    Levels        : TArray<TImpactLevel>;
    /// <summary>Depth-1 name matches left OUT of Levels because this project cannot
    /// see the declaration: same-named other symbols, or a unit its closure lacks.</summary>
    ByNameRefs    : Integer;
    Implementors  : TArray<TCrossImplementor>;
    Via           : TArray<TCrossVia>;
  end;

  /// <summary>The whole cross-project answer.</summary>
  TCrossImpactReport = record
    QName       : string ;
    Depth       : Integer;
    Platform    : string ; // the --platform filter; '' = every platform the manifest names
    Declarations: TArray<TCrossDeclaration>;
    Sections    : TArray<TCrossSection>;
    /// <summary>Every section answered, from an index with no changed files.</summary>
    /// <returns>False when any row is not cisAnswered or has StaleFiles above zero.
    /// True says nothing about a project the manifest does not name.</returns>
    function Complete: Boolean;
    /// <summary>The target was declared somewhere or has a counted caller.</summary>
    /// <returns>True when the verb should exit 0.</returns>
    function Found: Boolean;
  end;

  /// <summary>Supplies the command that would index a section that could not answer.</summary>
  TCrossRepairFunc = reference to function(const pItem: TPlanSection): string;

/// <summary>Asks every database of a resolved plan about one symbol.</summary>
/// <param name="pPlan">The resolved manifest plan. Sections sharing a database are one row.</param>
/// <param name="pQName">The symbol: qualified, partly qualified or bare.</param>
/// <param name="pDepth">Caller levels to walk; must be above zero.</param>
/// <param name="pPlatform">Echoed into the report; the plan was already filtered by it.</param>
/// <param name="pRepair">Names the repair for a section that could not answer; may be nil.</param>
/// <returns>One row per distinct database, in plan order.</returns>
/// <remarks>Opens every database read-only and writes nothing. Never raises for a
/// database it cannot read: that is a row. Caller levels are the same name-based walk
/// as the single-database verb, so they may include same-named other routines.</remarks>
function BuildCrossImpact(const pPlan: TIndexPlan; const pQName: string; pDepth: Integer;
  const pPlatform: string; const pRepair: TCrossRepairFunc): TCrossImpactReport;

/// <summary>Renders the report as JSON.</summary>
/// <param name="pReport">The report.</param>
/// <returns>An owned object: {qname,depth,platform,complete,found,declarations[],sections[],summary}.
/// Each section has name,kind,db,state; levels and target_declared on a project or folder only.
/// The caller frees it.</returns>
function CrossImpactToJson(const pReport: TCrossImpactReport): TJSONObject;

/// <summary>Renders the report as text, one block per section and a coverage line.</summary>
/// <param name="pReport">The report.</param>
/// <returns>Text that ends in the coverage line; INCOMPLETE appears there when not Complete.
/// Sections that answered with no declaration and no reference share one line.</returns>
function CrossImpactToText(const pReport: TCrossImpactReport): string;

implementation

uses
  System.Generics.Collections, System.StrUtils,
  DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness,
  DRagLint.Query.Callers, DRagLint.Query.Implementors;

const
  KIND_PROJECT = 'project';
  KIND_FOLDER  = 'folder';
  KIND_LIBRARY = 'library';
  EDGE_BY_NAME = 'by-name';
  EDGE_CERTAIN = 'certain';
  LINK_IMPLEMENTS = 'implements';
  { The transitive walk's first level is what a by-name reference count needs. }
  BY_NAME_DEPTH = 1;

function StateText(pState: TCrossImpactState): string;
begin
  case pState of
    cisAnswered  : Result:= 'answered';
    cisNotIndexed: Result:= 'not-indexed';
    cisOldSchema : Result:= 'old-schema';
  else
    Result:= 'unreadable';
  end;
end; // function

function SectionKind(const pItem: TPlanSection): string;
begin
  case pItem.Mode of
    smLibrary: Result:= KIND_LIBRARY;
    smClosure: Result:= KIND_PROJECT;
  else
    Result:= KIND_FOLDER;
  end;
end; // function

function BareOf(const pQName: string): string;
begin
  Result:= pQName.Substring(pQName.LastIndexOf('.') + 1);
end; // function

{ The symbols pQName names here: qualified first, then a bare or partly qualified
  suffix -- the same order the implementors verb resolves a target in. }
function TargetSymbols(const pStore: ISymbolStore; const pQName: string): TArray<TSymbol>;
var
  Bare  : string;
  Suffix: string;
begin
  Result:= pStore.FindSymbolsByQualifiedName(pQName);
  if Length(Result) > 0 then Exit;
  Bare  := BareOf(pQName);
  Suffix:= '.' + pQName;
  for var S in pStore.FindSymbolsByExactName(Bare) do
    if SameText(Bare, pQName) or EndsText(Suffix, S.QualifiedName) then
      Result:= Result + [S];
end; // function

{ The interface a target belongs to: itself, or the parent of an interface member. }
function InterfaceNameOf(const pStore: ISymbolStore; const pSym: TSymbol): string;
begin
  Result:= '';
  if pSym.Kind = skInterface then Exit(pSym.Name);
  if pSym.ParentId <= 0 then Exit;
  var Parent:= pStore.GetSymbolById(pSym.ParentId);
  if Parent.Kind = skInterface then Result:= Parent.Name;
end; // function

procedure AddImplementor(var pRow: TCrossSection; const pQName, pEdge: string);
begin
  for var I in pRow.Implementors do
    if SameText(I.QName, pQName) then Exit;
  var Item:= Default(TCrossImplementor);
  Item.QName:= pQName;
  Item.Edge := pEdge;
  pRow.Implementors:= pRow.Implementors + [Item];
end; // procedure

procedure AddDeclarations(var pReport: TCrossImpactReport; const pStore: ISymbolStore;
  const pRow: TCrossSection; const pSyms: TArray<TSymbol>);
begin
  for var S in pSyms do
  begin
    var D:= Default(TCrossDeclaration);
    D.Section := pRow.Name;
    D.Kind    := pRow.Kind;
    D.QName   := S.QualifiedName;
    D.FilePath:= pStore.GetFilePath(S.FileId);
    D.Line    := S.StartLine;
    pReport.Declarations:= pReport.Declarations + [D];
  end;
end; // procedure

{ A project that holds the declaration: resolved implementors and dispatch sites. }
procedure AnswerLocalDispatch(const pStore: ISymbolStore; const pSyms: TArray<TSymbol>; var pRow: TCrossSection);
begin
  for var S in pSyms do
    if S.Kind = skInterface then
    begin
      for var C in ImplementingClassesOf(pStore, S) do AddImplementor(pRow, C.QualifiedName, EDGE_CERTAIN);
    end
    else if S.Kind in [skProcedure, skFunction, skMethod] then
    begin
      for var L in pStore.FindDispatchLinks(S.Id, False) do
        if L.Kind = LINK_IMPLEMENTS then AddImplementor(pRow, L.OtherQName, L.Confidence);
      for var V in DispatchCallersOf(pStore, S.Id) do
        if V.ViaCount > 0 then
        begin
          var Via:= Default(TCrossVia);
          Via.Via  := V.Via;
          Via.Kind := V.ViaKind;
          Via.Edge := V.ViaEdge;
          Via.Sites:= V.ViaCount;
          pRow.Via:= pRow.Via + [Via];
        end;
    end;
end; // procedure

{ A project that sees an interface only through the library: its classes name the
  interface in their heritage, and that name is all this database has to go on. }
procedure AnswerLibraryImplementors(const pStore: ISymbolStore; const pInterfaceName: string; var pRow: TCrossSection);
begin
  for var N in pStore.FindDescendantNamesOfKind(pInterfaceName, 'class') do
    for var S in pStore.FindSymbolsByExactName(N) do
      if S.Kind = skClass then AddImplementor(pRow, S.QualifiedName, EDGE_BY_NAME);
end; // procedure

procedure AnswerProject(const pStore: ISymbolStore; const pQName: string; pDepth: Integer;
  const pSyms: TArray<TSymbol>; const pLibraryDeclares: Boolean; const pLibraryInterface: string;
  var pRow: TCrossSection);
begin
  var Bare:= BareOf(pQName);
  pRow.TargetDeclared:= Length(pSyms) > 0;
  if pRow.TargetDeclared then
  begin
    pRow.Levels:= pStore.FindTransitiveCallers(Bare, pDepth);
    AnswerLocalDispatch(pStore, pSyms, pRow);
  end
  else if pLibraryDeclares then
  begin
    pRow.Levels:= pStore.FindTransitiveCallers(Bare, pDepth);
    if pLibraryInterface <> '' then AnswerLibraryImplementors(pStore, pLibraryInterface, pRow);
  end
  else
    for var L in pStore.FindTransitiveCallers(Bare, BY_NAME_DEPTH) do
      pRow.ByNameRefs:= pRow.ByNameRefs + L.CallerCount;
end; // procedure

{ Opens one database and answers for it; every failure becomes the row's state.
  A library row FILLS pLibraryDeclares and pLibraryInterface, a project row reads
  them, so BuildCrossImpact asks every library first. }
procedure AnswerSection(var pReport: TCrossImpactReport; var pRow: TCrossSection; const pQName: string; pDepth: Integer;
  var pLibraryDeclares: Boolean; var pLibraryInterface: string);
var
  Store   : ISymbolStore;
  Found   : Integer     ;
  Expected: Integer     ;
begin
  if not FileExists(pRow.DbPath) then
  begin
    pRow.State:= cisNotIndexed;
    Exit;
  end;
  try
    Store:= TSQLiteSymbolStore.Create(pRow.DbPath, {AReadOnly=}True);
    if not Store.IsSchemaCurrent(Found, Expected) then
    begin
      pRow.State := cisOldSchema;
      pRow.Reason:= Format('index schema v%d < v%d', [Found, Expected]);
      Exit;
    end;
    var Fresh:= ProbeIndexFreshness(Store);
    if Fresh.Verdict = fvStale then pRow.StaleFiles:= Fresh.Changed;
    var Syms:= TargetSymbols(Store, pQName);
    AddDeclarations(pReport, Store, pRow, Syms);
    if pRow.Kind = KIND_LIBRARY then
    begin
      pRow.TargetDeclared:= Length(Syms) > 0;
      if pRow.TargetDeclared then pLibraryDeclares:= True;
      for var S in Syms do
        if pLibraryInterface = '' then pLibraryInterface:= InterfaceNameOf(Store, S);
    end
    else AnswerProject(Store, pQName, pDepth, Syms, pLibraryDeclares, pLibraryInterface, pRow);
  except
    on E: Exception do
    begin
      pRow.State := cisUnreadable;
      pRow.Reason:= E.Message;
      pRow.Levels:= [];
      pRow.Implementors:= [];
      pRow.Via:= [];
    end;
  end; // try
end; // procedure

function BuildCrossImpact(const pPlan: TIndexPlan; const pQName: string; pDepth: Integer;
  const pPlatform: string; const pRepair: TCrossRepairFunc): TCrossImpactReport;
var
  Seen           : TDictionary<string, Integer>;
  Items          : TArray<TPlanSection>;
  LibraryDeclares: Boolean;
  LibraryIntf    : string ;
begin
  Result:= Default(TCrossImpactReport);
  Result.QName   := pQName;
  Result.Depth   := pDepth;
  Result.Platform:= pPlatform;
  Items:= [];
  Seen:= TDictionary<string, Integer>.Create;
  try
    for var Item in pPlan.Items do
    begin
      var Key:= LowerCase(ExpandFileName(Item.DbPath));
      var At: Integer;
      if Seen.TryGetValue(Key, At) then
      begin
        Result.Sections[At].Name:= Result.Sections[At].Name + ', ' + Item.Name;
        Continue;
      end;
      Seen.Add(Key, Length(Items));
      Items:= Items + [Item];
      var Row:= Default(TCrossSection);
      Row.Name    := Item.Name;
      Row.Kind    := SectionKind(Item);
      Row.DbPath  := Item.DbPath;
      Row.Platform:= Item.Platform;
      Result.Sections:= Result.Sections + [Row];
    end;
  finally
    Seen.Free;
  end; // try

  { Libraries first: a project row needs to know what the library declares. }
  LibraryDeclares:= False;
  LibraryIntf    := '';
  for var I:= 0 to High(Result.Sections) do
    if Result.Sections[I].Kind = KIND_LIBRARY then
      AnswerSection(Result, Result.Sections[I], pQName, pDepth, LibraryDeclares, LibraryIntf);
  for var I:= 0 to High(Result.Sections) do
    if Result.Sections[I].Kind <> KIND_LIBRARY then
      AnswerSection(Result, Result.Sections[I], pQName, pDepth, LibraryDeclares, LibraryIntf);

  if Assigned(pRepair) then
    for var I:= 0 to High(Result.Sections) do
      if (Result.Sections[I].State <> cisAnswered) or (Result.Sections[I].StaleFiles > 0) then
        Result.Sections[I].Repair:= pRepair(Items[I]);
end; // function

function TCrossImpactReport.Complete: Boolean;
begin
  for var S in Sections do
    if (S.State <> cisAnswered) or (S.StaleFiles > 0) then Exit(False);
  Result:= True;
end; // function

function TCrossImpactReport.Found: Boolean;
begin
  Result:= Length(Declarations) > 0;
  if Result then Exit;
  for var S in Sections do
    if Length(S.Levels) > 0 then Exit(True);
end; // function

function CrossImpactToJson(const pReport: TCrossImpactReport): TJSONObject;
var
  Answered: Integer;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('qname'   , pReport.QName);
  Result.AddPair('depth'   , TJSONNumber.Create(pReport.Depth));
  Result.AddPair('platform', pReport.Platform);
  Result.AddPair('complete', TJSONBool.Create(pReport.Complete));
  Result.AddPair('found'   , TJSONBool.Create(pReport.Found));

  var JDecls:= TJSONArray.Create;
  Result.AddPair('declarations', JDecls);
  for var D in pReport.Declarations do
  begin
    var J:= TJSONObject.Create;
    JDecls.AddElement(J);
    J.AddPair('section', D.Section);
    J.AddPair('kind'   , D.Kind);
    J.AddPair('qname'  , D.QName);
    J.AddPair('file'   , D.FilePath);
    J.AddPair('line'   , TJSONNumber.Create(D.Line));
  end;

  Answered:= 0;
  var JSecs:= TJSONArray.Create;
  Result.AddPair('sections', JSecs);
  for var S in pReport.Sections do
  begin
    if S.State = cisAnswered then Inc(Answered);
    var J:= TJSONObject.Create;
    JSecs.AddElement(J);
    J.AddPair('name' , S.Name);
    J.AddPair('kind' , S.Kind);
    J.AddPair('db'   , S.DbPath);
    J.AddPair('state', StateText(S.State));
    if S.Reason <> '' then J.AddPair('reason', S.Reason);
    if S.Repair <> '' then J.AddPair('repair', S.Repair);
    if S.State <> cisAnswered then Continue;
    J.AddPair('stale_files', TJSONNumber.Create(S.StaleFiles));
    J.AddPair('target_declared', TJSONBool.Create(S.TargetDeclared));
    if S.Kind = KIND_LIBRARY then Continue; { authority rule: no caller keys at all }
    J.AddPair('by_name_refs', TJSONNumber.Create(S.ByNameRefs));
    var JLevels:= TJSONArray.Create;
    J.AddPair('levels', JLevels);
    for var L in S.Levels do
    begin
      var JL:= TJSONObject.Create;
      JLevels.AddElement(JL);
      JL.AddPair('depth'  , TJSONNumber.Create(L.Depth));
      JL.AddPair('callers', TJSONNumber.Create(L.CallerCount));
      JL.AddPair('units'  , TJSONNumber.Create(L.UnitCount));
    end;
    var JImpls:= TJSONArray.Create;
    J.AddPair('implementors', JImpls);
    for var I in S.Implementors do
    begin
      var JI:= TJSONObject.Create;
      JImpls.AddElement(JI);
      JI.AddPair('qname', I.QName);
      JI.AddPair('edge' , I.Edge);
    end;
    var JVia:= TJSONArray.Create;
    J.AddPair('via_dispatch', JVia);
    for var V in S.Via do
    begin
      var JV:= TJSONObject.Create;
      JVia.AddElement(JV);
      JV.AddPair('via'  , V.Via);
      JV.AddPair('kind' , V.Kind);
      JV.AddPair('sites', TJSONNumber.Create(V.Sites));
    end;
  end;

  var JSum:= TJSONObject.Create;
  Result.AddPair('summary', JSum);
  JSum.AddPair('sections', TJSONNumber.Create(Length(pReport.Sections)));
  JSum.AddPair('answered', TJSONNumber.Create(Answered));
end; // function

procedure WriteSectionText(pOut: TStringBuilder; const pRow: TCrossSection);
begin
  var Head:= Format('  %s [%s] %s', [pRow.Name, pRow.Kind, pRow.DbPath]);
  case pRow.State of
    cisNotIndexed: pOut.AppendLine(Head + ' -- NOT INDEXED: no answer from this section');
    cisOldSchema : pOut.AppendLine(Head + ' -- OLD SCHEMA (' + pRow.Reason + '): no answer from this section');
    cisUnreadable: pOut.AppendLine(Head + ' -- UNREADABLE (' + pRow.Reason + '): no answer from this section');
  else
    pOut.AppendLine(Head);
  end;
  if pRow.Repair <> '' then pOut.AppendLine('    repair: ' + pRow.Repair);
  if pRow.State <> cisAnswered then Exit;
  if pRow.StaleFiles > 0 then
    pOut.AppendLine(Format('    STALE: %d indexed file(s) changed on disk; this answer may be short', [pRow.StaleFiles]));
  if pRow.Kind = KIND_LIBRARY then
  begin
    pOut.AppendLine(if pRow.TargetDeclared then '    declares the target (a library answers declarations, not callers)'
      else '    does not declare the target');
    Exit;
  end;
  for var L in pRow.Levels do
    pOut.AppendLine(Format('    Depth %d: %3d callers in %d units', [L.Depth, L.CallerCount, L.UnitCount]));
  if pRow.ByNameRefs > 0 then
    pOut.AppendLine(Format('    target not visible here: %d by-name reference(s) NOT counted'
      + ' (another symbol of that name, or a unit this closure lacks)', [pRow.ByNameRefs]))
  else if Length(pRow.Levels) = 0 then pOut.AppendLine('    no callers');
  if Length(pRow.Implementors) > 0 then
  begin
    pOut.AppendLine('    implementors:');
    for var I in pRow.Implementors do
      pOut.AppendLine('      ' + I.QName + (if I.Edge = EDGE_CERTAIN then '' else ' [' + I.Edge + ']'));
  end;
  for var V in pRow.Via do
    pOut.AppendLine(Format('    via %s dispatch (%s): %d site(s)', [V.Kind, V.Via, V.Sites]));
end; // procedure

{ A section that answered and has nothing to say. On a real manifest most sections
  are this, so they share one line and a section with an answer stands out. }
function HasNothing(const pRow: TCrossSection): Boolean;
begin
  var Current:= (pRow.State = cisAnswered) and (pRow.StaleFiles = 0);
  var NoHits := (not pRow.TargetDeclared) and (pRow.ByNameRefs = 0);
  Result:= Current and NoHits and (Length(pRow.Levels) = 0) and (Length(pRow.Implementors) = 0);
end; // function

function CrossImpactToText(const pReport: TCrossImpactReport): string;
var
  Answered: Integer;
begin
  var Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine(pReport.QName + Format('  (every manifest section; depth %d%s)',
      [pReport.Depth, (if pReport.Platform <> '' then '; platform ' + pReport.Platform else '')]));
    if Length(pReport.Declarations) > 0 then
    begin
      Sb.AppendLine('  declared:');
      for var D in pReport.Declarations do
        Sb.AppendLine(Format('    %s  %s:%d  [%s: %s]', [D.QName, D.FilePath, D.Line, D.Kind, D.Section]));
    end
    else Sb.AppendLine('  declared: nowhere that answered');
    Answered:= 0;
    var Nothing: TArray<string>:= [];
    for var S in pReport.Sections do
    begin
      if S.State = cisAnswered then Inc(Answered);
      if HasNothing(S) then Nothing:= Nothing + [S.Name]
      else WriteSectionText(Sb, S);
    end;
    if Length(Nothing) > 0 then
      Sb.AppendLine('  no declaration, no reference: ' + string.Join(', ', Nothing));
    var Coverage:= Format('Coverage: %d of %d manifest section(s) answered.', [Answered, Length(pReport.Sections)]);
    if not pReport.Complete then Coverage:= Coverage + ' INCOMPLETE: index or repair the sections marked above, then ask again.';
    Sb.AppendLine(Coverage);
    Sb.AppendLine('A project the manifest does not name is not covered. Caller counts match by name.');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

end.
