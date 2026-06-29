unit StringEqualityNumeric;

interface

implementation

procedure P;
var
  A, B: Integer;
begin
  { Numeric equality comparison using '=' is normal Delphi code.
    The string-equality-comparison rule should not fire here because
    neither operand is string-typed. This is a false positive that occurs
    because the rule fires on all '=' operators, not just string comparisons. }
  if A = B then
    WriteLn('equal');
  if A = 42 then
    WriteLn('magic');
end;

end.
