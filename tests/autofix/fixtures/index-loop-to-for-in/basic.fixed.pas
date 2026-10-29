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
begin
  for var LItem in A do
    Use(LItem);
end;

procedure HitCount(L: TList<Integer>);
begin
  for var LItem in L do
  begin
    Use(LItem);
    Use(LItem * 2);
  end;
end;

end.
