unit uCycle;

interface

procedure RunCycle;

implementation

uses
  uDal;

function CycB(const S: string; N: Integer): string; forward;

function CycA(const S: string; N: Integer): string;
begin
  if N = 0 then
    Result := S
  else
    Result := CycB(S, N - 1);
end;

function CycB(const S: string; N: Integer): string;
begin
  Result := CycA(S, N);
end;

procedure RunCycle;
begin
  GConn.ExecSQL(CycA(ParamStr(1), 3));
end;

end.
