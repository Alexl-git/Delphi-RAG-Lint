unit HaltLib;

interface

implementation

uses
  Winapi.Windows, Vcl.Forms;

procedure Bad;
begin
  Halt;
  Halt(1);
  ExitProcess(0);
  TerminateProcess(GetCurrentProcess, 0);
  Application.Terminate;
end;

procedure Good(pCode: Integer);
begin
  if pCode > 0 then Exit;
  TerminateProcess(OpenProcess(PROCESS_TERMINATE, False, 4), 0);
  Application.ProcessMessages;
  MyHalt;
  Writeln('Halt');
end;

end.
