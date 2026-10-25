<#
  run_parse_implementation_line.ps1 -- N-06 T2: TParseResult.ImplementationLine.

  The Delphi parser reports the 1-based line of a unit's `implementation`
  keyword (0 for a program / package / a unit without one). N-06 uses it to
  give a {$I} uses clause the host section its directive sits in. Observed
  through the internal diagnostic verb dump-parse-uses --file PATH
  (line 1: implementation_line<TAB>N; then use<TAB>section<TAB>unit<TAB>line).

  Fixture tests\fixtures\cyclefix\incuses:
    IncB.pas     -> implementation_line 10
    IncA.pas     -> implementation_line 12, its own `uses IncB` in implementation
                    at line 15 (POSITIVE CONTROL: the dump really parses)
    IncUses.dpr  -> implementation_line 0
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$fx = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path

function Dump([string]$file) {
  Push-Location C:\TEMP
  try { $o = & $Exe dump-parse-uses --file $file 2>&1 | ForEach-Object { "$_" } } finally { Pop-Location }
  return ,@($o)
}
function ImplLine($lines) {
  $l = @($lines | Where-Object { $_ -like "implementation_line`t*" })
  if ($l.Count -ne 1) { return '' }
  return ($l[0] -split "`t")[1]
}

$b = Dump "$fx\IncB.pas"
Check 'IncB.pas implementation_line = 10' ((ImplLine $b) -eq '10') ("got '" + (ImplLine $b) + "'")
$a = Dump "$fx\IncA.pas"
Check 'IncA.pas implementation_line = 12' ((ImplLine $a) -eq '12') ("got '" + (ImplLine $a) + "'")
Check 'positive control: IncA.pas own uses IncB, implementation, line 15' (@($a | Where-Object { $_ -eq "use`timplementation`tIncB`t15" }).Count -eq 1) ($a -join ' | ')
$d = Dump "$fx\IncUses.dpr"
Check 'IncUses.dpr implementation_line = 0' ((ImplLine $d) -eq '0') ("got '" + (ImplLine $d) + "'")

if ($script:Failed) { Write-Host 'run_parse_implementation_line: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_parse_implementation_line: PASS' -ForegroundColor Green; exit 0