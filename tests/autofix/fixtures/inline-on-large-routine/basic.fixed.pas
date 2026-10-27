unit basic;

interface

procedure Big(X: Integer);

procedure Wide(X: Integer); overload;

type
  TFoo = class
  public
    procedure Heavy;
  end;

implementation

procedure Big(X: Integer);
begin
  try
    Writeln(X);
  finally
    Writeln(0);
  end;
end;

procedure Wide(X: Integer);
begin
  try
    Writeln(X);
  finally
    Writeln(1);
  end;
end;

procedure Local(X: Integer);
begin
  try
    Writeln(X);
  finally
    Writeln(2);
  end;
end;

procedure TFoo.Heavy;
begin
  try
    Writeln(3);
  finally
    Writeln(4);
  end;
end;

end.
