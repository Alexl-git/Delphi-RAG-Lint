unit MagicLiteralV152;

interface

implementation

procedure P(M: TObject; var S: string; X: Integer);
begin
  S := M.Groups[3].Value;
  S := M.Params[4].AsString;
  X := X * 7;
  if X > 50 then X := 0;
  Reg(1057, 'TTM_SETTITLEW');
  Set4Map(X, 0, 1, 9, 6, 6, -6, 13);
  Foo(X, 7, 9);
  Bar(3, 4, 5, 6, 7);
end;

end.