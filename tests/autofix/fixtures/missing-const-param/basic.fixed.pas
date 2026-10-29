unit basic;

interface

type
  TFoo = class
  public
    function Twice(const S: string; var N: Integer): string;
    function Join(
      const A: string;
      const Sep: string): string;
  end;

function Echo(const S: string): string;

implementation

function TFoo.Twice(const S: string; var N: Integer): string;
begin
  Inc(N);
  Result := S + S;
end;

function TFoo.Join(
  const A: string;
  const Sep: string): string;
begin
  Result := A + Sep;
end;

function Echo(const S: string): string;
begin
  Result := S;
end;

end.
