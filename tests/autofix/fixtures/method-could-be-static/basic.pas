unit basic;

interface

type
  TFoo = class
  private
    FCount: Integer;
  public
    function Twice(S: string): string;
    procedure Bump(var N: Integer); inline;
    function Count: Integer;
  end;

implementation

function TFoo.Twice(S: string): string;
begin
  Result := S + S;
end;

procedure TFoo.Bump(var N: Integer);
begin
  N := N + 1;
end;

function TFoo.Count: Integer;
begin
  Result := FCount;
end;

end.
