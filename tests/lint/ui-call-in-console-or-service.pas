program UiCallConsole;

{$APPTYPE CONSOLE}

uses
  Vcl.Dialogs, System.SysUtils, Vcl.Forms;

procedure Report;
begin
  ShowMessage('done');
  if MessageDlg('ok?', mtInformation, [mbOK], 0) = 0 then
    Writeln('x');
  Application.MessageBox('a', 'b', 0);
end;

begin
  Report;
end.
