unit DRagLint.Diagnostics.ControlFlowChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L5.
  L0 shipped this unit as a STUB: Check returns nil. The lane replaces the body
  and adds the emitted ids to LINT_GATE_CONTROL_FLOW's checker (the ids are already
  in the gate list and in TRuleCatalog.BuiltinRegistry -- a lane registers
  nothing new in CLI.pas or RuleCatalog.pas).
  Rules: loop-condition-invariant, for-bound-modified-in-body, infinite-loop-no-exit, redundant-continue-exit, else-after-exit, unconditional-recursion. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the loop-condition-invariant, for-bound-modified-in-body, infinite-loop-no-exit, redundant-continue-exit, else-after-exit, unconditional-recursion rules. Stub until lane L5 lands.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_CONTROL_FLOW).
  /// </remarks>
  TControlFlowChecker = class
  public
    /// <summary>Runs the ControlFlowChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

class function TControlFlowChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.