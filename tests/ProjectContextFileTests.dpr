program ProjectContextFileTests;
{$APPTYPE CONSOLE}
{ DRagLint.Project.ContextFile: save -> load round trip, SHA-1 staleness, nearest-wins lookup,
  platform/config effect on the define set (positive control: DEBUG in Debug, not in Release),
  and the central defaults reader (absent file tolerated). Exit code = number of failures.
  Fixture: a copy of src\cli\drag-lint.dproj (real DEBUG / RELEASE DCC_Define). }
uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  DRagLint.Project.ContextFile;

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then
    Inc(GPass)
  else
  begin
    Inc(GFail);
    Writeln('FAIL: ', AName);
  end;
end;

function Has(const AItems: TArray<string>; const AName: string): Boolean;
var
  S: string;
begin
  Result := False;
  for S in AItems do
    if SameText(S, AName) then Exit(True);
end;

var
  Tmp, Sub, Dproj, CtxFile, DefFile: string;
  Ctx, Back, Near: TProjectContext;
  Defs: TContextDefaults;
begin
  Tmp := TPath.Combine(GetEnvironmentVariable('TEMP'), 'dl-ctxfile-test-' + IntToStr(Random(100000)));
  TDirectory.CreateDirectory(Tmp);
  try
    DefFile := TPath.Combine(Tmp, 'defaults.json');
    SetEnvironmentVariable(PChar(CONTEXT_DEFAULTS_ENV), PChar(DefFile));
    Dproj := TPath.Combine(Tmp, 'App.dproj');
    TFile.Copy(ParamStr(1), Dproj);

    // defaults: absent file tolerated, then read
    Check('defaults file path honours env', ContextDefaultsFile = DefFile);
    Check('absent defaults -> False', not TryLoadContextDefaults(Defs));
    TFile.WriteAllText(DefFile,
      '{"schema":1,"platform":"Win32","config":"Debug","targetCompiler":"37",' +
      '"libraries":{"Win64":{"libraryDb":"%TEMP%\\lib.sqlite","libraryRoots":["C:\\rtl"]}}}');
    Check('defaults -> True', TryLoadContextDefaults(Defs));
    Check('defaults platform', Defs.Platform = 'Win32');
    Check('defaults targetCompiler', Defs.TargetCompiler = '37');
    Check('defaults one library', Length(Defs.Libraries) = 1);
    if Length(Defs.Libraries) = 1 then
    begin
      Check('library platform', Defs.Libraries[0].Platform = 'Win64');
      Check('library env expanded', Pos('%', Defs.Libraries[0].LibraryDb) = 0);
      Check('library roots', Length(Defs.Libraries[0].LibraryRoots) = 1);
    end;
    TFile.WriteAllText(DefFile, '{not json');
    Check('malformed defaults -> False', not TryLoadContextDefaults(Defs));

    // positive control: config changes the defines
    Ctx := BuildProjectContext(Dproj, 'Win64', 'Debug');
    Check('Debug has DEBUG', Has(Ctx.Defines, 'DEBUG'));
    Check('Debug platform', Ctx.Platform = 'Win64');
    Check('Win64 has WIN64', Has(Ctx.Defines, 'WIN64'));
    Check('Release lacks DEBUG', not Has(BuildProjectContext(Dproj, 'Win64', 'Release').Defines, 'DEBUG'));
    Check('Win32 lacks WIN64', not Has(BuildProjectContext(Dproj, 'Win32', 'Debug').Defines, 'WIN64'));
    Check('sha1 is 40 hex', Length(Ctx.SourceSha1) = 40);

    // round trip
    Ctx.TargetCompiler := '37';
    Ctx.UnitAliases := [TPair<string, string>.Create('WinTypes', 'Winapi.Windows')];
    Ctx.LibraryDb := 'C:\x\lib.sqlite';
    CtxFile := ContextFileFor(Dproj);
    Check('context file name', ExtractFileName(CtxFile) = 'App.dlcontext.json');
    SaveProjectContext(Ctx, CtxFile);
    Check('loads', TryLoadProjectContext(CtxFile, Back));
    Check('round trip platform/config', (Back.Platform = Ctx.Platform) and (Back.Config = Ctx.Config));
    Check('round trip defines', Length(Back.Defines) = Length(Ctx.Defines));
    Check('round trip alias', (Length(Back.UnitAliases) = 1) and (Back.UnitAliases[0].Value = 'Winapi.Windows'));
    Check('round trip targetCompiler/libraryDb', (Back.TargetCompiler = '37') and (Back.LibraryDb = Ctx.LibraryDb));
    Check('fresh is not stale', not Back.Stale);
    Check('no BOM', TFile.ReadAllBytes(CtxFile)[0] = Ord('{'));

    // staleness
    TFile.AppendAllText(Dproj, ' ');
    Check('changed dproj -> stale', TryLoadProjectContext(CtxFile, Back) and Back.Stale);

    // nearest wins
    Sub := TPath.Combine(Tmp, 'sub');
    TDirectory.CreateDirectory(Sub);
    TFile.WriteAllText(TPath.Combine(Sub, 'u.pas'), 'unit u; end.');
    Check('parent context found from sub unit', FindProjectContextForUnit(TPath.Combine(Sub, 'u.pas'), Near)
      and (Near.Config = Ctx.Config));
    Ctx.Config := 'Nearest';
    SaveProjectContext(Ctx, TPath.Combine(Sub, 'Inner.dlcontext.json'));
    Check('nearest wins', FindProjectContextForUnit(TPath.Combine(Sub, 'u.pas'), Near) and (Near.Config = 'Nearest'));
    Check('no context -> False', not FindProjectContextForUnit('Z:\no\such\dir\x.pas', Near));

    // .dpr / no project: built-ins, never stale
    Ctx := BuildProjectContext('', 'Win32', 'Debug');
    Check('built-ins Win32', (Ctx.Platform = 'Win32') and Has(Ctx.Defines, 'WIN32') and (Ctx.SourceFile = ''));
  finally
    SetEnvironmentVariable(PChar(CONTEXT_DEFAULTS_ENV), nil);
    TDirectory.Delete(Tmp, True);
  end;
  Writeln(Format('ProjectContextFileTests: %d passed, %d failed', [GPass, GFail]));
  ExitCode := GFail;
end.
