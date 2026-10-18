unit ChartsTests.Process;

(* Cases for DRagLint.Charts.Process.QuoteArg: an argument quoted for CreateProcess must come
  back exactly as given when the child splits its command line (CommandLineToArgvW). Moved
  here from the PowerShell producer's tests when that producer was removed (2026-10-18); the
  engine still starts drag-lint.exe as a child (DRagLint.Charts.Pairs) with these quotes.
  Pure string work: nothing is started. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProcessTests = class
  public
    [Test] procedure PlainValueIsQuoted;
    [Test] procedure QuotedValuesSurviveCommandLineToArgvW;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, DRagLint.Charts.Process;

const
  ENGINE_FIXTURE = 'C:\X\drag-lint.exe'; // dl:ok hardcoded-absolute-path@7ebd -- synthetic test input: never touches the filesystem
  SPACED_PROJECT = 'C:\My Projects\A B.dproj'; // dl:ok hardcoded-absolute-path@bdb5 -- synthetic test input: never touches the filesystem
  SLASH_END_PROJECT = 'C:\dir\'; // dl:ok hardcoded-absolute-path@b310 -- synthetic test input: never touches the filesystem
  SPACED_ENGINE = 'C:\Program Files\dl\drag-lint.exe'; // dl:ok hardcoded-absolute-path@4250 -- synthetic test input: never touches the filesystem
  SLASH_QUOTE_TARGET = 'a\"b';
  ARGC = 4;

{$POINTERMATH ON}
{ The command line split back the way the child process will split it. }
function SplitArgv(const pLine: string): TArray<string>;
begin
  var Count: Integer;
  var Argv:= CommandLineToArgvW(PChar(pLine), Count);
  Assert.IsTrue(Argv <> nil, 'CommandLineToArgvW failed');
  try
    SetLength(Result, Count);
    for var I:= 0 to Count - 1 do
      Result[I]:= Argv[I];
  finally
    LocalFree(HLOCAL(Argv));
  end;
end;
{$POINTERMATH OFF}

procedure TProcessTests.PlainValueIsQuoted;
begin
  Assert.AreEqual('"OPERAT.NAME"', QuoteArg('OPERAT.NAME'));
  Assert.AreEqual('""', QuoteArg(''), 'an empty value is still one argument');
end;

procedure TProcessTests.QuotedValuesSurviveCommandLineToArgvW;
begin
  // a path with spaces, a value ending in a backslash right before the next argument, an engine
  // path with spaces, and a backslash before an embedded quote: each must come back exactly as given
  Assert.AreEqual('"a\\\"b"', QuoteArg(SLASH_QUOTE_TARGET), 'backslash then quote: 2n+1 backslashes');
  Assert.AreEqual('"C:\dir\\"', QuoteArg(SLASH_END_PROJECT), 'trailing backslash doubled');
  var Line:= QuoteArg(SPACED_ENGINE) + ' ' + QuoteArg(SLASH_QUOTE_TARGET) + ' ' + QuoteArg(SPACED_PROJECT) + ' ' +
    QuoteArg(SLASH_END_PROJECT);
  var Argv:= SplitArgv(Line + ' ' + QuoteArg(ENGINE_FIXTURE));
  Assert.AreEqual(ARGC + 1, Integer(Length(Argv)), 'every value is its own argument: ' + Line);
  Assert.AreEqual(SPACED_ENGINE, Argv[0], 'spaced engine');
  Assert.AreEqual(SLASH_QUOTE_TARGET, Argv[1], 'a\"b round trip');
  Assert.AreEqual(SPACED_PROJECT, Argv[2], 'spaced project');
  Assert.AreEqual(SLASH_END_PROJECT, Argv[3], 'trailing backslash round trip');
  Assert.AreEqual(ENGINE_FIXTURE, Argv[ARGC], 'the argument after a trailing backslash is still its own');
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessTests);

end.
