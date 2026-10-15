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
  Refuse(U('\\host\share\x.pas'),                 NOT_LOCAL, 'UH-UNC');
  Refuse(U('\\host@SSL\DavWWWRoot\x.hta'),        NOT_LOCAL, 'UH-WEBDAV');
  Refuse(U('\\?\C:\Projects\x.pas'),              NOT_LOCAL, 'UH-LONG');
  Refuse(U('\\.\pipe\x.pas'),                     NOT_LOCAL, 'UH-DEVICE');
  Refuse(U('//host/share/x.pas'),                 NOT_LOCAL, 'UH-SLASH');
  Refuse(U('Blueprint4.pas'),                     NOT_LOCAL, 'UH-REL');
  Refuse(U('\Projects\x.pas'),                    NOT_LOCAL, 'UH-ROOTED');
  Refuse(U('C:/Projects/x.pas'),                  NOT_LOCAL, 'UH-FWD');
  Refuse(U('C:\Users\x\Downloads\x.py'),          'extension ".py" is not a source file', 'UH-PY');
  Refuse(U('C:\Users\x\Downloads\x.hta'),         'extension ".hta" is not a source file', 'UH-HTA');
  Refuse(U('C:\Windows\System32\calc.exe'),       'extension ".exe" is not a source file', 'UH-EXE');
  Refuse(U('C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj'), 'extension ".dproj" is not a source file', 'UH-DPROJ');
  Refuse(U('C:\Projects\x'),                      'extension "" is not a source file', 'UH-NOEXT');
  Refuse(U('C:\Projects\a.exe:b.pas'),            'character ":" not allowed after the drive', 'UH-ADS');
  Refuse(U('C:\Projects\CON.pas'),                'reserved device name "CON"', 'UH-DEVNAME');
  Refuse('draglint://open?file=C%3A%5Cx.pas%0AC%3A%5Cevil.pas%091&line=1', 'control character in file', 'UH-LF');
  Refuse('draglint://open?file=C%3A%5Cx.pas%095&line=1', 'control character in file', 'UH-TAB');
  Refuse('draglint://open?file=C%3A%5Cx.pas&line=1%0AC%3A%5Cevil.pas', 'control character in line', 'UH-LINELF');
  Refuse(U('C:\Projects\x.pas', '1', '&col=%09'), 'control character in col', 'UH-COLTAB');
  Refuse(U('C:\Projects\x.pas', 'abc'),           'line is not a number', 'UH-LINEABC');
  Refuse(U('C:\Projects\x.pas', '-3'),            'line is not a number', 'UH-LINENEG');
  Refuse(U('C:\Projects\x.pas', '1234567890'),    'line is not a number', 'UH-LINE10');
  Refuse(U('C:\Projects\x.pas', '1', '&col=x'),   'col is not a number', 'UH-COL');
  Refuse('draglint://open?line=1',                'no file= in uri', 'UH-NOFILE');
  Refuse('draglint://open',                       'no file= in uri', 'UH-NOQUERY');
  Refuse('file:///C:/x.pas',                      'not a draglint uri', 'UH-SCHEME');
  Refuse('   ',                                   'no uri given', 'UH-BLANK');
  Refuse(U('C:\Projects\x.dpk'),                  'extension ".dpk" is not a source file', 'UH-DPK');
  Refuse(U('C:\Projects\x.hta.'),                 'extension "." is not a source file', 'UH-TRAILDOT');
  Refuse(U('C:\Projects\x.hta '),                 'extension ".hta " is not a source file', 'UH-TRAILSP');
  Refuse(U('C:\Projects\dir.\x.pas'),             'a path segment ends in a dot or a space', 'UH-SEGDOT');
  Refuse(U('C:\Projects\dir \x.pas'),             'a path segment ends in a dot or a space', 'UH-SEGSP');
  Refuse(U('C:\Projects\x.pas::$DATA'),           'character ":" not allowed after the drive', 'UH-STREAM');
  Refuse(U('C:\Projects\x.pas', '%D9%A1%D9%A2'),  'line is not a number', 'UH-UDIGLINE');
  Refuse(U('C:\Projects\x.pas', '1', '&col=%D9%A1'), 'col is not a number', 'UH-UDIGCOL');
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&file=%5C%5Chost%5Cx.pas', 'duplicate file= in uri', 'UH-DUPFILE');
  Refuse('draglint://open?file=%5C%5Chost%5Cx.pas&line=1&file=C%3A%5CP%5Ca.pas', 'duplicate file= in uri', 'UH-DUPFILE2');
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&line=2', 'duplicate line= in uri', 'UH-DUPLINE');
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&LINE=2', 'duplicate line= in uri', 'UH-DUPCASE');
  Refuse('draglint://open?file=%E2%84%AA%3A%5CP%5Cx.pas&line=1', NOT_LOCAL, 'UH-KELVIN');
  Refuse(U(#$212A + ':\x.pas'),                   NOT_LOCAL, 'UH-KELVIN-CODE');
  Refuse('draglint://open?file=%C4%B0%3A%5CP%5Cx.pas&line=1', NOT_LOCAL, 'UH-DOTTEDI');
  Refuse(U('C:\P\COM' + SUP1 + '.pas'),           'reserved device name "COM' + SUP1 + '"', 'UH-COMSUP1');
  Refuse(U('C:\P\COM' + SUP2 + '.pas'),           'reserved device name "COM' + SUP2 + '"', 'UH-COMSUP2');
  Refuse(U('C:\P\lpt' + SUP3 + '.pas'),           'reserved device name "lpt' + SUP3 + '"', 'UH-LPTSUP3');
  Refuse(U('C:\P\LPT' + SUP1 + '\x.pas'),         'reserved device name "LPT' + SUP1 + '"', 'UH-LPTSUP1');
  Refuse(U('C:\P\COM1.pas'),                      'reserved device name "COM1"', 'UH-COM1');
  Refuse(U('C:\P\x.pa' + #$017F),                 'extension ".pa' + #$017F + '" is not a source file', 'UH-LONGS');
  { the script takes the base name up to the FIRST dot, trimmed: CON.x.pas and CON .pas are CON }
  Refuse(U('C:\P\CON.x.pas'),                     'reserved device name "CON"', 'UH-DEVMULTIDOT');
  Refuse(U('C:\P\NUL .pas'),                      'reserved device name "NUL"', 'UH-DEVSPACE');
  { fix round 1: the script's device digits are [0-9] -- COM0 / LPT0 too (the gate takes only 1-9) }
  Refuse(U('C:\P\COM0.pas'),                      'reserved device name "COM0"', 'UH-COM0');
  Refuse(U('C:\P\lpt0.pas'),                      'reserved device name "lpt0"', 'UH-LPT0');
  Refuse(U('C:\P\LPT0\x.pas'),                    'reserved device name "LPT0"', 'UH-LPT0-DIR');
  { fix round 1: a letter that case-folds onto ASCII (-match folds it) is folded before the device test }
  Refuse(U('C:\P\CON' + #$0130 + 'N$.pas'),       'reserved device name "CON' + #$0130 + 'N$"', 'UH-DEVFOLD');
  Refuse(U('C:\P\con' + #$0131 + 'n$\x.pas'),     'reserved device name "con' + #$0131 + 'n$"', 'UH-DEVFOLD-DIR');
  { fix round 1: a raw non-ASCII key could fold onto file/line/col under .NET ToLower -- refused outright }
  Refuse('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F' + #$0130 + 'LE=%5C%5Chost%5Cx.pas',
         'non-ascii key in uri', 'UH-KEY-NONASCII');
  Refuse('draglint://open?' + #$212A + '=1&file=C%3A%5CP%5Ca.pas', 'non-ascii key in uri', 'UH-KEY-KELVIN');

  { --- accepted: exact pipe payloads --- }
  Accept(U('C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas', '681'),
         'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas' + #9 + '681' + #10, 'UH-GOOD');
  Accept(U('C:\P\a.pas', '12', '&col=5'),         'C:\P\a.pas' + #9 + '12' + #9 + '5' + #10, 'UH-GOOD-COL');
  Accept(U('C:\P\a.pas', '0'),                    'C:\P\a.pas' + #9 + '1' + #10, 'UH-LINE0');
  Accept('draglint://open?file=C%3A%5CP%5Ca.pas', 'C:\P\a.pas' + #9 + '1' + #10, 'UH-NOLINE');
  Accept(U('C:\P\a.pas', ''),                     'C:\P\a.pas' + #9 + '1' + #10, 'UH-EMPTYLINE');
  Accept(U('C:\P\a.pas', '3') + '/',              'C:\P\a.pas' + #9 + '3' + #10, 'UH-SLASHEND');
  Accept(' ' + U('C:\P\a.pas', '3') + '//  ',     'C:\P\a.pas' + #9 + '3' + #10, 'UH-TRIM');
  Accept('DragLint://OPEN?FILE=C%3A%5CP%5Ca.pas&Line=4', 'C:\P\a.pas' + #9 + '4' + #10, 'UH-CASE');
  Accept('draglint://whatever?file=C%3A%5CP%5Ca.pas&line=2&junk&=x&z=', 'C:\P\a.pas' + #9 + '2' + #10, 'UH-HOSTJUNK');
  Accept('draglint://open?file=C%3A%5CP%5Ca+b.pas&line=2', 'C:\P\a+b.pas' + #9 + '2' + #10, 'UH-PLUS');
  Accept('draglint://open?file=C%3A%5CP%5C%2541.pas&line=2', 'C:\P\%41.pas' + #9 + '2' + #10, 'UH-DECODE-ONCE');
  Accept('draglint://open?file=C%3A%5CP%5Cx%FF.pas&line=2', 'C:\P\x%FF.pas' + #9 + '2' + #10, 'UH-BADUTF8');
  Accept(U('C:\P\a.pas', '7', '&col='),           'C:\P\a.pas' + #9 + '7' + #10, 'UH-EMPTYCOL');
  Accept(U('C:\P\a.dfm', '7'),                    'C:\P\a.dfm' + #9 + '7' + #10, 'UH-GOOD-EXT dfm');
  Accept(U('C:\P\a.dpr', '7'),                    'C:\P\a.dpr' + #9 + '7' + #10, 'UH-GOOD-EXT dpr');
  Accept(U('C:\P\a.inc', '7'),                    'C:\P\a.inc' + #9 + '7' + #10, 'UH-GOOD-EXT inc');
  Accept(U('C:\DB\SQL\MS1.SQL', '7'),             'C:\DB\SQL\MS1.SQL' + #9 + '7' + #10, 'UH-GOOD-EXT SQL');
  Accept(U('C:\P\a.fmx', '7'),                    'C:\P\a.fmx' + #9 + '7' + #10, 'UH-GOOD-EXT fmx');
  Accept(U('C:\P\A.PAS', '7'),                    'C:\P\A.PAS' + #9 + '7' + #10, 'UH-GOOD-EXT PAS');
  { keys are never percent-decoded (nor by the script): F%C4%B0LE is its own, ignored, ASCII key }
  Accept('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F%C4%B0LE=%5C%5Chost%5Cx.pas',
         'C:\P\a.pas' + #9 + '1' + #10, 'UH-KEY-PCT');
  Accept(U('C:\P\Console.pas', '7'),              'C:\P\Console.pas' + #9 + '7' + #10, 'UH-NOTCON');

  if Fails = 0 then Writeln('OK') else Writeln(Fails, ' FAILED');
end.
