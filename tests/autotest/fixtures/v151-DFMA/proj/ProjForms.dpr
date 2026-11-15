program ProjForms;

uses
  Vcl.Forms,
  UMain in 'UMain.pas' {MainForm},
  UDm in 'UDm.pas' {dmMain: TDataModule},
  UReport in 'UReport.pas' {ReportForm},
  UOrphan in 'UOrphan.pas' {OrphanForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TdmMain, dmMain);
  Application.CreateForm(TReportForm, ReportForm);
  // Application.CreateForm(TOrphanForm, OrphanForm);
  Application.Run;
end.
