program HandlersOrder;

{ check-init fixture handlers-order (lane HBEVORD, ruling HB5). The program block writes GCfg BEFORE
  Application.Run and GLate only AFTER it (the MAY twin). TMainForm is auto-created in the prefix;
  TLaterForm is created at run time by a button handler (its handlers stay unordered). }

uses
  Vcl.Forms,
  hoData in 'hoData.pas',
  hoMain in 'hoMain.pas' {MainForm},
  hoLater in 'hoLater.pas' {LaterForm};

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  GCfg:= 1;
  Application.Run;
  GLate:= 1;
end.
