program RecvDriver;

{ check-init lane HBRECV test driver (built and run by tests\autotest\run_check_init_receiver.ps1).

  Usage: RecvDriver --db <db> --target <QName> [--max-routines N] [--stable]

  Calls DRagLint.Query.HappensBefore.CheckInit, then -- for an instance field -- the receiver proof
  DRagLint.Query.HappensBefore.Receiver.ApplyReceiverProof over the same DB, and prints HbAnswerJson of
  the answer (one JSON document). This is the call CheckInit makes itself once INT wires the receiver
  proof into its htkInstanceField branch (handover H-RECV1); ApplyReceiverProof is idempotent, so the
  driver stays valid after that wiring. --stable zeroes budget.ms. Exit code: HbExitCode, 2 on a
  usage error. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, DRagLint.Core.Interfaces
, DRagLint.Storage.SQLite
, DRagLint.Charts.Index
, DRagLint.Diagnostics.ParseCache
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Render
, DRagLint.Query.HappensBefore.Receiver
, DRagLint.Query.HappensBefore
  ;

procedure Usage;
begin
  Writeln(ErrOutput, 'usage: RecvDriver --db <db> --target <QName> [--max-routines N] [--stable]');
end;

function Run: Integer;
var
  DbPath, Target: string;
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
  if (DbPath = '') or (Target = '') or (Opts.MaxRoutines < 0) then
  begin
    Usage;
    Exit(2);
  end;
  try
    var Answer:= CheckInit(DbPath, Target, '', Opts);
    if Answer.Target.Kind = htkInstanceField then
    begin
      var Index:= TChartsIndex.Create(DbPath);
      try
        var Store: ISymbolStore:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
        ApplyReceiverProof(Index, Store, Answer, if Opts.MaxRoutines > 0 then Opts.MaxRoutines
          else HB_DEFAULT_MAX_ROUTINES);
      finally
        Index.Free;
      end;
    end;
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
