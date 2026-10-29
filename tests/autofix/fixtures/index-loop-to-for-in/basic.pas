unit basic;

interface

uses
  System.Generics.Collections;

procedure HitHigh(const A: TArray<Integer>);
procedure HitCount(L: TList<Integer>);

implementation

procedure Use(X: Integer);
begin
end;

procedure HitHigh(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Use(A[I]);
end;

procedure HitCount(L: TList<Integer>);
begin
  for var J := 0 to L.Count - 1 do
  begin
    Use(L[J]);
    Use(L.Items[J] * 2);
  end;
end;

end.
