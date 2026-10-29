unit basic;

interface

uses
  System.Generics.Collections;

implementation

procedure Run(D: TDictionary<string, Integer>; const K: string);
var
  V: Integer;
begin
  if D.ContainsKey(K) then
    V:= D[K];
  if D.ContainsKey(K) then
  begin
    V:= D[K];
    Inc(V);
  end;
end;

end.
