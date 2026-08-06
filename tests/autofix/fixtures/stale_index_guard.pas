unit stale_index_guard;

interface

const
  glyActive = 1;

procedure SetLimit(ALimit: Integer);
procedure ApplyLimit;

implementation

procedure SetLimit(ALimit: Integer);
begin
end;

procedure ApplyLimit;
var
  Err: Boolean;
begin
  Err := False;
  if not Err then
    SetLimit(0)
  else
    SetLimit(glyActive);
end;

end.
