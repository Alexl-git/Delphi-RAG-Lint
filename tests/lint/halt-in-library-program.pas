program HaltProg;

uses
  Winapi.Windows, Vcl.Forms;

begin
  Halt(2);
  ExitProcess(0);
  Application.Terminate;
end.
