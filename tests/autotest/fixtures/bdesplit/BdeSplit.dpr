program BdeSplit;

uses
  Vcl.Forms,
  BdeSplitForm in 'BdeSplitForm.pas' {FrmBdeSplit};

begin
  Application.Initialize;
  Application.CreateForm(TFrmBdeSplit, FrmBdeSplit);
  Application.Run;
end.