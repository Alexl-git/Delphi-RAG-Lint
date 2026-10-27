unit basic;

interface

uses
  System.Generics.Collections;

implementation

procedure Run(D: TDictionary<string, Integer>; const K: string);
var
  V: Integer;
begin
  D.TryGetValue(K, V);
  if D.TryGetValue(K, V) then
  begin
    Inc(V);
  end;
end;

end.
