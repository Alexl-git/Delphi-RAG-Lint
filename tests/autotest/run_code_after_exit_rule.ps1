<#
  run_code_after_exit_rule.ps1 -- `code-after-exit` reports a statement that
  follows an UNCONDITIONAL Exit/raise/Break/Continue/Halt in the same block, and
  does not report one that follows a CONDITIONAL exit.

  Why this exists: until 2026-09-27 the rule had no runner and no fixture
  anywhere under tests\ (searched for the id). TAstChecker.CheckCodeAfterExit's
  NodeStr then became a delegate of the shared SrcText helper (behaviour-neutral,
  done to stop a duplicate-code finding), and there was nothing to prove "neutral".
  Each "MUST fire" has a "must NOT fire" twin, so a rule that reports nothing, or
  everything, fails here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-code-after-exit-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$src = @(
  'unit AfterExit;'
  ''
  'interface'
  ''
  'procedure Dead;'
  'procedure Live(const AFlag: Boolean);'
  ''
  'implementation'
  ''
  'procedure Dead;'
  'begin'
  '  Exit;'
  '  Writeln(''dead'');'
  'end;'
  ''
  'procedure Live(const AFlag: Boolean);'
  'begin'
  '  if AFlag then'
  '    Exit;'
  '  Writeln(''live'');'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'AfterExit.pas'
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)
$lines = [IO.File]::ReadAllLines($pas)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnDead = LineOf "Writeln('dead');"
$lnLive = LineOf "Writeln('live');"
Check 'fixture statements located' (($lnDead -gt 0) -and ($lnLive -gt 0)) "dead=$lnDead live=$lnLive"

$fired = @()
foreach ($line in (& $Exe lint $pas 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+code-after-exit:') { $fired += [int]$Matches[1] }
}
$fired = @($fired | Sort-Object -Unique)
Write-Host ("  fired on lines: [{0}]" -f ($fired -join ', ')) -ForegroundColor DarkGray
Check "statement after an unconditional Exit (line $lnDead) MUST fire" ($fired -contains $lnDead)
Check "statement after a CONDITIONAL Exit (line $lnLive) must NOT fire" (-not ($fired -contains $lnLive))

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
