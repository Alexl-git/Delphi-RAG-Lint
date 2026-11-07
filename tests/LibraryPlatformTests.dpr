program LibraryPlatformTests;
{$APPTYPE CONSOLE}
{ L-C20 (wave 146 k5): a non-Windows project must not silently bind library-Win32.
  PlatformOfDproj and ChooseLibraryPlatform (DRagLint.CLI.LibraryReady) accept every
  token of KnownPlatforms; a Win32/Win64 dproj and fingerprint keep their old answer
  (positive control). Recipe: tests\autotest\run_library_platform_tokens.ps1. }
uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  DRagLint.CLI.LibraryReady;

var
  Failed: Integer = 0;
  Dir   : string;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else begin Writeln('  [FAIL] ', AName, '  ', ADetail); Inc(Failed); end;
end;

function MakeDproj(const AName, APlat: string): string;
begin
  Result:= TPath.Combine(Dir, AName + '.dproj');
  TFile.WriteAllText(Result, '<Project><PropertyGroup><Platform Condition="' + QuotedStr('$(Platform)') + '==' + QuotedStr('') + '">'
    + APlat + '</Platform></PropertyGroup></Project>');
end;

procedure CheckChoice(const AName, AArg, AFp, ADproj, AWantPlat, AWantSrc: string);
var
  Src: string;
  Got: string;
begin
  Got:= ChooseLibraryPlatform(AArg, AFp, ADproj, 'Win32', Src);
  Check(AName, (Got = AWantPlat) and (Src = AWantSrc), 'got ' + Got + '/' + Src + ' want ' + AWantPlat + '/' + AWantSrc);
end;

begin
  Dir:= TPath.Combine(TPath.GetTempPath, 'drag-lint-libplat-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    CheckChoice('control: dproj Win64', '', '', MakeDproj('a64', 'Win64'), 'Win64', 'dproj');
    CheckChoice('control: dproj Win32', '', '', MakeDproj('a32', 'Win32'), 'Win32', 'dproj');
    CheckChoice('control: fingerprint win64', '', 'v1;plat=win64;x', '', 'Win64', 'db-fingerprint');
    CheckChoice('control: no evidence -> manifest default', '', '', '', 'Win32', 'default');
    CheckChoice('dproj Linux64', '', '', MakeDproj('l64', 'Linux64'), 'Linux64', 'dproj');
    CheckChoice('dproj OSXARM64', '', '', MakeDproj('oa', 'OSXARM64'), 'OSXARM64', 'dproj');
    CheckChoice('dproj Android64', '', '', MakeDproj('an', 'Android64'), 'Android64', 'dproj');
    CheckChoice('fingerprint plat=osx64', '', 'v1;plat=osx64;x', '', 'OSX64', 'db-fingerprint');
    CheckChoice('fingerprint beats dproj', '', 'v1;plat=linux64;x', MakeDproj('w', 'Win64'), 'Linux64', 'db-fingerprint');
    CheckChoice('unknown dproj token stays default', '', '', MakeDproj('zz', 'Plan9'), 'Win32', 'default');
  finally
    TDirectory.Delete(Dir, True);
  end;
  if Failed > 0 then begin Writeln(Failed, ' FAILED'); Halt(1); end;
  Writeln('all passed');
end.
