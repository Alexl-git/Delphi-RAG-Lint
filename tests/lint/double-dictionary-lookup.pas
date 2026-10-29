unit DoubleDictionaryLookup;

interface

uses
  System.Generics.Collections;

implementation

procedure P(D: TDictionary<string, Integer>; const K: string);
var
  V: Integer;
begin
  if D.ContainsKey(K) then
    V:= D[K];
  if D.ContainsKey(K) then
  begin
    V:= D.Items[K];
    Inc(V);
  end;
  if D.TryGetValue(K, V) then
    Inc(V);
  if D.ContainsKey(K) then
    D[K]:= 1;
  if D.ContainsKey(K) then
    V:= 5;
  if D.ContainsKey(K) then
    V:= D['other'];
  if D.ContainsKey(Trim(K)) then
    V:= D[Trim(K)];
  if not D.ContainsKey(K) then
    V:= 0
  else
    V:= D[K];
end;

end.
