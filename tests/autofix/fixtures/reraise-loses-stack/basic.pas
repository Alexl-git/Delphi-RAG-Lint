unit basic;

interface

implementation

procedure P;
begin
  try
    DoIt;
  except
    on E: Exception do raise E;
  end;
end;

end.
