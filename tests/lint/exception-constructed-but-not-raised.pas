unit exccreate;
interface
uses System.SysUtils;
implementation
procedure P;
var
  E: Exception;
begin
  EMyError.Create('boom');
  raise EMyError.Create('ok');
  E := Exception.Create('assigned');
  E.Free;
end;
end.
