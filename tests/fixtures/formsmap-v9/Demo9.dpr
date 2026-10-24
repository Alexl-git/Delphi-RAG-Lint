program Demo9;
uses
  Vcl.Forms,
  uMain9 in 'uMain9.pas' {frmMain9},
  uBarUtils9 in 'uBarUtils9.pas',
  uGridPopup9 in 'uGridPopup9.pas',
  uA9 in 'uA9.pas' {frmA9},
  uB9 in 'uB9.pas' {frmB9},
  uC9 in 'uC9.pas' {frmC9},
  uD9 in 'uD9.pas' {frmD9},
  uE9 in 'uE9.pas' {frmE9},
  uF9 in 'uF9.pas' {frmF9};

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain9, frmMain9);
  Application.Run;
end.
