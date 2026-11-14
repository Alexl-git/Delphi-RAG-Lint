unit GR11Labels;
{ v151 GR11: numeric labels and goto (grammar v1.4.11, a literalNumber where an
  identifier stood). Indexed twice: as is, and with GR11_ALT defined. }
interface
function Gr11Jump(pN: Integer): Integer;
function Gr11Pick(pN: Integer): Integer;
implementation
function Gr11Jump(pN: Integer): Integer;
label
  99, Gr11Done;
begin
  Result := 0;
  if pN > 0 then
    goto 99;
{$IFDEF GR11_ALT}
  Result := 1;
  goto Gr11Done;
{$ELSE}
  Result := 2;
{$ENDIF}
  99:
  Result := Result + pN;
  Gr11Done:
end;
function Gr11Pick(pN: Integer): Integer;
begin
  case pN of
    7: Result := 70;
  else
    Result := 0;
  end;
end;
end.
