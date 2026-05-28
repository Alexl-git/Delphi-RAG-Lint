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

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  System.StrUtils;

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
