unit DRagLint.Context.Bundler;

// v0.18: TContextBundler -- composes surface/slice/impact/callers/docs into
// a TContextBundle for AI-ready symbol context. Rendering helpers produce
// Markdown, JSON, or raw Pascal text from the bundle.

interface

uses
  System.SysUtils
  , System.Classes
  , System.DateUtils
  , System.StrUtils
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Index   .LibraryOracle { TLibraryOracle -- the opt-in query-time Library calls count (RSV-R2) }
  , DRagLint.Query   .Callers
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.Context.Bundler.CapTypeBodies (DRagLint.Context.Bundler.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.MCP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TContextBundler = class
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AVerb"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACallerContext"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AMaxCallers"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AIncludeDocs"><!-- drag-lint:auto type -->Boolean</param>
      /// <param name="AIncludeSurface"><!-- drag-lint:auto type -->Boolean</param>
      /// <param name="AIncludeImpl"><!-- drag-lint:auto type -->Boolean</param>
      /// <param name="AExcludeDfmFields">Lean surface (default True; False = <c>--full-surface</c>):
      /// a class owner's DFM component fields are dropped, and for a MEMBER target
      /// (not a class/record/interface) so are the surface's comment-only lines.</param>
      /// <param name="ATaskText">The caller's raw task phrase, if any. Matched
      /// against the aliases of every <c>dl:wiki</c> topic in this index; up to
      /// two matches ride along in WikiTopics. Empty (the default) skips the
      /// lookup entirely, so every existing caller is unaffected. Honoured only
      /// when AIncludeDocs is set -- <c>--no-docs</c> means no prose, and a
      /// concept body is prose.</param>
      /// <param name="AOracle">Optional library oracle (RSV-R2). When set, a call in the target's
      /// body that carries NO stored external_target but whose receiver type text the oracle
      /// binds to exactly one library member counts toward "Library calls" as well
      /// (LibraryCallVia = 'oracle' if at least one such hit was added, else 'stored').
      /// nil (the default) keeps the stored-only count and never touches a library. The
      /// caller owns the oracle and the stores behind it.</param>
      /// <param name="ABodyTokenCap">CTX-TYPECAP: for a TYPE target (class, record,
      /// interface) the impl-method bodies are kept up to this many estimated tokens;
      /// the rest land in OmittedBodies as header + line range, and the class-decl
      /// chunk is dropped when a class surface is present. Engages only when the
      /// bodies exceed the cap; a member target is never cut; 0 = uncapped. Words
      /// after the type name in AQName (<c>TFoo Bar</c>) name FOCUS methods whose
      /// bodies are always kept. Spec:
      /// docs\superpowers\specs\2026-11-03-ctx-typecap-design.md.</param>
      /// <returns><!-- drag-lint:auto type -->TContextBundle</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Copy, Default, DRagLint.Context.Bundler.CallersOfTarget, DRagLint.Context.Bundler.CapTypeBodies, DRagLint.Context.Bundler.ChunkHeaderLine, DRagLint.Context.Bundler.CollectLibraryCalls, DRagLint.Context.Bundler.DistinctCallSites, DRagLint.Context.Bundler.DropCappedMemberDocs, DRagLint.Context.Bundler.HeaderLeafName, DRagLint.Context.Bundler.OwnerIsClassKind (+19 more)</para>
      /// <para>Complexity: 45 (cyclomatic, outer body), 360 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Context.Bundler.CallersOfTarget"/>
      /// <seealso cref="DRagLint.Context.Bundler.CapTypeBodies"/>
      /// <seealso cref="DRagLint.Context.Bundler.ChunkHeaderLine"/>
      /// <seealso cref="DRagLint.Context.Bundler.CollectLibraryCalls"/>
      /// <seealso cref="DRagLint.Context.Bundler.DistinctCallSites"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Build(
        const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
        AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True; const ATaskText: string = ''; AOracle: TLibraryOracle = nil;
        ABodyTokenCap: Integer = CONTEXT_BODY_TOKEN_CAP): TContextBundle;
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: Round(Length(AText) / 3.7).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Context.Bundler.CapTypeBodies (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderJson"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderMarkdown"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderRaw"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function EstimateTokens(const AText: string)          : Integer;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Context.Bundler.OmittedMethodCount, DRagLint.Core.Model.CapOmittedNote, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Format, FormatDateTime, IfThen</para>
      /// <para>Complexity: 32 (cyclomatic, outer body), 175 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Context.Bundler.OmittedMethodCount"/>
      /// <seealso cref="DRagLint.Core.Model.CapOmittedNote"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderMarkdown(const ABundle: TContextBundle): string ;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Copy, Default, DRagLint.Context.Bundler.OmittedMethodCount, DRagLint.Core.Model.JsonEscape, DRagLint.Query.Callers.TResolutionTally.Add, Format, IfThen</para>
      /// <para>Pure</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 133 lines (full implementation)</para>
      /// <seealso cref="DRagLint.Context.Bundler.OmittedMethodCount"/>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.Query.Callers.TResolutionTally.Add"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderJson(const ABundle: TContextBundle)    : string ;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas)</para>
      /// <para>Pure</para>
      /// <para>Calls: Format</para>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderJson"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderMarkdown"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderRaw(const ABundle: TContextBundle)     : string ;
  end;

implementation

uses
  DRagLint.Doc.Regions
  , DRagLint.Doc.Wiki   { TWikiParser -- alias matching for the ## Wiki section }
  , System.JSON         { RenderJson's content keys -- escaped by the JSON writer }
  , System.Generics.Defaults { TComparer -- CapTypeBodies' ranking }
  ;

const
  { How many external targets the "Library calls" line names. }
  LIBRARY_CALLS_TOP = 3;
  { CTX-TYPECAP: estimated tokens of one omitted-body line beyond its header
    text (the backticks, the L<a>-<b> range and the token note). }
  OMITTED_LINE_TOKENS = 6;

class function TContextBundler.EstimateTokens(const AText: string): Integer;
begin
  Result:= Round(Length(AText) / 3.7);
end;

// True when a trimmed class-body line is a simple field declaration of the form
//   Ident : TSomeType;       (a published component field -- DFM-streamed noise)
// i.e. has a colon, ends with ';', no '(' (so not a method/event), and the
// leading token is a plain identifier (not a keyword). Used to strip the
// hundreds of auto-generated component fields a form class carries.
function IsComponentFieldLine(const ATrim: string): Boolean;
var
  ColonPos: Integer;
  I       : Integer;
  Head    : string ;
  Low     : string ;
begin
  Result:= False;
  if ATrim = '' then Exit;
  if ATrim[Length(ATrim)] <> ';' then Exit;
  ColonPos:= Pos(':', ATrim);
  if ColonPos < 2 then Exit;
  if Pos('(', ATrim) > 0 then Exit; // method / event handler
  Head:= Trim(Copy(ATrim, 1, ColonPos - 1));
  if Head = '' then Exit;
  // leading token must be a plain identifier (a field name), not a keyword
  for I:= 1 to Length(Head) do
    if not (CharInSet(Head[I], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then Exit;
  Low:= LowerCase(Head);
  if (Low = 'procedure') or (Low = 'function') or (Low = 'property') or (Low = 'constructor') or (Low = 'destructor') or (Low = 'class') or
  (Low = 'type') or (Low = 'const') or (Low = 'var') or (Low = 'case') then Exit;
  Result:= True;
end; // function

// Drops published component-field declarations from a class surface. The class
// body's default (pre-specifier) and explicit `published` sections are where
// the IDE streams DFM component fields; private/protected/public members and
// all methods/properties/events are kept.
function StripDfmFields( const ASurface: TArray<TSurfaceLine>): TArray<TSurfaceLine>;
var
  Acc        : TList<TSurfaceLine>;
  L          : TSurfaceLine       ;
  T          : string             ;
  Low        : string             ;
  InPublished: Boolean            ;
begin
  Acc:= TList<TSurfaceLine>.Create;
  try
    InPublished:= True; // form classes are $M+: top section is published
    for L in ASurface do
    begin
      T:= Trim(L.Text);
      Low:= LowerCase(T);
      if (Low = 'private') or (Low = 'strict private') or (Low = 'protected') or (Low = 'strict protected') or (Low = 'public') or (Low = 'strict public') then InPublished:= False
      else if Low = 'published' then InPublished:= True
      else if InPublished and IsComponentFieldLine(T) then Continue; // drop the DFM component field
      Acc.Add(L);
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

// GAP-CONTEXT (1.40): drops comment-only lines (first non-blank text `//`,
// which covers `///` doc blocks) from a class surface. Used for a MEMBER
// target in lean mode: the surface then carries the owner's SHAPE (its
// declarations), while the target's own doc is in ## Doc. Measured on
// `modify TSQLiteSymbolStore.ResolveDispatch`: 2256 of the 2457 surface lines
// were other members' doc comments (47.5k-token bundle). Multi-line brace
// comments and trailing comments on a declaration line are kept.
function StripCommentOnlyLines(const ASurface: TArray<TSurfaceLine>): TArray<TSurfaceLine>;
var
  Acc: TList<TSurfaceLine>;
  L  : TSurfaceLine       ;
begin
  Acc:= TList<TSurfaceLine>.Create;
  try
    for L in ASurface do
      if not TrimLeft(L.Text).StartsWith('//') then Acc.Add(L);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

// The ONE symbol a name that is not a whole qualified name identifies; empty
// when none or several do (ambiguity declines on purpose -- a confidently-wrong
// bundle is worse than an empty one).
//   * no dot     -> the bare-name rule: exactly one symbol with that exact name.
//   * with a dot -> the suffix rule: exactly one symbol whose qualified_name
//                   ends with `.<AQName>`. Segment-aligned (the character before
//                   the suffix must be a '.', so `orker.UniqueMethod` never
//                   matches `uA.TWorker.UniqueMethod`), case-insensitive, with
//                   every segment's `<...>` list stripped first because symbols
//                   are stored under BARE names since schema v23. Candidates
//                   come from the LAST segment's exact-name lookup -- the same
//                   index the bare rule queries.
// See the call site in Build for the why.
function ResolveUniqueName( const AStore: ISymbolStore; const AQName: string): TArray<TSymbol>;
var
  Suffix: string         ;
  Tail  : string         ;
  ByName: TArray<TSymbol>;
  Hit   : Integer        ;
  Hits  : Integer        ;
  I     : Integer        ;
begin
  SetLength(Result, 0);
  if Pos('.', AQName) = 0 then
  begin
    ByName:= AStore.FindSymbolsByExactName(AQName);
    if Length(ByName) = 1 then Result:= ByName;
    Exit;
  end;
  Suffix:= StripGenericSegments(AQName);
  Tail  := Copy(Suffix, LastDelimiter('.', Suffix) + 1, MaxInt);
  ByName:= AStore.FindSymbolsByExactName(Tail);
  Hit   := -1;
  Hits  := 0;
  for I:= 0 to High(ByName) do
    if EndsText('.' + Suffix, ByName[I].QualifiedName) then
    begin
      Inc(Hits);
      Hit:= I;
    end;
  if Hits = 1 then Result:= [ByName[Hit]];
end; // function

// True when the store knows AOwnerQName as a CLASS -- the only kind whose
// surface may carry a DFM component dump, and therefore the only kind the lean
// filter (StripDfmFields) may run on. An owner the store cannot find has no
// surface either, so True there changes nothing and keeps the pre-2026-09-17
// behaviour for a class; an empty name has no owner at all.
function OwnerIsClassKind( const AStore: ISymbolStore; const AOwnerQName: string): Boolean;
var
  Owners: TArray<TSymbol>;
begin
  Result:= True;
  if AOwnerQName = '' then Exit;
  Owners:= AStore.FindSymbolsByQualifiedName(AOwnerQName);
  if Length(Owners) > 0 then Result:= Owners[0].Kind = skClass;
end; // function

// ARefs with every repeat of a (file, line, col) position dropped, first
// occurrence kept, order otherwise unchanged. The caller lookup is KIND-BLIND
// by design, and one call site can hold several refs: a class-method call
// `TLintConfigWriter.SaveToFile(CP, Cfg)` indexes a bound `call` AND an unbound
// `member-access` on the same span. Listed as they came, that site printed
// twice under `## Callers (2)` while `find-callers` said one -- a doubled count
// is the mirror of the "zero callers is a defect" trap, and it spends the
// caller cap on repeats. Must run BEFORE the cap. Guarded by
// tests\autotest\run_context_callers_dedup_and_version.ps1.
function DistinctCallSites( const ARefs: TArray<TReference>): TArray<TReference>;
var
  Seen: TDictionary<string, Boolean>;
  Key : string;
  N   : Integer;
  I   : Integer;
begin
  SetLength(Result, Length(ARefs));
  N:= 0;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to High(ARefs) do
    begin
      Key:= Format('%d:%d:%d', [ARefs[I].FileId, ARefs[I].StartLine, ARefs[I].StartCol]);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Result[N]:= ARefs[I];
      Inc(N);
    end;
  finally
    Seen.Free;
  end; // try
  SetLength(Result, N);
end; // function

// ARefs (a BARE-NAME caller lookup) narrowed to refs that can be calls of the
// target. The lookup matches the last name segment only, so for `Create` it
// returned every constructor call in the index (stats\draglint-gaps.log
// 2026-10-23: `modify TDragLintDockFrame.Create` listed TCriticalSection.Create,
// TFileStream.Create, ...). Two rules, both from facts already in the DB:
//  1. a ref the resolver bound to a symbol OUTSIDE ATargetIds is a call of that
//     other symbol, never of the target (refs.symbol_id is the bound target);
//  2. an UNBOUND ref of a CONSTRUCTOR is kept only when its receiver is empty,
//     Self, inherited or the owning type -- the receiver rule of
//     ISymbolStore.FindUnresolvedNameCallers. Ordinary methods skip rule 2: their
//     receiver is usually a variable, and dropping `FFoo.Run` would be worse.
//  3. (1.42 GAP-CALLERS) an UNBOUND ref on the same token (file, line, column) as a
//     ref bound OUTSIDE ATargetIds is dropped too: `TBeta.Build(2)` stores a `call`
//     ref bound to TBeta.Build AND a `member-access` twin left NULL, and rule 1 alone
//     let the twin through as a [name-only] caller of TAlpha.Build.
//  4. (1.42 GAP-CALLERS) when the target is a UNIT-LEVEL routine (AUnitOwner is its
//     unit's qualified name), an UNBOUND ref written with a receiver is kept only
//     when that receiver names the unit (`Unit.Run`):
//     `LSP.Run` / `C.Run` call a METHOD of a value and can never reach a free
//     routine, yet they were listed as [name-only] callers of DRagLint.CLI.Run.
// Guarded by tests\autotest\run_context_callers_scoped_to_target.ps1 (T1-T4).
function CallersOfTarget( const ARefs: TArray<TReference>; const ATargetIds: TArray<Int64>; AIsConstructor: Boolean;
  const AOwnerLeaf, AUnitOwner: string): TArray<TReference>;

  function ReceiverLeaf( const AText: string): string;
  var
    P: Integer;
  begin
    Result:= Trim(AText);
    P:= Pos('<', Result);
    if P > 0 then Result:= Trim(Copy(Result, 1, P - 1));
    P:= LastDelimiter('.', Result);
    if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
  end; // function

  function IsTarget( AId: Int64): Boolean;
  var
    T: Int64;
  begin
    for T in ATargetIds do
      if T = AId then Exit(True);
    Result:= False;
  end; // function

  function TokenKey( const ARef: TReference): string;
  begin
    Result:= Format('%d:%d:%d', [ARef.FileId, ARef.StartLine, ARef.StartCol]);
  end; // function

var
  R        : TReference;
  Recv     : string    ;
  BoundElse: TDictionary<string, Boolean>; { tokens bound to a non-target (rule 3) }
begin
  Result:= [];
  BoundElse:= TDictionary<string, Boolean>.Create;
  try
    for R in ARefs do
      if (R.SymbolId <> 0) and not IsTarget(R.SymbolId) then BoundElse.AddOrSetValue(TokenKey(R), True);
    for R in ARefs do
    begin
      if R.SymbolId <> 0 then
      begin
        if IsTarget(R.SymbolId) then Result:= Result + [R];
        Continue;
      end;
      if BoundElse.ContainsKey(TokenKey(R)) then Continue;
      if (AUnitOwner <> '') and (Trim(R.ReceiverText) <> '') then
      begin
        Recv:= Trim(R.ReceiverText);
        if not (SameText(Recv, AUnitOwner) or SameText(Recv, AOwnerLeaf)
                or EndsText('.' + AUnitOwner, Recv)) then Continue;
      end;
      if AIsConstructor and (AOwnerLeaf <> '') then
      begin
        Recv:= ReceiverLeaf(R.ReceiverText);
        if not ((Recv = '') or SameText(Recv, 'Self') or SameText(Recv, 'inherited') or SameText(Recv, AOwnerLeaf)) then
          Continue;
      end;
      Result:= Result + [R];
    end;
  finally
    BoundElse.Free;
  end; // try
end; // function

{ The library routine the oracle binds for one unresolved call that has no stored
  external_target, or '' (no oracle, no receiver type text, or a decline). Same
  binding find-callees uses (EmitExternalCallees): the receiver type text is
  split at its first dot into the type and the pending member chain. }
function OracleTarget(const AStore: ISymbolStore; AOracle: TLibraryOracle; const ARef: TReference): string;
begin
  Result:= '';
  if (AOracle = nil) or (ARef.ReceiverTypeText = '') then Exit;
  var Dot: Integer:= Pos('.', ARef.ReceiverTypeText);
  var TypeText: string:= (if Dot > 0 then Copy(ARef.ReceiverTypeText, 1, Dot - 1) else ARef.ReceiverTypeText);
  var Pending : string:= (if Dot > 0 then Copy(ARef.ReceiverTypeText, Dot + 1, MaxInt) else '');
  var UsedUnits: TArray<string>:= nil;
  for var U: TUnitUse in AStore.GetUnitUsesForFile(ARef.FileId) do UsedUnits:= UsedUnits + [LowerCase(U.UnitName)];
  var Reason: string;
  Result:= AOracle.Bind(TypeText, Pending, ARef.NameText, ekCall, UsedUnits, Reason);
end; // function

{ D08 / D10 (owner ruling 2026-11-08): the stored external target, named for what it is when
  it is not a library routine -- X (built-in) for a compiler intrinsic, X (event) for an
  event property the call fires. '' when the ref has no stored target. }
function LabelledExternalTarget(const ARef: TReference): string;
begin
  Result:= ARef.ExternalTarget;
  if Result = '' then Exit;
  if ARef.ExternalKind = EXTERNAL_KIND_INTRINSIC then Result:= Format('%s (built-in)', [ARef.ExternalTarget])
  else if ARef.ExternalKind = EXTERNAL_KIND_INDIRECT then Result:= Format('%s (event)', [ARef.ExternalTarget]);
end;
{ Library calls (item 4 / C3, RSV-R2): one query per target id, counted from the stored
  external_target and, when AOracle is set, from calls the oracle binds now; with
  neither, a project indexed without a library gets count 0 and the line stays out of the bundle. ACount is incremented (the
  caller's bundle starts zeroed); ATop receives at most LIBRARY_CALLS_TOP targets,
  most-called first, ties in first-seen order. Split out of TContextBundler.Build
  to keep that routine under the cyclomatic-complexity limit. }
procedure CollectLibraryCalls(const AStore: ISymbolStore; AOracle: TLibraryOracle; const ATargetIds: TArray<Int64>;
  var ACount: Integer; var ATop: TArray<string>; var AVia: string);
var
  LibCounts: TDictionary<string, Integer>;
  LibOrder : TList<string>               ;
  Seen     : Integer                     ;
  Best     : Integer                     ;
begin
  LibCounts:= TDictionary<string, Integer>.Create;
  try
    LibOrder:= TList<string>.Create;
    try
      AVia:= '';
      for var TId: Int64 in ATargetIds do
        for var LR: TReference in AStore.GetUnresolvedCallsFromSymbol(TId) do
        begin
          var Target: string:= LabelledExternalTarget(LR);
          if Target <> '' then AVia:= (if AVia = '' then 'stored' else AVia)
          else
          begin
            Target:= OracleTarget(AStore, AOracle, LR);
            if Target <> '' then AVia:= 'oracle';
          end;
          if Target = '' then Continue;
          Inc(ACount);
          if LibCounts.TryGetValue(Target, Seen) then LibCounts[Target]:= Seen + 1
          else
          begin
            LibCounts.Add(Target, 1);
            LibOrder.Add(Target);
          end;
        end;
      while (Length(ATop) < LIBRARY_CALLS_TOP) and (LibOrder.Count > 0) do
      begin
        Best:= 0;
        for var K: Integer:= 1 to LibOrder.Count - 1 do
          if LibCounts[LibOrder[K]] > LibCounts[LibOrder[Best]] then Best:= K;
        ATop:= ATop + [LibOrder[Best]];
        LibOrder.Delete(Best);
      end;
    finally
      LibOrder.Free;
    end;
  finally
    LibCounts.Free;
  end;
end; // procedure

{ CTX-TYPECAP: the header line of one impl-method chunk -- the first line that
  starts with a routine keyword; the first non-blank line when none does. }
function ChunkHeaderLine(const AText: string): string;
const
  HEADS: array[0..5] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'class ', 'operator ');
begin
  Result:= '';
  for var S: string in AText.Split([#10]) do
  begin
    var T: string:= Trim(S);
    for var H: string in HEADS do
      if StartsText(H, T) then Exit(T);
    if (Result = '') and (T <> '') then Result:= T;
  end;
end;

{ CTX-TYPECAP: the bare method name of a header line (`procedure TFoo<T>.Bar(..)`
  -> `Bar`), '' when none can be read. Generic parameter lists are skipped. }
function HeaderLeafName(const AHeader: string): string;
var
  S    : string ;
  Depth: Integer;
  P    : Integer;
begin
  S:= Trim(AHeader);
  if StartsText('class ', S) then S:= Trim(Copy(S, Length('class ') + 1, MaxInt));
  P:= Pos(' ', S);
  if P = 0 then Exit('');
  S:= Trim(Copy(S, P + 1, MaxInt));  { drop the routine keyword }
  Depth := 0;
  var SB: TStringBuilder:= TStringBuilder.Create;
  try
    for P:= 1 to Length(S) do
    begin
      if S[P] = '<' then Inc(Depth)
      else if S[P] = '>' then Dec(Depth)
      else if Depth = 0 then
      begin
        if not CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Break;
        SB.Append(S[P]);
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
  if LastDelimiter('.', Result) > 0 then Result:= Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ CTX-TYPECAP: the distinct lower-cased identifiers of one chunk's text. }
function ChunkIdentifiers(const AText: string): TDictionary<string, Boolean>;
var
  P    : Integer;
  Start: Integer;
begin
  Result:= TDictionary<string, Boolean>.Create;
  P:= 1;
  while P <= Length(AText) do
  begin
    if CharInSet(AText[P], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Start:= P;
      while (P <= Length(AText)) and CharInSet(AText[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(P);
      Result.AddOrSetValue(LowerCase(Copy(AText, Start, P - Start)), True);
    end
    else Inc(P);
  end;
end;

{ CTX-TYPECAP (owner ruling 2026-11-01; spec
  docs\superpowers\specs\2026-11-03-ctx-typecap-design.md). Caps a TYPE
  target's impl-method bodies at ACap estimated tokens, IN PLACE on ABundle.

  Engages only when the bodies together exceed ACap -- below it the bundle is
  untouched, so a small type renders exactly as before. Ranking: a FOCUS method
  (AFocus, named after the type in the task) first and always kept; then more
  in-type callers (how many OTHER bodies of the type mention the leaf name);
  then smaller first; then source order. Greedy: a body that does not fit the
  remaining budget is skipped and the walk goes on. Kept bodies stay in source
  order; each omitted one becomes a header + line range entry. The class-decl
  chunk is dropped when AHasSurface (it repeats the surface). }
procedure CapTypeBodies(var ABundle: TContextBundle; ACap: Integer; const AFocus: TArray<string>; AHasSurface: Boolean);
var
  Ix     : TArray<Integer>;  { ImplSlice index of each impl-method chunk }
  Leaf   : TArray<string> ;
  Tok    : TArray<Integer>;
  Calls  : TArray<Integer>;
  Forced : TArray<Boolean>;
  Keep   : TArray<Boolean>;
  Order  : TArray<Integer>;
  Total  : Integer        ;
  Used   : Integer        ;
  K      : Integer        ;
  Kept   : TArray<TSliceChunk>;
begin
  Ix:= nil;
  Total:= 0;
  for K:= 0 to High(ABundle.ImplSlice) do
    if ABundle.ImplSlice[K].Kind = 'impl-method' then
    begin
      Ix := Ix  + [K];
      Tok:= Tok + [TContextBundler.EstimateTokens(ABundle.ImplSlice[K].Text)];
      Inc(Total, Tok[High(Tok)]);
    end;
  if Total <= ACap then Exit;

  SetLength(Leaf  , Length(Ix));
  SetLength(Calls , Length(Ix));
  SetLength(Forced, Length(Ix));
  SetLength(Keep  , Length(Ix));
  SetLength(Order , Length(Ix));
  for K:= 0 to High(Ix) do
  begin
    Leaf[K]:= LowerCase(HeaderLeafName(ChunkHeaderLine(ABundle.ImplSlice[Ix[K]].Text)));
    Order[K]:= K;
    for var F: string in AFocus do
    begin
      var FL: string:= F;
      if LastDelimiter('.', FL) > 0 then FL:= Copy(FL, LastDelimiter('.', FL) + 1, MaxInt);
      if (Leaf[K] <> '') and SameText(FL, Leaf[K]) then Forced[K]:= True;
    end;
  end;

  { In-type callers: one tokenisation per chunk, then one lookup per leaf. A
    body sharing the leaf (an overload) is not counted as its caller. }
  for K:= 0 to High(Ix) do
  begin
    var Ids: TDictionary<string, Boolean>:= ChunkIdentifiers(ABundle.ImplSlice[Ix[K]].Text);
    try
      for var J: Integer:= 0 to High(Ix) do
        if (Leaf[J] <> '') and (Leaf[J] <> Leaf[K]) and Ids.ContainsKey(Leaf[J]) then Inc(Calls[J]);
    finally
      Ids.Free;
    end;
  end;

  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result:= Ord(Forced[B]) - Ord(Forced[A]);
      if Result = 0 then Result:= Calls[B] - Calls[A];
      if Result = 0 then Result:= Tok[A] - Tok[B];
      if Result = 0 then Result:= A - B;
    end));

  Used:= 0;
  for K in Order do
    if Forced[K] or (Used + Tok[K] <= ACap) then
    begin
      Keep[K]:= True;
      Inc(Used, Tok[K]);
    end;

  ABundle.BodyCap        := ACap;
  ABundle.BodiesTotal    := Length(Ix);
  ABundle.BodyTokensTotal:= Total;
  ABundle.BodyTokensShown:= Used;
  Kept:= nil;
  var M: Integer:= 0;  { position in Ix }
  for K:= 0 to High(ABundle.ImplSlice) do
  begin
    var C: TSliceChunk:= ABundle.ImplSlice[K];
    if C.Kind = 'impl-method' then
    begin
      if Keep[M] then Kept:= Kept + [C]
      else
      begin
        var O: TSliceChunk:= C;
        O.Text:= ChunkHeaderLine(C.Text);
        ABundle.OmittedBodies:= ABundle.OmittedBodies + [O];
        ABundle.OmittedTokens:= ABundle.OmittedTokens + [Tok[M]];
      end;
      Inc(M);
    end
    else if (C.Kind = 'class-decl') and AHasSurface then
    begin
      var O: TSliceChunk:= C;
      O.Text:= 'class declaration (its members are listed in ## Class surface)';
      ABundle.OmittedBodies:= ABundle.OmittedBodies + [O];
      ABundle.OmittedTokens:= ABundle.OmittedTokens + [TContextBundler.EstimateTokens(C.Text)];
    end
    else Kept:= Kept + [C];
  end;
  ABundle.ImplSlice:= Kept;
end;

// CTX-SURFACE-DOCS (1.42, owner ruling D8): the member name a class-surface
// declaration line declares ('' when the line is not a member declaration: a
// visibility keyword, the `TFoo = class` header, an attribute, a blank line).
function SurfaceMemberLeaf(const ALine: string): string;
var
  T: string ;
  P: Integer;
begin
  T:= Trim(ALine);
  if (T = '') or not CharInSet(T[1], ['A'..'Z', 'a'..'z', '_']) then Exit('');
  if StartsText('procedure ', T) or StartsText('function ', T) or StartsText('constructor ', T) or StartsText('destructor ', T) or StartsText('class ', T) or  // dl:ok boolean-expression-complexity@f722 -- REVIEWED 2026-11-04: a flat keyword list, one alternative per header kind
    StartsText('operator ', T) or StartsText('property ', T) then Exit(LowerCase(HeaderLeafName(T)));
  P:= 1;
  while (P <= Length(T)) and CharInSet(T[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(P);
  if (P <= Length(T)) and (T[P] = ':') then Exit(LowerCase(Copy(T, 1, P - 1)));
  Result:= '';
end;

// CTX-SURFACE-DOCS (1.42, owner ruling D8): on a CAPPED type the surface drops
// the comment-only lines that document a member whose body the cap omitted
// (TSQLiteSymbolStore: 72k -> ~25k tokens). A member whose body is KEPT (a focus
// word, in-type callers) keeps its docs, and a line that is not a recognised
// member declaration keeps the comments above it.
function DropCappedMemberDocs(const ASurface: TArray<TSurfaceLine>; const AKeptLeaves: TDictionary<string, Boolean>): TArray<TSurfaceLine>;
var
  Acc    : TList<TSurfaceLine>;
  Pending: TList<TSurfaceLine>;
  L      : TSurfaceLine       ;
  Leaf   : string             ;
begin
  Acc    := TList<TSurfaceLine>.Create;
  Pending:= TList<TSurfaceLine>.Create;
  try
    for L in ASurface do
      if TrimLeft(L.Text).StartsWith('//') then Pending.Add(L)
      else
      begin
        Leaf:= SurfaceMemberLeaf(L.Text);
        if (Leaf = '') or AKeptLeaves.ContainsKey(Leaf) then Acc.AddRange(Pending);
        Pending.Clear;
        Acc.Add(L);
      end;
    Acc.AddRange(Pending);
    Result:= Acc.ToArray;
  finally
    Pending.Free;
    Acc.Free;
  end; // try
end; // function

{ How many impl-method bodies the cap omitted (the class-decl entry excluded). }
function OmittedMethodCount(const ABundle: TContextBundle): Integer;
begin
  Result:= 0;
  for var O: TSliceChunk in ABundle.OmittedBodies do
    if O.Kind = 'impl-method' then Inc(Result);
end;

class function TContextBundler.Build(
  const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
  AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True; const ATaskText: string = ''; AOracle: TLibraryOracle = nil;
        ABodyTokenCap: Integer = CONTEXT_BODY_TOKEN_CAP): TContextBundle;
var
  Syms       : TArray<TSymbol>   ;
  Sym        : TSymbol           ;
  EffQName   : string            ;  { the RESOLVED qname -- see its assignment }
  ParentQName: string            ;
  OwnerIsClass: Boolean          ;  { the lean DFM-field filter runs only for a CLASS owner }
  CallerName : string            ;
  RawCallers : TArray<TReference>;
  TargetIds  : TArray<Int64>     ;  { every symbol id under EffQName (overloads) }
  OwnerLeaf  : string            ;  { 'TType' of Unit.TType.Member; '' for a free routine }
  UnitOwner  : string            ;  { the unit's qualified name when the target is unit-level, else '' }
  Total     : Integer           ;
  SB         : TStringBuilder    ;
  I          : Integer           ;
  L          : TSurfaceLine      ;
  C          : TSliceChunk       ;
  BC         : TBundleCaller     ;
  VTot       : TBundleViaTotal   ;
  R          : TReference        ;
  LookupName : string            ;  { AQName's first word -- see the focus words }
  Focus      : TArray<string>    ;  { CTX-TYPECAP focus method names }

  { Up to MAX_WIKI_TOPICS topics whose name or alias the task phrase matched.

    THIS IS THE ROUTER FROM HUMAN VOCABULARY TO SYMBOLS, and it earns its place
    in a bundle whose whole reason to exist is being small: two short concept
    notes are cheap, and the alternative is the reader guessing which identifier
    a project noun refers to. A third loosely-matching note is not.

    Runs against the TARGET DB ONLY -- the store handed in, not the resolved
    set. A concept note from an unrelated project's index would be a confident
    wrong answer, which is worse than none. }
  procedure MatchWikiTopics;
  const
    MAX_WIKI_TOPICS = 2;
  var
    Rows  : TArray<TWikiDocRow>;
    Row   : TWikiDocRow        ;
    Cands : TArray<TWikiTopic> ;
    Scores: TArray<Integer>    ;
    T     : TWikiTopic         ;
    Best  : Integer            ;
    BestIx: Integer            ;
    K     : Integer            ;
    N     : Integer            ;
  begin
    if Trim(ATaskText) = '' then Exit;
    Rows:= AStore.FindWikiDocBlocks;
    if Length(Rows) = 0 then Exit;

    SetLength(Cands, 0);
    for Row in Rows do
      for T in TWikiParser.ParseRawBlock(Row.RawBlock, Row.QName, Row.Kind,
                                         Row.FilePath, Row.StartLine) do
        if TWikiParser.MatchScore(T, ATaskText) > 0 then Cands:= Cands + [T];
    if Length(Cands) = 0 then Exit;

    SetLength(Scores, Length(Cands));
    for K:= 0 to High(Cands) do Scores[K]:= TWikiParser.MatchScore(Cands[K], ATaskText);

    { Selection rather than a sort: at most two are kept, so repeatedly taking
      the best and blanking it is both shorter and obviously correct. }
    N:= Length(Cands);
    if N > MAX_WIKI_TOPICS then N:= MAX_WIKI_TOPICS;
    for K:= 1 to N do
    begin
      Best  := -1;
      BestIx:= -1;
      for var J: Integer:= 0 to High(Cands) do
        if (Scores[J] > 0) and
           ((BestIx < 0) or (TWikiParser.CompareRanked(Scores[J], Cands[J].Name,
                                                       Best, Cands[BestIx].Name) < 0)) then
        begin
          Best  := Scores[J];
          BestIx:= J;
        end;
      if BestIx < 0 then Break;
      Result.WikiTopics:= Result.WikiTopics + [Cands[BestIx]];
      Scores[BestIx]:= 0;
    end;
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Verb       := AVerb;
  Result.GeneratedAt:= Now;

  { CTX-TYPECAP focus words: a qname never contains a space, so in
    `TFoo Bar Baz` the first word is the symbol and the rest name methods whose
    bodies CapTypeBodies always keeps. A phrase without a space is unchanged. }
  LookupName:= Trim(AQName);
  Focus     := nil;
  if LookupName.Contains(' ') then
  begin
    Focus     := Copy(LookupName, Pos(' ', LookupName) + 1, MaxInt).Split([' ', ','], TStringSplitOptions.ExcludeEmpty);
    LookupName:= Copy(LookupName, 1, Pos(' ', LookupName) - 1);
  end;
  Result.QName:= LookupName;

  Syms:= AStore.FindSymbolsByQualifiedName(LookupName);

  { BARE NAME FALLBACK. FindSymbolsByQualifiedName matches the FULL dotted name,
    so `context --task "modify TypeIsRefCountedOrValue"` found nothing and this
    function returned an empty bundle with `Token count (estimated): 0` and exit
    0 -- indistinguishable from "this symbol has no context". Meanwhile
    `query --name <same bare name>` resolved it to exactly one symbol, so the
    information was there and only this lookup could not reach it.

    It matters out of proportion to its size: CLAUDE.md instructs every session
    to run this verb BEFORE reading a large .pas, so the silent empty answer
    costs exactly the ~60x token saving the feature exists to provide, and looks
    like the feature working.

    Resolved ONLY when the name is unambiguous. Picking Syms[0] out of several
    same-named symbols would hand back a confidently-wrong bundle -- a worse
    failure than the empty one, because nothing about it looks wrong. Ambiguous
    bare names still return empty, and the caller reports "not found", which
    remains the honest answer for a name that does not identify one symbol.
    See docs\INBOX-context-bundle-empty-for-bare-name.md.

    CLASS-QUALIFIED SUFFIX (2026-09-17). Between the bare name (no dot) and the full qname
    there was nothing: `modify TIndexer.ApplyInheritedFieldFacts` -- the form a
    reader naturally types after seeing a class surface -- answered "No symbol
    matched" while BOTH the bare member and the unit-qualified name resolved
    (INBOX 2026-09-17, section 1). The middle spelling resolved less readily
    than either neighbour.

    A dotted name that is not a whole qname resolves when EXACTLY ONE symbol's
    qualified_name ends with `.<the typed text>` -- segment-aligned (the char
    before the suffix must be a '.', so `orker.UniqueMethod` never matches
    `uA.TWorker.UniqueMethod`), case-insensitive, and with every segment's
    `<...>` list stripped first because symbols are stored under BARE names
    since schema v23. The candidates come from the LAST segment's exact-name
    lookup, which is the same index the bare-name rule uses.

    The bare-name policy is kept, not relaxed: two units each declaring
    `TTwin.Shared` is ambiguous and still returns nothing, because a
    confidently-wrong bundle is worse than an empty one.

    Guarded by tests\autotest\run_context_class_qualified_name.ps1; the bare
    rule by run_context_bare_name_body.ps1. Both live in ResolveUniqueName. }
  if Length(Syms) = 0 then
  begin
    Syms:= ResolveUniqueName(AStore, LookupName);
    { Report the resolved QUALIFIED name, not the text the caller typed --
      the bundle header is the reader's evidence of WHICH symbol they got. }
    if Length(Syms) = 1 then Result.QName:= Syms[0].QualifiedName;
  end;

  { THE ALIAS IS ALSO A FALLBACK, not only an enrichment. When the qname
    resolved to nothing, the task phrase may still name a CONCEPT -- which is
    exactly the case where the caller used a project word instead of an
    identifier. Returning the topic and its SeeCode symbols turns a bare "not
    found" into the pointer the reader was actually asking for. }
  if Length(Syms) = 0 then
  begin
    if AIncludeDocs then MatchWikiTopics;
    if Length(Result.WikiTopics) > 0 then
      for I:= 0 to High(Result.WikiTopics) do
        Inc(Result.TokenEstimate, EstimateTokens(Result.WikiTopics[I].Body));
    Exit;
  end;
  Sym          := Syms[0];
  Result.Resolved:= True;

  { THE NAME TO USE FROM HERE DOWN IS THE RESOLVED ONE, NEVER THE TYPED ONE.

    The bare-name fallback above (:293-303) resolved `DoHover` to
    `DRagLint.CLI.DoHover` and set Result.QName so the HEADER named the symbol
    the reader actually got. Three consumers below kept reading the raw AQName,
    which is still the bare word -- so the class surface, the impl slice and the
    caller lookup were all asked about a name the store cannot match. Measured
    2026-09-15: `context --task "modify DoHover"` returned 870 bytes with no
    `## Impl slice` while the qualified form returned 5,035 bytes with one, and
    the bare bundle's own header said `DRagLint.CLI.DoHover`.

    That is the worst shape a bundle can take: it resolves, it says which symbol
    it resolved to, and it silently omits the body the task named -- so an agent
    edits a routine it never saw and nothing looks wrong. The header was made
    honest; the body was not. One name, used everywhere, is the fix.

    Guarded by tests\autotest\run_context_bare_name_body.ps1. }
  EffQName:= Sym.QualifiedName;
  if EffQName = '' then EffQName:= LookupName;  { defensive: never regress to empty }

  if AIncludeDocs then MatchWikiTopics;

  // Doc
  if AIncludeDocs then
  begin
    Result.Doc:= AStore.GetSymbolDoc(Sym.Id);
    Result.HasDoc:= Result.Doc.HasContent;
  end;

  { Class surface. For a METHOD the surface wanted is its owning class, which is
    everything before the last '.'. For a TYPE it is the type's OWN surface --
    chopping the last segment there yields the UNIT, which has no class surface,
    so `context --task "modify <Unit.TType>"` came back with no `## Class
    surface` section at all: the one question a type-shaped task is asking (what
    members does this thing have?) was the one the bundle did not answer, while
    the same task aimed at any single method of that type answered it fine. }
  if AIncludeSurface then
  begin
    if Sym.Kind in [skClass, skInterface, skRecord] then
    begin
      ParentQName := Sym.QualifiedName;
      OwnerIsClass:= Sym.Kind = skClass;
    end
    else
    begin
      ParentQName:= EffQName;
      if LastDelimiter('.', ParentQName) > 0 then ParentQName:= Copy(ParentQName, 1, LastDelimiter('.', ParentQName) - 1);
      if ParentQName = EffQName then ParentQName:= '';  { no owner to describe }
      OwnerIsClass:= OwnerIsClassKind(AStore, ParentQName);  { decides whether the lean filter may run -- see below }
    end;
    if ParentQName <> '' then
    begin
      Result.ClassSurface:= AStore.GetClassSurface(ParentQName, False, False);
      { Strip the auto-generated DFM component fields unless the caller asked
        for the full surface (e.g. when working on the form's components/DFM).

        ONLY WHEN THE OWNER IS A CLASS. StripDfmFields treats the default
        (pre-specifier) section as published and drops every `Ident: TType;`
        line in it -- the shape of a form's component dump. A RECORD has no
        visibility specifiers, so ALL of its fields sit in that section and
        every one of them looked like a component field: measured 2026-09-17,
        `modify TTypeAncestor` printed ONE of eight fields (Ordinal, whose
        trailing `// comment` stops the line ending in ';') and the `///` doc
        comments of the other seven with the declarations they documented
        MISSING. Nothing in a record or an interface is DFM-streamed, so the
        filter has nothing to remove there. Guarded by
        tests\autotest\run_context_record_surface.ps1. }
      if AExcludeDfmFields and OwnerIsClass then Result.ClassSurface:= StripDfmFields(Result.ClassSurface);
      { GAP-CONTEXT (1.40): a MEMBER target's lean surface is declarations only
        -- see StripCommentOnlyLines. A TYPE target keeps its members' docs (the
        question it asks), and --full-surface keeps everything. Guarded by
        tests\autotest\run_context_member_surface_lean.ps1. }
      if AExcludeDfmFields and (Sym.Kind not in [skClass, skInterface, skRecord]) then
        Result.ClassSurface:= StripCommentOnlyLines(Result.ClassSurface);
    end;
  end;

  // Impl slice -- ONLY the target symbol's own body, never the whole parent
  // class.  Pulling the parent's slice dragged in every sibling method body, so
  // the bundle was ~the whole source file (bench-context ~1x, no savings).  The
  // class SURFACE (signatures, cheap) already supplies the surrounding shape;
  // the body the caller actually needs is the target's own.  (v0.41)
  if AIncludeImpl then Result.ImplSlice:= AStore.GetSymbolSlice(EffQName);
  { CTX-TYPECAP: a whole TYPE's slice is every method body; cap it. }
  if AIncludeImpl and (ABodyTokenCap > 0) and (Sym.Kind in [skClass, skInterface, skRecord]) then
  begin
    CapTypeBodies(Result, ABodyTokenCap, Focus, Length(Result.ClassSurface) > 0);
    if Result.BodyCap > 0 then Result.BodyFile:= AStore.GetFilePath(Sym.FileId);
    { CTX-SURFACE-DOCS: lean surface only; --full-surface keeps every doc. }
    if (Result.BodyCap > 0) and AExcludeDfmFields then
    begin
      var KeptLeaves: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
      try
        for var KC: TSliceChunk in Result.ImplSlice do
          if KC.Kind = 'impl-method' then KeptLeaves.AddOrSetValue(LowerCase(HeaderLeafName(ChunkHeaderLine(KC.Text))), True);
        Result.ClassSurface:= DropCappedMemberDocs(Result.ClassSurface, KeptLeaves);
      finally
        KeptLeaves.Free;
      end;
    end;
  end;

  // Callers (truncated to AMaxCallers; resolve FilePath from store)
  CallerName:= EffQName;
  if LastDelimiter('.', CallerName) > 0 then CallerName:= Copy(CallerName, LastDelimiter('.', CallerName) + 1, MaxInt);
  TargetIds:= [];
  for var TS: TSymbol in AStore.FindSymbolsByQualifiedName(EffQName) do TargetIds:= TargetIds + [TS.Id];
  if Length(TargetIds) = 0 then TargetIds:= [Sym.Id];
  OwnerLeaf:= Copy(EffQName, 1, Length(EffQName) - Length(CallerName) - 1);
  { rule 4 of CallersOfTarget: the owning UNIT's name when the target is a unit-level routine }
  UnitOwner:= '';
  for var OS: TSymbol in AStore.FindSymbolsByQualifiedName(OwnerLeaf) do
    if OS.Kind = skUnit then UnitOwner:= OwnerLeaf;
  if LastDelimiter('.', OwnerLeaf) > 0 then OwnerLeaf:= Copy(OwnerLeaf, LastDelimiter('.', OwnerLeaf) + 1, MaxInt);
  RawCallers:= DistinctCallSites(CallersOfTarget(AStore.FindCallersByNameWithContext(CallerName, ACallerContext),
                                                 TargetIds, Sym.Kind = skConstructor, OwnerLeaf, UnitOwner));
  Result.TotalCallers:= Length(RawCallers); { XERJ item 2: the count BEFORE the cut }
  Result.CallerCap   := AMaxCallers;
  if Length(RawCallers) > AMaxCallers then SetLength(RawCallers, AMaxCallers);
  SetLength(Result.Callers, Length(RawCallers));
  for I:= 0 to High(RawCallers) do
  begin
    R:= RawCallers[I];
    BC.FilePath:= AStore.GetFilePath(R.FileId);
    BC.Line       := R.StartLine;
    BC.Col        := R.StartCol;
    BC.ContextText:= R.ContextText;
    BC.Resolution := R.Resolution ;
    Result.Callers[I]:= BC;
  end;

  { RB-5 P1: sites that reach the target only through the interface method it
    implements. Same truncation as Callers; the text is the call line, no
    context window, to keep the bundle small. }
  VTot:= Default(TBundleViaTotal);
  if Sym.Kind in [skProcedure, skFunction, skMethod] then
    for var TgtId in TargetIds do
      for var VR in DispatchCallersOf(AStore, TgtId) do
      begin
        if VR.ViaCount > 0 then
        begin
          VTot.Via  := VR.Via     ;
          VTot.Count:= VR.ViaCount;
          Result.ViaTotals:= Result.ViaTotals + [VTot];
        end;
        if Length(Result.ViaCallers) >= AMaxCallers then Continue;
        BC:= Default(TBundleCaller);
        BC.FilePath:= VR.FullPath;
        BC.Line    := VR.CallSiteLine;
        BC.Via     := VR.Via;
        Result.ViaCallers:= Result.ViaCallers + [BC];
      end;

  CollectLibraryCalls(AStore, AOracle, TargetIds, Result.LibraryCallCount, Result.LibraryCallTop, Result.LibraryCallVia);

  // Impact summary (for refactor/delete verbs)
  if SameText(AVerb, 'refactor') or SameText(AVerb, 'delete') then Result.ImpactSummary:= AStore.FindTransitiveCallers(CallerName, 2);

  // Compute token estimate from all major text contributions
  SB:= TStringBuilder.Create;
  try
    if Result.HasDoc then SB.Append(Result.Doc.RawBlock);
    SB.AppendLine;
    SB.AppendLine;
    Total:= EstimateTokens(SB.ToString);
    for I:= 0 to High(Result.ClassSurface) do
    begin
      L:= Result.ClassSurface[I];
      Inc(Total, EstimateTokens(L.Text));
    end;
    for I:= 0 to High(Result.ImplSlice) do
    begin
      C:= Result.ImplSlice[I];
      Inc(Total, EstimateTokens(C.Text));
    end;
    { The omitted-bodies list is rendered, so it is counted (header + range). }
    for I:= 0 to High(Result.OmittedBodies) do Inc(Total, EstimateTokens(Result.OmittedBodies[I].Text) + OMITTED_LINE_TOKENS);
    for I:= 0 to High(Result.Callers) do
    begin
      BC:= Result.Callers[I];
      Inc(Total, EstimateTokens(BC.ContextText));
    end;
    { Wiki bodies are rendered, so they are counted. A token estimate that
      omitted a section the reader can see would understate the bundle by
      exactly the amount that matters when deciding whether to read it. }
    for I:= 0 to High(Result.WikiTopics) do
      Inc(Total, EstimateTokens(Result.WikiTopics[I].Name + Result.WikiTopics[I].Body));
    Result.TokenEstimate:= Total;
  finally
    SB.Free;
  end; // try
end; // function

class function TContextBundler.RenderMarkdown( const ABundle: TContextBundle): string;
var
  SB: TStringBuilder;
  I : Integer       ;
  L : TSurfaceLine  ;
  C : TSliceChunk   ;
  BC: TBundleCaller ;
  IL: TImpactLevel  ;
begin
  SB:= TStringBuilder.Create;
  try
    SB.AppendLine('# Context bundle: ' + ABundle.Verb + ' ' + ABundle.QName);
    SB.AppendLine;
    { The RUNNING engine's version. This said a literal `v0.18` -- the release
      that added the bundle -- for every engine after it. }
    SB.AppendLine(Format('> Generated by drag-lint v%s at %s', [DRAGLINT_VERSION, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', ABundle.GeneratedAt)]));
    SB.AppendLine(Format('> Token count (estimated): %d', [ABundle.TokenEstimate]));
    { Say it in the DOCUMENT, not only in the exit code. A bundle that silently
      contains nothing reads as "this symbol has no context"; one that says the
      name did not resolve sends the reader somewhere useful. }
    if not ABundle.Resolved then
      SB.AppendLine(Format('> NOT FOUND: no symbol named `%s` in this index.%s',
        [ABundle.QName,
         IfThen(Length(ABundle.WikiTopics) > 0,
                ' The phrase does match a wiki topic -- see below.', '')]));
    SB.AppendLine;

    if ABundle.HasDoc then
    begin
      SB.AppendLine('## Doc');
      // v(ADP3 T1) review fix: strip the AUTO_MARK ownership token (and, for
      // Remarks, the AUTO_BEGIN/AUTO_END facts-fence) before it reaches this
      // agent-facing bundle -- see TDocRegions.StripForDisplay's own comment.
      // The read path (ABundle.Doc.* themselves) must keep carrying it.
      var CleanSummary: string:= TDocRegions.StripForDisplay(ABundle.Doc.Summary    );
      var CleanReturns: string:= TDocRegions.StripForDisplay(ABundle.Doc.ReturnsText);
      var CleanRemarks: string:= TDocRegions.StripForDisplay(ABundle.Doc.Remarks    );
      if CleanSummary <> '' then SB.AppendLine('**Summary:** ' + CleanSummary);
      if CleanReturns <> '' then SB.AppendLine('**Returns:** ' + CleanReturns);
      if CleanRemarks <> '' then SB.AppendLine('**Remarks:** ' + CleanRemarks);
      SB.AppendLine;
    end;

    { FIRST, above the code. A concept note explains what the symbols below are
      FOR, and a reader who meets it after the impl slice has already had to
      guess. It is also what makes a "not found" bundle useful: when the qname
      resolved to nothing, this section is the entire answer. }
    if Length(ABundle.WikiTopics) > 0 then
    begin
      SB.AppendLine('## Wiki');
      for I:= 0 to High(ABundle.WikiTopics) do
      begin
        var W: TWikiTopic:= ABundle.WikiTopics[I];
        SB.AppendLine(Format('### %s', [W.Name]));
        SB.AppendLine(Format('- defined at: %s:%d (%s)', [W.FilePath, W.HeaderLine, W.OwnerQName]));
        if Length(W.Aliases) > 0 then
          SB.AppendLine('- also called: ' + string.Join(', ', W.Aliases));
        if Length(W.SeeCode) > 0 then
          SB.AppendLine('- see code: ' + string.Join(', ', W.SeeCode));
        if W.Body <> '' then
        begin
          SB.AppendLine;
          SB.AppendLine(W.Body);
        end;
        SB.AppendLine;
      end;
    end;

    if Length(ABundle.ClassSurface) > 0 then
    begin
      SB.AppendLine('## Class surface');
      SB.AppendLine('```pascal'       );
      for I:= 0 to High(ABundle.ClassSurface) do
      begin
        L:= ABundle.ClassSurface[I];
        SB.AppendLine(L.Text);
      end;
      SB.AppendLine('```');
      SB.AppendLine;
    end;

    if Length(ABundle.ImplSlice) > 0 then
    begin
      SB.AppendLine('## Impl slice');
      // A stale-anchor chunk means the slice refused (index older than the unit):
      // say so OUTSIDE the code fence, where a reader cannot skim past it.
      for I:= 0 to High(ABundle.ImplSlice) do
        if ABundle.ImplSlice[I].Kind = 'stale-anchor' then
          SB.AppendLine('> **WARNING: STALE INDEX** -- the recorded line no longer holds this symbol; no body shown. ' +
            'Reindex, then ask again.');
      SB.AppendLine('```pascal'    );
      for I:= 0 to High(ABundle.ImplSlice) do
      begin
        C:= ABundle.ImplSlice[I];
        SB.AppendLine('// --- ' + C.Kind + ' ---');
        SB.AppendLine(C.Text);
      end;
      SB.AppendLine('```');
      SB.AppendLine;
    end;

    { CTX-TYPECAP: the bodies the type cap left out, as header + line range. }
    if Length(ABundle.OmittedBodies) > 0 then
    begin
      SB.AppendLine(Format('## Omitted bodies (%d of %d method bodies; body cap %d tokens, shown ~%d of ~%d)',
        [OmittedMethodCount(ABundle), ABundle.BodiesTotal, ABundle.BodyCap, ABundle.BodyTokensShown, ABundle.BodyTokensTotal]));
      SB.AppendLine('file: ' + ABundle.BodyFile);
      for I:= 0 to High(ABundle.OmittedBodies) do
        SB.AppendLine(Format('- `%s` -- L%d-%d (~%d tok)', [ABundle.OmittedBodies[I].Text, ABundle.OmittedBodies[I].StartLine,
          ABundle.OmittedBodies[I].EndLine, ABundle.OmittedTokens[I]]));
      SB.AppendLine(CapOmittedNote(OmittedMethodCount(ABundle), ABundle.BodyCap, False, '--max-body-tokens', 0));
      SB.AppendLine;
    end;

    if ABundle.LibraryCallCount > 0 then
    begin
      SB.AppendLine(Format('Library calls: %d (top: %s)', [ABundle.LibraryCallCount, string.Join(', ', ABundle.LibraryCallTop)]));
      SB.AppendLine;
    end;

    if Length(ABundle.Callers) > 0 then
    begin
      if ABundle.TotalCallers > Length(ABundle.Callers) then
        SB.AppendLine(Format('## Callers (%d of %d)', [Length(ABundle.Callers), ABundle.TotalCallers]))
      else
        SB.AppendLine(Format('## Callers (%d)', [Length(ABundle.Callers)]));
      for I:= 0 to High(ABundle.Callers) do
      begin
        BC:= ABundle.Callers[I];
        { XERJ item 3: only a caller that is NOT an exact bind says so. }
        SB.AppendLine(Format('- %s:%d:%d%s', [BC.FilePath, BC.Line, BC.Col,
          (if (BC.Resolution = '') or (BC.Resolution = RESOLUTION_EXACT) then '' else ' [' + BC.Resolution + ']')]));
        if BC.ContextText <> '' then
        begin
          SB.AppendLine('  ```');
          SB.AppendLine(BC.ContextText);
          SB.AppendLine('  ```');
        end;
      end;
      if ABundle.TotalCallers > Length(ABundle.Callers) then
        SB.AppendLine(CapOmittedNote(ABundle.TotalCallers - Length(ABundle.Callers), ABundle.CallerCap, False, '--max-callers', ABundle.TotalCallers));
    end;

    if Length(ABundle.ViaCallers) > 0 then
    begin
      var LastVia: string:= #0;
      for I:= 0 to High(ABundle.ViaCallers) do
      begin
        BC:= ABundle.ViaCallers[I];
        if BC.Via <> LastVia then
        begin
          var Cnt: Integer:= 0;
          for var VT in ABundle.ViaTotals do
            if VT.Via = BC.Via then Inc(Cnt, VT.Count);
          SB.AppendLine(Format('## Callers via interface dispatch (%s): %d site(s)', [BC.Via, Cnt]));
          LastVia:= BC.Via;
        end;
        SB.AppendLine(Format('- %s:%d', [BC.FilePath, BC.Line]));
      end;
    end;

    if Length(ABundle.ImpactSummary) > 0 then
    begin
      SB.AppendLine('## Impact summary');
      for I:= 0 to High(ABundle.ImpactSummary) do
      begin
        IL:= ABundle.ImpactSummary[I];
        SB.AppendLine(Format('- Depth %d: %d callers in %d units', [IL.Depth, IL.CallerCount, IL.UnitCount]));
      end;
    end;

    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

class function TContextBundler.RenderRaw(const ABundle: TContextBundle): string;
var
  SB: TStringBuilder;
  I : Integer       ;
  L : TSurfaceLine  ;
  C : TSliceChunk   ;
begin
  SB:= TStringBuilder.Create;
  try
    if ABundle.HasDoc then
    begin
      SB.AppendLine(ABundle.Doc.RawBlock);
      SB.AppendLine;
    end;
    for I:= 0 to High(ABundle.ClassSurface) do
    begin
      L:= ABundle.ClassSurface[I];
      SB.AppendLine(L.Text);
    end;
    SB.AppendLine;
    for I:= 0 to High(ABundle.ImplSlice) do
    begin
      C:= ABundle.ImplSlice[I];
      SB.AppendLine(C.Text);
    end;
    for I:= 0 to High(ABundle.OmittedBodies) do  { CTX-TYPECAP }
      SB.AppendLine(Format('// omitted: %s  (L%d-%d)', [ABundle.OmittedBodies[I].Text, ABundle.OmittedBodies[I].StartLine, ABundle.OmittedBodies[I].EndLine]));
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

class function TContextBundler.RenderJson(const ABundle: TContextBundle): string;
var
  Wiki   : string    ;
  LibJson: string    ;
  I      : Integer   ;
  W      : TWikiTopic;
begin
  { The wiki topics are NAMED here rather than dumped: a JSON consumer that
    wants the body has `wiki --term`, and a bundle summary that inlined
    paragraphs would stop being a summary. `resolved` is new and load-bearing --
    without it a consumer cannot tell an empty bundle from a missing symbol. }
  Wiki:= '';
  for I:= 0 to High(ABundle.WikiTopics) do
  begin
    W:= ABundle.WikiTopics[I];
    if I > 0 then Wiki:= Wiki + ',';
    Wiki:= Wiki + Format('{"name":"%s","file":"%s","line":%d}',
      [JsonEscape(W.Name), JsonEscape(W.FilePath), W.HeaderLine]);
  end;

  LibJson:= '';
  if ABundle.LibraryCallCount > 0 then
  begin
    var Quoted: TArray<string>:= nil;
    for I:= 0 to High(ABundle.LibraryCallTop) do Quoted:= Quoted + ['"' + JsonEscape(ABundle.LibraryCallTop[I]) + '"'];
    LibJson:= Format(',"library_calls":{"count":%d,"via":"%s","top":[%s]}', [ABundle.LibraryCallCount, ABundle.LibraryCallVia, string.Join(',', Quoted)]);
  end;

  { XERJ item 3: the bundle JSON carries counts, not caller rows, so the resolution kinds
    arrive as a tally object (an additive key, after library_calls). }
  var ResTally: TResolutionTally:= Default(TResolutionTally);
  for I:= 0 to High(ABundle.Callers) do ResTally.Add(ABundle.Callers[I].Resolution);
  LibJson:= LibJson + Format(',"caller_resolution":{"exact":%d,"ambiguous":%d,"external":%d,"name-only":%d}',
    [ResTally.Exact, ResTally.Ambiguous, ResTally.External, ResTally.NameOnly]);

  { RB-5 (1.38): the sites that reach the target only through its interface, as
    impact's "via_dispatch" shape (an array of via/kind/sites objects); the key is present only
    when non-empty. Totals for one interface method are summed (two target ids
    of one QName can report the same via). DispatchCallersOf walks 'implements'
    edges only, so kind is 'interface'. Pinned by run_context_via_callers_guard.ps1. }
  if Length(ABundle.ViaTotals) > 0 then
  begin
    var ViaNames: TArray<string>:= nil;
    var ViaSites: TArray<Integer>:= nil;
    for var VT in ABundle.ViaTotals do
    begin
      var At: Integer:= -1;
      for I:= 0 to High(ViaNames) do
        if ViaNames[I] = VT.Via then At:= I;
      if At < 0 then
      begin
        ViaNames:= ViaNames + [VT.Via];
        ViaSites:= ViaSites + [0];
        At:= High(ViaNames);
      end;
      Inc(ViaSites[At], VT.Count);
    end;
    var ViaJson: TArray<string>:= nil;
    for I:= 0 to High(ViaNames) do
      ViaJson:= ViaJson + [Format('{"via":"%s","kind":"interface","sites":%d}', [JsonEscape(ViaNames[I]), ViaSites[I]])];
    LibJson:= LibJson + ',"via_dispatch":[' + string.Join(',', ViaJson) + ']';
  end;

  Result:= Format(
    '{"task":"%s","verb":"%s","qname":"%s","resolved":%s,"token_estimate":%d,' +
    '"has_doc":%s,"caller_count":%d,"surface_lines":%d,"slice_chunks":%d,"wiki":[%s]%s,"omitted":%d,"cap":%d}', [
      JsonEscape(ABundle.Verb + ' ' + ABundle.QName), JsonEscape(ABundle.Verb), JsonEscape(ABundle.QName),
      IfThen(ABundle.Resolved, 'true', 'false'),
      ABundle.TokenEstimate, IfThen(ABundle.HasDoc, 'true', 'false'), Length(ABundle.Callers),
      Length(ABundle.ClassSurface), Length(ABundle.ImplSlice), Wiki, LibJson,
      Ord(ABundle.TotalCallers > Length(ABundle.Callers)) * (ABundle.TotalCallers - Length(ABundle.Callers)), ABundle.CallerCap]);

  { THE CONTENT, NOT ONLY ITS COUNTS (Gitea #32, 2026-10-15). The MCP tool
    get_context_bundle -- whose description promises the doc, the class
    surface, the implementation slice and the callers -- and `context --format
    json` returned the counts above and nothing to read. The same content the
    markdown form prints now follows them; every key above keeps its place and
    meaning, so a consumer of the summary is untouched. }
  var Extra: TJSONObject:= TJSONObject.Create;
  try
    if ABundle.HasDoc then
    begin
      var JDoc: TJSONObject:= TJSONObject.Create;
      JDoc.AddPair('summary', ABundle.Doc.Summary);
      if ABundle.Doc.Remarks     <> '' then JDoc.AddPair('remarks', ABundle.Doc.Remarks);
      if ABundle.Doc.ReturnsText <> '' then JDoc.AddPair('returns', ABundle.Doc.ReturnsText);
      JDoc.AddPair('raw', ABundle.Doc.RawBlock);
      Extra.AddPair('doc', JDoc);
    end;
    var JSurface: TJSONArray:= TJSONArray.Create;
    for var SL: TSurfaceLine in ABundle.ClassSurface do
      JSurface.AddElement(TJSONObject.Create.AddPair('kind', SL.Kind)
        .AddPair('line', TJSONNumber.Create(SL.StartLine)).AddPair('text', SL.Text));
    Extra.AddPair('surface', JSurface);
    var JSlice: TJSONArray:= TJSONArray.Create;
    for var SC: TSliceChunk in ABundle.ImplSlice do
      JSlice.AddElement(TJSONObject.Create.AddPair('kind', SC.Kind)
        .AddPair('start_line', TJSONNumber.Create(SC.StartLine))
        .AddPair('end_line', TJSONNumber.Create(SC.EndLine)).AddPair('text', SC.Text));
    Extra.AddPair('slice', JSlice);
    var JCallers: TJSONArray:= TJSONArray.Create;
    for var BC: TBundleCaller in ABundle.Callers do
      JCallers.AddElement(TJSONObject.Create.AddPair('file', BC.FilePath)
        .AddPair('line', TJSONNumber.Create(BC.Line)).AddPair('col', TJSONNumber.Create(BC.Col))
        .AddPair('context', BC.ContextText));
    Extra.AddPair('callers', JCallers);
    var JImpact: TJSONArray:= TJSONArray.Create;
    for var IL: TImpactLevel in ABundle.ImpactSummary do
      JImpact.AddElement(TJSONObject.Create.AddPair('depth', TJSONNumber.Create(IL.Depth))
        .AddPair('callers', TJSONNumber.Create(IL.CallerCount)).AddPair('units', TJSONNumber.Create(IL.UnitCount)));
    Extra.AddPair('impact', JImpact);
    { CTX-TYPECAP: present only when the type body cap engaged. }
    if ABundle.BodyCap > 0 then
    begin
      Extra.AddPair('body_cap', TJSONNumber.Create(ABundle.BodyCap));
      Extra.AddPair('bodies_total', TJSONNumber.Create(ABundle.BodiesTotal));
      Extra.AddPair('bodies_omitted', TJSONNumber.Create(OmittedMethodCount(ABundle)));
      Extra.AddPair('body_tokens_total', TJSONNumber.Create(ABundle.BodyTokensTotal));
      Extra.AddPair('body_tokens_shown', TJSONNumber.Create(ABundle.BodyTokensShown));
      var JOmit: TJSONArray:= TJSONArray.Create;
      for I:= 0 to High(ABundle.OmittedBodies) do
        JOmit.AddElement(TJSONObject.Create.AddPair('kind', ABundle.OmittedBodies[I].Kind)
          .AddPair('signature', ABundle.OmittedBodies[I].Text)
          .AddPair('start_line', TJSONNumber.Create(ABundle.OmittedBodies[I].StartLine))
          .AddPair('end_line', TJSONNumber.Create(ABundle.OmittedBodies[I].EndLine))
          .AddPair('tokens', TJSONNumber.Create(ABundle.OmittedTokens[I])));
      Extra.AddPair('omitted_bodies', JOmit);
    end;
    var Tail: string:= Extra.ToJSON;  // an object: its keys are spliced in after the summary keys
    Result:= Copy(Result, 1, Length(Result) - 1) + ',' + Copy(Tail, 2, MaxInt);
  finally
    Extra.Free;
  end;
end; // function

end.
