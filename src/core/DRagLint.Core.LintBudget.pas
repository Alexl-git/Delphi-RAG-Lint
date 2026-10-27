unit DRagLint.Core.LintBudget;

{ How long a caller waits for ONE out-of-process `drag-lint lint <file>` run.

  Two callers spawn that child with a hard budget and fall back (or show
  nothing) when it runs out: the LSP's `--full-rules` publish
  (DRagLint.LSP.Server.RunFullRulesLint) and the IDE plugin's live runner
  (DragLint.Plugin.LiveDiagnostics). Both used to carry their own 8000. A
  platform-library unit (an RTL/VCL file whose owning index is a
  `library-*.sqlite`) skips the flow, type-aware and project rules (LSP C11/C12)
  and still measured 7.8 s on a 100%-CPU box, so it gets twice the budget. One
  unit, compiled into both the engine and the plugin package, so the two can no
  longer drift.

  Pure: no I/O, no globals. Pinned by
  tests\autotest\fixtures\lintbudget\LintBudgetHarness.dpr
  (tests\autotest\run_plugin_library_timeout_guard.ps1). }

interface

const
  /// <summary>Budget for one lint child of a project (non-library) file, in ms.</summary>
  LINT_CHILD_TIMEOUT_MS = 8000;
  /// <summary>Budget for one lint child of a platform-library unit, in ms (2x the
  /// project budget; see the unit comment for the measurement).</summary>
  LINT_CHILD_LIBRARY_TIMEOUT_MS = 2 * LINT_CHILD_TIMEOUT_MS;

/// <summary>Tells whether an index path names a platform-library index.</summary>
/// <param name="pDbPath">Path (or bare file name) of a .sqlite index; may be ''.</param>
/// <returns>True when the file name starts with <c>library-</c>, case-insensitively
/// -- the same test the engine's lint gates (FlowIsLibrary) use.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function IsLibraryIndexPath(const pDbPath: string): Boolean;

/// <summary>Chooses the lint-child budget for a file from the index that OWNS it.</summary>
/// <param name="pOwningDbPath">The first index, in the order the child lint is given
/// them, that contains the file; '' when none does.</param>
/// <returns>LINT_CHILD_LIBRARY_TIMEOUT_MS for a library index, else
/// LINT_CHILD_TIMEOUT_MS (also for '').</returns>
/// <remarks>Pure; thread-safe.</remarks>
function LintChildTimeoutMs(const pOwningDbPath: string): Cardinal;

implementation

uses
  System.SysUtils
  ;

function IsLibraryIndexPath(const pDbPath: string): Boolean;
begin
  Result:= LowerCase(ExtractFileName(pDbPath)).StartsWith('library-');
end; // function

function LintChildTimeoutMs(const pOwningDbPath: string): Cardinal;
begin
  Result:= if IsLibraryIndexPath(pOwningDbPath) then LINT_CHILD_LIBRARY_TIMEOUT_MS else LINT_CHILD_TIMEOUT_MS;
end; // function

end.
