unit basic;

interface

implementation

uses
  System.Classes;

procedure Bad;
var
  SL: TStringList;
  Q: TStringList;
begin
  SL := TStringList.Create;
  Q := TStringList.Create(True);
end;

end.
