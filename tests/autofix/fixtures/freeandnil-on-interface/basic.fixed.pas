unit basic;

interface

type
  IFoo = interface
  end;

implementation

uses
  System.SysUtils;

procedure Run;
var
  I: IFoo;
begin
  I := nil;
end;

end.
