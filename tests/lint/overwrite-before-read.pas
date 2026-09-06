unit overwritebeforeread;
interface
implementation
procedure P;
var x: Integer;
begin
  x := 1;
  x := 2;
  Writeln(x);
end;

{ A store whose value is consumed only inside a NESTED routine is not dead. A
  nested routine closes over the enclosing locals, and the CFG deliberately does
  not descend into one (DRagLint.Analysis.Cfg), so liveness cannot see that
  read. Reporting it fires precisely when someone does what method-too-long and
  cyclomatic-complexity ask for -- in Delphi the cheapest correct extraction is
  a nested routine, because it closes over the locals and so needs no
  parameters and cannot trip too-many-parameters.

  The shape matters. `cap` must also be read in the BODY (the `if`), or
  ReadAny[cap] is false and the rule skips it entirely, handing it to
  write-only-local -- which already honours the Captured flag. The defect only
  shows on a LATER store whose value nothing in the body consumes.

  `dead` is the control that makes this a per-VARIABLE claim rather than
  "routines containing a nested routine are exempt": UseIt never mentions
  `dead`, so its dead store must still be reported. }
procedure Q;
var
  cap : Integer;
  dead: Integer;

  procedure UseIt;
  begin
    Writeln(cap);
  end;

begin
  cap := 1;
  if cap <= 0 then
    cap := 2;
  dead := 1;
  dead := 2;
  Writeln(dead);
  UseIt;
end;
end.
