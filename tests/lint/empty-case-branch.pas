unit EmptyCase;

interface

implementation

procedure P(X: Integer);
begin
  case X of
    1: ;
    2: WriteLn('two');
  end;
end;

end.
