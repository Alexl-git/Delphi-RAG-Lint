<#
  run_flowchecker_profile_breakdown.ps1 --
  docs\INBOX-flowchecker-is-half-of-lint-all.md

  FlowChecker.Check is HALF of lint-all (measured 2026-08-28 on this repo's own
  110 files: 114.78 s of 209.53 s, 1043 ms/file, 5.7x the next item) and until
  now it was ONE number with nothing inside it. That note is a record of four
  hypotheses about it that measured dead, one at literally 0.00 s -- so it
  forbids optimising before a sub-breakdown exists. This guards the breakdown.

  WHY THE SUM BOUND IS THE LOAD-BEARING ASSERTION, and not decoration: getting
  this instrumentation right took THREE attempts, and the first two both LOOKED
  fine while pointing at the wrong phase.

    1. windows only          definite-assignment 50.1%, interface derefs 25.9%
    2. + derefs timed exactly definite-assignment 71.3%, derefs 5.8%
                              -- but sum 121.12 s against a 114.38 s slot,
                                 because derefs was counted in its own bucket
                                 AND inside the enclosing window
    3. + window exclusion     definite-assignment 69.7%, derefs 6.1%, sum 114.52
                                 against 114.78 -- a partition at last

  Attempt 1 over-attributed `interface derefs` by 4.3x, which is precisely how a
  profile sends the next optimisation at the wrong target. A2 below is what
  fails if either mistake comes back.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_flowprofile"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# Small but flow-rich: every phase must get work, or a phase could read 0.00 s
# for the boring reason that nothing exercised it.
Write-Ascii (Join-Path $src 'uFlow.pas') @'
unit uFlow;

interface

type
  TThing = class
  public
    procedure Go;
  end;

procedure Drive(AFlag: Boolean);

implementation

procedure TThing.Go;
begin
end;

procedure Drive(AFlag: Boolean);
var
  T: TThing;
  I: Integer;
  S: string;
begin
  T := TThing.Create;
  try
    for I := 0 to 9 do
      if AFlag then
      begin
        S := IntToStr(I);
        if S <> '' then T.Go;
      end
      else
        S := '';
    if S = '' then Exit;
    T.Go;
  finally
    T.Free;
  end;
end;

end.
'@

$db = Join-Path $WorkDir 'flow.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function RunLint([bool]$Profile) {
  Remove-Item Env:\DRAGLINT_PROFILE -ErrorAction SilentlyContinue
  if ($Profile) { $env:DRAGLINT_PROFILE = '1' }
  try   { return (& $exePath lint-all --db $db --rules-dir $rules 2>&1 | Out-String) }
  finally { Remove-Item Env:\DRAGLINT_PROFILE -ErrorAction SilentlyContinue }
}

Push-Location C:\TEMP
try {
  $withP = RunLint $true
  $noP   = RunLint $false

  # ---- A1: the sub-lines exist and name the phases.
  Check 'A1 the breakdown header is printed under DRAGLINT_PROFILE' `
        ($withP -match 'FlowChecker\.Check breakdown') 'no breakdown line'
  # Session 47 split the two big windows into SOLVE and the work after it. The
  # names are matched in full, not as prefixes: 'definite-assignment' alone is a
  # substring of both halves, so the old list would keep passing even if the
  # split silently collapsed back into one bucket.
  foreach ($ph in @('CFG build','var table','definite-assignment solve','definite-assignment replay',
                    'interface derefs','liveness','escape solve','escape rest')) {
    Check "A1 phase line present: $ph" ($withP -match [regex]::Escape($ph)) 'phase missing from the profile'
  }

  # ---- A2: THE PARTITION BOUND. An accumulator that never accumulates, that
  #      double-counts a nested phase, or that charges a window twice all show
  #      up here and nowhere else. Both historic mistakes fail this.
  $slot = $null; $sum = $null
  if ($withP -match 'FlowChecker\.Check\s+([0-9.]+) s')           { $slot = [double]$Matches[1] }
  if ($withP -match 'FlowChecker\.Check breakdown\s+([0-9.]+) s') { $sum  = [double]$Matches[1] }
  Check 'A2 both the slot and the breakdown total were parsed' `
        (($null -ne $slot) -and ($null -ne $sum)) "slot=$slot sum=$sum"
  if (($null -ne $slot) -and ($null -ne $sum) -and ($slot -gt 0)) {
    $ratio = $sum / $slot
    Check 'A2 the breakdown SUMS to the slot it decomposes (0.75..1.05)' `
          (($ratio -ge 0.75) -and ($ratio -le 1.05)) `
          "slot=$slot s, breakdown sum=$sum s, ratio=$([math]::Round($ratio,3)) -- over 1.05 means a phase is counted twice; under 0.75 means the phases no longer cover the routine"
  }

  # ---- A3: POSITIVE CONTROL on the instrumentation being inert. A guard that
  #      only checked the profile lines exist would pass a broken profiler that
  #      changed what the linter reported.
  function FindingsOnly([string]$T) {
    ,@($T -split "`r?`n" | Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' } | Sort-Object)
  }
  $fp = FindingsOnly $withP
  $fn = FindingsOnly $noP
  Check 'A3 CONTROL findings are IDENTICAL with and without the profiler' `
        (($fp -join "`n") -eq ($fn -join "`n")) `
        "profiled=$($fp.Count) plain=$($fn.Count)"
  Check 'A3 CONTROL the plain run prints NO breakdown' `
        (-not ($noP -match 'FlowChecker\.Check breakdown')) 'profile output leaked into a non-profiled run'

  Check 'VACUITY the fixture produced findings at all' ($fn.Count -gt 0) `
        'no findings -- the fixture exercises nothing and A3 would be trivially true'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
