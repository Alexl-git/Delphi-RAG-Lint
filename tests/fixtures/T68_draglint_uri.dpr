program T68_draglint_uri;

{ T68: ParseDragLintUri -- the draglint:// URI gate the GUI handler
  (drag-lint-open.exe) calls before it writes anything to the IDE pipe.

  A Delphi port of the validation in the retired charts\src\Open-DragLintUri.ps1.
  The case table is the UH-* table of tests\autotest\run_uri_handler.ps1 (first
  written in the retired charts\src\Test-DragLintProtocol.ps1), case for case: every hostile URI there is refused here, every good one is accepted
  with the same pipe payload. The path verdict itself is
  DragLint.Plugin.OpenSourcePath.IsOpenableSourcePath (T66), so a path refusal
  carries THAT unit's reason text; the URI-level reasons (scheme, duplicate
  key, control character, line/col) are the script's own words.

  Non-ASCII inputs are written as char codes so this file stays 7-bit ASCII. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.OpenSourcePath in '..\..\src\delphi-plugin\DragLint.Plugin.OpenSourcePath.pas',
  DRagLint.Core.DragLintUri in '..\..\src\core\DRagLint.Core.DragLintUri.pas';

const
  NOT_LOCAL = 'not a local drive path (X:\...)';
  SUP1 = #$00B9;
  SUP2 = #$00B2;
  SUP3 = #$00B3;

var
  Fails: Integer = 0;

{ EscapeDataString: every UTF-8 byte outside the unreserved set as %XX. }
function Esc(const S: string): string;
var
  B : Byte;
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for B in TEncoding.UTF8.GetBytes(S) do
      if CharInSet(Char(B), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~']) then
        SB.Append(Char(B))
      else
        SB.Append('%').Append(IntToHex(B, 2));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function U(const AFile: string; const ALine: string = '1'; const AExtra: string = ''): string;
begin
  Result:= 'draglint://open?file=' + Esc(AFile) + '&line=' + ALine + AExtra;
end;

function Show(const S: string): string;
begin
  Result:= StringReplace(StringReplace(S, #9, '<TAB>', [rfReplaceAll]), #10, '<LF>', [rfReplaceAll]);
end;

procedure Refuse(const AUri, AWhy, ALabel: string);
var
  T  : TDragLintTarget;
  Why: string;
begin
  if ParseDragLintUri(AUri, T, Why) then
  begin
    Writeln('  FAIL ', ALabel, ' -- accepted: ', Show(T.Payload));
    Inc(Fails);
  end
  else if Why <> AWhy then
  begin
    Writeln('  FAIL ', ALabel, ' -- reason [', Why, '], want [', AWhy, ']');
    Inc(Fails);
  end
  else
    Writeln('  ok   ', ALabel);
end;

procedure Accept(const AUri, APayload, ALabel: string);
var
  T  : TDragLintTarget;
  Why: string;
begin
  if not ParseDragLintUri(AUri, T, Why) then
  begin
    Writeln('  FAIL ', ALabel, ' -- refused: ', Why);
    Inc(Fails);
  end
  else if T.Payload <> APayload then
  begin
    Writeln('  FAIL ', ALabel, ' -- payload [', Show(T.Payload), '], want [', Show(APayload), ']');
    Inc(Fails);
  end
  else
    Writeln('  ok   ', ALabel);
end;

begin
  { --- hostile: the UH-* table of run_uri_handler.ps1 --- }
  Refuse(U('\\host\share\x.pas'),                 NOT_LOCAL, 'UH-UNC');  // dl:ok hardcoded-absolute-path@92ea -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('\\host@SSL\DavWWWRoot\x.hta'),        NOT_LOCAL, 'UH-WEBDAV');  // dl:ok hardcoded-absolute-path@6601 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('\\?\C:\Projects\x.pas'),              NOT_LOCAL, 'UH-LONG');  // dl:ok hardcoded-absolute-path@44b2 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('\\.\pipe\x.pas'),                     NOT_LOCAL, 'UH-DEVICE');
  Refuse(U('//host/share/x.pas'),                 NOT_LOCAL, 'UH-SLASH');  // dl:ok hardcoded-absolute-path@f3e7 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('Blueprint4.pas'),                     NOT_LOCAL, 'UH-REL');
  Refuse(U('\Projects\x.pas'),                    NOT_LOCAL, 'UH-ROOTED');
  Refuse(U('C:/Projects/x.pas'),                  NOT_LOCAL, 'UH-FWD');  // dl:ok hardcoded-absolute-path@2df9 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Users\x\Downloads\x.py'),          'extension ".py" is not a source file', 'UH-PY');  // dl:ok hardcoded-absolute-path@c6e6 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Users\x\Downloads\x.hta'),         'extension ".hta" is not a source file', 'UH-HTA');  // dl:ok hardcoded-absolute-path@436c -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Windows\System32\calc.exe'),       'extension ".exe" is not a source file', 'UH-EXE');  // dl:ok hardcoded-absolute-path@a8cc -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj'), 'extension ".dproj" is not a source file', 'UH-DPROJ');  // dl:ok hardcoded-absolute-path@c77c -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x'),                      'extension "" is not a source file', 'UH-NOEXT');  // dl:ok hardcoded-absolute-path@905d -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\a.exe:b.pas'),            'character ":" not allowed after the drive', 'UH-ADS');  // dl:ok hardcoded-absolute-path@248a -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\CON.pas'),                'reserved device name "CON"', 'UH-DEVNAME');  // dl:ok hardcoded-absolute-path@0a20 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse('draglint://open?file=C%3A%5Cx.pas%0AC%3A%5Cevil.pas%091&line=1', 'control character in file', 'UH-LF');
  Refuse('draglint://open?file=C%3A%5Cx.pas%095&line=1', 'control character in file', 'UH-TAB');
  Refuse('draglint://open?file=C%3A%5Cx.pas&line=1%0AC%3A%5Cevil.pas', 'control character in line', 'UH-LINELF');
  Refuse(U('C:\Projects\x.pas', '1', '&col=%09'), 'control character in col', 'UH-COLTAB');  // dl:ok hardcoded-absolute-path@2b0d -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', 'abc'),           'line is not a number', 'UH-LINEABC');  // dl:ok hardcoded-absolute-path@4aea -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', '-3'),            'line is not a number', 'UH-LINENEG');  // dl:ok hardcoded-absolute-path@3c5b -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', '1234567890'),    'line is not a number', 'UH-LINE10');  // dl:ok hardcoded-absolute-path@86e8 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', '1', '&col=x'),   'col is not a number', 'UH-COL');  // dl:ok hardcoded-absolute-path@b893 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse('draglint://open?line=1',                'no file= in uri', 'UH-NOFILE');
  Refuse('draglint://open',                       'no file= in uri', 'UH-NOQUERY');
  Refuse('file:///C:/x.pas',                      'not a draglint uri', 'UH-SCHEME');
  Refuse('   ',                                   'no uri given', 'UH-BLANK');
  Refuse(U('C:\Projects\x.dpk'),                  'extension ".dpk" is not a source file', 'UH-DPK');  // dl:ok hardcoded-absolute-path@d78d -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.hta.'),                 'extension "." is not a source file', 'UH-TRAILDOT');  // dl:ok hardcoded-absolute-path@245e -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.hta '),                 'extension ".hta " is not a source file', 'UH-TRAILSP');  // dl:ok hardcoded-absolute-path@f0b7 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\dir.\x.pas'),             'a path segment ends in a dot or a space', 'UH-SEGDOT');  // dl:ok hardcoded-absolute-path@28ef -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\dir \x.pas'),             'a path segment ends in a dot or a space', 'UH-SEGSP');  // dl:ok hardcoded-absolute-path@a462 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas::$DATA'),           'character ":" not allowed after the drive', 'UH-STREAM');  // dl:ok hardcoded-absolute-path@968a -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', '%D9%A1%D9%A2'),  'line is not a number', 'UH-UDIGLINE');  // dl:ok hardcoded-absolute-path@53b2 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\Projects\x.pas', '1', '&col=%D9%A1'), 'col is not a number', 'UH-UDIGCOL');  // dl:ok hardcoded-absolute-path@6d17 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&file=%5C%5Chost%5Cx.pas', 'duplicate file= in uri', 'UH-DUPFILE');
  Refuse('draglint://open?file=%5C%5Chost%5Cx.pas&line=1&file=C%3A%5CP%5Ca.pas', 'duplicate file= in uri', 'UH-DUPFILE2');
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&line=2', 'duplicate line= in uri', 'UH-DUPLINE');
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&LINE=2', 'duplicate line= in uri', 'UH-DUPCASE');
  Refuse('draglint://open?file=%E2%84%AA%3A%5CP%5Cx.pas&line=1', NOT_LOCAL, 'UH-KELVIN');
  Refuse(U(#$212A + ':\x.pas'),                   NOT_LOCAL, 'UH-KELVIN-CODE');
  Refuse('draglint://open?file=%C4%B0%3A%5CP%5Cx.pas&line=1', NOT_LOCAL, 'UH-DOTTEDI');
  Refuse(U('C:\P\COM' + SUP1 + '.pas'),           'reserved device name "COM' + SUP1 + '"', 'UH-COMSUP1');  // dl:ok hardcoded-absolute-path@73c5 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\COM' + SUP2 + '.pas'),           'reserved device name "COM' + SUP2 + '"', 'UH-COMSUP2');  // dl:ok hardcoded-absolute-path@f837 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\lpt' + SUP3 + '.pas'),           'reserved device name "lpt' + SUP3 + '"', 'UH-LPTSUP3');  // dl:ok hardcoded-absolute-path@1f51 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\LPT' + SUP1 + '\x.pas'),         'reserved device name "LPT' + SUP1 + '"', 'UH-LPTSUP1');  // dl:ok hardcoded-absolute-path@a389 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\COM1.pas'),                      'reserved device name "COM1"', 'UH-COM1');  // dl:ok hardcoded-absolute-path@54f1 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\x.pa' + #$017F),                 'extension ".pa' + #$017F + '" is not a source file', 'UH-LONGS');  // dl:ok hardcoded-absolute-path@4298 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  { the script takes the base name up to the FIRST dot, trimmed: CON.x.pas and CON .pas are CON }
  Refuse(U('C:\P\CON.x.pas'),                     'reserved device name "CON"', 'UH-DEVMULTIDOT');  // dl:ok hardcoded-absolute-path@7702 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\NUL .pas'),                      'reserved device name "NUL"', 'UH-DEVSPACE');  // dl:ok hardcoded-absolute-path@14df -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  { fix round 1: the script's device digits are [0-9] -- COM0 / LPT0 too (the gate takes only 1-9) }
  Refuse(U('C:\P\COM0.pas'),                      'reserved device name "COM0"', 'UH-COM0');  // dl:ok hardcoded-absolute-path@16fb -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\lpt0.pas'),                      'reserved device name "lpt0"', 'UH-LPT0');  // dl:ok hardcoded-absolute-path@2901 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\LPT0\x.pas'),                    'reserved device name "LPT0"', 'UH-LPT0-DIR');  // dl:ok hardcoded-absolute-path@9ff3 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  { fix round 1: a letter that case-folds onto ASCII (-match folds it) is folded before the device test }
  Refuse(U('C:\P\CON' + #$0130 + 'N$.pas'),       'reserved device name "CON' + #$0130 + 'N$"', 'UH-DEVFOLD');  // dl:ok hardcoded-absolute-path@5284 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Refuse(U('C:\P\con' + #$0131 + 'n$\x.pas'),     'reserved device name "con' + #$0131 + 'n$"', 'UH-DEVFOLD-DIR');  // dl:ok hardcoded-absolute-path@9fb7 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  { fix round 1: a raw non-ASCII key could fold onto file/line/col under .NET ToLower -- refused outright }
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F' + #$0130 + 'LE=%5C%5Chost%5Cx.pas',
         'non-ascii key in uri', 'UH-KEY-NONASCII');
  Refuse('draglint://open?' + #$212A + '=1&file=C%3A%5CP%5Ca.pas', 'non-ascii key in uri', 'UH-KEY-KELVIN');

  { --- accepted: exact pipe payloads --- }
  Accept(U('C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas', '681'),  // dl:ok hardcoded-absolute-path@9a41 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
         'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas' + #9 + '681' + #10, 'UH-GOOD');  // dl:ok hardcoded-absolute-path@882c -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.pas', '12', '&col=5'),         'C:\P\a.pas' + #9 + '12' + #9 + '5' + #10, 'UH-GOOD-COL');  // dl:ok hardcoded-absolute-path@d9cc -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.pas', '0'),                    'C:\P\a.pas' + #9 + '1' + #10, 'UH-LINE0');  // dl:ok hardcoded-absolute-path@2576 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('draglint://open?file=C%3A%5CP%5Ca.pas', 'C:\P\a.pas' + #9 + '1' + #10, 'UH-NOLINE');  // dl:ok hardcoded-absolute-path@bffb -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.pas', ''),                     'C:\P\a.pas' + #9 + '1' + #10, 'UH-EMPTYLINE');  // dl:ok hardcoded-absolute-path@0015 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.pas', '3') + '/',              'C:\P\a.pas' + #9 + '3' + #10, 'UH-SLASHEND');  // dl:ok hardcoded-absolute-path@0b67 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(' ' + U('C:\P\a.pas', '3') + '//  ',     'C:\P\a.pas' + #9 + '3' + #10, 'UH-TRIM');  // dl:ok hardcoded-absolute-path@400c -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('DragLint://OPEN?FILE=C%3A%5CP%5Ca.pas&Line=4', 'C:\P\a.pas' + #9 + '4' + #10, 'UH-CASE');  // dl:ok hardcoded-absolute-path@5508 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('draglint://whatever?file=C%3A%5CP%5Ca.pas&line=2&junk&=x&z=', 'C:\P\a.pas' + #9 + '2' + #10, 'UH-HOSTJUNK');  // dl:ok hardcoded-absolute-path@65e7 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('draglint://open?file=C%3A%5CP%5Ca+b.pas&line=2', 'C:\P\a+b.pas' + #9 + '2' + #10, 'UH-PLUS');  // dl:ok hardcoded-absolute-path@8be6 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('draglint://open?file=C%3A%5CP%5C%2541.pas&line=2', 'C:\P\%41.pas' + #9 + '2' + #10, 'UH-DECODE-ONCE');  // dl:ok hardcoded-absolute-path@5e90 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept('draglint://open?file=C%3A%5CP%5Cx%FF.pas&line=2', 'C:\P\x%FF.pas' + #9 + '2' + #10, 'UH-BADUTF8');  // dl:ok hardcoded-absolute-path@eac0 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.pas', '7', '&col='),           'C:\P\a.pas' + #9 + '7' + #10, 'UH-EMPTYCOL');  // dl:ok hardcoded-absolute-path@89c9 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.dfm', '7'),                    'C:\P\a.dfm' + #9 + '7' + #10, 'UH-GOOD-EXT dfm');  // dl:ok hardcoded-absolute-path@275c -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.dpr', '7'),                    'C:\P\a.dpr' + #9 + '7' + #10, 'UH-GOOD-EXT dpr');  // dl:ok hardcoded-absolute-path@8d1b -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.inc', '7'),                    'C:\P\a.inc' + #9 + '7' + #10, 'UH-GOOD-EXT inc');  // dl:ok hardcoded-absolute-path@ffea -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\DB\SQL\MS1.SQL', '7'),             'C:\DB\SQL\MS1.SQL' + #9 + '7' + #10, 'UH-GOOD-EXT SQL');  // dl:ok hardcoded-absolute-path@193a -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\a.fmx', '7'),                    'C:\P\a.fmx' + #9 + '7' + #10, 'UH-GOOD-EXT fmx');  // dl:ok hardcoded-absolute-path@a9d4 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\A.PAS', '7'),                    'C:\P\A.PAS' + #9 + '7' + #10, 'UH-GOOD-EXT PAS');  // dl:ok hardcoded-absolute-path@a6b7 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  { keys are never percent-decoded (nor by the script): F%C4%B0LE is its own, ignored, ASCII key }
  Accept('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F%C4%B0LE=%5C%5Chost%5Cx.pas',
         'C:\P\a.pas' + #9 + '1' + #10, 'UH-KEY-PCT');  // dl:ok hardcoded-absolute-path@662b -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened
  Accept(U('C:\P\Console.pas', '7'),              'C:\P\Console.pas' + #9 + '7' + #10, 'UH-NOTCON');  // dl:ok hardcoded-absolute-path@0f94 -- REVIEWED 2026-10-15: hostile-path test data for the draglint:// gate, never opened

  if Fails = 0 then Writeln('OK') else Writeln(Fails, ' FAILED');
end.
