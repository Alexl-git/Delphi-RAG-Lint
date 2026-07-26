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
function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc; const AReturnRhs: TArray<string> = nil; const AFactLines: TArray<string> = nil): string;

function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string; overload;

// v0.43: turn a proc-like signature -- e.g. '(AOwner: TComponent;
// AFldrSystID: Int64): Boolean' -- into an IDE-style markdown block listing
// each parameter name + type on its own line, plus the return type. Returns ''
// when the signature has no parameter list (containers, fields, properties).
function RenderSignatureParamsMarkdown(const ASignature: string): string;

/// <summary>One parsed parameter from a routine signature: the leading
/// const/var/out modifier (if any), the parameter name, and its type text.</summary>
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
function RenderHoverJson(const AModel: THoverModel; const AFactLines: TArray<string>): string; overload;

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , System.StrUtils
  , System.Generics.Collections
  ;

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
    if ADoc.Summary   <> '' then SB.AppendLine('Summary: ' + ADoc.Summary  );
    if ADoc.ParamsJsonRaw <> '' then
    begin
      Re:= TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do SB.AppendLine('  ' + M.Groups[1].Value + ' -- ' + M.Groups[2].Value);
    end;
    if ADoc.ReturnsText <> '' then SB.AppendLine('Returns: ' + ADoc.ReturnsText);
    if ADoc.Remarks     <> '' then SB.AppendLine('Remarks: ' + ADoc.Remarks    );
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
    if ADoc.Summary <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine(ADoc.Summary);
    end;
    if ADoc.ParamsJsonRaw <> '' then
    begin
      SB.AppendLine(''               );
      SB.AppendLine('**Parameters:**');
      Re:= TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do SB.AppendLine('- `' + M.Groups[1].Value + '` ' + M.Groups[2].Value);
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
    if ADoc.ReturnsText <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('**Returns:** ' + ADoc.ReturnsText);
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
    if ADoc.Remarks <> '' then
    begin
      SB.AppendLine(''          );
      SB.AppendLine('## Remarks');
      SB.AppendLine(ADoc.Remarks);
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
  Result:= System.SysUtils.Format(
    '{"qname":"%s","format":"%s","summary":"%s","returns":"%s",' + '"since":"%s","deprecated":%s}', [
      JsonEscape(ASym.QualifiedName), DocFormatToStr(ADoc.Format), JsonEscape(ADoc.Summary), JsonEscape(ADoc.ReturnsText), JsonEscape(ADoc.SinceText),
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
    SB.Append(Format('"summary":"%s"}', [JsonEscape(AModel.Doc.Summary)]));
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
