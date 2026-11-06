unit DRagLint.Query.Implementors;

{ The interface report (spec docs\superpowers\specs\2026-11-01-interface-report-design.md):
  who implements an interface, which method answers an interface method in which class,
  who calls / reads / writes an interface member (attributed to the INTERFACE member, RB-5
  ruling 2026-09-16), which interfaces a class implements and what answers each member.

  ONE engine for the `implementors` verb, the `ask implementors` chart, the LSP
  go-to-implementation answer, the "N implementors" code lens and the MCP tool. It reads
  rows the index already holds (symbols, type_ancestors, dispatch_edges, the resolved
  caller rows) through ISymbolStore only; it writes nothing.

  Method-resolution clauses (`procedure IJob.Execute = RunJob`) and `implements`
  delegation are answered from the rows the x129 extractor writes (lane `call`): an
  implements edge to RunJob, and a dispatch_edges 'delegates' row (base = the interface,
  impl = the delegating property). An index built before x129 holds neither; there the
  clause shows its body-less row and a delegating class answers 'not answered'. }

interface

uses
  System.SysUtils, System.JSON,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>One answer row: a class implementing the target, or (class target) one
  /// interface member and what answers it.</summary>
  /// <remarks>
  /// How: lists | via | inherited | delegated | library. Confidence: certain |
  /// ambiguous | unanswered. Paths are full paths; Line/BodyLine 0 =
  /// unknown.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Query.Implementors.AddLibrary (DRagLint.Query.Implementors.pas), DRagLint.Query.Implementors.ImplementingMethodsOf (DRagLint.Query.Implementors.pas), DRagLint.Query.Implementors.ReportClass (DRagLint.Query.Implementors.pas), DRagLint.Query.Implementors.ReportImplementor (DRagLint.Query.Implementors.pas), DRagLint.Query.Implementors.ReportInterface (DRagLint.Query.Implementors.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.Query.Implementors</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TImplRow = record
    ClassQName : string ;
    How        : string ;
    Via        : string ; // the derived interface (how=via), the listing ancestor (inherited) or the property (delegated)
    Member     : string ; // the interface member answered (interface-method and class targets)
    Method     : string ; // the answering method's qualified name; '' when unanswered
    DeclaredIn : string ; // the class declaring Method (differs from ClassQName when inherited)
    Confidence : string ;
    Note       : string ;
    FilePath   : string ;
    Line       : Integer;
    BodyLine   : Integer;
  end;

  /// <summary>One call / use site of the target member.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Implementors.pas) ?, DRagLint.Query.Implementors.AddSite (DRagLint.Query.Implementors.pas)</para>
  /// <para>Used in units: DRagLint.Query.Implementors</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TImplSite = record
    Mode      : string ; // call | read | write | ...
    FilePath  : string ;
    Line      : Integer;
    Enclosing : string ;
    Via       : string ; // the interface member the site dispatches through ('' = direct)
  end;

  /// <summary>The whole answer for one target.</summary>
  /// <remarks>
  /// Arrays are empty, never absent. LibraryImplementors is -1 when no library
  /// store was given.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Implementors.pas) ?, DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas) ?, DRagLint.CLI.DoImplementors (DRagLint.CLI.pas) ?, DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas) ?, DRagLint.Query.Implementors.BuildImplementorsReport (DRagLint.Query.Implementors.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.Charts.Q.Implementors, DRagLint.CLI, DRagLint.MCP.Server, DRagLint.Query.Implementors</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TImplementorsReport = record
    TargetQName : string ;
    TargetKind  : string ; // interface | interface-method | interface-property | class | method
    TargetFile  : string ;
    TargetLine  : Integer;
    Implementors: TArray<TImplRow>;
    Unanswered  : TArray<TImplRow>;
    Sites       : TArray<TImplSite>;
    SitesTotal  : Integer;
    LibraryImplementors: Integer;
    Notes       : TArray<string>;
  end;

  /// <summary>Report options.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Implementors.pas) ?, DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas), DRagLint.CLI.DoImplementors (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas), DRagLint.Query.Implementors.TImplementorsOptions.Defaults (DRagLint.Query.Implementors.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.Charts.Q.Implementors, DRagLint.CLI, DRagLint.MCP.Server, DRagLint.Query.Implementors</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TImplementorsOptions = record
    WithUses       : Boolean;      // add call / use sites
    MaxSites       : Integer;      // cap on Sites (SitesTotal is always the full count); <= 0 = no cap
    IncludeLibrary : Boolean;      // list the library's implementors as rows, not only a count
    LibraryStore   : ISymbolStore; // nil = no library
    /// <summary>The defaults: no sites, cap 50, no library.</summary>
    /// <returns>The default options.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas), DRagLint.CLI.DoImplementors (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Returns: Default(TImplementorsOptions)</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Defaults: TImplementorsOptions; static;
  end;

  /// <summary>The target names nothing the report can answer, or several symbols.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas) ?, DRagLint.CLI.DoImplementors (DRagLint.CLI.pas) ?, DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas) ?, DRagLint.Query.Implementors.BuildImplementorsReport (DRagLint.Query.Implementors.pas)</para>
  /// <para>Used in units: DRagLint.Charts.Q.Implementors, DRagLint.CLI, DRagLint.MCP.Server, DRagLint.Query.Implementors</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EImplementorsTarget = class(Exception)
  strict private
    FAmbiguous: Boolean;
  public
    /// <summary>Creates the error.</summary>
    /// <param name="pMsg">The message: what was asked and what matched.</param>
    /// <param name="pAmbiguous">True: several symbols matched; False: none did.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.Implementors.BuildImplementorsReport (DRagLint.Query.Implementors.pas)</para>
    /// <para>Calls: Create</para>
    /// <para>constructor</para>
    /// <para>Writes: FAmbiguous</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor CreateFor(const pMsg: string; pAmbiguous: Boolean);
    /// <summary>True when the name matched several symbols (exit 2), False when it
    /// matched none (exit 1).</summary>
    property Ambiguous: Boolean read FAmbiguous write FAmbiguous;
  end;

/// <summary>Builds the interface report for pTarget.</summary>
/// <param name="pStore">The project index; must not be nil.</param>
/// <param name="pTarget">Interface, interface method/property, class or class method;
/// qualified, partly qualified (IJob.Execute) or bare.</param>
/// <param name="pOptions">See TImplementorsOptions.</param>
/// <returns>The report; Implementors / Unanswered / Sites may be empty.</returns>
/// <exception cref="EImplementorsTarget">No symbol of a reportable kind matches, or
/// several do.</exception>
/// <remarks>
/// Read-only. Not thread-safe; call from the store's owning thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas), DRagLint.CLI.DoImplementors (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.Implementors.AddLibrary, DRagLint.Query.Implementors.AddSitesOf, DRagLint.Query.Implementors.EImplementorsTarget.CreateFor, DRagLint.Query.Implementors.IsRoutineKind, DRagLint.Query.Implementors.KindText, DRagLint.Query.Implementors.ReportClass, DRagLint.Query.Implementors.ReportImplementor, DRagLint.Query.Implementors.ReportInterface, DRagLint.Query.Implementors.ReportMember, DRagLint.Query.Implementors.TargetCandidates, DRagLint.Query.Implementors.TCtx.Create, DRagLint.Query.Implementors.TCtx.FilePathOf</para>
/// <para>Returns: Default(TImplementorsReport)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Query.Implementors.AddLibrary"/>
/// <seealso cref="DRagLint.Query.Implementors.AddSitesOf"/>
/// <seealso cref="DRagLint.Query.Implementors.EImplementorsTarget.CreateFor"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildImplementorsReport(const pStore: ISymbolStore; const pTarget: string;
  const pOptions: TImplementorsOptions): TImplementorsReport;

/// <summary>The answering methods of one interface member, one per implementing class
/// (a method answering for several classes appears once).</summary>
/// <param name="pStore">The project index.</param>
/// <param name="pMember">An interface method; any other symbol answers [].</param>
/// <returns>The answering method symbols (for a resolution clause: the named method).</returns>
/// <remarks>
/// Backs LSP textDocument/implementation and the code lens count.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Feature.ImplDecl.AddInterfaceImplementations (DRagLint.LSP.Feature.ImplDecl.pas), DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas), DRagLint.Query.Implementors.ImplementorCountsForFile (DRagLint.Query.Implementors.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.Implementors.AnswerFor, DRagLint.Query.Implementors.ImplementingClassesOfCtx, DRagLint.Query.Implementors.IsRoutineKind, DRagLint.Query.Implementors.TCtx.Create</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Query.Implementors.AnswerFor"/>
/// <seealso cref="DRagLint.Query.Implementors.ImplementingClassesOfCtx"/>
/// <seealso cref="DRagLint.Query.Implementors.IsRoutineKind"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementingMethodsOf(const pStore: ISymbolStore; const pMember: TSymbol): TArray<TSymbol>;

/// <summary>The classes implementing interface pIntf (directly, via a derived
/// interface or an ancestor class).</summary>
/// <param name="pStore">The project index.</param>
/// <param name="pIntf">An interface symbol.</param>
/// <returns>Class symbols, in FindDescendantNamesOfKind order.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Feature.ImplDecl.AddInterfaceImplementations (DRagLint.LSP.Feature.ImplDecl.pas), DRagLint.Query.CrossImpact.AnswerLocalDispatch (DRagLint.Query.CrossImpact.pas), DRagLint.Query.Implementors.ImplementorCountsForFile (DRagLint.Query.Implementors.pas)</para>
/// <para>Calls: DRagLint.Query.Implementors.ImplementingClassesOfCtx, DRagLint.Query.Implementors.TCtx.Create</para>
/// <para>Returns: ImplementingClassesOfCtx(Ctx, pIntf)</para>
/// <seealso cref="DRagLint.Query.Implementors.ImplementingClassesOfCtx"/>
/// <seealso cref="DRagLint.Query.Implementors.TCtx.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementingClassesOf(const pStore: ISymbolStore; const pIntf: TSymbol): TArray<TSymbol>;

/// <summary>The "N implementors" code-lens data of one file: every interface declared in
/// it (its implementing classes) and every interface method (its answering methods).</summary>
/// <param name="pStores">The stores that index the file; the first that knows it answers.</param>
/// <param name="pPath">The file's full path.</param>
/// <returns>A new array of {line (0-based), count}, count &gt; 0 only; the caller owns it.</returns>
/// <remarks>
/// Read-only. One entry per line.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Feature.CodeLens.TLspCodeLensFeature.Handle (DRagLint.LSP.Feature.CodeLens.pas), DRagLint.LSP.Server.TLSPServer.HandleCallerCounts (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.Implementors.ImplementingClassesOf, DRagLint.Query.Implementors.ImplementingMethodsOf, DRagLint.Query.Implementors.IsRoutineKind</para>
/// <para>Returns: TJSONArray.Create</para>
/// <para>Catches: Exception (re-raise)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Query.Implementors.ImplementingClassesOf"/>
/// <seealso cref="DRagLint.Query.Implementors.ImplementingMethodsOf"/>
/// <seealso cref="DRagLint.Query.Implementors.IsRoutineKind"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementorCountsForFile(const pStores: TArray<ISymbolStore>; const pPath: string): TJSONArray;

/// <summary>Renders the report as the `implementors/1` JSON document.</summary>
/// <param name="pReport">The report.</param>
/// <returns>A new object; the caller owns it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoImplementors (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: DRagLint.Query.Implementors.RowJson</para>
/// <para>Returns: TJSONObject.Create</para>
/// <para>Catches: Exception (re-raise)</para>
/// <seealso cref="DRagLint.Query.Implementors.RowJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementorsReportToJson(const pReport: TImplementorsReport): TJSONObject;

/// <summary>Renders the report as text (the verb's default output).</summary>
/// <param name="pReport">The report.</param>
/// <returns>CRLF-separated lines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoImplementors (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Query.Implementors.Bare, DRagLint.Query.Implementors.HowText, DRagLint.Query.Implementors.Loc, DRagLint.Query.Implementors.Short</para>
/// <para>Returns: Sb.ToString</para>
/// <seealso cref="DRagLint.Query.Implementors.Bare"/>
/// <seealso cref="DRagLint.Query.Implementors.HowText"/>
/// <seealso cref="DRagLint.Query.Implementors.Loc"/>
/// <seealso cref="DRagLint.Query.Implementors.Short"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementorsReportToText(const pReport: TImplementorsReport): string;

/// <summary>Renders the report as a chart: dot or mermaid.</summary>
/// <param name="pReport">The report.</param>
/// <param name="pMermaid">True: mermaid flowchart; False: Graphviz dot.</param>
/// <param name="pHref">Optional: the link of a node from (file, 1-based line); nil = no links.
/// Dot only; written as given into an HTML-like label's TD HREF (the charts row parser reads it), so it must
/// already be XML-escaped (DRagLint.Charts.Text.RowHref is).</param>
/// <returns>The chart source text.</returns>
/// <remarks>
/// Columns left to right: target, implementing classes, answering methods,
/// then (sites present) the calling routines.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Q.Implementors.Emit (DRagLint.Charts.Q.Implementors.pas), DRagLint.CLI.DoImplementors (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Query.Implementors.Bare, DRagLint.Query.Implementors.ChartId, DRagLint.Query.Implementors.ImplementorsReportToChart.Edge, DRagLint.Query.Implementors.ImplementorsReportToChart.Node, DRagLint.Query.Implementors.Short, ExtractFileName, pHref, Xml</para>
/// <para>Returns: Sb.ToString</para>
/// <seealso cref="DRagLint.Query.Implementors.Bare"/>
/// <seealso cref="DRagLint.Query.Implementors.ChartId"/>
/// <seealso cref="DRagLint.Query.Implementors.ImplementorsReportToChart.Edge"/>
/// <seealso cref="DRagLint.Query.Implementors.ImplementorsReportToChart.Node"/>
/// <seealso cref="DRagLint.Query.Implementors.Short"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ImplementorsReportToChart(const pReport: TImplementorsReport; pMermaid: Boolean;
  const pHref: TFunc<string, Integer, string> = nil): string;

implementation

uses
  System.StrUtils, System.RegularExpressions, System.Generics.Collections,
  DRagLint.Query.Callers;

const
  MAX_CHAIN = 32;
  DEFAULT_MAX_SITES = 50;
  HOW_LISTS = 'lists';
  HOW_VIA = 'via';
  HOW_INHERITED = 'inherited';
  HOW_DELEGATED = 'delegated';
  HOW_LIBRARY = 'library';
  CONF_CERTAIN = 'certain';
  CONF_UNANSWERED = 'unanswered';
  NOTE_DELEGATED = 'answered by the object the property returns';
  KIND_DELEGATES = 'delegates';
  NOTE_CLAUSE = 'resolution clause';
  NOTE_NO_METHOD = 'no method of that name in the class chain (library ancestor or index gap)';
  KIND_INTERFACE = 'interface';

constructor EImplementorsTarget.CreateFor(const pMsg: string; pAmbiguous: Boolean);
begin
  inherited Create(pMsg);
  FAmbiguous:= pAmbiguous;
end;

class function TImplementorsOptions.Defaults: TImplementorsOptions;
begin
  Result:= Default(TImplementorsOptions);
  Result.MaxSites:= DEFAULT_MAX_SITES;
end;

type
  { Per-run state: the store. }
  TCtx = class
  strict private
    FStore: ISymbolStore;
  public
    constructor Create(const pStore: ISymbolStore);
    function FilePathOf(const pSym: TSymbol): string;
    property Store: ISymbolStore read FStore;
  end;

constructor TCtx.Create(const pStore: ISymbolStore);
begin
  inherited Create;
  FStore:= pStore;
end;

function TCtx.FilePathOf(const pSym: TSymbol): string;
begin
  Result:= if pSym.FileId > 0 then FStore.GetFilePath(pSym.FileId) else '';
end;

function IsRoutineKind(pKind: TSymbolKind): Boolean;
begin
  Result:= pKind in [skMethod, skProcedure, skFunction, skConstructor, skDestructor];
end;

{ The heritage list as bare names: generic arguments and unit prefixes dropped. }
function HeritageNames(const pHeritage: string): TArray<string>;
begin
  Result:= [];
  var S:= pHeritage;
  while S.Contains('<') do
  begin
    var Before:= S;
    S:= TRegEx.Replace(S, '<[^<>]*>', '');
    if S = Before then Break;
  end;
  for var Part in S.Split([',']) do
  begin
    var N:= Part.Trim;
    if N = '' then Continue;
    Result:= Result + [N.Substring(N.LastIndexOf('.') + 1)];
  end;
end;

function AncestorIs(const pAnc: TTypeAncestor; const pIntf: TSymbol): Boolean;
begin
  Result:= (pAnc.Resolved and (pAnc.SymbolId = pIntf.Id)) or
    ((not pAnc.Resolved) and pAnc.MatchesName(pIntf.Name));
end;

function HasInterface(const pCtx: TCtx; const pType: TSymbol; const pIntf: TSymbol): Boolean;
begin
  Result:= False;
  for var A in pCtx.Store.GetTransitiveAncestors(pType.Id) do
    if AncestorIs(A, pIntf) then Exit(True);
end;

{ The parent class: the first heritage name, matched among the resolved class ancestors. }
function ParentClassOf(const pCtx: TCtx; const pClass: TSymbol): TSymbol;
begin
  Result:= Default(TSymbol);
  var Names:= HeritageNames(pClass.Heritage);
  if Length(Names) = 0 then Exit;
  for var A in pCtx.Store.GetTransitiveAncestors(pClass.Id) do
    if A.Resolved and SameText(A.Kind, 'class') and A.MatchesName(Names[0]) then
      Exit(pCtx.Store.GetSymbolById(A.SymbolId));
end;

{ A property of pClass that delegates pIntf (`implements pIntf`, or an interface derived
  from it): its dispatch_edges 'delegates' row. }
function DelegatingPropertyOf(const pCtx: TCtx; const pClass, pIntf: TSymbol): TSymbol;
begin
  Result:= Default(TSymbol);
  for var P in pCtx.Store.FindAllChildSymbols(pClass.Id) do
  begin
    if P.Kind <> skProperty then Continue;
    for var B in pCtx.Store.FindDispatchLinks(P.Id, True) do
    begin
      if B.Kind <> KIND_DELEGATES then Continue;
      var Base:= pCtx.Store.GetSymbolById(B.OtherId);
      if (Base.Id = pIntf.Id) or ((Base.Id > 0) and HasInterface(pCtx, Base, pIntf)) then Exit(P);
    end;
  end;
end;

{ How pClass comes to implement pIntf. }
procedure ClassifyHow(const pCtx: TCtx; const pClass, pIntf: TSymbol; var pRow: TImplRow);
begin
  var Parent:= ParentClassOf(pCtx, pClass);
  if (Parent.Id > 0) and HasInterface(pCtx, Parent, pIntf) then
  begin
    pRow.How:= HOW_INHERITED;
    var Cur:= Parent;
    for var Hop:= 1 to MAX_CHAIN do
    begin
      var Up:= ParentClassOf(pCtx, Cur);
      if (Up.Id = 0) or not HasInterface(pCtx, Up, pIntf) then Break;
      Cur:= Up;
    end;
    pRow.Via:= Cur.QualifiedName;
    Exit;
  end;
  pRow.How:= HOW_LISTS;
  var Listed:= False;
  for var N in HeritageNames(pClass.Heritage) do
    if SameText(N, pIntf.Name) then Listed:= True;
  if not Listed then
    for var A in pCtx.Store.GetTransitiveAncestors(pClass.Id) do
      if A.Resolved and SameText(A.Kind, KIND_INTERFACE) and (A.SymbolId <> pIntf.Id) then
      begin
        var J:= pCtx.Store.GetSymbolById(A.SymbolId);
        if (J.Id > 0) and HasInterface(pCtx, J, pIntf) and
          MatchText(J.Name, HeritageNames(pClass.Heritage)) then
        begin
          pRow.How:= HOW_VIA;
          pRow.Via:= J.QualifiedName;
          Break;
        end;
      end;
  var Deleg:= DelegatingPropertyOf(pCtx, pClass, pIntf);
  if Deleg.Id > 0 then
  begin
    pRow.How:= HOW_DELEGATED;
    pRow.Via:= Deleg.QualifiedName;
  end;
end;

function ImplementingClassesOfCtx(const pCtx: TCtx; const pIntf: TSymbol): TArray<TSymbol>;
begin
  Result:= [];
  for var N in pCtx.Store.FindDescendantNamesOfKind(pIntf.Name, 'class') do
    for var S in pCtx.Store.FindSymbolsByExactName(N) do
      if (S.Kind = skClass) and HasInterface(pCtx, S, pIntf) then
        Result:= Result + [S];
end;

function ImplementingClassesOf(const pStore: ISymbolStore; const pIntf: TSymbol): TArray<TSymbol>;
begin
  var Ctx:= TCtx.Create(pStore);
  try
    Result:= ImplementingClassesOfCtx(Ctx, pIntf);
  finally
    Ctx.Free;
  end;
end;

{ True when pMethod overrides, through any number of override hops, a method one of
  pLinks names (it is not itself one of them). }
function OverridesInto(const pCtx: TCtx; const pMethod: TSymbol; const pLinks: TArray<TDispatchLink>): Boolean;
begin
  Result:= False;
  var Cur:= pMethod.Id;
  for var Hop:= 1 to MAX_CHAIN do
  begin
    var Next:= Int64(0);
    for var B in pCtx.Store.FindDispatchLinks(Cur, True) do
      if B.Kind = 'override' then
      begin
        Next:= B.OtherId;
        Break;
      end;
    if Next = 0 then Exit;
    for var L in pLinks do
      if L.OtherId = Next then Exit(True);
    Cur:= Next;
  end;
end;

{ Fills Method / DeclaredIn / Confidence / Note / FilePath / Line / BodyLine of pRow:
  what answers pMember of pIntf for pClass. False = nothing answers it. }
function AnswerFor(const pCtx: TCtx; const pClass, pIntf, pMember: TSymbol; var pRow: TImplRow): Boolean;
begin
  Result:= False;
  var Links:= pCtx.Store.FindDispatchLinks(pMember.Id, False);
  var Cur:= pClass;
  for var Hop:= 1 to MAX_CHAIN do
  begin
    if Cur.Id = 0 then Break;
    { `implements` delegation takes the whole interface over for that class. }
    var Deleg:= DelegatingPropertyOf(pCtx, Cur, pIntf);
    if Deleg.Id > 0 then
    begin
      pRow.How:= HOW_DELEGATED;
      pRow.Via:= Deleg.QualifiedName;
      pRow.Confidence:= CONF_CERTAIN;
      pRow.Note:= NOTE_DELEGATED;
      pRow.DeclaredIn:= Cur.QualifiedName;
      pRow.FilePath:= pCtx.FilePathOf(Deleg);
      pRow.Line:= Deleg.StartLine;
      Exit(True);
    end;
    { A subclass override of the implementing method answers for the subclass: the
      implements edge names only the class that implements; subclasses are reached
      through override edges (TDispatchResolver.Run remarks). }
    var Own:= pCtx.Store.FindChildSymbolByName(Cur.Id, pMember.Name);
    if (Own.Id > 0) and IsRoutineKind(Own.Kind) and OverridesInto(pCtx, Own, Links) then
    begin
      pRow.Confidence:= CONF_CERTAIN;
      pRow.Method:= Own.QualifiedName;
      pRow.DeclaredIn:= Cur.QualifiedName;
      pRow.FilePath:= pCtx.FilePathOf(Own);
      pRow.Line:= Own.StartLine;
      pRow.BodyLine:= Own.ImplStartLine;
      Exit(True);
    end;
    for var L in Links do
    begin
      var Impl:= pCtx.Store.GetSymbolById(L.OtherId);
      if Impl.ParentId <> Cur.Id then Continue;
      pRow.Confidence:= L.Confidence;
      if not SameText(Impl.Name, pMember.Name) then
        pRow.Note:= NOTE_CLAUSE + ' (' + pMember.Name + ' = ' + Impl.Name + ')';
      pRow.Method:= Impl.QualifiedName;
      pRow.DeclaredIn:= Cur.QualifiedName;
      pRow.FilePath:= pCtx.FilePathOf(Impl);
      pRow.Line:= Impl.StartLine;
      pRow.BodyLine:= Impl.ImplStartLine;
      Exit(True);
    end;
    Cur:= ParentClassOf(pCtx, Cur);
  end;
  pRow.Confidence:= CONF_UNANSWERED;
  pRow.Note:= NOTE_NO_METHOD;
end;

function KindText(const pSym: TSymbol; const pParent: TSymbol): string;
begin
  case pSym.Kind of
    skInterface: Result:= KIND_INTERFACE;
    skClass    : Result:= 'class';
    skProperty : Result:= 'interface-property';
  else
    Result:= if pParent.Kind = skInterface then 'interface-method' else 'method';
  end;
end;

function Reportable(const pStore: ISymbolStore; const pSym: TSymbol): Boolean;
begin
  if pSym.Kind in [skInterface, skClass] then Exit(True);
  if not (IsRoutineKind(pSym.Kind) or (pSym.Kind = skProperty)) then Exit(False);
  var P:= pStore.GetSymbolById(pSym.ParentId);
  Result:= (P.Kind = skInterface) or ((P.Kind = skClass) and IsRoutineKind(pSym.Kind));
end;

{ Every reportable symbol pTarget names: qualified first, then a bare or partly qualified suffix. }
function TargetCandidates(const pStore: ISymbolStore; const pTarget: string): TArray<TSymbol>;
var
  Hits: TArray<TSymbol>;
begin
  Hits:= [];
  for var S in pStore.FindSymbolsByQualifiedName(pTarget) do
    if Reportable(pStore, S) then Hits:= Hits + [S];
  if Length(Hits) = 0 then
  begin
    var Bare:= pTarget.Substring(pTarget.LastIndexOf('.') + 1);
    var Suffix:= '.' + pTarget;
    for var S in pStore.FindSymbolsByExactName(Bare) do
      if Reportable(pStore, S) and ((Bare = pTarget) or EndsText(Suffix, S.QualifiedName)) then
        Hits:= Hits + [S];
  end;
  Result:= Hits;
end;


procedure AddSite(const pOptions: TImplementorsOptions; const pMode, pPath: string; pLine: Integer;
  const pEnclosing, pVia: string; var pReport: TImplementorsReport);
begin
  Inc(pReport.SitesTotal);
  if (pOptions.MaxSites > 0) and (Length(pReport.Sites) >= pOptions.MaxSites) then Exit;
  var S:= Default(TImplSite);
  S.Mode:= if pMode = '' then 'call' else pMode;  // a resolved call edge carries no mode; member accesses do
  S.FilePath:= pPath;
  S.Line:= pLine;
  S.Enclosing:= pEnclosing;
  S.Via:= pVia;
  pReport.Sites:= pReport.Sites + [S];
end;

procedure AddSitesOf(const pCtx: TCtx; const pMember: TSymbol; const pOptions: TImplementorsOptions;
  var pReport: TImplementorsReport);
begin
  for var RC in pCtx.Store.FindResolvedCallers(pMember.Id) do
    AddSite(pOptions, RC.Mode, RC.FullPath, RC.CallSiteLine, RC.EnclosingQName, '', pReport);

end;

procedure AddLibrary(const pIntf: TSymbol; const pOptions: TImplementorsOptions;
  var pReport: TImplementorsReport);
begin
  if pOptions.LibraryStore = nil then Exit;
  var Names:= pOptions.LibraryStore.FindDescendantNamesOfKind(pIntf.Name, 'class');
  pReport.LibraryImplementors:= Length(Names);
  if not pOptions.IncludeLibrary then Exit;
  for var N in Names do
    for var S in pOptions.LibraryStore.FindSymbolsByExactName(N) do
      if S.Kind = skClass then
      begin
        var R:= Default(TImplRow);
        R.ClassQName:= S.QualifiedName;
        R.How:= HOW_LIBRARY;
        R.Confidence:= CONF_CERTAIN;
        R.FilePath:= if S.FileId > 0 then pOptions.LibraryStore.GetFilePath(S.FileId) else '';
        R.Line:= S.StartLine;
        pReport.Implementors:= pReport.Implementors + [R];
        Break;
      end;
end;

procedure ReportInterface(const pCtx: TCtx; const pIntf: TSymbol; var pReport: TImplementorsReport);
begin
  for var C in ImplementingClassesOfCtx(pCtx, pIntf) do
  begin
    var R:= Default(TImplRow);
    R.ClassQName:= C.QualifiedName;
    R.Confidence:= CONF_CERTAIN;
    R.FilePath:= pCtx.FilePathOf(C);
    R.Line:= C.StartLine;
    ClassifyHow(pCtx, C, pIntf, R);
    pReport.Implementors:= pReport.Implementors + [R];
  end;
end;

procedure ReportMember(const pCtx: TCtx; const pMember, pIntf: TSymbol; var pReport: TImplementorsReport);
begin
  for var C in ImplementingClassesOfCtx(pCtx, pIntf) do
  begin
    var R:= Default(TImplRow);
    R.ClassQName:= C.QualifiedName;
    R.Member:= pMember.QualifiedName;
    ClassifyHow(pCtx, C, pIntf, R);
    if (pMember.Kind <> skProperty) and AnswerFor(pCtx, C, pIntf, pMember, R) then
      pReport.Implementors:= pReport.Implementors + [R]
    else if pMember.Kind = skProperty then
    begin
      R.Confidence:= CONF_CERTAIN;
      R.Note:= 'answered through the property''s accessors';
      R.FilePath:= pCtx.FilePathOf(C);
      R.Line:= C.StartLine;
      pReport.Implementors:= pReport.Implementors + [R];
    end
    else
    begin
      R.FilePath:= pCtx.FilePathOf(C);
      R.Line:= C.StartLine;
      pReport.Unanswered:= pReport.Unanswered + [R];
    end;
  end;
end;

procedure ReportClass(const pCtx: TCtx; const pClass: TSymbol; var pReport: TImplementorsReport);
begin
  var Seen:= TDictionary<Int64, Boolean>.Create;
  try
    for var A in pCtx.Store.GetTransitiveAncestors(pClass.Id) do
    begin
      if not (A.Resolved and SameText(A.Kind, KIND_INTERFACE)) or Seen.ContainsKey(A.SymbolId) then Continue;
      Seen.Add(A.SymbolId, True);
      var Intf:= pCtx.Store.GetSymbolById(A.SymbolId);
      for var M in pCtx.Store.FindAllChildSymbols(Intf.Id) do
      begin
        if not IsRoutineKind(M.Kind) then Continue;
        var R:= Default(TImplRow);
        R.ClassQName:= pClass.QualifiedName;
        R.Member:= M.QualifiedName;
        ClassifyHow(pCtx, pClass, Intf, R);
        if AnswerFor(pCtx, pClass, Intf, M, R) then
          pReport.Implementors:= pReport.Implementors + [R]
        else
          pReport.Unanswered:= pReport.Unanswered + [R];
      end;
    end;
  finally
    Seen.Free;
  end;
end;

procedure ReportImplementor(const pCtx: TCtx; const pMethod: TSymbol; const pOptions: TImplementorsOptions;
  var pReport: TImplementorsReport);
begin
  var Cls:= pCtx.Store.GetSymbolById(pMethod.ParentId);
  for var L in pCtx.Store.FindDispatchLinks(pMethod.Id, True) do
  begin
    if L.Kind <> 'implements' then Continue;
    var R:= Default(TImplRow);
    R.ClassQName:= Cls.QualifiedName;
    R.How:= HOW_LISTS;
    R.Member:= L.OtherQName;
    R.Method:= pMethod.QualifiedName;
    R.DeclaredIn:= Cls.QualifiedName;
    R.Confidence:= L.Confidence;
    R.FilePath:= pCtx.FilePathOf(pMethod);
    R.Line:= pMethod.StartLine;
    R.BodyLine:= pMethod.ImplStartLine;
    pReport.Implementors:= pReport.Implementors + [R];
  end;
  if not pOptions.WithUses then Exit;
  for var Row in DispatchCallersOf(pCtx.Store, pMethod.Id) do
    AddSite(pOptions, Row.Mode, Row.FullPath, Row.CallSiteLine, Row.CallerQName, Row.Via, pReport);

end;

function BuildImplementorsReport(const pStore: ISymbolStore; const pTarget: string;
  const pOptions: TImplementorsOptions): TImplementorsReport;
begin
  Result:= Default(TImplementorsReport);
  Result.LibraryImplementors:= -1;
  var Hits:= TargetCandidates(pStore, pTarget.Trim);
  if Length(Hits) <> 1 then
  begin
    var Names: TArray<string>:= [];
    for var H in Hits do Names:= Names + [H.QualifiedName];
    raise EImplementorsTarget.CreateFor(if Length(Hits) = 0
      then pTarget + ': no interface, interface member, class or class method of that name in this index'
      else pTarget + ' is ambiguous -- qualify it: ' + string.Join(', ', Names), Length(Hits) > 1);
  end;
  var T:= Hits[0];
  var Ctx:= TCtx.Create(pStore);
  try
    var Parent:= pStore.GetSymbolById(T.ParentId);
    Result.TargetQName:= T.QualifiedName;
    Result.TargetKind:= KindText(T, Parent);
    Result.TargetFile:= Ctx.FilePathOf(T);
    Result.TargetLine:= T.StartLine;
    case T.Kind of
      skInterface:
        begin
          ReportInterface(Ctx, T, Result);
          AddLibrary(T, pOptions, Result);
          if pOptions.WithUses then
            for var M in pStore.FindAllChildSymbols(T.Id) do
              if IsRoutineKind(M.Kind) or (M.Kind = skProperty) then AddSitesOf(Ctx, M, pOptions, Result);
        end;
      skClass:
        ReportClass(Ctx, T, Result);
    else
      if Parent.Kind = skInterface then
      begin
        ReportMember(Ctx, T, Parent, Result);
        AddLibrary(Parent, pOptions, Result);
        AddSitesOf(Ctx, T, pOptions, Result);  // a member target always carries its sites
      end
      else
        ReportImplementor(Ctx, T, pOptions, Result);
    end;
  finally
    Ctx.Free;
  end;
end;

function ImplementingMethodsOf(const pStore: ISymbolStore; const pMember: TSymbol): TArray<TSymbol>;
begin
  Result:= [];
  if not IsRoutineKind(pMember.Kind) then Exit;
  var Intf:= pStore.GetSymbolById(pMember.ParentId);
  if Intf.Kind <> skInterface then Exit;
  var Ctx:= TCtx.Create(pStore);
  var Seen:= TDictionary<string, Boolean>.Create;
  try
    for var C in ImplementingClassesOfCtx(Ctx, Intf) do
    begin
      var R:= Default(TImplRow);
      if not AnswerFor(Ctx, C, Intf, pMember, R) or (R.Method = '') or Seen.ContainsKey(R.Method) then Continue;
      Seen.Add(R.Method, True);
      for var S in pStore.FindSymbolsByQualifiedName(R.Method) do
        if IsRoutineKind(S.Kind) then
        begin
          Result:= Result + [S];
          Break;
        end;
    end;
  finally
    Seen.Free;
    Ctx.Free;
  end;
end;

function ImplementorCountsForFile(const pStores: TArray<ISymbolStore>; const pPath: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  try
    for var St in pStores do
    begin
      if St = nil then Continue;
      var Syms:= St.FindSymbolsByFile(pPath);
      if Length(Syms) = 0 then Continue;
      var Seen:= TDictionary<Integer, Boolean>.Create;
      try
        for var S in Syms do
        begin
          var N:= 0;
          if S.Kind = skInterface then N:= Length(ImplementingClassesOf(St, S))
          else if IsRoutineKind(S.Kind) and (St.GetSymbolById(S.ParentId).Kind = skInterface) then
            N:= Length(ImplementingMethodsOf(St, S));
          if (N = 0) or (S.StartLine <= 0) or Seen.ContainsKey(S.StartLine) then Continue;
          Seen.Add(S.StartLine, True);
          var O:= TJSONObject.Create;
          Result.AddElement(O);
          O.AddPair('line', TJSONNumber.Create(S.StartLine - 1));
          O.AddPair('count', TJSONNumber.Create(N));
        end;
      finally
        Seen.Free;
      end;
      Exit;
    end;
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

{ ---- rendering ---- }

function RowJson(const pRow: TImplRow): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('class', pRow.ClassQName);
  Result.AddPair('how', pRow.How);
  Result.AddPair('via', pRow.Via);
  Result.AddPair('member', pRow.Member);
  Result.AddPair('method', pRow.Method);
  Result.AddPair('declared_in', pRow.DeclaredIn);
  Result.AddPair('confidence', pRow.Confidence);
  Result.AddPair('note', pRow.Note);
  Result.AddPair('file', pRow.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pRow.Line));
  Result.AddPair('body_line', TJSONNumber.Create(pRow.BodyLine));
end;

function ImplementorsReportToJson(const pReport: TImplementorsReport): TJSONObject;
begin
  Result:= TJSONObject.Create;
  try
    Result.AddPair('schema', 'implementors/1');
    var JT:= TJSONObject.Create;
    Result.AddPair('target', JT);
    JT.AddPair('qname', pReport.TargetQName);
    JT.AddPair('kind', pReport.TargetKind);
    JT.AddPair('file', pReport.TargetFile);
    JT.AddPair('line', TJSONNumber.Create(pReport.TargetLine));
    var JI:= TJSONArray.Create;
    Result.AddPair('implementors', JI);
    for var R in pReport.Implementors do JI.AddElement(RowJson(R));
    var JU:= TJSONArray.Create;
    Result.AddPair('unanswered', JU);
    for var R in pReport.Unanswered do JU.AddElement(RowJson(R));
    var JS:= TJSONArray.Create;
    Result.AddPair('sites', JS);
    for var S in pReport.Sites do
    begin
      var O:= TJSONObject.Create;
      JS.AddElement(O);
      O.AddPair('mode', S.Mode);
      O.AddPair('file', S.FilePath);
      O.AddPair('line', TJSONNumber.Create(S.Line));
      O.AddPair('enclosing', S.Enclosing);
      O.AddPair('via', S.Via);
    end;
    Result.AddPair('sites_total', TJSONNumber.Create(pReport.SitesTotal));
    Result.AddPair('library_implementors', TJSONNumber.Create(pReport.LibraryImplementors));
    var JN:= TJSONArray.Create;
    Result.AddPair('notes', JN);
    for var N in pReport.Notes do JN.Add(N);
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function Bare(const pQName: string): string;
begin
  Result:= pQName.Substring(pQName.LastIndexOf('.') + 1);
end;

{ The class part of a method QName: 'U.TFoo.Bar' -> 'TFoo.Bar'. }
function Short(const pQName: string): string;
begin
  var Parts:= pQName.Split(['.']);
  Result:= if Length(Parts) >= 2 then Parts[High(Parts) - 1] + '.' + Parts[High(Parts)] else pQName;
end;

function HowText(const pRow: TImplRow): string;
begin
  Result:= pRow.How;
  if pRow.Via <> '' then Result:= Result + ' ' + Bare(pRow.Via);
  if pRow.Note <> '' then Result:= Result + '; ' + pRow.Note;
end;

function Loc(const pPath: string; pLine: Integer): string;
begin
  Result:= if pPath = '' then '' else ExtractFileName(pPath) + ':' + IntToStr(pLine);
end;

function ImplementorsReportToText(const pReport: TImplementorsReport): string;
begin
  var Sb:= TStringBuilder.Create;
  try
    Sb.AppendFormat('%s  (%s, %s)', [pReport.TargetQName, pReport.TargetKind, Loc(pReport.TargetFile, pReport.TargetLine)]).Append(sLineBreak);
    var Heading:= if pReport.TargetKind = 'class' then 'interface members answered'
      else if pReport.TargetKind = 'method' then 'interface members it answers'
      else 'implementors';
    Sb.AppendFormat('  %s (%d):', [Heading, Length(pReport.Implementors)]).Append(sLineBreak);
    for var R in pReport.Implementors do
    begin
      var Lead:= if (pReport.TargetKind = 'class') or (pReport.TargetKind = 'method') then Short(R.Member) else Bare(R.ClassQName);
      var What:= if R.Method <> '' then '  ' + Short(R.Method) else '';
      Sb.AppendFormat('    %s%s  (%s)  %s', [Lead, What, HowText(R), Loc(R.FilePath, R.Line)]);
      if R.BodyLine > 0 then Sb.AppendFormat('  body :%d', [R.BodyLine]);
      Sb.Append(sLineBreak);
    end;
    if Length(pReport.Unanswered) > 0 then
    begin
      Sb.AppendFormat('  not answered (%d):', [Length(pReport.Unanswered)]).Append(sLineBreak);
      for var R in pReport.Unanswered do
        Sb.AppendFormat('    %s  %s  (%s)', [Bare(R.ClassQName), Short(R.Member), HowText(R)]).Append(sLineBreak);
    end;
    if pReport.LibraryImplementors >= 0 then
      Sb.AppendFormat('  library implementors: %d', [pReport.LibraryImplementors]).Append(sLineBreak);
    if pReport.SitesTotal > 0 then
    begin
      var Attr:= if pReport.TargetKind = 'method' then 'reaching it through the interface'
        else 'attributed to the interface member per RB-5';
      Sb.AppendFormat('  sites (%d, %s):', [pReport.SitesTotal, Attr]).Append(sLineBreak);
      for var S in pReport.Sites do
      begin
        Sb.AppendFormat('    %s  %s  in %s', [Loc(S.FilePath, S.Line), S.Mode, S.Enclosing]);
        if S.Via <> '' then Sb.Append('  via ' + Short(S.Via));
        Sb.Append(sLineBreak);
      end;
      if pReport.SitesTotal > Length(pReport.Sites) then
        Sb.AppendFormat('    ... %d more (--max-sites)', [pReport.SitesTotal - Length(pReport.Sites)]).Append(sLineBreak);
    end;
    for var N in pReport.Notes do Sb.Append('  note: ' + N + sLineBreak);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function Xml(const pText: string): string;
begin
  Result:= pText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function ChartId(const pText: string): string;
begin
  Result:= 'n_' + TRegEx.Replace(pText, '[^A-Za-z0-9]', '_');
end;

function ImplementorsReportToChart(const pReport: TImplementorsReport; pMermaid: Boolean;
  const pHref: TFunc<string, Integer, string>): string;
var
  Sb: TStringBuilder;
  Nodes: TDictionary<string, Boolean>;

  procedure Node(const pId, pLabel: string; const pFile: string = ''; pLine: Integer = 0);
  begin
    if Nodes.ContainsKey(pId) then Exit;
    Nodes.Add(pId, True);
    var Lbl:= pLabel.Replace('"', '''');
    if pMermaid then Sb.AppendFormat('  %s["%s"]', [pId, Lbl]).Append(sLineBreak)
    else if Assigned(pHref) and (pFile <> '') and (pLine > 0) then
      Sb.AppendFormat('  %s [label=<<TABLE BORDER="0" CELLBORDER="0"><TR><TD HREF="%s" TITLE="%s  --  %s:%d"><FONT>%s</FONT></TD></TR></TABLE>>];',
        [pId, pHref(pFile, pLine), Xml(Lbl), Xml(ExtractFileName(pFile)), pLine, Xml(Lbl)]).Append(sLineBreak)
    else Sb.AppendFormat('  %s [label="%s"];', [pId, Lbl]).Append(sLineBreak);
  end;

  procedure Edge(const pFrom, pTo, pLabel: string);
  begin
    if pMermaid then Sb.AppendFormat('  %s -->|%s| %s', [pFrom, pLabel, pTo]).Append(sLineBreak)
    else Sb.AppendFormat('  %s -> %s [label="%s"];', [pFrom, pTo, pLabel]).Append(sLineBreak);
  end;

begin
  Sb:= TStringBuilder.Create;
  Nodes:= TDictionary<string, Boolean>.Create;
  try
    if pMermaid then Sb.Append('flowchart LR' + sLineBreak)
    else Sb.Append('digraph implementors {' + sLineBreak + '  rankdir=LR; node [shape=box, fontname="Consolas"];' + sLineBreak);
    var Root:= ChartId(pReport.TargetQName);
    Node(Root, Short(pReport.TargetQName) + ' (' + pReport.TargetKind + ')', pReport.TargetFile, pReport.TargetLine);
    for var R in pReport.Implementors + pReport.Unanswered do
    begin
      var C:= ChartId(R.ClassQName);
      Node(C, Bare(R.ClassQName), if R.Method = '' then R.FilePath else '', if R.Method = '' then R.Line else 0);
      Edge(Root, C, R.How);
      if R.Method <> '' then
      begin
        var M:= ChartId(R.Method);
        Node(M, Short(R.Method), R.FilePath, if R.BodyLine > 0 then R.BodyLine else R.Line);
        Edge(C, M, if R.Confidence = CONF_CERTAIN then 'answers' else R.Confidence);
      end
      else if R.Confidence = CONF_UNANSWERED then
      begin
        var U:= ChartId(R.ClassQName + '_unanswered');
        Node(U, 'not answered: ' + R.Note);
        Edge(C, U, 'gap');
      end;
    end;
    for var S in pReport.Sites do
      if S.Enclosing <> '' then
      begin
        var E:= ChartId('site_' + S.Enclosing);
        Node(E, Short(S.Enclosing), S.FilePath, S.Line);
        Edge(E, Root, S.Mode);
      end;
    if not pMermaid then Sb.Append('}' + sLineBreak);
    Result:= Sb.ToString;
  finally
    Nodes.Free;
    Sb.Free;
  end;
end;

end.
