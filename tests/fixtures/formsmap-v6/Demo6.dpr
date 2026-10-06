program Demo6;
uses
  Vcl.Forms,
  uMain6 in 'uMain6.pas' {frmMain6},
  uGroups6 in 'uGroups6.pas' {frmGroups6},
  uGroupEdit6 in 'uGroupEdit6.pas' {frmGroupEdit6},
  uEdit6 in 'uEdit6.pas' {frmEdit6},
  uReports6 in 'uReports6.pas' {frmReports6},
  uNag6 in 'uNag6.pas' {frmNag6},
  uLonely6 in 'uLonely6.pas' {frmLonely6},
  uLog6 in 'uLog6.pas' {frmLog6},
  uHelpers6 in 'uHelpers6.pas',
  uImport6 in 'uImport6.pas' {frmImport6},
  uImportVM6 in 'uImportVM6.pas',
  uMdi6 in 'uMdi6.pas' {frmMdi6},
  uPanel6 in 'uPanel6.pas' {frmPanel6},
  uSerial6 in 'uSerial6.pas' {frmSerial6},
  uCache6 in 'uCache6.pas' {frmCache6},
  uPopup6 in 'uPopup6.pas' {frmPopup6};

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain6, frmMain6);
  Application.Run;
end.