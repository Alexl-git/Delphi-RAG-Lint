program App;
uses
  Vcl.Forms,
  uMain in 'uMain.pas' {frmMain},
  uJoin in 'uJoin.pas' {frmJoin},
  uTools in 'uTools.pas';
begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
