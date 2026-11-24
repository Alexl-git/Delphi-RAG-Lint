unit DRagLint.V154.FLOW;

{ Wave v154 (1.54.0-alpha) lane FLOW -- managed-result-read-first, same-variable-two-var-params,
  address-of-nested-routine, var-param-never-written, value-param-assigned, constant-return,
  redundant-field-init, absolute-overlay (G-08 G-09 G-17 G-18 G-19 G-31 G-33 G-39).
  Wiki: docs\wiki\v154-flow-rules.md. Helpers: DRagLint.V154.FLOW.Support.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v154 lanes reuse the
  DRagLint.V151.Api types). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v154 lane FLOW; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV154FLOWRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.StrUtils
  , DRagLint.V154.FLOW.Support
  ;

const
  CATEGORY_BUG = 'bug-patterns';
  CATEGORY_FLOW = 'data-flow';
  CATEGORY_REFACTORING = 'refactoring';
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  { OFF unless the config or --rule asks for them: computed only then }
  OFF_RULES: array[0..4] of string = (RULE_VAR_UNWRITTEN, RULE_VALUE_SET, RULE_CONST_RETURN, RULE_FIELD_INIT, RULE_OVERLAY);

{ The defaults follow "Measured" in docs\wiki\v154-flow-rules.md. }
class procedure TV154FLOWRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_RESULT_FIRST, CATEGORY_FLOW, SEVERITY_WARNING, 'Result of a string, dynamic array, interface or Variant function read before it is set'));
  ADecls.Add(V151Rule(RULE_SAME_VAR, CATEGORY_BUG, SEVERITY_WARNING, 'One variable passed to two parameters that can change it'));
  ADecls.Add(V151Rule(RULE_NESTED_ADDR, CATEGORY_BUG, SEVERITY_WARNING, 'Address of a nested routine taken'));
  ADecls.Add(V151Rule(RULE_VAR_UNWRITTEN, CATEGORY_REFACTORING, SEVERITY_HINT, 'var parameter that is never written', False));
  ADecls.Add(V151Rule(RULE_VALUE_SET, CATEGORY_REFACTORING, SEVERITY_HINT, 'By-value parameter used as a local variable', False));
  ADecls.Add(V151Rule(RULE_CONST_RETURN, CATEGORY_FLOW, SEVERITY_HINT, 'Function whose every assignment to Result is the same literal', False));
  ADecls.Add(V151Rule(RULE_FIELD_INIT, CATEGORY_REFACTORING, SEVERITY_HINT, 'Constructor sets a field to the value a new object already has', False));
  ADecls.Add(V151Rule(RULE_OVERLAY, CATEGORY_BUG, SEVERITY_HINT, 'Variable declared absolute over another variable', False));
end;

class function TV154FLOWRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Run: TFlowRun;

  { True when this run reports ARule; the unit's nodes are collected for the first such rule. }
  function Wanted(const ARule: string): Boolean;
  begin
    Result:= ACtx.Wants(ARule) and ((not MatchStr(ARule, OFF_RULES)) or SameText(ACtx.NarrowRule, ARule) or ACtx.Cfg.ShouldKeep(ARule, True));
    if Result and (Run = nil) then Run:= TFlowRun.Create(ACtx);
  end;

begin
  Result:= nil;
  Run   := nil;
  try
    if Wanted(RULE_RESULT_FIRST) then Run.CheckResults;
    if Wanted(RULE_SAME_VAR) then Run.CheckArguments;
    if Wanted(RULE_NESTED_ADDR) then Run.CheckNestedAddresses;
    if Wanted(RULE_VAR_UNWRITTEN) then Run.CheckVarParams;
    if Wanted(RULE_VALUE_SET) then Run.CheckValueParams;
    if Wanted(RULE_CONST_RETURN) then Run.CheckConstants;
    if Wanted(RULE_FIELD_INIT) then Run.CheckFieldInits;
    if Wanted(RULE_OVERLAY) then Run.CheckOverlays;
    if Run <> nil then Result:= Run.Findings;
  finally
    Run.Free;
  end;
end;
class function TV154FLOWRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@bde6 -- REVIEWED 2026-11-24 v154 FLOW: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV154FLOWRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@bcf2 -- REVIEWED 2026-11-24 v154 FLOW: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV154FLOWRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@2bcc -- REVIEWED 2026-11-24 v154 FLOW: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
