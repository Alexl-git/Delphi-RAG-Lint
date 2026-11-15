unit RepeatedElseIfImplied;
{ repeated-else-if-condition, implied shape: a later condition that can only
  hold when an earlier one of the same chain already held. }
interface
function Pick(pA, pB, pC: Boolean): Integer;
implementation
function Pick(pA, pB, pC: Boolean): Integer;
begin
  if pA or pB then
    Result := 1
  else if pA then
    Result := 2
  else if pC and pB then
    Result := 3
  else if (pB or pA) then
    Result := 4
  else
    Result := 0;
end;
end.
