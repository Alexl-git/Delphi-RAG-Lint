unit basic;

interface

implementation

procedure Run(P: PChar);
var
  S: string;
begin
  S:= string(P);
  S:= string(P) + 'x';
  if S <> '' then Exit;
end;

end.
