<#
  run_lsp_switch_guard.ps1 -- drag-lint-switch must be able to turn the IDE's
  custom LSP entry off AND put it back, exactly.

  WHY THIS TOOL EXISTS AT ALL: it is the rollback lever for registering
  drag-lint as the IDE's Code Insight LSP. That sets the bar -- it has to work
  when the thing it switches is broken, from a terminal, with the IDE unusable.
  A backup that cannot be restored is worse than no backup, because it is
  believed.

  RUNS AGAINST A SCRATCH KEY, NEVER THE LIVE ONE. --reg-root points every
  mutating path at HKCU\Software\DragLintSwitchTest for the duration. Testing
  the real Software\Embarcadero\BDS\37.0\LSP\UserDefined would mean the battery
  rewrote the developer's IDE configuration on each of its 300+ runs, so the
  guard would be disabled and the mutating paths would end up untested -- which
  is how the dangerous code ends up being the unguarded code.

  THE ASSERTION THAT MATTERS is the round trip: --off then `reg import` of the
  backup must restore every value, of every type, byte-for-byte. InitString is
  the one that decides it -- it is a MULTI-LINE REG_SZ, and a plain
  "key"="value" .reg line cannot represent an embedded newline at all. A backup
  written the easy way looks fine, imports without error, and silently loses
  the value. So the guard asserts the restored string still contains its CRLFs.

  POSITIVE CONTROL: case 5 asserts --off on an absent entry reports "already"
  (exit 1) and writes NO backup file. Without it, a tool that did nothing at
  all would pass every "the key is gone" assertion here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint-switch.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-switch-guard",
  [string]$RegRoot = 'Software\DragLintSwitchTest\LSP\UserDefined'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: drag-lint-switch.exe not found: $Exe" -ForegroundColor Red
  Write-Host '       build it with build\build_lsp_switch.bat' -ForegroundColor Red
  exit 2
}
$Exe = (Resolve-Path $Exe).Path

$psRoot = "HKCU:\$RegRoot"
$entry  = "$psRoot\drag-lint"
function Clean-Scratch {
  $top = 'HKCU:\Software\DragLintSwitchTest'
  if (Test-Path $top) { Remove-Item -Path $top -Recurse -Force -ErrorAction SilentlyContinue }
}
Clean-Scratch
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# A file that really exists -- --on refuses a missing executable on purpose,
# because a registered entry pointing at nothing makes the IDE retry forever.
$fakeServer = Join-Path $WorkDir 'pretend-server.exe'
Set-Content -LiteralPath $fakeServer -Value 'not really an exe' -Encoding ascii

# NOT named $Args: that is a PowerShell AUTOMATIC variable, and shadowing it
# here silently passed NOTHING to the exe -- which then ran its default
# --status against the LIVE registry root and reported success, so the first
# assertion "PASSED" while testing the opposite of what it claimed.
function Run-Switch([string[]]$SwitchArgs) {
  $out = & $Exe @SwitchArgs 2>&1 | Out-String
  return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

# ---- case 1: --on registers, and is idempotent ----
Write-Host ''
Write-Host 'CASE 1: --on writes the entry, and says so if already on' -ForegroundColor Cyan
$r = Run-Switch @('--delphi','--on','--exe',$fakeServer,'--reg-root',$RegRoot)
Check '--on succeeded (exit 0)' ($r.Code -eq 0) "exit=$($r.Code) $($r.Out.Trim())"
Check 'the entry exists' (Test-Path $entry)
$r2 = Run-Switch @('--delphi','--on','--exe',$fakeServer,'--reg-root',$RegRoot)
Check '--on again reports already (exit 1, not an error)' ($r2.Code -eq 1) "exit=$($r2.Code)"

# ---- case 2: the values, and their TYPES ----
Write-Host ''
Write-Host 'CASE 2: schema matches what the IDE dialog writes' -ForegroundColor Cyan
$k = Get-Item $entry
$p = Get-ItemProperty $entry
Check 'Name'       ($p.Name -eq 'drag-lint')          "got: $($p.Name)"
Check 'FileName'   ($p.FileName -eq $fakeServer)      "got: $($p.FileName)"
Check 'LanguageId' ($p.LanguageId -eq 'pascal')       "got: $($p.LanguageId)"
Check 'Timeout is a DWORD of 15000' `
  (($k.GetValueKind('Timeout') -eq 'DWord') -and ($p.Timeout -eq 15000)) `
  "got: $($k.GetValueKind('Timeout')) $($p.Timeout)"
# The multi-line one. If this ever becomes single-line the backup format below
# stops being exercised and the round trip proves much less than it looks.
Check 'InitString is genuinely multi-line' ($p.InitString -match "`r`n") `
  ("got: [" + ($p.InitString -replace "`r`n",'\r\n') + "]")

# ---- case 3: --off backs up, then deletes ----
Write-Host ''
Write-Host 'CASE 3: --off writes a restorable backup and removes the entry' -ForegroundColor Cyan
$before = @{}
foreach ($n in $k.Property) { $before[$n] = $p.$n }
$r3 = Run-Switch @('--delphi','--off','--backup-dir',$WorkDir,'--reg-root',$RegRoot)
Check '--off succeeded (exit 0)' ($r3.Code -eq 0) "exit=$($r3.Code)"
Check 'the entry is gone' (-not (Test-Path $entry))
$bk = @(Get-ChildItem "$WorkDir\*.reg" | Sort-Object LastWriteTime -Descending)
Check 'a .reg backup was written' ($bk.Count -ge 1) "found $($bk.Count)"
Check 'the backup path was printed' ($r3.Out -match '\.reg') $($r3.Out.Trim())

if ($bk.Count -ge 1) {
  # regedit's "Version 5.00" format is UTF-16LE; an ANSI file imports as garbage.
  $b = [System.IO.File]::ReadAllBytes($bk[0].FullName)
  Check 'backup is UTF-16LE with BOM' (($b[0] -eq 0xFF) -and ($b[1] -eq 0xFE)) `
    ("first bytes: {0:X2} {1:X2}" -f $b[0], $b[1])

  # ---- case 4: THE ROUND TRIP ----
  Write-Host ''
  Write-Host 'CASE 4: reg import restores every value exactly' -ForegroundColor Cyan
  $null = reg import $bk[0].FullName 2>&1
  Check 'reg import succeeded' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  Check 'the entry is back' (Test-Path $entry)
  if (Test-Path $entry) {
    $k2 = Get-Item $entry
    $p2 = Get-ItemProperty $entry
    Check 'same set of values' `
      (((($k2.Property | Sort-Object) -join ',')) -eq (($before.Keys | Sort-Object) -join ',')) `
      "got: $(($k2.Property | Sort-Object) -join ',')"
    foreach ($n in ($before.Keys | Sort-Object)) {
      Check "value restored exactly: $n" ($p2.$n -eq $before[$n]) `
        ("expected [" + ($before[$n] -replace "`r`n",'\r\n') + "] got [" + ($p2.$n -replace "`r`n",'\r\n') + "]")
    }
    Check 'Timeout is still a DWORD' ($k2.GetValueKind('Timeout') -eq 'DWord') `
      "got: $($k2.GetValueKind('Timeout'))"
    # Stated separately because it is the assertion the hex(1) encoding exists
    # for: a "key"="value" backup would have restored this with its newlines
    # eaten, and every other check above would still be green.
    Check 'multi-line InitString survived the round trip' ($p2.InitString -match "`r`n") `
      ("got: [" + ($p2.InitString -replace "`r`n",'\r\n') + "]")
  }
}

# ---- case 5: POSITIVE CONTROL ----
Write-Host ''
Write-Host 'CASE 5: POSITIVE CONTROL -- --off on an absent entry does nothing' -ForegroundColor Cyan
$null = Run-Switch @('--delphi','--off','--backup-dir',$WorkDir,'--reg-root',$RegRoot)
$countBefore = @(Get-ChildItem "$WorkDir\*.reg").Count
$r5 = Run-Switch @('--delphi','--off','--backup-dir',$WorkDir,'--reg-root',$RegRoot)
Check '--off on nothing reports already (exit 1)' ($r5.Code -eq 1) "exit=$($r5.Code)"
$countAfter = @(Get-ChildItem "$WorkDir\*.reg").Count
Check 'no spurious backup file written' ($countAfter -eq $countBefore) `
  "before=$countBefore after=$countAfter"

# ---- case 6: --on refuses a missing executable ----
# A registered entry pointing at nothing is NOT inert: the IDE launches it and
# retries forever ("LSP server is not responding. Sending restart."), observed
# 2026-08-18 with a throwaway entry.
Write-Host ''
Write-Host 'CASE 6: --on refuses to register a file that does not exist' -ForegroundColor Cyan
$r6 = Run-Switch @('--delphi','--on','--exe',"$WorkDir\no-such-server.exe",'--reg-root',$RegRoot)
Check '--on rejected the missing exe (exit 3)' ($r6.Code -eq 3) "exit=$($r6.Code)"
Check 'no entry was created' (-not (Test-Path $entry))

# ---- case 7: --status never mutates ----
Write-Host ''
Write-Host 'CASE 7: --status is read-only' -ForegroundColor Cyan
$existedBefore = Test-Path $entry
$r7 = Run-Switch @('--delphi','--status','--reg-root',$RegRoot)
Check '--status exits 0' ($r7.Code -eq 0) "exit=$($r7.Code)"
Check '--status changed nothing' ((Test-Path $entry) -eq $existedBefore)

# ---- the live key must be untouched throughout ----
Write-Host ''
Write-Host 'SAFETY: the real BDS key was never used' -ForegroundColor Cyan
Check 'no drag-lint entry under the LIVE BDS key' `
  (-not (Test-Path 'HKCU:\Software\Embarcadero\BDS\37.0\LSP\UserDefined\drag-lint')) `
  'the guard must never register against the real IDE config'

Clean-Scratch
Check 'scratch registry key cleaned up' (-not (Test-Path 'HKCU:\Software\DragLintSwitchTest'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
