unit basic;

interface

type
  TFoo = class
  private
    FCount: Integer;
  public
    class function Twice(S: string): string; static;
    class procedure Bump(var N: Integer); static; inline;
    function Count: Integer;
  end;

implementation

class function TFoo.Twice(S: string): string;
begin
  Result := S + S;
end;

class procedure TFoo.Bump(var N: Integer);
begin
  N := N + 1;
end;

function TFoo.Count: Integer;
begin
  Result := FCount;
end;

end.
