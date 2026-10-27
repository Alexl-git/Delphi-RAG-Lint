unit DRagLint.Diagnostics.ParityExtChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G9.
  G0 shipped this unit as a STUB: Check returns nil. The lane replaces the body.
  The ids are already in LINT_GATE_PARITY_EXT (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- a lane registers nothing new in CLI.pas or
  RuleCatalog.pas.
  Rules: identical-then-else, interface-object-mixing (extensions emitting existing ids). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the ParityExtChecks rules of the gap-rules wave (G9).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_PARITY_EXT).
  /// </remarks>
  TParityExtChecker = class
  public
    /// <summary>Runs the ParityExtChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

class function TParityExtChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.