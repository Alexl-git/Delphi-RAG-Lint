unit GR11IncHost;
{ v151 GR11: host of GR11IncHeaders.inc; the include supplies the interface headers. }
interface
{$I GR11IncHeaders.inc}
implementation
procedure Gr11IncFirst(pN: Integer);
begin
end;
function Gr11IncSecond: Integer;
begin
  Result := 0;
end;
procedure Gr11IncLast;
begin
  Gr11IncFirst(Gr11IncSecond);
end;
end.
