<#
  run_v1523_COLS-TAILS.ps1 -- 1.52.3 COLS-TAILS: finding columns are CHARACTER (UTF-16) columns
  after 2-byte, 3-byte and non-BMP (4-byte, surrogate pair) characters, on every column path the
  lane fence covers. Verifies the BK-COLS2 tails closed by 9de010441 stay closed and widens them
  from e-acute (2 bytes) to 3- and 4-byte characters.

  Each check computes the expected column from the line text (String.IndexOf = UTF-16 units) and
  first asserts that it DIFFERS from the UTF-8 byte column, so a byte-column engine fails the check
  (the check is capable of failing; positive control built in).

    Q2/Q3/Q4  .scm rule (deprecated-rtl-function) after a 2-, 3-, 4-byte character   QueryRules.Run
    Q5        .scm rule after a BLANKED inactive {$IFDEF} holding non-BMP + 3-byte     QueryRules ColSource
    L1        field-by-name-in-loop after a non-BMP character                         Linter
    L2        raise-bare-exception after non-BMP + 3-byte                              AST checks CharCol
    A1        unconnected-control (.pas field after a non-BMP comment)                 V151 DFM-A CharCol
    D1        lint of a .dfm: parser-error after a non-BMP character                   Linter.CollectDfmParseErrors
    D2        index DIAG line for the same .dfm parse error                            Parser.DFM
    T1        hardcoded-string after a non-BMP + 3-byte literal                        V151.TXT TxtScanText

  Usage: pwsh -File run_v1523_COLS-TAILS.ps1 [-Exe <drag-lint.exe>]   exit 0 = all pass, 1 = a fail.
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { $script:Pass++; Write-Host "[PASS] $n" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "[FAIL] $n  $d" -ForegroundColor Red }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1523-cols-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
try {
  $U8 = New-Object Text.UTF8Encoding($false)
  $C2 = [string][char]0xFC                      # u-umlaut: 2 UTF-8 bytes, 1 UTF-16 unit
  $C3 = [string][char]0x20AC                    # euro sign: 3 UTF-8 bytes, 1 UTF-16 unit
  $C4 = [char]::ConvertFromUtf32(0x1F600)       # U+1F600: 4 UTF-8 bytes, 2 UTF-16 units
  $Pas = @'
unit uCols;

interface

uses Classes, Forms, StdCtrls;

type
  TForm1 = class(TForm)
    {X~4} Button1: TEdit;
  end;

procedure P1(PC: PChar; Q: TObject);
procedure Say(const S: string);

implementation

{$R *.dfm}

uses SysUtils, DB;

procedure Say(const S: string);
begin
  if S = '' then Exit;
end;

procedure P1(PC: PChar; Q: TObject);
var
  S: string;
  I: Integer;
begin
  S:= '~2'; S:= StrPas(PC); // Q2
  S:= '~3'; S:= StrPas(PC); // Q3
  S:= '~4'; S:= StrPas(PC); // Q4
  {$IFDEF NEVER_DEFINED_X} ~4~3 {$ENDIF} S:= StrPas(PC); // Q5
  for I:= 0 to 3 do begin S:= '~4'; S:= TDataSet(Q).FieldByName('a').AsString; end; // L1
  for I:= 0 to 3 do begin S:= '~4~3'; raise Exception.Create('x'); end; // L2
  Say('~4~3 is here' + 'Hello there my friend'); // T1
end;

end.
'@
  $PasText = ($Pas -replace "`r?`n", "`r`n").Replace('~2', $C2).Replace('~3', $C3).Replace('~4', $C4)
  [IO.File]::WriteAllBytes((Join-Path $Work 'uCols.pas'), $U8.GetBytes($PasText))
  $DfmText = "object Form1: TForm1`r`n  Caption = '$C4$C3$C2'`r`n  object Button1: TButton`r`n    Caption = '$C4' @@@`r`n  end`r`nend`r`n"
  [IO.File]::WriteAllBytes((Join-Path $Work 'uCols.dfm'), $U8.GetBytes($DfmText))
  $Db = Join-Path $Work 'cols.sqlite'
  $idx = (& { $ErrorActionPreference = 'Continue'; & $Exe index $Work --db $Db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $idx; throw 'index failed' }

  function LintJ([string]$file, [string[]]$extra) {
    $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint (Join-Path $Work $file) --db $Db --json @extra 2>$null }) -join "`n"
    $arr = @(); try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { Write-Host ('  unparsed: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length))) }
    return ,$arr
  }
  $PasF = LintJ 'uCols.pas' @('--full-rules')
  $TxtF = LintJ 'uCols.pas' @('--enable', 'hardcoded-string')
  $DfmF = LintJ 'uCols.dfm' @('--full-rules')

  $PasLines = $PasText -split "`r`n"
  $DfmLines = $DfmText -split "`r`n"
  # 1-based line number of the line that carries ATag; 0 when absent.
  function LineOf([string[]]$lines, [string]$tag) {
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($tag)) { return $i + 1 } }
    return 0
  }
  # Character column (UTF-16, 1-based) and UTF-8 byte column of AWord on ALine.
  function Cols([string]$line, [string]$word) {
    $k = $line.IndexOf($word)
    return @(($k + 1), ($U8.GetByteCount($line.Substring(0, $k)) + 1))
  }
  function ColCheck([string]$name, $findings, [string]$rule, [string[]]$lines, [string]$tag, [string]$word) {
    $ln = LineOf $lines $tag
    $cc = Cols $lines[$ln - 1] $word
    $hit = @($findings | Where-Object { $_.rule -eq $rule -and [int]$_.start_line -eq $ln })
    $got = ($hit | ForEach-Object { $_.start_col }) -join ','
    Check "$name $rule line $ln at character column $($cc[0]) (byte column $($cc[1]))" `
      (($cc[0] -ne $cc[1]) -and ($hit.Count -ge 1) -and ([int]$hit[0].start_col -eq $cc[0])) "got=$got"
  }

  ColCheck 'Q2' $PasF 'deprecated-rtl-function' $PasLines '// Q2' 'StrPas'
  ColCheck 'Q3' $PasF 'deprecated-rtl-function' $PasLines '// Q3' 'StrPas'
  ColCheck 'Q4' $PasF 'deprecated-rtl-function' $PasLines '// Q4' 'StrPas'
  ColCheck 'Q5' $PasF 'deprecated-rtl-function' $PasLines '// Q5' 'StrPas'
  ColCheck 'L1' $PasF 'field-by-name-in-loop'   $PasLines '// L1' 'FieldByName'
  ColCheck 'L2' $PasF 'raise-bare-exception'    $PasLines '// L2' 'raise'
  ColCheck 'A1' $PasF 'unconnected-control'     $PasLines 'Button1: TEdit' 'Button1'
  ColCheck 'T1' $TxtF 'hardcoded-string'        $PasLines '// T1' "'Hello"
  ColCheck 'D1' $DfmF 'parser-error'            $DfmLines '@@@' '@@@'

  $dl = LineOf $DfmLines '@@@'
  $dc = Cols $DfmLines[$dl - 1] '@@@'
  $diag = @(($idx -split "`r?`n") | Where-Object { $_ -match 'uCols\.dfm\((\d+),(\d+)\): parse error' })
  $dcol = if ($diag.Count -gt 0 -and $diag[0] -match 'uCols\.dfm\((\d+),(\d+)\)') { [int]$Matches[2] } else { -1 }
  Check "D2 index DIAG for the .dfm parse error prints character column $($dc[0]) (byte column $($dc[1]))" `
    (($dc[0] -ne $dc[1]) -and ($dcol -eq $dc[0])) "got=$dcol line=$($diag | Select-Object -First 1)"
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { $null = $_ }
}
Write-Host ("RESULT: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
