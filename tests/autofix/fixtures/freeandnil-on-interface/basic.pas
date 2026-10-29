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
  FreeAndNil(I);
end;

end.
