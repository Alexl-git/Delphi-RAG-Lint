unit BareExcept;

interface

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
    WriteLn('oops');
  end;
end;

end.
