unit DRagLint.Hover.Renderer;

// v0.16: shared hover rendering helpers used by both the CLI (drag-lint hover)
// and the LSP server (textDocument/hover). Factored out of DRagLint.CLI so
// the LSP server does not depend on the CLI unit.
//
// All three functions accept a TSymbol (for the qualified name / kind) and a
// TParsedDoc (for the extracted documentation fields). Callers that only have
// a qualified name string can populate a minimal TSymbol with QualifiedName
// set and leave the rest zero/empty.

interface

uses
  DRagLint.Core.Model
  ;

/// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
/// <param name="ADoc"><!-- drag-lint:auto type -->const TParsedDoc</param>
/// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Trim
/// Pure
/// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderHoverPlain(const ASym: TSymbol; const ADoc: TParsedDoc): string;

/// <summary>Renders a symbol's hover popup as markdown: qualified-name
/// heading, deprecated/since badges, summary, parameters (from doc-comment
/// tags, else an IDE-style block derived from the signature), returns text,
/// mined Result:=/Exit() return cases, remarks, example, and -- v(ADP2 T9)
/// -- the Phase-2 analysis facts under an 'Analysis facts' section when
/// AFactLines is non-empty.</summary>
/// <param name="ASym">The symbol being hovered over.</param>
/// <param name="ADoc">The symbol's parsed doc-comment (may be empty).</param>
/// <param name="AReturnRhs">Mined `Result:=`/`Exit()` return expressions;
/// shown even when ADoc already has a hand-written &lt;returns&gt;.</param>
/// <param name="AFactLines">v(ADP2 T9): the Phase-2 fact lines (Complexity /
/// Reads-Writes / Owns returned / Handles / SQL / Covered by), pre-formatted
/// by DRagLint.Doc.Regions.TDocRegions.FormatPhase2FactLines -- the SAME
/// helper the managed doc block's RenderFactsBlock calls, so hover and
/// `document` can never show different facts for the same symbol (the
/// doc/hover consistency lock). Nil/empty (the default) renders no facts
/// section at all -- this renderer never computes facts itself, it only
/// lays out lines the caller already built (mirrors the AReturnRhs
/// caller-computes pattern; keeps this unit decoupled from
/// DRagLint.Doc.Facts/DRagLint.Storage, which DoHover/HandleHover already
/// have open).</param>
/// <returns><!-- drag-lint:auto -->Observed: SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: DRagLint.Doc.Regions.TDocRegions.StripForDisplay, DRagLint.Hover.Renderer.HasAnyParamDescription, DRagLint.Hover.Renderer.RenderSignatureParamsMarkdown
/// Complexity: 13 (cyclomatic, outer body), 107 lines (full implementation)
/// Pure
/// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
/// <seealso cref="DRagLint.Hover.Renderer.HasAnyParamDescription"/>
/// <seealso cref="DRagLint.Hover.Renderer.RenderSignatureParamsMarkdown"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc; const AReturnRhs: TArray<string> = nil; const AFactLines: TArray<string> = nil): string;

/// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
/// <param name="ADoc"><!-- drag-lint:auto type -->const TParsedDoc</param>
/// <returns><!-- drag-lint:auto type -->string</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: DRagLint.Core.Model.DocFormatToStr, DRagLint.Core.Model.JsonEscape, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, IfThen
/// Overload 1 of 2
/// Pure
/// <seealso cref="DRagLint.Core.Model.DocFormatToStr"/>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string; overload;

// v0.43: turn a proc-like signature -- e.g. '(AOwner: TComponent;
// AFldrSystID: Int64): Boolean' -- into an IDE-style markdown block listing
// each parameter name + type on its own line, plus the return type. Returns ''
// when the signature has no parameter list (containers, fields, properties).
/// <param name="ASignature"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: ''; SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Hover.Renderer.RenderHoverMarkdown (DRagLint.Hover.Renderer.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas) ?
/// Calls: Copy, DRagLint.Hover.Renderer.LastTopLevelColon, DRagLint.Hover.Renderer.SplitTopLevel, Format, Pos, StartsText, Trim
/// Complexity: 16 (cyclomatic, outer body), 82 lines (full implementation)
/// Pure
/// <seealso cref="DRagLint.Hover.Renderer.LastTopLevelColon"/>
/// <seealso cref="DRagLint.Hover.Renderer.SplitTopLevel"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderSignatureParamsMarkdown(const ASignature: string): string;

  /// <summary>One parsed parameter from a routine signature: the leading
  /// const/var/out modifier (if any), the parameter name, and its type text.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Hover.Renderer.ParseSignatureParams (DRagLint.Hover.Renderer.pas)
  /// Used in units: DRagLint.Hover.Renderer
  /// <!-- drag-lint:auto END -->
  /// </remarks>
type
  TParamPart = record
    Modifier: string;
    Name    : string;
    TypeText: string;
  end;

  /// <summary>One mined `Result:= &lt;Expr>` / `Exit(&lt;Expr>)` return expression,
  /// as produced by the Task 2 returns-miner.</summary>
type
  TReturnFact = record
    Expr: string ;
    Line: Integer;   // absolute 1-based source line the RHS was mined from; 0 if unknown
  end;

  /// <summary>Structured hover model: the parsed pieces of a symbol's
  /// signature, doc-comment, and mined return facts, ready for a renderer to
  /// lay out / color without re-parsing a flat string.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoHover (DRagLint.CLI.pas), declaration (DRagLint.Hover.Renderer.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Hover.Renderer
  /// <!-- drag-lint:auto END -->
  /// </remarks>
type
  THoverModel = record
    QualifiedName: string             ;
    Kind         : string             ;
    Signature    : string             ;
    UnitFile     : string             ;
    DefLine      : Integer            ;
    Params       : TArray<TParamPart> ;
    ReturnType   : string             ;
    Returns      : TArray<TReturnFact>;
    ReturnsMore  : Integer            ;
    Doc          : TParsedDoc         ;
  end;

/// <summary>Parses a routine signature's parameter list -- e.g.
/// '(AOwner: TComponent; const AName: string): Boolean' -- into one
/// TParamPart per parameter name (multi-name segments like 'A, B: Integer'
/// expand to one part each). Returns an empty array when the signature has
/// no parameter list.</summary>
/// <param name="ASignature">The routine's raw signature text.</param>
/// <returns>One TParamPart per parameter name, in declaration order.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Hover.Renderer.BuildHoverModel (DRagLint.Hover.Renderer.pas)
/// Calls: Copy, DRagLint.Hover.Renderer.LastTopLevelColon, DRagLint.Hover.Renderer.SplitTopLevel, Pos, StartsText, Trim
/// Returns: Parts.ToArray
/// Complexity: 11 (cyclomatic, outer body), 47 lines (full implementation)
/// Pure
/// <seealso cref="DRagLint.Hover.Renderer.LastTopLevelColon"/>
/// <seealso cref="DRagLint.Hover.Renderer.SplitTopLevel"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseSignatureParams(const ASignature: string): TArray<TParamPart>;

/// <summary>Assembles a THoverModel from an indexed symbol, its parsed
/// doc-comment, the resolved unit file path, and mined return-expression
/// text. Caps Returns at 10 entries, recording the overflow count in
/// ReturnsMore.</summary>
/// <param name="ASym">The symbol being hovered over.</param>
/// <param name="ADoc">The symbol's parsed doc-comment (may be empty).</param>
/// <param name="AUnitFile">Resolved path of the unit declaring ASym.</param>
/// <param name="AReturnRhs">Mined `Result:=`/`Exit()` return expressions.</param>
/// <param name="AReturnLines">Parallel to AReturnRhs: the absolute 1-based source
/// line each RHS was mined from (for click-to-navigate). Pass nil/[] for none;
/// entries default to 0 (unknown) when shorter than AReturnRhs.</param>
/// <returns>A populated THoverModel.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoHover (DRagLint.CLI.pas)
/// Calls: DRagLint.Hover.Renderer.KindQualifier, DRagLint.Hover.Renderer.ParseSignatureParams, DRagLint.Hover.Renderer.ReturnTypeFromSig
/// Pure
/// <seealso cref="DRagLint.Hover.Renderer.KindQualifier"/>
/// <seealso cref="DRagLint.Hover.Renderer.ParseSignatureParams"/>
/// <seealso cref="DRagLint.Hover.Renderer.ReturnTypeFromSig"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildHoverModel(const ASym: TSymbol; const ADoc: TParsedDoc; const AUnitFile: string; const AReturnRhs: TArray<string>; const AReturnLines: TArray<Integer> = nil): THoverModel;

/// <summary>Serializes a structured THoverModel to the hover JSON shape:
/// qname/unit/def_line/return_type/params (modifier/name/type each)/returns
/// (mined RHS expressions)/returns_more (overflow count beyond the 10-entry
/// cap)/summary. Used by `drag-lint hover --format json`.</summary>
/// <param name="AModel">The hover model built by BuildHoverModel.</param>
/// <param name="AFactLines">v(hover facts fix): the Phase-2 analysis fact lines
/// (as FormatPhase2FactLines produced them) emitted as a `"facts":[...]` array
/// so the structured IDE popup can render them; pass nil/[] for none.</param>
/// <returns>A single-line JSON object string.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: DRagLint.Core.Model.JsonEscape, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, Format, IntToStr
/// Returns: SB.ToString
/// Overload 2 of 2
/// Pure
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderHoverJson(const AModel: THoverModel; const AFactLines: TArray<string>): string; overload;

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , System.StrUtils
  , System.Generics.Collections
  , DRagLint.Doc.Regions
  ;

// v(ADP3 T1) review fix: StripForDisplay is now DRagLint.Doc.Regions'
// TDocRegions.StripForDisplay -- a single exported presentation-layer
// stripper shared by every consumer (hover here, the context bundle, MCP's
// doc JSON, LSP completion/signature-help, TypeAt's plain render), so the
// marker-hiding behaviour cannot drift between them. See its own comment in
// DRagLint.Doc.Regions.pas for the full contract; every call site in this
// unit below just qualifies it as TDocRegions.StripForDisplay.

{ ---- v0.43 signature -> Parameters block helpers ---- }

// Split S on Sep, but only at top nesting level (ignores separators inside
// (), [], <> so generics like TDictionary<Integer, string> stay intact).
function SplitTopLevel(const S: string; Sep: Char): TArray<string>;
var
  Parts: TList<string>;
  i    : Integer      ;
  Depth: Integer      ;
  Start: Integer      ;
begin
  Parts:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for i:= 1 to Length(S) do
    begin
      case S[i] of
        '(', '[', '<': Inc(Depth)                  ;
        ')', ']', '>': if Depth > 0 then Dec(Depth);
      end;
      if (S[i] = Sep) and (Depth = 0) then
      begin
        Parts.Add(Copy(S, Start, i - Start));
        Start:= i + 1;
      end;
    end;
    Parts.Add(Copy(S, Start, Length(S) - Start + 1));
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end; // try
end; // function

// Index of the last top-level ':' in S (the name/type separator), or 0.
function LastTopLevelColon(const S: string): Integer;
var
  i    : Integer;
  Depth: Integer;
begin
  Result:= 0;
  Depth := 0;
  for i:= 1 to Length(S) do
  case S[i] of
    '(', '[', '<': Inc(Depth)                  ;
    ')', ']', '>': if Depth > 0 then Dec(Depth);
    ':'          : if Depth = 0 then Result:= i;
  end;
end;

function ParseSignatureParams(const ASignature: string): TArray<TParamPart>;
var
  Sig, ParamsPart: string;
  OpenParen, CloseParen, Depth, i, ColonPos: Integer;
  Seg, Names, Typ, ModWord, MW, Nm: string;
  Parts: TList<TParamPart>;
  PP: TParamPart;
begin
  Parts:= TList<TParamPart>.Create;
  try
    Sig:= Trim(ASignature);
    OpenParen:= Pos('(', Sig);
    if OpenParen > 0 then
    begin
      Depth:= 0; CloseParen:= 0;
      for i:= OpenParen to Length(Sig) do
      begin
        if Sig[i] = '(' then Inc(Depth)
        else if Sig[i] = ')' then begin Dec(Depth); if Depth = 0 then begin CloseParen:= i; Break; end; end;
      end;
      if CloseParen > 0 then
      begin
        ParamsPart:= Trim(Copy(Sig, OpenParen + 1, CloseParen - OpenParen - 1));
        for Seg in SplitTopLevel(ParamsPart, ';') do
        begin
          if Trim(Seg) = '' then Continue;
          ColonPos:= LastTopLevelColon(Seg);
          if ColonPos > 0 then
          begin Names:= Trim(Copy(Seg, 1, ColonPos - 1)); Typ:= Trim(Copy(Seg, ColonPos + 1, MaxInt)); end
          else begin Names:= Trim(Seg); Typ:= ''; end;
          ModWord:= '';
          for MW in ['const ', 'var ', 'out '] do
            if StartsText(MW, Names) then
            begin ModWord:= Trim(MW); Names:= Trim(Copy(Names, Length(MW) + 1, MaxInt)); Break; end;
          for Nm in SplitTopLevel(Names, ',') do
            if Trim(Nm) <> '' then
            begin
              PP.Modifier:= ModWord; PP.Name:= Trim(Nm); PP.TypeText:= Typ;
              Parts.Add(PP);
            end;
        end;
      end;
    end;
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

// v(PHASE A3): True when AParamsJsonRaw carries at least one <param> whose
// description has real text once the ownership marker is stripped.
//
// Ruling D-3 made a <param> tag STRUCTURAL -- emitted for every signature
// parameter so that doc-drift can be satisfied and a human has a slot to type
// into. Rendering must therefore stop treating "a tag exists" as "this
// parameter is documented", or every tooltip loses the signature-derived
// name+type block the moment `document --apply` runs over a unit.
function HasAnyParamDescription(const AParamsJsonRaw: string): Boolean;
var
  M: TMatch;
begin
  Result:= False;
  if AParamsJsonRaw = '' then Exit;
  for M in TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"').Matches(AParamsJsonRaw) do
    if Trim(TDocRegions.StripForDisplay(M.Groups[2].Value)) <> '' then Exit(True);
end;

function RenderSignatureParamsMarkdown(const ASignature: string): string;
var
  Sig       : string        ;
  ParamsPart: string        ;
  RetPart   : string        ;
  Names     : string        ;
  Typ       : string        ;
  ModWord   : string        ;
  OpenParen : Integer       ;
  CloseParen: Integer       ;
  ColonPos  : Integer       ;
  Depth     : Integer       ;
  i         : Integer       ;
  SB        : TStringBuilder;
  Seg       : string        ;
  Nm        : string        ;
  MW        : string        ;
begin
  Result:= '';
  Sig:= Trim(ASignature);
  OpenParen:= Pos('(', Sig);
  if OpenParen = 0 then Exit; // no parameter list -- nothing IDE-style to break out

  { find the paren that closes OpenParen }
  Depth     := 0;
  CloseParen:= 0;
  for i:= OpenParen to Length(Sig) do
  begin
    case Sig[i] of
      '(': Inc(Depth)                                                               ;
      ')': begin Dec(Depth); if Depth = 0 then begin CloseParen:= i; Break; end; end;
    end;
  end;
  if CloseParen = 0 then Exit;

  ParamsPart:= Trim(Copy(Sig, OpenParen + 1, CloseParen - OpenParen - 1));
  RetPart:= Trim(Copy(Sig, CloseParen + 1, MaxInt));
  if (RetPart <> '') and (RetPart[1] = ':') then RetPart:= Trim(Copy(RetPart, 2, MaxInt));

  SB:= TStringBuilder.Create;
  try
    if ParamsPart <> '' then
    begin
      SB.AppendLine('**Parameters:**');
      for Seg in SplitTopLevel(ParamsPart, ';') do
      begin
        if Trim(Seg) = '' then Continue;
        ColonPos:= LastTopLevelColon(Seg);
        if ColonPos > 0 then
        begin
          Names:= Trim(Copy(Seg, 1, ColonPos - 1));
          Typ:= Trim(Copy(Seg, ColonPos + 1, MaxInt));
        end
        else
        begin
          Names:= Trim(Seg);
          Typ:= '';
        end;
        { peel a leading const/var/out modifier off the names }
        ModWord:= '';
        for MW in ['const ', 'var ', 'out '] do
          if StartsText(MW, Names) then
          begin
            ModWord:= Trim(MW) + ' ';
            Names:= Trim(Copy(Names, Length(MW) + 1, MaxInt));
            Break;
          end;
        for Nm in SplitTopLevel(Names, ',') do
          if Trim(Nm) <> '' then
            if Typ <> '' then SB.AppendLine(Format('- `%s` : %s%s', [Trim(Nm), ModWord, Typ]))
          else SB.AppendLine(Format('- `%s`', [Trim(Nm)]));
      end; // for
    end; // if
    if RetPart <> '' then
    begin
      if ParamsPart <> '' then SB.AppendLine('');
      SB.AppendLine('**Returns:** ' + RetPart);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

// 2026-08-17: param/exception descriptions are stored JSON-ESCAPED (ParamsToJson
// and ExceptionsToJson both run the text through JsonEscape), but both renderers
// pulled the value straight out with a regex and never reversed that. A
// multi-line <param> therefore reached the hover card as a LITERAL backslash-n
// rather than a line break -- visible in every tooltip carrying a wrapped
// description. Reverses only what JsonEscape produces; \uXXXX is not emitted by
// it, so it is deliberately not handled here rather than half-handled.
function UnescapeJsonText(const AText: string): string;
begin
  Result:= AText;
  if Result = '' then Exit;
  if Pos('\', Result) = 0 then Exit;          // fast path: nothing escaped
  Result:= StringReplace(Result, '\r\n', sLineBreak, [rfReplaceAll]);
  Result:= StringReplace(Result, '\n'   , sLineBreak, [rfReplaceAll]);
  Result:= StringReplace(Result, '\r'   , sLineBreak, [rfReplaceAll]);
  Result:= StringReplace(Result, '\t'   , #9        , [rfReplaceAll]);
  Result:= StringReplace(Result, '\"'   , '"'       , [rfReplaceAll]);
  Result:= StringReplace(Result, '\/'   , '/'       , [rfReplaceAll]);
  // Backslash LAST: doing it earlier would let an escaped backslash swallow the
  // sequence that follows it.
  Result:= StringReplace(Result, '\\'   , '\'       , [rfReplaceAll]);
end;

function RenderHoverPlain(const ASym: TSymbol; const ADoc: TParsedDoc): string;
var
  SB: TStringBuilder;
  Re: TRegEx        ;
  M : TMatch        ;
begin
  SB:= TStringBuilder.Create;
  try
    SB.AppendLine(ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('[DEPRECATED]');
    if ADoc.SinceText <> '' then SB.AppendLine('Since: '   + ADoc.SinceText);
    // v(ADP3 T1): strip the ownership marker before a human sees it -- see
    // StripForDisplay's own comment; the read path (ADoc.Summary itself)
    // must keep carrying it.
    var CleanSummary: string:= TDocRegions.StripForDisplay(ADoc.Summary);
    if CleanSummary <> '' then SB.AppendLine('Summary: ' + CleanSummary);
    if ADoc.ParamsJsonRaw <> '' then
    begin
      Re:= TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do
        // v(ADP3 T1): a managed <param> desc is just AUTO_MARK -- strip it so
        // the row reads "Name -- " rather than leaking the marker.
        // v(PHASE A3): ... and a row with NOTHING after the dash is skipped
        // outright. Since ruling D-3 the engine emits a <param> tag for every
        // signature parameter, body or no body -- that tag exists so doc-drift
        // can be satisfied and so a human has a slot to type into, not to put
        // `AValue -- ` in a tooltip. An empty description is not a description.
        if Trim(TDocRegions.StripForDisplay(M.Groups[2].Value)) <> '' then
          SB.AppendLine('  ' + M.Groups[1].Value + ' -- ' + UnescapeJsonText(TDocRegions.StripForDisplay(M.Groups[2].Value)));
    end;
    // v(ADP3 T1): strip the ownership marker before a human sees it.
    var CleanReturns: string:= TDocRegions.StripForDisplay(ADoc.ReturnsText);
    if CleanReturns <> '' then SB.AppendLine('Returns: ' + CleanReturns);
    // 2026-08-17: <exception cref> was parsed, stored and served, and then
    // DROPPED HERE -- this renderer had no exception branch at all, so no symbol
    // could ever show what it raises. "What does this raise?" is one of the
    // questions a hover card most obviously ought to answer, and the project's
    // own DocInsight standard mandates <exception cref> on the public surface.
    // Shape is whatever ExceptionsToJson emits: a JSON array of objects each
    // carrying a "type" and a "desc" key. (Written as line comments on purpose:
    // a brace comment holding that literal JSON ends early at its own closing
    // brace, which silently turns the rest into code -- it did exactly that here.)
    // Placeholder-only descriptions are skipped for the same reason params are:
    // the engine emits an auto <exception cref="Exception"> stub so doc-drift can
    // be satisfied, and a stub is not a description.
    if ADoc.ExceptionsJsonRaw <> '' then
    begin
      Re:= TRegEx.Create('"type":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ExceptionsJsonRaw) do
      begin
        var ExcDesc: string:= Trim(UnescapeJsonText(TDocRegions.StripForDisplay(M.Groups[2].Value)));
        if ExcDesc <> '' then SB.AppendLine('Raises ' + M.Groups[1].Value + ': ' + ExcDesc)
        else SB.AppendLine('Raises ' + M.Groups[1].Value);
      end;
    end;
    // v(ADP3 T1) review fix (finding 1b): a Remarks facts block still carries
    // the raw AUTO_BEGIN/AUTO_END fence around its facts lines -- strip just
    // the fence markers, keep the facts text between them.
    var CleanRemarks: string:= TDocRegions.StripForDisplay(ADoc.Remarks);
    if CleanRemarks <> '' then SB.AppendLine('Remarks: ' + CleanRemarks);
    if ADoc.ExampleText <> '' then
    begin
      SB.AppendLine('Example:');
      SB.AppendLine(ADoc.ExampleText);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc; const AReturnRhs: TArray<string> = nil; const AFactLines: TArray<string> = nil): string;
var
  SB: TStringBuilder;
  Re: TRegEx        ;
  M : TMatch        ;
begin
  SB:= TStringBuilder.Create;
  try
    SB.AppendLine('# ' + ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('> **DEPRECATED**');
    if ADoc.SinceText <> '' then SB.AppendLine('> _Since: ' + ADoc.SinceText + '_');
    // v(ADP3 T1): strip the ownership marker before a human sees it -- see
    // StripForDisplay's own comment; the read path (ADoc.Summary itself)
    // must keep carrying it.
    var CleanSummary: string:= TDocRegions.StripForDisplay(ADoc.Summary);
    if CleanSummary <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine(CleanSummary);
    end;
    // v(PHASE A3): "has <param> tags" is no longer the same question as "has
    // param DOCUMENTATION". Since ruling D-3 every signature parameter gets a
    // tag whether or not the source says anything about it, so keying the
    // fallback off tag PRESENCE would have replaced the informative
    // signature-derived block (name AND type) with a list of bare names. The
    // fallback now keys off whether any tag actually carries text.
    if HasAnyParamDescription(ADoc.ParamsJsonRaw) then
    begin
      SB.AppendLine(''               );
      SB.AppendLine('**Parameters:**');
      Re:= TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do
        // v(ADP3 T1): a managed <param> desc is just AUTO_MARK -- strip it.
        SB.AppendLine('- `' + M.Groups[1].Value + '` ' + UnescapeJsonText(TDocRegions.StripForDisplay(M.Groups[2].Value)));
    end
    else
    begin
      { v0.43: no XMLDoc @param tags -- fall back to the IDE-style block
        derived from the signature itself (name + type per parameter). }
      var SigBlock: string:= RenderSignatureParamsMarkdown(ASym.Signature);
      if SigBlock <> '' then
      begin
        SB.AppendLine(''      );
        SB.Append    (SigBlock);
      end;
    end;
    // v(ADP3 T1): strip the ownership marker before a human sees it.
    var CleanReturns: string:= TDocRegions.StripForDisplay(ADoc.ReturnsText);
    if CleanReturns <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('**Returns:** ' + CleanReturns);
    end;
    // 2026-08-17: mirrors the plain renderer's new Raises section -- see the
    // comment there. Both paths dropped <exception cref> entirely before this.
    if ADoc.ExceptionsJsonRaw <> '' then
    begin
      Re:= TRegEx.Create('"type":"([^"]+)","desc":"([^"]*)"');
      var WroteExcHdr: Boolean:= False;
      for M in Re.Matches(ADoc.ExceptionsJsonRaw) do
      begin
        var ExcDesc: string:= Trim(UnescapeJsonText(TDocRegions.StripForDisplay(M.Groups[2].Value)));
        if not WroteExcHdr then
        begin
          SB.AppendLine('');
          SB.AppendLine('**Raises:**');
          WroteExcHdr:= True;
        end;
        if ExcDesc <> '' then SB.AppendLine('- `' + M.Groups[1].Value + '` -- ' + ExcDesc)
        else SB.AppendLine('- `' + M.Groups[1].Value + '`');
      end;
    end;
    // Live-mined Result:=/Exit() return cases, shown even when the doc has a
    // hand-written <returns> (unifies the popup with the managed doc's
    // 'Returns:' fact line). Empty for procedures / when nothing was mined.
    if Length(AReturnRhs) > 0 then
    begin
      var RObs: string:= '';
      for var ri:= 0 to High(AReturnRhs) do
      begin
        if ri > 0 then RObs:= RObs + '; ';
        RObs:= RObs + AReturnRhs[ri];
      end;
      SB.AppendLine('');
      SB.AppendLine('**Returns (observed):** ' + RObs);
    end;
    // v(ADP2 T9): Phase-2 analysis facts (Complexity / Reads-Writes fields /
    // Owns returned / Handles / SQL tables touched / Covered by), already
    // formatted by the SAME DRagLint.Doc.Regions.TDocRegions.
    // FormatPhase2FactLines helper the managed doc block's RenderFactsBlock
    // calls -- see this function's own AFactLines param comment for the
    // doc/hover consistency-lock rationale. This renderer does not compute
    // or reorder anything: AFactLines is emitted verbatim, one bullet per
    // line, in whatever order the caller supplied (FormatPhase2FactLines'
    // own fixed Complexity/Reads-Writes/Owns-returned/Handles/SQL/Covered-by
    // order). Omitted entirely -- no empty '**Analysis facts:**' heading --
    // when AFactLines is nil/empty (the default; e.g. a caller with no
    // store open, or a symbol with none of the six facts).
    if Length(AFactLines) > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('**Analysis facts:**');
      for var FactLine in AFactLines do
        SB.AppendLine('- ' + FactLine);
    end;
    // v(ADP3 T1) review fix (finding 1b): strip just the AUTO_BEGIN/AUTO_END
    // fence markers, keep the facts lines between them.
    var CleanMdRemarks: string:= TDocRegions.StripForDisplay(ADoc.Remarks);
    if CleanMdRemarks <> '' then
    begin
      SB.AppendLine(''          );
      SB.AppendLine('## Remarks');
      SB.AppendLine(CleanMdRemarks);
    end;
    if ADoc.ExampleText <> '' then
    begin
      SB.AppendLine(''          );
      SB.AppendLine('## Example');
      SB.AppendLine('```pascal' );
      SB.AppendLine(ADoc.ExampleText);
      SB.AppendLine('```');
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  // v(ADP3 T1): strip the ownership marker before it reaches a human --
  // see StripForDisplay's own comment; ADoc.Summary/ReturnsText themselves
  // must keep carrying it for the read path (MergeComment/drift).
  Result:= System.SysUtils.Format(
    '{"qname":"%s","format":"%s","summary":"%s","returns":"%s",' + '"since":"%s","deprecated":%s}', [
      JsonEscape(ASym.QualifiedName), DocFormatToStr(ADoc.Format), JsonEscape(TDocRegions.StripForDisplay(ADoc.Summary)), JsonEscape(TDocRegions.StripForDisplay(ADoc.ReturnsText)), JsonEscape(ADoc.SinceText),
      IfThen(ADoc.Deprecated, 'true', 'false')]);
end;

function RenderHoverJson(const AModel: THoverModel; const AFactLines: TArray<string>): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB:= TStringBuilder.Create;
  try
    SB.Append('{');
    SB.Append(Format('"qname":"%s",', [JsonEscape(AModel.QualifiedName)]));
    SB.Append(Format('"kind":"%s",', [JsonEscape(AModel.Kind)]));   // v(FB #3): friendly qualifier for the header
    SB.Append(Format('"signature":"%s",', [JsonEscape(AModel.Signature)]));   // raw sig -- for enum values this carries the ordinal (= N)
    SB.Append(Format('"unit":"%s","def_line":%d,', [JsonEscape(AModel.UnitFile), AModel.DefLine]));
    SB.Append(Format('"return_type":"%s",', [JsonEscape(AModel.ReturnType)]));
    SB.Append('"params":[');
    for i:= 0 to High(AModel.Params) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(Format('{"modifier":"%s","name":"%s","type":"%s"}',
        [JsonEscape(AModel.Params[i].Modifier), JsonEscape(AModel.Params[i].Name), JsonEscape(AModel.Params[i].TypeText)]));
    end;
    SB.Append('],"returns":[');
    for i:= 0 to High(AModel.Returns) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(Format('"%s"', [JsonEscape(AModel.Returns[i].Expr)]));
    end;
    { v(FB3): a PARALLEL array of the absolute 1-based source line each return RHS
      was mined from (0 = unknown). The plugin zips it with "returns" to make each
      return value clickable and jump to that line. Kept parallel (not nested in
      "returns") so existing string-array consumers of "returns" are unaffected. }
    SB.Append('],"returns_lines":[');
    for i:= 0 to High(AModel.Returns) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(IntToStr(AModel.Returns[i].Line));
    end;
    SB.Append(Format('],"returns_more":%d,', [AModel.ReturnsMore]));
    { v(hover facts fix): the Phase-2 analysis fact lines (Complexity / Reads /
      Writes / SQL / Handles / Owns returned / Covered by), one string each,
      exactly as FormatPhase2FactLines produced them. The structured IDE popup
      reads this array and renders a FACTS section -- previously the JSON omitted
      facts entirely, so the plugin's colored popup never showed them (only the
      `--format md` path did). Empty array when the symbol has no facts. }
    SB.Append('"facts":[');
    for i:= 0 to High(AFactLines) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(Format('"%s"', [JsonEscape(AFactLines[i])]));
    end;
    SB.Append('],');
    // v(ADP3 T1): strip the ownership marker before it reaches a human --
    // see StripForDisplay's own comment; AModel.Doc.Summary itself must keep
    // carrying it for the read path (MergeComment/drift). This is the JSON
    // shape `drag-lint hover --format json` actually renders (DoHover calls
    // this THoverModel overload, not the plain-TParsedDoc one above).
    SB.Append(Format('"summary":"%s"}', [JsonEscape(TDocRegions.StripForDisplay(AModel.Doc.Summary))]));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

// Parses the trailing '): <Type>;' from a routine signature. Inlined here
// rather than reusing DRagLint.Doc.Facts.ParseReturnType, which is private
// to that unit.
function ReturnTypeFromSig(const ASig: string): string;
var
  CloseParen, ColonP, SemiP: Integer;
  Tail: string;
begin
  Result:= '';
  CloseParen:= LastDelimiter(')', ASig);
  if CloseParen = 0 then Exit;
  Tail:= Copy(ASig, CloseParen + 1, MaxInt);
  ColonP:= Pos(':', Tail);
  if ColonP = 0 then Exit;
  Tail:= Trim(Copy(Tail, ColonP + 1, MaxInt));
  SemiP:= Pos(';', Tail);
  if SemiP > 0 then Tail:= Copy(Tail, 1, SemiP - 1);
  Result:= Trim(Tail);
end;

function KindQualifier(AKind: TSymbolKind): string;
{ A human-friendly qualifier shown before the symbol name in the hover header
  (e.g. "function", "local var", "parameter", "property"). '' for kinds that read
  fine without one. }
begin
  case AKind of
    skUnit        : Result:= 'unit'        ;
    skProgram     : Result:= 'program'     ;
    skPackage     : Result:= 'package'     ;
    skClass       : Result:= 'class'       ;
    skInterface   : Result:= 'interface'   ;
    skRecord      : Result:= 'record'      ;
    skEnum        : Result:= 'enum'        ;
    skEnumValue   : Result:= 'enum value'  ;
    skProcedure   : Result:= 'procedure'   ;
    skFunction    : Result:= 'function'    ;
    skMethod      : Result:= 'method'      ;
    skConstructor : Result:= 'constructor' ;
    skDestructor  : Result:= 'destructor'  ;
    skProperty    : Result:= 'property'    ;
    skField       : Result:= 'field'       ;
    skVarDecl     : Result:= 'var'         ;
    skConstDecl   : Result:= 'const'       ;
    skTypeAlias   : Result:= 'type'        ;
    skLocalVar    : Result:= 'local var'   ;
    skParam       : Result:= 'parameter'   ;
    else            Result:= ''            ;
  end;
end;

function BuildHoverModel(const ASym: TSymbol; const ADoc: TParsedDoc;
  const AUnitFile: string; const AReturnRhs: TArray<string>; const AReturnLines: TArray<Integer> = nil): THoverModel;
var
  i: Integer;
  Cap: Integer;
begin
  Result.QualifiedName:= ASym.QualifiedName;
  Result.Signature    := ASym.Signature;
  Result.UnitFile     := AUnitFile;
  Result.DefLine      := ASym.StartLine;
  Result.Params       := ParseSignatureParams(ASym.Signature);
  Result.ReturnType   := ReturnTypeFromSig(ASym.Signature);
  Result.Doc          := ADoc;
  Result.Kind         := KindQualifier(ASym.Kind); // v(FB #3): friendly qualifier for the header
  Cap:= Length(AReturnRhs);
  if Cap > 10 then begin Result.ReturnsMore:= Cap - 10; Cap:= 10; end
  else Result.ReturnsMore:= 0;
  SetLength(Result.Returns, Cap);
  for i:= 0 to Cap - 1 do
  begin
    Result.Returns[i].Expr:= AReturnRhs[i];
    if i <= High(AReturnLines) then Result.Returns[i].Line:= AReturnLines[i]
    else Result.Returns[i].Line:= 0;
  end;
end;

end.
