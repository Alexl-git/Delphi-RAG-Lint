unit ForBoundModifiedInBody;

interface

implementation

procedure Hit1(List: TStrings);
var
  I, N: Integer;
begin
  N := List.Count;
  for I := 0 to N - 1 do // HIT bound N changes
  begin
    if List[I] = '' then
      Dec(N);
  end;
end;

procedure Hit2;
var
  I: Integer;
begin
  for I := 0 to 9 do // HIT loop variable is changed
  begin
    if Odd(I) then
      Inc(I);
  end;
end;

procedure Hit3(Last: Integer);
var
  I: Integer;
begin
  for I := 1 to Last do // HIT bound assigned
    Last := Last + 1;
end;

procedure NoHit1(Last: Integer);
var
  I, J: Integer;
begin
  { FP shape: the body changes a different variable }
  J := 0;
  for I := 0 to Last do
    Inc(J);
end;

procedure NoHit2(List: TStrings);
var
  I: Integer;
begin
  { FP shape: member access on the bound owner is not an assignment to the bound }
  for I := List.Count - 1 downto 0 do
    List.Delete(I);
end;

procedure NoHit3(Last: Integer);
var
  I: Integer;
begin
  { FP shape: nested loop reuses the name of a changed variable only in its own header }
  for I := 0 to Last do
    WriteLn(I);
end;

end.
