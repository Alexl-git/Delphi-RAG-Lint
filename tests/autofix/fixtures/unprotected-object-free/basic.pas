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
  X.Add('a');
  Writeln(X.Count);
  X.Free;
end;

end.
