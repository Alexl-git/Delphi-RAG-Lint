unit IncDB;

interface

uses
  IncDA;

procedure UseIncDB;

implementation

procedure UseIncDB;
var
  R: TIncDARec;
begin
  R.X := 1;
end;

end.