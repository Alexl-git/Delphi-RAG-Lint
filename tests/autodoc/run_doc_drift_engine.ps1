<#
  run_doc_drift_engine.ps1 -- TDocDrift engine (ADF Task 6).

  Exercises the deterministic doc-vs-code drift engine through the
  `doc-drift --qname X --json` diagnostic verb. Uses fixtures\docdrift\drift.pas,
  whose decls each carry a STALE doc-comment on purpose:

    * function F(New: Integer): string;
        doc has <param name="Old"> (renamed away)  -> ddParamRenamedOrRemoved (report-only)
        doc has NO <param> for the real sig param New -> ddParamMissing (report-only --
          v(ADP3 T3): was FIXABLE before this task; MergeComment's omit-when-empty
          rule now forbids ever adding a marker-only <param> stub, so the old fix
          action for this signal no longer exists -- see DRagLint.Doc.Drift's own
          MakeFinding call-site comment)
        doc has a <returns> and F IS a function       -> OK, no returns drift
    * procedure P;
        doc has a spurious <returns> but P is a proc  -> ddReturnsButNoValue (report-only)
    * function Lookup(Key: Integer): string;
        doc has <exception cref="EFoo"> never raised  -> ddExceptionNotRaised (report-only)
        (Key IS documented; function HAS a <returns>? no -> also a ddValueButNoReturns FIXABLE)

  Asserts the findings array per symbol contains the expected kinds AND that each
  finding's `fixable` flag matches the rules (ddValueButNoReturns / ddFactsBlockStale
  = True; all others False, including ddParamMissing as of v(ADP3 T3)).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdrift\drift.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docdrift'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'drift.pas'
$db     = Join-Path $scratch 'docdrift.sqlite'
Copy-Item $fixture $target -Force

# Parse the JSON-per-line output of `doc-drift --qname X --json` into an array of
# PSCustomObjects (each with .kind, .detail, .fixable, .line).
function Get-Drift($qname) {
  $out = & $exePath doc-drift --qname $qname --db $db --json 2>$null
  $rows = @()
  foreach ($ln in $out) {
    $t = $ln.Trim()
    if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) }
  }
  return ,$rows
}
# True when the findings array has an entry of kind $k whose fixable == $fx.
function HasKind($rows,$k,$fx) {
  foreach ($r in $rows) { if ($r.kind -eq $k -and [bool]$r.fixable -eq $fx) { return $true } }
  return $false
}
# True when NO entry of kind $k is present (regardless of fixable).
function LacksKind($rows,$k) {
  foreach ($r in $rows) { if ($r.kind -eq $k) { return $false } }
  return $true
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- F: renamed param (report-only) + missing param (fixable), returns OK ---
  $f = Get-Drift 'drift.F'
  Check 'F: emits at least one finding' ($f.Count -ge 1)
  Check 'F: ddParamRenamedOrRemoved present, NOT fixable' (HasKind $f 'ddParamRenamedOrRemoved' $false)
  Check 'v(ADP3 T3): F: ddParamMissing present, report-only (no longer FIXABLE)' (HasKind $f 'ddParamMissing' $false)
  Check 'F: no ddReturnsButNoValue (function has a real <returns>)' (LacksKind $f 'ddReturnsButNoValue')
  Check 'F: no ddValueButNoReturns (function HAS a <returns>)' (LacksKind $f 'ddValueButNoReturns')

  # --- P: spurious <returns> on a procedure (report-only) ---
  $p = Get-Drift 'drift.P'
  Check 'P: ddReturnsButNoValue present, NOT fixable' (HasKind $p 'ddReturnsButNoValue' $false)
  Check 'P: no ddValueButNoReturns' (LacksKind $p 'ddValueButNoReturns')

  # --- Lookup: documents EFoo it never raises (report-only) + no <returns> though it is a fn ---
  $l = Get-Drift 'drift.Lookup'
  Check 'Lookup: ddExceptionNotRaised present, NOT fixable' (HasKind $l 'ddExceptionNotRaised' $false)
  Check 'Lookup: ddValueButNoReturns present, FIXABLE (fn, no <returns>)' (HasKind $l 'ddValueButNoReturns' $true)
  Check 'Lookup: no ddParamMissing (Key IS documented)' (LacksKind $l 'ddParamMissing')
  Check 'Lookup: no ddParamRenamedOrRemoved (Key matches)' (LacksKind $l 'ddParamRenamedOrRemoved')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
