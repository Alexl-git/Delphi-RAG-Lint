program T2_typecheck;
{$APPTYPE CONSOLE}
uses
  DRagLint.Core.Model;
var
  P: TParsedDoc;
  R: TDocCommentRegion;
begin
  P.Summary := 'hello';
  R.StartLine := 1;
  R.Kind := dckTripleSlash;
  WriteLn('OK');
end.
