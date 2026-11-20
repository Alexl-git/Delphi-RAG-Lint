unit DragLint.Plugin.FixCommand;

{ 1.52.2 FIXIDE: the engine command line of the IDE's "Fix it" for ONE finding, kept free of IDE units so a console test can assert it.

  The with rules (with-statement, nested-with, with-hides-outer-symbol) are not linted by the engine: `lint --fix --fix-rule <with rule>`
  runs `unwith`, which builds the project through the compile gate and exits 2 "needs --project" without it. So the plugin must name the
  active project for those rules, and must not run a command that is bound to fail when no project is known. }

interface

/// <summary>True for the rules whose engine fix is `unwith` (with-statement, nested-with, with-hides-outer-symbol).</summary>
/// <param name="pRule">The finding's rule id; compared case-insensitively.</param>
/// <returns>True when the engine fix needs --project (compile gate).</returns>
function FixRuleNeedsProject(const pRule: string): Boolean;

/// <summary>The engine command for the fix of one rule on one line.</summary>
/// <param name="pExe">Engine exe path.</param>
/// <param name="pFileName">The unit to fix.</param>
/// <param name="pDb">The project index DB.</param>
/// <param name="pRule">The rule id of the finding.</param>
/// <param name="pLine1">1-based line of the finding.</param>
/// <param name="pApply">True = write (--apply); False = dry-run preview.</param>
/// <param name="pProject">The active .dproj; appended as --project when not empty (required by FixRuleNeedsProject rules).</param>
/// <returns>The full command line, quoted for the process runner.</returns>
function FixCommandLine(const pExe, pFileName, pDb, pRule: string; pLine1: Integer; pApply: Boolean;
  const pProject: string): string;

/// <summary>The message to show instead of running a fix that cannot work, or '' when the fix may run.</summary>
/// <param name="pRule">The finding's rule id.</param>
/// <param name="pProject">The active project file, '' when none is known.</param>
/// <returns>A user-facing sentence naming what is missing, or ''.</returns>
function FixBlockedReason(const pRule, pProject: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function FixRuleNeedsProject(const pRule: string): Boolean;
begin
  Result:= MatchText(pRule, ['with-statement', 'nested-with', 'with-hides-outer-symbol']);
end;

function FixCommandLine(const pExe, pFileName, pDb, pRule: string; pLine1: Integer; pApply: Boolean;
  const pProject: string): string;
begin
  Result:= Format('"%s" lint --in "%s" --db "%s" --fix --fix-line %d --fix-rule "%s"%s%s',
    [pExe, pFileName, pDb, pLine1, pRule,
     if pProject <> '' then Format(' --project "%s"', [pProject]) else '',
     if pApply then ' --apply' else '']);
end;

function FixBlockedReason(const pRule, pProject: string): string;
begin
  Result:= '';
  if FixRuleNeedsProject(pRule) and (pProject = '') then
    Result:= Format('drag-lint: the fix for %s builds the project to prove each change, so it needs an active project. Open the project (.dproj) in the IDE and try again.', [pRule]);
end;

end.
