unit IndexofResultUnchecked;

interface

implementation

uses
  System.Classes, System.SysUtils;

procedure Bad(L: TStringList; const S: string);
var
  Z: string;
begin
  Z := L[L.IndexOf(S)];
  Z := L.Strings[L.IndexOf(S)];
  L.Delete(L.IndexOf(S));
  L.Objects[L.IndexOf(S)] := nil;
  L.Exchange(0, L.IndexOfName(S));
  Z := S[Pos('x', S)];
end;

procedure Good(L: TStringList; const S: string);
var
  I: Integer;
  Z: string;
begin
  I := L.IndexOf(S);
  if I >= 0 then
    Z := L[I];
  if L.IndexOf(S) >= 0 then
    L.Delete(0);
  Z := L[0];
  Z := Copy(S, 1, 2);
end;

end.
