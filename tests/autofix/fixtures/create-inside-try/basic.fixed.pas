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
  SL := TStringList.Create;
  try
    SL.Add('x');
  finally
    SL.Free;
  end;
end;

end.
