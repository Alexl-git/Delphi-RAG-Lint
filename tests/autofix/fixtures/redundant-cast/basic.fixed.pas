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
  SL.Add('x');
  SL.Free;
end;

end.
