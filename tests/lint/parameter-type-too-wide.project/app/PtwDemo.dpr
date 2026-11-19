program PtwDemo;
{$APPTYPE CONSOLE}
uses
  PtwBase in 'PtwBase.pas',
  PtwLeaf in 'PtwLeaf.pas',
  PtwUse in 'PtwUse.pas',
  PtwForm in 'PtwForm.pas' {PtwForm},
  PtwLib;
begin
  RunAll;
  LibMid(nil);
end.
