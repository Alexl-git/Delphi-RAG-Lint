unit AppTermLib;

interface

implementation

uses
  Vcl.Forms;

procedure Bad;
begin
  Application.Terminate;
end;

procedure Good;
begin
  Application.ProcessMessages;
  Timer.Terminate;
  Halt;
end;

end.
