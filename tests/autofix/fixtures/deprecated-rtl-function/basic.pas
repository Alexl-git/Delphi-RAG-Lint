unit basic;

interface

implementation

procedure Run(P: PChar);
var
  S: string;
begin
  S:= StrPas(P);
  S:= StrPas(P) + 'x';
  if S <> '' then Exit;
end;

end.
