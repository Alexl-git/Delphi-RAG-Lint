<#
  run_query_text_short_literal.ps1 -- B-27 (INBOX-query-text-short-string-literal.md):
  `query --text "null" --limit 3` returned only comment rows although the five
  'null' string literals ARE in string_literals; and a Pascal-quoted
  `--substring "'declaration'"` found 0.

  ROOT CAUSES (TSQLiteSymbolStore.SearchText, DRagLint.Storage.SQLite.pas):
    a. ORDER BY f.path, sl.start_line LIMIT n -- comment / doc rows (indexed
       since M1b) in an alphabetically earlier file fill a small window before
       any literal is reached. Nothing is dropped; it is ranked out of view.
    b. string_literals.text is stored WITHOUT its Pascal quotes, so a query
       spelled as the source spells it ('declaration') never matches in the
       trigram (substring) table.

  Fixture: aComments.pas (sorts first) holds five comments mentioning null;
  bLiteral.pas holds S := 'null'.

  Asserts:
    1. --limit 3 returns a [pas/literal] row whose text is exactly null (RED before).
    2. --substring "'null'" (Pascal-quoted) returns that literal (RED before).
    3. Positive control: without a limit, the comment rows are still returned
       (ranking did not drop them) and the total is 6.
    4. Positive control: --kind comment returns only comment rows.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-query-text-short-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Q([string[]]$QArgs) {
  $out = & $Exe query @QArgs --db $db --source pas 2>$null
  return @($out | Where-Object { $_ -match '\[pas/' })
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$dir = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null

Write-Ascii (Join-Path $dir 'aComments.pas') @'
unit aComments;
interface
procedure A1;
implementation
procedure A1;
begin
  // first: a null here
  // second: a null here
  // third: a null here
  // fourth: a null here
  // fifth: a null here
end;
end.
'@
Write-Ascii (Join-Path $dir 'bLiteral.pas') @'
unit bLiteral;
interface
function B1: string;
implementation
function B1: string;
begin
  Result := 'null';
end;
end.
'@
$db = Join-Path $dir 'fx.sqlite'
& $Exe index $dir --db $db 2>&1 | Out-Null

Write-Host 'B-27a: a short literal is not ranked out of a small --limit' -ForegroundColor Cyan
$r = Q @('--text', 'null', '--limit', '3')
Check '--limit 3 returns the null literal' (@($r | Where-Object { $_ -match '\[pas/literal\]\s+null\s' }).Count -ge 1) ($r -join ' | ')

Write-Host 'B-27b: a Pascal-quoted --substring query matches the unquoted stored text' -ForegroundColor Cyan
$r = Q @('--text', "'null'", '--substring', '--limit', '10')
Check "--substring 'null' returns the literal" (@($r | Where-Object { $_ -match 'bLiteral\.pas.*\[pas/literal\]' }).Count -eq 1) ($r -join ' | ')

Write-Host 'Positive controls' -ForegroundColor Cyan
$r = Q @('--text', 'null', '--limit', '100')
Check 'unlimited: 5 comments + 1 literal = 6 rows' ($r.Count -eq 6) ("count=" + $r.Count)
$r = Q @('--text', 'null', '--kind', 'comment', '--limit', '100')
Check '--kind comment: 5 rows, all comments' (($r.Count -eq 5) -and (@($r | Where-Object { $_ -notmatch '\[pas/comment\]' }).Count -eq 0)) ($r -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-query-text-short-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
