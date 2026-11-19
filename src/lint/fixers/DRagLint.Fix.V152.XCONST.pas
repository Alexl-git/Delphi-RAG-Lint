unit DRagLint.Fix.V152.XCONST;

{ Wave v152 lane XCONST -- the MANUAL "extract constant" fix (ruling B4 part 2,
  PLAN D6) for magic-literal, large-magic-number, case-magic-numbers and the
  on-demand rule extract-constant (DRagLint.V152.XCONST).

  `lint --fix --fix-rule <id> --fix-line <n> [--col <c>] [--name <ident>]`:
  declares one constant for the finding's literal and replaces every occurrence
  of that literal token in the unit (DRagLint.V152.XCONST.Support.XcPlan says
  which are left, and why). Registered RISKY (a literal of the same value may
  mean something else) and MANUAL ONLY: a batch --fix never applies it. Without
  --name the plan proposes a name and the preview shows it. The plan's report
  (name, counts, placement, every occurrence left) goes to stderr.

  Self-registering from the initialization section; nothing uses this unit. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Math
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  , DRagLint.V152.XCONST.Support
  ;

const
  { The rules whose finding sits on a literal the fix can extract. }
  XC_FIX_RULES: array[0..3] of string = ('magic-literal', 'large-magic-number', 'case-magic-numbers', 'extract-constant');

var
  { file|literal pairs and names this process already planned: two findings on
    one literal are one extraction, and one --name is one constant. }
  GPlanned: TStringList;

function FixExtractConst(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
begin
  Result:= nil;
  { --col picks one literal of a line holding several }
  var Col: Integer:= StrToIntDef(XcCmdLineValue('--col'), 0);
  if (Col > 0) and ((Col < AFinding.StartCol) or (Col > Max(AFinding.EndCol, AFinding.StartCol + 1))) then Exit;
  var Plan: TXcPlan:= XcPlan(ALines, AFinding.StartLine, AFinding.StartCol, XcCmdLineValue('--name'));
  if Plan.Ok then
  begin
    if GPlanned.IndexOf(LowerCase(AFinding.FilePath) + '|' + Plan.Literal) >= 0 then Exit;
    if GPlanned.IndexOf('name|' + LowerCase(AFinding.FilePath) + '|' + LowerCase(Plan.Name)) >= 0 then
    begin
      Plan.Ok:= False;
      Plan.Refusal:= Format('the name ''%s'' is already used by another literal in this run -- pass --col <c> to pick one literal', [Plan.Name]);
    end;
  end;
  for var S: string in XcPlanReport(AFinding.FilePath, Plan) do
    Writeln(ErrOutput, S);
  if not Plan.Ok then Exit;
  GPlanned.Add(LowerCase(AFinding.FilePath) + '|' + Plan.Literal);
  GPlanned.Add('name|' + LowerCase(AFinding.FilePath) + '|' + LowerCase(Plan.Name));
  Result:= XcPlanEdits(AFinding.FilePath, Plan);
end;

procedure RegisterXConstFixers;
begin
  for var Id: string in XC_FIX_RULES do
  begin
    RegisterFixer(Id, FixExtractConst, True);
    MarkFixManualOnly(Id);
  end;
end;

initialization
  GPlanned:= TStringList.Create;
  RegisterXConstFixers;

finalization
  GPlanned.Free;

end.
