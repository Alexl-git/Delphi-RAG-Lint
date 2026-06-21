unit FanIntf;

interface

uses System.SysUtils;

implementation

procedure P(Intf: IInterface; Obj: TObject);
begin
  FreeAndNil(Intf);
  FreeAndNil(Obj);
end;

end.
