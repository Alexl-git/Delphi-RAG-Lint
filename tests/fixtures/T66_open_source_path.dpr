program T66_open_source_path;

{ T66: the open-in-IDE pipe validates the path BEFORE touching the file system.

  DragLint.Plugin.OpenSourceServer.DoOpenInIDE used to call FileExists on
  whatever reached the pipe, then open any existing file: a UNC path made the
  IDE process authenticate to that server (an NTLM hash leak), and .dproj /
  .dpk / .bpl files were opened too. Found by the charts session's review of
  the draglint:// click path, 2026-09-29. IsOpenableSourcePath mirrors the
  browser-side handler (charts\src\Open-DragLintUri.ps1); the owner ruled that
  .dpr MAY open. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.OpenSourcePath in '..\..\src\delphi-plugin\DragLint.Plugin.OpenSourcePath.pas';

var
  Fails: Integer = 0;

procedure Expect(const APath: string; AWant: Boolean; const ALabel: string);
var
  Why: string;
  Got: Boolean;
begin
  Got:= IsOpenableSourcePath(APath, Why);
  if Got = AWant then
    Writeln('  ok   ', ALabel)
  else
  begin
    Writeln('  FAIL ', ALabel, ' -- got ', BoolToStr(Got, True), ' (', Why, ')');
    Inc(Fails);
  end;
end;

begin
  { accepted: local drive path, allow-listed source extension }
  Expect('C:\Projects\App\Unit1.pas',            True,  'plain .pas');
  Expect('c:\projects\app\Unit1.PAS',            True,  'extension is case-insensitive');
  Expect('D:\src\Main Form.dfm',                 True,  'space inside a segment');
  Expect('C:\src\App.dpr',                       True,  '.dpr allowed (owner ruling)');
  Expect('C:\src\defs.inc',                      True,  '.inc');
  Expect('C:\sql\MS1.SQL',                       True,  '.sql');
  Expect('C:\src\Form.fmx',                      True,  '.fmx');
  { refused: network and device namespaces }
  Expect('\\server\share\Unit1.pas',             False, 'UNC path (NTLM leak)');
  Expect('//server/share/Unit1.pas',             False, 'forward-slash UNC');
  Expect('\\?\C:\src\Unit1.pas',                 False, 'extended-length prefix');
  Expect('\\.\C:\src\Unit1.pas',                 False, 'device namespace');
  Expect('Unit1.pas',                            False, 'relative path');
  Expect('C:Unit1.pas',                          False, 'drive-relative path');
  { refused: extensions outside the allow-list }
  Expect('C:\src\App.dproj',                     False, '.dproj');
  Expect('C:\src\All.groupproj',                 False, '.groupproj');
  Expect('C:\src\Pkg.dpk',                       False, '.dpk');
  Expect('C:\bin\Pkg.bpl',                       False, '.bpl');
  Expect('C:\bin\tool.exe',                      False, '.exe');
  Expect('C:\src\noext',                         False, 'no extension');
  { refused: shapes that change what the path means }
  Expect('C:\src\a.exe:b.pas',                   False, 'NTFS stream');
  Expect('C:\src\*.pas',                         False, 'wildcard');
  Expect('C:\src\Unit1.pas.',                    False, 'trailing dot');
  Expect('C:\src\dir \Unit1.pas',                False, 'segment ending in a space');
  Expect('C:\src\CON.pas',                       False, 'reserved device name CON');
  Expect('C:\src\nul.pas',                       False, 'reserved device name, lower case');
  Expect('C:\src\COM1.pas',                      False, 'COM1');
  Expect('C:\src\LPT9.pas',                      False, 'LPT9');
  Expect('C:\src\CONIN$.pas',                    False, 'CONIN$');
  Expect('C:\src\COM' + #$00B9 + '.pas',         False, 'COM superscript-one');
  Expect('C:\src\Unit' + #9 + '1.pas',           False, 'control character');
  Expect('',                                     False, 'empty');
  { positive control for the device-name check: a name that merely STARTS with one }
  Expect('C:\src\Console.pas',                   True,  'Console.pas is not CON');
  Expect('C:\src\COM10.pas',                     True,  'COM10 is not a device');

  if Fails = 0 then Writeln('OK') else Writeln(Fails, ' FAILED');
end.
