program Demo8;
uses
  Vcl.Forms,
  uMain8 in 'uMain8.pas' {frmMain8},
  uMenuUtils8 in 'uMenuUtils8.pas',
  uDesign8 in 'uDesign8.pas' {frmDesign8},
  uReports8 in 'uReports8.pas' {frmReports8},
  uExport8 in 'uExport8.pas' {frmExport8},
  uDeep8 in 'uDeep8.pas' {frmDeep8},
  uSide8 in 'uSide8.pas' {frmSide8},
  uSideChild8 in 'uSideChild8.pas' {frmSideChild8};

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain8, frmMain8);
  Application.Run;
end.
