unit IncDeclE;

interface

uses
  IncDeclD;

procedure UseD;

implementation

procedure UseD;
var
  LBaz: TBaz;
  LHid: THiddenD;
  N: Integer;
begin
  LBaz := TBaz.Create;
  R;
  N := cImplD;
  ImplR;
end;

end.
