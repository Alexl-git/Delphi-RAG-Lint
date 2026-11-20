program FixCommandTests;
{$APPTYPE CONSOLE}
{ 1.52.2 FIXIDE: the IDE "Fix it" command line for the with rules carries --project, and a with fix with no project is refused up front.
  Run by tests\plugin\run_plugin_fix_command.ps1 (which also builds it over a stub that omits --project: that run MUST fail). }
uses
  System.SysUtils,
  System.StrUtils,
  DragLint.Plugin.FixCommand;

var
  GFailed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean);
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName);
  end;
end;

begin
  Check('with-statement needs a project', FixRuleNeedsProject('with-statement'));
  Check('nested-with needs a project', FixRuleNeedsProject('nested-with'));
  Check('with-hides-outer-symbol needs a project', FixRuleNeedsProject('with-hides-outer-symbol'));
  Check('naming rule does not', not FixRuleNeedsProject('naming-convention'));
  Check('apply line names --project',
    FixCommandLine('e.exe', 'U.pas', 'x.sqlite', 'with-statement', 7, True, 'P.dproj') =
    '"e.exe" lint --in "U.pas" --db "x.sqlite" --fix --fix-line 7 --fix-rule "with-statement" --project "P.dproj" --apply');
  Check('preview line names --project, no --apply',
    ContainsText(FixCommandLine('e.exe', 'U.pas', 'x.sqlite', 'nested-with', 7, False, 'P.dproj'), '--project "P.dproj"') and
    not ContainsText(FixCommandLine('e.exe', 'U.pas', 'x.sqlite', 'nested-with', 7, False, 'P.dproj'), '--apply'));
  Check('no project: no --project flag (other rules unchanged)',
    FixCommandLine('e.exe', 'U.pas', 'x.sqlite', 'magic-literal', 3, True, '') =
    '"e.exe" lint --in "U.pas" --db "x.sqlite" --fix --fix-line 3 --fix-rule "magic-literal" --apply');
  Check('with fix, no project: blocked with a message', FixBlockedReason('with-statement', '') <> '');
  Check('with fix, project known: not blocked', FixBlockedReason('with-statement', 'P.dproj') = '');
  Check('other rule, no project: not blocked', FixBlockedReason('magic-literal', '') = '');
  if GFailed > 0 then
  begin
    Writeln('FAILED: ', GFailed);
    Halt(1);
  end;
  Writeln('ALL PASSED');
end.
