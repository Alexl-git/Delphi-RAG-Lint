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
  SL.Create;
  Q.Create(True);
end;

end.
