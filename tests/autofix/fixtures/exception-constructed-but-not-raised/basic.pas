unit basic;

interface

uses
  System.SysUtils;

type
  EMyError = class(Exception);

procedure P;

implementation

procedure P;
begin
  EMyError.Create('boom');
end;

end.
