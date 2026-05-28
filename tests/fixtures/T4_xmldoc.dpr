program T4_xmldoc;
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
    '<summary>Computes the baz</summary>'#13#10 +
    '<param name="value">input, must be > 0</param>'#13#10 +
    '<returns>the baz</returns>'#13#10 +
    '<exception cref="EArgumentException">when value <= 0</exception>';
  P := TDocCommentParser.ParseXmlDoc(Raw);
  Assert(P.Summary = 'Computes the baz', 'summary='+P.Summary);
  Assert(Length(P.Params) = 1, 'param count');
  Assert(P.Params[0].Name = 'value', 'param name='+P.Params[0].Name);
  Assert(P.Params[0].Desc = 'input, must be > 0', 'param desc='+P.Params[0].Desc);
  Assert(P.ReturnsText = 'the baz', 'returns='+P.ReturnsText);
  Assert(Length(P.Exceptions) = 1, 'exc count');
  Assert(P.Exceptions[0].TypeName = 'EArgumentException', 'exc type');
  Assert(P.HasContent, 'hasContent');
  WriteLn('OK');
end.
