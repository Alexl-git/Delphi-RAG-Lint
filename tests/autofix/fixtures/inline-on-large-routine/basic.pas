unit basic;

interface

procedure Big(X: Integer); inline;

procedure Wide(X: Integer); inline; overload;

type
  TFoo = class
  public
    procedure Heavy;
      inline;
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

procedure Local(X: Integer); inline;
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
