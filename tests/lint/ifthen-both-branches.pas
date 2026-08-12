unit IfThenBoth;

interface

implementation

uses SysUtils, StrUtils;

function Expensive: Integer;
begin
  Result := 42;
end;

function ExpensiveMessage: string;
begin
  Result := 'x';
end;

procedure Bad;
var
  B: Boolean;
  N: Integer;
begin
  N := IfThen(B, Expensive, 0);
  N := IfThen(B, 1, Expensive);
end;

procedure Good;
var
  B: Boolean;
  N: Integer;
begin
  if B then
    N := Expensive
  else
    N := 0;
end;

// Task 9b: both branches are literals -- a literal cannot have a side
// effect, so the rule's rationale is inapplicable (YADF.Options.pas:850,879).
procedure GoodBothLiteral;
var
  B: Boolean;
  S: string;
begin
  S := IfThen(B, 'true', 'false');
end;

// Post-merge review regression fix: StrUtils.IfThen's string overload
// declares 'AFalse: string = ''''', so the 2-argument call is valid,
// idiomatic Delphi -- NOT a malformed 3-arg call. The 3-arg patterns cannot
// match it (both require a 3rd child that does not exist here), so it needs
// its own pattern. A non-literal single value branch is a genuine
// unconditionally-evaluated side effect -- still fires.
procedure BadTwoArg;
var
  B: Boolean;
  S: string;
begin
  S := IfThen(B, ExpensiveMessage);
end;

// The 2-arg counterpart to GoodBothLiteral: the single value branch is a
// literal -- no finding.
procedure GoodTwoArgLiteral;
var
  B: Boolean;
  S: string;
begin
  S := IfThen(B, 'literal');
end;

end.
