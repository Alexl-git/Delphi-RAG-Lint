<#
  run_find_callers_json_one_document.ps1 -- name-based `query find-callers`
  answers ONCE across every --db: one JSON document, one total line.

  THE PROBLEM (field report, 2026-09-29). The name-based path printed per store:
    * `--json` over two --db wrote two arrays back to back -- `[...][...]` is not
      a JSON document, so a consumer that parses the output fails on exactly the
      cross-project question (several --db) the verb is used for;
    * `--json` with no hit anywhere wrote NOTHING, where `--resolved --json`
      writes `[]`;
    * the text form wrote one "N caller(s)" line per store.

  THE FIX. AppendReferencesJson collects every store's rows into ONE array;
  PrintReferenceLines prints rows only and the verb prints ONE total.

  Usage: pwsh -File tests/autotest/run_find_callers_json_one_document.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-callers-json-$PID"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Two independent trees, one database each; each has ONE caller of Touch.
foreach ($t in @('A', 'B')) {
  $dir = Join-Path $WorkDir "src$t"
  New-Item -ItemType Directory $dir | Out-Null
  Write-Ascii (Join-Path $dir "u$t.pas") @"
unit u$t;

interface

procedure Touch;
procedure Caller$t;

implementation

procedure Touch;
begin
end;

procedure Caller$t;
begin
  Touch;
end;

end.
"@
  & $Exe index $dir --db (Join-Path $WorkDir "$t.sqlite") --quiet 2>&1 | Out-Null
  Check "precondition: index $t exits 0" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
}
$dbA = Join-Path $WorkDir 'A.sqlite'
$dbB = Join-Path $WorkDir 'B.sqlite'

function Run([string[]]$VerbArgs) {
  $o = @(& $Exe @VerbArgs 2>$null) -join "`n"
  return @{ Code = $LASTEXITCODE; Out = $o }
}
function Parse([string]$Text) {
  try { return @{ Ok = $true; Value = (ConvertFrom-Json -InputObject $Text -NoEnumerate) } }
  catch { return @{ Ok = $false; Value = $null } }
}

Write-Host 'two --db, --json' -ForegroundColor Cyan
$r = Run @('query','find-callers','--name','Touch','--json','--db',$dbA,'--db',$dbB)
Check 'exit 0 with callers' ($r.Code -eq 0) "exit=$($r.Code)"
$p = Parse $r.Out
Check 'ASSERT: stdout is ONE JSON document' $p.Ok "stdout: $($r.Out)"
Check 'ASSERT: the document is an array holding BOTH stores'' callers' `
  ($p.Ok -and ($p.Value -is [array]) -and ($p.Value.Count -eq 2)) "rows=$(if ($p.Ok) { $p.Value.Count } else { '?' })"
Check 'CONTROL: rows keep the full file_path' `
  ($p.Ok -and (@($p.Value | Where-Object { [IO.Path]::IsPathRooted($_.file_path) }).Count -eq 2)) ''

Write-Host ''
Write-Host 'two --db, --json --context 1' -ForegroundColor Cyan
$r = Run @('query','find-callers','--name','Touch','--json','--context','1','--db',$dbA,'--db',$dbB)
$p = Parse $r.Out
Check 'ASSERT: --context keeps ONE document, rows carry context' `
  ($p.Ok -and ($p.Value.Count -eq 2) -and (@($p.Value | Where-Object { $_.context }).Count -eq 2)) "stdout: $($r.Out)"

Write-Host ''
Write-Host 'two --db, text' -ForegroundColor Cyan
$r = Run @('query','find-callers','--name','Touch','--db',$dbA,'--db',$dbB)
$totals = @($r.Out -split "`n" | Where-Object { $_ -match '^\d+ caller\(s\)( \(.*\))?$' })  # main appends the XERJ resolution tally
Check 'ASSERT: ONE total line for the whole answer' ($totals.Count -eq 1) "total lines: $($totals -join ' | ')"
Check 'ASSERT: the total counts both stores' (@($totals | Where-Object { $_ -match '^2 caller\(s\)' }).Count -eq 1) ''

Write-Host ''
Write-Host 'no hit anywhere' -ForegroundColor Cyan
$r = Run @('query','find-callers','--name','NoSuchRoutine','--json','--db',$dbA,'--db',$dbB)
Check 'empty answer exits 1 (documented: an EMPTY answer, not an error)' ($r.Code -eq 1) "exit=$($r.Code)"
$p = Parse $r.Out
Check 'ASSERT: --json with no hit prints [] -- a document, not nothing' `
  ($p.Ok -and ($p.Value -is [array]) -and ($p.Value.Count -eq 0)) "stdout: '$($r.Out)'"
$r = Run @('query','find-callers','--name','NoSuchRoutine','--resolved','--json','--db',$dbA,'--db',$dbB)
$p = Parse $r.Out
Check 'CONTROL: --resolved --json already printed [] -- the two paths now agree' `
  ($p.Ok -and ($p.Value.Count -eq 0)) "stdout: '$($r.Out)'"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-callers-json-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
