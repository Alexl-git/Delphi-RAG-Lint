program Probe2;
{$APPTYPE CONSOLE}
uses System.SysUtils, UOther in 'UOther.pas';

type
  IStop = interface
    procedure Stop; noreturn;
  end;
  TImp = class(TInterfacedObject, IStop)
    procedure Stop; noreturn;
  end;
  TProc = procedure;

procedure TImp.Stop;
begin
end;

procedure CrossPlain; noreturn;
begin
  OtherPlain;
end;

procedure CrossFail; noreturn;
begin
  OtherFail;
end;

procedure Swallow; noreturn;
begin
  try
    raise Exception.Create('x');
  except
  end;
end;

procedure SwallowCall; noreturn;
begin
  try
    OtherFail;
  except
    on E: Exception do Writeln(E.Message);
  end;
end;

procedure ViaVar(P: TProc); noreturn;
begin
  P;
end;

procedure LoopBreak(A: Integer); noreturn;
begin
  while True do
    if A > 1 then Break;
end;

procedure Forever; noreturn;
begin
  while True do ;
end;

function F2: Integer; noreturn;
begin
  raise Exception.Create('s');
end;

procedure AfterCall2;
begin
  OtherFail;
  Writeln('never');
end;

procedure HaltIt; noreturn;
begin
  Halt(1);
end;

procedure AbortIt; noreturn;
begin
  Abort;
end;

procedure RaiseOs; noreturn;
begin
  RaiseLastOSError;
end;

begin
  AfterCall2;
end.
