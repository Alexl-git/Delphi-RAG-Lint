unit hardcodedcredentialV151;

interface

implementation

uses System.SysUtils;

type
  TConn = class
    Password: string;
    PasswordChar: Char;
    SQL: record Text: string end;
    CommandText: string;
  end;

procedure Bad(C: TConn; Obj: TObject; sCond, sWhere: string);
begin
  C.Password := 'hunter2';
  C.PasswordChar := '*';
  C.CommandText := 'DELETE FROM T ' + sCond;
  C.CommandText := 'DELETE FROM T ' + sWhere;
  C.CommandText := 'DELETE FROM T WHERE ' + sCond;
  C.SQL.Text := 'UPDATE T SET A=1' + #13#10 + ' ';
  C.SQL.Text := 'SELECT 1' + ' x';
  if Obj.ClassNameIs('TFoo') then Exit;
  if 'TFoo' = Obj.ClassName then Exit;
  if Obj.ClassName = 'TFoo' then Exit;
end;

end.
