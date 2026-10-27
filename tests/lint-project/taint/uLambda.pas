unit uLambda;

interface

procedure RunLambda;

implementation

uses
  SysUtils, uDal;

procedure RunLambda;
var
  S: string;
  P: TProc;
begin
  S := ParamStr(1);
  P := procedure
    begin
      GConn.ExecSQL(S);
    end;
  P;
end;

end.
