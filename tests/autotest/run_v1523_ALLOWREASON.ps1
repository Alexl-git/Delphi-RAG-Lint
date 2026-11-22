<#
  run_v1523_ALLOWREASON.ps1 -- `allow --apply --reason` on a line whose dl:ok marker already
  records ANOTHER rule keeps that rule's reviewed reason (v1523 INT-W2b, item e).

  WHY
  ---
  SLZ-S11 (2026-11-22) found `allow --reason` merging the new rule id into the existing marker but
  REPLACING the marker's reason, so the reviewed reason of the neighbour rule vanished silently
  (7 instances repaired by hand in 18b208850; docs\INBOX-allow-apply-overwrites-reason.md).
  The 1.52 INT14 re-stamp (--reason replaces the reason) is right only for a marker that records
  this rule alone.

  WHAT THIS PINS
    * A1: new rule added with --reason: the neighbour's reason (stamp included) is kept and the new
      reason is appended with '; ';
    * A2: re-hash of this rule on a shared marker with --reason: the neighbour's reason is kept,
      the new reason appended;
    * A3 (control, INT14 R1): a marker recording only this rule is still re-stamped (replaced);
    * A4 (control): the same --reason again is a byte-identical no-op.

  Usage: pwsh -File tests\autotest\run_v1523_ALLOWREASON.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,
  [string]$WorkDir = ''
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP "drag-lint-allow-reason-$PID" }
$ErrorActionPreference = 'Continue'
$script:fail = 0; $script:pass = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { $script:pass++; Write-Host "  [PASS] $n" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  [FAIL] $n -- $d" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }
Set-Location $WorkDir

$stamp = 'REVIEWED ' + (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')
$today = 'REVIEWED ' + (Get-Date).ToString('yyyy-MM-dd')

function New-Fixture([string]$Name, [string]$L1) {
  $t = "unit $Name;`r`n`r`ninterface`r`n`r`nprocedure P;`r`n`r`nimplementation`r`n`r`nuses`r`n" +
       "  System.SysUtils;`r`n`r`nprocedure P;`r`nvar`r`n  I: Integer;`r`n  S: string;`r`nbegin`r`n" +
       "  S := '';`r`n  for I := 0 to 3 do`r`n  begin`r`n$L1`r`n`r`n  end;`r`nend;`r`n`r`nend.`r`n"
  $p = Join-Path $WorkDir "$Name.pas"
  [IO.File]::WriteAllText($p, $t, [Text.Encoding]::ASCII)
  return $p
}
function Invoke-Allow([string]$Path, [string[]]$Extra = @()) {
  $out = @(& { $ErrorActionPreference = 'Continue'; & $Exe allow $Path --fix-line 20 --fix-rule concat-in-loop --apply @Extra 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" })
  return @{ Out = ($out -join "`n"); Lines = [IO.File]::ReadAllLines($Path) }
}

# --- A1: NEW rule with --reason on a line that records another rule ----------------------------
$p = New-Fixture 'NewRuleReason' "    S := S + IntToStr(I); // dl:ok other-rule@abcd -- $stamp other reason"
$r = Invoke-Allow $p @('--reason', "$today bounded loop")
Write-Host "  raw A1: $($r.Lines[19])"
Check 'A1 rule appended, neighbour reason kept, new reason appended' ($r.Lines[19] -match ("other-rule@abcd, concat-in-loop@[0-9a-f]{4} -- " + [regex]::Escape("$stamp other reason; $today bounded loop") + '$')) $r.Lines[19]

# --- A2: re-hash of THIS rule on a shared marker with --reason ----------------------------------
$p = New-Fixture 'SharedRestamp' "    S := S + IntToStr(I); // dl:ok other-rule@abcd, concat-in-loop@ffff -- $stamp shared reason"
$r = Invoke-Allow $p @('--reason', "$today re-read")
Write-Host "  raw A2: $($r.Lines[19])"
Check 'A2 neighbour reason kept, new reason appended' ($r.Lines[19] -match ("other-rule@abcd, concat-in-loop@[0-9a-f]{4} -- " + [regex]::Escape("$stamp shared reason; $today re-read") + '$')) $r.Lines[19]
Check 'A2 this rule re-hashed' ($r.Lines[19] -notmatch 'concat-in-loop@ffff') $r.Lines[19]

# --- A3 (control): a marker for this rule alone is re-stamped (INT14 R1 unchanged) ---------------
$p = New-Fixture 'SoleRestamp' "    S := S + IntToStr(I); // dl:ok concat-in-loop@ffff -- $stamp bounded"
$r = Invoke-Allow $p @('--reason', "$today bounded, re-read")
Write-Host "  raw A3: $($r.Lines[19])"
Check 'A3 sole-rule marker reason replaced' ($r.Lines[19] -match ("concat-in-loop@[0-9a-f]{4} -- " + [regex]::Escape("$today bounded, re-read") + '$')) $r.Lines[19]

# --- A4 (control): the same --reason again on A1's line is a no-op ------------------------------
$p = Join-Path $WorkDir 'NewRuleReason.pas'
$snap = [IO.File]::ReadAllText($p)
$null = Invoke-Allow $p @('--reason', "$today bounded loop")
Check 'A4 same --reason again leaves the file byte-identical' ([IO.File]::ReadAllText($p) -eq $snap) ([IO.File]::ReadAllLines($p)[19])

Write-Host "run_v1523_ALLOWREASON: $script:pass pass, $script:fail fail"
if ($script:fail -gt 0) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
