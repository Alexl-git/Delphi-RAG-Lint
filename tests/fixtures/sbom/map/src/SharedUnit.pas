unit SharedUnit;

interface

procedure Shared;

implementation

uses
  System.SysUtils;

procedure Shared;
begin
  Writeln(Format('%s', ['x']));
end;

end.
