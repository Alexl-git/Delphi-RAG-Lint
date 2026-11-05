<#
  run_dpr_messagebox_gate_guard.ps1 -- GUILOCK (dpr:313): every Application.MessageBox in ConvRulesEditor.dpr
  runs inside RunNativeDialog. MessageBox runs a native loop that never calls Application.OnMessage, so a
  command posted under it is refused only if NativeDialogUp is set (NativeLoopVerdict, dlggap).
  Positive control: the pre-fix text of the dpr (a bare MessageBox) must FAIL the same check.
#>
param([string]$Dpr = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dpr = if ($Dpr) { $Dpr } else { Join-Path $root 'src\tools\convrules-editor\ConvRulesEditor.dpr' }
function Bare([string]$text) {
  # lines holding Application.MessageBox with no RunNativeDialog within the 4 lines above
  $lines = $text -split "`r?`n"; $bad = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Application\.MessageBox\(') {
      $lo = [Math]::Max(0, $i - 4)
      if (-not (($lines[$lo..$i]) -match 'RunNativeDialog')) { $bad += ($i + 1) }
    }
  }
  return ,$bad
}
$fail = 0
$real = Get-Content -LiteralPath $dpr -Raw
$n = ([regex]::Matches($real, 'Application\.MessageBox\(')).Count
if ($n -lt 1) { Write-Output "FAIL dpr.has.messagebox (found ${n}: the check would be vacuous)"; $fail++ } else { Write-Output "PASS dpr.has.messagebox ($n)" }
$b = Bare $real
if ($b.Count -eq 0) { Write-Output 'PASS dpr.messagebox.gated' } else { Write-Output "FAIL dpr.messagebox.gated: bare at line(s) $($b -join ',')"; $fail++ }
$old = "    on E: Exception do`r`n      Application.MessageBox(PChar('x'), 'ConvRulesEditor', 0);"
if ((Bare $old).Count -eq 1) { Write-Output 'PASS control.old.code.fails' } else { Write-Output 'FAIL control.old.code.fails (the check cannot fail)'; $fail++ }
if ($fail) { Write-Output "FAILED $fail"; exit 1 }
Write-Output 'OK'