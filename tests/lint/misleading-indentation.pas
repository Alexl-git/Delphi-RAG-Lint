unit MisleadingIndentation;

interface

implementation

procedure P(X: Integer; var R: Integer);
begin
  if X > 0 then
    R:= 1;
    R:= 2;
  if X > 1 then
    R:= 3;
  R:= 4;
  if X > 2 then R:= 5;
    R:= 6;
  while X > 0 do
    Dec(X);
    Inc(R);
  if X > 3 then
  begin
    R:= 7;
  end;
    R:= 8;
  if X > 4 then R:= 9; R:= 10;
  if X > 5 then
    R:= 11
  else
    R:= 12;
end;

procedure Tabbed(X: Integer; var R: Integer);
begin
	if X > 0 then
		R:= 1;
		R:= 2;
	if X > 1 then
		R:= 3;
	R:= 4;
end;

procedure Directive(X: Integer; var R: Integer);
begin
  if X > 0 then R:= 1;
  {$IFDEF NEVER_DEFINED_L6}R:= 2;{$ENDIF}
  if X > 1 then R:= 3;
  {$IFDEF DEBUG}R:= 4;{$ENDIF}
end;

end.
