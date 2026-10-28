program featuregen;

{ featuregen: owns the drag-lint feature registry (features\) and generates docs
  from it. Verbs so far: build [--site | --all], import-help, check, add, update, find,
  blast-radius, move-menu, deprecate, normalise, verify, audit. Exit 0 ok, 1 changed (check mode) or failed,
  2 usage. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.RegularExpressions
  , Winapi.Windows
  , FeatureGen.Json in 'FeatureGen.Json.pas'
  , FeatureGen.Model in 'FeatureGen.Model.pas'
  , FeatureGen.Output in 'FeatureGen.Output.pas'
  , FeatureGen.Live in 'FeatureGen.Live.pas'
  , FeatureGen.SiteFormat in 'FeatureGen.SiteFormat.pas'
  , FeatureGen.Markdown in 'FeatureGen.Markdown.pas'
  , FeatureGen.Site in 'FeatureGen.Site.pas'
  , FeatureGen.HelpImport in 'FeatureGen.HelpImport.pas'
  , FeatureGen.HelpText in 'FeatureGen.HelpText.pas'
  , FeatureGen.Wiki in 'FeatureGen.Wiki.pas'
  , FeatureGen.DocsCheck in 'FeatureGen.DocsCheck.pas'
  , FeatureGen.Check in 'FeatureGen.Check.pas'
  , FeatureGen.Audit in 'FeatureGen.Audit.pas'
  , FeatureGen.Commands in 'FeatureGen.Commands.pas'
  ;

procedure PrintUsage;
begin
  Writeln('usage: featuregen <verb> [options]');
  Writeln('  build [--site | --all] [--check] [--repo <dir>] [--engine <exe>] [--out <dir>]');
  Writeln('      no target flag: the ported wiki outputs (docs\wiki pages, README / AI-USAGE blocks,');
  Writeln('      features\generated\manifest.json and cli-reference.md), --out renders them elsewhere;');
  Writeln('      --site: the website help set (default root from features\site-format.json) and features\generated\site-pages.json,');
  Writeln('      the per-page "updated" map (not written with --out);');
  Writeln('      --all: both (--out not allowed);');
  Writeln('      --check writes nothing and exits 1 when any file would change.');
  Writeln('  import-help [--blocks] [--dry-run] [--repo <dir>] [--engine <exe>]');
  Writeln('      seeds usage / flags / pitfalls of cli surfaces that lack them from the engine --help;');
  Writeln('      never overwrites a present field and never writes verified.');
  Writeln('  check [--level wellformed|full] [--repo <dir>] [--engine <exe>]');
  Writeln('      the registry guard''s checks A-E; wellformed = check A only (no engine);');
  Writeln('      full (default) adds the live surface (B, C), generated outputs (D) and staleness notes (E).');
  Writeln('      B/C compare FULL ide-menu paths read by the engine''s menu-tree verb (a moved item fails);');
  Writeln('      an engine without menu-tree falls back to the flat caption harvest (leaf-only, noted).');
  Writeln('      exits 1 when any check fails.');
  PrintRegistryUsage(
    procedure(const pLine: string)
    begin
      Writeln(pLine);
    end);
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

{ DRAGLINT_VERSION of the repo: the version a changed site page is stamped with. }
function ProductVersionOf(const pRepo: string): string;
var
  lFile: string;
  lM: TMatch;
begin
  lFile := TPath.Combine(pRepo, 'src\core\DRagLint.Core.Model.pas');
  lM := TRegEx.Match(TFile.ReadAllText(lFile), 'DRAGLINT_VERSION\s*=\s*''([^'']+)''');
  if not lM.Success then
    raise EFeatureGen.CreateFmt('DRAGLINT_VERSION not found in %s', [lFile]);
  Result := lM.Groups[1].Value;
end;

function BuildSiteCommand(pArgs: TArray<string>): Integer;
var
  lCheck, lSite, lAll, lWikiChanged: Boolean;
  lRepo, lEngine, lOut, lArg: string;
  lI, lLeaves: Integer;
  lFmt: TSiteFormat;
  lHelp: TLiveHelp;
  lWriter: TOutputWriter;
  lRes, lPagesRes: TOutputResult;
  lFile: string;
  lPages: TSitePages;
  lDefaultOut: Boolean;
begin
  lCheck := False;
  lSite := False;
  lAll := False;
  lRepo := '';
  lEngine := '';
  lOut := '';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if lArg = '--site' then
      lSite := True
    else if lArg = '--all' then
      lAll := True
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
  if lAll and (lOut <> '') then
  begin
    Writeln('featuregen: --out cannot be combined with --all');
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
    lWikiChanged := False;
    if lAll or not lSite then
    begin
      lWriter := TOutputWriter.Create((if lOut <> '' then lOut else lRepo), lCheck, False);
      try
        BuildWiki(lRepo, lWriter, lEngine);
        lRes := lWriter.Finish;
      finally
        lWriter.Free;
      end;
      Writeln(Format('wiki outputs: written=%d changed=%d', [Length(lRes.Written), Length(lRes.Changed)]));
      if lCheck then
        for lFile in lRes.Changed do
          Writeln(lFile);
      lWikiChanged := lCheck and (Length(lRes.Changed) > 0);
      if not lAll then
        Exit(if lWikiChanged then 1 else 0);
    end;
    lDefaultOut := lOut = '';
    if lDefaultOut then
      lOut := TPath.Combine(lRepo, lFmt.Root);
    lHelp := TLiveHelp.Create;
    lPages := TSitePages.Create(ProductVersionOf(lRepo));
    try
      lHelp.Load(lEngine);
      lFmt.Help := lHelp;
      lPages.LoadFromFile(TPath.Combine(lRepo, 'features\generated\site-pages.json'));
      lWriter := TOutputWriter.Create(lOut, lCheck, True);
      try
        BuildSite(lRepo, lFmt, lWriter, lPages);
        lLeaves := 0;
        for lFile in lWriter.ProducedFiles do
          if lFile.StartsWith('features\') and lFile.EndsWith('.md') then
            Inc(lLeaves);
        lRes := lWriter.Finish;
      finally
        lWriter.Free;
      end;
      if lDefaultOut then
      begin
        // the per-page updated map lives beside manifest.json, not in the site root
        lWriter := TOutputWriter.Create(TPath.Combine(lRepo, 'features\generated'), lCheck, False);
        try
          lWriter.Put('site-pages.json', lPages.ToJson, 'site-pages.json');
          lPagesRes := lWriter.Finish;
        finally
          lWriter.Free;
        end;
        lRes.Written := lRes.Written + lPagesRes.Written;
        lRes.Changed := lRes.Changed + lPagesRes.Changed;
      end;
    finally
      lPages.Free;
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
    Result := if lWikiChanged then 1 else 0;
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
  lBlocks: Boolean;
begin
  lDry := False;
  lBlocks := False;
  lRepo := '';
  lEngine := '';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if lArg = '--dry-run' then
      lDry := True
    else if lArg = '--blocks' then
      lBlocks := True
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
      if lBlocks then
      begin
        Writeln(Format('%sblocks=%d', [IfThen(lDry, 'dry-run: ', ''), SeedHelpBlocks(lRepo, lHelp, lDry, procedure(pLine: string) begin Writeln(pLine); end)]));
        Exit(0);
      end;
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

function CheckCommand(pArgs: TArray<string>): Integer;
var
  lRepo, lEngine, lArg, lLevelText, lNote: string;
  lI: Integer;
  lLevel: TCheckLevel;
  lFmt: TSiteFormat;
  lFindings: TArray<TFinding>;
  lF: TFinding;
  lNotes: TArray<string>;
begin
  lRepo := '';
  lEngine := '';
  lLevelText := 'full';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if (lArg = '--repo') or (lArg = '--engine') or (lArg = '--level') then
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
        lLevelText := LowerCase(pArgs[lI]);
    end
    else
    begin
      Writeln('featuregen: unknown option ', lArg);
      Exit(2);
    end;
    Inc(lI);
  end;
  if lLevelText = 'wellformed' then
    lLevel := clWellFormed
  else if lLevelText = 'full' then
    lLevel := clFull
  else
  begin
    Writeln('featuregen: --level must be wellformed or full');
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
    if (lEngine = '') and (lLevel = clFull) then
    begin
      lFmt := LoadSiteFormat(lRepo);
      lEngine := TPath.Combine(lRepo, lFmt.Engine);
    end;
    lFindings := RunCheckCommand(lRepo, lEngine, lLevel, lNotes);
    for lNote in lNotes do
      Writeln('  [NOTE] ', lNote);
    for lF in lFindings do
      Writeln(FindingText(lF));
    if Length(lFindings) > 0 then
      Writeln(Format('check: %d failure(s)', [Length(lFindings)]))
    else
    begin
      Writeln(Format('check (%s): PASS', [lLevelText]));
      Result := 0;
    end;
  except
    on E: Exception do
    begin
      Writeln('featuregen: ', E.Message);
      Result := 1;
    end;
  end;
end;

{ Test aid (not in PrintUsage): prints the live help verbs and the main-menu captions this tool
  harvests, one "verb<TAB>x" / "caption<TAB>x" line each, so run_docs_surface_harvest_lib.ps1 can
  compare them with the PowerShell harvest (tests\autotest\lib\DocsSurfaceHarvest.ps1). }
function DumpLiveCommand(pArgs: TArray<string>): Integer;
var
  lRepo, lEngine, lS: string;
  lI: Integer;
  lLive: TLiveSurface;
begin
  lRepo := '';
  lEngine := '';
  lI := 0;
  while lI + 1 < Length(pArgs) do
  begin
    if pArgs[lI] = '--repo' then
      lRepo := pArgs[lI + 1]
    else if pArgs[lI] = '--engine' then
      lEngine := pArgs[lI + 1];
    Inc(lI, 2);
  end;
  Result := 1;
  try
    if lRepo = '' then
      lRepo := FindRepo(GetCurrentDir);
    if lRepo = '' then
      raise EFeatureGen.Create('dump-live: no repo found; pass --repo');
    lRepo := TPath.GetFullPath(lRepo);
    if lEngine = '' then
      lEngine := TPath.Combine(lRepo, LoadSiteFormat(lRepo).Engine);
    lLive := TLiveSurface.Create;
    try
      lLive.Harvest(lRepo, lEngine);
      for lS in lLive.HelpVerbs do
        Writeln('verb'#9, lS);
      for lS in lLive.Captions do
        Writeln('caption'#9, lS);
    finally
      lLive.Free;
    end;
    Result := 0;
  except
    on E: Exception do
      Writeln('featuregen: ', E.Message);
  end;
end;

{ The words of the command line by the C runtime rules (SplitCommandLine): System.ParamStr turns \" into \, so a
  --set value with quotes passed from bash or PowerShell arrived mangled. }
function ArgCount: Integer;
begin
  Result := Length(SplitCommandLine(GetCommandLine)) - 1;
end;

function Arg(pIndex: Integer): string;
var
  lAll: TArray<string>;
begin
  lAll := SplitCommandLine(GetCommandLine);
  Result := (if pIndex < Length(lAll) then lAll[pIndex] else '');
end;

var
  lArgs: TArray<string>;
  lI: Integer;
begin
  if (ArgCount >= 1) and ((Arg(1) = '--help') or (Arg(1) = '-h')) then
  begin
    PrintUsage;
    ExitCode := 0;
  end
  else if (ArgCount >= 1) and (Arg(1) = 'dump-live') then
  begin
    SetLength(lArgs, ArgCount - 1);
    for lI := 2 to ArgCount do
      lArgs[lI - 2] := Arg(lI);
    ExitCode := DumpLiveCommand(lArgs);
  end
  else if (ArgCount >= 1) and (Arg(1) = 'build') then
  begin
    SetLength(lArgs, ArgCount - 1);
    for lI := 2 to ArgCount do
      lArgs[lI - 2] := Arg(lI);
    ExitCode := BuildSiteCommand(lArgs);
  end
  else if (ArgCount >= 1) and (Arg(1) = 'import-help') then
  begin
    SetLength(lArgs, ArgCount - 1);
    for lI := 2 to ArgCount do
      lArgs[lI - 2] := Arg(lI);
    ExitCode := ImportHelpCommand(lArgs);
  end
  else if (ArgCount >= 1) and (Arg(1) = 'check') then
  begin
    SetLength(lArgs, ArgCount - 1);
    for lI := 2 to ArgCount do
      lArgs[lI - 2] := Arg(lI);
    ExitCode := CheckCommand(lArgs);
  end
  else if (ArgCount >= 1) and IsRegistryVerb(Arg(1)) then
  begin
    SetLength(lArgs, ArgCount - 1);
    for lI := 2 to ArgCount do
      lArgs[lI - 2] := Arg(lI);
    ExitCode := RunRegistryCommand(Arg(1), lArgs, (if FindRepo(GetCurrentDir) <> '' then FindRepo(GetCurrentDir) else FindRepo(ExtractFilePath(Arg(0)))),
      procedure(const pLine: string)
      begin
        Writeln(pLine);
      end);
  end
  else
  begin
    PrintUsage;
    ExitCode := 2;
  end;
end.
