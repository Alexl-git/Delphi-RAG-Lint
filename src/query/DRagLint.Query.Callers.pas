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
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas), DRagLint.Charts.MemberAccess.CollectMemberAccess (DRagLint.Charts.MemberAccess.pas), DRagLint.Charts.MemberAccess.GroupRoutines (DRagLint.Charts.MemberAccess.pas), DRagLint.Charts.MemberAccess.HitsOf (DRagLint.Charts.MemberAccess.pas), DRagLint.Query.Callers.ResolvedCallersForName (DRagLint.Query.Callers.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Charts.MemberAccess, DRagLint.Query.Callers</para>
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
  /// <para>Used by: declaration (DRagLint.Query.Callers.pas), DRagLint.Charts.MemberAccess.HitsOf (DRagLint.Charts.MemberAccess.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryCallerRows = TArray<TQueryCallerRow>;

type
  /// <summary>Counts of caller/callee rows per derived resolution kind, for the text
  /// totals `12 callers (9 exact, 1 ambiguous, 2 name-only)` and the context JSON
  /// `caller_resolution` object.</summary>
  TResolutionTally = record
    Exact    : Integer;
    Ambiguous: Integer;
    External : Integer;
    NameOnly : Integer;
    /// <summary>Counts one row of kind <paramref name="AKind"/> (a RESOLUTION_* value; an
    /// unknown or empty kind is not counted).</summary>
    procedure Add(const AKind: string);
    /// <summary>`9 exact, 1 ambiguous, 2 name-only`: only the kinds seen, in the order
    /// exact, ambiguous, external, name-only; '' when nothing was counted.</summary>
    function ToText: string;
  end;

/// <summary>Maps a call_edges confidence (or 'callback') to the derived resolution kind.</summary>
/// <param name="AConfidence">'certain' | 'ambiguous' | 'callback' | anything else.</param>
/// <returns>'ambiguous' for 'ambiguous'; 'name-only' for 'callback' (a by-name reach, no
/// edge); 'exact' for every other stored edge ('certain').</returns>
function ResolutionOfConfidence(const AConfidence: string): string;

/// <summary>Precise callers of every symbol matching <paramref name="AName"/>
/// in one store, keyed by resolved call edges rather than by name.</summary>
/// <param name="AStore">An open store; must not be nil.</param>
/// <param name="AName">Bare or qualified callee name, matched exactly.</param>
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
/// <para>Called from: DRagLint.Charts.MemberAccess.CollectMemberAccess (DRagLint.Charts.MemberAccess.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, ExtractFileName, Format, LowerCase, Trim</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 103 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
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
/// <remarks>Only 'implements' edges are reported: a virtual override is not
/// part of the owner ruling and would churn every class-hierarchy answer. A call
/// whose receiver is class-typed binds to the class method (a direct caller) and
/// never appears here. Rows keep the call edge's own confidence; the dispatch
/// edge's confidence is ViaEdge, and an 'ambiguous' edge is marked by the
/// renderers.</remarks>
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
/// <remarks>A qualified query drops UNBOUND refs: an unbound `X.Streaming`
/// cannot be attributed to TJob rather than to any other Streaming.</remarks>
function UsageRefsForName(const AStore: ISymbolStore; const AName: string; const ADecls: TArray<TSymbol>): TArray<TReference>;

/// <summary>The `usages` bucket a reference belongs to.</summary>
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

/// <summary>A name match's refs, minus those that cannot be a call of the name:
/// writes, and reads of a same-named local or parameter of the enclosing routine.</summary>
/// <param name="AStore">The store the refs came from; nil returns ARefs unchanged.</param>
/// <param name="ARefs">Name-matched refs (FindCallersByName and friends).</param>
/// <returns>The refs that can still be calls, in order. Shared by `query
/// find-callers` and the MCP find_callers tool.</returns>
function DropRefsThatCannotBeCallers(const AStore: ISymbolStore;
  const ARefs: TArray<TReference>): TArray<TReference>;

/// <summary>One ref per call SITE (file + line + column), keeping the
/// highest-ranked kind there ('call' over 'member-access' over 'read').</summary>
/// <param name="ARefs">Refs in display order.</param>
/// <returns>The refs with same-site duplicates collapsed, order preserved.</returns>
function CollapseRefsAtSameSite(const ARefs: TArray<TReference>): TArray<TReference>;

implementation

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
    Row.TargetQName:= '';
    Row.CodeText   := CodeLineFromContext(Refs[i].ContextText, Refs[i].StartLine);
    Row.EnclosingSymbolId:= Refs[i].EnclosingSymbolId;
    Result[i]:= Row;
  end;
end; // function

function UsageRefsForName(const AStore: ISymbolStore; const AName: string; const ADecls: TArray<TSymbol>): TArray<TReference>;
var
  DotAt: Integer;
  Kept : TList<TReference>;
begin
  DotAt:= LastDelimiter('.', AName);
  if DotAt = 0 then Exit(AStore.FindCallersByName(AName));
  Kept:= TList<TReference>.Create;
  try
    for var R in AStore.FindCallersByName(Copy(AName, DotAt + 1, MaxInt)) do
      for var D in ADecls do
        if (R.SymbolId <> 0) and (R.SymbolId = D.Id) then
        begin
          Kept.Add(R);
          Break;
        end;
    Result:= Kept.ToArray;
  finally
    Kept.Free;
  end;
end; // function

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
    if SameText(AKind, 'call'         ) then Exit(3);
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

end.
