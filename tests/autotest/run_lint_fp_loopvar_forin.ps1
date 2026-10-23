<#
  run_lint_fp_loopvar_forin.ps1 -- N-15 (INBOX-loop-var-after-loop-nested-forin).

  loop-var-after-loop fired on a counter that a counted `for lI := 0 to ..` loop
  left behind and that a LATER `for lI in ..` loop re-binds. The for-in defines
  lI on entry to its body (CFG EntryDefs), but the post-loop walk only treated an
  assignment item as a redefinition, so every read of lI inside the for-in body
  (also in a nested for-in header) was reported. Real case: FeatureGen.Site.pas
  BuildCliReference, 4 findings. The 15-line repro in the INBOX note used two
  for-in loops, which is why it did not trigger: the counted loop is the trigger.

  Positive controls: a read of the counter after the counted loop with no
  re-binding, and a read AFTER the re-binding for-in loop has ended, must still
  be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-loopvar-forin-$PID"
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
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$src = @'
unit fploopvar;

interface

type
  TRow = record
    Items: TArray<Integer>;
  end;

function Rebound(const pRows: TArray<TRow>; const pIdx: TArray<Integer>): Integer;
function Stale(const pRows: TArray<TRow>): Integer;
function AfterForIn(const pRows: TArray<TRow>; const pIdx: TArray<Integer>): Integer;

implementation

function Rebound(const pRows: TArray<TRow>; const pIdx: TArray<Integer>): Integer;
var
  lI, lS: Integer;
begin
  Result := 0;
  for lI := 0 to High(pRows) do
    Result := Result + Length(pRows[lI].Items);
  try
    for lI in pIdx do
      for lS in pRows[lI].Items do
        Result := Result + lS;
    for lI in pIdx do
      Result := Result + pRows[lI].Items[0];
  finally
    Result := Result + 1;
  end;
end;

function Stale(const pRows: TArray<TRow>): Integer;
var
  lI: Integer;
begin
  Result := 0;
  for lI := 0 to High(pRows) do
    Result := Result + Length(pRows[lI].Items);
  Result := Result + lI;
end;

function AfterForIn(const pRows: TArray<TRow>; const pIdx: TArray<Integer>): Integer;
var
  lI: Integer;
begin
  Result := 0;
  for lI := 0 to High(pRows) do
    Result := Result + Length(pRows[lI].Items);
  for lI in pIdx do
    Result := Result + lI;
  Result := Result + lI;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fploopvar.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule loop-var-after-loop 2>$null | Out-String)
$rebound = @([regex]::Matches($out, 'fploopvar\.pas:(2[4-9]|30):')).Count

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'a for-in that re-binds the counter: no finding in its body or nested header' `
  ($rebound -eq 0) "(found $rebound in lines 24-30)"
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'the counter read after the counted loop with no re-binding is still reported' `
  ($out -match 'fploopvar\.pas:41:') 'else the fix just disabled the rule'
Check 'the counter read after the re-binding for-in has ENDED is still reported' `
  ($out -match 'fploopvar\.pas:53:') 'else the for-in def leaks past its loop'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
