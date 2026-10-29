unit basic;

interface

type
  TFoo = class
  public
    function Twice(S: string; var N: Integer): string;
    function Join(
      A: string;
      Sep: string): string;
  end;

function Echo(S: string): string;

implementation

function TFoo.Twice(S: string; var N: Integer): string;
begin
  Inc(N);
  Result := S + S;
end;

function TFoo.Join(
  A: string;
  Sep: string): string;
begin
  Result := A + Sep;
end;

function Echo(S: string): string;
begin
  Result := S;
end;

end.
