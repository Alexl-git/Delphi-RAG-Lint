program LintBudgetHarness;

{ LSP C13: pins DRagLint.Core.LintBudget, the ONE lint-child budget shared by
  the LSP --full-rules publish and the IDE plugin's live runner. Prints one
  "PASS <name>" or "FAIL <name> -- <detail>" line per case; exits 1 on any
  failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , DRagLint.Core.LintBudget in '..\..\..\..\src\core\DRagLint.Core.LintBudget.pas'
  ;

var
  GFailed: Boolean = False;

procedure Check(const AName: string; AGot, AWant: Cardinal);
begin
  if AGot = AWant then Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName, ' -- got ', AGot, ' want ', AWant);
    GFailed:= True;
  end;
end;

begin
  { POSITIVE CONTROL: a project index keeps the 8 s the plugin always had. }
  Check('project index -> 8000 ms',
    LintChildTimeoutMs('C:\P\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'), 8000);
  Check('no owning index -> 8000 ms', LintChildTimeoutMs(''), 8000);
  Check('platform library index -> 16000 ms',
    LintChildTimeoutMs('C:\Projects\.drag-lint\library-Win64.sqlite'), 16000);
  Check('library test is case-insensitive -> 16000 ms',
    LintChildTimeoutMs('C:\X\LIBRARY-Win32.SQLITE'), 16000);
  Check('only the FILE name counts, not a library-* folder -> 8000 ms',
    LintChildTimeoutMs('C:\X\library-stuff\Proj.sqlite'), 8000);
  Check('a name merely containing library- -> 8000 ms',
    LintChildTimeoutMs('C:\X\my-library-Win64.sqlite'), 8000);
  Check('library budget is twice the project budget',
    LINT_CHILD_LIBRARY_TIMEOUT_MS, 2 * LINT_CHILD_TIMEOUT_MS);
  if GFailed then ExitCode:= 1;
end.
