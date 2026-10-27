unit DRagLint.Diagnostics.DeclParityChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G7.
  G0 shipped this unit as a STUB: Check returns nil. The lane replaces the body.
  The ids are already in LINT_GATE_DECL_PARITY (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- a lane registers nothing new in CLI.pas or
  RuleCatalog.pas.
  Rules: hides-ancestor-virtual, needless-exit, free-of-parameter, property-accessor-name, unused-loop-variable, property-references-itself (extension). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the DeclParityChecks rules of the gap-rules wave (G7).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_DECL_PARITY).
  /// </remarks>
  TDeclParityChecker = class
  public
    /// <summary>Runs the DeclParityChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

class function TDeclParityChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.