# run_plugin_bounded_waits.ps1 -- source-scan guard: no unbounded wait in the
# IDE plugin's process-running units (ProcRun, Editor). Pattern: an INFINITE
# argument to WaitForSingleObject/WaitForMultipleObjects, or a bare
# TThread.WaitFor (no timeout). Comments are stripped before the scan.
# Positive control: a planted unbounded wait MUST be detected.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$units = 'DragLint.Plugin.ProcRun.pas', 'DragLint.Plugin.Editor.pas'
$pat = 'Wait(ForSingleObject|ForMultipleObjects)\s*\([^;]*\bINFINITE\s*\)|\.WaitFor\s*;'

function Get-Unbounded([string[]]$pLines) {
  $hits = @(); $inBrace = $false
  for ($i = 0; $i -lt $pLines.Count; $i++) {
    $l = $pLines[$i]
    if ($inBrace) { if ($l -match '\}') { $inBrace = $false; $l = $l -replace '^[^}]*\}', '' } else { continue } }
    $l = $l -replace '\{[^}]*\}', '' -replace '//.*$', '' -replace '\(\*.*?\*\)', ''
    if ($l -match '\{') { $inBrace = $true; $l = $l -replace '\{.*$', '' }
    if ($l -match $pat) { $hits += ($i + 1) }
  }
  return $hits
}

$fail = 0
$ctl = Get-Unbounded @('  WaitForSingleObject(PI.hProcess, INFINITE);', '  T.WaitFor;')
if ($ctl.Count -ne 2) { Write-Host "FAIL positive control: scan found $($ctl.Count) of 2 planted waits"; $fail++ } else { Write-Host 'PASS positive control' }
$neg = Get-Unbounded @('{ INFINITE is fine }', '  // WaitForSingleObject(H, INFINITE);', '  WaitForSingleObject(H, 2000);')
if ($neg.Count -ne 0) { Write-Host 'FAIL negative control: comment/bounded flagged'; $fail++ } else { Write-Host 'PASS negative control' }
foreach ($u in $units) {
  $f = Join-Path $root "src\delphi-plugin\$u"
  $h = Get-Unbounded (Get-Content $f)
  if ($h.Count) { Write-Host "FAIL $u unbounded wait at line(s) $($h -join ',')"; $fail++ } else { Write-Host "PASS $u" }
}
if ($fail) { exit 1 } else { exit 0 }