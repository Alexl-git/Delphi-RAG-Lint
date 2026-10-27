unit uSafe;

interface

procedure SafeQuoted;
procedure SafeParam;
procedure SafeLiteral;
procedure SafeKill;
procedure SafeInt;
procedure SafeNonSource;

implementation

uses
  SysUtils, FireDAC.Comp.Client, uDal;

function GetConfigName: string;
begin
  Result := 'cfg';
end;

procedure Helper(const A: string);
begin
  GConn.ExecSQL(A);
end;

procedure SafeQuoted;
begin
  GConn.ExecSQL('select * from T where N = ' + QuotedStr(ParamStr(1)));
end;

procedure SafeParam;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'select * from T where N = :N';
  Q.ParamByName('N').AsString := ParamStr(1);
  Q.Open;
end;

procedure SafeLiteral;
begin
  GConn.ExecSQL('select 1 from T');
end;

procedure SafeKill;
var
  S: string;
begin
  S := ParamStr(1);
  S := 'select 2 from T';
  GConn.ExecSQL(S);
end;

procedure SafeInt;
begin
  GConn.ExecSQL(Format('delete from T where id = %d', [StrToInt(ParamStr(1))]));
end;

procedure SafeNonSource;
begin
  Helper(GetConfigName);
end;

end.
