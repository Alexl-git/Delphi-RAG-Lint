unit DRagLint.CLI.CallGraph;

// ---------------------------------------------------------------------------
// The call-graph verbs: dump-call-edges, find-callees, ambiguous-calls, call-path, call-graph,
// reverse-calltree and butterfly. Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>v14 (D5): drag-lint dump-call-edges --db PATH -- diagnostic dump of
/// every resolved call edge in the index, one per line, as
/// ref_id|target_qname|confidence. target_qname is the resolved target symbol's
/// qualified name (empty when the symbol is missing). Used to verify the
/// ResolveCallTargets pass populates call_edges with the right resolutions.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath is the index to dump.</param>
/// <returns>0 on success, 2 on usage error / missing or stale db.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.Core.Interfaces.ISymbolStore.DumpAllCallEdges, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, FileExists, Format, Writeln</para>
/// <para>Returns: 0</para>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.DumpAllCallEdges"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoDumpCallEdges(const AArgs: TArgs): Integer;

/// <summary>The library index find-callees opens beside the project index (item 4).</summary>
/// <param name="AArgs">Parsed args: DbPaths (a second --db) and LibraryDbs (--library-db).</param>
/// <param name="AProjectDb">In: --db (first). Out: the project DB, unchanged unless a
/// manifest-classified library was named first.</param>
/// <returns>An explicit --library-db (never 'none'), else a second --db that is not the
/// project DB, else ''. Existence is not checked here; the caller degrades to "not open".</returns>
/// <remarks>
/// Never reads the manifest to GUESS a library: opening one nobody named would make
/// the answer depend on a machine-level setting (the 2026-10-25 no-attach ruling).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoFindCallees (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.SplitConsumerDbs, ExpandFileName, SameText</para>
/// <para>Returns: ''; Lib; AArgs.LibraryDbs[0]</para>
/// <para>Mutates: AProjectDb (var)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.SplitConsumerDbs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindCalleesLibraryDb(const AArgs: TArgs; var AProjectDb: string): string;

/// <summary>v14 (D5 T9): drag-lint find-callees --qname X [--json] --db PATH
/// [--db LIBRARY | --library-db LIBRARY] --
/// the mirror of find-callers --resolved: every RESOLVED outgoing call made
/// from inside routine X's body (via call_edges), rendered as the target's
/// qualified name + confidence. X is resolved via FindSymbolsByQualifiedName;
/// an overloaded/duplicate qname is handled by unioning the callees of every
/// matching symbol. A routine with no resolved outgoing calls prints "0
/// callee(s)" (text) / an empty array (json) -- a valid, non-error answer.
/// Item 4: library-bound callees follow the resolved ones, marked "(library"
/// in text and {"external": true, "via": "edge"|"oracle"} in json; with no
/// library open the text ends "M external (library not open)" for the sites a
/// library could bind.</summary>
/// <param name="AArgs">Parsed CLI args; QName is the calling routine, DbPath the index.</param>
/// <returns>0 when --qname resolved and at least one callee (resolved or external) was found;
/// 1 if --qname does not resolve to any symbol OR it calls nothing (GitHub #17, 1.52 -- an empty
/// answer, as query find-callers); 2 on usage error / missing or stale db.</returns>
function DoFindCallees(const AArgs: TArgs): Integer;

/// <summary>v14 (D5 T9): drag-lint ambiguous-calls [--qname X|--file F] [--json]
/// --db PATH -- the resolver-coverage diagnostic. Lists call sites that name a
/// known routine/method but that the resolver did NOT pin to a single certain
/// target (confidence='ambiguous' in call_edges, or no call_edges row at all --
/// untypable receiver). Optionally scoped to --qname (the enclosing routine's
/// qualified name) or --file (a source file); with neither, it lists every
/// ambiguous/unverified call site in the whole DB (the global coverage view --
/// can be large; scoping is recommended). An empty result is a VALID "fully
/// resolved" answer, not an error.</summary>
/// <param name="AArgs">Parsed CLI args; QName and/or InFile (--file/--in) scope
/// the query, DbPath is the index.</param>
/// <returns>0 whenever the store opened OK, regardless of result count (empty
/// is a valid answer); 2 on usage error / missing or stale db.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.Core.Interfaces.ISymbolStore.GetAmbiguousCalls, FileExists, Format, Writeln</para>
/// <para>Returns: 0</para>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAmbiguousCalls"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoAmbiguousCalls(const AArgs: TArgs): Integer;

/// <summary>v14 (D5 T11): drag-lint call-path --from A --to B [--max-depth N]
/// [--json] --db PATH -- prints the SHORTEST resolved call path A -&gt; ... -&gt;
/// B over the resolved call_edges (does A eventually call B, and by what
/// route). A and B are resolved via ResolveEndpointIds (bare name or qname).
/// Traversal is a breadth-first search over the CALLEES direction
/// (GetCallEdgesFromSymbol -&gt; TargetSymbolId), starting from every id A
/// resolves to, stopping at the first id B resolves to. A VISITED set guards
/// cycles (a node is never revisited) and the search is additionally bounded by
/// --max-depth (default 20). BFS yields the shortest path; it is rebuilt from a
/// child-&gt;parent map. "No path within the cap" is a VALID answer (exit 1 +
/// "no path from A to B" / json found:false), NOT an error. Traverses within a
/// single DB -- ids are per-DB, so a path that would span indexes is out of
/// scope.</summary>
/// <param name="AArgs">Parsed CLI args; CallFrom is A, RenameTo (--to) is B,
/// MaxDepth the cap, DbPath the index.</param>
/// <returns>0 when a path was found and printed; 1 when both endpoints resolved
/// but no path exists within --max-depth; 2 on usage error / missing or
/// unreadable db (store-open failure) / an endpoint that resolves to no
/// symbol.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.CallGraph.ResolveEndpointIds, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.ReportNotFound, DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks, DRagLint.Core.Interfaces.ISymbolStore.GetCallEdgesFromSymbol, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, FileExists, Format, Writeln</para>
/// <para>Returns: 1; 0</para>
/// <para>Complexity: 30 (cyclomatic, outer body), 149 lines (full implementation)</para>
/// <seealso cref="DRagLint.CLI.CallGraph.ResolveEndpointIds"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.ReportNotFound"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetCallEdgesFromSymbol"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoCallPath(const AArgs: TArgs): Integer;

/// <summary>v14 (D5 T11): drag-lint callgraph --qname X [--direction
/// callers|callees] [--depth N] [--json] --db PATH -- prints the N-deep
/// resolved call tree rooted at X, over the resolved call_edges. --direction
/// callees (default) follows outgoing calls; callers follows resolved callers.
/// The tree is bounded by BOTH --depth (default 3) AND a global-visited set
/// that guards cycles: a recursive call graph WILL contain cycles (A calls B
/// calls A), and each node is expanded at most once -- a re-encounter prints
/// "&lt;qname&gt; (cycle)" (text) / cycle:true (json) and does not recurse, so
/// the traversal provably terminates. Renders an indented text tree (2 spaces
/// per level) or a nested {qname, children:[...]} JSON object. Traverses within
/// a single DB (ids are per-DB).</summary>
/// <param name="AArgs">Parsed CLI args; QName is the root, Direction the
/// direction, Depth the tree depth, DbPath the index.</param>
/// <returns>0 when the store opened OK and --qname resolved to at least one
/// symbol; 1 if --qname does not resolve to any symbol; 2 on usage error /
/// missing or unreadable db (store-open failure) / a bad --direction
/// value.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.CallGraph.BuildCallGraphJson, DRagLint.CLI.CallGraph.RenderCallGraphText, DRagLint.CLI.CallGraph.ResolveEndpointIds, DRagLint.CLI.Common.AddStalenessPairs, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.ReportNotFound, FileExists, Format, LowerCase, Trim, Writeln</para>
/// <para>Returns: 2; 0</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 72 lines (full implementation)</para>
/// <seealso cref="DRagLint.CLI.CallGraph.BuildCallGraphJson"/>
/// <seealso cref="DRagLint.CLI.CallGraph.RenderCallGraphText"/>
/// <seealso cref="DRagLint.CLI.CallGraph.ResolveEndpointIds"/>
/// <seealso cref="DRagLint.CLI.Common.AddStalenessPairs"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoCallGraph(const AArgs: TArgs): Integer;

/// <summary>drag-lint reverse-calltree --qname X [--direction callers|callees] [--depth N]
/// [--format text|json|dot|mermaid] [--json] --db PATH ... -- the N-deep call tree rooted
/// at X, with call sites (unit:line) and cycle markers. --direction callers (default,
/// back-compat with the original REVERSE tree) walks UPWARD via BuildReverseCallTree
/// (FindResolvedCallers): who calls X, who calls them. --direction callees walks
/// DOWNWARD via BuildForwardCallTree (GetCallEdgesFromSymbol): what X calls, what those
/// call. AArgs.Direction is shared with the callgraph verb, whose parser default is
/// empty (per-verb default applied locally, NOT a shared literal -- see ParseArgs);
/// an empty/absent/invalid --direction here resolves to 'callers', never callgraph's
/// 'callees' default. Both directions emit the SAME schema reverse-calltree/1 (root/
/// summary, per-node qname/site/file/line/cycle under the "callers" JSON key regardless
/// of direction). Text is an indented tree (2 spaces/level); --format dot|mermaid emit
/// a chart. With multiple --db, the first DB that resolves the qname is used (ids are
/// per-DB).</summary>
/// <param name="AArgs">QName=root, Direction=callers|callees (default callers),
/// Depth=tree depth (default 3), Format/AsJson=output, DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname unresolved in every DB; 2 usage error / no readable db (an explicit --db that is missing or stale is exit 2).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: BuildNodeJson, BuildSummaryJson, CharInSet, DRagLint.CLI.CallGraph.DoReverseCallTree.BuildTreeJson, DRagLint.CLI.CallGraph.DoReverseCallTree.EmitRendering, DRagLint.CLI.CallGraph.DoReverseCallTree.RenderNodeChart, DRagLint.CLI.CallGraph.DoReverseCallTree.RenderNodeText, DRagLint.CLI.CallGraph.ResolveEndpointIds, DRagLint.CLI.Common.AddStalenessPairs, DRagLint.CLI.Common.ExplicitDbsExist (+13 more)</para>
/// <para>Returns: 1; 0</para>
/// <para>Complexity: 29 (cyclomatic, outer body), 230 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.CallGraph.DoReverseCallTree.BuildTreeJson"/>
/// <seealso cref="DRagLint.CLI.CallGraph.DoReverseCallTree.EmitRendering"/>
/// <seealso cref="DRagLint.CLI.CallGraph.DoReverseCallTree.RenderNodeChart"/>
/// <seealso cref="DRagLint.CLI.CallGraph.DoReverseCallTree.RenderNodeText"/>
/// <seealso cref="DRagLint.CLI.CallGraph.ResolveEndpointIds"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoReverseCallTree(const AArgs: TArgs): Integer;

/// <summary>drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json]
/// [--output F] --db PATH [--db ...] -- Track 5.3 slice (Batch H2): composes a
/// symbol's CALLERS (upward wing, via BuildReverseCallTree) and CALLEES (downward
/// wing, via BuildForwardCallTree) into one "butterfly" chart, the static-export
/// counterpart to the in-IDE butterfly tab (Batch F). No new engine -- both trees
/// are the shipped TRCallTree/TRCallNode shape from DRagLint.Report.RCallTree;
/// composition works because both trees share the same root qname, so a chart
/// renderer that dedupes nodes by qname naturally attaches both wings to one
/// center node. Multi-db root resolution mirrors DoReverseCallTree exactly: the
/// first db whose ResolveEndpointIds(qname) is non-empty wins. --depth applies to
/// BOTH wings. dot/mermaid: callers render `caller -> X` (existing reverse-tree
/// orientation); callees render `X -> callee` (the REVERSED orientation, via the
/// AReverseEdges parameter added to the local RenderNodeChart). Root node is
/// styled distinctly in dot output (bold, `#ffd` fill) so the chart's center is
/// obvious. text: two headed sections (CALLERS upward / CALLEES downward), each
/// via RenderNodeText. json: schema "butterfly/1" wrapping the two full
/// reverse-calltree/1 tree objects under "callers"/"callees". Read-only.</summary>
/// <param name="AArgs">QName=root (required), Depth=tree depth for both wings
/// (default 3, &lt;0 clamped to 0), Format/AsJson=output (default dot),
/// Output=optional file path (else stdout), DbPath/DbPaths=index(es).</param>
/// <returns>0 ok (even with zero callers and/or zero callees -- still a valid
/// 1-node chart); 1 qname unresolved in every DB; 2 usage error / no readable db (an explicit --db that is missing or stale is exit 2).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: BuildNodeJson, BuildSummaryJson, CharInSet, DRagLint.CLI.CallGraph.DoButterfly.BuildTreeJson, DRagLint.CLI.CallGraph.DoButterfly.RenderNodeChart, DRagLint.CLI.CallGraph.DoButterfly.RenderNodeText, DRagLint.CLI.CallGraph.ResolveEndpointIds, DRagLint.CLI.Common.AddStalenessPairs, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.OpenReadOnlyStore (+12 more)</para>
/// <para>Returns: 1; 0</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 229 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.CallGraph.DoButterfly.BuildTreeJson"/>
/// <seealso cref="DRagLint.CLI.CallGraph.DoButterfly.RenderNodeChart"/>
/// <seealso cref="DRagLint.CLI.CallGraph.DoButterfly.RenderNodeText"/>
/// <seealso cref="DRagLint.CLI.CallGraph.ResolveEndpointIds"/>
/// <seealso cref="DRagLint.CLI.Common.AddStalenessPairs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoButterfly(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, Winapi.Windows, DRagLint.Core.OutputEncoding,
  System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding, System.JSON, System.DateUtils,
  System.Generics.Collections, System.SyncObjs, Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Async,
  FireDAC.Stan.Param, FireDAC.DApt, TreeSitter, DRagLint.Index.LibraryOracle, DRagLint.Core.Interfaces,
  DRagLint.Report.RCallTree, DRagLint.Query.Callers;

function DoDumpCallEdges(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore     ;
  Edges: TArray<TCallEdge>;
  E    : TCallEdge        ;
  QName: string           ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath]));
  Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // stale schema: 2 like every bad --db -- 1 is reserved for an EMPTY answer
  Edges:= Store.DumpAllCallEdges;
  for E in Edges do
  begin
    QName:= if E.TargetSymbolId > 0 then Store.GetSymbolById(E.TargetSymbolId).QualifiedName else '';
    Writeln(Format('%d|%s|%s', [E.RefId, QName, E.Confidence]));
  end;
  Result:= 0;
end; // function

type
  /// <summary>Counters of find-callees' external (library-bound) callee pass.</summary>
  TExternalCalleeTally = record
    /// <summary>External callees listed (stored external_target, or bound now by the oracle).</summary>
    Listed: Integer;
    /// <summary>Unresolved calls with a known receiver type that a library COULD bind but
    /// none is open; reported as "M external (library not open)".</summary>
    NotOpen: Integer;
  end;

function FindCalleesLibraryDb(const AArgs: TArgs; var AProjectDb: string): string;
begin
  Result:= '';
  if Length(AArgs.DbPaths) > 1 then
  begin
    var Lib: string;
    SplitConsumerDbs(AArgs, AArgs.DbPaths, AProjectDb, Lib);
    if AProjectDb = '' then AProjectDb:= AArgs.DbPath;
    if Lib = '' then
      for var D: string in AArgs.DbPaths do
        if TFile.Exists(D) and not SameText(ExpandFileName(D), ExpandFileName(AProjectDb)) then
          begin
            Lib:= D;
            Break;
          end;
    Result:= Lib;
  end;
  if (Result = '') and (Length(AArgs.LibraryDbs) > 0) and not SameText(AArgs.LibraryDbs[0], 'none') then
    Result:= AArgs.LibraryDbs[0];
end;

/// <summary>Lists the library-bound callees of one routine: its unresolved call refs that carry
/// a stored external_target ("edge") or whose receiver_type_text the oracle binds against the
/// open library right now ("oracle").</summary>
/// <param name="AStore">The project store.</param>
/// <param name="AOracle">Oracle over the open library stores (an empty list declines everything).</param>
/// <param name="ALibraryOpen">True when at least one library store is open.</param>
/// <param name="ASymbolId">The enclosing routine.</param>
/// <param name="AJson">Receives one object per external callee, or nil for text output.</param>
/// <param name="ATally">Incremented.</param>
/// <remarks>Binds only through TLibraryOracle (exactly one type, exactly one member); a decline
/// lists nothing. A site whose type text is known but whose library is not open only counts
/// toward NotOpen, so the answer says what it could not see instead of staying silent.</remarks>
procedure EmitExternalCallees(const AStore: ISymbolStore; AOracle: TLibraryOracle; ALibraryOpen: Boolean;
  ASymbolId: Int64; AJson: TJSONArray; var ATally: TExternalCalleeTally);
begin
  for var R: TReference in AStore.GetUnresolvedCallsFromSymbol(ASymbolId) do
  begin
    var QName: string:= R.ExternalTarget;
    var Via  : string:= 'edge';
    if QName = '' then
    begin
      if R.ReceiverTypeText = '' then Continue;
      if not ALibraryOpen then
      begin
        Inc(ATally.NotOpen);
        Continue;
      end;
      var Dot: Integer:= Pos('.', R.ReceiverTypeText);
      var TypeText: string:= (if Dot > 0 then Copy(R.ReceiverTypeText, 1, Dot - 1) else R.ReceiverTypeText);
      var Pending : string:= (if Dot > 0 then Copy(R.ReceiverTypeText, Dot + 1, MaxInt) else '');
      var UsedUnits: TArray<string>:= nil;
      for var U: TUnitUse in AStore.GetUnitUsesForFile(R.FileId) do UsedUnits:= UsedUnits + [LowerCase(U.UnitName)];
      var Reason: string;
      QName:= AOracle.Bind(TypeText, Pending, R.NameText, ekCall, UsedUnits, Reason);
      if QName = '' then Continue;
      Via:= 'oracle';
    end;
    Inc(ATally.Listed);
    if AJson <> nil then
    begin
      var JObj:= TJSONObject.Create;
      JObj.AddPair('target_qname', QName);
      JObj.AddPair('confidence'  , 'library');
      JObj.AddPair('external'    , TJSONTrue.Create);
      JObj.AddPair('via'         , Via);
      JObj.AddPair('receiver_type', R.ReceiverTypeText);
      { D08 / D10 (owner ruling 2026-11-08): only when the stored target is not a routine. }
      if R.ExternalKind = EXTERNAL_KIND_INDIRECT then JObj.AddPair('mode', CALLER_MODE_EVENT)
      else if R.ExternalKind = EXTERNAL_KIND_INTRINSIC then JObj.AddPair('mode', CALLER_MODE_BUILT_IN);
      JObj.AddPair('resolution'   , RESOLUTION_EXTERNAL); { XERJ item 3: LAST key }
      AJson.AddElement(JObj);
    end
    else Writeln(Format('  -> %s   (library, %s)%s', [QName, (if Via = 'edge' then 'by name' else 'resolved now'),
      (if R.ExternalKind = EXTERNAL_KIND_INDIRECT then '  [event]'
       else if R.ExternalKind = EXTERNAL_KIND_INTRINSIC then '  [built-in]' else '')]));
  end; // for R
end;

/// <summary>The routine-kind symbols (procedure / function / method / constructor / destructor)
/// whose bare name is AName -- find-callees --name's target set, the find-callers bare-name rule.</summary>
/// <param name="AStore">The open store to search.</param>
/// <param name="AName">The bare routine name, case-insensitive.</param>
/// <returns>Every matching routine, in store order; empty when none.</returns>
function RoutinesOfBareName(const AStore: ISymbolStore; const AName: string): TArray<TSymbol>;
var
  S: TSymbol       ;
  L: TList<TSymbol>;
begin
  L:= TList<TSymbol>.Create;
  try
    for S in AStore.FindSymbolsByExactName(AName) do
      if CanBeCallTarget(S.Kind) then L.Add(S);
    Result:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // function

function DoFindCallees(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore     ;
  Targets: TArray<TSymbol>  ;
  T      : TSymbol          ;
  Edges  : TArray<TCallEdge>;
  E      : TCallEdge        ;
  QName  : string           ;
  Total  : Integer          ;
  Ext    : TExternalCalleeTally;
  Oracle : TLibraryOracle   ;
begin
  { 1.52.1 SMALLS: --name <bare> is the find-callers spelling -- every routine of that bare name is a target. }
  var ByName: Boolean:= (AArgs.QName = '') and (AArgs.Name <> '');
  if (AArgs.QName = '') and not ByName then
  begin
    Writeln('Usage: drag-lint find-callees --qname X | --name <bare> [--json] --db PATH [--db LIBRARY | --library-db LIBRARY]');
    Exit(2);
  end;
  var ProjectDb: string:= AArgs.DbPath;
  var LibraryDb: string:= FindCalleesLibraryDb(AArgs, ProjectDb);
  if not FileExists(ProjectDb) then
  begin
    Writeln(Format('Database not found: %s', [ProjectDb]));
    Exit(2);
  end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(ProjectDb, RoOk);
  if not RoOk then Exit(2); // stale schema: 2 like every bad --db -- 1 is reserved for an EMPTY answer

  Targets:= if ByName then RoutinesOfBareName(Store, AArgs.Name) else Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Targets) = 0 then
  begin
    ReportNotFound(AArgs, Format('symbol not found: %s', [(if ByName then AArgs.Name else AArgs.QName)]));
    Exit(1);
  end;

  { The library is opened read-only and never written; a library that cannot be
    opened degrades to "library not open" with one stderr line, never an error. }
  var LibStores: TArray<ISymbolStore>:= nil;
  if LibraryDb <> '' then
  begin
    var LibOk: Boolean;
    var LibStore: ISymbolStore:= OpenReadOnlyStore(LibraryDb, LibOk, {AQuiet=}True);
    if LibOk then LibStores:= [LibStore]
    else Writeln(ErrOutput, 'NOTE: find-callees: the library index could not be opened (', LibraryDb, '); treated as not open.');
  end;

  Total:= 0;
  Ext:= Default(TExternalCalleeTally);
  Oracle:= TLibraryOracle.Create(LibStores);
  var JOut: TJSONArray:= nil;
  if AArgs.AsJson then JOut:= TJSONArray.Create;
  try
    for T in Targets do
    begin
      { several routines share the bare name: say which one the lines below belong to (text mode only;
        --json keeps its flat array, its shape is a contract). }
      if ByName and (Length(Targets) > 1) and not AArgs.AsJson then Writeln('# ', T.QualifiedName);
      Edges:= Store.GetCallEdgesFromSymbol(T.Id);
      for E in Edges do
      begin
        QName:= if E.TargetSymbolId > 0 then Store.GetSymbolById(E.TargetSymbolId).QualifiedName else '';
        if AArgs.AsJson then
        begin
          var JObj:= TJSONObject.Create;
          JObj.AddPair('target_qname', QName        );
          JObj.AddPair('confidence'  , E.Confidence  );
          JObj.AddPair('resolution'  , ResolutionOfConfidence(E.Confidence)); { XERJ item 3: LAST key }
          JOut.AddElement(JObj);
        end
        else Writeln(Format('  %s  [%s]', [QName, E.Confidence]));
        Inc(Total);
      end; // for E
      EmitExternalCallees(Store, Oracle, Length(LibStores) > 0, T.Id, JOut, Ext);
    end; // for T
    if AArgs.AsJson then Writeln(JOut.Format(2))
    else
    begin
      if (Total = 0) and (Ext.Listed = 0) then Writeln('0 callee(s)');
      if (Ext.Listed > 0) or (Ext.NotOpen > 0) then
        Writeln(Format('%d resolved + %d external%s', [Total, Ext.Listed,
          (if Ext.NotOpen > 0 then Format('; %d external (library not open)', [Ext.NotOpen]) else '')]));
    end;
  finally
    JOut.Free;
    Oracle.Free;
  end; // try
  { GitHub #17 (owner ruling 1.52): no callee at all is an EMPTY answer -- exit 1, as
    query find-callers. An external callee whose library is not open still counts. }
  Result:= if (Total = 0) and (Ext.Listed = 0) and (Ext.NotOpen = 0) then 1 else 0;
end; // function

function DoAmbiguousCalls(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore          ;
  Rows : TArray<TResolvedCaller>;
  R    : TResolvedCaller        ;
begin
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath]));
  Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // stale schema: 2 like every bad --db -- 1 is reserved for an EMPTY answer

  Rows:= Store.GetAmbiguousCalls(AArgs.QName, AArgs.InFile);

  if AArgs.AsJson then
  begin
    var JOut:= TJSONArray.Create;
    try
      for R in Rows do
      begin
        var JObj:= TJSONObject.Create;
        JObj.AddPair('enclosing_qname', R.EnclosingQName);
        JObj.AddPair('file'           , R.Location       );
        JObj.AddPair('confidence'     , R.Confidence     );
        JOut.AddElement(JObj);
      end; // for R
      Writeln(JOut.Format(2));
    finally
      JOut.Free;
    end; // try
  end
  else
  begin
    for R in Rows do
      Writeln(Format('  %s  (%s)  [%s]', [R.EnclosingQName, R.Location, R.Confidence]));
    if Length(Rows) = 0 then Writeln('0 ambiguous call(s) -- fully resolved')
    else Writeln(Format('%d ambiguous call(s)', [Length(Rows)]));
  end; // if
  Result:= 0;
end; // function

/// <summary>v14 (D5 T11): resolve a --from/--to/--qname endpoint (a bare name
/// OR a fully-qualified name) to symbol ids, for the call-graph traversal
/// verbs. Tries exact-name first (FindSymbolsByExactName -- lets a test pass a
/// bare method name like 'StepA'), then falls back to qualified-name lookup
/// (FindSymbolsByQualifiedName -- 'unit.TClass.Method'). Returns every matching
/// symbol id (an overloaded/duplicated name yields several); empty array when
/// the name resolves to nothing.</summary>
/// <param name="AStore">The open store to resolve against.</param>
/// <param name="AName">The endpoint name (bare or qualified).</param>
/// <returns>All matching symbol ids (may be empty).</returns>
function ResolveEndpointIds(const AStore: ISymbolStore; const AName: string): TArray<Int64>;
var
  Syms: TArray<TSymbol>;
  S   : TSymbol        ;
  L   : TList<Int64>   ;
begin
  L:= TList<Int64>.Create;
  try
    Syms:= AStore.FindSymbolsByExactName(AName);
    if Length(Syms) = 0 then Syms:= AStore.FindSymbolsByQualifiedName(AName);
    for S in Syms do
      if not L.Contains(S.Id) then L.Add(S.Id);
    Result:= L.ToArray;
  finally
    L.Free;
  end; // try
end; // function

function DoCallPath(const AArgs: TArgs): Integer;
var
  Store   : ISymbolStore              ;
  FromIds : TArray<Int64>             ;
  ToIds   : TArray<Int64>             ;
  ToSet   : TDictionary<Int64,Boolean>;
  Visited : TDictionary<Int64,Boolean>;
  Parent  : TDictionary<Int64,Int64>  ;
  Depths  : TDictionary<Int64,Integer>;
  Frontier: TQueue<Int64>             ;
  Cur     : Int64                     ;
  Hit     : Int64                     ;
  Found   : Boolean                   ;
  Edges   : TArray<TCallEdge>         ;
  E       : TCallEdge                 ;
  PathIds : TList<Int64>              ;
  QNames  : TList<string>             ;
  Walk    : Int64                     ;
  ToB     : string                    ;
  i       : Integer                   ;
begin
  ToB:= AArgs.RenameTo; // --to reuses RenameTo (rename + call-path never co-run)
  if (AArgs.CallFrom = '') or (ToB = '') then
  begin Writeln('Usage: drag-lint call-path --from A --to B [--max-depth N] [--json] --db PATH');
  Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath]));
  Exit(2); end;
  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // store-open/corruption failure = 2 (distinct from no-path = 1)

  FromIds:= ResolveEndpointIds(Store, AArgs.CallFrom);
  if Length(FromIds) = 0 then begin ReportNotFound(AArgs, Format('symbol not found: %s', [AArgs.CallFrom]));
  Exit(2); end;
  ToIds:= ResolveEndpointIds(Store, ToB);
  if Length(ToIds) = 0 then begin ReportNotFound(AArgs, Format('symbol not found: %s', [ToB]));
  Exit(2); end;

  var Cap: Integer:= AArgs.MaxDepth;
  if Cap <= 0 then Cap:= 20;

  ToSet   := TDictionary<Int64,Boolean>.Create;
  Visited := TDictionary<Int64,Boolean>.Create;
  Parent  := TDictionary<Int64,Int64>.Create;
  Depths  := TDictionary<Int64,Integer>.Create;
  Frontier:= TQueue<Int64>.Create;
  PathIds := TList<Int64>.Create;
  QNames  := TList<string>.Create;
  try
    for Hit in ToIds do ToSet.AddOrSetValue(Hit, True);

    // Seed the BFS with every id A resolves to (multi-source). A source that is
    // itself a target = the trivial length-0 path.
    Found:= False;
    Hit:= 0;
    for Cur in FromIds do
      if not Visited.ContainsKey(Cur) then
      begin
        Visited.Add(Cur, True);
        Depths.AddOrSetValue(Cur, 0);
        Frontier.Enqueue(Cur);
        if ToSet.ContainsKey(Cur) and not Found then begin Found:= True;
        Hit:= Cur; end;
      end;

    while (not Found) and (Frontier.Count > 0) do
    begin
      Cur:= Frontier.Dequeue;
      var D: Integer:= Depths[Cur];
      if D >= Cap then Continue; // depth cap: do not expand past the cap
      Edges:= Store.GetCallEdgesFromSymbol(Cur);
      for E in Edges do
      begin
        if E.TargetSymbolId <= 0 then Continue;
        if Visited.ContainsKey(E.TargetSymbolId) then Continue; // cycle/revisit guard
        Visited.Add(E.TargetSymbolId, True);
        Parent.AddOrSetValue(E.TargetSymbolId, Cur);
        Depths.AddOrSetValue(E.TargetSymbolId, D + 1);
        if ToSet.ContainsKey(E.TargetSymbolId) then
        begin Found:= True;
        Hit:= E.TargetSymbolId;
        Break; end;
        Frontier.Enqueue(E.TargetSymbolId);
      end; // for E
      { RB-5 P1: control also flows from an interface method into the methods
        that implement it (dispatch_edges 'implements'), one step per hop. }
      if not Found then
        for var DL in Store.FindDispatchLinks(Cur, False) do
        begin
          if DL.Kind <> 'implements' then Continue;
          if Visited.ContainsKey(DL.OtherId) then Continue;
          Visited.Add(DL.OtherId, True);
          Parent.AddOrSetValue(DL.OtherId, Cur);
          Depths.AddOrSetValue(DL.OtherId, D + 1);
          if ToSet.ContainsKey(DL.OtherId) then
          begin
            Found:= True;
            Hit  := DL.OtherId;
            Break;
          end;
          Frontier.Enqueue(DL.OtherId);
        end; // for DL
    end; // while

    if not Found then
    begin
      if AArgs.AsJson then
      begin
        var JNo:= TJSONObject.Create;
        try
          JNo.AddPair('found', TJSONBool.Create(False));
          JNo.AddPair('path' , TJSONArray.Create);
          Writeln(JNo.Format(2));
        finally JNo.Free; end;
      end
      else Writeln(Format('no path from %s to %s (within max-depth %d)', [AArgs.CallFrom, ToB, Cap]));
      Exit(1); // "not found" is a valid answer, signalled by exit 1
    end;

    // Reconstruct: walk parent links from Hit back to a seed (no parent entry).
    Walk:= Hit;
    while True do
    begin
      PathIds.Add(Walk);
      if not Parent.TryGetValue(Walk, Walk) then Break; // reached a BFS seed
    end;
    PathIds.Reverse; // parent-walk is target->source; flip to source->target

    for i:= 0 to PathIds.Count - 1 do
      QNames.Add(Store.GetSymbolById(PathIds[i]).QualifiedName);

    if AArgs.AsJson then
    begin
      var JOut:= TJSONObject.Create;
      try
        JOut.AddPair('found', TJSONBool.Create(True));
        var JArr:= TJSONArray.Create;
        for i:= 0 to QNames.Count - 1 do JArr.Add(QNames[i]);
        JOut.AddPair('path', JArr);
        Writeln(JOut.Format(2));
      finally JOut.Free; end;
    end
    else
    begin
      var Line: string:= '';
      for i:= 0 to QNames.Count - 1 do
      begin
        if i > 0 then Line:= Line + ' -> ';
        Line:= Line + QNames[i];
      end;
      Writeln(Line);
    end;
    Result:= 0;
  finally
    ToSet.Free;
    Visited.Free;
    Parent.Free;
    Depths.Free;
    Frontier.Free;
    PathIds.Free;
    QNames.Free;
  end; // try
end; // function

/// <summary>v14 (D5 T11): renders one node of the callgraph text tree (indented
/// 2 spaces per level) and recurses to --depth in the chosen direction. Cycle
/// policy is GLOBAL-VISITED: a symbol is expanded at most once across the whole
/// traversal; a second encounter prints "&lt;qname&gt; (cycle)" and does NOT
/// recurse, so the walk provably terminates (every recursion either hits the
/// depth cap or a node not yet in the visited set, and the id space is finite).
/// callees follows GetCallEdgesFromSymbol.TargetSymbolId; callers follows
/// FindResolvedCallers.EnclosingSymbolId.</summary>
/// <param name="AStore">Open store.</param>
/// <param name="AId">Symbol id of this node.</param>
/// <param name="ADepth">Remaining depth (0 = do not expand children).</param>
/// <param name="ACallees">True = callees direction, False = callers.</param>
/// <param name="AIndent">Current indent prefix.</param>
/// <param name="AVisited">Global visited set (shared across the whole tree).</param>
procedure RenderCallGraphText(const AStore: ISymbolStore; AId: Int64; ADepth: Integer;
  ACallees: Boolean; const AIndent: string; AVisited: TDictionary<Int64,Boolean>);
var
  QName    : string             ;
  Edges    : TArray<TCallEdge>  ;
  E        : TCallEdge          ;
  Callers  : TArray<TResolvedCaller>;
  C        : TResolvedCaller    ;
  ChildIds : TList<Int64>       ;
  Cid      : Int64              ;
begin
  QName:= AStore.GetSymbolById(AId).QualifiedName;
  if AVisited.ContainsKey(AId) then
  begin
    Writeln(Format('%s%s (cycle)', [AIndent, QName]));
    Exit; // already expanded elsewhere -- print marker, do not recurse
  end;
  AVisited.Add(AId, True);
  Writeln(Format('%s%s', [AIndent, QName]));
  if ADepth <= 0 then Exit;

  ChildIds:= TList<Int64>.Create;
  try
    if ACallees then
    begin
      Edges:= AStore.GetCallEdgesFromSymbol(AId);
      for E in Edges do
        if (E.TargetSymbolId > 0) and not ChildIds.Contains(E.TargetSymbolId) then
          ChildIds.Add(E.TargetSymbolId);
    end
    else
    begin
      Callers:= AStore.FindResolvedCallers(AId);
      for C in Callers do
        if (C.EnclosingSymbolId > 0) and not ChildIds.Contains(C.EnclosingSymbolId) then
          ChildIds.Add(C.EnclosingSymbolId);
    end;
    for Cid in ChildIds do
      RenderCallGraphText(AStore, Cid, ADepth - 1, ACallees, AIndent + '  ', AVisited);
  finally
    ChildIds.Free;
  end; // try
end; // procedure

/// <summary>v14 (D5 T11): builds one JSON node {qname, children:[...]} of the
/// callgraph, recursing to --depth with the SAME global-visited cycle policy as
/// the text renderer (a re-encountered node emits {qname, cycle:true} with no
/// children). Caller owns the returned TJSONObject.</summary>
/// <param name="AStore">Open store.</param>
/// <param name="AId">Symbol id of this node.</param>
/// <param name="ADepth">Remaining depth.</param>
/// <param name="ACallees">True = callees, False = callers.</param>
/// <param name="AVisited">Global visited set.</param>
/// <returns>A newly allocated JSON node the caller must free.</returns>
function BuildCallGraphJson(const AStore: ISymbolStore; AId: Int64; ADepth: Integer;
  ACallees: Boolean; AVisited: TDictionary<Int64,Boolean>): TJSONObject;
var
  QName   : string             ;
  Edges   : TArray<TCallEdge>  ;
  E       : TCallEdge          ;
  Callers : TArray<TResolvedCaller>;
  C       : TResolvedCaller    ;
  ChildIds: TList<Int64>       ;
  Cid     : Int64              ;
  Kids    : TJSONArray         ;
begin
  QName:= AStore.GetSymbolById(AId).QualifiedName;
  Result:= TJSONObject.Create;
  Result.AddPair('qname', QName);
  if AVisited.ContainsKey(AId) then
  begin
    Result.AddPair('cycle', TJSONBool.Create(True));
    Exit;
  end;
  AVisited.Add(AId, True);
  Kids:= TJSONArray.Create;
  Result.AddPair('children', Kids);
  if ADepth <= 0 then Exit;

  ChildIds:= TList<Int64>.Create;
  try
    if ACallees then
    begin
      Edges:= AStore.GetCallEdgesFromSymbol(AId);
      for E in Edges do
        if (E.TargetSymbolId > 0) and not ChildIds.Contains(E.TargetSymbolId) then
          ChildIds.Add(E.TargetSymbolId);
    end
    else
    begin
      Callers:= AStore.FindResolvedCallers(AId);
      for C in Callers do
        if (C.EnclosingSymbolId > 0) and not ChildIds.Contains(C.EnclosingSymbolId) then
          ChildIds.Add(C.EnclosingSymbolId);
    end;
    for Cid in ChildIds do
      Kids.AddElement(BuildCallGraphJson(AStore, Cid, ADepth - 1, ACallees, AVisited));
  finally
    ChildIds.Free;
  end; // try
end; // function

function DoCallGraph(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore              ;
  RootIds: TArray<Int64>             ;
  Visited: TDictionary<Int64,Boolean>;
  Dir    : string                    ;
  Callees: Boolean                   ;
  Depth  : Integer                   ;
  Rid    : Int64                     ;
begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint callgraph --qname X [--direction callers|callees] [--depth N] [--json|--format text|json] --db PATH');
  Exit(2); end;
  if not FileExists(AArgs.DbPath) then begin Writeln(Format('Database not found: %s', [AArgs.DbPath]));
  Exit(2); end;

  Dir:= LowerCase(Trim(AArgs.Direction));
  if Dir = '' then Dir:= 'callees';
  if (Dir <> 'callees') and (Dir <> 'callers') then
  begin Writeln(Format('ERROR: --direction must be callers|callees (got "%s")', [AArgs.Direction]));
  Exit(2); end;
  Callees:= (Dir = 'callees');

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  { --format WAS PARSED AND NEVER READ (Gitea drag-lint#16): `--format dot`
    printed the text tree with exit 0, so a caller asking for a graph got
    something else and no sign of it. json is the --json the other verbs also
    accept as --format json; text is the default; anything else is refused
    and pointed at the verb that does draw graphs. }
  var Fmt: string:= LowerCase(Trim(AArgs.Format));
  if (Fmt <> '') and (Fmt <> 'text') and (Fmt <> 'json') then
  begin
    Writeln(ErrOutput, Format('ERROR: callgraph --format must be text|json (got "%s"); ' +
      'for dot or mermaid use: drag-lint reverse-calltree --qname X --direction %s --format %s', [AArgs.Format, Dir, Fmt]));
    Exit(2);
  end;

  var RoOk: Boolean;
  Store:= OpenReadOnlyStore(AArgs.DbPath, RoOk);
  if not RoOk then Exit(2); // store-open/corruption failure = 2 (distinct from unresolved-qname = 1)

  RootIds:= ResolveEndpointIds(Store, AArgs.QName);
  if Length(RootIds) = 0 then begin ReportNotFound(AArgs, Format('symbol not found: %s', [AArgs.QName]));
  Exit(1); end;

  if AArgs.AsJson or (Fmt = 'json') then
  begin
    var JRoots:= TJSONArray.Create;
    try
      for Rid in RootIds do
      begin
        Visited:= TDictionary<Int64,Boolean>.Create;
        try
          var JTree: TJSONObject:= BuildCallGraphJson(Store, Rid, Depth, Callees, Visited);
          AddStalenessPairs(JTree, AArgs.DbPath); { ENG-3 }
          JRoots.AddElement(JTree);
        finally Visited.Free; end;
      end;
      // A single root prints the bare object; multiple (overloads) print an array.
      if JRoots.Count = 1 then Writeln((JRoots.Items[0] as TJSONObject).Format(2))
      else Writeln(JRoots.Format(2));
    finally JRoots.Free; end;
  end
  else
  begin
    for Rid in RootIds do
    begin
      Visited:= TDictionary<Int64,Boolean>.Create;
      try
        RenderCallGraphText(Store, Rid, Depth, Callees, '', Visited);
      finally Visited.Free; end;
    end;
  end;
  Result:= 0;
end; // function

function DoReverseCallTree(const AArgs: TArgs): Integer;
var
  Dbs    : TArray<string>;
  Db     : string        ;
  StoreDb: string        ;
  Store  : ISymbolStore  ;
  RootIds: TArray<Int64> ;
  Depth  : Integer       ;
  Fmt    : string        ;
  AnyRead: Boolean       ;
  Dir    : string        ;
  Rid    : Int64         ;
  Trees  : TList<TRCallTree>;
  Opts   : TRCallOptions ;

  function SanitizeId(const AName: string): string;
  var
    Ch: Char;
  begin
    Result:= '';
    for Ch in AName do
      Result:= if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Result + Ch else Result + '_';
    if (Result = '') or CharInSet(Result[1], ['0'..'9']) then Result:= '_' + Result;
  end;

  procedure RenderNodeText(const ANode: TRCallNode; const AIndent: string; ALines: TStrings);
  var
    Line : string;
    Kid  : TRCallNode;
  begin
    Line:= AIndent + ANode.QName;
    if ANode.Site <> '' then Line:= Line + Format(' [%s]', [ANode.Site]);
    if ANode.Cycle then Line:= Line + ' (cycle)';
    ALines.Add(Line);
    if ANode.Cycle then Exit; // already expanded elsewhere -- marker only, no recursion
    for Kid in ANode.Callers do
      RenderNodeText(Kid, AIndent + '  ', ALines);
  end; // procedure

  function BuildNodeJson(const ANode: TRCallNode): TJSONObject;
  var
    JKids: TJSONArray;
    Kid  : TRCallNode ;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('qname', ANode.QName);
    Result.AddPair('site' , ANode.Site );
    Result.AddPair('file' , ANode.SiteFile);
    Result.AddPair('line' , TJSONNumber.Create(ANode.SiteLine));
    Result.AddPair('cycle', TJSONBool.Create(ANode.Cycle));
    JKids:= TJSONArray.Create;
    for Kid in ANode.Callers do JKids.AddElement(BuildNodeJson(Kid));
    Result.AddPair('callers', JKids);
  end; // function

  function BuildSummaryJson(const ASummary: TRCallSummary): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('node_count'      , TJSONNumber.Create(ASummary.NodeCount      ));
    Result.AddPair('max_depth_reached', TJSONNumber.Create(ASummary.MaxDepthReached));
    Result.AddPair('cycle_count'     , TJSONNumber.Create(ASummary.CycleCount     ));
    Result.AddPair('truncated'       , TJSONBool.Create(ASummary.Truncated        ));
  end; // function

  function BuildTreeJson(const ATree: TRCallTree): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('schema' , 'reverse-calltree/1'    );
    Result.AddPair('root'   , BuildNodeJson(ATree.Root));
    Result.AddPair('summary', BuildSummaryJson(ATree.Summary));
  end; // function

  { An edge always points from the CALLER to the CALLEE. The children of a
    callers tree are callers (Kid -> ANode); the children of a callees tree --
    stored in the same Callers field -- are callees, so the arrow turns round
    (ANode -> Kid). Without that the callees graph claimed every callee called
    the root (Gitea drag-lint#14); butterfly's callees wing already did this. }
  procedure RenderNodeChart(const ANode: TRCallNode; ABuf: TStringBuilder; AIsDot: Boolean; ACalleeTree: Boolean);
  var
    Kid : TRCallNode;
    From: string    ;
    Dest: string    ;
  begin
    for Kid in ANode.Callers do
    begin
      if ACalleeTree then begin From:= ANode.QName;
      Dest:= Kid.QName;   end
      else                begin From:= Kid.QName;
      Dest:= ANode.QName; end;
      if AIsDot then ABuf.AppendLine(Format('  "%s" -> "%s";', [From, Dest]))
      else ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(From), SanitizeId(Dest)]));
      if not Kid.Cycle then RenderNodeChart(Kid, ABuf, AIsDot, ACalleeTree);
    end;
  end; // procedure

  { --output F writes the rendering to F (and says so on stdout), like butterfly and
    callgraph; without it the rendering goes to stdout. Until 1.41 the flag was parsed and
    ignored here. }
  procedure EmitRendering(const AText: string);
  begin
    if AArgs.Output <> '' then
    begin
      WriteOutputFile(AArgs.Output, AText);
      Writeln('Wrote ', AArgs.Output);
    end
    else Writeln(AText);
  end; // procedure

begin
  if not ExplicitDbsExist(AArgs, 'reverse-calltree') then Exit(2);
  if AArgs.QName = '' then
  begin ReportNotFoundFor(AArgs.AsJson or SameText(AArgs.Format, 'json'), 'Usage: drag-lint reverse-calltree --qname X [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH');
  Exit(2); end;

  Fmt:= LowerCase(Trim(AArgs.Format));

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  { --direction is SHARED with callgraph (TArgs.Direction), whose parser
    default is empty (per-verb default applied here, not globally -- see
    ParseArgs). reverse-calltree's historic behaviour is the UPWARD callers
    tree, so empty/absent/invalid --direction must resolve to 'callers', NOT
    callgraph's 'callees' default; only an explicit 'callees' switches this
    verb to the DOWNWARD tree via BuildForwardCallTree. }
  Dir:= LowerCase(Trim(AArgs.Direction));
  if (Dir <> 'callers') and (Dir <> 'callees') then Dir:= 'callers';

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin ReportNotFoundFor(AArgs.AsJson or (Fmt = 'json'), 'ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
  Exit(2); end;

  // Multi-db root resolution: use the FIRST db whose ResolveEndpointIds(qname)
  // is non-empty (mirrors DoHover's multi-db precedent). Exit 1 only if NO db
  // resolves the qname; exit 2 if no --db is even readable.
  Store  := nil;
  RootIds:= nil;
  AnyRead:= False;
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    var CandidateStore: ISymbolStore:= OpenReadOnlyStore(Db, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'reverse-calltree', Db) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    AnyRead:= True;
    var CandidateIds: TArray<Int64>:= ResolveEndpointIds(CandidateStore, AArgs.QName);
    if Length(CandidateIds) > 0 then
    begin
      Store  := CandidateStore;
      StoreDb:= Db; { ENG-3: the envelope's stale/stale_files describe THIS index }
      RootIds:= CandidateIds;
      Break;
    end;
  end;
  { An index was read but none resolved the qname: that is "not found" (exit 1), as the comment
    above promises -- not "no readable index" (exit 2), which this used to print for both. }
  if (Store = nil) and AnyRead then
  begin
    ReportNotFoundFor(AArgs.AsJson or (Fmt = 'json'), Format('symbol not found: %s', [AArgs.QName]));
    Exit(1);
  end;
  if Store = nil then begin ReportNotFoundFor(AArgs.AsJson or (Fmt = 'json'), 'ERROR: no readable drag-lint index among --db path(s)');
  Exit(2); end;
  if Length(RootIds) = 0 then begin ReportNotFoundFor(AArgs.AsJson or (Fmt = 'json'), Format('symbol not found: %s', [AArgs.QName]));
  Exit(1); end;

  Opts.Depth:= Depth;

  Trees:= TList<TRCallTree>.Create;
  try
    for Rid in RootIds do
      if Dir = 'callees' then
        Trees.Add(BuildForwardCallTree(Store, Rid, Opts))
      else
        Trees.Add(BuildReverseCallTree(Store, Rid, Opts));

    if (Fmt = 'dot') or (Fmt = 'mermaid') then
    begin
      var Buf: TStringBuilder:= TStringBuilder.Create;
      try
        if Fmt = 'dot' then
        begin
          Buf.AppendLine('// Generated by drag-lint reverse-calltree');
          Buf.AppendLine('digraph DragLintReverseCallTree {');
          Buf.AppendLine('  rankdir=LR;');
          Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];');
          Buf.AppendLine('  edge [color="#888"];');
        end
        else
        begin
          Buf.AppendLine('%% Generated by drag-lint reverse-calltree');
          Buf.AppendLine('graph LR');
        end;
        for var T in Trees do RenderNodeChart(T.Root, Buf, Fmt = 'dot', Dir = 'callees');
        if Fmt = 'dot' then Buf.AppendLine('}');
        EmitRendering(Buf.ToString);
      finally
        Buf.Free;
      end;
    end
    else if (Fmt = 'json') or ((Fmt = '') and AArgs.AsJson) then
    begin
      var JRoots: TJSONArray:= TJSONArray.Create;
      try
        for var T in Trees do
        begin
          var JTree: TJSONObject:= BuildTreeJson(T);
          AddStalenessPairs(JTree, StoreDb); { ENG-3 }
          JRoots.AddElement(JTree);
        end;
        // A single root prints the bare object; multiple (overloads) print an array.
        if JRoots.Count = 1 then EmitRendering((JRoots.Items[0] as TJSONObject).Format(2))
        else EmitRendering(JRoots.Format(2));
      finally
        JRoots.Free;
      end;
    end
    else // text (default, or explicit --format text)
    begin
      var Lines: TStringList:= TStringList.Create;
      try
        for var T in Trees do RenderNodeText(T.Root, '', Lines);
        EmitRendering(Lines.Text);
      finally
        Lines.Free;
      end;
    end;
  finally
    Trees.Free;
  end; // try
  Result:= 0;
end; // function

function DoButterfly(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>;
  Db       : string        ;
  StoreDb  : string        ;
  Store    : ISymbolStore  ;
  RootIds  : TArray<Int64> ;
  Depth    : Integer       ;
  Fmt      : string        ;
  Opts     : TRCallOptions ;
  ReverseTree: TRCallTree  ;
  ForwardTree: TRCallTree  ;

  function SanitizeId(const AName: string): string;
  var
    Ch: Char;
  begin
    Result:= '';
    for Ch in AName do
      Result:= if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Result + Ch else Result + '_';
    if (Result = '') or CharInSet(Result[1], ['0'..'9']) then Result:= '_' + Result;
  end;

  procedure RenderNodeText(const ANode: TRCallNode; const AIndent: string; ALines: TStrings);
  var
    Line : string;
    Kid  : TRCallNode;
  begin
    Line:= AIndent + ANode.QName;
    if ANode.Site <> '' then Line:= Line + Format(' [%s]', [ANode.Site]);
    if ANode.Cycle then Line:= Line + ' (cycle)';
    ALines.Add(Line);
    if ANode.Cycle then Exit; // already expanded elsewhere -- marker only, no recursion
    for Kid in ANode.Callers do
      RenderNodeText(Kid, AIndent + '  ', ALines);
  end; // procedure

  function BuildNodeJson(const ANode: TRCallNode): TJSONObject;
  var
    JKids: TJSONArray;
    Kid  : TRCallNode ;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('qname', ANode.QName);
    Result.AddPair('site' , ANode.Site );
    Result.AddPair('file' , ANode.SiteFile);
    Result.AddPair('line' , TJSONNumber.Create(ANode.SiteLine));
    Result.AddPair('cycle', TJSONBool.Create(ANode.Cycle));
    JKids:= TJSONArray.Create;
    for Kid in ANode.Callers do JKids.AddElement(BuildNodeJson(Kid));
    Result.AddPair('callers', JKids);
  end; // function

  function BuildSummaryJson(const ASummary: TRCallSummary): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('node_count'      , TJSONNumber.Create(ASummary.NodeCount      ));
    Result.AddPair('max_depth_reached', TJSONNumber.Create(ASummary.MaxDepthReached));
    Result.AddPair('cycle_count'     , TJSONNumber.Create(ASummary.CycleCount     ));
    Result.AddPair('truncated'       , TJSONBool.Create(ASummary.Truncated        ));
  end; // function

  function BuildTreeJson(const ATree: TRCallTree): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('schema' , 'reverse-calltree/1'    );
    Result.AddPair('root'   , BuildNodeJson(ATree.Root));
    Result.AddPair('summary', BuildSummaryJson(ATree.Summary));
  end; // function

  // AReverseEdges=False: caller orientation (Kid -> ANode), the existing
  // reverse-tree emit direction, used for the CALLERS wing. AReverseEdges=True:
  // emits the OPPOSITE (ANode -> Kid), used for the CALLEES wing (ANode.Callers
  // holds the callees for a forward tree; field name kept for record reuse --
  // see TRCallNode doc comment).
  procedure RenderNodeChart(const ANode: TRCallNode; ABuf: TStringBuilder; AIsDot: Boolean; AReverseEdges: Boolean);
  var
    Kid: TRCallNode;
  begin
    for Kid in ANode.Callers do
    begin
      if AIsDot then
      begin
        if AReverseEdges then ABuf.AppendLine(Format('  "%s" -> "%s";', [ANode.QName, Kid.QName]))
        else ABuf.AppendLine(Format('  "%s" -> "%s";', [Kid.QName, ANode.QName]));
      end
      else
      begin
        if AReverseEdges then ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(ANode.QName), SanitizeId(Kid.QName)]))
        else ABuf.AppendLine(Format('  %s --> %s', [SanitizeId(Kid.QName), SanitizeId(ANode.QName)]));
      end;
      if not Kid.Cycle then RenderNodeChart(Kid, ABuf, AIsDot, AReverseEdges);
    end;
  end; // procedure

begin
  if not ExplicitDbsExist(AArgs, 'butterfly') then Exit(2);
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH');
  Exit(2); end;

  Fmt:= LowerCase(Trim(AArgs.Format));
  if Fmt = '' then Fmt:= 'dot'; // chart verb -- default dot (unlike reverse-calltree's text default)

  Depth:= AArgs.Depth;
  if Depth < 0 then Depth:= 0;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
  Exit(2); end;

  // Multi-db root resolution: first db whose ResolveEndpointIds(qname) is
  // non-empty wins. AnyDbOpened tracks whether at least one --db path opened
  // read-only successfully, INDEPENDENT of whether the qname resolved in it --
  // this distinguishes "no readable db at all" (exit 2) from "every db opened
  // fine but none of them declares this qname" (exit 1). NOTE: DoReverseCallTree's
  // equivalent loop lacks this distinction (Store only gets assigned on a qname
  // match, so an all-readable-but-unresolved-qname run there falls through to
  // the SAME "no readable index" exit-2 message instead of exit 1 -- a
  // pre-existing bug, not fixed here since it is out of scope for this verb).
  Store  := nil;
  RootIds:= nil;
  var AnyDbOpened: Boolean:= False;
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    var CandidateStore: ISymbolStore:= OpenReadOnlyStore(Db, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'butterfly', Db) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    AnyDbOpened:= True;
    var CandidateIds: TArray<Int64>:= ResolveEndpointIds(CandidateStore, AArgs.QName);
    if Length(CandidateIds) > 0 then
    begin
      Store  := CandidateStore;
      StoreDb:= Db; { ENG-3: the envelope's stale/stale_files describe THIS index }
      RootIds:= CandidateIds;
      Break;
    end;
  end;
  if not AnyDbOpened then begin Writeln('ERROR: no readable drag-lint index among --db path(s)');
  Exit(2); end;
  if Store = nil then
  begin
    ReportNotFoundFor(AArgs.AsJson or SameText(AArgs.Format, 'json'), Format('symbol not found: %s', [AArgs.QName]));
    Exit(1);
  end;

  Opts.Depth:= Depth;

  // Overloads: butterfly composes a SINGLE center node, so use the first
  // resolved root id (matches the common case; overload fan-out is out of
  // scope for a v1 chart verb -- reverse-calltree's multi-root loop is not
  // reused here because the composed chart has exactly one center).
  ReverseTree:= BuildReverseCallTree(Store, RootIds[0], Opts);
  ForwardTree:= BuildForwardCallTree(Store, RootIds[0], Opts);

  if (Fmt = 'dot') or (Fmt = 'mermaid') then
  begin
    var Buf: TStringBuilder:= TStringBuilder.Create;
    try
      if Fmt = 'dot' then
      begin
        Buf.AppendLine('// Generated by drag-lint butterfly');
        Buf.AppendLine('digraph DragLintButterfly {');
        Buf.AppendLine('  rankdir=LR;');
        Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];');
        Buf.AppendLine('  edge [color="#888"];');
        Buf.AppendLine(Format('  "%s" [fillcolor="#ffd", style="filled,bold"];', [ReverseTree.Root.QName]));
      end
      else
      begin
        Buf.AppendLine('%% Generated by drag-lint butterfly');
        Buf.AppendLine('graph LR');
      end;
      RenderNodeChart(ReverseTree.Root, Buf, Fmt = 'dot', False); // callers wing: caller -> X
      RenderNodeChart(ForwardTree.Root, Buf, Fmt = 'dot', True);  // callees wing: X -> callee
      if Fmt = 'dot' then Buf.AppendLine('}');

      if AArgs.Output <> '' then
      begin
        WriteOutputFile(AArgs.Output, Buf.ToString);
        Writeln('Wrote ', AArgs.Output);
      end
      else Writeln(Buf.ToString);
    finally
      Buf.Free;
    end;
  end
  else if (Fmt = 'json') or AArgs.AsJson then
  begin
    var JOut: TJSONObject:= TJSONObject.Create;
    try
      JOut.AddPair('schema' , 'butterfly/1'    );
      JOut.AddPair('qname'  , ReverseTree.Root.QName);
      JOut.AddPair('callers', BuildTreeJson(ReverseTree));
      JOut.AddPair('callees', BuildTreeJson(ForwardTree));
      AddStalenessPairs(JOut, StoreDb); { ENG-3 }
      var OutStr: string:= JOut.Format(2);
      if AArgs.Output <> '' then
      begin
        WriteOutputFile(AArgs.Output, OutStr);
        Writeln('Wrote ', AArgs.Output);
      end
      else Writeln(OutStr);
    finally
      JOut.Free;
    end;
  end
  else // text (default explicit --format text)
  begin
    var Lines: TStringList:= TStringList.Create;
    try
      Lines.Add('CALLERS (upward):');
      RenderNodeText(ReverseTree.Root, '  ', Lines);
      Lines.Add('CALLEES (downward):');
      RenderNodeText(ForwardTree.Root, '  ', Lines);
      if AArgs.Output <> '' then
      begin
        WriteOutputFile(AArgs.Output, Lines.Text);
        Writeln('Wrote ', AArgs.Output);
      end
      else Writeln(Lines.Text);
    finally
      Lines.Free;
    end;
  end;
  Result:= 0;
end; // function

end.
