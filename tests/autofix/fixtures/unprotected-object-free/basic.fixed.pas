unit basic;

interface

uses
  System.Classes;

procedure P;

implementation

procedure P;
var
  X: TStringList;
begin
  X := TStringList.Create;
  try
    X.Add('a');
    Writeln(X.Count);
  finally
    X.Free;
  end;
end;

end.
