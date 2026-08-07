unit usedbeforeassignmentclean;
interface
implementation
function F3(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1 else x := 2;
  Result := x;
end;
function F4: string;
var s: string;
begin
  Result := s;
end;
{ B1/B9 -- the DataCopy CopyFileVerified shape, and the reason both defects were
  filed. n is assigned inside the try; the guard clause above it and the except
  handler below it both END IN exit, so neither can deliver an unassigned n to
  the code after the try. It read as "may be used before it is assigned" because
  the try body was emitted into the CFG twice AND because `exit;` never
  diverted -- two independent defects landing on one line. }
function F5(const s: string): Integer;
var n: Integer;
begin
  Result := 0;
  try
    if s = '' then exit;
    n := 5;
  except
    on E: Exception do exit;
  end;
  if n > 0 then
    Result := n;
end;
end.
