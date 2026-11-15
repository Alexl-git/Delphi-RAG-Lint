unit write_only_local_value_param;

{ v151 WID-FLOW: write-only-local widened to by-value parameters that the
  routine stores to but never reads (the incoming value is unused AND the
  stored one is lost). }

interface

procedure StoreOnly(A: Integer);
procedure ReadThenStore(A: Integer);
procedure OutAndVar(out O: Integer; var V: Integer);

implementation

procedure StoreOnly(A: Integer);
begin
  A := 5;
end;

procedure ReadThenStore(A: Integer);
begin
  Writeln(A);
  A := 1;
end;

procedure OutAndVar(out O: Integer; var V: Integer);
begin
  O := 1;
  V := 2;
end;

end.
