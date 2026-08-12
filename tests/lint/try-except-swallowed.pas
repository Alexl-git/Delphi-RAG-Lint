unit TryExceptSwallowed;

interface

implementation

uses System.SysUtils;

procedure Bad;
begin
  try
    Writeln('x');
  except
    // swallowed -- nothing here
  end;
end;

procedure GoodReraise;
begin
  try
    Writeln('x');
  except
    raise;
  end;
end;

procedure GoodLog;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      LogError(E.Message);
  end;
end;

// Task 9c: assigning Result IS handling -- the standard Delphi TryXxx shape.
function GoodResultAssign: Boolean;
begin
  Result := True;
  try
    Writeln('x');
  except
    Result := False;
  end;
end;

// Task 9c: assigning an out parameter IS handling.
procedure GoodOutParamAssign(out AOK: Boolean);
begin
  try
    Writeln('x');
  except
    AOK := False;
  end;
end;

// Task 9c: assigning only a LOCAL is NOT handling -- nothing outside the
// routine can observe it, so this is still the swallow the rule exists to
// catch.
procedure LocalOnly;
var
  Dummy: Boolean;
begin
  try
    Writeln('x');
  except
    Dummy := False;
  end;
end;

end.
