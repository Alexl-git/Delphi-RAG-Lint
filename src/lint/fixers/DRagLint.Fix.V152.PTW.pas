unit DRagLint.Fix.V152.PTW;

{ Wave v152 lane PTW -- the autofix of parameter-type-too-wide (ruling B7): retypes the parameter to the narrower
  type the narrow-param plan proved, in both routine headers, and adds that type's unit to the uses clause when
  needed. The edits come from DRagLint.Refactor.NarrowParam.BuildNarrowEdits, which re-proves every finding first,
  so a stale finding is declined. A per-FILE fixer: all findings of one unit share one uses-clause edit. Written
  through the --fix applier, so --compile-gate builds the project before the edit is kept. Self-registering from
  the initialization section; nothing uses this unit except the CLI hook that hands it the library store. }

interface

uses
  DRagLint.Core.Interfaces;

/// <summary>Hands the platform library store to the parameter-type-too-wide autofix for one fix run.</summary>
/// <param name="pLib">The library store, or nil. Without it a chain or member the project does not declare (VCL,
/// RTL ancestors) is unproved and that finding's fix is declined, as the rule itself would decline it.</param>
/// <remarks>Set by the CLI around BuildAutofixEdits and cleared (nil) after it. The caller keeps ownership of the
/// store. Not thread-safe; call from the run thread only.</remarks>
procedure SetPtwFixLibrary(const pLib: ISymbolStore);

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Refactor.NarrowParam
  , DRagLint.Lint.Autofix
  ;

const
  CRuleId = 'parameter-type-too-wide';

var
  { the library store of the current fix run (SetPtwFixLibrary); nil = none }
  GPtwLib: ISymbolStore = nil;

procedure SetPtwFixLibrary(const pLib: ISymbolStore);
begin
  GPtwLib:= pLib;
end;

{ The parameter a finding names: its message starts "Parameter <name> of <routine> ...". '' = every parameter of the
  routine the plan can narrow, which is what a finding without that wording asks for. }
function ParamOf(const pMessage: string): string;
begin
  var M:= TRegEx.Match(pMessage, '^Parameter (\w+) of ');
  Result:= if M.Success then M.Groups[1].Value else '';
end;

function FixParamTooWide(const pPath: string; const pFindings: TArray<TLintFinding>; out pFixed: Integer): TArray<TTextEdit>;
begin
  Result:= nil;
  pFixed:= 0;
  var Store:= AutofixStore;
  if Store = nil then Exit;
  var Path:= ExpandFileName(pPath);
  var Targets: TArray<TNarrowTarget>:= nil;
  for var F in pFindings do
    if SameText(F.RuleId, CRuleId) and SameText(ExpandFileName(F.FilePath), Path) then
    begin
      var T: TNarrowTarget;
      T.Line := F.StartLine;
      T.Param:= ParamOf(F.Message);
      Targets:= Targets + [T];
    end;
  if Targets = nil then Exit;
  var Libs: TArray<ISymbolStore>:= nil;
  if GPtwLib <> nil then Libs:= [GPtwLib];
  var Why: string;
  if not BuildNarrowEdits(Store, Libs, Path, Targets, Result, pFixed, Why) then
  begin
    Result:= nil;
    pFixed:= 0;
  end;
end;

initialization
  RegisterFileFixer(CRuleId, FixParamTooWide);

end.
