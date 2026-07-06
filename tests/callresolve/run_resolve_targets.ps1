<#
  run_resolve_targets.ps1 -- TDD harness for D5 Task 6: the ResolveCallTargets
  whole-DB pass populates call_edges, and the receiver-typing resolver produces
  the RIGHT per-site resolutions.

  Fixture receivers.pas (TAlpha.Run / TBeta.Run / TCaller.Run, with TCaller
  dispatching Run via a field, a param, a typed local, and Self/bare) is the
  first real end-to-end proof the resolver works. After indexing it, the new
  `dump-call-edges --db` diagnostic verb prints one line per call_edge as
  `ref_id|target_qname|confidence`. We assert:
    - call_edges is populated (at least the 5 dispatch sites resolve),
    - FAlpha.Run field-receiver -> receivers.TAlpha.Run    | certain
    - AAlpha.Run param-receiver -> receivers.TAlpha.Run    | certain
    - B.Run typed-local receiver -> receivers.TBeta.Run     | certain
    - Self.Run / bare Run       -> receivers.TCaller.Run    | certain

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\receivers.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_resolvetargets'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'receivers.pas'
$db      = Join-Path $scratch 'receivers.sqlite'
Copy-Item $fixture $target -Force

# True when the dump has at least one line resolving to $qname with $conf.
function HasEdge([string[]]$lines, [string]$qname, [string]$conf) {
  foreach ($l in $lines) {
    $p = $l -split '\|'
    if ($p.Count -ge 3 -and $p[1] -eq $qname -and $p[2] -eq $conf) { return $true }
  }
  return $false
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $out   = & $exePath dump-call-edges --db $db 2>$null | Out-String
  # A real edge line is exactly `ref_id|target_qname|confidence`: an integer
  # ref id, a dotted qname, and a certain|ambiguous confidence. This shape
  # rejects usage/error text that merely contains a '|'.
  $lines = @($out -split "`r?`n" | Where-Object { $_ -match '^\d+\|[A-Za-z_][\w.]*\|(certain|ambiguous)$' })

  Check 'call_edges populated (>= 5 edges)'                 ($lines.Count -ge 5)
  Check 'FAlpha.Run field  -> receivers.TAlpha.Run certain'  (HasEdge $lines 'receivers.TAlpha.Run'  'certain')
  Check 'AAlpha.Run param  -> receivers.TAlpha.Run certain'  (HasEdge $lines 'receivers.TAlpha.Run'  'certain')
  Check 'B.Run local       -> receivers.TBeta.Run  certain'  (HasEdge $lines 'receivers.TBeta.Run'   'certain')
  Check 'Self.Run / bare   -> receivers.TCaller.Run certain' (HasEdge $lines 'receivers.TCaller.Run' 'certain')

  # TAlpha.Run must resolve from BOTH the field site and the param site (two
  # distinct certain edges to the same target -- not one shared row).
  $alphaCount = @($lines | Where-Object { ($_ -split '\|')[1] -eq 'receivers.TAlpha.Run' -and ($_ -split '\|')[2] -eq 'certain' }).Count
  Check 'two certain edges to receivers.TAlpha.Run'          ($alphaCount -ge 2)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
