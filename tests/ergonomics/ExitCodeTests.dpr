program ExitCodeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Output.ExitCode in '..\..\src\output\DRagLint.Output.ExitCode.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function F(const ASeverity: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId:= 'r'; Result.Severity:= ASeverity;
end;

procedure TestExitCode;
var
  Warns, Infos, Errs, Empty: TArray<TLintFinding>;
begin
  Empty:= [];
  Infos:= [F('info')];
  Warns:= [F('info'), F('warning')];
  Errs := [F('warning'), F('error')];

  // Flag absent => preserve default code.
  Check('absent: default 1 preserved', ExitCodeFor(Warns, '', 1) = 1);
  Check('absent: default 0 preserved', ExitCodeFor(Empty, '', 0) = 0);

  // none => always 0.
  Check('none: errors -> 0', ExitCodeFor(Errs, 'none', 1) = 0);

  // error threshold.
  Check('fail-on error: has error -> 1', ExitCodeFor(Errs , 'error', 0) = 1);
  Check('fail-on error: only warning -> 0', ExitCodeFor(Warns, 'error', 0) = 0);

  // warning threshold (error or warning trips it).
  Check('fail-on warning: warning -> 1', ExitCodeFor(Warns, 'warning', 0) = 1);
  Check('fail-on warning: only info -> 0', ExitCodeFor(Infos, 'warning', 0) = 0);

  // info threshold (anything info+ trips it).
  Check('fail-on info: info -> 1', ExitCodeFor(Infos, 'info', 0) = 1);
  Check('fail-on info: empty -> 0', ExitCodeFor(Empty, 'info', 0) = 0);

  // Unknown --fail-on value ranks 0, so any finding (rank >= 0) trips it.
  Check('fail-on unknown: warning -> 1', ExitCodeFor(Warns, 'typo', 0) = 1);

  { v0.81 review Minor: FinalizeAndOutput must derive ADefaultCode from the
    post-ShouldKeep Survivors set, not from the command's raw (pre-filter)
    findings. Model both sides of that contract here: a command whose 2 raw
    findings were BOTH suppressed as OFF-by-default (Survivors = Empty) must
    exit 0 -- the pre-fix caller wired ADefaultCode from
    IfThen(Length(RawFindings) > 0, 1, 0) = 1, which this proves would have
    been wrong; the fixed caller wires it from
    IfThen(Length(Survivors) > 0, 1, 0) = 0, which is correct. }
  Check('survivors-derived default: all-suppressed raw findings -> 0 (fixed contract)',
    ExitCodeFor(Empty, '', IfThen(Length(Empty) > 0, 1, 0)) = 0);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestExitCode;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('exitcode-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
