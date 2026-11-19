program SolveDriver;

{ check-init lane HBSOLVER test driver (built and run by tests\autotest\run_check_init_verdicts.ps1).

  Usage: SolveDriver --db <db> [--target <QName>] [--at <file>:<line>[:<col>]] [--max-routines N] [--stable]

  Calls DRagLint.Query.HappensBefore.CheckInit and prints HbAnswerJson of the answer on stdout (one
  JSON document). --stable zeroes budget.ms so two runs can be compared byte for byte. Exit code:
  HbExitCode (0 SET, 1 MAY-BE-UNSET / NEVER-SET), 2 on a usage error (EHbUsage, message on stderr).
  It is the same call `drag-lint check-init --json` makes once the CLI is wired to the solver. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, DRagLint.Diagnostics.ParseCache
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Render
, DRagLint.Query.HappensBefore
  ;

procedure Usage;
begin
  Writeln(ErrOutput, 'usage: SolveDriver --db <db> [--target <QName>] [--at <file>:<line>[:<col>]] ' +
    '[--max-routines N] [--stable]');
end;

function Run: Integer;
var
  DbPath, Target, At: string;
  Stable: Boolean;
  Opts: THbOptions;
begin
  Opts:= Default(THbOptions);
  Stable:= False;
  var I:= 1;
  while I <= ParamCount do
  begin
    var P:= ParamStr(I);
    if SameText(P, '--stable') then Stable:= True
    else if I < ParamCount then
    begin
      Inc(I);
      if SameText(P, '--db') then DbPath:= ParamStr(I)
      else if SameText(P, '--target') then Target:= ParamStr(I)
      else if SameText(P, '--at') then At:= ParamStr(I)
      else if SameText(P, '--max-routines') then Opts.MaxRoutines:= StrToIntDef(ParamStr(I), -1)
      else
      begin
        Usage;
        Exit(2);
      end;
    end
    else
    begin
      Usage;
      Exit(2);
    end;
    Inc(I);
  end;
  if (DbPath = '') or ((Target = '') and (At = '')) or (Opts.MaxRoutines < 0) then
  begin
    Usage;
    Exit(2);
  end;
  try
    var Answer:= CheckInit(DbPath, Target, At, Opts);
    if Stable then Answer.Budget.Ms:= 0;
    Writeln(HbAnswerJson(Answer));
    Result:= HbExitCode(Answer);
  except
    on E: EHbUsage do
    begin
      Writeln(ErrOutput, 'ERROR: ', E.Message);
      for var C in E.Candidates do Writeln(ErrOutput, '       candidate: ', C);
      Result:= 2;
    end;
  end;
  TAstParseCache.Clear;
end;

begin
  try
    ExitCode:= Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode:= 2;
    end;
  end;
end.
