unit ReservedWordClean;

interface

type
  TOptions = record
    &Inline: Boolean;
    Name: string;
    Index: Integer;
    Message: Integer;
  end;

function Twice(&Library: Integer; At: Integer): Integer; inline;

var
  &Type: Integer;

implementation

function Twice(&Library: Integer; At: Integer): Integer;
begin
  Result:= &Library * 2 + At;
end;

end.