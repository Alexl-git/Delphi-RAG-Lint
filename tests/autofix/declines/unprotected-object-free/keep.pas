unit keep;
interface
uses
  System.Classes;
implementation
procedure P(B: Boolean);
var
  X: TStringList;
begin
  X := TStringList.Create;
  X.Add('a');
  if B then
    Writeln('b');
  X.Add('c'); X.Free;
end;
end.
