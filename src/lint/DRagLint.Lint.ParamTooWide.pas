unit DRagLint.Lint.ParamTooWide;

{ The `parameter-type-too-wide` project rule (1.46 lane t4, E-PARAM-TOO-WIDE). OFF by default.

  A class-typed parameter whose routine only ever uses members that an ancestor of the declared
  type already declares could take that ancestor: the signature promises more than the body needs
  and callers are tied to the wider type. The proof is the one `narrow-param --all --plan` already
  makes (DRagLint.Refactor.NarrowParam.PlanNarrowParams): every use is `p.m` read or called or a
  nil test, each m has a first declaring class in the chain, the routine is not virtual,
  overloaded, published, an interface's method or taken as a value, and so on. This rule reports
  exactly the plan's FIXES, one finding per parameter, anchored at the routine's declaration; the
  refusals are not findings. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  PARAM_TOO_WIDE_RULE = 'parameter-type-too-wide';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index (a SQLite store); nil yields no findings.</param>
/// <param name="ALibraryStore">The platform library index, or nil. Without it an ancestor or
/// member the project does not declare is unproved, so the rule stays silent there.</param>
/// <returns>One 'parameter-type-too-wide' hint per parameter `narrow-param` can prove narrowable,
/// anchored at the routine's declaration line; the message names the parameter, its type and the
/// narrower type (and the unit that would join the uses clause).</returns>
/// <remarks>
/// Not thread-safe. Reads the source files of the routines it examines (the planner masks
/// comments and strings); writes nothing. Cost is the planner's: a full routine scan plus one
/// file read per examined routine, so it is OptedIn-gated and ships OFF.
/// </remarks>
function CollectParamTooWide(const AStore, ALibraryStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , DRagLint.Refactor.NarrowParam
  ;

function CollectParamTooWide(const AStore, ALibraryStore: ISymbolStore): TArray<TLintFinding>;
begin
  Result:= nil;
  if AStore = nil then Exit;
  var Opts:= Default(TNarrowParamOptions);
  Opts.All:= True;
  var Libs: TArray<ISymbolStore>:= nil;
  if ALibraryStore <> nil then Libs:= [ALibraryStore];
  var Plan:= PlanNarrowParams(AStore, Libs, Opts);
  SetLength(Result, Length(Plan.Fixes));
  for var I:= 0 to High(Plan.Fixes) do
  begin
    var S:= Plan.Fixes[I];
    var F:= Default(TLintFinding);
    F.RuleId   := PARAM_TOO_WIDE_RULE;
    F.Severity := 'hint';
    F.FilePath := S.FilePath;
    F.StartLine:= S.Line;
    F.EndLine  := S.Line;
    F.StartCol := 1;
    F.EndCol   := 1;
    F.Message  := Format('Parameter %s of %s is declared %s but only members of %s are used -- '
      + 'declare it %s%s so callers are not tied to the wider type.',
      [S.Param, S.Routine, S.FromType, S.ToType, S.ToType,
       (if S.AddUses <> '' then ' (add ' + S.AddUses + ' to uses)' else '')]);
    Result[I]:= F;
  end;
end;

end.
