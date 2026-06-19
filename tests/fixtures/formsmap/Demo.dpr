program Demo;
uses
  Vcl.Forms,
  uDemoMain in 'uDemoMain.pas' {frmMain},
  uDemoList in 'uDemoList.pas' {frmList},
  uDemoEdit in 'uDemoEdit.pas' {frmEdit},
  uDemoChild in 'uDemoChild.pas' {frmChild},
  uDemoReports in 'uDemoReports.pas' {frmReports},
  uDemoGap in 'uDemoGap.pas' {frmGap},
  uDemoUnreached in 'uDemoUnreached.pas' {frmLonely},
  uDemoData in 'uDemoData.pas' {dmDemo: TDataModule};

procedure RunAdminBootstrap;
begin
  Application.CreateForm(TfrmEdit, frmEdit);
end;

begin
  Application.Initialize;
  Application.CreateForm(TdmDemo, dmDemo);
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
