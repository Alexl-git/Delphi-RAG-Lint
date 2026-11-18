unit ReservedWordFire;

interface

type
  TOptions = record
    Inline: Boolean;
    Count: Integer;
  end;

procedure Configure(Library: string; const Value: Integer);

var
  Inline: Integer;

implementation

procedure Configure(Library: string; const Value: Integer);
begin
end;

end.