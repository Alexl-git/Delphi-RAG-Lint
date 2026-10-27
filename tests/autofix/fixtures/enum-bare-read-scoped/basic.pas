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
  K:= Green;
  if K = Red then Exit;
end;

end.
