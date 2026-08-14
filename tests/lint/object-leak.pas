unit objectleak;
interface
uses System.Classes;
implementation
procedure P1;
var o: TStringList;
begin
  o := TStringList.Create;
  o.Add('x');
end;
procedure P2;
var o: TStringList;
begin
  o := TStringList.Create;
  try o.Add('x'); finally o.Free; end;
end;
function P3: TStringList;
begin
  Result := TStringList.Create;
end;
procedure P4(aList: TStrings);
var o: TStringList;
begin
  o := TStringList.Create;
  aList.AddObject('x', o);
end;
{ B9: a guard clause inside a try..FINALLY. Delphi runs the finally before the
  exit leaves, so o IS freed on that path -- the CFG has to replay the finally
  on the divert path or this reads as a leak. }
procedure P5(b: Boolean);
var o: TStringList;
begin
  o := TStringList.Create;
  try
    if b then exit;
    o.Add('x');
  finally
    o.Free;
  end;
end;
{ same for break, which leaves a loop the try..finally sits INSIDE }
procedure P6(b: Boolean);
var i: Integer; o: TStringList;
begin
  for i := 0 to 2 do
  begin
    o := TStringList.Create;
    try
      if b then break;
      o.Add('x');
    finally
      o.Free;
    end;
  end;
end;
{ CONTROL: the exit is OUTSIDE the try, so nothing frees o on that path -- a
  real leak that must still be reported, or the replay has been over-applied }
procedure P7(b: Boolean);
var o: TStringList;
begin
  o := TStringList.Create;
  if b then exit;
  o.Free;
end;
{ P8 -- the try..FINALLY that frees o is wrapped in a try..EXCEPT. Measured
  2026-08-13: this fired while the identical code WITHOUT the outer except did
  not, and swapping the outer except for a finally also did not. Cause is the
  tryEntry->handler edge, which models "the exception fired before the body
  ran" and so skips the inner finally. o IS freed on every real path. }
procedure P8;
var o: TStringList;
begin
  try
    o := TStringList.Create;
    try
      o.Add('x');
    finally
      o.Free;
    end;
  except
    Writeln('e');
  end;
end;
{ P9 CONTROL -- same outer try..except, but nothing ever frees o. If P8's fix
  were "anything inside a try..except is fine", this would go quiet too. It is
  the case that proves the guard is keyed on the finally and not on the except. }
procedure P9;
var o: TStringList;
begin
  try
    o := TStringList.Create;
    o.Add('x');
  except
    Writeln('e');
  end;
end;
end.
