<#
  run_multiline_string.ps1 -- P1: Delphi 12+ multi-line string literals
  ('''<EOL> ... <EOL>''') made a whole unit unparseable.

  DIAGNOSIS (measured 2026-09-23, before any change). Two layers, both needed:
    * GRAMMAR (tree-sitter-delphi13, another team's repo). It HAS a
      triple-quote token, /'''[\s\S]*?'''/, and a body of plain text parses.
      But the single-quoted token /'([^']|'')*'/ admits newlines, so a body
      holding an ODD number of apostrophes (`it's`, `a 'b' c`) lexes as a
      different, shorter string and the unit dies with syntax-error at 1:1 --
      with --no-preprocess too. The 5-quote form ('''''<EOL>..'''''), which
      dcc accepts so that ''' may appear inside, is not recognised at all.
    * PREPROCESSOR (this repo). DRagLint.Preprocess.Lexer bounds a '-string at
      end of line, so a multi-line body is lexed as CODE: a `{$IFDEF X}` in
      the body becomes a live directive and blanks real code after it.
  THE NEUTRALISATION (DRagLint.Preprocess.Tolerance.NeutralizeMultilineStrings,
  run unconditionally at the top of Preprocess, before the directive lexer):
  inside a recognised literal, every apostrophe and open-brace, and the '(' of
  a '(*', become a space; a 5+-quote delimiter becomes ''' plus spaces. The
  grammar's own triple-quote token then matches, the lexer sees no directive,
  and Length(output) = Length(input) with every LF in place (offset identity).
  The literal's TEXT keeps everything but those characters.

  CONTROLS. uPlain.pas (ordinary strings: '''', 'it''s', '' -- no multi-line
  literal) must come out of preprocess-file byte-identical, and must lint
  clean on the pre-fix engine as well.

  Run from a NEUTRAL CWD. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($Path, $norm, [Text.Encoding]::ASCII)
}

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_mlstr_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$db = Join-Path $work 'mlstr.sqlite'

Write-Ascii (Join-Path $work 'uMl.pas') @'
unit uMl;

interface

function Page: string;
function Five: string;
function Guarded: string;
function After: Integer;

implementation

function Page: string;
begin
  Result := '''
    <html lang="en">
    it's a { brace and a (* star
    '''
    + 'tail';
end;

function Five: string;
begin
  Result := '''''
    holds ''' inside
    ''''';
end;

function Guarded: string;
begin
  Result := '''
    {$IFDEF NEVER_DEFINED}
    text
    ''';
end;

function After: Integer;
begin
  Result := 42;
end;

end.
'@

Write-Ascii (Join-Path $work 'uPlain.pas') @'
unit uPlain;

interface

function Q: string;

implementation

function Q: string;
begin
  Result := '''' + 'it''s' + '' + '''x''';
end;

end.
'@

Push-Location $env:TEMP
try {
  Write-Host 'CONTROL -- ordinary strings are untouched:' -ForegroundColor Cyan
  $plainIn = [IO.File]::ReadAllBytes((Join-Path $work 'uPlain.pas'))
  $plainOutFile = Join-Path $work 'uPlain.pp'
  cmd /c "`"$exePath`" preprocess-file --file `"$(Join-Path $work 'uPlain.pas')`" > `"$plainOutFile`" 2>NUL"
  $plainOut = [IO.File]::ReadAllBytes($plainOutFile)
  Check 'uPlain preprocess-file output is byte-identical to the input' ([Linq.Enumerable]::SequenceEqual([byte[]]$plainIn, [byte[]]$plainOut)) "in=$($plainIn.Length) out=$($plainOut.Length)"
  $pl = (& $exePath lint (Join-Path $work 'uPlain.pas') 2>&1) -join "`n"
  Check 'uPlain lints with no syntax/parser error' ($pl -notmatch 'syntax-error|parser-error')

  Write-Host 'P1 -- multi-line literals:' -ForegroundColor Cyan
  $mlIn = [IO.File]::ReadAllBytes((Join-Path $work 'uMl.pas'))
  $mlOutFile = Join-Path $work 'uMl.pp'
  cmd /c "`"$exePath`" preprocess-file --file `"$(Join-Path $work 'uMl.pas')`" > `"$mlOutFile`" 2>NUL"
  $mlOut = [IO.File]::ReadAllBytes($mlOutFile)
  Check 'offset identity: preprocess-file output length = input length' ($mlIn.Length -eq $mlOut.Length) "in=$($mlIn.Length) out=$($mlOut.Length)"
  $lfIn  = @($mlIn  | Where-Object { $_ -eq 10 }).Count
  $lfOut = @($mlOut | Where-Object { $_ -eq 10 }).Count
  Check 'every LF preserved' ($lfIn -eq $lfOut) "in=$lfIn out=$lfOut"

  $ml = (& $exePath lint (Join-Path $work 'uMl.pas') 2>&1) -join "`n"
  Check 'uMl lints with no syntax/parser error' ($ml -notmatch 'syntax-error|parser-error') (($ml -split "`n" | Select-String 'error') -join ' | ')

  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $j = (& $exePath sql --db $db --query "select coalesce(impl_start_line, 0) from symbols where name = 'After' and kind = 'function'" --json 2>$null) -join "`n" | ConvertFrom-Json
  $lines = @($j.rows | ForEach-Object { [int]$_[0] })
  Check 'After (the routine behind the {$IFDEF}-bearing literal) has its body at line 36' ($lines -contains 36) ("impl_start_line: " + ($lines -join ','))
  $lit = (& $exePath sql --db $db --query "select text from string_literals where text like '%html lang%'" --json 2>$null) -join "`n" | ConvertFrom-Json
  Check 'the Page literal text is harvested (content kept)' ($lit.row_count -ge 1) "rows=$($lit.row_count)"
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
