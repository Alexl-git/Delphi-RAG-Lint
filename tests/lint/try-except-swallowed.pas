unit TryExceptSwallowed;

interface

implementation

uses System.SysUtils;

procedure Bad;
begin
  try
    Writeln('x');
  except

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

// OWNER RULING 2026-08-13: a DOCUMENTED deliberate swallow is ACCEPTED -- an
// except body that runs no code and says in writing why dropping the exception
// is the lesser evil. Appended at the END of this fixture on purpose: every
// expectation above is anchored to a line number, so a case inserted anywhere
// else would silently renumber all of them.
// Note what this does NOT accept: a handler that RUNS something and merely
// carries a comment, and a body whose only comment is a dl:ok marker. The full
// matrix lives in tests\autotest\run_swallow_documented.ps1.
procedure DocumentedSwallow;
begin
  try
    Writeln('x');
  except
    // Deliberately swallowed: this runs during finalization, where letting an
    // exception escape is worse than the work being skipped.
  end;
end;

end.
