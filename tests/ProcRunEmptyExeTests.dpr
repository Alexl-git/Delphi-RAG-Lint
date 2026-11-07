program ProcRunEmptyExeTests;
{$APPTYPE CONSOLE}
{ O-PLUGIN-EMPTY-EXE: EngineExeOrEmpty answers '' when no engine resolves, and about
  60 Editor / StructureForm sites format that straight into `"%s" verb ...`. The
  runner is the one place all of them pass through, so it refuses such a line.

  THE CASES, and what each one would catch being undone:
    1 an empty-exe command returns -1 with the shared message as its output: without
      the check CreateProcessW fails and the caller shows nothing, or an empty report.
    2 leading blanks do not hide it.
    3 positive control: a real command still runs, exit 0, its output intact -- a check
      that refused everything would pass 1 and 2 alone.
    4 positive control: a quoted exe that merely CONTAINS a doubled quote later on is
      not refused.
    5 the hook is told, once per refusal, and a hook that raises is dropped rather than
      failing the caller's spawn. }
uses
  System.SysUtils,
  DRagLint.Core.OutputEncoding in '..\src\core\DRagLint.Core.OutputEncoding.pas',
  DRagLint.Core.ControlChannel in '..\src\core\DRagLint.Core.ControlChannel.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas';

const
  ENGINE_TEXT = 'drag-lint.exe not found -- check drag-lint Options.';
  RUN_MS = 10000;

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;
  GHookCalls: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName, ' ', ADetail);
  end;
end;

var
  Output: string;
  Code  : Integer;
begin
  Code:= RunCaptureStdout('"" lint "x.pas"', Output, RUN_MS);
  Check('1a empty exe: exit -1', Code = -1, IntToStr(Code));
  Check('1b empty exe: the shared message is the output', Output = ENGINE_TEXT, Output);
  Code:= RunCaptureStdout('   "" lint "x.pas"', Output, RUN_MS);
  Check('2 leading blanks: same refusal', (Code = -1) and (Output = ENGINE_TEXT), Output);
  Code:= RunCaptureStdout('cmd.exe /c echo hello', Output, RUN_MS);
  Check('3 positive control: a real command runs', (Code = 0) and (Pos('hello', Output) > 0), Output);
  Code:= RunCaptureStdout('cmd.exe /c echo "" tail', Output, RUN_MS);
  Check('4 positive control: a later doubled quote is not refused', (Code = 0) and (Pos('tail', Output) > 0), Output);
  GEngineMissingHook:=
    procedure
    begin
      Inc(GHookCalls);
    end;
  RunCaptureStdout('"" lint "x.pas"', Output, RUN_MS);
  Check('5a the hook is told about a refusal', GHookCalls = 1, IntToStr(GHookCalls));
  RunCaptureStdout('cmd.exe /c echo hello', Output, RUN_MS);
  Check('5b positive control: a real command does not tell it', GHookCalls = 1, IntToStr(GHookCalls));
  GEngineMissingHook:=
    procedure
    begin
      raise Exception.Create('hook failed');
    end;
  Code:= RunCaptureStdout('"" lint "x.pas"', Output, RUN_MS);
  Check('5c a raising hook does not fail the refusal', (Code = -1) and (Output = ENGINE_TEXT), Output);
  Check('5d a raising hook is dropped', not Assigned(GEngineMissingHook));
  Check('6 IsEmptyExeCommand', IsEmptyExeCommand('"" x') and IsEmptyExeCommand(' ""') and not IsEmptyExeCommand('"a.exe" ""') and not IsEmptyExeCommand(''));
  Writeln(GPassed, ' passed, ', GFailed, ' failed');
  if GFailed > 0 then ExitCode:= 1;
end.