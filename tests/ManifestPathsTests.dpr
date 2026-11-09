program ManifestPathsTests;
{$APPTYPE CONSOLE}
{ Installed layout v2 phase 3 (P2): the plugin asks the engine's resolver for drag-lint.json.

  THE CASES, and what each one would catch being undone:
    1 layout OFF, nothing explicit: engine dir then BPL dir, exactly today's two paths (the
      positive control that the OFF switch changes nothing).
    2 layout OFF, no engine exe: the BPL rung alone.
    3 layout v2 with a roaming file: both rungs answer the roaming file, once; RootDir is its folder.
    4 layout v2 with NO roaming file: today's two paths (an un-migrated install still works).
    5 DRAGLINT_MANIFEST honoured with the layout OFF (spec section 4: an ignored explicit request
      fails open onto the real manifest).
    6 outDir %NAME%: literal with the layout OFF, expanded under v2 (E6).
    7 empty outDir: '' with the layout OFF; the roaming manifest under v2 gives
      %LOCALAPPDATA%\drag-lint\library (ruling 3).
    8 write target: exe dir with the layout OFF; the roaming file under v2 when no manifest exists.
  Every folder is a scratch folder under %TEMP%: APPDATA and LOCALAPPDATA are pointed there for the
  process, so the real profile is never read or written. }
uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  DragLint.Plugin.ManifestPaths;

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName, ' ', ADetail);
  end;
end;

procedure SetEnv(const AName, AValue: string);
begin
  if AValue = '' then SetEnvironmentVariable(PChar(AName), nil)
  else SetEnvironmentVariable(PChar(AName), PChar(AValue));
end;

function Joined(const A: TArray<string>): string;
begin
  Result:= string.Join(' | ', A);
end;

var
  Root, AppData, LocalAppData, ExeDir, BplDir, Roaming, Explicit: string;
  C: TArray<string>;
begin
  Root        := TPath.Combine(TPath.GetTempPath, 'dl-manifestpaths-' + IntToStr(GetCurrentProcessId));
  AppData     := TPath.Combine(Root, 'roam');
  LocalAppData:= TPath.Combine(Root, 'local');
  ExeDir      := TPath.Combine(Root, 'bin') + '\';
  BplDir      := TPath.Combine(Root, 'bpl') + '\';
  Roaming     := TPath.Combine(AppData, 'drag-lint\drag-lint.json');
  Explicit    := TPath.Combine(Root, 'explicit\drag-lint.json');
  ForceDirectories(ExtractFilePath(Roaming));
  ForceDirectories(LocalAppData);
  ForceDirectories(ExeDir);
  ForceDirectories(BplDir);
  SetEnv('APPDATA', AppData);
  SetEnv('LOCALAPPDATA', LocalAppData);
  SetEnv('DRAGLINT_MANIFEST', '');
  SetEnv('DL_XP3_PROBE', 'probe');
  try
    { 1, 2: layout OFF }
    SetEnv('DRAGLINT_LAYOUT', '');
    TFile.WriteAllText(Roaming, '{}');
    C:= PluginManifestCandidates(ExeDir + 'drag-lint.exe', BplDir);
    Check('1 OFF: engine dir then BPL dir', (Length(C) = 2) and SameText(C[0], ExeDir + 'drag-lint.json')
      and SameText(C[1], BplDir + 'drag-lint.json'), Joined(C));
    C:= PluginManifestCandidates('', BplDir);
    Check('2 OFF, no engine: BPL dir only', (Length(C) = 1) and SameText(C[0], BplDir + 'drag-lint.json'), Joined(C));

    { 3: v2 with the roaming file }
    SetEnv('DRAGLINT_LAYOUT', 'v2');
    C:= PluginManifestCandidates(ExeDir + 'drag-lint.exe', BplDir);
    Check('3a v2: the roaming file, once', (Length(C) = 1) and SameText(C[0], Roaming), Joined(C));
    Check('3b v2: RootDir is the roaming folder',
      SameText(ExcludeTrailingPathDelimiter(PluginManifestIn(BplDir).RootDir), ExtractFileDir(Roaming)),
      PluginManifestIn(BplDir).RootDir);

    { 4: v2, roaming file absent }
    TFile.Delete(Roaming);
    C:= PluginManifestCandidates(ExeDir + 'drag-lint.exe', BplDir);
    Check('4 v2, no roaming file: today''s two paths', (Length(C) = 2) and SameText(C[0], ExeDir + 'drag-lint.json')
      and SameText(C[1], BplDir + 'drag-lint.json'), Joined(C));

    { 5: explicit, layout OFF }
    SetEnv('DRAGLINT_LAYOUT', '');
    SetEnv('DRAGLINT_MANIFEST', Explicit);
    C:= PluginManifestCandidates(ExeDir + 'drag-lint.exe', BplDir);
    Check('5 explicit honoured with the layout OFF', (Length(C) = 1) and SameText(C[0], Explicit), Joined(C));
    SetEnv('DRAGLINT_MANIFEST', '');

    { 6: outDir expansion }
    Check('6a OFF: %NAME% stays literal', PluginLibraryOutDir('%DL_XP3_PROBE%\lib', ExeDir + 'drag-lint.json') = '%DL_XP3_PROBE%\lib',
      PluginLibraryOutDir('%DL_XP3_PROBE%\lib', ExeDir + 'drag-lint.json'));
    SetEnv('DRAGLINT_LAYOUT', 'v2');
    Check('6b v2: %NAME% expanded', PluginLibraryOutDir('%DL_XP3_PROBE%\lib', ExeDir + 'drag-lint.json') = 'probe\lib',
      PluginLibraryOutDir('%DL_XP3_PROBE%\lib', ExeDir + 'drag-lint.json'));

    { 7: empty outDir }
    Check('7a v2, roaming manifest, no outDir: LOCALAPPDATA library',
      SameText(ExcludeTrailingPathDelimiter(PluginLibraryOutDir('', Roaming)), TPath.Combine(LocalAppData, 'drag-lint\library')),
      PluginLibraryOutDir('', Roaming));
    Check('7b v2, exe-side manifest, no outDir: none', PluginLibraryOutDir('', ExeDir + 'drag-lint.json') = '',
      PluginLibraryOutDir('', ExeDir + 'drag-lint.json'));
    SetEnv('DRAGLINT_LAYOUT', '');
    Check('7c OFF, roaming path, no outDir: none', PluginLibraryOutDir('', Roaming) = '', PluginLibraryOutDir('', Roaming));

    { 8: write target }
    Check('8a OFF: write beside the engine', SameText(PluginManifestWriteTarget(ExeDir), ExeDir + 'drag-lint.json'),
      PluginManifestWriteTarget(ExeDir));
    SetEnv('DRAGLINT_LAYOUT', 'v2');
    Check('8b v2, no manifest anywhere: write the roaming file', SameText(PluginManifestWriteTarget(ExeDir), Roaming),
      PluginManifestWriteTarget(ExeDir));
  finally
    SetEnv('DRAGLINT_LAYOUT', '');
    TDirectory.Delete(Root, True);
  end;

  Writeln(Format('ManifestPathsTests: %d passed, %d failed', [GPassed, GFailed]));
  if GFailed > 0 then ExitCode:= 1;
end.
