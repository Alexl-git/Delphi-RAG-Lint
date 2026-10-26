program DispatchForms;

uses
  Vcl.Forms,
  DF.Main in 'DF.Main.pas' {frmMain},
  DF.Base in 'DF.Base.pas',
  DF.Plans in 'DF.Plans.pas',
  DF.FormA in 'DF.FormA.pas' {frmA},
  DF.FormC in 'DF.FormC.pas' {frmC},
  DF.FormD in 'DF.FormD.pas' {frmD};

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.