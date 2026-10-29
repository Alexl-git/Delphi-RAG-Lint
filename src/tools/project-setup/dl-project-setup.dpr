program dl_project_setup;

{ Writes <ProjectBase>.dlcontext.json for a project that has only a .dpr.
  Usage: dl-project-setup.exe [App.dpr] [/smoke]   (/smoke: open the form, then close) }

uses
  Vcl.Forms,
  System.SysUtils, System.IOUtils,
  ProjectSetup.ContextJson in 'ProjectSetup.ContextJson.pas',
  ProjectSetup.MainForm in 'ProjectSetup.MainForm.pas';

var
  gForm: TSetupForm;
  gFile: string;
  i: Integer;
  gSmoke: Boolean;

{$R 'dl-project-setup.res'}

begin
  gFile := '';
  gSmoke := False;
  for i := 1 to ParamCount do
    if SameText(ParamStr(i), '/smoke') then
      gSmoke := True
    else if gFile = '' then
      gFile := ParamStr(i);
  Application.Initialize;
  gForm := TSetupForm.CreateSetup(Application, gFile);
  if gSmoke then
  begin
    gForm.Show;
    Application.ProcessMessages;
    TFile.WriteAllText(ParamStr(0) + '.smoke.txt', 'SMOKE form-opened visible=' + BoolToStr(gForm.Visible, True));
    gForm.Close;
  end
  else
    gForm.ShowModal;
end.
