unit basic;

interface

uses
  System.Classes;

procedure P;

implementation

procedure P;
var
  SL: TStringList;
begin
  try
    SL := TStringList.Create;
    SL.Add('x');
  finally
    SL.Free;
  end;
end;

end.
