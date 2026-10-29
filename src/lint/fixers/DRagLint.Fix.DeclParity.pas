unit DRagLint.Fix.DeclParity;

{ Autofix for the gap-rules wave lane G7 (needless-exit). Self-registering: the
  initialization section hands the fixer to DRagLint.Lint.Autofix, which never
  uses this unit (no unit cycle). }

interface

implementation

uses
  System.Classes
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

{ needless-exit: the finding spans the trailing Exit / Exit(Result) statement; delete it. }
function FixNeedlessExit(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  E: TTextEdit;
begin
  Result:= nil;
  if DeleteStatement(AFinding, ALines, E) then Result:= [E];
end;

initialization
  RegisterFixer('needless-exit', FixNeedlessExit);

end.