unit DRagLint.Query.Callers;

{ Shared caller queries -- the ONE place resolved callers and name-matched
  callers are computed.

  WHY THIS UNIT EXISTS. The resolved-caller rules (call_edges plus the
  callback-reach rules below) lived inline inside DRagLint.CLI.DoQuery, so the
  only way to ask the question was to SPAWN drag-lint.exe. The IDE hover did
  exactly that -- twice per hover, each spawn re-opening indexes the already
  running LSP server had open and warm. Serving the hover over the LSP needed
  the same computation callable in-process, and duplicating it would have left
  two copies of the callback rules to drift apart. So it moved here, and the CLI
  now renders from these functions rather than owning them.

  The CLI's rendered output -- text and --json alike -- is unchanged by the
  move, which is what run_query_callers_shared_guard.ps1 pins. }

interface

uses
  System.SysUtils           ,
  System.Generics.Collections,
  DRagLint.Core.Model       ,
  DRagLint.Core.Interfaces  ;


type
  /// <summary>One caller row, in the shape both the CLI renderer and the LSP
  /// hoverBundle reply need.</summary>
  /// <remarks>
  /// FilePath is file-NAME-only for resolved and callback rows (the
  /// idempotency design the JSON contract already carries) and the FULL path
  /// for name-matched rows, because the hover popup navigates to them. Line is
  /// meaningful only when HasLine is True: a resolved or callback row whose
  /// caller symbol id is unknown deliberately carries no caller line, and the
  /// JSON renderer must omit the pair rather than emit 0.
  /// TWO LINES, TWO FIELDS: CallSiteLine is the site on every row; Line is the
  /// caller ROUTINE's declaration line on resolved and callback rows (the
  /// CLI's `caller_line`) and the reference's own line on name-matched rows.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Charts.MemberAccess.GroupRoutines (DRagLint.Charts.MemberAccess.pas) ?, DRagLint.Charts.MemberAccess.HitsOf (DRagLint.Charts.MemberAccess.pas) ?, DRagLint.Query.Callers.NameCallersForName (DRagLint.Query.Callers.pas), DRagLint.Query.Callers.ResolvedCallersForName (DRagLint.Query.Callers.pas), DRagLint.Query.Callers.RowOfCaller (DRagLint.Query.Callers.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.Charts.MemberAccess, DRagLint.LSP.Server, DRagLint.Query.Callers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryCallerRow = record
    CallerQName: string ;
    FilePath   : string ;
    Line       : Integer;
    HasLine    : Boolean;
    /// <summary>'certain' | 'ambiguous' (from call_edges) | 'callback' (a
    /// by-name reach; see ResolvedCallersForName's remarks).</summary>
    Confidence : string ;
    TargetQName: string ;
    /// <summary>True on the first row of each TARGET's caller run.</summary>
    /// <remarks>Grouping cannot be recovered from TargetQName alone: OVERLOADS
    /// are distinct target symbols that share one qualified name, and the CLI's
    /// text form prints a header per TARGET -- so `TFoo.Create:` appears twice
    /// for two overloads that both have callers. Deriving the header from "the
    /// name changed" would silently merge them into one group. Always False on
    /// callback rows, which the text form prints with no header at all.</remarks>
    FirstOfTarget: Boolean;
    /// <summary>The call site's own source line, already trimmed. Filled by
    /// NameCallersForName only; always empty for resolved rows.</summary>
    /// <remarks>A resolved row's text is NOT filled here on purpose: this
    /// function answers from the index alone, and the text a reader wants is
    /// the one in the editor's UNSAVED buffer. Only the LSP has that, so it
    /// renders the line itself from FullPath + CallSiteLine.</remarks>
    CodeText   : string ;
    /// <summary>FilePath, fully qualified. Filled for resolved and callback
    /// rows, where FilePath is filename-only by contract.</summary>
    /// <remarks>Equal to FilePath for name-matched rows, which already carry
    /// the full path.</remarks>
    FullPath   : string ;
    /// <summary>The line of the CALL ITSELF, as opposed to Line, which for a
    /// resolved or callback row is the caller ROUTINE's start line.</summary>
    /// <remarks>Both are wanted and neither substitutes for the other.
    /// CallSiteLine is what a reader means by "called from": the exact
    /// statement, and it is what the CLI prints as `line` on EVERY row
    /// (2026-09-23, C1). Until then the CLI printed Line there for the
    /// call_edges rows and the site for callback rows -- one key, two meanings
    /// chosen by the arm that produced the row. Line survives as the CLI's
    /// `caller_line`. 0 when unknown.</remarks>
    CallSiteLine: Integer;
    /// <summary>Id of the symbol whose body contains this reference; 0 at unit
    /// level. Filled by NameCallersForName only.</summary>
    /// <remarks>The scoping key for a PARAMETER or LOCAL, which cannot be
    /// referenced outside the routine that declares it. Without it a usage list
    /// gathered by bare name sweeps in every same-named parameter in the index
    /// -- reported 2026-08-19 for two constructors that both take `btn`.
    /// Ids are per-DATABASE, so it is only meaningful against the store the row
    /// came from.</remarks>
    EnclosingSymbolId: Int64;
    /// <summary>'read' | 'write' when the target is a PROPERTY or FIELD and
    /// this row is an access bound by the resolver (2026-09-16); '' for a
    /// routine call. Rendered as a trailing key/bracket only when set, so
    /// routine rows are byte-identical to what they were.</summary>
    Mode       : string ;
    /// <summary>XERJ item 3: how sure the row is, DERIVED -- 'exact' | 'ambiguous' |
    /// 'external' | 'name-only' (RESOLUTION_* in DRagLint.Core.Model). Rendered as the
    /// LAST key of every caller JSON row.</summary>
    /// <remarks>A resolved row maps from its call_edges Confidence; a 'callback' reach is
    /// by-name and so 'name-only'; a name-matched row carries the TReference.Resolution the
    /// store derived from call_edges / refs.external_target / refs.symbol_id.</remarks>
    Resolution : string ;
    /// <summary>Qualified name of the INTERFACE method this site calls, when
    /// the row is a caller that reaches TargetQName only through interface
    /// dispatch (RB-5 P1); '' for a direct caller.</summary>
    Via        : string ;
    /// <summary>'interface' on a via row; '' otherwise. Reserved for other
    /// dispatch kinds.</summary>
    ViaKind    : string ;
    /// <summary>On the FIRST row of a via group: the number of sites in the
    /// group (the group is the consecutive rows sharing TargetQName and Via);
    /// 0 on every other row. The text renderer prints its header from it.</summary>
    ViaCount   : Integer;
    /// <summary>'certain' | 'ambiguous': the dispatch_edges confidence of the
    /// implements edge that links TargetQName to Via. Set on via rows only.</summary>
    ViaEdge    : string ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas), DRagLint.Charts.MemberAccess.HitsOf (DRagLint.Charts.MemberAccess.pas), DRagLint.CLI.DoImpact (DRagLint.CLI.pas), DRagLint.LSP.Server.HoverResolvedCallers (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.FindCallersText (DRagLint.MCP.Server.pas) (+3 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryCallerRows = TArray<TQueryCallerRow>;

type
  /// <summary>Counts of caller/callee rows per derived resolution kind, for the text
  /// totals `12 callers (9 exact, 1 ambiguous, 2 name-only)` and the context JSON
  /// `caller_resolution` object.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.PrintReferenceLines (DRagLint.CLI.pas) ?, DRagLint.Context.Bundler.TContextBundler.RenderJson (DRagLint.Context.Bundler.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TResolutionTally = record
    Exact    : Integer;
    Ambiguous: Integer;
    External : Integer;
    NameOnly : Integer;
    /// <summary>Counts one row of kind <paramref name="AKind"/> (a RESOLUTION_* value; an
    /// unknown or empty kind is not counted).</summary>
    /// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.MemberAccess.GroupRoutines (DRagLint.Charts.MemberAccess.pas) ?, DRagLint.Charts.MemberAccess.LoadSites (DRagLint.Charts.MemberAccess.pas) ?, DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.PrintReferenceLines (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.RenderJson (DRagLint.Context.Bundler.pas) (+81 more)</para>
    /// <para>Writes: Exact, Ambiguous, External, NameOnly</para>
    /// <seealso cref="DRagLint.Query.Callers.TResolutionTally.ToText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Add(const AKind: string);
    /// <summary>`9 exact, 1 ambiguous, 2 name-only`: only the kinds seen, in the order
    /// exact, ambiguous, external, name-only; '' when nothing was counted.</summary>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Query.Callers.TResolutionTally.ToText.Part, Format</para>
    /// <para>Reads: Exact, Ambiguous, External, NameOnly</para>
    /// <seealso cref="DRagLint.Query.Callers.TResolutionTally.ToText.Part"/>
    /// <seealso cref="DRagLint.Query.Callers.TResolutionTally.Add"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ToText: string;
  end;

/// <summary>Maps a call_edges confidence (or 'callback') to the derived resolution kind.</summary>
/// <param name="AConfidence">'certain' | 'ambiguous' | 'callback' | anything else.</param>
/// <returns>'ambiguous' for 'ambiguous'; 'name-only' for 'callback' (a by-name reach, no
/// edge); 'exact' for every other stored edge ('certain').</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.Query.Callers.MemberUsersForName.AddRows (DRagLint.Query.Callers.pas), DRagLint.Query.Callers.RowOfCaller (DRagLint.Query.Callers.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Returns: RESOLUTION_AMBIGUOUS; RESOLUTION_NAME_ONLY; RESOLUTION_EXACT</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolutionOfConfidence(const AConfidence: string): string;

/// <summary>Precise callers of every symbol matching <paramref name="AName"/>
/// in one store, keyed by resolved call edges rather than by name.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">Bare or qualified callee name, matched exactly.</param>
/// <param name="AWithDispatch"><!-- drag-lint:auto type -->Boolean = False</param>
/// <returns>Rows in the CLI's historical emission order: all resolved callers
/// grouped per matching target, then the callback reaches. Empty when nothing
/// matches.</returns>
/// <remarks>
/// <para>CALLBACK REACHES. A routine handed somewhere BY NAME --
/// <c>Register(Pred)</c>, <c>@Handler</c>, <c>OnFoo := Handler</c> -- is
/// reached from that site but is not CALLED there, so the indexer records a
/// refs.kind='read' row and no call_edges row. Without reporting those, the
/// query that is documented as the PRECISE one answers 0 for a live predicate
/// while the plain name path answers 1, and the honest reading of that 0 is
/// "dead code".</para>
/// <para>call_edges is deliberately NOT widened to carry these. An edge there
/// means a call, with a call site and arguments; inventing one would make
/// callgraph, impact and call-path assert control flow that does not exist at
/// that line. So the reach is reported here and marked 'callback', where it can
/// never be mistaken for a call.</para>
/// <para>A CALL AT THE SAME SITE means the read is part of an ordinary
/// invocation, not a callback pass. <c>Self.Run</c> emits THREE refs at one
/// line -- 'call', 'member-access', and a 'read' whose receiver is NULL -- so
/// neither kind nor receiver alone can tell it from <c>Register(Pred)</c>. The
/// position can: a genuine callback has no call of the SAME NAME at its own
/// line. An earlier attempt filtered on receiver_text and let Self.Run through,
/// because that ref's receiver is NULL.</para>
/// <para>Still name-keyed, so a local variable sharing a routine's name can
/// produce a spurious row; the 'callback' marker is what keeps that honest.</para>
/// <para>A 'read' that OWNS a call_edges row is a PARENLESS CALL
/// (<c>N := NextId</c>, bound since resolver 1.7.0-alpha) and is already a
/// resolved row, so a line holding one is not listed again as a callback.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.MemberAccess.CollectMemberAccess (DRagLint.Charts.MemberAccess.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.LSP.Server.HoverResolvedCallers (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.FindCallersText (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.Callers.DispatchCallersOf, DRagLint.Query.Callers.RowOfCaller, ExtractFileName, Format, LowerCase, Trim</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 110 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolvedCallersForName(const AStore: ISymbolStore; const AName: string; AWithDispatch: Boolean = False): TQueryCallerRows;

/// <summary>The callers that reach one implementing method only through the
/// INTERFACE method it implements (RB-5 P1).</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AImplId">Symbol id of the implementing method.</param>
/// <returns>For every dispatch_edges 'implements' edge into AImplId (climbing
/// through 'override' edges, bounded), the resolved callers of the interface
/// method, as rows with Via = the interface method's qualified name, ViaKind =
/// 'interface', TargetQName = AImplId's qualified name and ViaCount set on the
/// first row of each group. Empty on a database without dispatch_edges or when
/// nothing implements through an interface.</returns>
/// <remarks>
/// Only 'implements' edges are reported: a virtual override is not
/// part of the owner ruling and would churn every class-hierarchy answer. A call
/// whose receiver is class-typed binds to the class method (a direct caller) and
/// never appears here. Rows keep the call edge's own confidence; the dispatch
/// edge's confidence is ViaEdge, and an 'ambiguous' edge is marked by the
/// renderers.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoImpact (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.LSP.Server.HoverResolvedCallers (DRagLint.LSP.Server.pas), DRagLint.Query.Callers.ResolvedCallersForName (DRagLint.Query.Callers.pas), DRagLint.Query.CrossImpact.AnswerLocalDispatch (DRagLint.Query.CrossImpact.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Query.Callers.RowOfCaller</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDispatchLinks"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Query.Callers.RowOfCaller"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DispatchCallersOf(const AStore: ISymbolStore; AImplId: Int64): TQueryCallerRows;

/// <summary>Name-matched callers of <paramref name="AName"/> in one store,
/// each carrying its own source line.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">Callee name, matched exactly (kind-blind).</param>
/// <param name="AContextLines">Context radius to read; 1 is enough to recover
/// the call site's own line, which is all CodeText needs.</param>
/// <returns>One row per reference, FilePath fully qualified, CodeText set to
/// the call site's own trimmed source line (empty when the file could not be
/// read). Confidence and TargetQName are empty: a name match asserts neither.</returns>
/// <remarks>
/// Kind-blind by design -- this is the wide net the resolved query is
/// checked against, not a claim that each row is a call.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Query.Callers.CodeLineFromContext, Trim</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Query.Callers.CodeLineFromContext"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NameCallersForName(const AStore: ISymbolStore; const AName: string; AContextLines: Integer = 1): TQueryCallerRows;

/// <summary>The references `usages` reports for <paramref name="AName"/> in one
/// store: the CLI verb and the LSP `draglint/usages` reply both call this, so
/// the two cannot disagree on which rows exist.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">A bare name (`Streaming`) or a qualified one
/// (`TJob.Streaming`, `uJob.TJob.Streaming`).</param>
/// <param name="ADecls">The declarations AStore.FindSymbolsByExactName returned
/// for AName; used only for a qualified name.</param>
/// <returns>A bare name: every ref whose name_text matches, kind-blind (the
/// historical behaviour). A qualified name: the refs named by its LAST segment
/// that the resolver bound to one of ADecls -- refs.name_text never carries a
/// dot, so matching the dotted string answered 0 for everything.</returns>
/// <remarks>
/// A qualified query drops UNBOUND refs: an unbound `X.Streaming`
/// cannot be attributed to TJob rather than to any other Streaming.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoUsages (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleUsages (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: Copy, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Query.Callers.DropMemberAccessUnderCall, LastDelimiter</para>
/// <para>Returns: DropMemberAccessUnderCall(Kept.ToArray)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
/// <seealso cref="DRagLint.Query.Callers.DropMemberAccessUnderCall"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UsageRefsForName(const AStore: ISymbolStore; const AName: string; const ADecls: TArray<TSymbol>): TArray<TReference>;

/// <summary>The `usages` bucket a reference belongs to, given what the
/// resolver BOUND it to (HARDCAST-CALL, 1.42).</summary>
/// <param name="ARef">A reference from UsageRefsForName.</param>
/// <param name="ADecls">The declarations of the queried name in the SAME store
/// as ARef (symbol ids are per store); may be empty.</param>
/// <returns>'types' for a 'call' ref bound to one of ADecls whose kind is a
/// TYPE (class, interface, record, enum, type alias, class reference) -- a hard
/// cast `TEnum(X)`, which the parse cannot tell from a one-argument call and
/// the resolver binds to the enum (ResolveEnumCast) without a call edge.
/// Otherwise exactly UsageBucketOf(ARef).</returns>
/// <remarks>
/// The ref row itself stays kind 'call': enum-ordinal-persisted
/// selects those rows. Only the usages bucket changes. A call ref bound to a
/// routine, or unbound, is untouched. Shared by the CLI verb and the LSP
/// draglint/usages reply. Pinned by run_refs_142_shapes.ps1.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoUsages.GroupFor (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleUsages.GroupFor (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: DRagLint.Query.Callers.UsageBucketOf</para>
/// <para>Returns: UsageBucketOf(ARef)</para>
/// <para>Effect-free (proven)</para>
/// <seealso cref="DRagLint.Query.Callers.UsageBucketOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UsageBucketIn(const ARef: TReference; const ADecls: TArray<TSymbol>): string;

/// <summary>A name match's refs, minus those that cannot be a call of the name:
/// writes, and reads of a same-named local or parameter of the enclosing routine.</summary>
/// <param name="AStore">The store the refs came from; nil returns ARefs unchanged.</param>
/// <param name="ARefs">Name-matched refs (FindCallersByName and friends).</param>
/// <returns>The refs that can still be calls, in order. Shared by `query
/// find-callers` and the MCP find_callers tool.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.FindCallersText (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, SameText</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DropRefsThatCannotBeCallers(const AStore: ISymbolStore;
  const ARefs: TArray<TReference>): TArray<TReference>;

/// <summary>One ref per call SITE (file + line + column), keeping the
/// highest-ranked kind there ('call' over 'member-access' over 'read').</summary>
/// <param name="ARefs">Refs in display order.</param>
/// <returns>The refs with same-site duplicates collapsed, order preserved.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.FindCallersText (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: DRagLint.Query.Callers.CollapseRefsAtSameSite.KindRank, Format, SameText</para>
/// <seealso cref="DRagLint.Query.Callers.CollapseRefsAtSameSite.KindRank"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollapseRefsAtSameSite(const ARefs: TArray<TReference>): TArray<TReference>;

type
  /// <summary>One user of a member, as `usages --rw` lists it.</summary>
  /// <remarks>
  /// Via says by which route the site reaches the member: 'property'
  /// (through a property), 'field' (a mention of the property's backing field),
  /// 'getter' / 'setter' (a direct call of the accessor method), 'direct' (the
  /// member has no property in front of it). ViaName is the qualified name of the
  /// symbol the site is bound to. Arg says why a site that the index stores as a
  /// read is listed as a write: 'inc-dec' (the argument of Inc or Dec), 'var-arg'
  /// (the argument bound to a var parameter of a resolved call; the site is
  /// listed as a reader AND a writer) or 'out-arg' (an out parameter; a writer
  /// only); '' for every other site.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas) ?, DRagLint.CLI.DoUsagesReadersWriters.RowsJson (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsagesReadersWriters.WriteRows (DRagLint.CLI.pas) ?, DRagLint.Query.Callers.MemberUsersForName.AddRows (DRagLint.Query.Callers.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Query.Callers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMemberUserRow = record
    CallerQName: string ;
    FullPath   : string ;
    Line       : Integer;
    Via        : string ;
    ViaName    : string ;
    Confidence : string ;
    Resolution : string ;
    Arg        : string ;
  end;

  /// <summary>The users of one declaration, split into readers and writers.</summary>
  /// <remarks>
  /// Calls holds the sites that neither read nor write: the callers of a
  /// routine that is no property's accessor. ReadAccessor / WriteAccessor are set
  /// for a property only, as written in its declaration; their Kind is 'field',
  /// 'method' or 'unresolved' (declared by an ancestor, or a source the index no
  /// longer matches), '' when the property has no such accessor.
  /// BacksProperties names the properties a field or accessor method stands behind.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas) ?, DRagLint.CLI.DoUsagesReadersWriters (DRagLint.CLI.pas) ?, DRagLint.Query.Callers.MemberUsersForName (DRagLint.Query.Callers.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Query.Callers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMemberUsers = record
    Target           : TSymbol;
    FilePath         : string ;
    ReadAccessor     : string ;
    ReadAccessorKind : string ;
    WriteAccessor    : string ;
    WriteAccessorKind: string ;
    BacksProperties  : TArray<string>;
    Readers          : TArray<TMemberUserRow>;
    Writers          : TArray<TMemberUserRow>;
    Calls            : TArray<TMemberUserRow>;
  end;

  /// <summary>The refs carrying a name that the resolver bound to nothing, by
  /// usage direction. They may belong to any symbol of that name.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas) ?, DRagLint.CLI.DoUsagesReadersWriters (DRagLint.CLI.pas), DRagLint.Query.Callers.UnboundUsersForName (DRagLint.Query.Callers.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Query.Callers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUnboundUsers = record
    Reads : TArray<TReference>;
    Writes: TArray<TReference>;
    Other : TArray<TReference>;
  end;

/// <summary>Finds the users of a property, field or routine, split into readers and
/// writers (`usages --rw`, owner Q1 2026-11-04).</summary>
/// <param name="AStore">An open store; nil answers nothing.</param>
/// <param name="AName">A bare or qualified name; one result per declaration.</param>
/// <returns>One TMemberUsers per declaration of AName. A property gathers its own
/// bound accesses, the mentions of a backing field and the direct calls of its
/// accessor methods. A field gathers the same for each property it backs, plus its own
/// mentions. A getter gathers only reads, a setter only writes. One site appears
/// once per direction, under its first route in that order; sites are per line,
/// because a resolved row carries no column.</returns>
/// <remarks>
/// The accessor NAMES come from the property's declaration text, read from
/// the file on disk, because symbols.prop_access keeps only 'ro'/'rw'/'wo' and
/// member_accesses names an accessor only for a property somebody accesses: a property
/// with no users must still lead to its field. A source that cannot be read leaves
/// the accessors empty and the bound sites intact. Directions are the index's:
/// the index stores a var/out argument and Inc/Dec of a field as reads, so this
/// function RECLASSIFIES them when it reports (no extractor change). Covered: a
/// site that is a whole argument of Inc/Dec (a write), of a var parameter (read and
/// write) or of an out parameter (write) of a RESOLVED call (a certain call_edge
/// or a bound call ref). Not covered, and left a reader: an argument of an
/// unresolved or ambiguous call, a part of a longer expression (`Foo(F + 1)`,
/// `Foo(F.X)`, `Foo(@F)`, `Foo(F[I])`), a call whose argument list is more than
/// 12 lines long, and a site the source no longer matches (stale file).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoUsagesReadersWriters (DRagLint.CLI.pas)</para>
/// <para>Calls: AccessorSymbol, AddAccessorRows, AddRows, DeclaredAccessors, Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Query.Callers.MemberUsersForName.GatherMember, DRagLint.Query.Callers.MemberUsersForName.GatherProperty, DRagLint.Query.Callers.ReadLinesOrNothing (+6 more)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Query.Callers.MemberUsersForName.GatherMember"/>
/// <seealso cref="DRagLint.Query.Callers.MemberUsersForName.GatherProperty"/>
/// <seealso cref="DRagLint.Query.Callers.ReadLinesOrNothing"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MemberUsersForName(const AStore: ISymbolStore; const AName: string): TArray<TMemberUsers>;

/// <summary>The refs named by a BARE name that the resolver left unbound.</summary>
/// <param name="AStore">An open store; nil answers nothing.</param>
/// <param name="AName">The name; a qualified name answers nothing, because an
/// unbound site cannot be attributed to one owner.</param>
/// <returns>The unbound refs, split with the `usages` buckets.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoUsagesReadersWriters (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Query.Callers.DropMemberAccessUnderCall, DRagLint.Query.Callers.UsageBucketOf, LastDelimiter, Trim</para>
/// <para>Returns: Default(TUnboundUsers)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
/// <seealso cref="DRagLint.Query.Callers.DropMemberAccessUnderCall"/>
/// <seealso cref="DRagLint.Query.Callers.UsageBucketOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnboundUsersForName(const AStore: ISymbolStore; const AName: string): TUnboundUsers;

/// <summary>Is the identifier that starts at (ALine, ACol) a WHOLE argument of a call?
/// The text half of the var / out / Inc-Dec argument classifier, shared with the calls
/// pass that persists the mode (150-RS2 (2)).</summary>
/// <param name="ALines">The file's source lines (0-based array, 1-based ALine).</param>
/// <param name="ALine">1-based line of the identifier.</param>
/// <param name="ACol">1-based column of the identifier.</param>
/// <param name="ACallee">Receives the called identifier before the opening parenthesis.</param>
/// <param name="ACalleeLine">Receives the callee's 1-based line.</param>
/// <param name="ACalleeCol">Receives the callee's 1-based column.</param>
/// <param name="AArgIndex">Receives the 0-based index of the argument.</param>
/// <returns>False when the site is not a whole argument of a call (or the text does not match).</returns>
/// <remarks>Text only: strings are skipped, comments are not parsed; looks back at most 12 lines.</remarks>
function LocateArgument(const ALines: TArray<string>; ALine, ACol: Integer;
  out ACallee: string; out ACalleeLine, ACalleeCol, AArgIndex: Integer): Boolean;

/// <summary>The mode word of the AIndex-th (0-based) parameter of a routine signature.</summary>
/// <param name="ASig">A signature such as `(A, B: T; var C: U)`.</param>
/// <param name="AIndex">0-based parameter index.</param>
/// <returns>'var' | 'out' | 'const' | 'in' | '' (by value, or past the list).</returns>
function ParamModeAt(const ASig: string; AIndex: Integer): string;

implementation

uses
  System.IOUtils,
  System.Math,
  System.RegularExpressions,
  System.StrUtils;

{ Pull the call site's OWN line out of the indexed context blob.
  FindCallersByNameWithContext formats each line as '%5d: %s', so after Trim the
  wanted line starts with '<StartLine>:'. Reading the file again here instead
  would be a second source of truth and would disagree with the index whenever
  the file has moved on. }
function CodeLineFromContext(const AContextText: string; ALine: Integer): string;
var
  Lines  : TArray<string>;
  L      : string        ;
  Trimmed: string        ;
  Prefix : string        ;
begin
  Result:= '';
  if (AContextText = '') or (ALine <= 0) then Exit;
  Prefix:= IntToStr(ALine) + ':';
  Lines := AContextText.Split([#10]);
  for L in Lines do
  begin
    Trimmed:= Trim(L);
    if Pos(Prefix, Trimmed) = 1 then Exit(Trim(Copy(Trimmed, Length(Prefix) + 1, MaxInt)));
  end;
end;

procedure TResolutionTally.Add(const AKind: string);
begin
  if AKind = RESOLUTION_EXACT then Inc(Exact)
  else if AKind = RESOLUTION_AMBIGUOUS then Inc(Ambiguous)
  else if AKind = RESOLUTION_EXTERNAL then Inc(External)
  else if AKind = RESOLUTION_NAME_ONLY then Inc(NameOnly);
end; // procedure

function TResolutionTally.ToText: string;
  procedure Part(ACount: Integer; const ALabel: string);
  begin
    if ACount = 0 then Exit;
    if Result <> '' then Result:= Result + ', ';
    Result:= Result + Format('%d %s', [ACount, ALabel]);
  end;
begin
  Result:= '';
  Part(Exact    , RESOLUTION_EXACT    );
  Part(Ambiguous, RESOLUTION_AMBIGUOUS);
  Part(External , RESOLUTION_EXTERNAL );
  Part(NameOnly , RESOLUTION_NAME_ONLY);
end; // function

function ResolutionOfConfidence(const AConfidence: string): string;
begin
  if SameText(AConfidence, 'ambiguous') then Result:= RESOLUTION_AMBIGUOUS
  else if SameText(AConfidence, 'callback') then Result:= RESOLUTION_NAME_ONLY
  else Result:= RESOLUTION_EXACT;
end; // function


{ One TResolvedCaller -> one row, the shape both arms of ResolvedCallersForName
  and DispatchCallersOf emit. }
function RowOfCaller(const AStore: ISymbolStore; const ARC: TResolvedCaller; const ATargetQName: string): TQueryCallerRow;
begin
  Result:= Default(TQueryCallerRow);
  Result.CallerQName := ARC.EnclosingQName;
  Result.FilePath    := ARC.Location      ;  { file name only, by contract }
  Result.FullPath    := ARC.FullPath      ;  { ...and the openable one beside it }
  Result.CallSiteLine:= ARC.CallSiteLine  ;
  Result.Confidence  := ARC.Confidence    ;
  Result.Resolution  := ResolutionOfConfidence(ARC.Confidence);
  Result.Mode        := ARC.Mode          ;
  Result.TargetQName := ATargetQName      ;
  { Line is the caller SYMBOL's own start line (routine-granular; the CLI's
    caller_line, omitted when the enclosing symbol is unknown). The site
    is CallSiteLine above. }
  if ARC.EnclosingSymbolId > 0 then
  begin
    Result.Line   := AStore.GetSymbolById(ARC.EnclosingSymbolId).StartLine;
    Result.HasLine:= True;
  end;
end;

function DispatchCallersOf(const AStore: ISymbolStore; AImplId: Int64): TQueryCallerRows;
const
  MAX_BASE_HOPS = 8;
var
  Todo    : TQueue<Int64>               ;
  Seen    : TDictionary<Int64, Boolean> ;
  Cur     : Int64                       ;
  Hops    : Integer                     ;
  ImplName: string                      ;
  Row     : TQueryCallerRow             ;
  First   : Integer                     ;
begin
  SetLength(Result, 0);
  if AStore = nil then Exit;
  ImplName:= AStore.GetSymbolById(AImplId).QualifiedName;
  Todo:= TQueue<Int64>.Create;
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    Todo.Enqueue(AImplId);
    Seen.Add(AImplId, True);
    Hops:= 0;
    while (Todo.Count > 0) and (Hops < MAX_BASE_HOPS) do
    begin
      Inc(Hops);
      Cur:= Todo.Dequeue;
      for var Link in AStore.FindDispatchLinks(Cur, True) do
      begin
        if Seen.ContainsKey(Link.OtherId) then Continue;
        Seen.Add(Link.OtherId, True);
        Todo.Enqueue(Link.OtherId);
        if Link.Kind <> 'implements' then Continue;
        First:= Length(Result);
        for var RC in AStore.FindResolvedCallers(Link.OtherId) do
        begin
          Row:= RowOfCaller(AStore, RC, ImplName);
          Row.Via    := Link.OtherQName;
          Row.ViaKind:= 'interface'    ;
          Row.ViaEdge:= Link.Confidence;
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)]:= Row;
        end;
        if Length(Result) > First then Result[First].ViaCount:= Length(Result) - First;
      end; // for Link
    end; // while
  finally
    Seen.Free;
    Todo.Free;
  end; // try
end; // function

function ResolvedCallersForName(const AStore: ISymbolStore; const AName: string; AWithDispatch: Boolean): TQueryCallerRows;
var
  Targets     : TArray<TSymbol>;
  Row         : TQueryCallerRow;
  NameIsRoutine: Boolean       ;
begin
  SetLength(Result, 0);
  if (AStore = nil) or (Trim(AName) = '') then Exit;

  Targets:= AStore.FindSymbolsByExactName(AName);

  for var T in Targets do
  begin
    var RCallers:= AStore.FindResolvedCallers(T.Id);
    var First: Boolean:= True;
    for var RC in RCallers do
    begin
      Row:= RowOfCaller(AStore, RC, T.QualifiedName);
      Row.FirstOfTarget:= First;
      First:= False;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Row;
    end; // for RC
    { RB-5 P1: then the sites that reach T only through its interface. A target
      with no direct caller still needs its header, so the first via row takes
      FirstOfTarget when nothing direct came first. }
    if AWithDispatch and (T.Kind in [skProcedure, skFunction, skMethod]) then
      for var VR in DispatchCallersOf(AStore, T.Id) do
      begin
        Row:= VR;
        Row.FirstOfTarget:= First;
        First:= False;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)]:= Row;
      end;
  end; // for T

  { Callback reaches -- only when the name denotes a ROUTINE. A 'read' of a
    variable that merely shares a class's or field's name is not a callback. }
  NameIsRoutine:= False;
  for var T in Targets do
    if T.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then
    begin
      NameIsRoutine:= True;
      Break;
    end;
  if not NameIsRoutine then Exit;

  var CallSites: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  { 2026-09-23 (resolver 1.7.0-alpha): a PARENLESS call in an expression is a
    'read' ref that now owns a call_edges row, so it is already listed above as
    a resolved caller. Its line is recorded here so the callback loop does not
    list the same site a second time. Keyed by path, because a resolved row
    carries the path and not the file id. }
  var ResolvedSites: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var R in Result do
      if (R.Mode = '') and (R.CallSiteLine > 0) then
        ResolvedSites.AddOrSetValue(Format('%s:%d', [LowerCase(R.FullPath), R.CallSiteLine]), True);
    var AllRefs:= AStore.FindCallersByName(AName);
    for var PosRef in AllRefs do
      if (PosRef.Kind = 'call') or (PosRef.Kind = 'member-access') then
        CallSites.AddOrSetValue(Format('%d:%d', [PosRef.FileId, PosRef.StartLine]), True);

    for var CbRef in AllRefs do
    begin
      if CbRef.Kind <> 'read' then Continue;
      if CallSites.ContainsKey(Format('%d:%d', [CbRef.FileId, CbRef.StartLine])) then Continue;
      { A read of a same-named local or parameter of the enclosing routine reads
        THAT, not the routine -- the rule DropRefsThatCannotBeCallers applies to
        the name path. `if Run > 0` in a routine with a local Run was listed as a
        callback reach of every routine named Run. }
      if CbRef.EnclosingSymbolId > 0 then
      begin
        var Shadow: TSymbol:= AStore.FindChildSymbolByName(CbRef.EnclosingSymbolId, CbRef.NameText);
        if (Shadow.Id > 0) and (Shadow.Kind in [skLocalVar, skParam, skVarDecl, skConstDecl]) then Continue;
      end;

      var CbWhere: string:= AStore.GetFilePath(CbRef.FileId);
      if ResolvedSites.ContainsKey(Format('%s:%d', [LowerCase(CbWhere), CbRef.StartLine])) then Continue;
      var CbWho  : string:= '';
      var CbDecl : Integer:= 0;
      if CbRef.EnclosingSymbolId > 0 then
      begin
        var CbSym: TSymbol:= AStore.GetSymbolById(CbRef.EnclosingSymbolId);
        CbWho := CbSym.QualifiedName;
        CbDecl:= CbSym.StartLine;
      end;
      if CbWho = '' then CbWho:= '(unit level)';

      Row:= Default(TQueryCallerRow);
      Row.CallerQName := CbWho                    ;
      Row.FilePath    := ExtractFileName(CbWhere) ;
      Row.FullPath    := CbWhere                  ;
      { Same two lines as a resolved row: Line = the caller's declaration,
        CallSiteLine = the site. Before C1 this row put the SITE in Line, which
        is what made `line` mean two things across arms. }
      Row.Line        := CbDecl                   ;
      Row.CallSiteLine:= CbRef.StartLine          ;
      Row.HasLine     := CbDecl > 0               ;
      Row.Confidence := 'callback'               ;
      Row.Resolution := RESOLUTION_NAME_ONLY     ;
      Row.TargetQName:= AName                    ;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Row;
    end; // for CbRef
  finally
    ResolvedSites.Free;
    CallSites.Free;
  end; // try
end; // function

function NameCallersForName(const AStore: ISymbolStore; const AName: string; AContextLines: Integer): TQueryCallerRows;
var
  Refs: TArray<TReference>;
  Row : TQueryCallerRow   ;
  i   : Integer           ;
begin
  SetLength(Result, 0);
  if (AStore = nil) or (Trim(AName) = '') then Exit;
  if AContextLines < 1 then AContextLines:= 1;

  Refs:= AStore.FindCallersByNameWithContext(AName, AContextLines);
  SetLength(Result, Length(Refs));
  for i:= Low(Refs) to High(Refs) do
  begin
    Row:= Default(TQueryCallerRow);
    Row.CallerQName:= '';
    Row.FilePath   := AStore.GetFilePath(Refs[i].FileId);
    Row.FullPath   := Row.FilePath;
    Row.Line       := Refs[i].StartLine;
    Row.CallSiteLine:= Refs[i].StartLine;
    Row.HasLine    := Refs[i].StartLine > 0;
    Row.Confidence := '';
    Row.Resolution := Refs[i].Resolution;
    { D08 / D10 (owner ruling 2026-11-08): a site bound to an event property fires it
      (`event`); one bound to a compiler intrinsic calls no user routine (`built-in`). }
    if Refs[i].ExternalKind = EXTERNAL_KIND_INDIRECT then Row.Mode:= CALLER_MODE_EVENT
    else if Refs[i].ExternalKind = EXTERNAL_KIND_INTRINSIC then Row.Mode:= CALLER_MODE_BUILT_IN;
    Row.TargetQName:= '';
    Row.CodeText   := CodeLineFromContext(Refs[i].ContextText, Refs[i].StartLine);
    Row.EnclosingSymbolId:= Refs[i].EnclosingSymbolId;
    Result[i]:= Row;
  end;
end; // function

{ USAGES-DOUBLE-COUNT (1.42). A QUALIFIED call `FHost.FeedHarvest(x)` stores two refs at ONE position:
  the 'call' and a 'member-access' (see CollapseRefsAtSameSite). `usages` buckets by kind, so the one
  call site was counted twice (calls + reads, or calls twice). Both rows stay in the store -- rename and
  --resolved read them -- so this is a READ-TIME screen: a member-access sharing file+line+col with a
  'call' is dropped from the usages list. Keyed on the column, so two calls on one line both survive.
  A member-access with no call beside it (a field/property read or write) is untouched. Order kept. }
function DropMemberAccessUnderCall(const ARefs: TArray<TReference>): TArray<TReference>;
var
  CallSites: TDictionary<string, Boolean>;
  R        : TReference;
begin
  Result:= nil;
  CallSites:= TDictionary<string, Boolean>.Create;
  try
    for R in ARefs do
      if SameText(R.Kind, 'call') then CallSites.AddOrSetValue(Format('%d:%d:%d', [R.FileId, R.StartLine, R.StartCol]), True);
    for R in ARefs do
      if not (SameText(R.Kind, 'member-access') and CallSites.ContainsKey(Format('%d:%d:%d', [R.FileId, R.StartLine, R.StartCol]))) then
        Result:= Result + [R];
  finally
    CallSites.Free;
  end;
end; // function

function UsageRefsForName(const AStore: ISymbolStore; const AName: string; const ADecls: TArray<TSymbol>): TArray<TReference>;
var
  DotAt: Integer;
  Kept : TList<TReference>;
begin
  DotAt:= LastDelimiter('.', AName);
  if DotAt = 0 then Exit(DropMemberAccessUnderCall(AStore.FindCallersByName(AName)));
  Kept:= TList<TReference>.Create;
  try
    for var R in AStore.FindCallersByName(Copy(AName, DotAt + 1, MaxInt)) do
      for var D in ADecls do
        if (R.SymbolId <> 0) and (R.SymbolId = D.Id) then
        begin
          Kept.Add(R);
          Break;
        end;
    Result:= DropMemberAccessUnderCall(Kept.ToArray);
  finally
    Kept.Free;
  end;
end; // function

/// <summary>Private (1.42: callers go through UsageBucketIn). The `usages` bucket a reference belongs to.</summary>
/// <param name="ARef">A reference from UsageRefsForName.</param>
/// <returns>'reads' | 'writes' | 'calls' | 'types' | 'attributes' | 'events' |
/// 'raises' | 'handles'. A 'member-access' ref goes by its AccessMode
/// (member_accesses.mode): 'read' -> 'reads', 'write' -> 'writes'; one with no
/// mode, and every unknown kind, stays in 'calls' as before. The exception facts
/// (1.36.0): raise / raise-expr / reraise -> 'raises', handle / handle-all ->
/// 'handles', so an exception class's raise and handler sites never inflate its
/// call count. Pinned by run_raise_handle_refs.ps1 (E).</returns>
/// <remarks>Before 2026-10-19 the kind alone decided, so every qualified field
/// access (`AJob.Streaming`) was a CALL and `reads` read 0 for a field read
/// all over the plugin. Pinned by run_usages_field_access.ps1.</remarks>
function UsageBucketOf(const ARef: TReference): string;
begin
  if ARef.Kind      = 'read'          then Result:= 'reads'
  else if ARef.Kind = 'write'         then Result:= 'writes'
  else if ARef.Kind = 'type_use'      then Result:= 'types'
  else if ARef.Kind = 'attribute'     then Result:= 'attributes'
  else if ARef.Kind = 'event-binding' then Result:= 'events'
  else if (ARef.Kind = REF_KIND_RAISE) or (ARef.Kind = REF_KIND_RAISE_EXPR) or (ARef.Kind = REF_KIND_RERAISE) then Result:= 'raises'
  else if (ARef.Kind = REF_KIND_HANDLE) or (ARef.Kind = REF_KIND_HANDLE_ALL) then Result:= 'handles'
  else if (ARef.Kind = 'member-access') and (ARef.AccessMode = 'read' ) then Result:= 'reads'
  else if (ARef.Kind = 'member-access') and (ARef.AccessMode = 'write') then Result:= 'writes'
  else Result:= 'calls'; { call + anything else }
end; // function

function UsageBucketIn(const ARef: TReference; const ADecls: TArray<TSymbol>): string;
const
  TYPE_KINDS = [skClass, skInterface, skRecord, skEnum, skTypeAlias, skClassRef];
begin
  Result:= UsageBucketOf(ARef);
  if (Result <> 'calls') or (ARef.Kind <> REF_KIND_CALL) or (ARef.SymbolId <= 0) then Exit;
  for var D: TSymbol in ADecls do
    if (D.Id = ARef.SymbolId) and (D.Kind in TYPE_KINDS) then Exit('types');
end; // function

{ ITEM 1e -- `find-callers` stops calling a WRITE and a same-named LOCAL a caller.

  FindCallersByName is name-keyed and KIND-BLIND: it returns every ref carrying
  the name, of any kind. That is deliberate and must stay so -- it is SHARED by
  rename/refactor (which must rewrite every occurrence, writes included),
  `usages` (which GROUPS by kind and therefore needs the writes), the dead-code
  rules, the context bundler, and LSP/MCP references. The comment at
  DRagLint.Doc.Facts.pas:2580 already records that excluding rows inside the
  shared query breaks those callers, and screens locally instead. This does the
  same thing for the same reason: a POST-FILTER on the `find-callers` VERB, not
  a change to the store.

  MEASURED on the session-60 fixture, five shapes of the name `Ticks`:

    Consume(Ticks())  call   line 23  a real call        -> KEEP
    N := Ticks;       read   line 30  paren-less call    -> KEEP
    F := Ticks;       read   line 38  procedural VALUE   -> kept, see below
    Ticks := 7;       write  line 46  same-named local   -> DROP
    Consume(Ticks)    read   line 47  same-named local   -> DROP

  Two rules, and neither is a heuristic:

  * A WRITE is never a call. `Ticks := 7` assigns to something; it invokes
    nothing, whatever the name is. The kind alone settles it, with no resolution.
  * A READ whose enclosing routine DECLARES a local or parameter of that name is
    a read of THAT, not of the routine. Delphi scoping says the inner
    declaration wins. Answering "who calls X" with a reference to an unrelated
    local that merely shares the name is a worse failure than missing a caller.

  WHAT IS DELIBERATELY NOT FIXED HERE. `F := Ticks` takes a routine's ADDRESS --
  the shape of every VCL event wiring, `Button.OnClick := HandleClick`. It stays
  listed, because telling it apart from a paren-less call needs the reads bound
  to symbols scope-aware, which is the resolver batch (R1/R2) and an owner
  scheduling decision, not an afternoon. The guard asserts that shape SEPARATELY
  so this note is honest about what it does and does not cover.

  ONLY THE DIRECT ENCLOSING SCOPE is consulted. A nested routine reading an
  outer routine's local is not caught. That direction is safe: it leaves an
  over-report standing rather than removing a genuine call. }
function DropRefsThatCannotBeCallers(const AStore: ISymbolStore;
  const ARefs: TArray<TReference>): TArray<TReference>;
var
  R    : TReference;
  Child: TSymbol   ;
begin
  Result:= nil;
  if AStore = nil then Exit(ARefs);
  for R in ARefs do
  begin
    if SameText(R.Kind, 'write') then Continue;
    if SameText(R.Kind, 'read') and (R.EnclosingSymbolId > 0) then
    begin
      Child:= AStore.FindChildSymbolByName(R.EnclosingSymbolId, R.NameText);
      if (Child.Id > 0) and (Child.Kind in [skLocalVar, skParam, skVarDecl, skConstDecl]) then Continue;
    end;
    Result:= Result + [R];
  end;
end;

{ `find-callers` prints each CALL SITE once.

  THE DEFECT (INBOX-find-callers-duplicate-rows.md). `find-callers --name
  Migrate` printed 75 rows for 38 unique file:line:col on this repo's own index:
  38 refs of kind 'call' and 37 of kind 'member-access'.

  BOTH ROWS ARE CORRECT, WHICH IS THE WHOLE POINT. A QUALIFIED call `Obj.Run`
  emits one 'call' ref and one 'member-access' ref AT THE SAME POSITION; an
  UNQUALIFIED `Run` emits only the 'call'. That is why the doubling is 38/37 and
  not a clean 2x, and it is why the original note's "duplicates in the refs
  TABLE means an extractor defect" reading -- which would have billed a
  DRAGLINT_EXTRACTOR_VERSION bump and a ~5h15m re-parse of every database -- is
  wrong. Nothing is duplicated in the table. The refs are distinct, carry
  different kinds, and BOTH are load-bearing: `usages` groups by kind, rename
  must rewrite every occurrence, and ResolvedCallersForName reads the
  'call'-at-this-line fact to tell a callback reach from an ordinary member
  call.

  So this is a RENDERING fault in ONE verb -- the text form prints no kind, so
  two correct rows are indistinguishable to the reader. Hence a POST-FILTER
  here, for the same reason DropRefsThatCannotBeCallers above is one, and NOT a
  change to the shared store query.

  KEYED ON file+line+COL, NOT file+line. Two calls on one line is legal Pascal
  (`A.Run; B.Run;`) and they are two real sites at two columns; a line-keyed
  collapse would delete one, turning an over-report into an UNDER-report.
  run_find_callers_no_duplicate_sites.ps1 case 5 is the positive control for
  exactly that, and no ref in a 12,725-row sample of this index carries col 0,
  so a position identifies one token.

  The SURVIVING row is the highest-ranked kind at that position, so the one row
  a reader gets is the 'call' rather than the 'member-access'. Order is
  preserved: the winner keeps the slot the first ref at that position took. }
function CollapseRefsAtSameSite(const ARefs: TArray<TReference>): TArray<TReference>;
  function KindRank(const AKind: string): Integer;
  begin
    if SameText(AKind, 'call'         ) then Exit(3); // dl:ok magic-literal@ab99 -- a rank, ordered by these three lines
    if SameText(AKind, 'member-access') then Exit(2);
    if SameText(AKind, 'read'         ) then Exit(1);
    Result:= 0;
  end;
var
  Seen: TDictionary<string, Integer>;
  Key : string                      ;
  Idx : Integer                     ;
  R   : TReference                  ;
begin
  Result:= nil;
  Seen:= TDictionary<string, Integer>.Create;
  try
    for R in ARefs do
    begin
      Key:= Format('%d:%d:%d', [R.FileId, R.StartLine, R.StartCol]);
      if Seen.TryGetValue(Key, Idx) then
      begin
        if KindRank(R.Kind) > KindRank(Result[Idx].Kind) then Result[Idx]:= R;
        Continue;
      end;
      Result:= Result + [R];
      Seen.Add(Key, High(Result));
    end;
  finally
    Seen.Free;
  end; // try
end;

{ The read and write specifiers of a property declaration: the text after the
  type colon, up to the first semicolon, comments and array parameters removed.
  Only the first segment of `read FRec.Value` names a member of the class. }
procedure DeclaredAccessors(const ALines: TArray<string>; const AProp: TSymbol; out ARead, AWrite: string);
const
  COMMENTS = '\{[^}]*\}|\(\*.*?\*\)|//[^\r\n]*';
  ARRAY_PARAMS = '\[[^\]]*\]';
  ACCESSOR = '\b%s\s+([A-Za-z_]\w*)';
var
  Text: string;
begin
  ARead := '';
  AWrite:= '';
  if (AProp.StartLine < 1) or (AProp.EndLine > Length(ALines)) then Exit;
  for var I: Integer:= AProp.StartLine to AProp.EndLine do Text:= Text + ALines[I - 1] + sLineBreak;
  Text:= TRegEx.Replace(Text, COMMENTS, ' ', [roSingleLine]);
  Text:= TRegEx.Replace(Text, ARRAY_PARAMS, ' ');
  var ColonAt: Integer:= Pos(':', Text);
  if ColonAt = 0 then Exit;
  Text:= Copy(Text, ColonAt + 1, MaxInt);
  var SemiAt: Integer:= Pos(';', Text);
  if SemiAt > 0 then SetLength(Text, SemiAt - 1);
  var M: TMatch:= TRegEx.Match(Text, Format(ACCESSOR, ['read']), [roIgnoreCase]);
  if M.Success then ARead:= M.Groups[1].Value;
  M:= TRegEx.Match(Text, Format(ACCESSOR, ['write']), [roIgnoreCase]);
  if M.Success then AWrite:= M.Groups[1].Value;
end;

{ AName as a member of AProp's class; Id 0 and kind 'unresolved' when the class
  does not declare it, '' for no accessor at all. }
function AccessorSymbol(const AStore: ISymbolStore; const AProp: TSymbol; const AName: string; out AKind: string): TSymbol;
begin
  Result:= Default(TSymbol);
  AKind := '';
  if AName = '' then Exit;
  Result:= AStore.FindChildSymbolByName(AProp.ParentId, AName);
  AKind:= if Result.Id <= 0 then 'unresolved' else if Result.Kind in [skFunction, skProcedure, skMethod] then 'method' else 'field';
end;

function ReadLinesOrNothing(const APath: string): TArray<string>;
begin
  Result:= nil;
  try
    if TFile.Exists(APath) then Result:= TFile.ReadAllLines(APath);
  except
    on E: EInOutError do Result:= nil; { the bound sites stand without the accessor names }
    on E: EEncodingError do Result:= nil;
  end;
end;

type
  { How a site that the index stores as a read really uses its target, as far as the
    source text and the resolved call say. }
  TArgUse = (auNone, auIncDec, auVarArg, auOutArg);

const
  ARG_SCAN_LINES = 12;
  ARG_LABELS: array[TArgUse] of string = ('', 'inc-dec', 'var-arg', 'out-arg');

function IsIdentChar(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ The character at a 1-based position; a blank outside the text, so column 0 acts
  as the line break. }
function CharAtPos(const ALines: TArray<string>; ALine, ACol: Integer): Char;
begin
  Result:= ' ';
  if InRange(ALine, 1, Length(ALines)) and InRange(ACol, 1, Length(ALines[ALine - 1])) then
    Result:= ALines[ALine - 1][ACol];
end;

{ One character back; column 0 stands for the line break. False at AFloorLine. }
function StepBack(const ALines: TArray<string>; var ALine, ACol: Integer; AFloorLine: Integer): Boolean;
begin
  Dec(ACol);
  if ACol < 0 then
  begin
    Dec(ALine);
    if (ALine < AFloorLine) or (ALine < 1) then Exit(False);
    ACol:= Length(ALines[ALine - 1]);
  end;
  Result:= True;
end;

{ Past blanks, backward. False at the floor. }
function SkipBlanksBack(const ALines: TArray<string>; var ALine, ACol: Integer; AFloorLine: Integer): Boolean;
begin
  Result:= True;
  while Result and CharInSet(CharAtPos(ALines, ALine, ACol), [' ', #9]) do
    Result:= StepBack(ALines, ALine, ACol, AFloorLine);
end;

{ Past an identifier, backward. False at the floor. }
function SkipIdentBack(const ALines: TArray<string>; var ALine, ACol: Integer; AFloorLine: Integer): Boolean;
begin
  Result:= True;
  while Result and IsIdentChar(CharAtPos(ALines, ALine, ACol)) do
    Result:= StepBack(ALines, ALine, ACol, AFloorLine);
end;

{ Does the next significant character after (ALine, AFromCol) end an argument? }
function ArgumentEndsAt(const ALines: TArray<string>; ALine, AFromCol: Integer): Boolean;
begin
  var NextLine: Integer:= ALine;
  var NextCol : Integer:= AFromCol;
  while (NextLine <= Length(ALines)) and (NextLine - ALine <= ARG_SCAN_LINES) do
  begin
    var Line: string:= ALines[NextLine - 1];
    while (NextCol <= Length(Line)) and CharInSet(Line[NextCol], [' ', #9]) do Inc(NextCol);
    if NextCol <= Length(Line) then Exit(CharInSet(Line[NextCol], [',', ')']));
    Inc(NextLine);
    NextCol:= 1;
  end;
  Result:= False;
end;

{ Backward past blanks and a `Receiver.` chain, stopping on the delimiter. }
function SkipReceiverBack(const ALines: TArray<string>; var ALine, ACol: Integer; AFloorLine: Integer): Boolean;
begin
  Result:= SkipBlanksBack(ALines, ALine, ACol, AFloorLine);
  while Result and (CharAtPos(ALines, ALine, ACol) = '.') do
    Result:= StepBack(ALines, ALine, ACol, AFloorLine) and SkipBlanksBack(ALines, ALine, ACol, AFloorLine)
      and IsIdentChar(CharAtPos(ALines, ALine, ACol)) and SkipIdentBack(ALines, ALine, ACol, AFloorLine)
      and SkipBlanksBack(ALines, ALine, ACol, AFloorLine);
end;

{ From a closing quote at ACol to its opening quote, on the same line. }
function SkipStringBack(const ALines: TArray<string>; ALine: Integer; var ACol: Integer): Boolean;
begin
  var QuoteAt: Integer:= ACol - 1;
  while (QuoteAt >= 1) and (ALines[ALine - 1][QuoteAt] <> '''') do Dec(QuoteAt);
  Result:= QuoteAt >= 1;
  if Result then ACol:= QuoteAt;
end;

{ Backward to the parenthesis that opens the argument list, counting the commas at
  depth 0. False on a `[` or `;` at depth 0, an open string, or at the floor. }
function WalkToOpenParen(const ALines: TArray<string>; var ALine, ACol: Integer; AFloorLine: Integer;
  var AArgIndex: Integer): Boolean;
begin
  var Depth: Integer:= 0;
  while True do
  begin
    var Ch: Char:= CharAtPos(ALines, ALine, ACol);
    case Ch of
      ')', ']': Inc(Depth);
      '(', '[':
        begin
          if Depth = 0 then Exit(Ch = '(');
          Dec(Depth);
        end;
      ',': if Depth = 0 then Inc(AArgIndex);
      ';': if Depth = 0 then Exit(False);
      '''': if not SkipStringBack(ALines, ALine, ACol) then Exit(False);
    end;
    if not StepBack(ALines, ALine, ACol, AFloorLine) then Exit(False);
  end;
end;

{ The identifier before the parenthesis at (ALine, ACol), unless it is a keyword (a
  grouping, not a call). }
function CalleeBefore(const ALines: TArray<string>; ALine, ACol, AFloorLine: Integer;
  out ACallee: string; out ACalleeLine, ACalleeCol: Integer): Boolean;
const
  NOT_CALLS: array[0..21] of string = ('if', 'while', 'until', 'and', 'or', 'not', 'in', 'of', 'then',
    'do', 'else', 'to', 'downto', 'case', 'with', 'xor', 'div', 'mod', 'shl', 'shr', 'is', 'as');
begin
  ACallee:= '';
  ACalleeLine:= 0;
  ACalleeCol:= 0;
  if not (StepBack(ALines, ALine, ACol, AFloorLine) and SkipBlanksBack(ALines, ALine, ACol, AFloorLine)) then Exit(False);
  if not IsIdentChar(CharAtPos(ALines, ALine, ACol)) then Exit(False);
  var LastCol: Integer:= ACol;
  if not SkipIdentBack(ALines, ALine, ACol, AFloorLine) then Exit(False);
  ACalleeLine:= ALine;
  ACalleeCol := ACol + 1;
  ACallee:= Copy(ALines[ALine - 1], ACalleeCol, LastCol - ACol);
  Result:= not MatchText(ACallee, NOT_CALLS);
end;

{ Is the identifier that starts at (ALine, ACol) a WHOLE argument of a call? That is:
  the next significant character is a comma or a closing parenthesis (so it is not
  followed by `.`, `[`, `^` or an operator), the characters before it, past any
  `Receiver.` prefix, are an opening parenthesis or a comma (so no `@`, no operator),
  and the parenthesis found by walking back is preceded by an identifier (so it is
  a call, not a grouping). Returns that identifier, where it starts, and the index of
  the argument. Strings are skipped; comments are not parsed. }
function LocateArgument(const ALines: TArray<string>; ALine, ACol: Integer;
  out ACallee: string; out ACalleeLine, ACalleeCol, AArgIndex: Integer): Boolean;
begin
  Result:= False;
  ACallee:= '';
  ACalleeLine:= 0;
  ACalleeCol:= 0;
  AArgIndex:= 0;
  if not InRange(ALine, 1, Length(ALines)) then Exit;
  var Text: string:= ALines[ALine - 1];
  if (not InRange(ACol, 1, Length(Text))) or (not IsIdentChar(Text[ACol])) then Exit;
  var EndCol: Integer:= ACol;
  while (EndCol <= Length(Text)) and IsIdentChar(Text[EndCol]) do Inc(EndCol);
  if not ArgumentEndsAt(ALines, ALine, EndCol) then Exit;
  var LowLine: Integer:= Max(ALine - ARG_SCAN_LINES, 1);
  var L: Integer:= ALine;
  var C: Integer:= ACol;
  if not (StepBack(ALines, L, C, LowLine) and SkipReceiverBack(ALines, L, C, LowLine)) then Exit;
  Result:= CharInSet(CharAtPos(ALines, L, C), ['(', ','])
    and WalkToOpenParen(ALines, L, C, LowLine, AArgIndex)
    and CalleeBefore(ALines, L, C, LowLine, ACallee, ACalleeLine, ACalleeCol);
end;

{ The mode word ('var' | 'out' | 'const' | '') of the AIndex-th parameter (0-based) in a
  routine signature `(A, B: T; var C: U)`. '' when the index is past the list. }
function ParamModeAt(const ASig: string; AIndex: Integer): string;
var
  Depth, GStart, Idx, Count, ColonAt: Integer;
  Group, Names, Mode: string;
begin
  Result:= '';
  var Open: Integer:= Pos('(', ASig);
  if Open = 0 then Exit;
  Depth:= 0;
  GStart:= Open + 1;
  Idx:= 0;
  for var I: Integer:= Open to Length(ASig) do
  begin
    var Ch: Char:= ASig[I];
    if CharInSet(Ch, ['(', '[', '<']) then Inc(Depth)
    else if CharInSet(Ch, [')', ']', '>']) then Dec(Depth);
    if not (((Ch = ';') and (Depth = 1)) or ((Ch = ')') and (Depth = 0))) then Continue;
    Group:= Trim(Copy(ASig, GStart, I - GStart));
    GStart:= I + 1;
    if Group <> '' then
    begin
      while Group.StartsWith('[') and Group.Contains(']') do Group:= Trim(Copy(Group, Pos(']', Group) + 1, MaxInt));
      Mode:= '';
      for var Word: string in ['var', 'out', 'const', 'in'] do
        if Group.StartsWith(Word + ' ', True) then
        begin
          Mode:= LowerCase(Word);
          Group:= Trim(Copy(Group, Length(Word) + 1, MaxInt));
          Break;
        end;
      ColonAt:= Pos(':', Group);
      Names:= if ColonAt > 0 then Copy(Group, 1, ColonAt - 1) else Group;
      Count:= 1;
      for var K: Integer:= 1 to Length(Names) do
        if Names[K] = ',' then Inc(Count);
      if AIndex < Idx + Count then Exit(Mode);
      Idx:= Idx + Count;
    end;
    if Depth = 0 then Break;
  end;
end;

type
  /// <summary>Decides, for a site the index stores as a read, whether the source makes
  /// it an Inc/Dec argument or an argument of a var / out parameter of a resolved call.</summary>
  /// <remarks>Caches source lines, name lookups and verdicts for one query. Not
  /// thread-safe; owned and freed by the caller.</remarks>
  TArgClassifier = class
  strict private
    FStore: ISymbolStore;
    FLines: TDictionary<string, TArray<string>>;
    FNamed: TDictionary<string, TArray<TReference>>;
    FPaths: TDictionary<Int64, string>;
    FEdges: TDictionary<Int64, TArray<TCallEdge>>;
    FUse  : TDictionary<string, TArgUse>;
    function LinesOf(const APath: string): TArray<string>;
    function RefsNamed(const AName: string): TArray<TReference>;
    function PathOf(AFileId: Int64): string;
    function EdgesOf(AEnclosingId: Int64): TArray<TCallEdge>;
    function TargetOf(const ARC: TResolvedCaller; const ACallee: string; ALine, ACol: Integer): TSymbol;
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    /// <summary>The argument use of one resolved site.</summary>
    /// <param name="ARC">A site with FullPath, CallSiteLine and CallSiteCol.</param>
    /// <returns>auNone when the site is no whole argument, the call is unresolved or
    /// ambiguous, the parameter is by value or const, or the source does not match.</returns>
    function Classify(const ARC: TResolvedCaller): TArgUse;
  end;

constructor TArgClassifier.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore:= AStore;
  FLines:= TDictionary<string, TArray<string>>.Create;
  FNamed:= TDictionary<string, TArray<TReference>>.Create;
  FPaths:= TDictionary<Int64, string>.Create;
  FEdges:= TDictionary<Int64, TArray<TCallEdge>>.Create;
  FUse  := TDictionary<string, TArgUse>.Create;
end;

destructor TArgClassifier.Destroy;
begin
  FUse.Free;
  FEdges.Free;
  FPaths.Free;
  FNamed.Free;
  FLines.Free;
  inherited Destroy;
end;

function TArgClassifier.LinesOf(const APath: string): TArray<string>;
begin
  var Key: string:= LowerCase(APath);
  if not FLines.TryGetValue(Key, Result) then
  begin
    Result:= ReadLinesOrNothing(APath);
    FLines.Add(Key, Result);
  end;
end;

function TArgClassifier.RefsNamed(const AName: string): TArray<TReference>;
begin
  var Key: string:= LowerCase(AName);
  if not FNamed.TryGetValue(Key, Result) then
  begin
    Result:= FStore.FindCallersByName(AName);
    FNamed.Add(Key, Result);
  end;
end;

function TArgClassifier.PathOf(AFileId: Int64): string;
begin
  if not FPaths.TryGetValue(AFileId, Result) then
  begin
    Result:= FStore.GetFilePath(AFileId);
    FPaths.Add(AFileId, Result);
  end;
end;

function TArgClassifier.EdgesOf(AEnclosingId: Int64): TArray<TCallEdge>;
begin
  if not FEdges.TryGetValue(AEnclosingId, Result) then
  begin
    Result:= FStore.GetCallEdgesFromSymbol(AEnclosingId);
    FEdges.Add(AEnclosingId, Result);
  end;
end;

function TArgClassifier.TargetOf(const ARC: TResolvedCaller; const ACallee: string; ALine, ACol: Integer): TSymbol;
begin
  Result:= Default(TSymbol);
  for var R: TReference in RefsNamed(ACallee) do
  begin
    if (R.StartLine <> ALine) or (R.StartCol <> ACol) then Continue;
    if not SameText(PathOf(R.FileId), ARC.FullPath) then Continue;
    if R.SymbolId > 0 then Exit(FStore.GetSymbolById(R.SymbolId));
    if ARC.EnclosingSymbolId > 0 then
      for var E: TCallEdge in EdgesOf(ARC.EnclosingSymbolId) do
        if (E.RefId = R.Id) and (E.TargetSymbolId > 0) and SameText(E.Confidence, 'certain') then
          Exit(FStore.GetSymbolById(E.TargetSymbolId));
  end;
end;

function TArgClassifier.Classify(const ARC: TResolvedCaller): TArgUse;
var
  Callee: string;
  CL, CC, Idx: Integer;
begin
  Result:= auNone;
  if (ARC.CallSiteLine < 1) or (ARC.CallSiteCol < 1) then Exit;
  var Key: string:= Format('%s:%d:%d', [LowerCase(ARC.FullPath), ARC.CallSiteLine, ARC.CallSiteCol]);
  if FUse.TryGetValue(Key, Result) then Exit;
  Result:= auNone;
  { 150-RS2 (2): the calls pass persisted the var / out use of a member_accesses row; read it
    first. A row without one (an identity-only local / parameter, a DB resolved before) falls
    through to the read-time classification below, so the answer is the same either way. }
  if SameText(ARC.ArgUse, ARG_LABELS[auVarArg]) then Result:= auVarArg
  else if SameText(ARC.ArgUse, ARG_LABELS[auOutArg]) then Result:= auOutArg;
  if Result <> auNone then
  begin
    FUse.Add(Key, Result);
    Exit;
  end;
  var Lines: TArray<string>:= LinesOf(ARC.FullPath);
  if (Length(Lines) > 0) and LocateArgument(Lines, ARC.CallSiteLine, ARC.CallSiteCol, Callee, CL, CC, Idx) then
  begin
    if (Idx = 0) and (SameText(Callee, 'Inc') or SameText(Callee, 'Dec')) then Result:= auIncDec
    else
    begin
      var Target: TSymbol:= TargetOf(ARC, Callee, CL, CC);
      if Target.Id > 0 then
      begin
        var Mode: string:= ParamModeAt(Target.Signature, Idx);
        if Mode = 'var' then Result:= auVarArg
        else if Mode = 'out' then Result:= auOutArg;
      end;
    end;
  end;
  FUse.Add(Key, Result);
end;

function MemberUsersForName(const AStore: ISymbolStore; const AName: string): TArray<TMemberUsers>;
const
  MODE_READ  = 'read' ;
  MODE_WRITE = 'write';
var
  Seen: TDictionary<string, Boolean>;
  Args: TArgClassifier;
  Cur : TMemberUsers;

  { The resolved callers of ASymbolId into Cur. AForce is the direction of a row
    that has none (a call of an accessor method); AOnly keeps one direction. }
  procedure AddRows(ASymbolId: Int64; const AVia, AViaName, AForce, AOnly: string);
  begin
    for var RC: TResolvedCaller in AStore.FindResolvedCallers(ASymbolId) do
    begin
      var Mode: string:= if RC.Mode <> '' then RC.Mode else AForce;
      if (AOnly <> '') and (Mode <> AOnly) then Continue;
      { A stored read that is really an Inc/Dec or var/out argument: see MemberUsersForName. }
      var Use: TArgUse:= auNone;
      if (AOnly = '') and (RC.Mode = MODE_READ) then Use:= Args.Classify(RC);
      var Modes: TArray<string>;
      case Use of
        auIncDec, auOutArg: Modes:= [MODE_WRITE];
        auVarArg          : Modes:= [MODE_READ, MODE_WRITE];
      else Modes:= [Mode];
      end;
      for var M: string in Modes do
      begin
        var Key: string:= Format('%s:%d:%s', [LowerCase(RC.FullPath), RC.CallSiteLine, M]);
        if Seen.ContainsKey(Key) then Continue;
        Seen.Add(Key, True);
        var Row: TMemberUserRow:= Default(TMemberUserRow);
        Row.CallerQName:= RC.EnclosingQName;
        Row.FullPath   := RC.FullPath;
        Row.Line       := RC.CallSiteLine;
        Row.Via        := AVia;
        Row.ViaName    := AViaName;
        Row.Confidence := RC.Confidence;
        Row.Resolution := ResolutionOfConfidence(RC.Confidence);
        Row.Arg        := ARG_LABELS[Use];
        if M = MODE_READ then Cur.Readers:= Cur.Readers + [Row]
        else if M = MODE_WRITE then Cur.Writers:= Cur.Writers + [Row]
        else Cur.Calls:= Cur.Calls + [Row];
      end;
    end;
  end;

  procedure AddAccessorRows(const AAccessor: TSymbol; const AKind, AMethodVia, AForce: string);
  begin
    if AKind = 'field' then AddRows(AAccessor.Id, 'field', AAccessor.QualifiedName, '', '')
    else if AKind = 'method' then AddRows(AAccessor.Id, AMethodVia, AAccessor.QualifiedName, AForce, '');
  end;

  procedure GatherProperty(const AProp: TSymbol; const ALines: TArray<string>);
  var
    RName, WName, RKind, WKind: string;
  begin
    DeclaredAccessors(ALines, AProp, RName, WName);
    var RSym: TSymbol:= AccessorSymbol(AStore, AProp, RName, RKind);
    var WSym: TSymbol:= AccessorSymbol(AStore, AProp, WName, WKind);
    Cur.ReadAccessor     := RName;
    Cur.ReadAccessorKind := RKind;
    Cur.WriteAccessor    := WName;
    Cur.WriteAccessorKind:= WKind;
    AddRows(AProp.Id, 'property', AProp.QualifiedName, '', '');
    AddAccessorRows(RSym, RKind, 'getter', MODE_READ);
    AddAccessorRows(WSym, WKind, 'setter', MODE_WRITE);
  end;

  { A field or method: the properties of its class it stands behind, then its own sites. }
  procedure GatherMember(const AMember: TSymbol; const ALines: TArray<string>);
  var
    RName, WName: string;
    Role: string;
  begin
    Role:= '';
    if AMember.ParentId > 0 then
      for var P: TSymbol in AStore.FindSymbolsByFile(Cur.FilePath) do
      begin
        if (P.Kind <> skProperty) or (P.ParentId <> AMember.ParentId) then Continue;
        DeclaredAccessors(ALines, P, RName, WName);
        var IsReader: Boolean:= SameText(RName, AMember.Name);
        var IsWriter: Boolean:= SameText(WName, AMember.Name);
        if not (IsReader or IsWriter) then Continue;
        Cur.BacksProperties:= Cur.BacksProperties + [P.QualifiedName];
        if AMember.Kind = skField then AddRows(P.Id, 'property', P.QualifiedName, '', '')
        else if IsReader then
        begin
          Role:= MODE_READ;
          AddRows(P.Id, 'property', P.QualifiedName, '', MODE_READ);
        end
        else
        begin
          Role:= MODE_WRITE;
          AddRows(P.Id, 'property', P.QualifiedName, '', MODE_WRITE);
        end;
      end;
    if Length(Cur.BacksProperties) = 0 then AddRows(AMember.Id, 'direct', AMember.QualifiedName, '', '')
    else if AMember.Kind = skField then AddRows(AMember.Id, 'field', AMember.QualifiedName, '', '')
    else if Role = MODE_READ then AddRows(AMember.Id, 'getter', AMember.QualifiedName, MODE_READ, '')
    else AddRows(AMember.Id, 'setter', AMember.QualifiedName, MODE_WRITE, '');
  end;

begin
  Result:= nil;
  if (AStore = nil) or (Trim(AName) = '') then Exit;
  Seen:= TDictionary<string, Boolean>.Create;
  Args:= TArgClassifier.Create(AStore);
  try
    for var T: TSymbol in AStore.FindSymbolsByExactName(AName) do
    begin
      Seen.Clear;
      Cur:= Default(TMemberUsers);
      Cur.Target  := T;
      Cur.FilePath:= AStore.GetFilePath(T.FileId);
      var Lines: TArray<string>:= ReadLinesOrNothing(Cur.FilePath);
      if T.Kind = skProperty then GatherProperty(T, Lines)
      else GatherMember(T, Lines);
      Result:= Result + [Cur];
    end;
  finally
    Args.Free;
    Seen.Free;
  end; // try
end; // function

function UnboundUsersForName(const AStore: ISymbolStore; const AName: string): TUnboundUsers;
begin
  Result:= Default(TUnboundUsers);
  if (AStore = nil) or (Trim(AName) = '') or (LastDelimiter('.', AName) > 0) then Exit;
  for var R: TReference in DropMemberAccessUnderCall(AStore.FindCallersByName(AName)) do
  begin
    if R.SymbolId > 0 then Continue;
    var Bucket: string:= UsageBucketOf(R);
    if Bucket = 'reads' then Result.Reads:= Result.Reads + [R]
    else if Bucket = 'writes' then Result.Writes:= Result.Writes + [R]
    else if Bucket = 'calls' then Result.Other:= Result.Other + [R];
  end;
end; // function

end.
