unit BareExceptReraise;

interface

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
    WriteLn('rollback');
    raise;
  end;
  try
    WriteLn('y');
  except
    raise;
  end;
  try
    WriteLn('z');
  except
    raise;
    WriteLn('unreachable');
  end;
  try
    WriteLn('w');
  except
    WriteLn('swallowed');
  end;
end;

end.