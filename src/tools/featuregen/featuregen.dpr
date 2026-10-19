program featuregen;

{ featuregen: owns the drag-lint feature registry (features\) and generates docs
  from it. Verbs so far: build --site. Exit 0 ok, 1 changed (check mode) or failed,
  2 usage. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , FeatureGen.Json in 'FeatureGen.Json.pas'
  , FeatureGen.Model in 'FeatureGen.Model.pas'
  , FeatureGen.Output in 'FeatureGen.Output.pas'
  , FeatureGen.Live in 'FeatureGen.Live.pas'
  , FeatureGen.SiteFormat in 'FeatureGen.SiteFormat.pas'
  , FeatureGen.Markdown in 'FeatureGen.Markdown.pas'
  , FeatureGen.Site in 'FeatureGen.Site.pas'
  , FeatureGen.HelpImport in 'FeatureGen.HelpImport.pas'
  ;

procedure PrintUsage;
begin
  Writeln('usage: featuregen <verb> [options]');
  Writeln('  build --site [--check] [--repo <dir>] [--engine <exe>] [--out <dir>]');
  Writeln('      writes the website help set (default root from features\site-format.json);');
  Writeln('      --check writes nothing and exits 1 when any file would change.');
  Writeln('  import-help [--dry-run] [--repo <dir>] [--engine <exe>]');
  Writeln('      seeds usage / flags / pitfalls of cli surfaces that lack them from the engine --help;');
  Writeln('      never overwrites a present field and never writes verified.');
end;

{ Walks up from pStart to the first dir holding features\entries. }
function FindRepo(const pStart: string): string;
var
  lDir, lParent: string;
begin
  lDir := ExcludeTrailingPathDelimiter(pStart);
  while lDir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(lDir, 'features\entries')) then
      Exit(lDir);
    lParent := ExtractFileDir(lDir);
    if lParent = lDir then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function BuildSiteCommand(pArgs: TArray<string>): Integer;
var
  lCheck, lSite: Boolean;
  lRepo, lEngine, lOut, lArg: string;
  lI, lLeaves: Integer;
  lFmt: TSiteFormat;
  lHelp: TLiveHelp;
  lWriter: TOutputWriter;
  lRes: TOutputResult;
  lFile: string;
begin
  lCheck := False;
  lSite := False;
  lRepo := '';
  lEngine := '';
  lOut := '';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if lArg = '--site' then
      lSite := True
    else if lArg = '--check' then
      lCheck := True
    else if (lArg = '--repo') or (lArg = '--engine') or (lArg = '--out') then
    begin
      Inc(lI);
      if lI >= Length(pArgs) then
      begin
        Writeln('featuregen: ', lArg, ' needs a value');
        Exit(2);
      end;
      if lArg = '--repo' then
        lRepo := pArgs[lI]
      else if lArg = '--engine' then
        lEngine := pArgs[lI]
      else
        lOut := pArgs[lI];
    end
    else
    begin
      Writeln('featuregen: unknown option ', lArg);
      Exit(2);
    end;
    Inc(lI);
  end;
  if not lSite then
  begin
    Writeln('featuregen: build needs --site');
    Exit(2);
  end;
  Result := 1;
  try
    if lRepo = '' then
      lRepo := FindRepo(GetCurrentDir);
    if lRepo = '' then
      lRepo := FindRepo(ExtractFilePath(ParamStr(0)));
    if lRepo = '' then
      raise EFeatureGen.Create('no repo found (no features\entries above the current dir); pass --repo');
    lRepo := TPath.GetFullPath(lRepo);
    lFmt := LoadSiteFormat(lRepo);
    if lEngine = '' then
      lEngine := TPath.Combine(lRepo, lFmt.Engine);
    if lOut = '' then
      lOut := TPath.Combine(lRepo, lFmt.Root);
    lHelp := TLiveHelp.Create;
    try
      lHelp.Load(lEngine);
      lFmt.Help := lHelp;
      lWriter := TOutputWriter.Create(lOut, lCheck, True);
      try
        BuildSite(lRepo, lFmt, lWriter);
        lLeaves := 0;
        for lFile in lWriter.ProducedFiles do
          if lFile.StartsWith('features\') and lFile.EndsWith('.md') then
            Inc(lLeaves);
        lRes := lWriter.Finish;
      finally
        lWriter.Free;
      end;
    finally
      lHelp.Free;
    end;
    Writeln(Format('site root: %s', [lOut]));
    Writeln(Format('leaves=%d written=%d removed=%d changed=%d', [lLeaves, Length(lRes.Written), Length(lRes.Removed), Length(lRes.Changed)]));
    if lCheck then
    begin
      for lFile in lRes.Changed do
        Writeln(lFile);
      if Length(lRes.Changed) > 0 then
        Exit(1);
    end;
    Result := 0;
  except
    on E: Exception do
    begin
      Writeln('featuregen: ', E.Message);
      Result := 1;
    end;
  end;
end;

function ImportHelpCommand(pArgs: TArray<string>): Integer;
var
  lDry: Boolean;
  lRepo, lEngine, lArg: string;
  lI: Integer;
  lFmt: TSiteFormat;
  lHelp: TLiveHelp;
  lTotals: TImportTotals;
begin
  lDry := False;
  lRepo := '';
  lEngine := '';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if lArg = '--dry-run' then
      lDry := True
    else if (lArg = '--repo') or (lArg = '--engine') then
    begin
      Inc(lI);
      if lI >= Length(pArgs) then
      begin
        Writeln('featuregen: ', lArg, ' needs a value');
        Exit(2);
      end;
      if lArg = '--repo' then
        lRepo := pArgs[lI]
      else
        lEngine := pArgs[lI];
    end
    else
    begin
      Writeln('featuregen: unknown option ', lArg);
      Exit(2);
    end;
    Inc(lI);
  end;
  Result := 1;
  try
    if lRepo = '' then
      lRepo := FindRepo(GetCurrentDir);
    if lRepo = '' then
      lRepo := FindRepo(ExtractFilePath(ParamStr(0)));
    if lRepo = '' then
      raise EFeatureGen.Create('no repo found (no features\entries above the current dir); pass --repo');
    lRepo := TPath.GetFullPath(lRepo);
    if lEngine = '' then
    begin
      lFmt := LoadSiteFormat(lRepo);
      lEngine := TPath.Combine(lRepo, lFmt.Engine);
    end;
    lHelp := TLiveHelp.Create;
    try
      lHelp.Load(lEngine);
      lTotals := ImportHelp(lRepo, lHelp, lDry,
        procedure(pLine: string)
        begin
          Writeln(pLine);
        end);
    finally
      lHelp.Free;
    end;
    Writeln(Format('%sentries=%d usage=%d flags=%d pitfalls=%d',
      [IfThen(lDry, 'dry-run: ', ''), lTotals.Entries, lTotals.Usage, lTotals.Flags, lTotals.Pitfalls]));
    Result := 0;
  except
    on E: Exception do
    begin
      Writeln('featuregen: ', E.Message);
      Result := 1;
    end;
  end;
end;

var
  lArgs: TArray<string>;
  lI: Integer;
begin
  if (ParamCount >= 1) and (ParamStr(1) = 'build') then
  begin
    SetLength(lArgs, ParamCount - 1);
    for lI := 2 to ParamCount do
      lArgs[lI - 2] := ParamStr(lI);
    ExitCode := BuildSiteCommand(lArgs);
  end
  else if (ParamCount >= 1) and (ParamStr(1) = 'import-help') then
  begin
    SetLength(lArgs, ParamCount - 1);
    for lI := 2 to ParamCount do
      lArgs[lI - 2] := ParamStr(lI);
    ExitCode := ImportHelpCommand(lArgs);
  end
  else
  begin
    PrintUsage;
    ExitCode := 2;
  end;
end.
