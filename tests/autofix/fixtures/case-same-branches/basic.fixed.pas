unit basic;

interface

implementation

procedure Run(X: Integer; var R: Integer);
begin
  case X of
    1, 3: R:= 10;
    2: R:= 20;
  end;
end;

end.
