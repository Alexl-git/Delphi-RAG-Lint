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
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.MCP.Server</para>
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
      /// <param name="AExcludeDfmFields"><!-- drag-lint:auto type -->Boolean = True</param>
      /// <param name="ATaskText">The caller's raw task phrase, if any. Matched
      /// against the aliases of every <c>dl:wiki</c> topic in this index; up to
      /// two matches ride along in WikiTopics. Empty (the default) skips the
      /// lookup entirely, so every existing caller is unaffected. Honoured only
      /// when AIncludeDocs is set -- <c>--no-docs</c> means no prose, and a
      /// concept body is prose.</param>
      /// <returns><!-- drag-lint:auto type -->TContextBundle</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Copy, DRagLint.Context.Bundler.OwnerIsClassKind, DRagLint.Context.Bundler.ResolveUniqueName, DRagLint.Context.Bundler.StripDfmFields, DRagLint.Context.Bundler.TContextBundler.Build.MatchWikiTopics, DRagLint.Context.Bundler.TContextBundler.EstimateTokens, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.FindTransitiveCallers, DRagLint.Core.Interfaces.ISymbolStore.GetClassSurface (+7 more)</para>
      /// <para>Complexity: 28 (cyclomatic, outer body), 279 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Context.Bundler.OwnerIsClassKind"/>
      /// <seealso cref="DRagLint.Context.Bundler.ResolveUniqueName"/>
      /// <seealso cref="DRagLint.Context.Bundler.StripDfmFields"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build.MatchWikiTopics"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Build(
        const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
        AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True; const ATaskText: string = ''): TContextBundle;
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: Round(Length(AText) / 3.7).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)</para>
      /// <para>Pure</para>
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
      /// <para>Calls: DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Format, FormatDateTime, IfThen</para>
      /// <para>Complexity: 20 (cyclomatic, outer body), 123 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderJson"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderRaw"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderMarkdown(const ABundle: TContextBundle): string ;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.JsonEscape, Format, IfThen</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderMarkdown"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderRaw"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderJson(const ABundle: TContextBundle)    : string ;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas)</para>
      /// <para>Pure</para>
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
  ;

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

class function TContextBundler.Build(
  const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
  AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True; const ATaskText: string = ''): TContextBundle;
var
  Syms       : TArray<TSymbol>   ;
  Sym        : TSymbol           ;
  EffQName   : string            ;  { the RESOLVED qname -- see its assignment }
  ParentQName: string            ;
  OwnerIsClass: Boolean          ;  { the lean DFM-field filter runs only for a CLASS owner }
  CallerName : string            ;
  RawCallers : TArray<TReference>;
  Total      : Integer           ;
  SB         : TStringBuilder    ;
  I          : Integer           ;
  L          : TSurfaceLine      ;
  C          : TSliceChunk       ;
  BC         : TBundleCaller     ;
  R          : TReference        ;

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
  Result.QName      := AQName;
  Result.GeneratedAt:= Now;

  Syms:= AStore.FindSymbolsByQualifiedName(AQName);

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
    Syms:= ResolveUniqueName(AStore, AQName);
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
  if EffQName = '' then EffQName:= AQName;  { defensive: never regress to empty }

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
    end;
  end;

  // Impl slice -- ONLY the target symbol's own body, never the whole parent
  // class.  Pulling the parent's slice dragged in every sibling method body, so
  // the bundle was ~the whole source file (bench-context ~1x, no savings).  The
  // class SURFACE (signatures, cheap) already supplies the surrounding shape;
  // the body the caller actually needs is the target's own.  (v0.41)
  if AIncludeImpl then Result.ImplSlice:= AStore.GetSymbolSlice(EffQName);

  // Callers (truncated to AMaxCallers; resolve FilePath from store)
  CallerName:= EffQName;
  if LastDelimiter('.', CallerName) > 0 then CallerName:= Copy(CallerName, LastDelimiter('.', CallerName) + 1, MaxInt);
  RawCallers:= AStore.FindCallersByNameWithContext(CallerName, ACallerContext);
  if Length(RawCallers) > AMaxCallers then SetLength(RawCallers, AMaxCallers);
  SetLength(Result.Callers, Length(RawCallers));
  for I:= 0 to High(RawCallers) do
  begin
    R:= RawCallers[I];
    BC.FilePath:= AStore.GetFilePath(R.FileId);
    BC.Line       := R.StartLine;
    BC.Col        := R.StartCol;
    BC.ContextText:= R.ContextText;
    Result.Callers[I]:= BC;
  end;

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
    SB.AppendLine(Format('> Generated by drag-lint v0.18 at %s', [FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', ABundle.GeneratedAt)]));
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

    if Length(ABundle.Callers) > 0 then
    begin
      SB.AppendLine(Format('## Callers (%d)', [Length(ABundle.Callers)]));
      for I:= 0 to High(ABundle.Callers) do
      begin
        BC:= ABundle.Callers[I];
        SB.AppendLine(Format('- %s:%d:%d', [BC.FilePath, BC.Line, BC.Col]));
        if BC.ContextText <> '' then
        begin
          SB.AppendLine('  ```');
          SB.AppendLine(BC.ContextText);
          SB.AppendLine('  ```');
        end;
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
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

class function TContextBundler.RenderJson(const ABundle: TContextBundle): string;
var
  Wiki: string    ;
  I   : Integer   ;
  W   : TWikiTopic;
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

  Result:= Format(
    '{"task":"%s","verb":"%s","qname":"%s","resolved":%s,"token_estimate":%d,' +
    '"has_doc":%s,"caller_count":%d,"surface_lines":%d,"slice_chunks":%d,"wiki":[%s]}', [
      JsonEscape(ABundle.Verb + ' ' + ABundle.QName), JsonEscape(ABundle.Verb), JsonEscape(ABundle.QName),
      IfThen(ABundle.Resolved, 'true', 'false'),
      ABundle.TokenEstimate, IfThen(ABundle.HasDoc, 'true', 'false'), Length(ABundle.Callers),
      Length(ABundle.ClassSurface), Length(ABundle.ImplSlice), Wiki]);
end; // function

end.
