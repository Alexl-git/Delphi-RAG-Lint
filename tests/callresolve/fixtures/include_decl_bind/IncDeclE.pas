unit IncDeclE;

interface

uses
  IncDeclD;

procedure UseD;

implementation

procedure UseD;
var
  LBaz: TBaz;
begin
  LBaz := TBaz.Create;
  R;
end;

end.
