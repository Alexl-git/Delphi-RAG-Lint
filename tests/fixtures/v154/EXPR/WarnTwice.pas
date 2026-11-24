unit WarnTwice;

interface

implementation

{$WARNINGS OFF}
procedure P;
begin
  Exit;
end;
{$WARNINGS ON}

{$WARNINGS OFF} // FIRE warnings-off-not-restored
procedure Q;
begin
  Exit;
end;

end.
