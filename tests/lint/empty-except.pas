unit EmptyExcept;

interface

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
  end;
end;

end.
