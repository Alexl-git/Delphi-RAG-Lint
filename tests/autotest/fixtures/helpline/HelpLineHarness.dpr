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
  , DragLint.Plugin.JobQueue
  , DragLint.Plugin.QueueText
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

function HitList(const pHits: TArray<TDLHelpHit>): string;
begin
  Result:= '';
  for var H in pHits do
  begin
    if Result <> '' then Result:= Result + '|';
    Result:= Result + H.Id + ':' + IntToStr(H.Rank);
  end; // for
end; // function

procedure RunMatcher(const pFixtureDir: string);
var
  Idx : TDLHelpIndex;
  Rows: TArray<TDLHelpEntry>;
  Many: TArray<TDLHelpEntry>;
begin
  Idx:= TDLHelpIndex.Create;
  try
    Idx.LoadFromFile(TPath.Combine(pFixtureDir, 'index-sample.json'));
    Rows:= Idx.Entries;
  finally
    Idx.Free;
  end; // try
  Put('match.empty', IntToStr(Length(DLHelpMatch('', Rows))));
  Put('match.blank', IntToStr(Length(DLHelpMatch('   ', Rows))));
  Put('match.cyc', HitList(DLHelpMatch('cyc', Rows)));
  Put('match.CYC', HitList(DLHelpMatch('  CYC ', Rows)));
  Put('match.summary', HitList(DLHelpMatch('never searched', Rows)));
  Put('match.title', HitList(DLHelpMatch('about', Rows)));
  SetLength(Many, 20);
  for var I:= 0 to High(Many) do
  begin
    Many[I]:= Rows[0];
    Many[I].Id:= Format('clone-%.2d', [I]);
  end; // for
  Put('match.cap', IntToStr(Length(DLHelpMatch('cyc', Many))));
  if Length(Rows) = 6 then
  begin
    Put('display.menu', DLHelpDisplayText(Rows[0]));
    Put('display.shortest', DLHelpDisplayText(Rows[1]));
    Put('display.context', DLHelpDisplayText(Rows[2]));
    Put('display.title', DLHelpDisplayText(Rows[3]));
    Put('display.cli', DLHelpDisplayText(Rows[5]));
    Put('match.cyc.display0', DLHelpMatch('cyc', Rows)[0].Display);
  end; // if
  Put('caption.fix', DLHelpIdForMenuCaption('Fix...', Rows));
  Put('caption.amp', DLHelpIdForMenuCaption('&Fix...', Rows));
  Put('caption.graph', DLHelpIdForMenuCaption('Call Graph', Rows));
  Put('caption.context', DLHelpIdForMenuCaption('Recycle Cache', Rows));
  Put('caption.none', DLHelpIdForMenuCaption('Nope', Rows));
  Put('caption.inner', DLHelpIdForMenuCaption('Refactor', Rows));
end; // procedure

function QueueState(const pDepth, pPercent: Integer; const pPhase: string;
  const pTitles: TArray<string>): TQueueState;
begin
  Result:= Default(TQueueState);
  Result.Running      := True;
  Result.CurrentTitle := 'Index project';
  Result.Percent      := pPercent;
  Result.Phase        := pPhase;
  Result.QueueDepth   := pDepth;
  Result.PendingTitles:= pTitles;
end; // function

procedure RunQueueText;
var
  S: TQueueState;
begin
  S:= QueueState(0, 45, 'uMain.pas', nil);
  Put('queue.d0', IntToStr(Length(DLQueueLines(S))));
  S:= QueueState(1, 45, 'uMain.pas', ['Lint all']);
  Put('queue.d1', string.Join('|', DLQueueLines(S)));
  S:= QueueState(3, 45, '', ['Lint all', 'Forms CSV', 'Reindex lib']);
  Put('queue.d3', string.Join('|', DLQueueLines(S)));
  S:= QueueState(5, 45, '', ['Lint all', 'Forms CSV', 'Reindex lib']);
  Put('queue.d5', string.Join('|', DLQueueLines(S)));
  S:= QueueState(1, -1, '', ['Lint all']);
  Put('queue.indet', string.Join('|', DLQueueLines(S)));
  S:= QueueState(1, -1, '', ['Lint all']);
  S.Running:= False;
  S.CurrentTitle:= '';
  Put('queue.idle', string.Join('|', DLQueueLines(S)));
end; // procedure

begin
  try
    RunUrlRules;
    RunQueueText;
    RunMatcher(ParamStr(1));
    RunSettingsRoundTrip;
    RunIndex(ParamStr(1), ParamStr(2));
    RunLocator(ParamStr(2));
    Writeln('DONE');
  except
    on E: Exception do
      Writeln('EXCEPTION=' + E.ClassName + ': ' + E.Message);
  end; // try
end.
