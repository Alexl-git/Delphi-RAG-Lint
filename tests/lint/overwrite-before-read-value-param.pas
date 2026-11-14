unit overwrite_before_read_value_param;

{ v151 WID-FLOW: the dead-store checks widened from locals to by-value
  parameters. A value parameter is the routine's own copy, so a store to it
  that is never read is lost exactly like a local's. }

interface

procedure StoreNeverRead(A: Integer);
procedure OverwrittenBeforeRead(A: Integer);
procedure ReadAfterStore(A: Integer);
procedure ConstAndVar(const C: Integer; var V: Integer);

implementation

procedure StoreNeverRead(A: Integer);
begin
  A := 5;
end;

procedure OverwrittenBeforeRead(A: Integer);
begin
  A := 5;
  A := 6;
  Writeln(A);
end;

procedure ReadAfterStore(A: Integer);
begin
  if A < 0 then
    A := 0;
  Writeln(A);
end;

procedure ConstAndVar(const C: Integer; var V: Integer);
begin
  V := C;
  V := C + 1;
end;

end.
