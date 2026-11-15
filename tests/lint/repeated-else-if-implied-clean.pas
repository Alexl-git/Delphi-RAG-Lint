unit RepeatedElseIfImpliedClean;
{ look-alikes: a later condition WIDER than an earlier one (pA or pC after pA),
  a conjunction whose operands were never conditions on their own, and an
  operand that appeared only inside an earlier conjunction. }
interface
function Pick(pA, pB, pC: Boolean): Integer;
implementation
function Pick(pA, pB, pC: Boolean): Integer;
begin
  if pA then
    Result := 1
  else if pA or pC then
    Result := 2
  else if pB and not pA then
    Result := 3
  else if pB then
    Result := 4
  else
    Result := 0;
end;
end.
