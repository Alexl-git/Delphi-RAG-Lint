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
  /// Used by: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
  /// Used in units: DRagLint.CLI, DRagLint.MCP.Server
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
      /// <returns><!-- drag-lint:auto type -->TContextBundle</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
      /// Calls: Copy, DRagLint.Context.Bundler.StripDfmFields, DRagLint.Context.Bundler.TContextBundler.EstimateTokens, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.FindTransitiveCallers, DRagLint.Core.Interfaces.ISymbolStore.GetClassSurface, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolSlice, FillChar, LastDelimiter, SameText
      /// Complexity: 17 (cyclomatic, outer body), 99 lines (full implementation)
      /// Pure
      /// <seealso cref="DRagLint.Context.Bundler.StripDfmFields"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindTransitiveCallers"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Build(
        const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
        AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True): TContextBundle;
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: Round(Length(AText) / 3.7).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)
      /// Pure
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderJson"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderMarkdown"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderRaw"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function EstimateTokens(const AText: string)          : Integer;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas)
      /// Calls: DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Format, FormatDateTime
      /// Complexity: 14 (cyclomatic, outer body), 90 lines (full implementation)
      /// Pure
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
      /// Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
      /// Calls: Format, IfThen
      /// Pure
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.EstimateTokens"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderMarkdown"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderRaw"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderJson(const ABundle: TContextBundle)    : string ;
      /// <param name="ABundle"><!-- drag-lint:auto type -->const TContextBundle</param>
      /// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoContext (DRagLint.CLI.pas)
      /// Pure
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

class function TContextBundler.Build(
  const AStore: ISymbolStore; const AVerb, AQName: string; ACallerContext, AMaxCallers: Integer; AIncludeDocs, AIncludeSurface,
  AIncludeImpl: Boolean; AExcludeDfmFields: Boolean = True): TContextBundle;
var
  Syms       : TArray<TSymbol>   ;
  Sym        : TSymbol           ;
  ParentQName: string            ;
  CallerName : string            ;
  RawCallers : TArray<TReference>;
  Total      : Integer           ;
  SB         : TStringBuilder    ;
  I          : Integer           ;
  L          : TSurfaceLine      ;
  C          : TSliceChunk       ;
  BC         : TBundleCaller     ;
  R          : TReference        ;
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
    See docs\INBOX-context-bundle-empty-for-bare-name.md. }
  if (Length(Syms) = 0) and (Pos('.', AQName) = 0) then
  begin
    var ByName: TArray<TSymbol>:= AStore.FindSymbolsByExactName(AQName);
    if Length(ByName) = 1 then
    begin
      Syms:= ByName;
      { Report the resolved QUALIFIED name, not the bare one the caller typed --
        the bundle header is the reader's evidence of WHICH symbol they got. }
      Result.QName:= ByName[0].QualifiedName;
    end;
  end;

  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];

  // Doc
  if AIncludeDocs then
  begin
    Result.Doc:= AStore.GetSymbolDoc(Sym.Id);
    Result.HasDoc:= Result.Doc.HasContent;
  end;

  // Class surface -- parent qname is everything before the last '.'
  ParentQName:= AQName;
  if AIncludeSurface then
  begin
    if LastDelimiter('.', ParentQName) > 0 then ParentQName:= Copy(ParentQName, 1, LastDelimiter('.', ParentQName) - 1);
    if ParentQName <> AQName then
    begin
      Result.ClassSurface:= AStore.GetClassSurface(ParentQName, False, False);
      // Strip the auto-generated DFM component fields unless the caller asked
      // for the full surface (e.g. when working on the form's components/DFM).
      if AExcludeDfmFields then Result.ClassSurface:= StripDfmFields(Result.ClassSurface);
    end;
  end;

  // Impl slice -- ONLY the target symbol's own body, never the whole parent
  // class.  Pulling the parent's slice dragged in every sibling method body, so
  // the bundle was ~the whole source file (bench-context ~1x, no savings).  The
  // class SURFACE (signatures, cheap) already supplies the surrounding shape;
  // the body the caller actually needs is the target's own.  (v0.41)
  if AIncludeImpl then Result.ImplSlice:= AStore.GetSymbolSlice(AQName);

  // Callers (truncated to AMaxCallers; resolve FilePath from store)
  CallerName:= AQName;
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
begin
  // Minimal hand-rolled JSON; schema mirrors the spec.
  Result:= Format(
    '{"task":"%s","verb":"%s","qname":"%s","token_estimate":%d,' + '"has_doc":%s,"caller_count":%d,"surface_lines":%d,"slice_chunks":%d}', [
      ABundle.Verb + ' ' + ABundle.QName, ABundle.Verb, ABundle.QName, ABundle.TokenEstimate, IfThen(ABundle.HasDoc, 'true', 'false'), Length(ABundle.Callers),
      Length(ABundle.ClassSurface), Length(ABundle.ImplSlice)]);
end; // function

end.
