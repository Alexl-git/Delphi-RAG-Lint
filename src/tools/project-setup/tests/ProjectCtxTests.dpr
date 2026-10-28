program ProjectCtxTests;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Classes,
  DRagLint.Project.ContextFile,
  ProjectSetup.ContextJson in '..\ProjectSetup.ContextJson.pas';

var
  gFail: Integer = 0;
  gRun: Integer = 0;

procedure Check(pCond: Boolean; const pName: string);
begin
  Inc(gRun);
  if pCond then
    Writeln('PASS ', pName)
  else
  begin
    Inc(gFail);
    Writeln('FAIL ', pName);
  end;
end;

function Has(const pArr: TArray<string>; const pS: string): Boolean;
var
  lS: string;
begin
  for lS in pArr do
    if SameText(lS, pS) then
      Exit(True);
  Result := False;
end;

procedure TestBuiltIns;
var
  lP: string;
begin
  Check(Has(BuiltInDefines('Win32'), 'WIN32'), 'Win32 has WIN32');
  Check(Has(BuiltInDefines('Win32'), 'VER370') and Has(BuiltInDefines('Win32'), 'CPUX86'), 'Win32 matches engine table');
  Check(Has(BuiltInDefines('Win64'), 'WIN64') and Has(BuiltInDefines('Win64'), 'CPUX86_64'), 'Win64 has WIN64,CPUX86_64');
  Check(Has(BuiltInDefines('Linux64'), 'LINUX64'), 'Linux64 has LINUX64');
  Check(Has(BuiltInDefines('OSXARM64'), 'CPUARM64'), 'OSXARM64 has CPUARM64');
  Check(Has(BuiltInDefines('Android64'), 'ANDROID64'), 'Android64 has ANDROID64');
  Check(Has(BuiltInDefines('iOSSimARM64'), 'IOSSIMULATOR'), 'iOSSimARM64 has IOSSIMULATOR');
  Check(not Has(BuiltInDefines('Win32'), 'WIN64'), 'Win32 lacks WIN64');
  Check(Length(BuiltInDefines('Nope')) = 0, 'unknown platform empty');
  for lP in SetupPlatforms do
    Check(Length(BuiltInDefines(lP)) > 0, 'built-ins non-empty: ' + lP);
end;

procedure TestDebug;
begin
  Check(Has(DefaultDefines('Win64', 'Debug'), 'DEBUG'), 'Debug adds DEBUG');
  Check(not Has(DefaultDefines('Win64', 'Release'), 'DEBUG'), 'Release has no DEBUG');
  Check(Has(DefaultNamespaces('Win32'), 'Vcl') and not Has(DefaultNamespaces('Linux64'), 'Vcl'), 'namespaces per platform');
end;

procedure TestRoundTrip;
var
  lDir, lDpr: string;
  lIn, lOut: TProjectContext;
begin
  lDir := TPath.Combine(TPath.GetTempPath, 'dlps_test_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(lDir);
  try
    lDpr := TPath.Combine(lDir, 'App.dpr');
    TFile.WriteAllText(lDpr, 'program App; begin end.');
    lIn := Default(TProjectContext);
    lIn.Project := lDpr;
    lIn.SourceFile := lDpr;
    lIn.SourceSha1 := FileSha1Hex(lDpr);
    lIn.Platform := 'Win64';
    lIn.Config := 'Debug';
    lIn.Defines := DefaultDefines('Win64', 'Debug');
    lIn.SearchPath := TArray<string>.Create('C:\X\lib', 'C:\X\other');
    lIn.Namespaces := DefaultNamespaces('Win64');
    lIn.TargetCompiler := '37';
    lIn.LibraryDb := 'C:\db\lib.sqlite';
    lIn.LibraryRoots := TArray<string>.Create('C:\RTL');
    lIn.Schema := CONTEXT_SCHEMA;
    SaveProjectContext(lIn, ContextFileFor(lDpr));
    Check(ContextFileFor(lDpr) = TPath.Combine(lDir, 'App.dlcontext.json'), 'file next to dpr');
    Check(TryLoadProjectContext(ContextFileFor(lDpr), lOut), 'load ok');
    Check((lOut.Project = lIn.Project) and (lOut.Platform = 'Win64') and (lOut.Config = 'Debug'), 'scalars round trip');
    Check((Length(lOut.Defines) = Length(lIn.Defines)) and Has(lOut.Defines, 'DEBUG'), 'defines round trip');
    Check((Length(lOut.SearchPath) = 2) and (lOut.SearchPath[0] = 'C:\X\lib') and (lOut.SearchPath[1] = lIn.SearchPath[1]), 'searchPath round trip incl. non-ASCII');
    Check((lOut.LibraryDb = lIn.LibraryDb) and (Length(lOut.LibraryRoots) = 1), 'library fields');
    Check((lOut.SourceSha1 = lIn.SourceSha1) and (Length(lOut.SourceSha1) = 40), 'sha1 round trip');
    Check(lOut.TargetCompiler = '37', 'targetCompiler round trip');
  finally
    TDirectory.Delete(lDir, True);
  end;
end;

procedure TestDefaults;
var
  lFile: string;
  lDef: TContextDefaults;
begin
  lFile := TPath.Combine(TPath.GetTempPath, 'dlps_defaults_' + IntToStr(GetTickCount) + '.json');
  TFile.WriteAllText(lFile, '{"schema":1,"platform":"Win64","config":"Release","targetCompiler":"37",' +
    '"libraries":{"Win64":{"libraryDb":"C:\\db\\w64.sqlite","libraryRoots":["C:\\RTL64"]}}}');
  try
    SetEnvironmentVariable('DRAGLINT_CONTEXT_DEFAULTS', PChar(lFile));
    Check(ContextDefaultsFile = lFile, 'env overrides defaults path');
    Check(TryLoadContextDefaults(lDef), 'defaults load');
    Check((lDef.Platform = 'Win64') and (lDef.Config = 'Release') and (lDef.TargetCompiler = '37'), 'defaults scalars');
    Check((Length(lDef.Libraries) = 1) and (lDef.Libraries[0].LibraryDb = 'C:\db\w64.sqlite') and (Length(lDef.Libraries[0].LibraryRoots) = 1), 'defaults libraries entry');
    SetEnvironmentVariable('DRAGLINT_CONTEXT_DEFAULTS', PChar(lFile + '.missing'));
    Check(not TryLoadContextDefaults(lDef), 'absent file tolerated');
  finally
    SetEnvironmentVariable('DRAGLINT_CONTEXT_DEFAULTS', nil);
    TFile.Delete(lFile);
  end;
end;

begin
  TestDefaults;
  TestBuiltIns;
  TestDebug;
  TestRoundTrip;
  Writeln(Format('%d checks, %d failed', [gRun, gFail]));
  if gFail > 0 then
    Halt(1);
end.
