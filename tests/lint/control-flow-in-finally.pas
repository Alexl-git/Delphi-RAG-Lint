unit ControlFlowInFinally;

interface

implementation

procedure P;
begin
  try
    WriteLn('x');
  finally
    Exit;
  end;
end;

procedure Q;
begin
  try
    Exit;
  finally
    WriteLn('cleanup');
  end;
end;

end.
