program App;

{ Fixture of lane GCR-2 (drag-lint 1.56). The folder of the project file is where the modules of a form are looked
  for; like many real projects it lists only the main form, the other units come through the search path. }

uses
  Vcl.Forms,
  uForm in 'uForm.pas' {frmMain};

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
