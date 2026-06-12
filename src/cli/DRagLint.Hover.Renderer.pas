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
  DRagLint.Core.Model;

function RenderHoverPlain(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;

function RenderHoverMarkdown(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;

function RenderHoverJson(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;

// v0.43: turn a proc-like signature -- e.g. '(AOwner: TComponent;
// AFldrSystID: Int64): Boolean' -- into an IDE-style markdown block listing
// each parameter name + type on its own line, plus the return type. Returns ''
// when the signature has no parameter list (containers, fields, properties).
function RenderSignatureParamsMarkdown(const ASignature: string): string;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  System.StrUtils,
  System.Generics.Collections;

{ ---- v0.43 signature -> Parameters block helpers ---- }

// Split S on Sep, but only at top nesting level (ignores separators inside
// (), [], <> so generics like TDictionary<Integer, string> stay intact).
function SplitTopLevel(const S: string; Sep: Char): TArray<string>;
var
  Parts: TList<string>;
  i, Depth, Start: Integer;
begin
  Parts := TList<string>.Create;
  try
    Depth := 0;
    Start := 1;
    for i := 1 to Length(S) do
    begin
      case S[i] of
        '(', '[', '<': Inc(Depth);
        ')', ']', '>': if Depth > 0 then Dec(Depth);
      end;
      if (S[i] = Sep) and (Depth = 0) then
      begin
        Parts.Add(Copy(S, Start, i - Start));
        Start := i + 1;
      end;
    end;
    Parts.Add(Copy(S, Start, Length(S) - Start + 1));
    Result := Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

// Index of the last top-level ':' in S (the name/type separator), or 0.
function LastTopLevelColon(const S: string): Integer;
var
  i, Depth: Integer;
begin
  Result := 0;
  Depth := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '(', '[', '<': Inc(Depth);
      ')', ']', '>': if Depth > 0 then Dec(Depth);
      ':': if Depth = 0 then Result := i;
    end;
end;

function RenderSignatureParamsMarkdown(const ASignature: string): string;
var
  Sig, ParamsPart, RetPart, Names, Typ, ModWord: string;
  OpenParen, CloseParen, ColonPos, Depth, i: Integer;
  SB: TStringBuilder;
  Seg, Nm, MW: string;
begin
  Result := '';
  Sig := Trim(ASignature);
  OpenParen := Pos('(', Sig);
  if OpenParen = 0 then
    Exit;   // no parameter list -- nothing IDE-style to break out

  { find the paren that closes OpenParen }
  Depth := 0;
  CloseParen := 0;
  for i := OpenParen to Length(Sig) do
  begin
    case Sig[i] of
      '(': Inc(Depth);
      ')': begin Dec(Depth); if Depth = 0 then begin CloseParen := i; Break; end; end;
    end;
  end;
  if CloseParen = 0 then
    Exit;

  ParamsPart := Trim(Copy(Sig, OpenParen + 1, CloseParen - OpenParen - 1));
  RetPart := Trim(Copy(Sig, CloseParen + 1, MaxInt));
  if (RetPart <> '') and (RetPart[1] = ':') then
    RetPart := Trim(Copy(RetPart, 2, MaxInt));

  SB := TStringBuilder.Create;
  try
    if ParamsPart <> '' then
    begin
      SB.AppendLine('**Parameters:**');
      for Seg in SplitTopLevel(ParamsPart, ';') do
      begin
        if Trim(Seg) = '' then Continue;
        ColonPos := LastTopLevelColon(Seg);
        if ColonPos > 0 then
        begin
          Names := Trim(Copy(Seg, 1, ColonPos - 1));
          Typ := Trim(Copy(Seg, ColonPos + 1, MaxInt));
        end
        else
        begin
          Names := Trim(Seg);
          Typ := '';
        end;
        { peel a leading const/var/out modifier off the names }
        ModWord := '';
        for MW in ['const ', 'var ', 'out '] do
          if StartsText(MW, Names) then
          begin
            ModWord := Trim(MW) + ' ';
            Names := Trim(Copy(Names, Length(MW) + 1, MaxInt));
            Break;
          end;
        for Nm in SplitTopLevel(Names, ',') do
          if Trim(Nm) <> '' then
            if Typ <> '' then
              SB.AppendLine(Format('- `%s` : %s%s', [Trim(Nm), ModWord, Typ]))
            else
              SB.AppendLine(Format('- `%s`', [Trim(Nm)]));
      end;
    end;
    if RetPart <> '' then
    begin
      if ParamsPart <> '' then SB.AppendLine('');
      SB.AppendLine('**Returns:** ' + RetPart);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderHoverPlain(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
var
  SB: TStringBuilder;
  Re: TRegEx;
  M: TMatch;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('[DEPRECATED]');
    if ADoc.SinceText <> '' then SB.AppendLine('Since: ' + ADoc.SinceText);
    if ADoc.Summary <> '' then
      SB.AppendLine('Summary: ' + ADoc.Summary);
    if ADoc.ParamsJsonRaw <> '' then
    begin
      Re := TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do
        SB.AppendLine('  ' + M.Groups[1].Value + ' -- ' +
          M.Groups[2].Value);
    end;
    if ADoc.ReturnsText <> '' then
      SB.AppendLine('Returns: ' + ADoc.ReturnsText);
    if ADoc.Remarks <> '' then SB.AppendLine('Remarks: ' + ADoc.Remarks);
    if ADoc.ExampleText <> '' then
    begin
      SB.AppendLine('Example:');
      SB.AppendLine(ADoc.ExampleText);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderHoverMarkdown(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
var
  SB: TStringBuilder;
  Re: TRegEx;
  M: TMatch;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# ' + ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('> **DEPRECATED**');
    if ADoc.SinceText <> '' then
      SB.AppendLine('> _Since: ' + ADoc.SinceText + '_');
    if ADoc.Summary <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine(ADoc.Summary);
    end;
    if ADoc.ParamsJsonRaw <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('**Parameters:**');
      Re := TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
      for M in Re.Matches(ADoc.ParamsJsonRaw) do
        SB.AppendLine('- `' + M.Groups[1].Value + '` ' +
          M.Groups[2].Value);
    end
    else
    begin
      { v0.43: no XMLDoc @param tags -- fall back to the IDE-style block
        derived from the signature itself (name + type per parameter). }
      var SigBlock: string := RenderSignatureParamsMarkdown(ASym.Signature);
      if SigBlock <> '' then
      begin
        SB.AppendLine('');
        SB.Append(SigBlock);
      end;
    end;
    if ADoc.ReturnsText <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('**Returns:** ' + ADoc.ReturnsText);
    end;
    if ADoc.Remarks <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('## Remarks');
      SB.AppendLine(ADoc.Remarks);
    end;
    if ADoc.ExampleText <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('## Example');
      SB.AppendLine('```pascal');
      SB.AppendLine(ADoc.ExampleText);
      SB.AppendLine('```');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderHoverJson(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
begin
  Result := System.SysUtils.Format(
    '{"qname":"%s","format":"%s","summary":"%s","returns":"%s",' +
    '"since":"%s","deprecated":%s}',
    [JsonEscape(ASym.QualifiedName), DocFormatToStr(ADoc.Format),
     JsonEscape(ADoc.Summary), JsonEscape(ADoc.ReturnsText),
     JsonEscape(ADoc.SinceText),
     IfThen(ADoc.Deprecated, 'true', 'false')]);
end;

end.
