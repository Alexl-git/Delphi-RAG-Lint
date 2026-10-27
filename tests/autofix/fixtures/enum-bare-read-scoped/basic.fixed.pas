unit basic;

interface

{$SCOPEDENUMS ON}
type
  TKind = (Red, Green);
{$SCOPEDENUMS OFF}

implementation

procedure Run;
var
  K: TKind;
begin
  K:= TKind.Green;
  if K = TKind.Red then Exit;
end;

end.
