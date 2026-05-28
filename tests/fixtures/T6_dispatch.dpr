program T6_dispatch;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  P: TParsedDoc;
  Region: TDocCommentRegion;
begin
  // Oneline: triple-slash with no XML tags
  Region.Kind := dckTripleSlash;
  Region.RawText := '/// Plain one-liner doc';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfOneline, 'oneline format');
  Assert(P.Summary = 'Plain one-liner doc', 'oneline summary='+P.Summary);

  // Oneline: //1 style
  Region.Kind := dckDoubleSlashOne;
  Region.RawText := '//1 Another oneliner';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfOneline, '//1 format');
  Assert(P.Summary = 'Another oneliner', '//1 summary='+P.Summary);

  // Triple-slash WITH XML tags -> xmldoc
  Region.Kind := dckTripleSlash;
  Region.RawText := '/// <summary>X</summary>';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfXmlDoc, 'xmldoc format');

  // PasDoc curly
  Region.Kind := dckPasDocCurly;
  Region.RawText := 'Hello' + #10 + '@returns world';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfPasDoc, 'pasdoc format');
  Assert(P.Summary = 'Hello', 'pasdoc summary='+P.Summary);

  // Loose with noise (TODO line)
  Region.Kind := dckLooseLine;
  Region.RawText := '// TODO: not a real doc';
  P := TDocCommentParser.Dispatch(Region);
  Assert(not P.HasContent, 'loose noise dropped');

  WriteLn('OK');
end.
