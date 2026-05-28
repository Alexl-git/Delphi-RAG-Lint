program T5_pasdoc;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  Raw: string;
  P: TParsedDoc;
begin
  Raw :=
    'Adds two numbers.'#10 +
    '@param A first number'#10 +
    '@param B second number'#10 +
    '@returns sum'#10 +
    '@throws EOverflow on huge values'#10 +
    '@since 1.0'#10 +
    '@deprecated use NewAdd instead';
  P := TDocCommentParser.ParsePasDoc(Raw);
  Assert(P.Summary = 'Adds two numbers.', 'summary='+P.Summary);
  Assert(Length(P.Params) = 2, Format('param count=%d', [Length(P.Params)]));
  Assert(P.Params[0].Name = 'A', 'param0 name');
  Assert(P.Params[0].Desc = 'first number', 'param0 desc');
  Assert(P.ReturnsText = 'sum', 'returns');
  Assert(Length(P.Exceptions) = 1, 'exc count');
  Assert(P.Exceptions[0].TypeName = 'EOverflow', 'exc type');
  Assert(P.SinceText = '1.0', 'since='+P.SinceText);
  Assert(P.Deprecated, 'deprecated');
  WriteLn('OK');
end.
