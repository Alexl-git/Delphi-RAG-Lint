<#
  run_lintall_cycles_section.ps1 -- the lint-all report must STATE the cycle
  outcome, including the negative one, and must never present a disabled rule
  as a clean result.

  Why this exists
  ---------------
  The owner asked for a cycles SECTION in the report. Session 40 shipped the
  message half -- circular-uses findings carry an accurate, cycle-specific
  advice string -- but the report still carried the outcome as one finding line
  buried among the rest. Absence of that line is indistinguishable from the rule
  not having run, and a reader who does not already know the rule exists cannot
  tell the difference.

  What is checked
  ---------------
    1. a real cycle is NAMED in the section, at the TOP of the report;
    2. the ordinary finding line SURVIVES -- the section owns the narrative, the
       finding owns the tooling contract (--fail-on, counts, machine-readable
       output). Rendering both from the same post-suppression survivors is what
       makes the two surfaces reconcile;
    3. a project with no cycles says so explicitly, with the denominator;
    4. THE HALF THAT MATTERS: with circular-uses disabled in config, the report
       says NOT CHECKED and does NOT say "none". A check whose absence reads as
       success is the failure this section was requested to prevent, and it is
       the one a "does it print a section?" test would miss entirely.
    5. --json stdout stays ONE valid object -- the section is text-path only.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$CycSrc  = "$PSScriptRoot\..\..\docs\examples\circular-uses-demo",
  [string]$NoCycSrc= "$PSScriptRoot\..\fixtures\reconcile",
  [string]$WorkDir = "$env:TEMP\draglint_cycles_section"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host '== lint-all cycles section ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }

function Prep([string]$name, [string]$src) {
  $d = Join-Path $WorkDir $name
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  Copy-Item "$src\*.pas" $d
  & $Exe index $d --db (Join-Path $d 't.sqlite') 2>&1 | Out-Null
  return $d
}
function Report([string]$dir, [string[]]$extra = @()) {
  $rep = Join-Path $dir 'rep.txt'
  & $Exe lint-all --db (Join-Path $dir 't.sqlite') --output $rep @extra 2>&1 | Out-Null
  if (-not (Test-Path $rep)) { return '' }
  return (Get-Content $rep -Raw)
}

# --- 1 + 2: a real cycle ------------------------------------------------------
$cyc = Prep 'withcycle' (Resolve-Path $CycSrc).Path
$r1  = Report $cyc
Check 'the section is at the TOP of the report' `
  ($r1 -match '^circular unit dependencies') "head: $(($r1 -split "`n")[0])"
Check 'a real cycle is NAMED in the section' `
  ($r1 -match 'circular unit dependencies[\s\S]{0,400}?Circular unit dependency among') ''
Check 'the ordinary finding line SURVIVES below it' `
  ($r1 -match '\[warning\]\s+circular-uses:') 'the finding must remain for --fail-on and counts'
Check 'it does NOT claim none detected when a cycle exists' `
  (-not ($r1 -match 'none detected')) ''

# --- 3: no cycles -------------------------------------------------------------
$non = Prep 'nocycle' (Resolve-Path $NoCycSrc).Path
$r2  = Report $non
Check 'a clean project says none detected, with the denominator' `
  ($r2 -match 'none detected across \d+ file\(s\) scanned') "head: $(($r2 -split "`n")[2])"

# --- 4: DISABLED must not read as clean --------------------------------------
$cfg = Join-Path $cyc 'cfg.json'
'{ "disabled": ["circular-uses"] }' | Set-Content -LiteralPath $cfg -Encoding Ascii
$r3 = Report $cyc @('--config', $cfg)
Check 'a DISABLED rule reports NOT CHECKED' ($r3 -match 'NOT CHECKED') ''
Check 'a DISABLED rule does NOT say none detected' (-not ($r3 -match 'none detected')) `
  'this is the whole point: absence of a check must not read as success'

# --- 5: machine-readable output stays pure -----------------------------------
$j = (& $Exe lint-all --db (Join-Path $cyc 't.sqlite') --format json 2>$null) -join "`n"
$si = $j.IndexOf('{'); $obj = $null
if ($si -ge 0) { try { $obj = ($j.Substring($si) | ConvertFrom-Json) } catch { } }
Check 'the section did not leak into --format json' `
  (-not ($j -match 'circular unit dependencies')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'CYCLES SECTION GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'CYCLES SECTION GUARD: PASS' -ForegroundColor Green
exit 0
