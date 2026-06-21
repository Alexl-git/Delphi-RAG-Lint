unit EmptyFinally;

interface

implementation

procedure P;
begin
  try
    WriteLn('x');
  finally
  end;
end;

end.
