unit basic;

interface

implementation

uses
  System.Classes;

procedure P;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  TStringList(SL).Add('x');
  SL.Free;
end;

end.
