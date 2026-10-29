unit nested;

interface

implementation

procedure P(B: Boolean);
begin
  if B then OutputDebugString('x')
  else Exit;
  if B then OutputDebugString('y');
  try
    OutputDebugString('t');
  finally
    OutputDebugString('f');
  end;
end;

end.
