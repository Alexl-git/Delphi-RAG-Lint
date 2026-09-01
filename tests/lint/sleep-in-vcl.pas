unit SleepInVcl;

interface

implementation

uses Vcl.Forms;

procedure Bad;
begin
  Sleep(500);
  Sleep(0);
end;

procedure Good;
begin
  // no Sleep call here
end;

end.
