program HelpLineHarness;

{ Headless harness for the IDE help line (plan docs\superpowers\plans\
  2026-10-23-ide-help-line.md). Prints key=value lines that
  tests\autotest\run_plugin_help_line.ps1 asserts on, then DONE.
  Built with -DDRAGLINT_TEST_REGROOT so the settings round-trip writes
  HKCU\Software\drag-lint\DelphiPlugin.Test, never the live key.
  Arg 1: the fixture folder (index-sample.json). Arg 2: a scratch folder. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , DragLint.Plugin.Settings
  , DragLint.Plugin.HelpIndex
  ;

procedure Put(const pKey, pValue: string);
begin
  Writeln(pKey + '=' + pValue);
end; // procedure

procedure RunUrlRules;
const
  WEB = 'https://www.delphi-rag-lint.com';
  FILEROOT = 'file:///C:/dl-help';
begin
  Put('url.web', DLHelpUrl(WEB, 'ask'));
  Put('url.webslash', DLHelpUrl(WEB + '/', 'ask'));
  Put('url.file', DLHelpUrl(FILEROOT, 'ask'));
  Put('url.folder', DLHelpUrl('C:\dl-help\', 'ask'));
  Put('url.noid', DLHelpUrl(WEB, ''));
  Put('norm.folder', DLNormaliseHelpRoot('C:\dl-help\'));
  Put('norm.empty', DLNormaliseHelpRoot(''));
  Put('norm.blank', DLNormaliseHelpRoot('   '));
  Put('norm.webslash', DLNormaliseHelpRoot(WEB + '//'));
  Put('norm.filebs', DLNormaliseHelpRoot('file:///C:\dl-help\'));
  Put('norm.prefix', DLNormaliseHelpRoot('http://intranet/docs/'));
  Put('all.web', DLHelpAllUrl(WEB));
  Put('all.file', DLHelpAllUrl(FILEROOT));
  Put('ide.web', DLHelpIdeUrl(WEB));
  Put('ide.file', DLHelpIdeUrl(FILEROOT));
  Put('isfile.web', BoolToStr(DLIsFileHelpRoot(WEB), True));
  Put('isfile.folder', BoolToStr(DLIsFileHelpRoot('C:\dl-help'), True));
  Put('folder.file', DLHelpRootFolder(FILEROOT));
  Put('folder.web', DLHelpRootFolder(WEB));
  Put('default.const', DL_DEFAULT_HELP_ROOT);
end; // procedure

procedure RunSettingsRoundTrip;
var
  S: TDragLintSettings;
begin
  Put('settings.default', DefaultSettings.HelpRoot);
  S:= DefaultSettings;
  S.HelpRoot:= 'C:\dl-help\';
  SaveSettings(S);
  Put('settings.folder', LoadSettings.HelpRoot);
  S.HelpRoot:= '';
  SaveSettings(S);
  Put('settings.empty', LoadSettings.HelpRoot);
  SaveSettings(DefaultSettings);
end; // procedure

begin
  try
    RunUrlRules;
    RunSettingsRoundTrip;
    Writeln('DONE');
  except
    on E: Exception do
      Writeln('EXCEPTION=' + E.ClassName + ': ' + E.Message);
  end; // try
end.
