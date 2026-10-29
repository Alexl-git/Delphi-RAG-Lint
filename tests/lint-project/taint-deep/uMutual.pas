unit uMutual;

interface

procedure MutA(const S: string; N: Integer);
procedure MutB(const S: string; N: Integer);
procedure MutTop;

implementation

uses
  System.SysUtils, uDeepConn;

procedure MutA(const S: string; N: Integer);
begin
  if N > 0 then MutB(S, N - 1);
end;

procedure MutB(const S: string; N: Integer);
begin
  GConn.ExecSQL(S);
  if N > 0 then MutA(Trim(S), N - 1);
end;

procedure MutTop;
begin
  MutA(ParamStr(2), 3);
end;

end.
