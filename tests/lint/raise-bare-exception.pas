unit RaiseBareException;

interface

uses System.SysUtils;

implementation

procedure P;
begin
  raise Exception.Create('boom');
end;

procedure Q;
begin
  raise EMyError.Create('specific');
end;

end.
