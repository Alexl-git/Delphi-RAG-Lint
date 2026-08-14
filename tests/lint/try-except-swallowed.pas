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

// v(2026-08-13b): a CALL carrying the exception's own text is reporting, even
// when the sink's name matches none of the known substrings. DoIniStatus is
// YADF's status-line sink -- no 'log', no 'report', no 'message' in the NAME.
// Appended at the END for the reason stated above: the expectations are
// line-anchored.
procedure GoodUnknownSinkReports;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      DoIniStatus('  (save failed: ' + E.Message + ')');
  end;
end;

// The other half of the same rule, and the reason the test above is restricted
// to a CALL: handing E.Message to a plain LOCAL is still a swallow. Nothing
// outside the routine can observe it. This is Task 9c's LocalOnly case with the
// exception actually touched, which is the shape a naive ".Message means it was
// reported" check would wrongly clear.
procedure LocalOnlyFromException;
var
  Dummy: string;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      Dummy := E.Message;
  end;
end;

// v(2026-08-13b): writing the exception THROUGH another object is reporting --
// this is a VCL memo, so the text lands on screen. Same observability test as
// Task 9c, applied to a member access instead of a call.
procedure GoodFieldReports;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      FResult.Text := '[Format error] ' + E.ClassName + ': ' + E.Message;
  end;
end;

// ...and the guard that keeps the rule's teeth: a field write that does NOT
// carry the exception is still a swallow. Without this, "any exprDot LHS counts
// as handling" would pass the test above while silently gutting the rule.
procedure FieldWriteWithoutException;
begin
  try
    Writeln('x');
  except
    FResultStat.Caption := 'error';
  end;
end;

// v(2026-08-13c): `exit(X)` is "assign Result, then return" -- the same TryXxx
// conversion Task 9c accepts as `Result := False`, in the spelling Delphi code
// actually uses. Measured on DataCopy: 3 of 5 surviving findings were this.
function GoodExitWithValue: Boolean;
begin
  try
    Writeln('x');
  except
    exit(False);
  end;
  Result := True;
end;

// The control: a BARE `exit;` returns without saying anything, so it is still
// the swallow this rule exists to catch. Without this case, matching on the
// word "exit" alone would pass the test above and quietly widen the rule.
procedure BareExitIsStillASwallow;
begin
  try
    Writeln('x');
  except
    exit;
  end;
end;

end.
