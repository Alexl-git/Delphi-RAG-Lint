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
  , System.IOUtils
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

procedure WriteText(const pPath, pText: string);
begin
  ForceDirectories(ExtractFilePath(pPath));
  TFile.WriteAllText(pPath, pText, TEncoding.UTF8);
end; // procedure

procedure RunIndex(const pFixtureDir, pScratch: string);
var
  Idx: TDLHelpIndex;
  E  : TDLHelpEntry;
  Bad: string;
begin
  Idx:= TDLHelpIndex.Create;
  try
    Put('index.load', BoolToStr(Idx.LoadFromFile(TPath.Combine(pFixtureDir, 'index-sample.json')), True));
    Put('index.count', IntToStr(Idx.Count));
    Put('index.loaded', BoolToStr(Idx.Loaded, True));
    if Idx.Count = 6 then
    begin
      E:= Idx.Entries[1];
      Put('index.r1.id', E.Id);
      Put('index.r1.menus', string.Join('|', E.Menus));
      Put('index.r1.verb', E.Verb);
      E:= Idx.Entries[0];
      Put('index.r0.verb', E.Verb);
      Put('index.r0.file', E.FileName);
      E:= Idx.Entries[3];
      Put('index.r3.menus', IntToStr(Length(E.Menus)));
      Put('index.r3.context', IntToStr(Length(E.Context)));
      E:= Idx.Entries[2];
      Put('index.r2.context', string.Join('|', E.Context));
    end; // if
    { malformed JSON: no exception, Loaded False, no rows, a reason }
    Bad:= TPath.Combine(pScratch, 'bad.json');
    WriteText(Bad, '[ { "id": "x", ');
    Put('bad.load', BoolToStr(Idx.LoadFromFile(Bad), True));
    Put('bad.loaded', BoolToStr(Idx.Loaded, True));
    Put('bad.count', IntToStr(Idx.Count));
    Put('bad.error', BoolToStr(Idx.LastError <> '', True));
    Put('missing.load', BoolToStr(Idx.LoadFromFile(TPath.Combine(pScratch, 'nope.json')), True));
    { reload when size/mtime changed }
    Bad:= TPath.Combine(pScratch, 'live.json');
    WriteText(Bad, '[{"id":"a","title":"A"},{"id":"b","title":"B"}]');
    Idx.LoadFromFile(Bad);
    Put('reload.same', BoolToStr(Idx.ReloadIfChanged, True));
    WriteText(Bad, '[{"id":"a","title":"A"}]');
    Put('reload.changed', BoolToStr(Idx.ReloadIfChanged, True));
    Put('reload.count', IntToStr(Idx.Count));
  finally
    Idx.Free;
  end; // try
end; // procedure

procedure RunLocator(const pScratch: string);
var
  Eng, Off, Bpl, Dev: string;
begin
  Eng:= TPath.Combine(pScratch, 'engine');
  Off:= TPath.Combine(pScratch, 'offline');
  Bpl:= TPath.Combine(pScratch, 'repo\third_party\dll-win32');
  Dev:= TPath.Combine(pScratch, 'repo\WWW\' + DL_HELP_INDEX_REL);
  WriteText(TPath.Combine(Eng, DL_HELP_INDEX_REL), '[]');
  WriteText(TPath.Combine(Off, DL_HELP_INDEX_REL), '[]');
  WriteText(Dev, '[]');
  ForceDirectories(Bpl);
  Put('loc.engine', DLLocateHelpIndex(Eng, Off, Bpl));
  Put('loc.engine.want', TPath.Combine(Eng, DL_HELP_INDEX_REL));
  DeleteFile(TPath.Combine(Eng, DL_HELP_INDEX_REL));
  Put('loc.file', DLLocateHelpIndex(Eng, 'file:///' + Off.Replace('\', '/'), Bpl));
  Put('loc.file.want', TPath.Combine(Off, DL_HELP_INDEX_REL));
  Put('loc.webroot', DLLocateHelpIndex(Eng, DL_DEFAULT_HELP_ROOT, Bpl));
  Put('loc.dev.want', Dev);
  Put('loc.noengine', DLLocateHelpIndex('', DL_DEFAULT_HELP_ROOT, Bpl));
  DeleteFile(Dev);
  Put('loc.none', DLLocateHelpIndex(Eng, DL_DEFAULT_HELP_ROOT, Bpl + '\nowhere'));
end; // procedure

begin
  try
    RunUrlRules;
    RunSettingsRoundTrip;
    RunIndex(ParamStr(1), ParamStr(2));
    RunLocator(ParamStr(2));
    Writeln('DONE');
  except
    on E: Exception do
      Writeln('EXCEPTION=' + E.ClassName + ': ' + E.Message);
  end; // try
end.
