unit CollectionModifiedInLoop;

interface

implementation

uses
  System.Classes, System.Generics.Collections;

procedure Bad(L: TList<Integer>; Names: TStringList);
var
  I: Integer;
  V: Integer;
  S: string;
begin
  for V in L do
    if V = 0 then
      L.Remove(V);
  for S in Names do
    Names.Add(S + 'x');
  for I := 0 to L.Count - 1 do
    if L[I] = 0 then
      L.Delete(I);
  for I := 0 to Names.Count - 1 do
  begin
    if Names[I] = '' then
      Names.Delete(I);
  end;
end;

procedure Good(L: TList<Integer>; Other: TList<Integer>);
var
  I: Integer;
  V: Integer;
begin
  for I := L.Count - 1 downto 0 do
    if L[I] = 0 then
      L.Delete(I);
  for V in L do
    Other.Add(V);
  for I := 0 to L.Count - 1 do
    Other.Delete(I);
end;

end.
