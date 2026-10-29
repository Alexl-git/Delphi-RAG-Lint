unit uLoop;

interface

procedure LoopSql;

implementation

uses
  System.SysUtils, uDeepConn;

{ loop-carried reassignment: arg 0 of StringReplace derives from its own result }
procedure LoopSql;
var
  S: string;
  I: Integer;
begin
  S := ParamStr(1);
  for I := 0 to 3 do
    S := StringReplace(S, 'a', 'b', []);
  GConn.ExecSQL(S);
end;

end.
