<#
  run_v152_HBHOVER.ps1 -- lane HBHOVER (1.52, ruling HB2 second half): hover over a unit variable /
  class var / field shows which routines / events set it -- the check-init writer list, budget-capped.

  Fixtures (indexed here into private DBs): tests\fixtures\happens-before\solve-callchain (GData: SET,
  writers; GData under a 1-routine budget: exhausted) and solve-unknown (GExempt: no writer -> NEVER-SET;
  GUnk: UNKNOWN-CALLEE, HBTAIL's verdict).

  Asserts:
    A  hover --format json of scData.GData has model.set_by; its writers equal `check-init --json`
       writers byte for byte (compact JSON), its verdict equals check-init's; state = listed.
       Positive control: check-init lists at least one writer.
    B  suData.GExempt: set_by.state = never-set, writers = [], verdict NEVER-SET; md says "never set".
       Control: check-init lists 0 writers for it.
    C  DRAGLINT_HOVER_SETBY_MAX_ROUTINES=1 on scData.GData: state = budget-exceeded, the md says
       "budget exceeded"; writers still equal check-init's (the events are complete, only the verdict
       is not). Control: A (no override) is NOT budget-exceeded.
    C5 (INT11, HBFIX H3 in the hover) DRAGLINT_HOVER_SETBY_MAX_SECONDS=0.000001 on scData.GData: the
       hover's wall-clock cap (default HOVER_SETBY_MAX_SECONDS = 5 s) stops the solve -> state
       budget-exceeded, budget.timed_out true. Control: A (no override) is not timed out.
    D  suData.GUnk: verdict UNKNOWN-CALLEE in json and in the md line.
    E  a routine (scWork.Level1) has NO set_by key (control: A has one).
    F  md of scData.GData lists the writer routine on a "Set by:" line.
    G  hover --format plain is unchanged by the lane: no "Set by" text (plain never paid for facts).

  Parameters: -Exe (default src\cli\Win64\Debug\drag-lint.exe), -Repo, -WorkDir.
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-hbhover-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
Write-Host '== v152 HBHOVER: hover set-by section ==' -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$dbs = @{}
foreach ($fx in 'solve-callchain', 'solve-unknown') {
  $src = Join-Path $WorkDir $fx
  Copy-Item -Recurse -Force (Join-Path $FixRoot $fx) $src
  $db = Join-Path $WorkDir "$fx.sqlite"
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } }
  if (-not (Test-Path -LiteralPath $db)) { Write-Host "FATAL: index failed for $fx" -ForegroundColor Red; exit 2 }
  $dbs[$fx] = $db
}

function HoverJson($qn, $db) {
  $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe hover --qname $qn --db $db --format json 2>$null }) -join "`n"
  try { return ($raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch { Write-Host "    raw hover: $raw"; return $null }
}
function HoverText($qn, $db, $fmt) { return ((& { $ErrorActionPreference = 'Continue'; & $Exe hover --qname $qn --db $db --format $fmt 2>$null }) -join "`n") }
function CheckInitJson($qn, $db) {
  $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe check-init $qn --db $db --json 2>$null }) -join "`n"
  try { return ($raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch { Write-Host "    raw check-init: $raw"; return $null }
}
function Has($obj, $name) { return ($null -ne $obj) -and ($obj.PSObject.Properties.Name -contains $name) }
function WritersText($arr) { if ($null -eq $arr -or @($arr).Count -eq 0) { return '[]' }; return (ConvertTo-Json -InputObject @($arr) -Compress -Depth 8) }

$cc = $dbs['solve-callchain']
$su = $dbs['solve-unknown']

# ---- A: set_by of a global equals check-init writers
$h = HoverJson 'scData.GData' $cc
$ci = CheckInitJson 'scData.GData' $cc
Write-Host ('    raw set_by (A): ' + $(if (Has $h 'set_by') { ConvertTo-Json -InputObject $h.set_by -Compress -Depth 8 } else { '<absent>' }))
Check 'A0 control: check-init lists >= 1 writer of scData.GData' (($null -ne $ci) -and (@($ci.writers).Count -ge 1)) ("count=" + @($ci.writers).Count)
Check 'A1 hover json has set_by' (Has $h 'set_by')
if (Has $h 'set_by') {
  Check 'A2 set_by.writers == check-init writers' ((WritersText $h.set_by.writers) -ceq (WritersText $ci.writers)) ''
  Check 'A3 set_by.verdict == check-init verdict' ($h.set_by.verdict -ceq $ci.verdict) ("$($h.set_by.verdict) vs $($ci.verdict)")
  Check 'A4 set_by.state = listed' ($h.set_by.state -ceq 'listed') $h.set_by.state
}

# ---- B: no writer -> never set
$hb = HoverJson 'suData.GExempt' $su
$cib = CheckInitJson 'suData.GExempt' $su
Check 'B0 control: check-init lists 0 writers of suData.GExempt' (($null -ne $cib) -and (@($cib.writers).Count -eq 0)) ''
Check 'B1 never-set state' ((Has $hb 'set_by') -and ($hb.set_by.state -ceq 'never-set')) $(if (Has $hb 'set_by') { $hb.set_by.state })
Check 'B2 never-set writers = []' ((Has $hb 'set_by') -and (@($hb.set_by.writers).Count -eq 0)) ''
Check 'B3 never-set verdict NEVER-SET' ((Has $hb 'set_by') -and ($hb.set_by.verdict -ceq 'NEVER-SET')) ''
$mdb = HoverText 'suData.GExempt' $su 'md'
Check 'B4 md says never set' ($mdb -match 'Set by: never set') ''

# ---- C: budget exceeded
$env:DRAGLINT_HOVER_SETBY_MAX_ROUTINES = '1'
try {
  $hc = HoverJson 'scData.GData' $cc
  $mdc = HoverText 'scData.GData' $cc 'md'
} finally { $env:DRAGLINT_HOVER_SETBY_MAX_ROUTINES = $null }
Check 'C1 budget-exceeded state' ((Has $hc 'set_by') -and ($hc.set_by.state -ceq 'budget-exceeded')) $(if (Has $hc 'set_by') { $hc.set_by.state })
Check 'C2 md says budget exceeded' ($mdc -match 'budget exceeded') ''
Check 'C3 writers still equal check-init' ((Has $hc 'set_by') -and ((WritersText $hc.set_by.writers) -ceq (WritersText $ci.writers))) ''
Check 'C4 control: no override is not budget-exceeded' ((Has $h 'set_by') -and ($h.set_by.state -cne 'budget-exceeded')) ''
$env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = '0.000001'
try { $hs = HoverJson 'scData.GData' $cc } finally { $env:DRAGLINT_HOVER_SETBY_MAX_SECONDS = $null }
Check 'C5 max-seconds cap: budget-exceeded' ((Has $hs 'set_by') -and ($hs.set_by.state -ceq 'budget-exceeded')) $(if (Has $hs 'set_by') { $hs.set_by.state })
Check 'C5 max-seconds cap: budget.timed_out' ((Has $hs 'set_by') -and ($hs.set_by.budget.timed_out -eq $true)) $(if (Has $hs 'set_by') { $hs.set_by.budget | ConvertTo-Json -Compress })
Check 'C5 control: no override is not timed out' ((Has $h 'set_by') -and ($h.set_by.budget.timed_out -ne $true)) ''

# ---- D: UNKNOWN-CALLEE
$hd = HoverJson 'suData.GUnk' $su
$mdd = HoverText 'suData.GUnk' $su 'md'
Check 'D1 json verdict UNKNOWN-CALLEE' ((Has $hd 'set_by') -and ($hd.set_by.verdict -ceq 'UNKNOWN-CALLEE')) $(if (Has $hd 'set_by') { $hd.set_by.verdict })
Check 'D2 md names UNKNOWN-CALLEE' ($mdd -match 'Init: UNKNOWN-CALLEE') ''

# ---- E: a routine has no set_by
$he = HoverJson 'scWork.Level1' $cc
Check 'E1 routine hover parsed' ($null -ne $he) ''
Check 'E2 routine has no set_by key' (($null -ne $he) -and -not (Has $he 'set_by')) ''

# ---- F: md lists the writer routine
$mda = HoverText 'scData.GData' $cc 'md'
$firstRoutine = if (($null -ne $ci) -and @($ci.writers).Count -ge 1) { @($ci.writers)[0].routine } else { '<none>' }
Check 'F1 md has a Set by: line naming the first writer' ($mda -match ('Set by: ' + [regex]::Escape($firstRoutine))) $firstRoutine

# ---- G: plain unchanged
$pl = HoverText 'scData.GData' $cc 'plain'
Check 'G1 plain has no Set by' (($pl -ne '') -and ($pl -notmatch 'Set by')) ''

if (-not $env:HB_KEEP_WORK) { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ("v152 HBHOVER: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'V152 HBHOVER: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V152 HBHOVER: PASS' -ForegroundColor Green
exit 0
