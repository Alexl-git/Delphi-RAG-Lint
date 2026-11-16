unit LargeMagicV1511b;

interface

implementation

procedure Reg(A: Integer; const S: string);
begin
end;

procedure P(Q: TObject; X: Integer);
begin
  Q.Params[34].AsLargeInt := 1;
  Q.Fields[35].AsString := 'a';
  X := Q.Items[36];
  Reg(40001, 'WM_FOO');
  Reg(40002, 'WM_BAR');
  X := X * 86400;
end;

end.
