unit DRagLint.V156.TAINTEXC;

{ Wave v156 (1.56.0-alpha) lane FA-2 -- taint through exceptions (on the B4 rows of
  DRagLint.Index.DataFlowExc). NOT a rule provider of DRagLint.V151.Dispatch: it emits under the
  taint ids of DRagLint.Lint.TaintRules, which calls Check through ONE hook line (lane TAINT-1).
  Scaffold created by lane FRAME-1; lane FA-2 owns this unit and DRagLint.V156.TAINTEXC.Support. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Taint that reaches a sink through raise / except: the part of the taint check that
  /// reads the exception data flows.</summary>
  /// <remarks>Stateless; class methods only. Not thread-safe (one store connection).</remarks>
  TV156TaintExc = class
  public
    /// <summary>Findings for tainted values carried by an exception object into a handler's sink.</summary>
    /// <param name="AStore">The project index; not nil.</param>
    /// <param name="ALibStore">The library index; may be nil.</param>
    /// <param name="AScopeFileIds">The files whose sinks are reported; empty = every file.</param>
    /// <returns>Findings under the existing taint rule ids; nil when none. The scaffold returns nil.</returns>
    /// <remarks>Read-only. Called once per TTaintRules.Check run, after the ordinary walk.</remarks>
    class function Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>; static;
  end;

implementation

class function TV156TaintExc.Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.
