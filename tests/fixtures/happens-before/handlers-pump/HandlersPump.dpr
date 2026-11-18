program HandlersPump;

{ check-init fixture handlers-pump (lane HBEVORD): the program block pumps messages BEFORE it writes
  GPump, so a handler of the auto-created form can run before the write: btnPumpClick is MAY-BE-UNSET
  although GPump is written before Application.Run (the twin of handlers-order's SET). }

uses
  Vcl.Forms,
  hpData in 'hpData.pas',
  hpMain in 'hpMain.pas' {PumpForm};

begin
  Application.Initialize;
  Application.CreateForm(TPumpForm, PumpForm);
  Application.ProcessMessages;
  GPump:= 1;
  Application.Run;
end.
