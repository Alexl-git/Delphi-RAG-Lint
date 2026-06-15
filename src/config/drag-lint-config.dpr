program drag_lint_config;

{$APPTYPE GUI}

uses
  Winapi.Windows,
  Vcl.Forms,
  System.SysUtils,
  System.Classes,
  DRagLint.Index.Manifest in '..\index\DRagLint.Index.Manifest.pas',
  DRagLint.Index.Plan in '..\index\DRagLint.Index.Plan.pas',
  DRagLint.Project.Resolver in '..\project\DRagLint.Project.Resolver.pas',
  Config.MainForm in 'Config.MainForm.pas' {MainForm},
  Config.IndexesFrame in 'Config.IndexesFrame.pas' {IndexesFrame: TFrame},
  Config.SettingsFrame in 'Config.SettingsFrame.pas' {SettingsFrame: TFrame},
  Config.EngineRunner in 'Config.EngineRunner.pas';

const
  VERSION = '0.45.0-alpha';

begin
  if FindCmdLineSwitch('version') or (ParamStr(1) = '--version') then
  begin
    AllocConsole;
    Writeln('drag-lint-config ' + VERSION);
    ExitCode := 0;
    Exit;
  end;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
