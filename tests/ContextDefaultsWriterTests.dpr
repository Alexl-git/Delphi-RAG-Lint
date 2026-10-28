program ContextDefaultsWriterTests;
{$APPTYPE CONSOLE}
{ DRagLint.Core.ContextDefaults.MergeLibraryDefault (the IDE plugin's writer for
  %LOCALAPPDATA%\drag-lint\context-defaults.json), read back through the LSP-owned reader
  DRagLint.Project.ContextFile.TryLoadContextDefaults. Covers: new file created with schema 1,
  other keys + this platform's libraryRoots preserved, no write when unchanged, a malformed file
  never overwritten, and DragLintLocalDataDir / the ContextFile forwarder agreeing.
  Exit code = number of failures. }
uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  DRagLint.Core.ContextDefaults,
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

function FindLib(const ADefs: TContextDefaults; const APlatform: string; out ALib: TLibraryDefault): Boolean;
var
  L: TLibraryDefault;
begin
  Result := False;
  ALib := Default(TLibraryDefault);
  for L in ADefs.Libraries do
    if SameText(L.Platform, APlatform) then
    begin
      ALib := L;
      Exit(True);
    end;
end;

const
  SEEDED =
    '{"schema":1,"platform":"Win32","config":"Release","targetCompiler":"36",' +
    '"libraries":{"Win32":{"libraryDb":"C:\\old\\library-Win32.sqlite","libraryRoots":["C:\\r1"]}}}';

var
  Tmp, DefFile: string;
  Defs: TContextDefaults;
  Lib: TLibraryDefault;
  Wrote: Boolean;
  Before: string;
begin
  Tmp := TPath.Combine(GetEnvironmentVariable('TEMP'), 'dl-ctxdefaults-test-' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(Tmp);
  try
    // 1. absent file (in a folder that does not exist yet) -> created, schema 1, readable
    DefFile := TPath.Combine(TPath.Combine(Tmp, 'sub'), 'context-defaults.json');
    SetEnvironmentVariable(PChar(CONTEXT_DEFAULTS_ENV), PChar(DefFile));
    Wrote := MergeLibraryDefault(DefFile, 'Win64', 'C:\lib\library-Win64.sqlite');
    Check('new file: wrote', Wrote);
    Check('new file: reader loads it', TryLoadContextDefaults(Defs));
    Check('new file: schema 1', Defs.Schema = 1);
    Check('new file: Win64 entry', FindLib(Defs, 'Win64', Lib));
    Check('new file: Win64 libraryDb', SameText(Lib.LibraryDb, 'C:\lib\library-Win64.sqlite'));

    // 2. unchanged value -> no write
    Check('unchanged: no write', not MergeLibraryDefault(DefFile, 'Win64', 'C:\lib\library-Win64.sqlite'));

    // 3. seeded file: other keys and this platform's libraryRoots survive
    TFile.WriteAllText(DefFile, SEEDED, TEncoding.ASCII);
    Wrote := MergeLibraryDefault(DefFile, 'Win32', 'C:\new\library-Win32.sqlite');
    Check('seeded: wrote', Wrote);
    Check('seeded: reader loads it', TryLoadContextDefaults(Defs));
    Check('seeded: platform kept', Defs.Platform = 'Win32');
    Check('seeded: config kept', Defs.Config = 'Release');
    Check('seeded: targetCompiler kept', Defs.TargetCompiler = '36');
    Check('seeded: Win32 entry', FindLib(Defs, 'Win32', Lib));
    Check('seeded: Win32 libraryDb updated', SameText(Lib.LibraryDb, 'C:\new\library-Win32.sqlite'));
    Check('seeded: Win32 libraryRoots kept', (Length(Lib.LibraryRoots) = 1) and SameText(Lib.LibraryRoots[0], 'C:\r1'));
    Wrote := MergeLibraryDefault(DefFile, 'Win64', 'C:\lib\library-Win64.sqlite');
    Check('seeded: second platform wrote', Wrote);
    Check('seeded: reader loads both', TryLoadContextDefaults(Defs) and (Length(Defs.Libraries) = 2));

    // 4. malformed file is never overwritten
    TFile.WriteAllText(DefFile, '{ not json', TEncoding.ASCII);
    Before := TFile.ReadAllText(DefFile);
    Check('malformed: no write', not MergeLibraryDefault(DefFile, 'Win64', 'C:\x.sqlite'));
    Check('malformed: bytes unchanged', TFile.ReadAllText(DefFile) = Before);

    // 5. empty arguments refused
    Check('empty platform: no write', not MergeLibraryDefault(DefFile, '', 'C:\x.sqlite'));
    Check('empty db: no write', not MergeLibraryDefault(DefFile, 'Win64', ''));

    // 6. folder helper: one definition, ContextFile forwards to it
    SetEnvironmentVariable('LOCALAPPDATA', PChar(Tmp + '\'));
    Check('local data dir', DRagLint.Core.ContextDefaults.DragLintLocalDataDir = Tmp + '\drag-lint');
    Check('forwarder agrees', DRagLint.Project.ContextFile.DragLintLocalDataDir =
      DRagLint.Core.ContextDefaults.DragLintLocalDataDir);
    SetEnvironmentVariable(PChar(CONTEXT_DEFAULTS_ENV), nil);
    Check('defaults file under local data dir', ContextDefaultsFile = Tmp + '\drag-lint\context-defaults.json');
  finally
    TDirectory.Delete(Tmp, True);
  end;
  Writeln(Format('ContextDefaultsWriterTests: %d passed, %d failed', [GPass, GFail]));
  ExitCode := GFail;
end.
