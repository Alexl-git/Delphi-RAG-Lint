program App;

uses
  Vcl.Forms,
  UMain in 'UMain.pas' {MainForm},
  UUsed in 'UUsed.pas',
  UDiReg in 'UDiReg.pas',
  UDeadUnit in 'UDeadUnit.pas',
  UDeadForm in 'UDeadForm.pas' {DeadForm},
  UDeadFormInit in 'UDeadFormInit.pas' {DeadFormInit},
  UNamedForm in 'UNamedForm.pas' {NamedForm};

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.